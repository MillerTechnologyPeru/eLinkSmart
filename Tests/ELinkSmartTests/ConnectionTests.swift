//
//  ConnectionTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import Foundation
import XCTest
@testable import ELinkSmart
import Bluetooth
import GATT
import BluetoothGAP

/// End-to-end tests of ``ELinkSmartConnection`` against a simulated lock.
final class ConnectionTests: XCTestCase {

    func testLoginAndUnlock() async throws {
        let central = TestCentral()
        let connection = try await central.connect(toLock: central.peripheral)
        try await connection.login()
        // the simulated lock's challenge is DE AD BE EF, little-endian
        let token = await connection.sessionToken
        XCTAssertEqual(token, 0xEFBEADDE)
        try await connection.unlock(password: ELinkSmartPassword(rawValue: "123456")!)
        // first write is the login, then the unlock; each is a single 20-byte packet or fewer
        XCTAssertGreaterThanOrEqual(central.writes.count, 2)
        await connection.disconnect()
    }

    func testUnlockLogsInAutomatically() async throws {
        let central = TestCentral()
        let connection = try await central.connect(toLock: central.peripheral)
        try await connection.unlock(password: ELinkSmartPassword(rawValue: "123456")!)
        let token = await connection.sessionToken
        XCTAssertNotNil(token)
        await connection.disconnect()
    }

    func testWrongPassword() async throws {
        let central = TestCentral()
        let connection = try await central.connect(toLock: central.peripheral)
        do {
            // the lock sends no reply to a bad password, so the command times out
            try await connection.unlock(password: ELinkSmartPassword(rawValue: "000000")!, timeout: 0.3)
            XCTFail("expected an error")
        } catch ELinkSmartConnectionError.timeout {
            // expected
        }
        await connection.disconnect()
    }

    func testBattery() async throws {
        let central = TestCentral()
        let connection = try await central.connect(toLock: central.peripheral)
        let level = try await connection.readBattery()
        XCTAssertEqual(level, 0x42)
        await connection.disconnect()
    }

    func testDisconnect() async throws {
        let central = TestCentral()
        let connection = try await central.connect(toLock: central.peripheral)
        await connection.disconnect()
        let isConnected = await connection.isConnected
        XCTAssertFalse(isConnected)
        do {
            try await connection.login()
            XCTFail("expected an error")
        } catch ELinkSmartConnectionError.disconnected {
            // expected
        }
    }

    func testConnectTimeout() async throws {
        let central = TestCentral(isAdvertising: false)
        do {
            _ = try await central.connect(toLock: central.peripheral, connectTimeout: 0.2)
            XCTFail("expected an error")
        } catch ELinkSmartConnectionError.connectionTimeout {
            // expected
        }
    }
}

// MARK: - Test Central

/// A simulated central with one eLinkSmart lock that decrypts commands and replies like the firmware.
private final class TestCentral: CentralManager, @unchecked Sendable {

    typealias Peripheral = GATT.Peripheral
    typealias Advertisement = LowEnergyAdvertisingData
    typealias AttributeID = UInt16
    typealias Data = Foundation.Data

    var log: (@Sendable (String) -> ())?

    let peripheral = Peripheral(id: BluetoothAddress(rawValue: "24:EC:4A:30:79:6A")!)

    /// Whether `connect(to:)` succeeds; otherwise it never returns, like CoreBluetooth.
    let isAdvertising: Bool

    private let pin = "123456"

    private let lock = NSLock()
    private var _writes = [[UInt8]]()
    private var _isConnected = false
    private var notify = [BluetoothUUID: AsyncIndefiniteStream<Data>.Continuation]()

    /// The lock's current challenge, cached after a login.
    private var challenge: [UInt8]?
    /// Accumulated command packets for the current write.
    private var inbuf = [[UInt8]]()

    init(isAdvertising: Bool = true) {
        self.isAdvertising = isAdvertising
    }

    var writes: [[UInt8]] { lock.withLock { _writes } }

    var peripherals: [Peripheral: Bool] {
        get async { [peripheral: lock.withLock { _isConnected }] }
    }

    func scan(filterDuplicates: Bool) async throws -> AsyncCentralScan<TestCentral> {
        AsyncCentralScan { _ in }
    }

    func connect(to peripheral: Peripheral) async throws {
        guard isAdvertising else {
            try await Task.sleep(nanoseconds: .max)
            return
        }
        lock.withLock { _isConnected = true }
    }

    func disconnect(_ peripheral: Peripheral) async {
        lock.withLock {
            _isConnected = false
            notify.removeAll()
        }
    }

    func disconnectAll() async {
        await disconnect(peripheral)
    }

