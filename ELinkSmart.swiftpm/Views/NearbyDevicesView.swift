//
//  NearbyDevicesView.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import Foundation
import SwiftUI
import ELinkSmart

struct NearbyDevicesView: View {

    @EnvironmentObject
    var store: Store

    @State
    private var scanTask: Task<Void, Never>?

    var body: some View {
        list
            .navigationTitle("eLinkSmart")
            .navigationBarItems(trailing: scanButton)
            .onAppear {
                scanTask?.cancel()
                scanTask = Task {
                    try? await store.central.wait(for: .poweredOn)
                    if store.isScanning == false {
                        toggleScan()
                    }
                }
            }
            .onDisappear {
                scanTask?.cancel()
                scanTask = nil
                if store.isScanning {
                    store.stopScanning()
                }
            }
    }
}

extension NearbyDevicesView {

    enum ScanState {
        case bluetoothUnavailable
        case scanning
        case stopScan
    }

    struct Item: Equatable, Hashable, Identifiable {

        let id: NativeCentral.Peripheral

        let lock: ELinkSmartLock
    }

    var items: [Item] {
        store.peripherals
            .lazy
            .sorted(by: { $0.value.name < $1.value.name })
            .map { Item(id: $0.key, lock: $0.value) }
    }

    var state: ScanState {
        if store.state != .poweredOn {
            return .bluetoothUnavailable
        } else if store.isScanning {
            return .scanning
        } else {
            return .stopScan
        }
    }

    var scanButton: some View {
        Button(action: toggleScan) {
            switch state {
            case .bluetoothUnavailable:
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            case .scanning:
                Image(systemName: "stop.fill")
            case .stopScan:
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    var list: some View {
        List {
            if items.isEmpty {
                Text("Searching for locks…")
                    .foregroundColor(.gray)
            }
            ForEach(items) { item in
                NavigationLink(destination: LockDetailView(peripheral: item.id, lock: item.lock)) {
                    LockRow(lock: item.lock)
                }
            }
        }
    }

    func toggleScan() {
        if store.isScanning {
            store.stopScanning()
        } else {
            scanTask?.cancel()
            scanTask = Task {
                guard await store.central.state == .poweredOn, store.isScanning == false else {
                    return
                }
                do { try await store.scan() }
                catch { store.log("⚠️ Unable to scan. \(error)") }
            }
        }
    }
}
