import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: TibberMonitorStore
    @Environment(\.dismiss) var dismiss
    
    @State private var isApiKeyVisible: Bool = false
    @State private var isHomeIdVisible: Bool = false
    
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
                    Stepper(value: $store.warningThreshold, in: 0.5...20.0, step: 0.5) {
                        Text("Warning Limit: \(store.warningThreshold, specifier: "%.1f")")
                    }
                    
                    Stepper(value: $store.criticalThreshold, in: 1.0...25.0, step: 0.5) {
                        Text("Critical Limit: \(store.criticalThreshold, specifier: "%.1f")")
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
            }
            .navigationTitle("Dashboard Settings")
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
