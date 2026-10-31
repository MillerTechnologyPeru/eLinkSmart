//
//  FramingTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import Testing
@testable import ELinkSmart

struct FramingTests {

    @Test func nibbleSwap() {
        #expect(ELinkSmartFraming.nibbleSwap(0x01) == 0x10)
        #expect(ELinkSmartFraming.nibbleSwap(0x10) == 0x01)
        #expect(ELinkSmartFraming.nibbleSwap(0x40) == 0x04)
    }

    @Test func writeSingleBlock() {
        // one 16-byte block → header 10 00, one 18-byte packet (matches captured "1000…")
        let cipher = hex("CB F5 05 01 9D 56 63 1B 5B 12 B0 78 A6 3B 18 8B")
        let frames = ELinkSmartFraming.write(cipher)
        #expect(frames.count == 1)
        #expect(frames[0] == hex("10 00") + cipher)
    }

    @Test func writeMultiBlock() {
        // 64-byte ciphertext → 4 packets, header 40 00
        let cipher = [UInt8](repeating: 0xAB, count: 64)
        let frames = ELinkSmartFraming.write(cipher)
        #expect(frames.count == 4)
        #expect(Array(frames[0].prefix(2)) == hex("40 00"))
        #expect(frames.map { $0.count } == [20, 20, 20, 6])
        // header + cipher reconstructed
        #expect(frames.flatMap { $0 } == hex("40 00") + cipher)
    }

    @Test func notificationsSingle() {
        let cipher = hex("1F B5 0B 67 82 F1 8F B5 E7 29 B4 6A 4D ED 25 1A")
        let frames = ELinkSmartFraming.notifications(cipher)
        #expect(frames.count == 1)
        // little-endian length 16, then ciphertext (matches captured "10 00 1F B5 …")
        #expect(frames[0] == hex("10 00") + cipher)
    }

    @Test func notificationsMultiAndReassemble() {
        let cipher = [UInt8](0 ..< 40)
        let frames = ELinkSmartFraming.notifications(cipher)
        // first frame: 2-byte length + 18 bytes; then 20, then 2
        #expect(frames.map { $0.count } == [20, 20, 2])
        #expect(ELinkSmartFraming.reassemble(frames) == cipher)
    }

    @Test func reassembleIncomplete() {
        // declares 40 bytes but only one 18-byte fragment present
        let partial = [hex("28 00") + [UInt8](repeating: 0x01, count: 18)]
        #expect(ELinkSmartFraming.reassemble(partial) == nil)
    }

    @Test func writeNotificationsRoundTrip() {
        let cipher = [UInt8](repeating: 0x5A, count: 32)
        // the write framing's payload (minus its 2-byte header) is the same ciphertext
        let written = ELinkSmartFraming.write(cipher).flatMap { $0 }
        #expect(Array(written.dropFirst(2)) == cipher)
        #expect(ELinkSmartFraming.reassemble(ELinkSmartFraming.notifications(cipher)) == cipher)
    }
}
