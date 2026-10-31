//
//  Framing.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

/// Splits ciphertext into BLE packets and reassembles it, for each direction of the eLinkSmart link.
///
/// The two directions are framed differently:
/// - **App → lock** (write to ``BluetoothUUID/elinkSmartDataIn``): the first packet is a 2-byte header
///   `[ nibble-swapped packet count ] [ 0x00 ]` followed by ciphertext; the stream is cut into
///   ≤20-byte writes. A single 16-byte block therefore begins `10 00 …`.
/// - **Lock → app** (notifications on ``BluetoothUUID/elinkSmartDataOut``): the first packet is a
///   little-endian `UInt16` ciphertext length followed by up to 18 ciphertext bytes; later packets
///   carry up to 20 raw bytes each.
public enum ELinkSmartFraming {

    /// The maximum number of bytes per BLE packet.
    public static var packetSize: Int { 20 }

    /// Frames ciphertext for writing to the lock's data-in characteristic.
    public static func write(_ ciphertext: [UInt8]) -> [[UInt8]] {
        // packetCount is the smallest n with n * packetSize - 2 >= ciphertext.count
        let packetCount = max(1, (ciphertext.count + 2 + packetSize - 1) / packetSize)
        let header: [UInt8] = [nibbleSwap(UInt8(truncatingIfNeeded: packetCount)), 0x00]
        return chunk(header + ciphertext)
    }

    /// Frames ciphertext as the notifications the lock sends on its data-out characteristic.
    public static func notifications(_ ciphertext: [UInt8]) -> [[UInt8]] {
        let length = UInt16(truncatingIfNeeded: ciphertext.count).littleEndianBytes
        let headerPayload = Swift.min(ciphertext.count, packetSize - 2)
        var frames = [length + Array(ciphertext.prefix(headerPayload))]
        var remaining = Array(ciphertext.dropFirst(headerPayload))
        while remaining.isEmpty == false {
            frames.append(Array(remaining.prefix(packetSize)))
            remaining = Array(remaining.dropFirst(packetSize))
        }
        return frames
    }

    /// Reassembles data-out notifications into ciphertext, or returns `nil` if they are incomplete.
    public static func reassemble(_ frames: [[UInt8]]) -> [UInt8]? {
        guard let first = frames.first, first.count >= 2 else {
            return nil
        }
        let length = Int(UInt16(littleEndian: (first[0], first[1])))
        var payload = Array(first.dropFirst(2))
        for frame in frames.dropFirst() {
            payload += frame
        }
        guard payload.count >= length else {
            return nil
        }
        return Array(payload.prefix(length))
    }

    /// Swaps the high and low nibbles of a byte.
    public static func nibbleSwap(_ byte: UInt8) -> UInt8 {
        (byte << 4) | (byte >> 4)
    }

    private static func chunk(_ bytes: [UInt8]) -> [[UInt8]] {
        guard bytes.isEmpty == false else {
            return []
        }
        var frames = [[UInt8]]()
        var index = 0
        while index < bytes.count {
            let end = Swift.min(index + packetSize, bytes.count)
            frames.append(Array(bytes[index ..< end]))
            index = end
        }
        return frames
    }
}
