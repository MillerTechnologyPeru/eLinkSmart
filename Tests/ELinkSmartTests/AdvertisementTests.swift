//
//  AdvertisementTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import Foundation
import Testing
import Bluetooth
import GATT
@testable import ELinkSmart

struct AdvertisementTests {

    @Test func decodeByName() {
        let advertisement = TestAdvertisement(localName: "lock-796A")
        let lock = ELinkSmartLock(advertisement)
        #expect(lock?.name == "lock-796A")
        #expect(lock?.id == "lock-796A")
    }

    @Test func decodeByService() {
        let advertisement = TestAdvertisement(serviceUUIDs: [.elinkSmartAdvertisedService])
        #expect(ELinkSmartLock(advertisement)?.name == "lock")
    }

    @Test func ignoresOther() {
        #expect(ELinkSmartLock(TestAdvertisement(localName: "Govee_H5072")) == nil)
        #expect(ELinkSmartLock(TestAdvertisement()) == nil)
    }

    @Test func advertisedServiceUUID() {
        #expect(BluetoothUUID.elinkSmartAdvertisedService == .bit16(0xFF30))
        #expect(BluetoothUUID.elinkSmartService == .bit16(0x1828))
    }
}

/// Minimal advertisement data for tests.
struct TestAdvertisement: AdvertisementData {

    typealias Data = Foundation.Data

    var localName: String?
    var manufacturerData: ManufacturerSpecificData<Data>?
    var txPowerLevel: Double?
    var serviceData: [BluetoothUUID: Data]?
    var serviceUUIDs: [BluetoothUUID]?
    var solicitedServiceUUIDs: [BluetoothUUID]?

    init(
        localName: String? = nil,
        serviceUUIDs: [BluetoothUUID]? = nil
    ) {
        self.localName = localName
        self.serviceUUIDs = serviceUUIDs
    }
}
