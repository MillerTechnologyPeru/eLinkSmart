//
//  MockCentral.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

#if targetEnvironment(simulator)
import Foundation
import Bluetooth
import GATT
import DarwinGATT
import ELinkSmart

/// A simulated central with one eLinkSmart lock that answers login and unlock like the firmware.
public final class MockCentral: CentralManager {

    public typealias Peripheral = GATT.Peripheral
    public typealias Advertisement = MockAdvertisementData
    public typealias AttributeID = UInt16

    // MARK: - Properties

    public var log: ((String) -> ())?

    public var state: DarwinBluetoothState {
        get async {
            try? await Task.sleep(timeInterval: 0.01)
            return await storage.bluetoothState
        }
    }

    public var peripherals: [Peripheral: Bool] {
        get async {
            let state = await storage.state
            var result = [Peripheral: Bool]()
            for scanData in state.scanData {
                result[scanData.peripheral] = state.connected.contains(scanData.peripheral)
            }
            return result
        }
    }

    private let storage = Storage()

    // MARK: - Initialization

    public init() {
        Task {
            try await Task.sleep(timeInterval: 0.3)
            await self.storage.stateDidChange(.poweredOn)
        }
    }

    // MARK: - Methods

    public func scan(filterDuplicates: Bool = true) -> AsyncCentralScan<MockCentral> {
        _scan(with: [])
    }

    public func scan(with services: Set<BluetoothUUID>, filterDuplicates: Bool = true) -> AsyncCentralScan<MockCentral> {
        _scan(with: services)
    }

    private func _scan(with services: Set<BluetoothUUID>) -> AsyncCentralScan<MockCentral> {
        AsyncCentralScan { continuation in
            let state = await self.state
            guard state == .poweredOn else {
                throw DarwinCentralError.invalidState(state)
            }
            await self.storage.updateState { $0.isScanning = true }
            defer { Task { await self.storage.updateState { $0.isScanning = false } } }
            try await Task.sleep(timeInterval: 0.2)
            for scanData in await self.storage.state.scanData {
                if services.isEmpty == false {
                    let advertised = Set(scanData.advertisementData.serviceUUIDs ?? [])
                    guard services.isSubset(of: advertised) else {
                        continue
                    }
                }
                try await Task.sleep(timeInterval: 0.1)
                continuation(scanData)
            }
        }
    }

    public func connect(to peripheral: Peripheral) async throws {
        let state = await self.state
        guard state == .poweredOn else {
            throw DarwinCentralError.invalidState(state)
        }
        await storage.updateState {
            $0.connected.insert(peripheral)
            $0.lock.reset()
            $0.inbuf.removeAll()
        }
        log?("Connected to \(peripheral)")
    }

    public func disconnect(_ peripheral: Peripheral) {
        Task {
            await storage.updateState {
                $0.connected.remove(peripheral)
                $0.notifications.removeAll()
            }
        }
    }

    public func disconnectAll() {
        Task {
            await storage.updateState {
                $0.connected.removeAll()
                $0.notifications.removeAll()
            }
        }
    }

    public func discoverServices(
        _ services: Set<BluetoothUUID> = [],
        for peripheral: Peripheral
    ) async throws -> [Service<Peripheral, AttributeID>] {
        try await requireConnected(peripheral)
        return [.elinkSmart, .battery]
    }

    public func discoverIncludedServices(
        _ services: Set<BluetoothUUID> = [],
        for service: Service<Peripheral, AttributeID>
    ) async throws -> [Service<Peripheral, AttributeID>] {
        []
    }

    public func discoverCharacteristics(
        _ characteristics: Set<BluetoothUUID> = [],
        for service: Service<Peripheral, AttributeID>
    ) async throws -> [Characteristic<Peripheral, AttributeID>] {
        try await requireConnected(service.peripheral)
        switch service.uuid {
        case .elinkSmartService:
            return [.dataIn, .dataOut, .dataIn2]
        case .batteryService:
            return [.batteryLevel]
        default:
            return []
        }
    }

