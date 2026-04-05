import SwiftUI

// MARK: - Garage Door Status Card (pure SwiftUI, no VLC)
struct GarageDoorStatusCard: View {
    @ObservedObject private var detector = GarageDoorDetector.shared

    private var headerStateText: String? {
        if detector.doorState != .unknown {
            return detector.doorState == .open ? "OPEN" : "CLOSED"
        }
        if detector.isEnabled {
            return "DETECTING"
        }
        return nil
    }

    private var detailStateText: String {
        detector.doorState == .unknown ? "State: Unknown" : "State: \(detector.doorState == .open ? "Open" : "Closed")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "door.garage.closed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Garage Door")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let headerStateText {
                    Text(headerStateText)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(detector.doorState == .unknown ? .secondary : (detector.doorState == .open ? .orange : .green))
                }
            }

            HStack(alignment: .center, spacing: 10) {
                Group {
                    if let image = detector.lastSnapshot {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color(.systemGray5)
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(width: 84, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(detailStateText)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text("Confidence: \(Int(detector.confidence * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let date = detector.lastSnapshotDate {
                        Text("Updated: \(date.formatted(date: .omitted, time: .standard))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Updated: --")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 15).fill(Color(.systemGray6)))
    }
}
