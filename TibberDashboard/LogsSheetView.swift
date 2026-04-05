import SwiftUI

struct LogsSheetView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store: TibberMonitorStore
    @State private var selectedLogTab = 0 // 0 for Connection, 1 for Data
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Log Type", selection: Binding(
                    get: { self.selectedLogTab },
                    set: { newValue in self.selectedLogTab = newValue }
                )) {
                    Text("Connection log").tag(0)
                    Text("Data log").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                if selectedLogTab == 0 {
                    // Connection Log
                    ScrollView {
                        ScrollViewReader { proxy in
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(store.connectionLogs.indices, id: \.self) { index in
                                    Text(store.connectionLogs[index])
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(.systemGray6))
                } else {
                    // Data Log
                    ScrollView {
                        ScrollViewReader { proxy in
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(store.dataLogs.indices, id: \.self) { index in
                                    Text(store.dataLogs[index])
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(.systemGray6))
                }
            }
            .navigationTitle("Diagnostics Logs")
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
