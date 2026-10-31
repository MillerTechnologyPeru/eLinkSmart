//
//  ScanIntent.swift
//
//
//  Created by Alsey Coleman Miller on 10/31/26.
//

import Foundation
import AppIntents
import SwiftUI
import ELinkSmart

/// Scans for nearby eLinkSmart locks and returns their names.
@available(iOS 16, *)
struct ScanIntent: AppIntent {

    static var title: LocalizedStringResource { "Scan for locks" }

    static var description: IntentDescription {
        IntentDescription(
            "Scan for nearby eLinkSmart locks.",
            categoryName: "Utility",
            searchKeywords: ["scan", "bluetooth", "lock", "elinksmart", "padlock"]
        )
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Scan nearby locks for \(\.$duration) seconds")
    }

    @Parameter(
        title: "Duration",
        description: "Duration in seconds for scanning.",
        default: 2.0
    )
    var duration: TimeInterval

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = Store.shared
        try await store.central.wait(for: .poweredOn, warning: 2, timeout: 5)
        try await store.scan(duration: duration)
        let locks = store.peripherals.values.sorted { $0.name < $1.name }
        let names = locks.map { $0.name }
        return .result(value: names, view: view(for: locks))
    }
}

@available(iOS 16, *)
@MainActor
private extension ScanIntent {

    func view(for locks: [ELinkSmartLock]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if locks.isEmpty {
                    Text("No locks found.")
                        .padding(20)
                } else if locks.count > 3 {
                    Text("Found \(locks.count) locks.")
                        .padding(20)
                } else {
                    ForEach(locks) { lock in
                        LockRow(lock: lock)
                            .padding(8)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