    func discoverServices(
        _ services: Set<BluetoothUUID>,
        for peripheral: Peripheral
    ) async throws -> [Service<Peripheral, AttributeID>] {
        [
            Service(id: 0x10, uuid: .elinkSmartService, peripheral: peripheral),
            Service(id: 0x20, uuid: .batteryService, peripheral: peripheral),
        ]
    }

    func discoverCharacteristics(
        _ characteristics: Set<BluetoothUUID>,
        for service: Service<Peripheral, AttributeID>
    ) async throws -> [Characteristic<Peripheral, AttributeID>] {
        switch service.uuid {
        case .elinkSmartService:
            return [
                Characteristic(id: 0x11, uuid: .elinkSmartDataIn, peripheral: peripheral, properties: [.write, .writeWithoutResponse]),
                Characteristic(id: 0x12, uuid: .elinkSmartDataOut, peripheral: peripheral, properties: [.notify]),
                Characteristic(id: 0x13, uuid: .elinkSmartDataIn2, peripheral: peripheral, properties: [.write]),
            ]
        case .batteryService:
            return [
                Characteristic(id: 0x21, uuid: .batteryLevel, peripheral: peripheral, properties: [.read, .notify]),
            ]
        default:
            return []
        }
    }

    func readValue(for characteristic: Characteristic<Peripheral, AttributeID>) async throws -> Data {
        characteristic.uuid == .batteryLevel ? Data([0x42]) : Data()
    }

    func writeValue(
        _ data: Data,
        for characteristic: Characteristic<Peripheral, AttributeID>,
        withResponse: Bool
    ) async throws {
        let frame = [UInt8](data)
        let reply: (BluetoothUUID, [[UInt8]])? = lock.withLock {
            _writes.append(frame)
            guard characteristic.uuid == .elinkSmartDataIn else { return nil }
            inbuf.append(frame)
            // the first packet's high nibble is the total packet count
            guard let first = inbuf.first, let expected = first.first.map({ Int(ELinkSmartFraming.nibbleSwap($0)) }),
                  inbuf.count >= expected else {
                return nil
            }
            let stream = inbuf.flatMap { $0 }
            inbuf.removeAll()
            var ciphertext = Array(stream.dropFirst(2))
            ciphertext = Array(ciphertext.prefix(ciphertext.count - ciphertext.count % 16))
            return (.elinkSmartDataOut, process(ciphertext))
        }
        if let (uuid, frames) = reply {
            let continuation = lock.withLock { notify[uuid] }
            for frame in frames {
                continuation?.yield(Data(frame))
            }
        }
    }

    /// Decrypts a command and returns the data-out notifications the lock would send back.
    private func process(_ ciphertext: [UInt8]) -> [[UInt8]] {
        let cipher = ELinkSmartCipher.default
        guard let plaintext = cipher.decrypt(ciphertext),
              let packet = ELinkSmartPacket(plaintext: plaintext) else {
            return []
        }
        switch packet.command {
        case .login:
            let challenge: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
            self.challenge = challenge
            let parameters = challenge + [UInt8](repeating: 0x00, count: 42)
            let response = ELinkSmartPacket(command: .login, parameters: parameters)
            return ELinkSmartFraming.notifications(cipher.encrypt(response.plaintext))
        case .unlock:
            guard packet.parameters.count >= 14,
                  Array(packet.parameters[0 ..< 4]) == challenge,
                  Array(packet.parameters[8 ..< 14]) == Array(pin.utf8) else {
                return [] // wrong token or password: no reply
            }
            let ack = ELinkSmartPacket(command: .unlock, parameters: [0x00, 0x00])
            return ELinkSmartFraming.notifications(cipher.encrypt(ack.plaintext))
        default:
            return []
        }
    }

    func discoverDescriptors(for characteristic: Characteristic<Peripheral, AttributeID>) async throws -> [Descriptor<Peripheral, AttributeID>] {
        []
    }

    func readValue(for descriptor: Descriptor<Peripheral, AttributeID>) async throws -> Data {
        Data()
    }

    func writeValue(_ data: Data, for descriptor: Descriptor<Peripheral, AttributeID>) async throws { }

    func notify(for characteristic: Characteristic<Peripheral, AttributeID>) async throws -> AsyncCentralNotifications<TestCentral> {
        AsyncCentralNotifications(onTermination: { }) { continuation in
            self.lock.withLock { self.notify[characteristic.uuid] = continuation }
        }
    }

    func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit {
        MaximumTransmissionUnit(rawValue: 23)!
    }

    func rssi(for peripheral: Peripheral) async throws -> RSSI {
        RSSI(rawValue: -50)!
    }
}
