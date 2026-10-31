//
//  ELinkSmartConnection.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import Foundation
import Bluetooth
import GATT

/// A GATT connection to an eLinkSmart padlock.
///
/// Encrypts each command, writes it to the lock's data-in characteristic in ≤20-byte packets, and
/// collects the reply from notifications on the data-out characteristic. Commands run one at a time.
///
/// Create one with ``GATT/CentralManager/connect(to:connectTimeout:timeout:)``, call ``login(timeout:)``
/// to obtain a session token, then ``unlock(password:timeout:)``.
public actor ELinkSmartConnection<Central: CentralManager> where Central: Sendable, Central.AttributeID: Sendable {

    public typealias Peripheral = Central.Peripheral

    public typealias Characteristic = GATT.Characteristic<Central.Peripheral, Central.AttributeID>

    // MARK: - Properties

    /// Connected peripheral.
    public nonisolated let peripheral: Peripheral

    /// Notifications that arrive outside a command. Finishes when the connection closes.
    public nonisolated let events: AsyncStream<[UInt8]>

    /// Whether the connection is still open.
    public private(set) var isConnected = true

    /// The session token from the last successful ``login(timeout:)``, if any.
    public private(set) var sessionToken: UInt32?

    private let central: Central

    private let cipher: ELinkSmartCipher

    private let eventsContinuation: AsyncStream<[UInt8]>.Continuation

    private var characteristics = [BluetoothUUID: Characteristic]()

    private var notifications = [AsyncCentralNotifications<Central>]()

    private var tasks = [Task<Void, Never>]()

    private var collector: Collector?

    private var requestCount: UInt64 = 0

    private var queue: Task<Void, Never>?

    // MARK: - Initialization

    internal init(
        central: Central,
        peripheral: Peripheral,
        cipher: ELinkSmartCipher = .default
    ) {
        self.central = central
        self.peripheral = peripheral
        self.cipher = cipher
        var continuation: AsyncStream<[UInt8]>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventsContinuation = continuation
    }

    // MARK: - Methods

    /// Logs in and stores the lock's session token.
    public func login(timeout: TimeInterval = 5) async throws {
        try await enqueue {
            try await self.performLogin(timeout: timeout)
        }
    }

    /// Unlocks the padlock, logging in first if there is no session token yet.
    public func unlock(password: ELinkSmartPassword, timeout: TimeInterval = 5) async throws {
        try await enqueue {
            try await self.performUnlockFlow(password: password, timeout: timeout)
        }
    }

    /// Closes the connection.
    public func disconnect() async {
        guard isConnected else {
            return
        }
        close()
        await central.disconnect(peripheral)
    }
}

// MARK: - Setup

internal extension ELinkSmartConnection {

    func setup() async throws {
        // discover the lock service and cache its characteristics
        let services = try await central.discoverServices([.elinkSmartService], for: peripheral)
        for service in services where service.uuid == .elinkSmartService {
            let characteristics = try await central.discoverCharacteristics([], for: service)
            for characteristic in characteristics {
                self.characteristics[characteristic.uuid] = characteristic
            }
        }
        for uuid in [BluetoothUUID.elinkSmartDataIn, .elinkSmartDataOut] {
            guard characteristics[uuid] != nil else {
                throw ELinkSmartConnectionError.characteristicNotFound(uuid)
            }
        }
        guard let dataOut = characteristics[.elinkSmartDataOut] else {
            throw ELinkSmartConnectionError.characteristicNotFound(.elinkSmartDataOut)
        }
        try await subscribe(dataOut)
    }
}

// MARK: - Commands

private extension ELinkSmartConnection {

    func performLogin(timeout: TimeInterval) async throws {
        let nonce = UInt32(truncatingIfNeeded: UInt64(Date().timeIntervalSince1970))
        let response = try await exchange(ELinkSmartCommand.login(nonce: nonce).packet, timeout: timeout)
        guard response.command == .login, response.parameters.count >= 4 else {
            throw ELinkSmartConnectionError.authenticationFailed
        }
        self.sessionToken = UInt32(littleEndian: (
            response.parameters[0],
            response.parameters[1],
            response.parameters[2],
            response.parameters[3]
        ))
    }

    func performUnlockFlow(password: ELinkSmartPassword, timeout: TimeInterval) async throws {
        if sessionToken == nil {
            try await performLogin(timeout: timeout)
        }
        try await performUnlock(password: password, timeout: timeout)
    }

