import SwiftUI

struct CatFeederStatusCard: View {
    @ObservedObject private var detector = CatFeederDetector.shared

    private var headerStateText: String? {
        if detector.bowlState != .unknown {
            return detector.bowlState == .empty ? "EMPTY" : "NOT EMPTY"
        }
        if detector.isEnabled {
            return "DETECTING"
        }
        return nil
    }

    private var detailStateText: String {
        switch detector.bowlState {
        case .empty:
            return "State: Bowl Empty"
        case .notEmpty:
            return "State: Bowl Not Empty"
        case .unknown:
            return "State: Unknown"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "pawprint.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Cat Feeder")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let headerStateText {
                    Text(headerStateText)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(detector.bowlState == .unknown ? .secondary : (detector.bowlState == .empty ? .red : .green))
                }
            }

            HStack(alignment: .center, spacing: 10) {
                Group {
                    if let image = detector.lastCroppedSnapshot ?? detector.lastSnapshot {
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
