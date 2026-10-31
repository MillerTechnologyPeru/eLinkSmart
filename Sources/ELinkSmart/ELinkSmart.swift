//
//  ELinkSmart.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import Bluetooth
import GATT

/// An eLinkSmart padlock discovered in a Bluetooth scan.
///
/// The locks advertise a Complete Local Name of the form `lock-XXXX` (the last two octets of the
/// Bluetooth address, in hex) and the 16-bit service UUID ``BluetoothUUID/elinkSmartAdvertisedService``.
public struct ELinkSmartLock: Equatable, Hashable, Sendable, Identifiable {

    /// The advertised local name, e.g. `"lock-796A"`.
    public let name: String

    public var id: String { name }

    public init(name: String) {
        self.name = name
    }
}

public extension ELinkSmartLock {

    /// The prefix of every eLinkSmart local name.
    static var namePrefix: String { "lock-" }

    /// Decodes a lock from advertisement data, or returns `nil` if it is not an eLinkSmart lock.
    init?<T: GATT.AdvertisementData>(_ advertisementData: T) {
        if let localName = advertisementData.localName, localName.hasPrefix(Self.namePrefix) {
            self.name = localName
        } else if let services = advertisementData.serviceUUIDs,
                  services.contains(.elinkSmartAdvertisedService) {
            self.name = "lock"
        } else {
            return nil
        }
    }
}