    func performUnlock(password: ELinkSmartPassword, timeout: TimeInterval) async throws {
        guard let token = sessionToken else {
            throw ELinkSmartConnectionError.notLoggedIn
        }
        let timestamp = UInt32(truncatingIfNeeded: UInt64(Date().timeIntervalSince1970))
        let command = ELinkSmartCommand.unlock(token: token, password: password, timestamp: timestamp)
        let response = try await exchange(command.packet, timeout: timeout)
        // the lock acknowledges by echoing the command code; a wrong password or token gets no reply
        guard response.command == command.packet.command else {
            throw ELinkSmartConnectionError.unlockFailed
        }
    }

    /// Encrypts a packet, writes it to the lock, and decrypts the reply.
    func exchange(_ packet: ELinkSmartPacket, timeout: TimeInterval) async throws -> ELinkSmartPacket {
        let characteristic = try characteristic(.elinkSmartDataIn)
        let central = self.central
        let frames = ELinkSmartFraming.write(cipher.encrypt(packet.plaintext))
        let fragments = try await collect(timeout: timeout) {
            for frame in frames {
                // DATAIN (0x2ADD) is Write Without Response on real hardware (props 0x04)
                try await central.writeValue(Central.Data(frame), for: characteristic, withResponse: false)
            }
        }
        guard let ciphertext = ELinkSmartFraming.reassemble(fragments),
              let plaintext = cipher.decrypt(ciphertext),
              let response = ELinkSmartPacket(plaintext: plaintext) else {
            throw ELinkSmartConnectionError.invalidData(.elinkSmartDataOut)
        }
        return response
    }
}

// MARK: - Private

private extension ELinkSmartConnection {

    struct Collector {

        let id: UInt64

        /// The request ends if no notification arrives by then.
        var deadline: Date

        /// Time allowed after each notification.
        let quiet: TimeInterval

        var fragments = [[UInt8]]()

        let continuation: CheckedContinuation<[[UInt8]], Error>
    }

    /// Runs operations one at a time, in order.
    func enqueue<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = queue
        let task = Task<T, Error> {
            _ = await previous?.value
            return try await operation()
        }
        queue = Task { _ = await task.result }
        return try await task.value
    }

    func characteristic(_ uuid: BluetoothUUID) throws -> Characteristic {
        guard isConnected else {
            throw ELinkSmartConnectionError.disconnected
        }
        guard let characteristic = characteristics[uuid] else {
            throw ELinkSmartConnectionError.characteristicNotFound(uuid)
        }
        return characteristic
    }

    /// Time without a notification after which a reply is considered complete.
    static var quietPeriod: TimeInterval { 1 }

    /// Runs the write, then collects the notifications it causes until they reassemble into a full reply.
    func collect(
        timeout: TimeInterval,
        write: @escaping @Sendable () async throws -> Void
    ) async throws -> [[UInt8]] {
        requestCount += 1
        let id = requestCount
        return try await withCheckedThrowingContinuation { continuation in
            // notifications can arrive before the write returns
            collector = Collector(
                id: id,
                deadline: Date().addingTimeInterval(timeout),
                quiet: min(timeout, Self.quietPeriod),
                continuation: continuation
            )
            Task {
                do {
                    try await write()
                }
                catch {
                    self.finishCollector(id, .failure(error))
                }
            }
            Task {
                await self.watchCollector(id)
            }
        }
    }

    /// Ends the request if no notification arrives before the deadline.
    func watchCollector(_ id: UInt64) async {
        while let collector, collector.id == id {
            let remaining = collector.deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                break
            }
            // notifications move the deadline, so check again well before it
            let wait = min(remaining, collector.quiet / 4)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        guard let collector, collector.id == id else {
            return
        }
        finishCollector(id, .failure(ELinkSmartConnectionError.timeout))
    }

    func finishCollector(_ id: UInt64, _ result: Result<[[UInt8]], Error>) {
        guard let collector, collector.id == id else {
            return
        }
        self.collector = nil
        collector.continuation.resume(with: result)
    }

    func subscribe(_ characteristic: Characteristic) async throws {
        let stream = try await central.notify(for: characteristic)
        notifications.append(stream)
        let task = Task { [weak self] in
            do {
                for try await data in stream {
                    await self?.receive([UInt8](data))
                }
            }
            catch { }
            // the stream ends when the device disconnects
            await self?.connectionLost()
        }
        tasks.append(task)
    }

    func receive(_ bytes: [UInt8]) {
        guard var collector else {
            eventsContinuation.yield(bytes)
            return
        }
        collector.fragments.append(bytes)
        collector.deadline = Date().addingTimeInterval(collector.quiet)
        self.collector = collector
        if ELinkSmartFraming.reassemble(collector.fragments) != nil {
            finishCollector(collector.id, .success(collector.fragments))
        }
    }

    /// Called when the device closed the connection.
    func connectionLost() {
        guard isConnected else {
            return
        }
        close()
    }

    func close() {
        isConnected = false
        notifications.forEach { $0.stop() }
        tasks.forEach { $0.cancel() }
        if let collector {
            finishCollector(collector.id, .failure(ELinkSmartConnectionError.disconnected))
        }
        eventsContinuation.finish()
    }
}

