import SwiftUI

struct CameraViewSheet: View {
    @Environment(\.dismiss) var dismiss
    let cameraUrl: String
    let cameraUsername: String
    let cameraPassword: String
    @State private var statusMessage: String? = "Connecting..."
    @ObservedObject private var detector = GarageDoorDetector.shared
    @AppStorage("garageDoorDetectionInterval") private var detectionInterval: Int = 5
    @AppStorage("cameraNetworkCachingMs") private var cameraNetworkCachingMs: Int = 1000
    @AppStorage("cameraLiveCachingMs") private var cameraLiveCachingMs: Int = 1000

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                let rtspUrl = constructRtspUrl()

                if rtspUrl.isEmpty {
                    Text("Camera URL not configured")
                        .foregroundColor(.red)
                        .padding()
                } else {
                    CameraView(
                        url: rtspUrl,
                        statusMessage: $statusMessage,
                        onSnapshot: { path in detector.analyze(imagePath: path) },
                        snapshotInterval: TimeInterval(detectionInterval),
                        networkCachingMs: cameraNetworkCachingMs,
                        liveCachingMs: cameraLiveCachingMs
                    )

                    // Door state overlay — top of screen
                    if detector.doorState != .unknown {
                        VStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(detector.doorState == .open ? Color.orange : Color.green)
                                    .frame(width: 10, height: 10)
                                Text(detector.doorState == .open ? "Open" : "Closed")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text(String(format: "%.0f%%", detector.confidence * 100))
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                            .padding(.top, 8)
                            Spacer()
                        }
                    }

                    // Status / error overlay
                    if let message = statusMessage {
                        VStack {
                            Spacer()
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(message.lowercased().contains("error") ? Color.red.opacity(0.85) : Color.black.opacity(0.6))
                                )
                                .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationTitle("Camera")
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
    
    private func constructRtspUrl() -> String {
        guard !cameraUrl.isEmpty, !cameraUsername.isEmpty, !cameraPassword.isEmpty else {
            return ""
        }
        var urlPart = cameraUrl
        if let rangeOfScheme = urlPart.range(of: "rtsp://") {
            urlPart.removeSubrange(urlPart.startIndex..<rangeOfScheme.upperBound)
        }
        if let atIndex = urlPart.firstIndex(of: "@") {
            urlPart.removeSubrange(urlPart.startIndex...atIndex)
        }
        return "rtsp://\(cameraUsername):\(cameraPassword)@\(urlPart)"
    }
}
