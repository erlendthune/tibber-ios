import SwiftUI

struct ContentView: View {
    @StateObject private var store = TibberMonitorStore()
    @State private var isShowingSplash = true
    
    var body: some View {
        Group {
            if isShowingSplash {
                // Custom Splash Screen
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.yellow)
                        
                        Text("Tibber Dashboard")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Connecting...")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                            .padding(.top, 20)
                    }
                }
                .onAppear {
                    // Start connection immediately
                    store.connect()
                    
                    // Dismiss splash screen after 2.5 seconds or when data is available
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation {
                            self.isShowingSplash = false
                        }
                    }
                }
            } else {
                MonitorView(store: store)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // Keep connected but maybe handle bg states if needed
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if !isShowingSplash {
                store.connect() // Ensure connection when active
            }
        }
    }
}