// MARK: - CentralManager

public extension CentralManager where Self: Sendable, AttributeID: Sendable {

    /// Connects to an eLinkSmart lock and discovers its characteristics.
    ///
    /// - Parameters:
    ///   - connectTimeout: Time allowed to establish the Bluetooth connection.
    ///   - timeout: Time allowed for setup.
    ///   - cipher: The AES cipher; defaults to the shared eLinkSmart key.
    func connect(
        toLock peripheral: Peripheral,
        connectTimeout: TimeInterval = 15,
        timeout: TimeInterval = 5,
        cipher: ELinkSmartCipher = .default
    ) async throws -> ELinkSmartConnection<Self> {
        // CoreBluetooth waits forever for a device that is not advertising
        do {
            try await withTimeout(connectTimeout) {
                try await self.connect(to: peripheral)
            } late: { result in
                if case .success = result {
                    await self.disconnect(peripheral)
                }
            }
        }
        catch ELinkSmartConnectionError.timeout {
            throw ELinkSmartConnectionError.connectionTimeout
        }
        let connection = ELinkSmartConnection(
            central: self,
            peripheral: peripheral,
            cipher: cipher
        )
        do {
            try await withTimeout(timeout) {
                try await connection.setup()
            }
        }
        catch {
            await connection.disconnect()
            throw error
        }
        return connection
    }
}

// MARK: - Timeout

/// Runs the operation, throwing ``ELinkSmartConnectionError/timeout`` if it does not finish in time.
///
/// The operation keeps running after a timeout; `late` receives its result.
internal func withTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    operation: @escaping @Sendable () async throws -> T,
    late: @escaping @Sendable (Result<T, Error>) async -> () = { _ in }
) async throws -> T {
    let result = TimeoutResult<T>()
    return try await withCheckedThrowingContinuation { continuation in
        result.continuation = continuation
        let task = Task {
            let value: Result<T, Error>
            do { value = .success(try await operation()) }
            catch { value = .failure(error) }
            if result.resume(with: value) == false {
                await late(value)
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if result.resume(with: .failure(ELinkSmartConnectionError.timeout)) {
                task.cancel()
            }
        }
    }
}

/// Resumes a continuation once.
private final class TimeoutResult<T: Sendable>: @unchecked Sendable {

    private let lock = NSLock()

    private var _continuation: CheckedContinuation<T, Error>?

    var continuation: CheckedContinuation<T, Error>? {
        get { lock.withLock { _continuation } }
        set { lock.withLock { _continuation = newValue } }
    }

    /// Returns `false` if already resumed.
    func resume(with result: Result<T, Error>) -> Bool {
        let continuation = lock.withLock {
            let continuation = _continuation
            _continuation = nil
            return continuation
        }
        guard let continuation else {
            return false
        }
        continuation.resume(with: result)
        return true
    }
}

// MARK: - Error

/// An error from an ``ELinkSmartConnection``.
public enum ELinkSmartConnectionError: Error, Equatable, Sendable {

    /// No reply within the timeout.
    case timeout

    /// The Bluetooth connection was not established in time, usually because the lock is out of range
    /// or connected to another phone.
    case connectionTimeout

    /// The connection was closed.
    case disconnected

    /// A required characteristic was not found.
    case characteristicNotFound(BluetoothUUID)

    /// A characteristic or reply held data that could not be decoded.
    case invalidData(BluetoothUUID)

    /// The lock did not return a valid session token.
    case authenticationFailed

    /// An unlock was attempted before a successful login.
    case notLoggedIn

    /// The lock did not acknowledge the unlock, usually because of a wrong password.
    case unlockFailed
}

extension ELinkSmartConnectionError: CustomStringConvertible {

    public var description: String {
        switch self {
        case .timeout:
            return "No reply from the lock"
        case .connectionTimeout:
            return "Could not connect; the lock may be out of range or connected to another phone"
        case .disconnected:
            return "The lock disconnected"
        case let .characteristicNotFound(uuid):
            return "Characteristic \(uuid) not found"
        case let .invalidData(uuid):
            return "Invalid data from characteristic \(uuid)"
        case .authenticationFailed:
            return "The lock rejected the login"
        case .notLoggedIn:
            return "Not logged in"
        case .unlockFailed:
            return "The lock rejected the unlock; check the password"
        }
    }
}
