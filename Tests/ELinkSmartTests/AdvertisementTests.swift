//
//  AdvertisementTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import XCTest
import Bluetooth
import GATT
@testable import ELinkSmart

final class AdvertisementTests: XCTestCase {

    func testDecodeByName() {
        let advertisement = TestAdvertisement(localName: "lock-796A")
        let lock = ELinkSmartLock(advertisement)
        XCTAssertEqual(lock?.name, "lock-796A")
        XCTAssertEqual(lock?.id, "lock-796A")
    }

    func testDecodeByService() {
        let advertisement = TestAdvertisement(serviceUUIDs: [.elinkSmartAdvertisedService])
        XCTAssertEqual(ELinkSmartLock(advertisement)?.name, "lock")
    }

    func testIgnoresOther() {
        XCTAssertNil(ELinkSmartLock(TestAdvertisement(localName: "Govee_H5072")))
        XCTAssertNil(ELinkSmartLock(TestAdvertisement()))
    }

    func testAdvertisedServiceUUID() {
        XCTAssertEqual(BluetoothUUID.elinkSmartAdvertisedService, .bit16(0xFF30))
        XCTAssertEqual(BluetoothUUID.elinkSmartService, .bit16(0x1828))
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
