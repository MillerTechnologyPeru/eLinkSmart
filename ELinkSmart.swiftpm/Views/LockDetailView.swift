//
//  LockDetailView.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import Foundation
import SwiftUI
import ELinkSmart

/// Connects to the selected lock, logs in, and unlocks it with a six-digit password.
struct LockDetailView: View {

    @EnvironmentObject
    var store: Store

    let peripheral: NativeCentral.Peripheral

    let lock: ELinkSmartLock

    @State
    private var password = ""

    @State
    private var isBusy = false

    @State
    private var status: String?

    @State
    private var error: String?

    var body: some View {
        Form {
            connectionSection
            passwordSection
            actionsSection
        }
        .navigationTitle(lock.name)
        .onDisappear {
            let peripheral = self.peripheral
            Task { await store.disconnect(peripheral) }
        }
    }
}

private extension LockDetailView {

    var isPasswordValid: Bool {
        ELinkSmartPassword(rawValue: password) != nil
    }

    var connectionSection: some View {
        Section {
            HStack {
                Text(verbatim: peripheral.description)
                    .foregroundColor(.gray)
                    .font(.footnote)
                Spacer()
                if isBusy {
                    ProgressView()
                } else {
                    Text(store.isConnected(peripheral) ? "Connected" : "Not connected")
                        .foregroundColor(store.isConnected(peripheral) ? .green : .gray)
                }
            }
            if let status {
                Text(verbatim: status)
                    .foregroundColor(.green)
                    .font(.footnote)
            }
            if let error {
                Text(verbatim: error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
        }
    }

    var passwordSection: some View {
        Section("Password") {
            TextField("Six digits", text: $password)
                .keyboardType(.numberPad)
                .textContentType(.password)
            if isPasswordValid == false {
                Text("The password must be six digits.")
                    .foregroundColor(.gray)
                    .font(.footnote)
            }
        }
    }

    var actionsSection: some View {
        Section {
            Button("Log In") { login() }
                .disabled(isBusy)
            Button("Unlock") { unlock() }
                .disabled(isBusy || isPasswordValid == false)
        }
    }

    func login() {
        perform {
            try await store.login(peripheral)
            status = "Logged in"
        }
    }

    func unlock() {
        guard let password = ELinkSmartPassword(rawValue: password) else {
            return
        }
        perform {
            try await store.unlock(peripheral, password: password)
            status = "Unlocked"
        }
    }

    /// Runs a lock action, tracking progress and errors.
    func perform(_ action: @escaping @MainActor () async throws -> ()) {
        Task { @MainActor in
            isBusy = true
            status = nil
            defer { isBusy = false }
            do {
                try await action()
                error = nil
            }
            catch {
                self.error = String(describing: error)
                self.status = nil
            }
        }
    }
}
