import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Welcome to Tibber Dashboard")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.bottom, 10)
                    
                    Group {
                        Text("Getting Started")
                            .font(.headline)
                        Text("To use this app, you need a Tibber API key and the Home ID belonging to your property. Enter these in the Settings (gear icon). You can automatically fetch your Home IDs once your API key is provided.")
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Power Ring & Metrics")
                            .font(.headline)
                        Text("The main circle represents your average power usage for the current hour compared to your configured Critical limit. The ring fills up and changes color based on your setup:")
                        HStack {
                            Circle().fill(Color.green).frame(width: 15, height: 15)
                            Text("Normal")
                        }
                        HStack {
                            Circle().fill(Color.orange).frame(width: 15, height: 15)
                            Text("Warning (Nearing limit)")
                        }
                        HStack {
                            Circle().fill(Color.red).frame(width: 15, height: 15)
                            Text("Critical (Threshold breached)")
                        }
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Screensaver")
                            .font(.headline)
                        Text("To prevent screen burn-in on always-on displays, the app automatically turns the screen black after a period of inactivity. This is configurable in Settings. You can also tap anywhere on the screen while the app is active to instantly hide the dashboard, or tap the black screen to wake it back up.")
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Audio Alarms")
                            .font(.headline)
                        Text("If your hour average breaches your Warning or Critical thresholds, an alarm sound will play to notify you, even if the screen is black.")
                    }
                }
                .padding()
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct MonitorView: View {
    @ObservedObject var store: TibberMonitorStore
    @State private var showingSettings = false
    @State private var showingHelp = false
    @State private var originalApiKey = ""
    @State private var originalHomeId = ""
    
    var body: some View {
        ZStack {
            // Main Dashboard
            NavigationView {
                VStack(spacing: 30) {
                    if let error = store.connectionError {
                        Text(error).foregroundColor(.red)
                    } else if !store.isConnected {
                        ProgressView("Connecting to Tibber...")
                            .onAppear { store.connect() }
                    } else if let data = store.liveData {
                        
                        GeometryReader { geometry in
                            let isLandscape = geometry.size.width > geometry.size.height
                            
                            if isLandscape {
                                HStack(spacing: 20) {
                                    // Left Column: Circle
                                    circleGauge(for: data, averageKW: (data.averagePower ?? 0) / 1000.0)
                                        .frame(maxWidth: .infinity)
                                    
                                    // Right Column: Stats and Log
                                    statsAndLog(for: data)
                                        .frame(maxWidth: .infinity)
                                }
                                .padding(.horizontal)
                            } else {
                                VStack(spacing: 30) {
                                    // Top: Circle
                                    circleGauge(for: data, averageKW: (data.averagePower ?? 0) / 1000.0)
                                    
                                    // Bottom: Stats and Log
                                    statsAndLog(for: data)
                                        .padding(.horizontal)
                                    
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar) // Hide standard nav bar to give more space/reduce status line impact
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .disabled(store.isScreensaverActive) // disabled when screensaver is on

            // Add our own gear icon since we hid the toolbar
            VStack {
                HStack {
                    // Help button left aligned
                    Button(action: { 
                        showingHelp = true 
                    }) {
                        Image(systemName: "questionmark.circle")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .padding()
                    }
                    .disabled(store.isScreensaverActive)

                    Spacer()
                    
                    // Settings button right aligned
                    Button(action: { 
                        originalApiKey = store.apiKey
                        originalHomeId = store.homeId
                        showingSettings = true 
                    }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .padding()
                    }
                    .disabled(store.isScreensaverActive)
                }
                Spacer()
            }
            
            // OLED Screensaver Overlay
            if store.isScreensaverActive {
                Color.black
                    .ignoresSafeArea()
                    .onTapGesture {
                        store.wakeScreen() // dismiss black overlay
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.5), value: store.isScreensaverActive)
            }
        }
        .statusBarHidden(true) // Hides the top status bar (battery, time, etc.) for a cleaner look
        .onTapGesture {
            // Unconditionally toggle screensaver if already active
            if store.isScreensaverActive {
                store.wakeScreen()
            } else {
                // If not active, turn it on immediately on touch
                store.isScreensaverActive = true
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store)
                // Reload on dismiss only if credentials changed
                .onDisappear {
                    if originalApiKey != store.apiKey || originalHomeId != store.homeId {
                        store.disconnect()
                        store.connect()
                    }
                }
        }
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .onDisappear {
            store.disconnect()
        }
    }
    
    private func colorForAverage(_ average: Double) -> Color {
        if average >= store.criticalThreshold {
            return .red
        } else if average >= store.warningThreshold {
            return .orange
        } else {
            return .green
        }
    }
    
    // MARK: - Subviews for Layout adaptive sizing
    
    @ViewBuilder
    private func circleGauge(for data: LiveMeasurement, averageKW: Double) -> some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 25.0)
                .opacity(0.2)
                .foregroundColor(colorForAverage(averageKW))
            
            Circle()
                .trim(from: 0.0, to: min(CGFloat(averageKW / store.criticalThreshold), 1.0))
                .stroke(style: StrokeStyle(lineWidth: 25.0, lineCap: .round, lineJoin: .round))
                .foregroundColor(colorForAverage(averageKW))
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear, value: averageKW)
            
            VStack {
                Text(String(format: "%.2f kW", averageKW))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(colorForAverage(averageKW))

                Text("Average")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(40)
    }
    
    @ViewBuilder
    private func statsAndLog(for data: LiveMeasurement) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    let livePowerKW = data.power / 1000.0
                    Text("Live Power: \(String(format: "%.2f kW", livePowerKW))")
                        .font(.headline)
                    
                    if store.isDataStale {
                        Text("⚠️ Data is stale. Connection may be dropped.")
                            .font(.caption)
                            .foregroundColor(.red)
                            .bold()
                    }
                }
                Spacer()
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 15).fill(Color(.systemGray6)))
            
            // Mini Console Log Drawer
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "terminal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Connection Log")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.bottom, 4)
                
                ScrollView {
                    ScrollViewReader { proxy in
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(store.connectionLogs.indices, id: \.self) { index in
                                Text(store.connectionLogs[index])
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 120) // Slightly taller to use up space
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 15).fill(Color(.systemGray6)))
        }
    }
}
