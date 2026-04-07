import SwiftUI

struct CatFeederDetectionWorker: View {
    let cameraUrl: String
    let cameraUsername: String
    let cameraPassword: String

    @ObservedObject private var detector = CatFeederDetector.shared
    @State private var statusMessage: String? = nil
    @AppStorage("catFeederDetectionInterval") private var detectionInterval: Int = 5
    @AppStorage("catFeederCameraNetworkCachingMs") private var cameraNetworkCachingMs: Int = 1000
    @AppStorage("catFeederCameraLiveCachingMs") private var cameraLiveCachingMs: Int = 1000

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
                    liveCachingMs: cameraLiveCachingMs,
                    snapshotFileName: "cat_feeder_snapshot.png"
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
