//
//  ELinkSmartCommand.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

/// A high-level eLinkSmart command, with the parameters needed to build its ``ELinkSmartPacket``.
public enum ELinkSmartCommand: Equatable, Hashable, Sendable {

    /// Begin a session. The 4-byte nonce is echoed in logs; the lock replies with its own session token.
    case login(nonce: UInt32)

    /// Unlock the padlock.
    ///
    /// - Parameters:
    ///   - proof: The challenge proof — the first four bytes of `AES-ECB(challenge)`, where the challenge
    ///     is the token from the lock's login reply (see ``ELinkSmartConnection``).
    ///   - password: The six-digit admin password.
    ///   - timestamp: Seconds since the Unix epoch, as sent by the app.
    case unlock(proof: UInt32, password: ELinkSmartPassword, timestamp: UInt32)
}

public extension ELinkSmartCommand {

    /// The plaintext packet for this command.
    var packet: ELinkSmartPacket {
        switch self {
        case let .login(nonce):
            return ELinkSmartPacket(command: .login, parameters: nonce.littleEndianBytes)
        case let .unlock(proof, password, timestamp):
            let parameters = proof.littleEndianBytes + timestamp.littleEndianBytes + password.bytes
            return ELinkSmartPacket(command: .unlock, parameters: parameters)
        }
    }
}

// MARK: - Password

/// A six-digit eLinkSmart admin password.
///
/// The password persists through factory resets and is the only credential the lock checks. The vendor
/// app retrieves it from a web API; this library takes it from the caller.
public struct ELinkSmartPassword: RawRepresentable, Equatable, Hashable, Sendable {

    public let rawValue: String

    /// Creates a password, or returns `nil` unless the string is exactly six decimal digits.
    public init?(rawValue: String) {
        guard rawValue.count == 6, rawValue.allSatisfy({ $0.isNumber && $0.isASCII }) else {
            return nil
        }
        self.rawValue = rawValue
    }
}

public extension ELinkSmartPassword {

    /// The password as its six ASCII bytes.
    var bytes: [UInt8] {
        Array(rawValue.utf8)
    }
}

extension ELinkSmartPassword: CustomStringConvertible {

    public var description: String {
        rawValue
    }
}
