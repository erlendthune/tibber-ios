import Foundation
import Combine
import SwiftUI
import OSLog

class TibberMonitorStore: ObservableObject {
    @AppStorage("apiKey") var apiKey: String = ""
    @AppStorage("homeId") var homeId: String = ""
    
    @AppStorage("warningThreshold") var warningThreshold: Double = 4.0 // kWh or kW target
    @AppStorage("criticalThreshold") var criticalThreshold: Double = 5.0 // kWh or kW target
    
    @AppStorage("breachCount") var breachCount: Int = 0
    @AppStorage("lastBreachMonth") var lastBreachMonth: Int = Calendar.current.component(.month, from: Date())
    
    @Published var liveData: LiveMeasurement?
    @Published var isConnected = false
    @Published var connectionError: String?
    @Published var isScreensaverActive = false
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var inactivityTimer: Timer?
    private let logger = Logger(subsystem: "com.erlendthune.tibber", category: "MonitorStore")
    
    // We keep track of the latest recorded average to trigger resets if it clears
    private var lastRecordedAverage: Double = 0.0

    init() {
        resetBreachCounterIfNeeded()
        startInactivityTimer()
    }

    func connect() {
        guard !apiKey.isEmpty, !homeId.isEmpty else {
            connectionError = "Missing API Key or Home ID"
            return
        }
        
        // Ensure UI stays awake
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        let urlSession = URLSession(configuration: .default)
        let url = URL(string: "wss://websocket-api.tibber.com/v1-beta/gql/subscriptions")!
        var request = URLRequest(url: url)
        request.setValue("graphql-transport-ws", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        request.setValue("AppleWebKit/537.36", forHTTPHeaderField: "User-Agent") // Mimic a browser if needed
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        // 1. Send connection_init
        let initMessage: [String: Any] = [
            "type": "connection_init",
            "payload": ["token": apiKey]
        ]
        
        sendMessage(initMessage)
        receiveMessage()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        DispatchQueue.main.async {
            self.isConnected = false
            self.liveData = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    private func sendMessage(_ dictionary: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        
        webSocketTask?.send(.string(jsonString)) { error in
            if let error = error {
                print("Failed to send message: \(error)")
            }
        }
    }
    
    private func subscribeToLiveMeasurement() {
        let query = """
        subscription {
            liveMeasurement(homeId: "\\(homeId)") {
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
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.connectionError = error.localizedDescription
                }
                
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                
                // Keep listening
                if self.webSocketTask?.state == .running {
                    self.receiveMessage()
                }
            }
        }
    }
    
    private func handleMessage(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String else { return }
        
        switch type {
        case "connection_ack":
            DispatchQueue.main.async {
                self.isConnected = true
                self.connectionError = nil
            }
            subscribeToLiveMeasurement()
            
        case "next":
            do {
                let response = try JSONDecoder().decode(LiveMeasurementResponse.self, from: data)
                if let measurement = response.payload?.data?.liveMeasurement {
                    DispatchQueue.main.async {
                        self.liveData = measurement
                        self.evaluateThresholds(measurement: measurement)
                    }
                }
            } catch {
                print("Decode error: \(error)")
            }
            
        case "error":
            print("GraphQL Error: \(dict)")
            
        default:
            break
        }
    }
    
    private func evaluateThresholds(measurement: LiveMeasurement) {
        // The user mentioned to "trust the average received in graphql"
        let average = measurement.averagePower ?? 0.0
        
        var alertLevel: AudioPlayer.AlertLevel = .none
        
        if average >= criticalThreshold {
            alertLevel = .critical
        } else if average >= warningThreshold {
            alertLevel = .warning
        }
        
        if alertLevel != .none {
            // Wake screen explicitly
            wakeScreen()
            AudioPlayer.shared.playAlert(level: alertLevel)
            
            // Increment breaches (only once per instance, or trust user's logic)
            // Simpler: If it just crossed critical right now, we log a breach
            if average >= criticalThreshold && lastRecordedAverage < criticalThreshold {
                incrementBreach()
            }
        }
        
        lastRecordedAverage = average
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
    
    // MARK: - Screensaver / Inactivity
    
    func wakeScreen() {
        DispatchQueue.main.async {
            self.isScreensaverActive = false
            self.startInactivityTimer() // reset timer
        }
    }
    
    func startInactivityTimer() {
        inactivityTimer?.invalidate()
        let timeout: TimeInterval = 5 * 60 // 5 minutes to screensaver
        
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isScreensaverActive = true
            }
        }
    }
}
