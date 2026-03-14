import Foundation
import Combine
import SwiftUI
import OSLog
import AVFoundation

class TibberMonitorStore: ObservableObject {
    @AppStorage("apiKey") var apiKey: String = ""
    @AppStorage("homeId") var homeId: String = ""
    
    @AppStorage("warningThreshold") var warningThreshold: Double = 4.0 // kWh or kW target
    @AppStorage("criticalThreshold") var criticalThreshold: Double = 5.0 // kWh or kW target
    
    @AppStorage("breachCount") var breachCount: Int = 0
    @AppStorage("lastBreachMonth") var lastBreachMonth: Int = Calendar.current.component(.month, from: Date())
    
    @AppStorage("idleTimerMinutes") var idleTimerMinutes: Double = 5.0

    @Published var liveData: LiveMeasurement?
    @Published var isConnected = false
    @Published var connectionError: String? {
        didSet {
            if connectionError != nil {
                AudioPlayer.shared.playAlert(level: .warning)
            }
        }
    }
    @Published var isScreensaverActive = false
    @Published var isDataStale = false {
        didSet {
            if isDataStale {
                AudioPlayer.shared.playAlert(level: .warning)
            }
        }
    }

    @Published var availableHomes: [Home] = []
    @Published var isFetchingHomes = false
    @Published var fetchHomesError: String?
    
    // Console log
    @Published var connectionLogs: [String] = []

    private var webSocketTask: URLSessionWebSocketTask?
    private var inactivityTimer: Timer?
    private var staleDataTimer: Timer?
    private let logger = Logger(subsystem: "com.erlendthune.tibber", category: "MonitorStore")
    
    // We keep track of the latest recorded average to trigger resets if it clears
    private var lastRecordedAverage: Double = 0.0
    
    // Connection state tracking
    private var isConnecting = false
    private var reconnectAttempt = 0
    private var isReconnecting = false

