import Foundation
import SwiftUI
import CoreBluetooth
import Bluetooth
import GATT
import ELinkSmart

@main
struct ELinkSmartApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(Store.shared)
        }
    }
}
