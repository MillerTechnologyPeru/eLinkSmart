//
//  UUID.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import Bluetooth

public extension BluetoothUUID {

    /// Service UUID advertised by the lock (incomplete 16-bit service list).
    ///
    /// Used to filter scan results; note this differs from ``elinkSmartService``,
    /// the primary GATT service discovered after connecting.
    static var elinkSmartAdvertisedService: BluetoothUUID {
        .bit16(0xFF30)
    }

    /// eLinkSmart primary GATT service.
    ///
    /// The vendor reuses the SIG-assigned `0x1828` short UUID for its proprietary protocol.
    static var elinkSmartService: BluetoothUUID {
        .bit16(0x1828)
    }

    /// Data-in characteristic: encrypted command stream, app → lock (chunked writes).
    static var elinkSmartDataIn: BluetoothUUID {
        .bit16(0x2ADD)
    }

    /// Data-out characteristic: encrypted notifications, lock → app (chunked).
    static var elinkSmartDataOut: BluetoothUUID {
        .bit16(0x2ADE)
    }

    /// Secondary data-in characteristic (usually unused).
    static var elinkSmartDataIn2: BluetoothUUID {
        .bit16(0x2ADF)
    }
}
