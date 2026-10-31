//
//  Store.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import Foundation
import SwiftUI
import CoreBluetooth
import Bluetooth
import GATT
import DarwinGATT
import ELinkSmart

@MainActor
public final class Store: ObservableObject {

    // MARK: - Properties

    @Published
    public private(set) var state: DarwinBluetoothState = .unknown

    @Published
    public private(set) var isScanning = false

    @Published
    public private(set) var peripherals = [NativeCentral.Peripheral: ELinkSmartLock]()

    /// Open GATT connections.
    @Published
    public internal(set) var connections = [NativeCentral.Peripheral: ELinkSmartConnection<NativeCentral>]()

    lazy var central = NativeCentral()

    private var scanStream: AsyncCentralScan<NativeCentral>?

    // MARK: - Initialization

    public static let shared = Store()

    private init() {
        central.log = { [unowned self] in self.log("📲 Central: " + $0) }
        observeBluetoothState()
    }

    // MARK: - Methods

    private func observeBluetoothState() {
        Task { [weak self] in
            while let self = self {
                let newState = await self.central.state
                if newState != self.state {
                    self.state = newState
                }
                try await Task.sleep(timeInterval: 0.5)
            }
        }
    }

    public func scan() async throws {
        let bluetoothState = await central.state
        guard bluetoothState == .poweredOn else {
            throw ELinkSmartAppError.bluetoothUnavailable
        }
        self.peripherals.removeAll(keepingCapacity: true)
        stopScanning()
        isScanning = true
        let scanStream = central.scan(
            with: [.elinkSmartAdvertisedService],
            filterDuplicates: true
        )
        self.scanStream = scanStream
        Task { [unowned self] in
            defer { Task { await MainActor.run { self.isScanning = false } } }
            do {
                for try await scanData in scanStream {
                    found(scanData)
                }
            }
            catch is CancellationError { }
            catch {
                self.log("Error scanning: \(error)")
            }
        }
    }

    /// Scans for the given duration, then stops. Used by App Intents.
    public func scan(duration: TimeInterval) async throws {
        try await scan()
        try await Task.sleep(timeInterval: duration)
        stopScanning()
    }

    public func stopScanning() {
        scanStream?.stop()
        scanStream = nil
        isScanning = false
    }

    private func found(_ scanData: ScanData<NativeCentral.Peripheral, NativeCentral.Advertisement>) {
        guard let lock = ELinkSmartLock(scanData.advertisementData) else {
            return
        }
        if peripherals[scanData.peripheral] != lock {
            peripherals[scanData.peripheral] = lock
        }
    }

    nonisolated public func log(_ message: String) {
        print(message)
    }
}