    public func readValue(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) async throws -> Data {
        try await requireConnected(characteristic.peripheral)
        return characteristic.uuid == .batteryLevel ? Data([0x42]) : Data()
    }

    public func writeValue(
        _ data: Data,
        for characteristic: Characteristic<Peripheral, AttributeID>,
        withResponse: Bool = true
    ) async throws {
        try await requireConnected(characteristic.peripheral)
        let frames = await storage.receiveWrite([UInt8](data), uuid: characteristic.uuid)
        guard frames.isEmpty == false else {
            return
        }
        let continuation = await storage.notification(for: .elinkSmartDataOut)
        for frame in frames {
            continuation?.yield(Data(frame))
        }
    }

    public func discoverDescriptors(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) async throws -> [Descriptor<Peripheral, AttributeID>] {
        []
    }

    public func readValue(
        for descriptor: Descriptor<Peripheral, AttributeID>
    ) async throws -> Data {
        Data()
    }

    public func writeValue(
        _ data: Data,
        for descriptor: Descriptor<Peripheral, AttributeID>
    ) async throws { }

    public func notify(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) async throws -> AsyncCentralNotifications<MockCentral> {
        try await requireConnected(characteristic.peripheral)
        let uuid = characteristic.uuid
        return AsyncCentralNotifications(bufferSize: 1000, onTermination: {
            Task { await self.storage.updateState { $0.notifications[uuid] = nil } }
        }) { continuation in
            Task { await self.storage.updateState { $0.notifications[uuid] = continuation } }
        }
    }

    public func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit {
        .default
    }

    public func rssi(for peripheral: Peripheral) async throws -> RSSI {
        RSSI(rawValue: -40)!
    }

    // MARK: - Private

    private func requireConnected(_ peripheral: Peripheral) async throws {
        let state = await self.state
        guard state == .poweredOn else {
            throw DarwinCentralError.invalidState(state)
        }
        guard await storage.state.connected.contains(peripheral) else {
            throw CentralError.disconnected
        }
    }
}

// MARK: - Storage

internal extension MockCentral {

    actor Storage {

        init() { }

        var bluetoothState: DarwinBluetoothState = .unknown

        func stateDidChange(_ newValue: DarwinBluetoothState) {
            bluetoothState = newValue
        }

        var state = State()

        @discardableResult
        func updateState<T>(_ block: (inout State) -> (T)) -> T {
            block(&state)
        }

        func notification(for uuid: BluetoothUUID) -> AsyncIndefiniteStream<Data>.Continuation? {
            state.notifications[uuid]
        }

        /// Accumulates a data-in write and, once the command is complete, returns the lock's reply.
        func receiveWrite(_ frame: [UInt8], uuid: BluetoothUUID) -> [[UInt8]] {
            guard uuid == .elinkSmartDataIn else {
                return []
            }
            state.inbuf.append(frame)
            // the first packet's high nibble is the total packet count
            guard let first = state.inbuf.first,
                  let expected = first.first.map({ Int(ELinkSmartFraming.nibbleSwap($0)) }),
                  state.inbuf.count >= expected else {
                return []
            }
            let stream = state.inbuf.flatMap { $0 }
            state.inbuf.removeAll()
            var ciphertext = Array(stream.dropFirst(2))
            ciphertext = Array(ciphertext.prefix(ciphertext.count - ciphertext.count % 16))
            return state.lock.handle(ciphertext: ciphertext)
        }
    }

    struct State {

        var isScanning = false
        var scanData: [MockScanData] = [.lock]
        var connected = Set<Peripheral>()
        var inbuf = [[UInt8]]()
        var lock = MockLockState()
        var notifications = [BluetoothUUID: AsyncIndefiniteStream<Data>.Continuation]()
    }
}

// Required by `ELinkSmartConnection`; storage is an actor.
extension MockCentral: @unchecked Sendable { }
#endif
