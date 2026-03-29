import Foundation
import SwiftUI
import OSLog
import Combine
import UIKit
import Network
import MobileVLCKit

struct CameraView: UIViewRepresentable {
    let url: String
    @Binding var statusMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(statusMessage: $statusMessage)
    }

    func makeUIView(context: Context) -> UIView {
        let videoView = UIView()
        videoView.backgroundColor = .black
        context.coordinator.start(url: url, drawableView: videoView)
        return videoView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func takeSnapshot(context: Context) {
        let path = NSTemporaryDirectory() + "snapshot.png"
        context.coordinator.mediaPlayer?.saveVideoSnapshot(at: path, withWidth: 0, andHeight: 0)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, VLCMediaPlayerDelegate {
        @Binding var statusMessage: String?
        // Created lazily at play time so the network stack is ready
        var mediaPlayer: VLCMediaPlayer?
        private var drawableView: UIView?
        private var streamUrl: String = ""
        private var reconnectTimer: Timer?
        private var pathMonitor: NWPathMonitor?
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TibberDashboard", category: "CameraView")

        init(statusMessage: Binding<String?>) {
            _statusMessage = statusMessage
        }

        func start(url: String, drawableView: UIView) {
            self.streamUrl = url
            self.drawableView = drawableView

            // Wait for a valid network path (non-0.0.0.0) before handing
            // the URL to VLC — otherwise VLC logs "invalid IP address: 0.0.0.0"
            // and takes minutes to recover.
            let monitor = NWPathMonitor()
            self.pathMonitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                guard path.status == .satisfied else { return }
                monitor.cancel()
                self.pathMonitor = nil
                self.logger.debug("rtsp: network ready, connecting")
                DispatchQueue.main.async { self.connect() }
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
        }

        private var connectRetries = 0

        private func connect() {
            reconnectTimer?.invalidate()
            reconnectTimer = nil

            // Ensure the drawable view is fully in the window hierarchy before
            // VLC creates its internal VLCOpenGLES2VideoView — otherwise its
            // background pthread will modify layer properties off the main thread.
            if drawableView?.window == nil {
                connectRetries += 1
                if connectRetries < 20 { // retry up to ~2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        self?.connect()
                    }
                    return
                }
                logger.warning("rtsp: drawable view still has no window after retries, proceeding anyway")
            }
            connectRetries = 0

            guard let streamUrl = URL(string: streamUrl) else {
                logger.error("rtsp: Invalid URL: \(self.streamUrl, privacy: .public)")
                DispatchQueue.main.async { self.statusMessage = "Invalid URL" }
                return
            }

            // Create player without options — we'll set them on the media instead
            // using addOption() (singular) which passes raw strings directly to libvlc.
            let player = VLCMediaPlayer()
            player.delegate = self
            player.drawable = drawableView
            self.mediaPlayer = player

            let media = VLCMedia(url: streamUrl)
            // Force RTSP interleaved TCP transport — this is what prevents the
            // "invalid IP address: 0.0.0.0" error (VLC won't try to open UDP ports).
            // MobileVLCKit addOption() uses ":" prefix, not "--".
            media.addOption(":rtsp-tcp")
            media.addOption(":network-caching=150")
            media.addOption(":live-caching=150")
            media.addOption(":drop-late-frames")
            media.addOption(":skip-frames")
            media.addOption(":clock-jitter=0")
            media.addOption(":clock-synchro=0")
            media.addOption(":no-audio")
            player.media = media
            player.play()
            logger.debug("rtsp: connecting to \(self.streamUrl, privacy: .public)")

            // If still not playing after 10 s, reconnect automatically
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                guard let self, self.mediaPlayer?.state != .playing else { return }
                self.logger.debug("rtsp: reconnect triggered (was not playing after 10s)")
                print("[rtsp] Reconnecting...")
                self.mediaPlayer?.stop()
                self.mediaPlayer = nil
                self.connect()
            }
        }

        func mediaPlayerStateChanged(_ aNotification: Notification) {
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            let state = player.state
            let stateDescription: String
            switch state {
            case .opening:    stateDescription = "Opening stream..."
            case .buffering:  stateDescription = "Buffering..."
            case .playing:
                reconnectTimer?.invalidate()
                reconnectTimer = nil
                logger.debug("rtsp: playing")
                DispatchQueue.main.async { self.statusMessage = nil }
                return
            case .paused:     stateDescription = "Paused"
            case .stopped:    stateDescription = "Stopped"
            case .error:      stateDescription = "Stream error — check URL and credentials"
            case .ended:      stateDescription = "Stream ended"
            default:          return
            }
            logger.debug("rtsp: \(stateDescription, privacy: .public)")
            print("[rtsp] Player state: \(stateDescription)")
            DispatchQueue.main.async { self.statusMessage = stateDescription }
        }
    }
}