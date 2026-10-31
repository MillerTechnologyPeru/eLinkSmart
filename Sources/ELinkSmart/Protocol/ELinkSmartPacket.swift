//
//  ELinkSmartPacket.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

/// A decrypted eLinkSmart application frame.
///
/// The plaintext layout is, little-endian:
///
/// ```
/// [ payload length : UInt16 ] [ command : UInt16 ] [ parameters ... ]
/// ```
///
/// where `payload length` counts the bytes that follow it, i.e. `2 + parameters.count`. The frame is
/// PKCS7-padded to a 16-byte boundary before AES-ECB encryption; the length field lets the receiver
/// ignore the padding.
///
/// Examples from observed traffic:
/// - Login request: `06 00 01 00 D3 F1 50 65` — length 6, command `0x01`, a 4-byte nonce.
/// - Unlock request: `10 00 12 00 <token:4> <timestamp:4> <password:6>` — length 16, command `0x12`.
/// - Acknowledgement: `04 00 <cmd> 00 00 00` — length 4, echoes the command.
public struct ELinkSmartPacket: Equatable, Hashable, Sendable {

    /// The command code.
    public let command: Command

    /// The command-specific parameter bytes.
    public let parameters: [UInt8]

    public init(command: Command, parameters: [UInt8] = []) {
        self.command = command
        self.parameters = parameters
    }
}

public extension ELinkSmartPacket {

    /// The plaintext bytes of the frame, before encryption.
    var plaintext: [UInt8] {
        let payloadLength = UInt16(2 + parameters.count)
        return payloadLength.littleEndianBytes + command.rawValue.littleEndianBytes + parameters
    }

    /// Parses a decrypted frame, ignoring any trailing padding.
    ///
    /// Returns `nil` if the bytes are too short for the declared payload length.
    init?<C: Collection>(plaintext bytes: C) where C.Element == UInt8 {
        let bytes = [UInt8](bytes)
        guard bytes.count >= 4 else {
            return nil
        }
        let payloadLength = Int(UInt16(littleEndian: (bytes[0], bytes[1])))
        guard payloadLength >= 2, bytes.count >= 2 + payloadLength else {
            return nil
        }
        self.command = Command(rawValue: UInt16(littleEndian: (bytes[2], bytes[3])))
        self.parameters = Array(bytes[4 ..< 2 + payloadLength])
    }
}

// MARK: - Command

public extension ELinkSmartPacket {

    /// An eLinkSmart command code.
    ///
    /// Modeled as an open set (a raw `UInt16`) because the firmware defines codes `1 ... 43`, most of
    /// which are undocumented. Named cases cover the commands this library implements.
    struct Command: RawRepresentable, Equatable, Hashable, Sendable {

        public let rawValue: UInt16

        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
    }
}

public extension ELinkSmartPacket.Command {

    /// Login / challenge request. The lock replies with a random 4-byte session token.
    static var login: ELinkSmartPacket.Command { .init(rawValue: 0x01) }

    /// Unlock.
    static var unlock: ELinkSmartPacket.Command { .init(rawValue: 0x12) }

    /// Alternate unlock command used by some firmware revisions.
    static var unlockAlternate: ELinkSmartPacket.Command { .init(rawValue: 0x04) }

    /// Factory reset.
    static var factoryReset: ELinkSmartPacket.Command { .init(rawValue: 0x0C) }
}

extension ELinkSmartPacket.Command: CustomStringConvertible {

    public var description: String {
        "0x" + rawValue.toHexadecimal()
    }
}
