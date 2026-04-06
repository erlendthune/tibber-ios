import SwiftUI

struct MonitorView: View {
    private enum MonitorCardKind: String {
        case garageStatus
        case garageLiveFeed
        case catFeederStatus
        case catFeederLiveFeed
        case tibberTop3
        case websocketTop3
        case zaptec
    }

    @ObservedObject var store: TibberMonitorStore
    @ObservedObject private var garageDoorDetector = GarageDoorDetector.shared
    @ObservedObject private var catFeederDetector = CatFeederDetector.shared
    @State private var showingSettings = false
    @State private var showingHelp = false
    @State private var showingLogs = false
    @State private var showingCamera = false
    @State private var showingCatFeederCamera = false
    @State private var originalApiKey = ""
    @State private var originalHomeId = ""
    @State private var selectedLogTab = 0 // 0 for Connection, 1 for Data
    @State private var selectedCard: MonitorCardKind = .garageStatus
    
    // Camera settings from AppStorage
    @AppStorage("cameraUrl") private var cameraUrl: String = ""
    @AppStorage("cameraUsername") private var cameraUsername: String = ""
    @AppStorage("cameraPassword") private var cameraPassword: String = ""
    @AppStorage("catFeederCameraUrl") private var catFeederCameraUrl: String = ""
    @AppStorage("catFeederCameraUsername") private var catFeederCameraUsername: String = ""
    @AppStorage("catFeederCameraPassword") private var catFeederCameraPassword: String = ""
    
    // Inject the store reference into the App's Zaptec instance right at load.
    init(store: TibberMonitorStore) {
        self.store = store
        ZaptecManager.shared.monitorStore = store
    }

    private var hasCameraCredentials: Bool {
        !cameraUrl.isEmpty && !cameraUsername.isEmpty && !cameraPassword.isEmpty
    }

    private var hasCatFeederCameraCredentials: Bool {
        !catFeederCameraUrl.isEmpty && !catFeederCameraUsername.isEmpty && !catFeederCameraPassword.isEmpty
    }

    private var availableCardKinds: [MonitorCardKind] {
        var cards: [MonitorCardKind] = []
        if hasCameraCredentials {
            cards.append(.garageStatus)
            cards.append(.garageLiveFeed)
        }
        if hasCatFeederCameraCredentials {
            cards.append(.catFeederStatus)
            cards.append(.catFeederLiveFeed)
        }
        if store.showMonthlyTop3Usage {
            cards.append(.tibberTop3)
        }
        if store.showWebsocketTop3Usage {
            cards.append(.websocketTop3)
        }
        if ZaptecManager.shared.isAuthenticated {
            cards.append(.zaptec)
        }
        return cards
    }

    private var isLiveFeedPageSelected: Bool {
        selectedCard == .garageLiveFeed
    }

    private var isCatFeederLiveFeedPageSelected: Bool {
        selectedCard == .catFeederLiveFeed
    }

