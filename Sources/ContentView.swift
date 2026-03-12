import SwiftUI

struct ContentView: View {
    @StateObject private var store = TibberMonitorStore()
    
    var body: some View {
        MonitorView(store: store)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                // Keep connected but maybe handle bg states if needed
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                store.connect() // Ensure connection when active
            }
    }
}
