import Foundation
import Combine
import SwiftUI

// Basic Zaptec State Models
struct ZaptecStateResponse: Codable {
    let StateId: Int
    let Timestamp: String
    let ValueAsString: String?
}

// Added to decode chargers tied to an installation
struct ZaptecCharger: Identifiable, Codable, Hashable {
    let Id: String
    let Name: String?
    let DeviceId: String?
    let InstallationId: String?
    
    var id: String { Id }
}

struct ZaptecChargersResponse: Codable {
    let Pages: Int
    let Data: [ZaptecCharger]
}

class ZaptecManager: ObservableObject {
    static let shared = ZaptecManager()
    
    @AppStorage("zaptecUsername") var username: String = ""
    @AppStorage("zaptecPassword") var password: String = ""
    @AppStorage("zaptecInstallationId") var installationId: String = "" // Usually a GUID
    
    @Published var isAuthenticated = false
    @Published var token: String?
    @Published var authError: String?
    
    @Published var isCharging = false
    @Published var chargePower: Double = 0.0 // in kW
    @Published var sessionEnergy: Double = 0.0 // in kWh (StateId 553)
    @Published var voltage: Double = 0.0 // in V (StateId 501)
    @Published var activeCurrent: Double = 0.0 // in A (StateId 708)
    @Published var operationModeString: String = "Unknown"
    @Published var lastStateUpdate: Date?
    @Published var activeChargerId: String = "" // Added to keep track of the specific charger for commands
    @Published var allowedChargeCurrent: Double = 16.0 // Added to sync UI with API value
    @Published var pendingChargeCurrent: Double? // Added to handle local stepper changes before saving
    @Published var lastChargeCurrentUpdate: Date? // Prevent updating more than once every 15 mins
    
    @AppStorage("zaptecMaxConfiguredCurrent") var maxConfiguredCurrent: Double = 13.0 // User configurable maximum

    // NEW state properties for charger picker
    @Published var availableChargers: [ZaptecCharger] = []
    @Published var isFetchingChargers = false
    @Published var fetchChargersError: String?

    private var updateTimer: Timer?
    
    // Store reference to log
    var monitorStore: TibberMonitorStore?
    
