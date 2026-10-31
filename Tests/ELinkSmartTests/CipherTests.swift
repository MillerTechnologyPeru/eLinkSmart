//
//  CipherTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import XCTest
@testable import ELinkSmart

final class CipherTests: XCTestCase {

    /// FIPS-197 Appendix B / C.1 AES-128 single-block vector.
    func testFIPS197Vector() throws {
        let key = hex("00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F")
        let plaintext = hex("00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF")
        let ciphertext = hex("69 C4 E0 D8 6A 7B 04 30 D8 CD B7 80 70 B4 C5 5A")
        let cipher = try XCTUnwrap(ELinkSmartCipher(key: key))
        // an already-aligned block is encrypted without padding
        XCTAssertEqual(cipher.encrypt(plaintext), ciphertext)
        XCTAssertEqual(cipher.decrypt(ciphertext), plaintext)
    }

    func testDefaultKey() {
        XCTAssertEqual(ELinkSmartCipher.defaultKey.count, 16)
        XCTAssertEqual(ELinkSmartCipher.defaultKey, Array("7b7079bb69001dce".utf8))
    }

    func testInvalidKey() {
        XCTAssertNil(ELinkSmartCipher(key: hex("00 01 02")))
    }

    func testRoundTripWithPadding() {
        let cipher = ELinkSmartCipher.default
        // login plaintext is 8 bytes and must be PKCS7-padded to one 16-byte block
        let plaintext = hex("06 00 01 00 D3 F1 50 65")
        let encrypted = cipher.encrypt(plaintext)
        XCTAssertEqual(encrypted.count, 16)
        let decrypted = try? XCTUnwrap(cipher.decrypt(encrypted))
        XCTAssertEqual(decrypted?.prefix(8).map { $0 }, plaintext)
        // PKCS7: eight bytes of value 0x08
        XCTAssertEqual(decrypted?.suffix(8), [8, 8, 8, 8, 8, 8, 8, 8])
    }

    func testDecryptRejectsMisalignedLength() {
        XCTAssertNil(ELinkSmartCipher.default.decrypt(hex("00 01 02")))
    }
}
