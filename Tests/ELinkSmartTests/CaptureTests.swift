//
//  CaptureTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/31/26.
//

import Testing
@testable import ELinkSmart

/// Tests against frames captured from a real eLinkSmart lock (model P5BF-PG) over BLE.
///
/// These vectors are taken verbatim from a PacketLogger trace and carry no secrets: the login nonce is a
/// timestamp and the acknowledgement has no payload. They prove the hardcoded key, AES-128-ECB, PKCS7
/// padding, the frame layout, and the write/notify framing all match the firmware.
struct CaptureTests {

    /// Real login write to 0x2ADD. Plaintext `06 00 01 00 <timestamp>`, PKCS7-padded, encrypts to the
    /// exact bytes seen on the wire — so the shared key and cipher are correct.
    @Test func loginWriteEncryptsToCapturedBytes() {
        let plaintext = hex("06 00 01 00 12 85 E5 6A")                         // len 6, cmd 0x01, nonce
        let captured = hex("75 CC 7B A6 4E 77 20 54 BD 8A 0A EC 82 99 AC 18")  // one AES block on the wire
        #expect(ELinkSmartCipher.default.encrypt(plaintext) == captured)
        // and the write is framed as a single 18-byte packet: 10 00 + the block
        #expect(ELinkSmartFraming.write(captured) == [hex("10 00") + captured])
    }

    /// Real unlock acknowledgement notification from 0x2ADE: decrypts to `04 00 12 00 00 00` (echoes 0x12).
    @Test func capturedAcknowledgementDecodes() throws {
        let captured = hex("10 50 DB BC 66 E6 6A 84 2A A4 18 75 B3 C5 23 A0")
        let plaintext = try #require(ELinkSmartCipher.default.decrypt(captured))
        #expect(Array(plaintext.prefix(6)) == hex("04 00 12 00 00 00"))
        let packet = try #require(ELinkSmartPacket(plaintext: plaintext))
        #expect(packet.command == .unlock)       // the ACK echoes the unlock command code
        #expect(packet.parameters == [0x00, 0x00])
    }

    /// Authenticated commands carry a proof, not the raw challenge: the first four bytes of
    /// AES-ECB(challenge). In the capture a login reply gave challenge `FE 12 00 00` and the unlock that
    /// followed used proof `7D 2E BC FB`.
    @Test func challengeProofMatchesCapture() {
        let challenge = hex("FE 12 00 00")
        let proof = Array(ELinkSmartCipher.default.encrypt(challenge).prefix(4))
        #expect(proof == hex("7D 2E BC FB"))
    }

    /// The lock sends replies as `[LE16 length][ciphertext]` in one notification (MTU 512); the
    /// reassembler recovers the ciphertext.
    @Test func capturedNotificationReassembles() {
        let cipher = hex("10 50 DB BC 66 E6 6A 84 2A A4 18 75 B3 C5 23 A0")
        let notification = hex("10 00") + cipher        // length 0x0010 = 16, then the block
        #expect(ELinkSmartFraming.reassemble([notification]) == cipher)
    }
}