    // Zaptec API Token Request
    func authenticate() {
        guard !username.isEmpty, !password.isEmpty else {
            authError = "Missing Zaptec credentials"
            return
        }
        
        let url = URL(string: "https://api.zaptec.com/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "grant_type=password&username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&password=\(password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        request.httpBody = bodyString.data(using: .utf8)
        
        print("Zaptec auth attempting with email: \(username)")
        DispatchQueue.main.async {
            self.monitorStore?.addConnectionLog("Auth attempt...", source: "ZAPTEC")
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Zaptec Auth Error: \(error.localizedDescription)")
                    self?.authError = "Failed: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("Zaptec Auth HTTP Status: \(httpResponse.statusCode)")
                }
                
                guard let data = data else { 
                    self?.authError = "No data received"
                    return 
                }
                
                if let rawJson = String(data: data, encoding: .utf8) {
                    print("Zaptec Auth Raw Response: \(rawJson)")
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if let token = json["access_token"] as? String {
                            self?.token = token
                            self?.isAuthenticated = true
                            self?.authError = nil
                            self?.startPolling()
                            print("Zaptec Auth Successful")
                            self?.monitorStore?.addConnectionLog("Connected", source: "ZAPTEC")
                        } else if let errorDesc = json["error_description"] as? String {
                            self?.authError = errorDesc
                            self?.monitorStore?.addConnectionLog("Auth rejected", source: "ZAPTEC")
                        } else {
                            self?.authError = "Authentication failed (no token)"
                        }
                    } else {
                        self?.authError = "Invalid JSON response"
                    }
                } catch {
                    print("Zaptec Auth Parse Error: \(error)")
                    self?.authError = "Parse error"
                }
            }
        }.resume()
    }
    
    func startPolling() {
        // If we haven't selected an active charger but we have a token, fetch the list!
        if activeChargerId.isEmpty {
            fetchChargers()
        } else {
            fetchState()
            fetchInstallationDetails()
        }
        
        updateTimer?.invalidate()
        // Poll every 60 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.fetchState()
            self?.fetchInstallationDetails()
        }
    }
    
    func stopPolling() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // Explicitly fetch all chargers tied to the Installation ID so the user can select one
    func fetchChargers() {
        guard let token = token, !installationId.isEmpty else { return }
        
        isFetchingChargers = true
        fetchChargersError = nil
        
        // The API endpoint to get all chargers globally for a user or installation:
        // /api/chargers normally gets all chargers the user has access to.
        let url = URL(string: "https://api.zaptec.com/api/chargers")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isFetchingChargers = false
                
                if let error = error {
                    self?.fetchChargersError = "Network error: \(error.localizedDescription)"
                    return
                }
                
                // Debug raw response
                if let httpResponse = response as? HTTPURLResponse {
                    print("Zaptec Chargers HTTP Status: \(httpResponse.statusCode)")
                }
                if let rawData = data, let str = String(data: rawData, encoding: .utf8) {
                    print("Zaptec Chargers Raw JSON: \(str)")
                }
                
                guard let data = data, !data.isEmpty else {
                    self?.fetchChargersError = "No data returned"
                    return
                }
                
                do {
                    // Extract chargers from JSON payload
                    let responseData = try JSONDecoder().decode(ZaptecChargersResponse.self, from: data)
                    // Filter down to the matching installation if we want, or just list them all
                    let targetId = self?.installationId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let mappedChargers = responseData.Data.filter { 
                        $0.InstallationId?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == targetId 
                    }
                    
                    self?.availableChargers = mappedChargers
                    
                    if mappedChargers.isEmpty {
                        self?.fetchChargersError = "No chargers found for this installation ID."
                    } else if self?.activeChargerId == "" {
                        // Automatically select the first charger if we don't have one selected yet
                        self?.activeChargerId = mappedChargers.first!.Id
                        self?.monitorStore?.addConnectionLog("Auto-selected charger", source: "ZAPTEC")
                        self?.fetchState()
                        self?.fetchInstallationDetails()
                    }
                } catch {
                    self?.fetchChargersError = "Failed to parse chargers."
                    print("Parse chargers error: \(error)")
                }
            }
        }.resume()
    }
    
    func fetchState() {
        guard let token = token, !activeChargerId.isEmpty else { return }
        
        // Fetch chargers for the installation first, or just fetch the installation's chargers directly
        // Usually, to get states, you need the charger ID, so we might need a two-step process:
        // 1. Get chargers for installation
        // 2. Get state for the first charger
        fetchChargerState(chargerId: activeChargerId, token: token)
    }
    
    // Fallback if needed when you fetch Installation state by UUID directly instead of chargers.
    func fetchInstallationDetails() {
        guard let token = token, !installationId.isEmpty else { return }
        
        let url = URL(string: "https://api.zaptec.com/api/installation/\(installationId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                print("Zaptec Installation Details HTTP Status: \(httpResponse.statusCode)")
            }
            if let rawData = data, let str = String(data: rawData, encoding: .utf8) {
                print("Zaptec Installation Details Raw JSON: \(str)")
            }
            
            guard let data = data else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let availableCurrent = json["AvailableCurrent"] as? Double {
                    DispatchQueue.main.async {
                        // Clamp the read value to the maximum configured current so the Stepper UI doesn't break
                        let clampedValue = min(availableCurrent, self?.maxConfiguredCurrent ?? 32.0)
                        self?.allowedChargeCurrent = clampedValue
                        // Automatically sync pending current if it hasn't been edited
                        if self?.pendingChargeCurrent == nil {
                            self?.pendingChargeCurrent = clampedValue
                        }
                        self?.monitorStore?.addConnectionLog("Set reading: \(clampedValue)A", source: "ZAPTEC")
                    }
                }
            } catch {
                print("Failed to decode Zaptec installation details: \(error)")
            }
        }.resume()
    }
    
    private func fetchChargerState(chargerId: String, token: String) {
        let url = URL(string: "https://api.zaptec.com/api/chargers/\(chargerId)/state")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.monitorStore?.addConnectionLog("State error: \(error.localizedDescription)", source: "ZAPTEC")
                }
                return
            }
            guard let data = data else { return }
            
            // Print raw state string directly to console for debugging
            if let str = String(data: data, encoding: .utf8) {
                print("Zaptec Raw state: \(str)")
            }
            
            do {
                let states = try JSONDecoder().decode([ZaptecStateResponse].self, from: data)
                DispatchQueue.main.async {
                    self?.parseStates(states)
                    self?.monitorStore?.addDataLog("State update received", source: "ZAPTEC")
                }
            } catch {
                if let str = String(data: data, encoding: .utf8) {
                    print("Raw state: \(str)")
                }
                print("Failed to decode Zaptec state: \(error)")
                DispatchQueue.main.async {
                    self?.monitorStore?.addConnectionLog("State decode error", source: "ZAPTEC")
                    // Log the decoding error description for easier debugging without Xcode
                    self?.monitorStore?.addConnectionLog("Error: \(error.localizedDescription)", source: "ZAPTEC")
                }
            }
        }.resume()
    }
    
    private func parseStates(_ states: [ZaptecStateResponse]) {
        self.lastStateUpdate = Date()
        
        for state in states {
            // StateId 710 = ChargerOperationMode
            // Based on ID 710 mappings: 1=Disconnected, 2=Connected/Waiting, 3=Charging, 5=Finished/Idle
            if state.StateId == 710 {
                if let val = state.ValueAsString {
                    // It can be float like "3.0" or integer like "3" depending on Zaptec backend formatting. Use Double and cast to Int to be safe.
                    if let valDouble = Double(val) {
                        let mode = Int(valDouble)
                        self.isCharging = (mode == 3)
                        
                        let modeString: String
                        switch mode {
                        case 1: modeString = "Disconnected"
                        case 2: modeString = "Waiting/Allocating"
                        case 3: modeString = "Charging"
                        case 5: modeString = "Finished/Idle"
                        default: modeString = "Unknown (\(mode))"
                        }
                        
                        DispatchQueue.main.async {
                            self.operationModeString = modeString
                            self.monitorStore?.addConnectionLog("Mode: \(modeString)", source: "ZAPTEC")
                        }
                    } else {
                        // Debug if casting completely fails
                        print("Failed to decode Zaptec mode from string: \(val)")
                    }
                }
            }
            
            // StateId 513 = Total Charge Power in Watts (Found in specific setups)
            if state.StateId == 513 {
                if let val = state.ValueAsString, let powerWatts = Double(val) {
                    DispatchQueue.main.async {
                        // Convert watts to kW
                        self.chargePower = powerWatts / 1000.0
                    }
                }
            }
            
            // StateId 553 = Session Energy in kWh
            if state.StateId == 553 {
                if let val = state.ValueAsString, let energy = Double(val) {
                    DispatchQueue.main.async {
                        self.sessionEnergy = energy
                    }
                }
            }
            
            // StateId 501 = Voltage
            if state.StateId == 501 {
                if let val = state.ValueAsString, let vDouble = Double(val) {
                    DispatchQueue.main.async {
                        self.voltage = vDouble
                    }
                }
            }
            
            // StateId 708 = Active Current
            if state.StateId == 708 {
                if let val = state.ValueAsString, let cDouble = Double(val) {
                    DispatchQueue.main.async {
                        self.activeCurrent = cDouble
                    }
                }
            }
        }
    }
    
    // Explicitly fetch charger settings
    func fetchSettings() {
        guard let token = token, !activeChargerId.isEmpty else { return }
        
        let url = URL(string: "https://api.zaptec.com/api/chargers/\(activeChargerId)/settings")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data else { return }
            
            // Check raw settings for debugging empty or unexpected formats
            if let str = String(data: data, encoding: .utf8) {
                print("Zaptec Settings Raw JSON: \(str)")
            }
            
            do {
                if let settings = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                    // Try to find setting 510 (Max Current)
                    if let currentSetting = settings.first(where: { ($0["SettingId"] as? Int) == 510 }) {
                        
                        var extractedValue: Double? = nil
                        
                        if let valueString = currentSetting["ValueAsString"] as? String {
                            extractedValue = Double(valueString)
                        } else if let valueNum = currentSetting["ValueAsString"] as? Double {
                            extractedValue = valueNum
                        }
                        
                        if let currentValue = extractedValue {
                            DispatchQueue.main.async {
                                self?.allowedChargeCurrent = currentValue
                                // Align pending to reflect actual save state
                                self?.pendingChargeCurrent = currentValue
                                self?.monitorStore?.addConnectionLog("Set reading: \(currentValue)A", source: "ZAPTEC")
                            }
                        }
                    } else {
                        print("Zaptec Setting 510 (Max Current) not found in response.")
                    }
                }
            } catch {
                print("Failed to decode Zaptec settings: \(error)")
            }
        }.resume()
    }

    // MARK: - Charger Commands

    func pauseCharging() {
        sendCommand(commandId: 50)
    }

    func resumeCharging() {
        sendCommand(commandId: 51)
    }

    private func sendCommand(commandId: Int) {
        guard let token = token, !activeChargerId.isEmpty else { return }
        
        let url = URL(string: "https://api.zaptec.com/api/chargers/\(activeChargerId)/sendCommand/\(commandId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    print("Zaptec SendCommand \(commandId) HTTP Status: \(httpResponse.statusCode)")
                    await MainActor.run {
                        ZaptecManager.shared.monitorStore?.addConnectionLog("Cmd \(commandId) return \(httpResponse.statusCode)", source: "ZAPTEC")
                    }
                }
                // Trigger a fast state poll after command
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.fetchState()
            } catch {
                print("Zaptec SendCommand Error: \(error)")
            }
        }
    }
    
    // Adjust maximum charge current in Amperes
    func updateChargeCurrent(amps: Int) {
        // Enforce the 15-minute cooldown rule
        if let lastUpdate = lastChargeCurrentUpdate, Date().timeIntervalSince(lastUpdate) < 15 * 60 {
            DispatchQueue.main.async {
                self.monitorStore?.addConnectionLog("Current update blocked (15m cooldown)", source: "ZAPTEC")
            }
            return
        }

        // Clamp between 6 and the configured max
        let clampedAmps = max(6, min(Int(maxConfiguredCurrent), amps))
        
        // Update local UI state immediately to prevent jumping
        DispatchQueue.main.async {
            self.allowedChargeCurrent = Double(clampedAmps)
            // Align pending to reflect actual save state
            self.pendingChargeCurrent = Double(clampedAmps)
            self.lastChargeCurrentUpdate = Date()
        }
        
        guard let token = token, !installationId.isEmpty else { return }
        
        let url = URL(string: "https://api.zaptec.com/api/installation/\(installationId)/update")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "availableCurrent": clampedAmps
        ]
        
        guard let jsonBody = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = jsonBody
        
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    print("Zaptec UpdateCurrent (\(clampedAmps)A) HTTP Status: \(httpResponse.statusCode)")
                    await MainActor.run {
                        self.monitorStore?.addConnectionLog("Set \(clampedAmps)A return \(httpResponse.statusCode)", source: "ZAPTEC")
                    }
                    // Refresh settings to confirm API accepted it
                    self.fetchInstallationDetails()
                }
            } catch {
                print("Zaptec UpdateCurrent Error: \(error)")
            }
        }
    }
}