    func fetchHomes() {
        guard !apiKey.isEmpty else {
            fetchHomesError = "Missing API Key"
            return
        }

        isFetchingHomes = true
        fetchHomesError = nil

        let query = """
        {
            viewer {
                homes {
                    id
                    appNickname
                    address {
                        address1
                    }
                }
            }
        }
        """

        guard let url = URL(string: "https://api.tibber.com/v1-beta/gql") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = ["query": query]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isFetchingHomes = false

                if let error = error {
                    self?.fetchHomesError = error.localizedDescription
                    return
                }

                guard let data = data else {
                    self?.fetchHomesError = "No data received"
                    return
                }

                do {
                    let decodedData = try JSONDecoder().decode(HomesResponse.self, from: data)
                    self?.availableHomes = decodedData.data?.viewer?.homes ?? []
                    if self?.availableHomes.isEmpty == true {
                        self?.fetchHomesError = "No homes found"
                    }
                } catch {
                    self?.fetchHomesError = "Failed to parse homes: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    func connect() {
        // Prevent multiple simultaneous connection attempts
        guard !isConnecting else {
            print("Already connecting, skipping duplicate connection attempt")
            return
        }
        
        // If already connected, don't reconnect
        if isConnected {
            print("Already connected, skipping connection attempt")
            return
        }
        
        guard !apiKey.isEmpty, !homeId.isEmpty else {
            connectionError = "Missing API Key or Home ID"
            self.logger.error("Cannot connect: Missing API Key or Home ID")
            return
        }
        
        isConnecting = true
        
        // Ensure UI stays awake
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        let urlSession = URLSession(configuration: .default)
        let url = URL(string: "wss://websocket-api.tibber.com/v1-beta/gql/subscriptions")!
        var request = URLRequest(url: url)
        request.setValue("graphql-transport-ws", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        request.setValue("AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        // Note: Authorization header is not needed when sending token in connection_init payload

        print("Attempting WebSocket connection to: \(url)")
        print("API Key being used: \(apiKey)")
        print("Home ID being used: \(homeId)")
        self.logger.info("Attempting WebSocket connection to Tibber API")
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        DispatchQueue.main.async {
            self.addLog("Connecting...")
        }

        // Start receiving messages immediately
        receiveMessage()
        
        // Send connection_init after a short delay to ensure socket is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let initMessage: [String: Any] = [
                "type": "connection_init",
                "payload": ["token": self.apiKey]
            ]
            
            print("Sending connection_init message with token: \(self.apiKey)")
            self.sendMessage(initMessage)
        }
    }
    
    func disconnect() {
        isConnecting = false
        isReconnecting = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        staleDataTimer?.invalidate()
        DispatchQueue.main.async {
            self.isConnected = false
            // self.liveData = nil // Keep old data rather than blanking out the UI totally
            self.isDataStale = false
            UIApplication.shared.isIdleTimerDisabled = false
            self.addLog("Disconnected")
        }
    }
    
    private func sendMessage(_ dictionary: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let jsonString = String(data: data, encoding: .utf8) else { 
            print("Failed to serialize message")
            return 
        }
        
        print("Sending message: \(jsonString)")
        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                print("Failed to send message: \(error)")
                self?.logger.error("Failed to send message: \(error.localizedDescription)")
            } else {
                print("Message sent successfully")
            }
        }
    }
    
    private func subscribeToLiveMeasurement() {
        let query = """
        subscription {
            liveMeasurement(homeId: "\(homeId)") {
                timestamp
                power
                accumulatedConsumption
                accumulatedConsumptionLastHour
                accumulatedCost
                currency
                averagePower
                voltagePhase1
                currentL1
                powerFactor
            }
        }
        """
        
        print("Subscribing with query: \(query)")
        
        let startMessage: [String: Any] = [
            "id": "1",
            "type": "subscribe",
            "payload": ["query": query]
        ]
        sendMessage(startMessage)
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self.logger.error("WebSocket receive error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.isConnecting = false
                    self.connectionError = "Connection failed: \(error.localizedDescription)"
                    self.addLog("Error: \(error.localizedDescription)")
                    self.triggerReconnect()
                }
                
            case .success(let message):
                switch message {
                case .string(let text):
                    print("WebSocket message received: \(text)")
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        print("WebSocket data received: \(text)")
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                
                // Always keep listening for new messages
                self.receiveMessage()
            }
        }
    }
    
    private func handleMessage(_ jsonString: String) {
        // Reset stale data tracking whenever we get any message from the server (even pings)
        resetStaleDataTimer()

        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String else { return }
        
        switch type {
        case "connection_ack":
            print("Connection acknowledged by server")
            DispatchQueue.main.async {
                self.isConnecting = false
                self.isConnected = true
                self.connectionError = nil
                self.reconnectAttempt = 0 // Reset backoff on success
                self.isReconnecting = false
                self.addLog("Connected")
            }
            subscribeToLiveMeasurement()
            
        case "next":
            do {
                let response = try JSONDecoder().decode(LiveMeasurementResponse.self, from: data)
                if let measurement = response.payload?.data?.liveMeasurement {
                    DispatchQueue.main.async {
                        self.liveData = measurement
                        self.isDataStale = false
                        self.evaluateThresholds(measurement: measurement)
                        // Add log silently for incoming data
                        self.addLog("Data received")
                    }
                }
            } catch {
                print("Decode error: \(error)")
            }
            
        case "error":
            print("GraphQL Error: \(dict)")
            if let errorMsg = dict["payload"] as? [String: Any] {
                print("Error details: \(errorMsg)")
            }
            
        case "ping":
            print("Received ping, sending pong")
            self.sendMessage(["type": "pong"])
            
        default:
            print("Received unknown message type: \(type)")
            break
        }
    }
    
    private func evaluateThresholds(measurement: LiveMeasurement) {
        // The user mentioned to "trust the average received in graphql"
        // The average power from the API is in W, so we convert it to kW for comparison
        let averageKW = (measurement.averagePower ?? 0.0) / 1000.0
        
        var alertLevel: AudioPlayer.AlertLevel = .none
        
        if averageKW >= criticalThreshold {
            alertLevel = .critical
        } else if averageKW >= warningThreshold {
            alertLevel = .warning
        }
        
        if alertLevel != .none {
            // Wake screen explicitly
            wakeScreen()
            AudioPlayer.shared.playAlert(level: alertLevel)
            
            // Increment breaches (only once per instance, or trust user's logic)
            // Simpler: If it just crossed critical right now, we log a breach
            if averageKW >= criticalThreshold && lastRecordedAverage < criticalThreshold {
                incrementBreach()
            }
        }
        
        lastRecordedAverage = averageKW
    }
    
    private func incrementBreach() {
        resetBreachCounterIfNeeded()
        breachCount += 1
    }
    
    private func resetBreachCounterIfNeeded() {
        let currentMonth = Calendar.current.component(.month, from: Date())
        if currentMonth != lastBreachMonth {
            breachCount = 0
            lastBreachMonth = currentMonth
        }
    }

    // MARK: - Stale Data check
    
    private func resetStaleDataTimer() {
        DispatchQueue.main.async { [weak self] in
            // Must invalidate existing timer to prevent duplicates
            self?.staleDataTimer?.invalidate()
            
            // Remove the stale warning immediately since we just got activity
            self?.isDataStale = false
            
            // Re-arm the timer
            self?.staleDataTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
                // Timer fired: No activity for 60 seconds
                DispatchQueue.main.async {
                    self?.isDataStale = true
                    self?.addLog("Stale connection (60s). Reconnecting...")
                    self?.triggerReconnect()
                }
            }
        }
    }
    
    // MARK: - Reconnect Logic
    
    private func triggerReconnect() {
        guard !isReconnecting else { return }
        isReconnecting = true
        
        // Ensure old socket is dead
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        
        // Exponential backoff: 2^attempt (1s, 2s, 4s, 8s, 16s, 32s, 60s max)
        let maxDelay: TimeInterval = 60.0
        let baseDelay = pow(2.0, Double(min(reconnectAttempt, 6)))
        
        // Jitter: Add random offset between 0 and 2 seconds
        let jitter = Double.random(in: 0...2.0)
        let delay = min(baseDelay + jitter, maxDelay)
        
        reconnectAttempt += 1
        
        let logMsg = "Triggering reconnect in \(String(format: "%.1f", delay))s (Attempt \(reconnectAttempt))"
        print(logMsg)
        
        DispatchQueue.main.async { [weak self] in
            self?.addLog("Delaying: \(String(format: "%.1f", delay))s")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.isReconnecting = false
            self?.connect()
        }
    }

    // MARK: - Screensaver / Inactivity
    
    func wakeScreen() {
        DispatchQueue.main.async {
            self.isScreensaverActive = false
            self.startInactivityTimer() // reset timer
        }
    }
    
    func startInactivityTimer() {
        inactivityTimer?.invalidate()
        let timeout: TimeInterval = idleTimerMinutes * 60
        
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isScreensaverActive = true
            }
        }
    }
    
    // MARK: - Logging
    
    func addLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        let timeString = formatter.string(from: Date())
        
        // Add new log at the start and keep last 50 lines to prevent memory bloat
        connectionLogs.insert("[\(timeString)] \(message)", at: 0)
        if connectionLogs.count > 50 {
            connectionLogs.removeLast()
        }
    }
}
