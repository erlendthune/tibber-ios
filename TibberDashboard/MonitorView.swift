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
                        Text("Telegram Alerts")
                            .font(.headline)
                        Text("You can receive Telegram alerts when a critical threshold is triggered. Go to Settings and open Telegram (Optional).")
                        Text("1. Find your bot token: open BotFather in Telegram, create/select your bot, and copy the HTTP API token.")
                        Text("2. Find your chat/user ID: start a conversation with your bot, then use getUpdates (or a Telegram ID bot) to read your chat id and add it as a recipient in Settings.")
                        Text("Important: each recipient must send at least one message to tun_dashboard_bot before the bot can send alerts to that chat.")
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
    @ObservedObject private var garageDoorDetector = GarageDoorDetector.shared
    @State private var showingSettings = false
    @State private var showingHelp = false
    @State private var showingLogs = false
    @State private var showingCamera = false
    @State private var originalApiKey = ""
    @State private var originalHomeId = ""
    @State private var selectedLogTab = 0 // 0 for Connection, 1 for Data
    @State private var cardPageIndex = 0
    
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
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "video.circle")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                                    .padding(.vertical)
                                    .padding(.horizontal, 8)
                                if garageDoorDetector.doorState != .unknown {
                                    Circle()
                                        .fill(garageDoorDetector.doorState == .open ? Color.orange : Color.green)
                                        .frame(width: 10, height: 10)
                                        .offset(x: 4, y: 6)
                                }
                            }
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
            if store.showMonthlyTop3Usage {
                store.refreshTopUsage()
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
        TabView(selection: $cardPageIndex) {
            // Camera Card
            if !cameraUrl.isEmpty && !cameraUsername.isEmpty && !cameraPassword.isEmpty {
                ScrollView {
                    GarageDoorCameraCard(
                        cameraUrl: cameraUrl,
                        cameraUsername: cameraUsername,
                        cameraPassword: cameraPassword
                    )
                    .padding()
                }
                .tag(0)
            }

            // Tibber API Top 3 Card
            if store.showMonthlyTop3Usage {
                ScrollView {
                    TopThreeUsageCard(store: store)
                        .padding()
                }
                .tag(1)
            }

            // WebSocket Top 3 Card
            if store.showWebsocketTop3Usage {
                ScrollView {
                    WebSocketTopThreeUsageCard(store: store)
                        .padding()
                }
                .tag(2)
            }

            // Zaptec Charger Card
            if ZaptecManager.shared.isAuthenticated {
                ScrollView {
                    ZaptecControlView(manager: ZaptecManager.shared)
                        .padding()
                }
                .tag(3)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .environmentObject(garageDoorDetector)
    }
}

struct GarageDoorCameraCard: View {
    let cameraUrl: String
    let cameraUsername: String
    let cameraPassword: String
    @EnvironmentObject var detector: GarageDoorDetector
    @State private var statusMessage: String? = "Connecting..."
    @AppStorage("garageDoorDetectionInterval") private var detectionInterval: Int = 5
    @AppStorage("cameraNetworkCachingMs") private var cameraNetworkCachingMs: Int = 1000
    @AppStorage("cameraLiveCachingMs") private var cameraLiveCachingMs: Int = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "door.garage.closed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Garage Door")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if detector.doorState != .unknown {
                    Text(detector.doorState == .open ? "OPEN" : "CLOSED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(detector.doorState == .open ? .orange : .green)
                } else if detector.isEnabled {
                    Text("DETECTING")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
            }

            let rtspUrl = constructRtspUrl()
            if rtspUrl.isEmpty {
                Text("Camera URL not configured")
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                CameraView(
                    url: rtspUrl,
                    statusMessage: $statusMessage,
                    onSnapshot: { path in detector.analyze(imagePath: path) },
                    snapshotInterval: TimeInterval(max(1, detectionInterval)),
                    networkCachingMs: cameraNetworkCachingMs,
                    liveCachingMs: cameraLiveCachingMs
                )
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(alignment: .center, spacing: 10) {
                    Group {
                        if let image = detector.lastSnapshot {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ZStack {
                                Color(.systemGray5)
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(width: 84, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(detector.doorState == .unknown ? "State: Unknown" : "State: \(detector.doorState == .open ? "Open" : "Closed")")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("Confidence: \(Int(detector.confidence * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let date = detector.lastSnapshotDate {
                            Text("Updated: \(date.formatted(date: .omitted, time: .standard))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Updated: --")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 15).fill(Color(.systemGray6)))
    }

    private func constructRtspUrl() -> String {
        guard !cameraUrl.isEmpty, !cameraUsername.isEmpty, !cameraPassword.isEmpty else {
            return ""
        }
        var urlPart = cameraUrl
        if let rangeOfScheme = urlPart.range(of: "rtsp://") {
            urlPart.removeSubrange(urlPart.startIndex..<rangeOfScheme.upperBound)
        }
        if let atIndex = urlPart.firstIndex(of: "@") {
            urlPart.removeSubrange(urlPart.startIndex...atIndex)
        }
        return "rtsp://\(cameraUsername):\(cameraPassword)@\(urlPart)"
    }
}

struct TopThreeUsageCard: View {
    @ObservedObject var store: TibberMonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Top 3 Hours This Month")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if store.isFetchingTopUsage {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Text("Source: Tibber API")
                .font(.caption2)
                .foregroundColor(.secondary)

            if let error = store.topUsageError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else if store.topUsageHours.isEmpty {
                Text("No usage data available yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(store.topUsageHours.enumerated()), id: \.element.id) { index, hour in
                    HStack {
                        Text("#\(index + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .leading)

                        Text(formatHour(hour.from))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(hour.consumption ?? 0, specifier: "%.2f") kWh")
                            .font(.caption)
                            .bold()
                    }
                }

                Divider()

                HStack {
                    Text("Average")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(store.topUsageAverage ?? 0, specifier: "%.2f") kWh")
                        .font(.subheadline)
                        .bold()
                }

                if let updatedAt = store.topUsageLastUpdated {
                    Text("Updated: \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 15).fill(Color(.systemGray6)))
    }

    private func formatHour(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        if let date = parser.date(from: iso) ?? fallback.date(from: iso) {
            return formatter.string(from: date)
        }

        return iso
    }
}

struct WebSocketTopThreeUsageCard: View {
    @ObservedObject var store: TibberMonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Top 3 Hours This Month (WebSocket)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            Text("Source: WebSocket")
                .font(.caption2)
                .foregroundColor(.secondary)

            if store.websocketTopUsageHours.isEmpty {
                Text("Collecting live data...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(store.websocketTopUsageHours.enumerated()), id: \.element.id) { index, hour in
                    HStack {
                        Text("#\(index + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .leading)

                        Text(formatHour(hour.from))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(hour.consumption ?? 0, specifier: "%.2f") kWh")
                            .font(.caption)
                            .bold()
                    }
                }

                Divider()

                HStack {
                    Text("Average")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(store.websocketTopUsageAverage ?? 0, specifier: "%.2f") kWh")
                        .font(.subheadline)
                        .bold()
                }

                if let updatedAt = store.websocketTopUsageLastUpdated {
                    Text("Updated: \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 15).fill(Color(.systemGray6)))
    }

    private func formatHour(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        if let date = parser.date(from: iso) ?? fallback.date(from: iso) {
            return formatter.string(from: date)
        }

        return iso
    }
}

struct ZaptecControlView: View {
    @ObservedObject var manager: ZaptecManager

    private var displayCurrent: Double {
        manager.pendingChargeCurrent ?? manager.allowedChargeCurrent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bolt.car")
                    .font(.caption)
                    .foregroundColor(manager.isCharging ? .green : .secondary)
                Text("Zaptec Charger")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()

                if !manager.isChargerReachable {
                    Label("Connection lost", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if manager.isCharging {
                    Text("\(String(format: "%.2f", manager.chargePower)) kW")
                        .font(.caption)
                        .foregroundColor(.green)
                        .bold()
                } else {
                    Text(manager.operationModeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if manager.isCharging {
                HStack {
                    Spacer()
                    Text("\(String(format: "%.1f", manager.voltage))V • \(String(format: "%.2f", manager.activeCurrent))A • Session: \(String(format: "%.2f", manager.sessionEnergy)) kWh")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if manager.sessionEnergy > 0 {
                HStack {
                    Spacer()
                    Text("Session: \(String(format: "%.2f", manager.sessionEnergy)) kWh")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            HStack {
                Text("\(Int(displayCurrent))A")
                    .font(.subheadline)
                    .frame(width: 40)

                Stepper("", value: Binding(
                    get: { displayCurrent },
                    set: { manager.pendingChargeCurrent = $0 }
                ), in: 6...manager.maxConfiguredCurrent, step: 1)
                .labelsHidden()

                if let pending = manager.pendingChargeCurrent, Int(pending) != Int(manager.allowedChargeCurrent) {
                    Button(action: {
                        manager.updateChargeCurrent(amps: Int(pending))
                    }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .padding(.leading, 5)
                    .transition(.opacity)

                    Button(action: {
                        manager.pendingChargeCurrent = nil
                    }) {
                        Image(systemName: "xmark.circle")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 2)
                    .transition(.opacity)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 15).fill(Color(.systemGray6)))
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
    @ObservedObject private var detector = GarageDoorDetector.shared
    @AppStorage("garageDoorDetectionInterval") private var detectionInterval: Int = 5
    @AppStorage("cameraNetworkCachingMs") private var cameraNetworkCachingMs: Int = 1000
    @AppStorage("cameraLiveCachingMs") private var cameraLiveCachingMs: Int = 1000

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
                    CameraView(
                        url: rtspUrl,
                        statusMessage: $statusMessage,
                        onSnapshot: nil,
                        snapshotInterval: TimeInterval(detectionInterval),
                        networkCachingMs: cameraNetworkCachingMs,
                        liveCachingMs: cameraLiveCachingMs
                    )

                    // Door state overlay — top of screen
                    if detector.doorState != .unknown {
                        VStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(detector.doorState == .open ? Color.orange : Color.green)
                                    .frame(width: 10, height: 10)
                                Text(detector.doorState == .open ? "Open" : "Closed")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text(String(format: "%.0f%%", detector.confidence * 100))
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                            .padding(.top, 8)
                            Spacer()
                        }
                    }

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
