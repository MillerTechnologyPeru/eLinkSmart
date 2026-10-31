//
//  UnlockIntent.swift
//
//
//  Created by Alsey Coleman Miller on 10/31/26.
//

import Foundation
import AppIntents
import ELinkSmart

/// Unlocks a nearby eLinkSmart lock with its six-digit password.
@available(iOS 16, *)
struct UnlockIntent: AppIntent {

    static var title: LocalizedStringResource { "Unlock lock" }

    static var description: IntentDescription {
        IntentDescription(
            "Unlock a nearby eLinkSmart lock.",
            categoryName: "Utility",
            searchKeywords: ["unlock", "open", "lock", "elinksmart", "padlock"]
        )
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Unlock \(\.$lock) with password \(\.$password)")
    }

    @Parameter(title: "Lock")
    var lock: LockEntity

    @Parameter(title: "Password", description: "The six-digit lock password.")
    var password: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let password = ELinkSmartPassword(rawValue: password) else {
            throw IntentError.invalidPassword
        }
        let store = Store.shared
        try await store.central.wait(for: .poweredOn, warning: 2, timeout: 5)
        try await store.scan(duration: 3)
        guard let peripheral = store.peripherals.first(where: { $0.value.name == lock.id })?.key else {
            throw IntentError.lockNotFound(lock.id)
        }
        try await store.unlock(peripheral, password: password)
        return .result(dialog: "Unlocked \(lock.id).")
    }
}

/// Errors surfaced to Shortcuts / Siri.
@available(iOS 16, *)
enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {

    case invalidPassword
    case lockNotFound(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidPassword:
            return "The password must be six digits."
        case let .lockNotFound(name):
            return "Couldn't find \(name) nearby."
        }
    }
}
