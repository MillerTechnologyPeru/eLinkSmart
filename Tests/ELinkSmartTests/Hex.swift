//
//  Hex.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

/// Parses a string of space-separated hex bytes into an array.
func hex(_ string: String) -> [UInt8] {
    string.split(separator: " ").compactMap { UInt8($0, radix: 16) }
}
