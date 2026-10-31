import SwiftUI
import ELinkSmart

struct ContentView: View {

    @EnvironmentObject
    var store: Store

    var body: some View {
        NavigationView {
            NearbyDevicesView()
        }
        .navigationViewStyle(.stack)
    }
}
