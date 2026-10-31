//
//  MockLock.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

#if targetEnvironment(simulator)
import Foundation
import Bluetooth
import GATT
import ELinkSmart

public typealias MockScanData = ScanData<GATT.Peripheral, MockAdvertisementData>

public typealias MockService = GATT.Service<GATT.Peripheral, UInt16>
public typealias MockCharacteristic = GATT.Characteristic<GATT.Peripheral, UInt16>

// MARK: - Peripheral

public extension GATT.Peripheral {

    /// The simulated lock, matching the eLinkSmart profile (`24:EC:4A:30:79:6A`, name `lock-796A`).
    static var lock: GATT.Peripheral {
        GATT.Peripheral(id: BluetoothAddress(rawValue: "24:EC:4A:30:79:6A")!)
    }
}

// MARK: - Advertisement

public struct MockAdvertisementData: AdvertisementData {

    public typealias Data = Foundation.Data

    public let localName: String?
    public let manufacturerData: ManufacturerSpecificData<Data>?
    public let txPowerLevel: Double?
    public let serviceData: [BluetoothUUID: Data]?
    public let serviceUUIDs: [BluetoothUUID]?
    public let solicitedServiceUUIDs: [BluetoothUUID]?

    internal init(
        localName: String? = nil,
        serviceUUIDs: [BluetoothUUID]? = nil
    ) {
        self.localName = localName
        self.manufacturerData = nil
        self.txPowerLevel = nil
        self.serviceData = nil
        self.serviceUUIDs = serviceUUIDs
        self.solicitedServiceUUIDs = nil
    }
}

public extension MockAdvertisementData {

    static var lock: MockAdvertisementData {
        MockAdvertisementData(
            localName: "lock-796A",
            serviceUUIDs: [.elinkSmartAdvertisedService]
        )
    }
}

public extension MockScanData {

    static var lock: MockScanData {
        MockScanData(
            peripheral: .lock,
            date: Date(timeIntervalSinceReferenceDate: 10_000),
            rssi: -40,
            advertisementData: .lock,
            isConnectable: true
        )
    }
}

// MARK: - Attributes

public extension MockService {

    static var elinkSmart: MockService {
        MockService(id: 0x10, uuid: .elinkSmartService, peripheral: .lock)
    }
}

public extension MockCharacteristic {

    static var dataIn: MockCharacteristic {
        MockCharacteristic(id: 0x11, uuid: .elinkSmartDataIn, peripheral: .lock, properties: [.write, .writeWithoutResponse])
    }

    static var dataOut: MockCharacteristic {
        MockCharacteristic(id: 0x12, uuid: .elinkSmartDataOut, peripheral: .lock, properties: [.notify])
    }

    static var dataIn2: MockCharacteristic {
        MockCharacteristic(id: 0x13, uuid: .elinkSmartDataIn2, peripheral: .lock, properties: [.write])
    }
}

// MARK: - Lock Simulation

/// Simulates the lock's side of the protocol: decrypts a command and returns the data-out reply frames.
public struct MockLockState {

    /// The six-digit password this simulated lock accepts.
    public static let password = "123456"

    private var challenge: [UInt8]?

    public init() { }

    /// Resets the session, as happens on a fresh connection.
    public mutating func reset() {
        challenge = nil
    }

    /// Processes a decrypted command stream and returns the data-out notifications, if any.
    public mutating func handle(ciphertext: [UInt8]) -> [[UInt8]] {
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
        case .unlock, .unlockAlternate:
            guard let challenge, packet.parameters.count >= 14 else {
                return []
            }
            let proof = Array(cipher.encrypt(challenge).prefix(4))
            guard Array(packet.parameters[0 ..< 4]) == proof,
                  Array(packet.parameters[8 ..< 14]) == Array(Self.password.utf8) else {
                return [] // wrong proof or password: the lock stays silent
            }
            let ack = ELinkSmartPacket(command: packet.command, parameters: [0x00, 0x00])
            return ELinkSmartFraming.notifications(cipher.encrypt(ack.plaintext))
        default:
            return []
        }
    }
}
#endif
