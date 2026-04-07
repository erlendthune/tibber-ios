import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var store: TibberMonitorStore
    @StateObject private var hueManager = HueManager.shared
    @StateObject private var zaptecManager = ZaptecManager.shared
    @StateObject private var telegramManager = TelegramManager.shared

    // Camera settings: use @State to prevent immediate saving during editing
    @State private var cameraUrl: String = UserDefaults.standard.string(forKey: "cameraUrl") ?? ""
    @State private var cameraUsername: String = UserDefaults.standard.string(forKey: "cameraUsername") ?? ""
    @State private var cameraPassword: String = UserDefaults.standard.string(forKey: "cameraPassword") ?? ""
    @State private var cameraNetworkCachingMs: Int = UserDefaults.standard.integer(forKey: "cameraNetworkCachingMs") == 0 ? 1000 : UserDefaults.standard.integer(forKey: "cameraNetworkCachingMs")
    @State private var cameraLiveCachingMs: Int = UserDefaults.standard.integer(forKey: "cameraLiveCachingMs") == 0 ? 1000 : UserDefaults.standard.integer(forKey: "cameraLiveCachingMs")
    @State private var learnModeEnabled: Bool = UserDefaults.standard.bool(forKey: "garageDoorLearnModeEnabled")
    @State private var learnModeIntervalMinutes: Int = UserDefaults.standard.integer(forKey: "garageDoorLearnModeIntervalMinutes") == 0 ? 15 : UserDefaults.standard.integer(forKey: "garageDoorLearnModeIntervalMinutes")
    @State private var detectionEnabled: Bool = UserDefaults.standard.bool(forKey: "garageDoorDetectionEnabled")
    @State private var detectionInterval: Int = UserDefaults.standard.integer(forKey: "garageDoorDetectionInterval") == 0 ? 5 : UserDefaults.standard.integer(forKey: "garageDoorDetectionInterval")
    @State private var confidenceThreshold: Double = UserDefaults.standard.double(forKey: "garageDoorConfidenceThreshold") == 0 ? 0.75 : UserDefaults.standard.double(forKey: "garageDoorConfidenceThreshold")
    @State private var alertRepeatMinutes: Int = UserDefaults.standard.integer(forKey: "garageDoorAlertRepeatMinutes") == 0 ? 5 : UserDefaults.standard.integer(forKey: "garageDoorAlertRepeatMinutes")
    @State private var catFeederCameraUrl: String = UserDefaults.standard.string(forKey: "catFeederCameraUrl") ?? ""
    @State private var catFeederCameraUsername: String = UserDefaults.standard.string(forKey: "catFeederCameraUsername") ?? ""
    @State private var catFeederCameraPassword: String = UserDefaults.standard.string(forKey: "catFeederCameraPassword") ?? ""
    @State private var catFeederCameraNetworkCachingMs: Int = UserDefaults.standard.integer(forKey: "catFeederCameraNetworkCachingMs") == 0 ? 1000 : UserDefaults.standard.integer(forKey: "catFeederCameraNetworkCachingMs")
    @State private var catFeederCameraLiveCachingMs: Int = UserDefaults.standard.integer(forKey: "catFeederCameraLiveCachingMs") == 0 ? 1000 : UserDefaults.standard.integer(forKey: "catFeederCameraLiveCachingMs")
    @State private var catFeederLearnModeEnabled: Bool = UserDefaults.standard.bool(forKey: "catFeederLearnModeEnabled")
    @State private var catFeederLearnModeIntervalMinutes: Int = UserDefaults.standard.integer(forKey: "catFeederLearnModeIntervalMinutes") == 0 ? 15 : UserDefaults.standard.integer(forKey: "catFeederLearnModeIntervalMinutes")
    @State private var catFeederDetectionEnabled: Bool = UserDefaults.standard.bool(forKey: "catFeederDetectionEnabled")
    @State private var catFeederDetectionInterval: Int = UserDefaults.standard.integer(forKey: "catFeederDetectionInterval") == 0 ? 5 : UserDefaults.standard.integer(forKey: "catFeederDetectionInterval")
    @State private var catFeederConfidenceThreshold: Double = UserDefaults.standard.double(forKey: "catFeederConfidenceThreshold") == 0 ? 0.75 : UserDefaults.standard.double(forKey: "catFeederConfidenceThreshold")
    @State private var catFeederAlertRepeatMinutes: Int = UserDefaults.standard.integer(forKey: "catFeederAlertRepeatMinutes") == 0 ? 30 : UserDefaults.standard.integer(forKey: "catFeederAlertRepeatMinutes")
    
    @AppStorage("log.enabled.camera") private var logCamera: Bool = true
    @AppStorage("log.enabled.tibber") private var logTibber: Bool = false
    @AppStorage("log.enabled.zaptec") private var logZaptec: Bool = false
    @AppStorage("log.enabled.hue") private var logHue: Bool = false
    @AppStorage("log.enabled.telegram") private var logTelegram: Bool = false
    
    @State private var isApiKeyVisible: Bool = false
    @State private var isHomeIdVisible: Bool = false
    @State private var isCameraPasswordVisible: Bool = false
    @State private var isCatFeederCameraPasswordVisible: Bool = false
    @State private var isZaptecPasswordVisible: Bool = false
    @State private var isTelegramTokenVisible: Bool = false
    @State private var showAddTelegramRecipient: Bool = false
    @State private var newRecipientName: String = ""
    @State private var newRecipientChatId: String = ""
    @State private var showTelegramTestResult: Bool = false
    @State private var telegramTestResultTitle: String = ""
    @State private var telegramTestResultMessage: String = ""
    @State private var originalSnapshot: SettingsSnapshot?

    private struct SettingsSnapshot: Equatable {
        var apiKey: String
        var homeId: String
        var criticalThreshold: Double
        var breachCount: Int
        var idleTimerMinutes: Double
        var showMonthlyTop3Usage: Bool
        var showWebsocketTop3Usage: Bool

        var cameraUrl: String
        var cameraUsername: String
        var cameraPassword: String
        var cameraNetworkCachingMs: Int
        var cameraLiveCachingMs: Int
        var learnModeEnabled: Bool
        var learnModeIntervalMinutes: Int
        var catFeederCameraUrl: String
        var catFeederCameraUsername: String
        var catFeederCameraPassword: String
        var catFeederCameraNetworkCachingMs: Int
        var catFeederCameraLiveCachingMs: Int
        var catFeederLearnModeEnabled: Bool
        var catFeederLearnModeIntervalMinutes: Int

        var detectionEnabled: Bool
        var detectionInterval: Int
        var confidenceThreshold: Double
        var alertRepeatMinutes: Int
        var catFeederDetectionEnabled: Bool
        var catFeederDetectionInterval: Int
        var catFeederConfidenceThreshold: Double
        var catFeederAlertRepeatMinutes: Int

        var logCamera: Bool
        var logTibber: Bool
        var logZaptec: Bool
        var logHue: Bool
        var logTelegram: Bool

        var zaptecUsername: String
        var zaptecPassword: String
        var zaptecInstallationId: String
        var zaptecMaxConfiguredCurrent: Double
        var zaptecActiveChargerId: String

        var hueEnabled: Bool
        var hueBridgeIP: String
        var hueUsername: String

        var telegramEnabled: Bool
        var telegramBotToken: String
        var telegramRecipientsData: Data?
    }

    private var hasUnsavedChanges: Bool {
        guard let originalSnapshot else { return false }
        return currentSnapshot() != originalSnapshot
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Authentication")) {
                    HStack {
                        if isApiKeyVisible {
                            TextField("API Key", text: $store.apiKey)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("API Key", text: $store.apiKey)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        Button(action: {
                            isApiKeyVisible.toggle()
                        }) {
                            Image(systemName: isApiKeyVisible ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        if isHomeIdVisible {
                            TextField("Home ID", text: $store.homeId)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("Home ID", text: $store.homeId)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        Button(action: {
                            isHomeIdVisible.toggle()
                        }) {
                            Image(systemName: isHomeIdVisible ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: {
                        store.fetchHomes()
                    }) {
                        HStack {
                            Text("Fetch Available Homes")
                            if store.isFetchingHomes {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }

                    if let error = store.fetchHomesError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    if !store.availableHomes.isEmpty {
                        Picker("Select Home", selection: $store.homeId) {
                            ForEach(store.availableHomes) { home in
                                let name = home.appNickname ?? home.address?.address1 ?? home.id
                                Text(name).tag(home.id)
                            }
                        }
                    }
                }
                
                Section(header: Text("Tariff / Thresholds")) {
                    Stepper(value: $store.criticalThreshold, in: 1.0...25.0, step: 0.5) {
                        Text("Critical Limit: \(store.criticalThreshold, specifier: "%.1f") kWh")
                    }
                }

                Section(header: Text("Display")) {
                    Stepper(value: $store.idleTimerMinutes, in: 1.0...60.0, step: 1.0) {
                        Text("Screensaver Timeout: \(Int(store.idleTimerMinutes)) min")
                    }
                }
                
                Section(header: Text("Stats (Current Month)")) {
                    HStack {
                        Text("Threshold Breaches")
                        Spacer()
                        Text("\(store.breachCount)")
                            .foregroundColor(.red)
                    }
                    
                    Button("Reset Counter") {
                        store.breachCount = 0
                    }
                    .foregroundColor(.red)
                }

                Section(
                    header: Text("Top 3 Hours (Current Month)"),
                    footer: Text("You can show one or both cards on the dashboard. Tibber API card fetches historical values. WebSocket card tracks top hours continuously while this app is running.")
                ) {
                    Toggle("Show Tibber API Card", isOn: $store.showMonthlyTop3Usage)
                    Toggle("Show WebSocket Card", isOn: $store.showWebsocketTop3Usage)

                    if store.showMonthlyTop3Usage {
                        Button(action: {
                            store.refreshTopUsage(force: true)
                        }) {
                            HStack {
                                Text("Refresh Top 3 Now")
                                if store.isFetchingTopUsage {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }

                        if let average = store.topUsageAverage {
                            Text("Average of top \(store.topUsageHours.count): \(average, specifier: "%.2f") kWh")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let updated = store.topUsageLastUpdated {
                            Text("Updated: \(updated.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let error = store.topUsageError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    if store.showWebsocketTop3Usage {
                        if let average = store.websocketTopUsageAverage {
                            Text("WebSocket average of top \(store.websocketTopUsageHours.count): \(average, specifier: "%.2f") kWh")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("WebSocket card is collecting data continuously from live measurements.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let updated = store.websocketTopUsageLastUpdated {
                            Text("WebSocket updated: \(updated.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("Garage Camera (Optional)"), footer: Text("Provide RTSP URL and credentials to take a snapshot every 5 minutes.")) {
                    TextField("RTSP URL (rtsp://ip:port/stream)", text: $cameraUrl)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    TextField("Username", text: $cameraUsername)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    HStack {
                        if isCameraPasswordVisible {
                            TextField("Password", text: $cameraPassword)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("Password", text: $cameraPassword)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        Button(action: {
                            isCameraPasswordVisible.toggle()
                        }) {
                            Image(systemName: isCameraPasswordVisible ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }

                    Stepper(
                        "Network Buffer: \(cameraNetworkCachingMs) ms",
                        value: $cameraNetworkCachingMs,
                        in: 250...3000,
                        step: 250
                    )

                    Stepper(
                        "Live Buffer: \(cameraLiveCachingMs) ms",
                        value: $cameraLiveCachingMs,
                        in: 250...3000,
                        step: 250
                    )

                    Button("Use Stable Stream Defaults") {
                        cameraNetworkCachingMs = 1000
                        cameraLiveCachingMs = 1000
                    }
                }

                Section(
                    header: Text("Garage Camera Learn Mode"),
                    footer: Text("When enabled, the app saves camera snapshots to your Photos library at the selected interval. Use these images to build a better training dataset for the garage door model.")
                ) {
                    Toggle("Enable Learn Mode", isOn: $learnModeEnabled)

                    Stepper(
                        "Save snapshot every \(learnModeIntervalMinutes) min",
                        value: $learnModeIntervalMinutes,
                        in: 1...240,
                        step: 1
                    )
                    .disabled(!learnModeEnabled)
                }
                
                Section(
                    header: Text("Garage Door Detection (Optional)"),
                    footer: Text("Analyzes snapshots from the live camera card in the monitor view. When the door stays open, alerts repeat at the configured interval.")
                ) {
                    Toggle("Enable Detection", isOn: $detectionEnabled)
                    Stepper(
                        "Check every \(detectionInterval) s",
                        value: $detectionInterval,
                        in: 1...30,
                        step: 1
                    )
                    .disabled(!detectionEnabled)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confidence threshold: \(Int(confidenceThreshold * 100))%")
                        Slider(value: $confidenceThreshold, in: 0.5...1.0, step: 0.05)
                    }
                    .disabled(!detectionEnabled)

                    Stepper(
                        "Repeat open alert every \(alertRepeatMinutes) min",
                        value: $alertRepeatMinutes,
                        in: 1...120,
                        step: 1
                    )
                    .disabled(!detectionEnabled)
                }

                Section(header: Text("Cat Feeder Camera (Optional)"), footer: Text("Provide RTSP URL and credentials to monitor whether the feeder bowl is empty.")) {
                    TextField("RTSP URL (rtsp://ip:port/stream)", text: $catFeederCameraUrl)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Username", text: $catFeederCameraUsername)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    HStack {
                        if isCatFeederCameraPasswordVisible {
                            TextField("Password", text: $catFeederCameraPassword)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("Password", text: $catFeederCameraPassword)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        Button(action: {
                            isCatFeederCameraPasswordVisible.toggle()
                        }) {
                            Image(systemName: isCatFeederCameraPasswordVisible ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }

                    Stepper(
                        "Network Buffer: \(catFeederCameraNetworkCachingMs) ms",
                        value: $catFeederCameraNetworkCachingMs,
                        in: 250...3000,
                        step: 250
                    )

                    Stepper(
                        "Live Buffer: \(catFeederCameraLiveCachingMs) ms",
                        value: $catFeederCameraLiveCachingMs,
                        in: 250...3000,
                        step: 250
                    )

                    Button("Use Stable Stream Defaults") {
                        catFeederCameraNetworkCachingMs = 1000
                        catFeederCameraLiveCachingMs = 1000
                    }
                }

                Section(
                    header: Text("Cat Feeder Camera Learn Mode"),
                    footer: Text("When enabled, the app saves feeder snapshots to your Photos library at the selected interval so you can improve your training dataset.")
                ) {
                    Toggle("Enable Learn Mode", isOn: $catFeederLearnModeEnabled)

                    Stepper(
                        "Save snapshot every \(catFeederLearnModeIntervalMinutes) min",
                        value: $catFeederLearnModeIntervalMinutes,
                        in: 1...240,
                        step: 1
                    )
                    .disabled(!catFeederLearnModeEnabled)
                }

                Section(
                    header: Text("Cat Feeder Detection (Optional)"),
                    footer: Text("Analyzes feeder snapshots and classifies bowl state as empty or not empty. When empty persists, reminders repeat at the configured interval.")
                ) {
                    Toggle("Enable Detection", isOn: $catFeederDetectionEnabled)
                    Stepper(
                        "Check every \(catFeederDetectionInterval) s",
                        value: $catFeederDetectionInterval,
                        in: 1...30,
                        step: 1
                    )
                    .disabled(!catFeederDetectionEnabled)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confidence threshold: \(Int(catFeederConfidenceThreshold * 100))%")
                        Slider(value: $catFeederConfidenceThreshold, in: 0.5...1.0, step: 0.05)
                    }
                    .disabled(!catFeederDetectionEnabled)

                    Stepper(
                        "Repeat empty alert every \(catFeederAlertRepeatMinutes) min",
                        value: $catFeederAlertRepeatMinutes,
                        in: 1...120,
                        step: 1
                    )
                    .disabled(!catFeederDetectionEnabled)
                }

                Section(
                    header: Text("Diagnostics Logging"),
                    footer: Text("Enable only the subsystems you want to inspect. Camera logs are useful for snapshot/detection troubleshooting.")
                ) {
                    Toggle("Camera", isOn: $logCamera)
                    Toggle("Tibber", isOn: $logTibber)
                    Toggle("Zaptec", isOn: $logZaptec)
                    Toggle("Hue", isOn: $logHue)
                    Toggle("Telegram", isOn: $logTelegram)

                    Button("Focus Camera Logging") {
                        logCamera = true
                        logTibber = false
                        logZaptec = false
                        logHue = false
                        logTelegram = false
                    }
                }

                Section(header: Text("Zaptec Charger (Optional)"), footer: Text("Provide credentials to display basic charger state on the dashboard.")) {
                    TextField("Email", text: $zaptecManager.username)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .disableAutocorrection(true)
                    
                    HStack {
                        if isZaptecPasswordVisible {
                            TextField("Password", text: $zaptecManager.password)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("Password", text: $zaptecManager.password)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        Button(action: {
                            isZaptecPasswordVisible.toggle()
                        }) {
                            Image(systemName: isZaptecPasswordVisible ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Installation ID")
                            .frame(width: 120, alignment: .leading)
                        TextField("Guid format", text: $zaptecManager.installationId)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    HStack {
                        Text("Max Current (A)")
                            .frame(width: 120, alignment: .leading)
                        Stepper("\(Int(zaptecManager.maxConfiguredCurrent)) A", value: $zaptecManager.maxConfiguredCurrent, in: 6...32, step: 1)
                    }
                    
                    Button(action: {
                        zaptecManager.authenticate()
                    }) {
                        HStack {
                            Text(zaptecManager.isAuthenticated ? "Re-authenticate" : "Authenticate")
                            Spacer()
                            if zaptecManager.isAuthenticated {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            }
                        }
                    }
                    
                    if let error = zaptecManager.authError {
                        VStack(alignment: .leading) {
                            Text("Setup Error:")
                                .foregroundColor(.red)
                                .font(.caption)
                                .bold()
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    if zaptecManager.isAuthenticated && !zaptecManager.installationId.isEmpty {
                        Button(action: {
                            zaptecManager.fetchChargers()
                            zaptecManager.fetchInstallationDetails() // Add diagnostic network call
                        }) {
                            HStack {
                                Text("Fetch Chargers from Installation")
                                if zaptecManager.isFetchingChargers {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        
                        if let error = zaptecManager.fetchChargersError {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        if !zaptecManager.availableChargers.isEmpty {
                            Picker("Select Charger", selection: $zaptecManager.activeChargerId) {
                                ForEach(zaptecManager.availableChargers) { charger in
                                    let displayName = charger.Name ?? charger.DeviceId ?? charger.Id
                                    Text(displayName).tag(charger.Id)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Philips Hue (Optional)"), footer: Text("Connect to your Philips Hue Bridge to flash lights on critical alerts.")) {
                    Toggle("Enable Light Flashing", isOn: $hueManager.isEnabled)
                    
                    HStack {
                        Text("Bridge IP")
                        Spacer()
                        TextField("Not discovered", text: $hueManager.bridgeIP)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    
                    HStack {
                        Text("Username")
                        Spacer()
                        Text(hueManager.username.isEmpty ? "Not linked" : "Linked")
                            .foregroundColor(hueManager.username.isEmpty ? .secondary : .green)
                    }
                    
                    if hueManager.username.isEmpty {
                        Button(action: {
                            if hueManager.bridgeIP.isEmpty {
                                hueManager.discoverBridge()
                            } else {
                                // Link must be pressed BEFORE calling linkBridge()
                                hueManager.linkBridge()
                            }
                        }) {
                            if hueManager.isDiscovering {
                                Text("Discovering Bridge...")
                            } else if hueManager.bridgeIP.isEmpty {
                                Text("Discover Bridge")
                            } else if hueManager.isLinking {
                                Text("Press button on Bridge then tap again...")
                                    .foregroundColor(.orange)
                            } else {
                                Text("Link Bridge")
                            }
                        }
                        
                        if let error = hueManager.discoveryError ?? hueManager.linkError {
                            Text("Error: \(error)")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }

                Section(
                    header: Text("Telegram (Optional)"),
                    footer: Text("Send a Telegram message to each recipient when a critical alert is triggered. Setup: 1) Use BotFather to create/select your bot and copy the HTTP API token. 2) Start a chat with tun_dashboard_bot and send at least one message. 3) Use getUpdates (or a Telegram ID bot) to find your chat ID, then add it as a recipient.")
                ) {
                    Toggle("Enable Telegram Alerts", isOn: $telegramManager.isEnabled)

                    HStack {
                        if isTelegramTokenVisible {
                            TextField("Bot Token", text: $telegramManager.botToken)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("Bot Token", text: $telegramManager.botToken)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        Button(action: {
                            isTelegramTokenVisible.toggle()
                        }) {
                            Image(systemName: isTelegramTokenVisible ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }

                    ForEach(telegramManager.chatRecipients) { recipient in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(recipient.name)
                                Text(recipient.chatId)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: {
                                telegramManager.sendTestMessage(to: recipient) { result in
                                    switch result {
                                    case .success:
                                        telegramTestResultTitle = "Test Sent"
                                        telegramTestResultMessage = "Test message sent to \(recipient.name)."
                                    case .failure(let error):
                                        telegramTestResultTitle = "Test Failed"
                                        telegramTestResultMessage = "Could not send test to \(recipient.name): \(error)"
                                    }
                                    showTelegramTestResult = true
                                }
                            }) {
                                Label("Test", systemImage: "paperplane")
                                    .font(.caption)
                            }
                        }
                    }
                    .onDelete { offsets in
                        telegramManager.removeRecipients(at: offsets)
                    }

                    Button(action: {
                        newRecipientName = ""
                        newRecipientChatId = ""
                        showAddTelegramRecipient = true
                    }) {
                        Label("Add Recipient", systemImage: "plus.circle")
                    }
                }
            } // Form
            .alert("Add Telegram Recipient", isPresented: $showAddTelegramRecipient) {
                TextField("Name", text: $newRecipientName)
                TextField("Chat ID", text: $newRecipientChatId)
                    .keyboardType(.numbersAndPunctuation)
                Button("Add") {
                    let trimmedName = newRecipientName.trimmingCharacters(in: .whitespaces)
                    let trimmedId = newRecipientChatId.trimmingCharacters(in: .whitespaces)
                    if !trimmedName.isEmpty && !trimmedId.isEmpty {
                        telegramManager.addRecipient(name: trimmedName, chatId: trimmedId)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a display name and the Telegram chat ID.")
            }
            .alert(telegramTestResultTitle, isPresented: $showTelegramTestResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(telegramTestResultMessage)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasUnsavedChanges)
            .onAppear {
                originalSnapshot = currentSnapshot()
                if store.showMonthlyTop3Usage {
                    store.refreshTopUsage()
                }
            }
            .onChange(of: store.showMonthlyTop3Usage) { enabled in
                if enabled {
                    store.refreshTopUsage()
                } else {
                    store.clearTopUsageDisplay()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if hasUnsavedChanges {
                        Button("Cancel") {
                            if let originalSnapshot {
                                restore(snapshot: originalSnapshot)
                            }
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(hasUnsavedChanges ? "Save" : "Done") {
                        // Persist camera and detection settings to UserDefaults
                        persistCameraSettings()
                        originalSnapshot = currentSnapshot()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func currentSnapshot() -> SettingsSnapshot {
        SettingsSnapshot(
            apiKey: store.apiKey,
            homeId: store.homeId,
            criticalThreshold: store.criticalThreshold,
            breachCount: store.breachCount,
            idleTimerMinutes: store.idleTimerMinutes,
            showMonthlyTop3Usage: store.showMonthlyTop3Usage,
            showWebsocketTop3Usage: store.showWebsocketTop3Usage,
            cameraUrl: cameraUrl,
            cameraUsername: cameraUsername,
            cameraPassword: cameraPassword,
            cameraNetworkCachingMs: cameraNetworkCachingMs,
            cameraLiveCachingMs: cameraLiveCachingMs,
            learnModeEnabled: learnModeEnabled,
            learnModeIntervalMinutes: learnModeIntervalMinutes,
            catFeederCameraUrl: catFeederCameraUrl,
            catFeederCameraUsername: catFeederCameraUsername,
            catFeederCameraPassword: catFeederCameraPassword,
            catFeederCameraNetworkCachingMs: catFeederCameraNetworkCachingMs,
            catFeederCameraLiveCachingMs: catFeederCameraLiveCachingMs,
            catFeederLearnModeEnabled: catFeederLearnModeEnabled,
            catFeederLearnModeIntervalMinutes: catFeederLearnModeIntervalMinutes,
            detectionEnabled: detectionEnabled,
            detectionInterval: detectionInterval,
            confidenceThreshold: confidenceThreshold,
            alertRepeatMinutes: alertRepeatMinutes,
            catFeederDetectionEnabled: catFeederDetectionEnabled,
            catFeederDetectionInterval: catFeederDetectionInterval,
            catFeederConfidenceThreshold: catFeederConfidenceThreshold,
            catFeederAlertRepeatMinutes: catFeederAlertRepeatMinutes,
            logCamera: logCamera,
            logTibber: logTibber,
            logZaptec: logZaptec,
            logHue: logHue,
            logTelegram: logTelegram,
            zaptecUsername: zaptecManager.username,
            zaptecPassword: zaptecManager.password,
            zaptecInstallationId: zaptecManager.installationId,
            zaptecMaxConfiguredCurrent: zaptecManager.maxConfiguredCurrent,
            zaptecActiveChargerId: zaptecManager.activeChargerId,
            hueEnabled: hueManager.isEnabled,
            hueBridgeIP: hueManager.bridgeIP,
            hueUsername: hueManager.username,
            telegramEnabled: telegramManager.isEnabled,
            telegramBotToken: telegramManager.botToken,
            telegramRecipientsData: try? JSONEncoder().encode(telegramManager.chatRecipients)
        )
    }

    private func restore(snapshot: SettingsSnapshot) {
        store.apiKey = snapshot.apiKey
        store.homeId = snapshot.homeId
        store.criticalThreshold = snapshot.criticalThreshold
        store.breachCount = snapshot.breachCount
        store.idleTimerMinutes = snapshot.idleTimerMinutes
        store.showMonthlyTop3Usage = snapshot.showMonthlyTop3Usage
        store.showWebsocketTop3Usage = snapshot.showWebsocketTop3Usage

        cameraUrl = snapshot.cameraUrl
        cameraUsername = snapshot.cameraUsername
        cameraPassword = snapshot.cameraPassword
        cameraNetworkCachingMs = snapshot.cameraNetworkCachingMs
        cameraLiveCachingMs = snapshot.cameraLiveCachingMs
        learnModeEnabled = snapshot.learnModeEnabled
        learnModeIntervalMinutes = snapshot.learnModeIntervalMinutes
        catFeederCameraUrl = snapshot.catFeederCameraUrl
        catFeederCameraUsername = snapshot.catFeederCameraUsername
        catFeederCameraPassword = snapshot.catFeederCameraPassword
        catFeederCameraNetworkCachingMs = snapshot.catFeederCameraNetworkCachingMs
        catFeederCameraLiveCachingMs = snapshot.catFeederCameraLiveCachingMs
        catFeederLearnModeEnabled = snapshot.catFeederLearnModeEnabled
        catFeederLearnModeIntervalMinutes = snapshot.catFeederLearnModeIntervalMinutes

        detectionEnabled = snapshot.detectionEnabled
        detectionInterval = snapshot.detectionInterval
        confidenceThreshold = snapshot.confidenceThreshold
        alertRepeatMinutes = snapshot.alertRepeatMinutes
        catFeederDetectionEnabled = snapshot.catFeederDetectionEnabled
        catFeederDetectionInterval = snapshot.catFeederDetectionInterval
        catFeederConfidenceThreshold = snapshot.catFeederConfidenceThreshold
        catFeederAlertRepeatMinutes = snapshot.catFeederAlertRepeatMinutes

        logCamera = snapshot.logCamera
        logTibber = snapshot.logTibber
        logZaptec = snapshot.logZaptec
        logHue = snapshot.logHue
        logTelegram = snapshot.logTelegram

        zaptecManager.username = snapshot.zaptecUsername
        zaptecManager.password = snapshot.zaptecPassword
        zaptecManager.installationId = snapshot.zaptecInstallationId
        zaptecManager.maxConfiguredCurrent = snapshot.zaptecMaxConfiguredCurrent
        zaptecManager.activeChargerId = snapshot.zaptecActiveChargerId

        hueManager.isEnabled = snapshot.hueEnabled
        hueManager.bridgeIP = snapshot.hueBridgeIP
        hueManager.username = snapshot.hueUsername

        telegramManager.isEnabled = snapshot.telegramEnabled
        telegramManager.botToken = snapshot.telegramBotToken
        if let data = snapshot.telegramRecipientsData,
           let recipients = try? JSONDecoder().decode([TelegramManager.TelegramChatRecipient].self, from: data) {
            telegramManager.chatRecipients = recipients
        } else {
            telegramManager.chatRecipients = []
        }
    }

    private func persistCameraSettings() {
        // Save camera and detection settings to UserDefaults only on Save
        UserDefaults.standard.set(cameraUrl, forKey: "cameraUrl")
        UserDefaults.standard.set(cameraUsername, forKey: "cameraUsername")
        UserDefaults.standard.set(cameraPassword, forKey: "cameraPassword")
        UserDefaults.standard.set(cameraNetworkCachingMs, forKey: "cameraNetworkCachingMs")
        UserDefaults.standard.set(cameraLiveCachingMs, forKey: "cameraLiveCachingMs")
        UserDefaults.standard.set(learnModeEnabled, forKey: "garageDoorLearnModeEnabled")
        UserDefaults.standard.set(learnModeIntervalMinutes, forKey: "garageDoorLearnModeIntervalMinutes")
        UserDefaults.standard.set(detectionEnabled, forKey: "garageDoorDetectionEnabled")
        UserDefaults.standard.set(detectionInterval, forKey: "garageDoorDetectionInterval")
        UserDefaults.standard.set(confidenceThreshold, forKey: "garageDoorConfidenceThreshold")
        UserDefaults.standard.set(alertRepeatMinutes, forKey: "garageDoorAlertRepeatMinutes")
        
        UserDefaults.standard.set(catFeederCameraUrl, forKey: "catFeederCameraUrl")
        UserDefaults.standard.set(catFeederCameraUsername, forKey: "catFeederCameraUsername")
        UserDefaults.standard.set(catFeederCameraPassword, forKey: "catFeederCameraPassword")
        UserDefaults.standard.set(catFeederCameraNetworkCachingMs, forKey: "catFeederCameraNetworkCachingMs")
        UserDefaults.standard.set(catFeederCameraLiveCachingMs, forKey: "catFeederCameraLiveCachingMs")
        UserDefaults.standard.set(catFeederLearnModeEnabled, forKey: "catFeederLearnModeEnabled")
        UserDefaults.standard.set(catFeederLearnModeIntervalMinutes, forKey: "catFeederLearnModeIntervalMinutes")
        UserDefaults.standard.set(catFeederDetectionEnabled, forKey: "catFeederDetectionEnabled")
        UserDefaults.standard.set(catFeederDetectionInterval, forKey: "catFeederDetectionInterval")
        UserDefaults.standard.set(catFeederConfidenceThreshold, forKey: "catFeederConfidenceThreshold")
        UserDefaults.standard.set(catFeederAlertRepeatMinutes, forKey: "catFeederAlertRepeatMinutes")
    }
}
