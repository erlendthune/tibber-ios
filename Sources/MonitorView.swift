import SwiftUI

struct MonitorView: View {
    @ObservedObject var store: TibberMonitorStore
    @State private var showingSettings = false
    
    var body: some View {
        ZStack {
            // Main Dashboard
            NavigationView {
                VStack(spacing: 30) {
                    if let error = store.connectionError {
                        Text(error).foregroundColor(.red)
                    } else if !store.isConnected {
                        ProgressView("Connecting to Tibber...")
                            .onAppear { store.connect() }
                    } else if let data = store.liveData {
                        // Ring gauge
                        ZStack {
                            Circle()
                                .stroke(lineWidth: 25.0)
                                .opacity(0.2)
                                .foregroundColor(colorForAverage(data.averagePower ?? 0))
                            
                            Circle()
                                .trim(from: 0.0, to: min(CGFloat((data.averagePower ?? 0) / store.criticalThreshold), 1.0))
                                .stroke(style: StrokeStyle(lineWidth: 25.0, lineCap: .round, lineJoin: .round))
                                .foregroundColor(colorForAverage(data.averagePower ?? 0))
                                .rotationEffect(Angle(degrees: 270.0))
                                .animation(.linear, value: data.averagePower)
                            
                            VStack {
                                Text(String(format: "%.2f kW", (data.averagePower ?? 0)))
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(colorForAverage(data.averagePower ?? 0))
                                
                                Text("Avg (from GraphQL)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(40)
                        
                        // Live Stats
                        HStack {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Live Power: \(String(format: "%.0f W", data.power))")
                                    .font(.headline)
                                Text("Accum. Hour: \(String(format: "%.2f kWh", data.accumulatedConsumptionLastHour ?? 0.0))")
                                Text("Voltage L1: \(String(format: "%.1f V", data.voltagePhase1 ?? 0.0))")
                                Text("Cost Today: \(String(format: "%.2f %@", data.accumulatedCost ?? 0.0, data.currency ?? "NOK"))")
                            }
                            Spacer()
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 15).fill(Color(.systemGray6)))
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                }
                .navigationTitle("Tibber Monitor")
                .toolbar {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .disabled(store.isScreensaverActive) // disabled when screensaver is on
            
            // OLED Screensaver Overlay
            if store.isScreensaverActive {
                Color.black
                    .ignoresSafeArea()
                    .onTapGesture {
                        store.wakeScreen() // dismiss black overlay
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.5), value: store.isScreensaverActive)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store)
                // Reload on dismiss
                .onDisappear {
                    store.disconnect()
                    store.connect()
                }
        }
        .onDisappear {
            store.disconnect()
        }
    }
    
    private func colorForAverage(_ average: Double) -> Color {
        if average >= store.criticalThreshold {
            return .red
        } else if average >= store.warningThreshold {
            return .orange
        } else {
            return .green
        }
    }
}
