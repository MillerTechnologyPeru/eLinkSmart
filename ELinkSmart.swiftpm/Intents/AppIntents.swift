//
//  AppIntents.swift
//
//
//  Created by Alsey Coleman Miller on 10/31/26.
//

import Foundation
import AppIntents

@available(iOS 16.0, *)
struct AppShortcuts: AppShortcutsProvider {

    /// The background color of the tile that Shortcuts displays for each of the app's App Shortcuts.
    static var shortcutTileColor: ShortcutTileColor {
        .navy
    }

    static var appShortcuts: [AppShortcut] {

        // Scan
        AppShortcut(
            intent: ScanIntent(),
            phrases: [
                "Scan for locks with \(.applicationName)",
            ],
            systemImageName: "arrow.clockwise"
        )

        // Unlock
        AppShortcut(
            intent: UnlockIntent(),
            phrases: [
                "Unlock \(\.$lock) with \(.applicationName)",
            ],
            systemImageName: "lock.open"
        )
    }
}
