import SwiftUI

// MARK: - Background detection worker (hidden)
// Mounts an invisible CameraView so detection runs even when the live-feed
// page is not selected. The parent must hide this view when the live-feed
// page or camera sheet is visible to avoid dual RTSP sessions.
struct GarageDoorDetectionWorker: View {
    let cameraUrl: String
    let cameraUsername: String
    let cameraPassword: String

    @ObservedObject private var detector = GarageDoorDetector.shared
    @State private var statusMessage: String? = nil
    @AppStorage("garageDoorDetectionInterval") private var detectionInterval: Int = 5
    @AppStorage("cameraNetworkCachingMs") private var cameraNetworkCachingMs: Int = 1000
    @AppStorage("cameraLiveCachingMs") private var cameraLiveCachingMs: Int = 1000

    var body: some View {
        let rtspUrl = constructRtspUrl()
        Group {
            if !rtspUrl.isEmpty {
                CameraView(
                    url: rtspUrl,
                    statusMessage: $statusMessage,
                    onSnapshot: { path in detector.analyze(imagePath: path) },
                    snapshotInterval: TimeInterval(max(1, detectionInterval)),
                    networkCachingMs: cameraNetworkCachingMs,
                    liveCachingMs: cameraLiveCachingMs
                )
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
