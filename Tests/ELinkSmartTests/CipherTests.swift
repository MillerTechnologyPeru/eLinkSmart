//
//  CipherTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import Testing
@testable import ELinkSmart

struct CipherTests {

    /// FIPS-197 Appendix B / C.1 AES-128 single-block vector.
    @Test func fips197Vector() throws {
        let key = hex("00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F")
        let plaintext = hex("00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF")
        let ciphertext = hex("69 C4 E0 D8 6A 7B 04 30 D8 CD B7 80 70 B4 C5 5A")
        let cipher = try #require(ELinkSmartCipher(key: key))
        // an already-aligned block is encrypted without padding
        #expect(cipher.encrypt(plaintext) == ciphertext)
        #expect(cipher.decrypt(ciphertext) == plaintext)
    }

    @Test func defaultKey() {
        #expect(ELinkSmartCipher.defaultKey.count == 16)
        #expect(ELinkSmartCipher.defaultKey == Array("7b7079bb69001dce".utf8))
    }

    @Test func invalidKey() {
        #expect(ELinkSmartCipher(key: hex("00 01 02")) == nil)
    }

    @Test func roundTripWithPadding() throws {
        let cipher = ELinkSmartCipher.default
        // login plaintext is 8 bytes and must be PKCS7-padded to one 16-byte block
        let plaintext = hex("06 00 01 00 D3 F1 50 65")
        let encrypted = cipher.encrypt(plaintext)
        #expect(encrypted.count == 16)
        let decrypted = try #require(cipher.decrypt(encrypted))
        #expect(Array(decrypted.prefix(8)) == plaintext)
        // PKCS7: eight bytes of value 0x08
        #expect(Array(decrypted.suffix(8)) == [8, 8, 8, 8, 8, 8, 8, 8])
    }

    @Test func decryptRejectsMisalignedLength() {
        #expect(ELinkSmartCipher.default.decrypt(hex("00 01 02")) == nil)
    }
}
