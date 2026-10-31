//
//  ELinkSmartCipher.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

/// AES-128-ECB cipher used for all eLinkSmart BLE traffic.
///
/// Every frame is encrypted with AES-128 in ECB mode under a key hardcoded in the vendor app and
/// firmware. Plaintext that is not a multiple of the 16-byte block size is PKCS7-padded before
/// encryption; decryption leaves any padding in place, since the payload carries its own length field
/// (see ``ELinkSmartPacket``).
public struct ELinkSmartCipher: Sendable {

    /// The key shared by every eLinkSmart lock: the 16 ASCII bytes of `"7b7079bb69001dce"`.
    public static let defaultKey: [UInt8] = Array("7b7079bb69001dce".utf8)

    /// A cipher using the ``defaultKey``.
    public static let `default` = ELinkSmartCipher(key: defaultKey)!

    private let aes: AES128

    /// Creates a cipher from a 16-byte key, or returns `nil` if the key is the wrong size.
    public init?(key: [UInt8]) {
        guard let aes = AES128(key: key) else {
            return nil
        }
        self.aes = aes
    }
}

public extension ELinkSmartCipher {

    /// The AES block size, in bytes.
    static var blockSize: Int { 16 }

    /// PKCS7-pads the plaintext to a block boundary and encrypts it, block by block, in ECB mode.
    func encrypt(_ plaintext: [UInt8]) -> [UInt8] {
        var data = plaintext
        let remainder = data.count % Self.blockSize
        if remainder != 0 {
            let padding = Self.blockSize - remainder
            data += [UInt8](repeating: UInt8(padding), count: padding)
        }
        var output = [UInt8]()
        output.reserveCapacity(data.count)
        var index = 0
        while index < data.count {
            output += aes.encrypt(block: data[index ..< index + Self.blockSize])
            index += Self.blockSize
        }
        return output
    }

    /// Decrypts a ciphertext, block by block, in ECB mode.
    ///
    /// Returns `nil` if the ciphertext length is not a multiple of the block size. Any PKCS7 or
    /// zero padding is left in the result for the caller to ignore using the payload length field.
    func decrypt(_ ciphertext: [UInt8]) -> [UInt8]? {
        guard ciphertext.count % Self.blockSize == 0 else {
            return nil
        }
        var output = [UInt8]()
        output.reserveCapacity(ciphertext.count)
        var index = 0
        while index < ciphertext.count {
            output += aes.decrypt(block: ciphertext[index ..< index + Self.blockSize])
            index += Self.blockSize
        }
        return output
    }
}
