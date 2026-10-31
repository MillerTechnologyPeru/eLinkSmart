//
//  LockEntity.swift
//
//
//  Created by Alsey Coleman Miller on 10/31/26.
//

import Foundation
import AppIntents
import ELinkSmart

/// A nearby eLinkSmart lock, for use as an App Intent parameter.
@available(iOS 16, *)
struct LockEntity: AppEntity {

    /// The lock's advertised name, which serves as its stable identifier.
    let id: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Lock" }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }

    static var defaultQuery = LockQuery()
}

/// Finds locks for App Intents: suggestions come from a short Bluetooth scan.
@available(iOS 16, *)
struct LockQuery: EntityQuery {

    func entities(for identifiers: [String]) async throws -> [LockEntity] {
        identifiers.map { LockEntity(id: $0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [LockEntity] {
        let store = Store.shared
        try? await store.central.wait(for: .poweredOn, warning: 2, timeout: 5)
        try? await store.scan(duration: 2)
        return store.peripherals.values
            .map { LockEntity(id: $0.name) }
            .sorted { $0.id < $1.id }
    }
}
