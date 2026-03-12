import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: TibberMonitorStore
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Authentication")) {
                    TextField("API Key", text: $store.apiKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    TextField("Home ID", text: $store.homeId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                Section(header: Text("Tariff / Thresholds")) {
                    Stepper(value: $store.warningThreshold, in: 0.5...20.0, step: 0.5) {
                        Text("Warning Limit: \(store.warningThreshold, specifier: "%.1f")")
                    }
                    
                    Stepper(value: $store.criticalThreshold, in: 1.0...25.0, step: 0.5) {
                        Text("Critical Limit: \(store.criticalThreshold, specifier: "%.1f")")
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
            .toolbar {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}
