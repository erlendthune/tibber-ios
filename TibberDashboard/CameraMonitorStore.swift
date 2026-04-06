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
    var onSnapshot: ((String) -> Void)? = nil
    var snapshotInterval: TimeInterval = 5
    var networkCachingMs: Int = 1000
    var liveCachingMs: Int = 1000
    var snapshotFileName: String = "garage_snapshot.png"

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(statusMessage: $statusMessage)
        coordinator.onSnapshot = onSnapshot
        coordinator.snapshotInterval = snapshotInterval
        coordinator.networkCachingMs = networkCachingMs
        coordinator.liveCachingMs = liveCachingMs
        coordinator.snapshotFileName = snapshotFileName
        return coordinator
    }

    func makeUIView(context: Context) -> UIView {
        let videoView = UIView()
        videoView.backgroundColor = .black
        context.coordinator.start(url: url, drawableView: videoView)
        return videoView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.updateConfiguration(
            url: url,
            drawableView: uiView,
            onSnapshot: onSnapshot,
            snapshotInterval: snapshotInterval,
            networkCachingMs: networkCachingMs,
            liveCachingMs: liveCachingMs,
            snapshotFileName: snapshotFileName
        )
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // Ensure VLC is fully detached before SwiftUI removes the view.
        coordinator.stop()
    }

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

        // Garage door detection
        var onSnapshot: ((String) -> Void)? = nil
        var snapshotInterval: TimeInterval = 5
        var networkCachingMs: Int = 1000
        var liveCachingMs: Int = 1000
        var snapshotFileName: String = "garage_snapshot.png"
        private var snapshotTimer: Timer? = nil
        private var snapshotTickCount: Int = 0
        private var lastPlayingAt: Date = .distantPast
        private var isActive: Bool = false

        init(statusMessage: Binding<String?>) {
            _statusMessage = statusMessage
        }

        func start(url: String, drawableView: UIView) {
            stop()
            isActive = true
            self.streamUrl = url
            self.drawableView = drawableView
            AppLog.info(.camera, "CameraView.start called. interval=\(snapshotInterval)s hasSnapshotCallback=\(onSnapshot != nil) networkCachingMs=\(networkCachingMs) liveCachingMs=\(liveCachingMs)")

            // Wait for a valid network path (non-0.0.0.0) before handing
            // the URL to VLC — otherwise VLC logs "invalid IP address: 0.0.0.0"
            // and takes minutes to recover.
            let monitor = NWPathMonitor()
            self.pathMonitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                guard self.isActive else { return }
                guard path.status == .satisfied else { return }
                monitor.cancel()
                self.pathMonitor = nil
                self.logger.debug("rtsp: network ready, connecting")
                AppLog.debug(.camera, "Network path satisfied. Proceeding to connect RTSP stream.")
                DispatchQueue.main.async { self.connect() }
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
        }

        func updateConfiguration(
            url: String,
            drawableView: UIView,
            onSnapshot: ((String) -> Void)?,
            snapshotInterval: TimeInterval,
            networkCachingMs: Int,
            liveCachingMs: Int,
            snapshotFileName: String
        ) {
            let shouldReconnect = self.streamUrl != url
                || self.networkCachingMs != networkCachingMs
                || self.liveCachingMs != liveCachingMs
            
            let intervalChanged = snapshotInterval != self.snapshotInterval

            self.drawableView = drawableView
            self.onSnapshot = onSnapshot
            self.snapshotInterval = snapshotInterval
            self.networkCachingMs = networkCachingMs
            self.liveCachingMs = liveCachingMs
            self.snapshotFileName = snapshotFileName

            if shouldReconnect, isActive {
                AppLog.info(.camera, "CameraView configuration changed. Reconnecting stream with updated settings.")
                start(url: url, drawableView: drawableView)
                return
            }

            if intervalChanged && snapshotTimer != nil {
                AppLog.debug(.camera, "CameraView snapshot interval updated to \(snapshotInterval)s")
                startSnapshotTimer()
            }
        }

        func stop() {
            isActive = false
            reconnectTimer?.invalidate()
            reconnectTimer = nil
            snapshotTimer?.invalidate()
            snapshotTimer = nil
            pathMonitor?.cancel()
            pathMonitor = nil
            connectRetries = 0

            // Capture the player reference NOW so that async blocks below only
            // ever touch this specific player instance. If start() is called
            // immediately after stop(), it will create a new player and set
            // self.mediaPlayer to that new instance — the closures must not
            // accidentally clear the new player.
            let playerToStop = mediaPlayer
            mediaPlayer = nil

            DispatchQueue.main.async {
                playerToStop?.stop()
            }

            // Detach drawable and delegate after a brief delay to let stop() propagate.
            // Only touches the captured player, never self.mediaPlayer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                playerToStop?.delegate = nil
                playerToStop?.drawable = nil
            }

            AppLog.debug(.camera, "CameraView.stop completed")
        }

        private var connectRetries = 0

        private func connect() {
            guard isActive else { return }
            reconnectTimer?.invalidate()
            reconnectTimer = nil

            // Ensure the drawable view is fully in the window hierarchy before
            // VLC creates its internal VLCOpenGLES2VideoView — otherwise its
            // background pthread will modify layer properties off the main thread.
            if drawableView?.window == nil {
                connectRetries += 1
                AppLog.debug(.camera, "Drawable has no window yet. retry=\(connectRetries)")
                if connectRetries < 20 { // retry up to ~2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        self?.connect()
                    }
                    return
                }
                logger.warning("rtsp: drawable view still has no window after retries, proceeding anyway")
                AppLog.warning(.camera, "Drawable still has no window after retries; continuing anyway.")
            }
            connectRetries = 0

            guard let streamUrl = URL(string: streamUrl) else {
                logger.error("rtsp: Invalid URL: \(self.streamUrl, privacy: .public)")
                AppLog.error(.camera, "Invalid RTSP URL format: \(self.streamUrl)")
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
            media.addOption(":network-caching=\(networkCachingMs)")
            media.addOption(":live-caching=\(liveCachingMs)")
            // Improve snapshot reliability on iOS by forcing software decode.
            media.addOption(":no-hw-dec")
            media.addOption(":no-videotoolbox")
            media.addOption(":drop-late-frames")
            media.addOption(":skip-frames")
            media.addOption(":clock-jitter=0")
            media.addOption(":clock-synchro=0")
            media.addOption(":no-audio")
            player.media = media
            player.play()
            logger.debug("rtsp: connecting to \(self.streamUrl, privacy: .public)")
            AppLog.info(.camera, "VLC play() issued for stream. networkCachingMs=\(networkCachingMs) liveCachingMs=\(liveCachingMs)")

            // If still not playing after 10 s, reconnect automatically
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                guard let self, self.isActive, self.mediaPlayer?.state != .playing else { return }
                self.logger.debug("rtsp: reconnect triggered (was not playing after 10s)")
                AppLog.warning(.camera, "Reconnect timer fired. Player not in .playing state after 10s.")
                self.mediaPlayer?.stop()
                self.mediaPlayer = nil
                self.connect()
            }
        }

        private func startSnapshotTimer() {
            snapshotTimer?.invalidate()
            snapshotTickCount = 0
            guard onSnapshot != nil else {
                AppLog.debug(.camera, "Snapshot timer not started: onSnapshot callback is nil.")
                return
            }
            AppLog.info(.camera, "Starting snapshot timer at interval=\(snapshotInterval)s")
            snapshotTimer = Timer.scheduledTimer(withTimeInterval: snapshotInterval, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.snapshotTickCount += 1
                guard self.isActive else {
                    AppLog.debug(.camera, "Snapshot tick #\(self.snapshotTickCount) skipped: coordinator inactive")
                    return
                }
                guard let player = self.mediaPlayer else {
                    AppLog.debug(.camera, "Snapshot tick #\(self.snapshotTickCount) skipped: no mediaPlayer")
                    return
                }
                guard let drawable = self.drawableView, drawable.window != nil else {
                    AppLog.debug(.camera, "Snapshot tick #\(self.snapshotTickCount) skipped: drawable not in window hierarchy")
                    return
                }
                // RTSP streams often don't reach state==.playing due to continuous buffering.
                // Check numberOfVideoTracks: if > 0, the video stream is actively being decoded.
                guard player.numberOfVideoTracks > 0 else {
                    AppLog.debug(.camera, "Snapshot tick #\(self.snapshotTickCount) skipped: no video tracks detected yet (state=\(self.describe(state: player.state)))")
                    return
                }
                let stableSeconds = Date().timeIntervalSince(self.lastPlayingAt)
                guard stableSeconds >= 3.0 else {
                    AppLog.debug(.camera, "Snapshot tick #\(self.snapshotTickCount) skipped: stream not stable yet (\(String(format: "%.2f", stableSeconds))s)")
                    return
                }
                let path = NSTemporaryDirectory() + self.snapshotFileName
                try? FileManager.default.removeItem(atPath: path)
                player.saveVideoSnapshot(at: path, withWidth: 0, andHeight: 0)
                AppLog.debug(.camera, "Snapshot tick #\(self.snapshotTickCount): snapshot requested (videoTracks=\(player.numberOfVideoTracks))")
            }
        }

        func mediaPlayerStateChanged(_ aNotification: Notification) {
            guard isActive else { return }
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            let state = player.state
            let stateDescription: String
            switch state {
            case .opening:    stateDescription = "Opening stream..."
            case .buffering:
                // For RTSP streams, buffering is normal even when video is visible.
                // If video tracks are detected but timer isn't started yet, start now.
                if player.numberOfVideoTracks > 0 && snapshotTimer == nil && onSnapshot != nil {
                    AppLog.info(.camera, "Stream has video tracks during buffering state; starting snapshot timer (videoTracks=\(player.numberOfVideoTracks))")
                    lastPlayingAt = Date()
                    DispatchQueue.main.async { self.startSnapshotTimer() }
                }
                stateDescription = "Buffering..."
            case .playing:
                reconnectTimer?.invalidate()
                reconnectTimer = nil
                lastPlayingAt = Date()
                logger.debug("rtsp: playing")
                AppLog.info(.camera, "Player entered .playing state")
                DispatchQueue.main.async {
                    self.statusMessage = nil
                    self.startSnapshotTimer()
                }
                return
            case .paused:     stateDescription = "Paused"
            case .stopped:
                snapshotTimer?.invalidate()
                snapshotTimer = nil
                AppLog.debug(.camera, "Player stopped. Snapshot timer invalidated.")
                stateDescription = "Stopped"
            case .error:
                snapshotTimer?.invalidate()
                snapshotTimer = nil
                AppLog.error(.camera, "Player error state reached. Snapshot timer invalidated.")
                stateDescription = "Stream error — check URL and credentials"
            case .ended:
                snapshotTimer?.invalidate()
                snapshotTimer = nil
                AppLog.debug(.camera, "Player ended. Snapshot timer invalidated.")
                stateDescription = "Stream ended"
            default:          return
            }
            logger.debug("rtsp: \(stateDescription, privacy: .public)")
            AppLog.debug(.camera, "Player state changed: \(stateDescription)")
            DispatchQueue.main.async { self.statusMessage = stateDescription }
        }

        @objc func mediaPlayerSnapshot(_ aNotification: Notification) {
            guard isActive else { return }
            guard aNotification.object as? VLCMediaPlayer != nil else {
                AppLog.warning(.camera, "mediaPlayerSnapshot called without VLCMediaPlayer object")
                return
            }
            let path = NSTemporaryDirectory() + snapshotFileName
            AppLog.debug(.camera, "mediaPlayerSnapshot delegate called for path: \(path)")
            if UIImage(contentsOfFile: path) != nil {
                AppLog.info(.camera, "Snapshot file ready; invoking callback")
                self.onSnapshot?(path)
            } else {
                AppLog.warning(.camera, "Snapshot file not found at path: \(path)")
            }
        }

        private func describe(state: VLCMediaPlayerState) -> String {
            switch state {
            case .opening: return "opening"
            case .buffering: return "buffering"
            case .playing: return "playing"
            case .paused: return "paused"
            case .stopped: return "stopped"
            case .error: return "error"
            case .ended: return "ended"
            case .esAdded: return "esAdded"
            default: return "unknown(\(state.rawValue))"
            }
        }
    }
}
