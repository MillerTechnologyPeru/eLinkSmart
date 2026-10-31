//
//  Integer.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

internal extension UInt16 {

    /// Initializes a value from two little-endian bytes.
    init(littleEndian bytes: (UInt8, UInt8)) {
        self = UInt16(bytes.0) | (UInt16(bytes.1) << 8)
    }

    /// The value as two little-endian bytes.
    var littleEndianBytes: [UInt8] {
        [UInt8(truncatingIfNeeded: self), UInt8(truncatingIfNeeded: self >> 8)]
    }
}

internal extension UInt32 {

    /// Initializes a value from four little-endian bytes.
    init(littleEndian bytes: (UInt8, UInt8, UInt8, UInt8)) {
        self = UInt32(bytes.0)
            | (UInt32(bytes.1) << 8)
            | (UInt32(bytes.2) << 16)
            | (UInt32(bytes.3) << 24)
    }

    /// The value as four little-endian bytes.
    var littleEndianBytes: [UInt8] {
        [
            UInt8(truncatingIfNeeded: self),
            UInt8(truncatingIfNeeded: self >> 8),
            UInt8(truncatingIfNeeded: self >> 16),
            UInt8(truncatingIfNeeded: self >> 24)
        ]
    }
}
