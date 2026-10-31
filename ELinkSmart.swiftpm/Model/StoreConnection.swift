//
//  StoreConnection.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import Foundation
import Bluetooth
import GATT
import DarwinGATT
import ELinkSmart

// MARK: - Connection

public extension Store {

    /// Whether there is an open connection to the lock.
    func isConnected(_ peripheral: NativeCentral.Peripheral) -> Bool {
        connections[peripheral] != nil
    }

    /// Returns the open connection to the lock, connecting first if needed.
    @discardableResult
    func connect(to peripheral: NativeCentral.Peripheral) async throws -> ELinkSmartConnection<NativeCentral> {
        if let connection = connections[peripheral], await connection.isConnected {
            return connection
        }
        // scanning slows down connecting
        if isScanning {
            stopScanning()
            log("Stopped scanning to connect")
        }
        log("Connecting to \(peripheral)")
        let connection = try await central.connect(toLock: peripheral)
        connections[peripheral] = connection
        log("Connected to \(peripheral)")
        // events end when the lock closes the connection
        Task { [weak self] in
            for await event in connection.events {
                self?.log("\(peripheral) unexpected notification \(event)")
            }
            self?.connectionClosed(peripheral, connection)
        }
        return connection
    }

    /// Closes the connection to the lock.
    func disconnect(_ peripheral: NativeCentral.Peripheral) async {
        guard let connection = connections[peripheral] else {
            return
        }
        connections[peripheral] = nil
        await connection.disconnect()
        log("Disconnected from \(peripheral)")
    }

    /// Runs an operation on the connection to the lock, connecting first if needed.
    func perform<T: Sendable>(
        on peripheral: NativeCentral.Peripheral,
        _ operation: (ELinkSmartConnection<NativeCentral>) async throws -> T
    ) async throws -> T {
        let connection = try await connect(to: peripheral)
        do {
            return try await operation(connection)
        }
        catch ELinkSmartConnectionError.disconnected {
            connectionClosed(peripheral, connection)
            throw ELinkSmartConnectionError.disconnected
        }
        catch ELinkSmartConnectionError.timeout {
            // the lock may have gone away without disconnecting; reconnect next time
            await disconnect(peripheral)
            throw ELinkSmartConnectionError.timeout
        }
    }

    /// Logs in to the lock, establishing a session token.
    func login(_ peripheral: NativeCentral.Peripheral) async throws {
        try await perform(on: peripheral) {
            try await $0.login()
        }
        log("\(peripheral) logged in")
    }

    /// Unlocks the lock with the given password.
    func unlock(_ peripheral: NativeCentral.Peripheral, password: ELinkSmartPassword) async throws {
        try await perform(on: peripheral) {
            try await $0.unlock(password: password)
        }
        log("\(peripheral) unlocked")
    }

    /// Reads the lock's battery level.
    func readBattery(_ peripheral: NativeCentral.Peripheral) async throws -> UInt8 {
        let level = try await perform(on: peripheral) {
            try await $0.readBattery()
        }
        log("\(peripheral) battery \(level) %")
        return level
    }
}

private extension Store {

    /// Forgets a connection the lock closed.
    func connectionClosed(_ peripheral: NativeCentral.Peripheral, _ connection: ELinkSmartConnection<NativeCentral>) {
        guard connections[peripheral] === connection else {
            return
        }
        connections[peripheral] = nil
        log("\(peripheral) closed the connection")
    }
}
