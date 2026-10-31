//
//  PacketTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import Testing
@testable import ELinkSmart

struct PacketTests {

    @Test func loginRequest() {
        let command = ELinkSmartCommand.login(nonce: 0x6550F1D3)
        let packet = command.packet
        #expect(packet.command == .login)
        // length 6, command 0x0001, nonce D3 F1 50 65 (little-endian)
        #expect(packet.plaintext == hex("06 00 01 00 D3 F1 50 65"))
    }

    @Test func unlockRequest() throws {
        let password = try #require(ELinkSmartPassword(rawValue: "123456"))
        let command = ELinkSmartCommand.unlock(token: 0x11223344, password: password, timestamp: 0x6550F1D3)
        let packet = command.packet
        #expect(packet.command == .unlock)
        // length 16, command 0x0012, token, timestamp, then "123456" in ASCII
        #expect(packet.plaintext == hex("10 00 12 00 44 33 22 11 D3 F1 50 65 31 32 33 34 35 36"))
    }

    @Test func decodeAcknowledgement() {
        // ACK: length 4, command echoed, two zero bytes — plus PKCS7 padding
        let padded = hex("04 00 12 00 00 00") + [UInt8](repeating: 0x0A, count: 10)
        let packet = ELinkSmartPacket(plaintext: padded)
        #expect(packet?.command == .unlock)
        #expect(packet?.parameters == [0x00, 0x00])
    }

    @Test func decodeLoginResponse() throws {
        // length 0x30 = 48: command 0x0001, 4-byte challenge, then padding to 64 bytes
        var plaintext = hex("30 00 01 00 DE AD BE EF")
        plaintext += [UInt8](repeating: 0x00, count: 64 - plaintext.count)
        let packet = try #require(ELinkSmartPacket(plaintext: plaintext))
        #expect(packet.command == .login)
        #expect(Array(packet.parameters.prefix(4)) == hex("DE AD BE EF"))
    }

    @Test func decodeRejectsShort() {
        #expect(ELinkSmartPacket(plaintext: hex("04 00")) == nil)
        // declares payload length 16 but only provides a few bytes
        #expect(ELinkSmartPacket(plaintext: hex("10 00 12 00")) == nil)
    }

    @Test func roundTrip() {
        let packet = ELinkSmartPacket(command: .unlock, parameters: hex("01 02 03 04"))
        let decoded = ELinkSmartPacket(plaintext: packet.plaintext)
        #expect(decoded == packet)
    }

    @Test func passwordValidation() {
        #expect(ELinkSmartPassword(rawValue: "123456") != nil)
        #expect(ELinkSmartPassword(rawValue: "12345") == nil)
        #expect(ELinkSmartPassword(rawValue: "1234567") == nil)
        #expect(ELinkSmartPassword(rawValue: "12345a") == nil)
        #expect(ELinkSmartPassword(rawValue: "123456")?.bytes == hex("31 32 33 34 35 36"))
    }
}
