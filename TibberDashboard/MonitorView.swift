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
                        Text("The main circle displays your energy consumption for the current hour. The ring fills up and changes color based on your configured Critical limit:")
                        HStack {
                            Circle().fill(Color.green).frame(width: 15, height: 15)
                            Text("Normal (Below limit)")
                        }
                        HStack {
                            Circle().fill(Color.red).frame(width: 15, height: 15)
                            Text("Critical (At or above limit)")
                        }
                        Text("Inside the ring you'll see: accumulated kWh consumed, time remaining in the hour, live power draw, remaining headroom before reaching your limit, and your configured limit.")
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
                        Text("If your hour average breaches your Critical threshold, an alarm sound will play to notify you, even if the screen is black.")
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Zaptec Charger Integration")
                            .font(.headline)
                        Text("You can control your Zaptec EV charger directly from the dashboard. Go to Settings, enter your Zaptec credentials and Installation ID. From the dashboard, you can monitor charge status, resume/pause charging, and adjust the available current limit. Please note that Zaptec restricts adjusting current limits to a maximum of once every 15 minutes.")
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Philips Hue Lights")
                            .font(.headline)
                        Text("You can synchronize your Philips Hue smart lights to visually indicate your power consumption level, including flashing the lights when a critical threshold is breached. To use this, go to Settings, discover your Bridge on your local network, tap the physical button on the bridge, and link it. You can enable or disable light flashing using the toggle in Settings.")
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
    @State private var showingLogs = false
    @State private var showingCamera = false
    @State private var originalApiKey = ""
    @State private var originalHomeId = ""
    @State private var selectedLogTab = 0 // 0 for Connection, 1 for Data
    
    // Camera settings from AppStorage
    @AppStorage("cameraUrl") private var cameraUrl: String = ""
    @AppStorage("cameraUsername") private var cameraUsername: String = ""
    @AppStorage("cameraPassword") private var cameraPassword: String = ""
    
    // Inject the store reference into the App's Zaptec instance right at load.
    init(store: TibberMonitorStore) {
        self.store = store
        ZaptecManager.shared.monitorStore = store
    }
    
    var body: some View {
        ZStack {
            // Main Dashboard
            NavigationView {
                VStack(spacing: 0) {
                    if let error = store.connectionError {
                        Text(error).foregroundColor(.red)
                            .padding()
                    } else if !store.isConnected {
                        ProgressView("Connecting to Tibber...")
                            .padding()
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
                                .padding(.top, 20)
                            } else {
                                VStack(spacing: 30) {
                                    // Top: Circle
                                    circleGauge(for: data, averageKW: (data.averagePower ?? 0) / 1000.0)
                                    
                                    // Bottom: Stats
                                    statsAndLog(for: data)
                                        .padding(.horizontal)
                                    
                                    Spacer()
                                }
                                .padding(.top, 20)
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

                    // Logs button - Left aligned next to Help button
                    Button(action: {
                        showingLogs = true
                    }) {
                        Image(systemName: "terminal")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .padding(.vertical)
                            .padding(.trailing)
                    }
                    .disabled(store.isScreensaverActive)
                    
                    // Camera button - Left aligned next to Logs button
                    if !cameraUrl.isEmpty && !cameraUsername.isEmpty && !cameraPassword.isEmpty {
                        Button(action: {
                            showingCamera = true
                        }) {
                            Image(systemName: "video.circle")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .padding(.vertical)
                                .padding(.horizontal, 8)
                        }
                        .disabled(store.isScreensaverActive)
                    }

                    Spacer()
                    
                    // Screensaver button right aligned before Settings
                    Button(action: {
                        store.isScreensaverActive = true
                    }) {
                        Image(systemName: "moon.zzz")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .padding(.vertical)
                            .padding(.leading)
                    }
                    .disabled(store.isScreensaverActive)
                    
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
                    .contentShape(Rectangle()) // Ensure entire black area catches taps
                    .onTapGesture {
                        store.wakeScreen() // dismiss black overlay
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.5), value: store.isScreensaverActive)
            }
        }
        .statusBarHidden(true) // Hides the top status bar (battery, time, etc.) for a cleaner look
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
        .sheet(isPresented: $showingLogs) {
            LogsSheetView(store: store)
        }
        .sheet(isPresented: $showingCamera) {
            CameraViewSheet(cameraUrl: cameraUrl, cameraUsername: cameraUsername, cameraPassword: cameraPassword)
        }
        .onDisappear {
            store.disconnect()
            ZaptecManager.shared.stopPolling()
        }
        .onAppear {
            if ZaptecManager.shared.token == nil && !ZaptecManager.shared.username.isEmpty {
                ZaptecManager.shared.authenticate()
            }
        }
    }
    
    private func colorForAverage(_ average: Double) -> Color {
        if average >= store.criticalThreshold {
            return .red
        } else {
            return .green
        }
    }
    
    // MARK: - Subviews for Layout adaptive sizing
    
    @ViewBuilder
    private func circleGauge(for data: LiveMeasurement, averageKW: Double) -> some View {
        let metricValue = data.accumulatedConsumptionLastHour ?? 0.0
        ZStack {
            Circle()
                .stroke(lineWidth: 25.0)
                .opacity(0.2)
                .foregroundColor(colorForAverage(metricValue))
            
            Circle()
                .trim(from: 0.0, to: min(CGFloat(metricValue / store.criticalThreshold), 1.0))
                .stroke(style: StrokeStyle(lineWidth: 25.0, lineCap: .round, lineJoin: .round))
                .foregroundColor(colorForAverage(metricValue))
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear, value: metricValue)
             VStack(spacing: 4) {
                let accumulatedKWh = data.accumulatedConsumptionLastHour ?? 0.0
                Text(String(format: "%.2f kWh", accumulatedKWh))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(colorForAverage(accumulatedKWh))
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)

                let minutesRemaining = max(0, 60 - Calendar.current.component(.minute, from: Date()))
                Text("\(minutesRemaining) min left")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()
                    .frame(width: 80)
                    .padding(.vertical, 2)

                let livePowerKW = data.power / 1000.0
                Text("Live: \(String(format: "%.2f kW", livePowerKW))")
                    .font(.caption)
                    .foregroundColor(.primary)

                // Calculate remaining headroom: how many kW can we still use
                let remainingKWh = max(0, store.criticalThreshold - accumulatedKWh)
                let minutesRemainingDouble = Double(minutesRemaining) / 60.0
                let maxAverageKW = minutesRemainingDouble > 0 ? remainingKWh / minutesRemainingDouble : 0
                let headroomKW = max(0, maxAverageKW - livePowerKW)
                
                Text("Headroom: \(String(format: "%.2f kW", headroomKW))")
                    .font(.caption)
                    .foregroundColor(headroomKW > 0 ? .green : .red)
                
                Divider()
                    .frame(width: 80)
                    .padding(.vertical, 2)
                
                Text("Limit: \(String(format: "%.1f kWh", store.criticalThreshold))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 50)
        }
        .padding(20)
    }
    
    @ViewBuilder
    private func statsAndLog(for data: LiveMeasurement) -> some View {
        // Since statsAndLog is a view builder outside the main struct body, we must access ZaptecManager via its singleton to fix scope closure constraints
        let localZaptecManager = ZaptecManager.shared
        
        VStack(spacing: 16) {
            // ...existing code...
            
            // Zaptec Charger Info (Optional)
            if localZaptecManager.isAuthenticated {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "bolt.car")
                            .font(.caption)
                            .foregroundColor(localZaptecManager.isCharging ? .green : .secondary)
                        Text("Zaptec Charger")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        if localZaptecManager.isCharging {
                            Text("\(String(format: "%.2f", localZaptecManager.chargePower)) kW")
                                .font(.caption)
                                .foregroundColor(.green)
                                .bold()
                        } else {
                            Text(localZaptecManager.operationModeString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if localZaptecManager.isCharging {
                        HStack {
                            Spacer()
                            Text("\(String(format: "%.1f", localZaptecManager.voltage))V • \(String(format: "%.2f", localZaptecManager.activeCurrent))A • Session: \(String(format: "%.2f", localZaptecManager.sessionEnergy)) kWh")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else if localZaptecManager.sessionEnergy > 0 {
                        // Show session energy when finished or paused
                         HStack {
                             Spacer()
                             Text("Session: \(String(format: "%.2f", localZaptecManager.sessionEnergy)) kWh")
                                 .font(.caption2)
                                 .foregroundColor(.secondary)
                         }
                    }
                    
                    Divider()
                    
                    HStack {
                        // Current adjustment
                        // Use pending to allow multiple taps without sending a request immediately
                        let displayCurrent = localZaptecManager.pendingChargeCurrent ?? localZaptecManager.allowedChargeCurrent
                        
                        Text("\(Int(displayCurrent))A")
                            .font(.subheadline)
                            .frame(width: 40)
                        
                        let currentBinding = Binding<Double>(
                            get: { displayCurrent },
                            set: { newValue in
                                localZaptecManager.pendingChargeCurrent = newValue
                            }
                        )
                        
                        Stepper("", value: currentBinding, in: 6...localZaptecManager.maxConfiguredCurrent, step: 1)
                            .labelsHidden()
                            
                        // Show save button ONLY if pending value differs from actual allowed and we aren't loading
                        if let pending = localZaptecManager.pendingChargeCurrent, Int(pending) != Int(localZaptecManager.allowedChargeCurrent) {
                            Button(action: {
                                localZaptecManager.updateChargeCurrent(amps: Int(pending))
                            }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                            .padding(.leading, 5)
                            .transition(.opacity)
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 15).fill(Color(.systemGray6)))
            }
        }
    }
}

// MARK: - Logs Sheet View

struct LogsSheetView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store: TibberMonitorStore
    @State private var selectedLogTab = 0 // 0 for Connection, 1 for Data
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Log Type", selection: Binding(
                    get: { self.selectedLogTab },
                    set: { newValue in self.selectedLogTab = newValue }
                )) {
                    Text("Connection log").tag(0)
                    Text("Data log").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                if selectedLogTab == 0 {
                    // Connection Log
                    ScrollView {
                        ScrollViewReader { proxy in
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(store.connectionLogs.indices, id: \.self) { index in
                                    Text(store.connectionLogs[index])
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(.systemGray6))
                } else {
                    // Data Log
                    ScrollView {
                        ScrollViewReader { proxy in
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(store.dataLogs.indices, id: \.self) { index in
                                    Text(store.dataLogs[index])
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(.systemGray6))
                }
            }
            .navigationTitle("Diagnostics Logs")
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

struct CameraViewSheet: View {
    @Environment(\.dismiss) var dismiss
    let cameraUrl: String
    let cameraUsername: String
    let cameraPassword: String
    @State private var statusMessage: String? = "Connecting..."

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                // Construct the RTSP URL with credentials in format: rtsp://username:password@IP:554/stream1
                let rtspUrl = constructRtspUrl()

                if rtspUrl.isEmpty {
                    Text("Camera URL not configured")
                        .foregroundColor(.red)
                        .padding()
                } else {
                    CameraView(url: rtspUrl, statusMessage: $statusMessage)

                    // Status / error overlay
                    if let message = statusMessage {
                        VStack {
                            Spacer()
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(message.lowercased().contains("error") ? Color.red.opacity(0.85) : Color.black.opacity(0.6))
                                )
                                .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationTitle("Camera")
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
    
    private func constructRtspUrl() -> String {
        guard !cameraUrl.isEmpty, !cameraUsername.isEmpty, !cameraPassword.isEmpty else {
            return ""
        }
        
        // Remove any existing scheme or credentials from cameraUrl
        var urlPart = cameraUrl
        if let rangeOfScheme = urlPart.range(of: "rtsp://") {
            urlPart.removeSubrange(urlPart.startIndex..<rangeOfScheme.upperBound)
        }
        // Remove existing credentials if present (username:password@)
        if let atIndex = urlPart.firstIndex(of: "@") {
            urlPart.removeSubrange(urlPart.startIndex...atIndex)
        }
        
        // Construct final URL: rtsp://username:password@IP:554/stream1
        let rtspUrl = "rtsp://\(cameraUsername):\(cameraPassword)@\(urlPart)"
        return rtspUrl
    }
}
