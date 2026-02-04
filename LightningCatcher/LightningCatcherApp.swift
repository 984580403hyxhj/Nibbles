import SwiftUI

@main
struct LightningCatcherApp: App {
    @StateObject private var dataStore = DataStore()
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            KnowledgeFeedView()
                .environmentObject(dataStore)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                let poller = TaskPoller(dataStore: dataStore)
                dataStore.processSharedURLs(using: poller)
            }
        }
    }
}
