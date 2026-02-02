import SwiftUI

struct ContentView: View {
    @StateObject var dataStore = DataStore()
    
    var body: some View {
        KnowledgeFeedView()
            .environmentObject(dataStore)
    }
}
