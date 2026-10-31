//
//  Error.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import Foundation

/// eLinkSmart app errors.
public enum ELinkSmartAppError: Error {

    case bluetoothUnavailable
}

extension ELinkSmartAppError: CustomStringConvertible {

    public var description: String {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth is not available; please turn it on."
        }
    }
}
