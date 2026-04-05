import SwiftUI

struct TopThreeUsageCard: View {
    @ObservedObject var store: TibberMonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Top 3 Hours This Month")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if store.isFetchingTopUsage {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Text("Source: Tibber API")
                .font(.caption2)
                .foregroundColor(.secondary)

            if let error = store.topUsageError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else if store.topUsageHours.isEmpty {
                Text("No usage data available yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(store.topUsageHours.enumerated()), id: \.element.id) { index, hour in
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
                    Text("\(store.topUsageAverage ?? 0, specifier: "%.2f") kWh")
                        .font(.subheadline)
                        .bold()
                }

                if let updatedAt = store.topUsageLastUpdated {
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
