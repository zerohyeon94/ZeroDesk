import SwiftUI

@main
struct ZeroDeskApp: App {
    @State private var store = VaultStore()

    var body: some Scene {
        WindowGroup {
            RootView().environment(store)
        }
    }
}