    private func normalizeCardSelection() {
        guard let first = availableCardKinds.first else {
            selectedCard = .garageStatus
            return
        }
        if !availableCardKinds.contains(selectedCard) {
            selectedCard = first
        }
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

                    if hasCatFeederCameraCredentials {
                        Button(action: {
                            showingCatFeederCamera = true
                        }) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "pawprint.circle")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                                    .padding(.vertical)
                                    .padding(.horizontal, 8)
                                if catFeederDetector.bowlState != .unknown {
                                    Circle()
                                        .fill(catFeederDetector.bowlState == .empty ? Color.red : Color.green)
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

            // Keep detector running even when user is not on the live-feed page.
            // Disable worker while live feed/sheet is visible to avoid dual RTSP sessions.
            if hasCameraCredentials && !isLiveFeedPageSelected && !showingCamera {
                GarageDoorDetectionWorker(
                    cameraUrl: cameraUrl,
                    cameraUsername: cameraUsername,
                    cameraPassword: cameraPassword
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            if hasCatFeederCameraCredentials && !isCatFeederLiveFeedPageSelected && !showingCatFeederCamera {
                CatFeederDetectionWorker(
                    cameraUrl: catFeederCameraUrl,
                    cameraUsername: catFeederCameraUsername,
                    cameraPassword: catFeederCameraPassword
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
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
        .sheet(isPresented: $showingCatFeederCamera) {
            CatFeederCameraViewSheet(
                cameraUrl: catFeederCameraUrl,
                cameraUsername: catFeederCameraUsername,
                cameraPassword: catFeederCameraPassword
            )
        }
        .onDisappear {
            store.disconnect()
            ZaptecManager.shared.stopPolling()
        }
        .onAppear {
            normalizeCardSelection()
            if ZaptecManager.shared.token == nil && !ZaptecManager.shared.username.isEmpty {
                ZaptecManager.shared.authenticate()
            }
            if store.showMonthlyTop3Usage {
                store.refreshTopUsage()
            }
        }
        .onChange(of: hasCameraCredentials) { _ in
            normalizeCardSelection()
        }
        .onChange(of: hasCatFeederCameraCredentials) { _ in
            normalizeCardSelection()
        }
        .onChange(of: store.showMonthlyTop3Usage) { _ in
            normalizeCardSelection()
        }
        .onChange(of: store.showWebsocketTop3Usage) { _ in
            normalizeCardSelection()
        }
        .onChange(of: ZaptecManager.shared.isAuthenticated) { _ in
            normalizeCardSelection()
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
    
    private var cardSetID: String {
        availableCardKinds.map(\.rawValue).joined(separator: "_")
    }

    private func statsAndLog(for data: LiveMeasurement) -> some View {
        // cardSetID forces a full TabView teardown/rebuild whenever the set of
        // visible cards changes (settings toggles, auth changes etc.). This is
        // intentional — it's the only reliable way to stop SwiftUI from showing
        // stale/wrong page content in a dynamically-sized page TabView.
        let setID = cardSetID
        return VStack(spacing: 8) {
            TabView(selection: $selectedCard) {
                ForEach(availableCardKinds, id: \.self) { card in
                    Group {
                        switch card {
                        case .garageStatus:
                            GarageDoorStatusCard()
                                .padding()
                        case .garageLiveFeed:
                            GarageDoorLiveFeedCard(
                                cameraUrl: cameraUrl,
                                cameraUsername: cameraUsername,
                                cameraPassword: cameraPassword,
                                isActive: isLiveFeedPageSelected
                            )
                            .padding()
                        case .catFeederStatus:
                            CatFeederStatusCard()
                                .padding()
                        case .catFeederLiveFeed:
                            CatFeederLiveFeedCard(
                                cameraUrl: catFeederCameraUrl,
                                cameraUsername: catFeederCameraUsername,
                                cameraPassword: catFeederCameraPassword,
                                isActive: isCatFeederLiveFeedPageSelected
                            )
                            .padding()
                        case .tibberTop3:
                            ScrollView {
                                TopThreeUsageCard(store: store)
                                    .padding()
                            }
                        case .websocketTop3:
                            ScrollView {
                                WebSocketTopThreeUsageCard(store: store)
                                    .padding()
                            }
                        case .zaptec:
                            ScrollView {
                                ZaptecControlView(manager: ZaptecManager.shared)
                                    .padding()
                            }
                        }
                    }
                    .tag(card)
                }
            }
            .id(setID)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onAppear {
                normalizeCardSelection()
                AppLog.info(.camera, "Stats TabView appeared. currentPage=\(selectedCard.rawValue)")
            }
            .onChange(of: selectedCard) { newCard in
                AppLog.info(.camera, "Stats TabView page changed to=\(newCard.rawValue)")
            }
            .onChange(of: availableCardKinds) { _ in
                normalizeCardSelection()
            }

            if availableCardKinds.count > 1 {
                HStack(spacing: 8) {
                    ForEach(availableCardKinds, id: \.self) { card in
                        Circle()
                            .fill(card == selectedCard ? Color.primary : Color.secondary.opacity(0.35))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

