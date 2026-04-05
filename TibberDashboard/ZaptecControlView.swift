import SwiftUI

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
