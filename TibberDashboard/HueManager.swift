import Foundation
import SwiftUI
import Combine

class HueManager: ObservableObject {
    static let shared = HueManager()
    
    @AppStorage("hueBridgeIP") var bridgeIP: String = ""
    @AppStorage("hueUsername") var username: String = ""
    @AppStorage("hueEnabled") var isEnabled: Bool = true // Added config flag for flashing lights
    
    @Published var isDiscovering = false
    @Published var discoveryError: String?
    @Published var isLinking = false
    @Published var linkError: String?
    
    // Discover the Hue Bridge IP using the MeetHue cloud discovery service
    func discoverBridge() {
        isDiscovering = true
        discoveryError = nil
        
        guard let url = URL(string: "https://discovery.meethue.com") else {
            self.discoveryError = "Invalid discovery URL"
            self.isDiscovering = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isDiscovering = false
                if let error = error {
                    self?.discoveryError = error.localizedDescription
                    return
                }
                
                guard let data = data else {
                    self?.discoveryError = "No data returned"
                    return
                }
                
                do {
                    if let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]],
                       let firstBridge = jsonArray.first,
                       let internalipaddress = firstBridge["internalipaddress"] as? String {
                        self?.bridgeIP = internalipaddress
                    } else {
                        self?.discoveryError = "No bridges found on the local network."
                    }
                } catch {
                    self?.discoveryError = "Failed to parse discovery response."
                }
            }
        }.resume()
    }
    
    // Link with the bridge (Button on bridge must be pressed before calling this)
    func linkBridge() {
        guard !bridgeIP.isEmpty else {
            linkError = "Bridge IP is missing"
            return
        }
        
        isLinking = true
        linkError = nil
        
        let urlString = "http://\(bridgeIP)/api"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let payload: [String: Any] = ["devicetype": "tibberdashboard#iphone"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLinking = false
                if let error = error {
                    self?.linkError = error.localizedDescription
                    return
                }
                
                guard let data = data else { return }
                
                do {
                    if let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]],
                       let firstItem = jsonArray.first {
                        if let success = firstItem["success"] as? [String: Any],
                           let username = success["username"] as? String {
                            self?.username = username
                        } else if let error = firstItem["error"] as? [String: Any],
                                  let description = error["description"] as? String {
                            self?.linkError = description
                        }
                    }
                } catch {
                    self?.linkError = "Failed to parse link response."
                }
            }
        }.resume()
    }
    
    // Trigger critical alert (flash lights)
    private var lastAlertTime: Date = .distantPast
    private let alertCooldown: TimeInterval = 60 // 60 seconds

    func triggerCriticalAlert() {
        let now = Date()
        guard isEnabled, !bridgeIP.isEmpty, !username.isEmpty,
              now.timeIntervalSince(lastAlertTime) >= alertCooldown else { return }
        lastAlertTime = now
        
        // Group 0 represents all lights
        let urlString = "http://\(bridgeIP)/api/\(username)/groups/0/action"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        
        // "lselect" flashes lights for ~15 seconds, "select" flashes once
        let payload: [String: Any] = ["alert": "lselect"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        
        Task {
            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                print("Hue critical alert error: \(error)")
            }
        }
    }
}
