import SwiftUI

struct CatFeederLiveFeedCard: View {
    let cameraUrl: String
    let cameraUsername: String
    let cameraPassword: String
    let isActive: Bool

    @ObservedObject private var detector = CatFeederDetector.shared
    @State private var statusMessage: String? = "Connecting..."
    @AppStorage("catFeederDetectionInterval") private var detectionInterval: Int = 5
    @AppStorage("catFeederCameraNetworkCachingMs") private var cameraNetworkCachingMs: Int = 1000
    @AppStorage("catFeederCameraLiveCachingMs") private var cameraLiveCachingMs: Int = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "video.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Cat Feeder Camera")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            let rtspUrl = constructRtspUrl()
            if rtspUrl.isEmpty {
                Text("Camera URL not configured")
                    .font(.caption)
                    .foregroundColor(.red)
            } else if !isActive {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Live feed paused on this page")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                CameraView(
                    url: rtspUrl,
                    statusMessage: $statusMessage,
                    onSnapshot: { path in detector.analyze(imagePath: path) },
                    snapshotInterval: TimeInterval(max(1, detectionInterval)),
                    networkCachingMs: cameraNetworkCachingMs,
                    liveCachingMs: cameraLiveCachingMs,
                    snapshotFileName: "cat_feeder_snapshot.png"
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 15).fill(Color(.systemGray6)))
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
