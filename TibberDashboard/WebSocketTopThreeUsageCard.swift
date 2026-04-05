import SwiftUI

struct WebSocketTopThreeUsageCard: View {
    @ObservedObject var store: TibberMonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Top 3 Hours This Month (WebSocket)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            Text("Source: WebSocket")
                .font(.caption2)
                .foregroundColor(.secondary)

            if store.websocketTopUsageHours.isEmpty {
                Text("Collecting live data...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(store.websocketTopUsageHours.enumerated()), id: \.element.id) { index, hour in
                    HStack {
                        Text("#\(index + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .leading)

                        Text(formatHour(hour.from))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(hour.consumption ?? 0, specifier: "%.2f") kWh")
                            .font(.caption)
                            .bold()
                    }
                }

                Divider()

                HStack {
                    Text("Average")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(store.websocketTopUsageAverage ?? 0, specifier: "%.2f") kWh")
                        .font(.subheadline)
                        .bold()
                }

                if let updatedAt = store.websocketTopUsageLastUpdated {
                    Text("Updated: \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 15).fill(Color(.systemGray6)))
    }

    private func formatHour(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        if let date = parser.date(from: iso) ?? fallback.date(from: iso) {
            return formatter.string(from: date)
        }

        return iso
    }
}
