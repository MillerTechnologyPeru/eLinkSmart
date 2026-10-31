//
//  PacketTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import XCTest
@testable import ELinkSmart

final class PacketTests: XCTestCase {

    func testLoginRequest() {
        let command = ELinkSmartCommand.login(nonce: 0x6550F1D3)
        let packet = command.packet
        XCTAssertEqual(packet.command, .login)
        // length 6, command 0x0001, nonce D3 F1 50 65 (little-endian)
        XCTAssertEqual(packet.plaintext, hex("06 00 01 00 D3 F1 50 65"))
    }

    func testUnlockRequest() {
        let password = ELinkSmartPassword(rawValue: "123456")!
        let command = ELinkSmartCommand.unlock(token: 0x11223344, password: password, timestamp: 0x6550F1D3)
        let packet = command.packet
        XCTAssertEqual(packet.command, .unlock)
        // length 16, command 0x0012, token, timestamp, then "123456" in ASCII
        XCTAssertEqual(packet.plaintext, hex("10 00 12 00 44 33 22 11 D3 F1 50 65 31 32 33 34 35 36"))
    }

    func testDecodeAcknowledgement() {
        // ACK: length 4, command echoed, two zero bytes — plus PKCS7 padding
        let padded = hex("04 00 12 00 00 00") + [UInt8](repeating: 0x0A, count: 10)
        let packet = ELinkSmartPacket(plaintext: padded)
        XCTAssertEqual(packet?.command, .unlock)
        XCTAssertEqual(packet?.parameters, [0x00, 0x00])
    }

    func testDecodeLoginResponse() {
        // length 0x30 = 48: command 0x0001, 4-byte challenge, then padding to 64 bytes
        var plaintext = hex("30 00 01 00 DE AD BE EF")
        plaintext += [UInt8](repeating: 0x00, count: 64 - plaintext.count)
        let packet = try? XCTUnwrap(ELinkSmartPacket(plaintext: plaintext))
        XCTAssertEqual(packet?.command, .login)
        XCTAssertEqual(packet?.parameters.prefix(4).map { $0 }, hex("DE AD BE EF"))
    }

    func testDecodeRejectsShort() {
        XCTAssertNil(ELinkSmartPacket(plaintext: hex("04 00")))
        // declares payload length 16 but only provides a few bytes
        XCTAssertNil(ELinkSmartPacket(plaintext: hex("10 00 12 00")))
    }

    func testRoundTrip() {
        let packet = ELinkSmartPacket(command: .unlock, parameters: hex("01 02 03 04"))
        let decoded = ELinkSmartPacket(plaintext: packet.plaintext)
        XCTAssertEqual(decoded, packet)
    }

    func testPasswordValidation() {
        XCTAssertNotNil(ELinkSmartPassword(rawValue: "123456"))
        XCTAssertNil(ELinkSmartPassword(rawValue: "12345"))
        XCTAssertNil(ELinkSmartPassword(rawValue: "1234567"))
        XCTAssertNil(ELinkSmartPassword(rawValue: "12345a"))
        XCTAssertEqual(ELinkSmartPassword(rawValue: "123456")?.bytes, hex("31 32 33 34 35 36"))
    }
}
