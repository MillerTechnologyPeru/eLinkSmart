//
//  AES.swift
//
//
//  Created by Alsey Coleman Miller on 10/28/26.
//

/// AES-128 block cipher (FIPS-197), single block (ECB) only.
///
/// Pure Swift so the package keeps building on every platform without a crypto dependency.
/// Only used for the eLinkSmart BLE frame encryption; not constant time.
internal struct AES128: Sendable {

    static var blockSize: Int { 16 }

    static var keySize: Int { 16 }

    private static var rounds: Int { 10 }

    /// Expanded key, 11 round keys of 16 bytes.
    private let roundKeys: [UInt8]

    init?<C: Collection>(key: C) where C.Element == UInt8 {
        let key = [UInt8](key)
        guard key.count == Self.keySize else {
            return nil
        }
        self.roundKeys = Self.expand(key)
    }
}

internal extension AES128 {

    func encrypt<C: Collection>(block: C) -> [UInt8] where C.Element == UInt8 {
        var state = [UInt8](block)
        precondition(state.count == Self.blockSize)
        addRoundKey(&state, round: 0)
        for round in 1 ..< Self.rounds {
            Self.subBytes(&state, box: AESTables.sbox)
            Self.shiftRows(&state)
            Self.mixColumns(&state)
            addRoundKey(&state, round: round)
        }
        Self.subBytes(&state, box: AESTables.sbox)
        Self.shiftRows(&state)
        addRoundKey(&state, round: Self.rounds)
        return state
    }

    func decrypt<C: Collection>(block: C) -> [UInt8] where C.Element == UInt8 {
        var state = [UInt8](block)
        precondition(state.count == Self.blockSize)
        addRoundKey(&state, round: Self.rounds)
        for round in (1 ..< Self.rounds).reversed() {
            Self.inverseShiftRows(&state)
            Self.subBytes(&state, box: AESTables.inverseSBox)
            addRoundKey(&state, round: round)
            Self.inverseMixColumns(&state)
        }
        Self.inverseShiftRows(&state)
        Self.subBytes(&state, box: AESTables.inverseSBox)
        addRoundKey(&state, round: 0)
        return state
    }
}

private extension AES128 {

    static func expand(_ key: [UInt8]) -> [UInt8] {
        let roundConstants: [UInt8] = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36]
        var words = key
        words.reserveCapacity(16 * (rounds + 1))
        for i in 4 ..< 4 * (rounds + 1) {
            var word = Array(words[(i - 1) * 4 ..< i * 4])
            if i % 4 == 0 {
                word = [word[1], word[2], word[3], word[0]].map { AESTables.sbox[Int($0)] }
                word[0] ^= roundConstants[i / 4 - 1]
            }
            for j in 0 ..< 4 {
                words.append(words[(i - 4) * 4 + j] ^ word[j])
            }
        }
        return words
    }

    func addRoundKey(_ state: inout [UInt8], round: Int) {
        for i in 0 ..< Self.blockSize {
            state[i] ^= roundKeys[round * Self.blockSize + i]
        }
    }

    static func subBytes(_ state: inout [UInt8], box: [UInt8]) {
        for i in 0 ..< blockSize {
            state[i] = box[Int(state[i])]
        }
    }

    /// Row `r` rotates left by `r`. State is column major: byte `r + 4c`.
    static func shiftRows(_ state: inout [UInt8]) {
        let old = state
        for row in 1 ..< 4 {
            for column in 0 ..< 4 {
                state[row + 4 * column] = old[row + 4 * ((column + row) % 4)]
            }
        }
    }

    static func inverseShiftRows(_ state: inout [UInt8]) {
        let old = state
        for row in 1 ..< 4 {
            for column in 0 ..< 4 {
                state[row + 4 * column] = old[row + 4 * ((column - row + 4) % 4)]
            }
        }
    }

    static func mixColumns(_ state: inout [UInt8]) {
        for column in 0 ..< 4 {
            let a = Array(state[4 * column ..< 4 * column + 4])
            state[4 * column + 0] = gmul(a[0], 2) ^ gmul(a[1], 3) ^ a[2] ^ a[3]
            state[4 * column + 1] = a[0] ^ gmul(a[1], 2) ^ gmul(a[2], 3) ^ a[3]
            state[4 * column + 2] = a[0] ^ a[1] ^ gmul(a[2], 2) ^ gmul(a[3], 3)
            state[4 * column + 3] = gmul(a[0], 3) ^ a[1] ^ a[2] ^ gmul(a[3], 2)
        }
    }

    static func inverseMixColumns(_ state: inout [UInt8]) {
        for column in 0 ..< 4 {
            let a = Array(state[4 * column ..< 4 * column + 4])
            state[4 * column + 0] = gmul(a[0], 14) ^ gmul(a[1], 11) ^ gmul(a[2], 13) ^ gmul(a[3], 9)
            state[4 * column + 1] = gmul(a[0], 9) ^ gmul(a[1], 14) ^ gmul(a[2], 11) ^ gmul(a[3], 13)
            state[4 * column + 2] = gmul(a[0], 13) ^ gmul(a[1], 9) ^ gmul(a[2], 14) ^ gmul(a[3], 11)
            state[4 * column + 3] = gmul(a[0], 11) ^ gmul(a[1], 13) ^ gmul(a[2], 9) ^ gmul(a[3], 14)
        }
    }
}

/// Multiplication in GF(2^8) with the AES polynomial x^8 + x^4 + x^3 + x + 1.
private func gmul(_ a: UInt8, _ b: UInt8) -> UInt8 {
    var a = a, b = b, result: UInt8 = 0
    while b != 0 {
        if b & 1 != 0 {
            result ^= a
        }
        let carry = a & 0x80
        a <<= 1
        if carry != 0 {
            a ^= 0x1B
        }
        b >>= 1
    }
    return result
}

/// S-boxes computed from their definition: multiplicative inverse followed by the affine transform.
private enum AESTables {

    static let sbox: [UInt8] = (0 ... 255).map { value in
        let x = UInt8(value)
        let inverse = x == 0 ? 0 : (1 ... 255).lazy.map(UInt8.init).first { gmul(x, $0) == 1 }!
        func rotate(_ byte: UInt8, _ n: UInt8) -> UInt8 { (byte << n) | (byte >> (8 - n)) }
        return inverse ^ rotate(inverse, 1) ^ rotate(inverse, 2) ^ rotate(inverse, 3) ^ rotate(inverse, 4) ^ 0x63
    }

    static let inverseSBox: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256)
        for (index, value) in sbox.enumerated() {
            table[Int(value)] = UInt8(index)
        }
        return table
    }()
}
