import Foundation
import SwiftUI
import Vision
import CoreML
import OSLog

class GarageDoorDetector: ObservableObject {
    static let shared = GarageDoorDetector()

    enum DoorState: String {
        case open, closed, unknown
    }

    @Published var doorState: DoorState = .unknown
    @Published var confidence: Double = 0
    @Published var lastSnapshot: UIImage? = nil
    @Published var lastSnapshotDate: Date? = nil

    @AppStorage("garageDoorDetectionEnabled") var isEnabled: Bool = false
    @AppStorage("garageDoorConfidenceThreshold") var confidenceThreshold: Double = 0.75
    @AppStorage("garageDoorAlertRepeatMinutes") var alertRepeatMinutes: Int = 5

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TibberDashboard", category: "GarageDoorDetector")
    private var vnModel: VNCoreMLModel?
    private var lastKnownState: DoorState = .unknown
    private var lastOpenAlertTime: Date = .distantPast

    private func deleteSnapshotIfTemporary(_ imagePath: String) {
        let tempDir = NSTemporaryDirectory()
        guard imagePath.hasPrefix(tempDir) else { return }
        do {
            try FileManager.default.removeItem(atPath: imagePath)
            AppLog.debug(.camera, "Deleted temporary snapshot at path=\(imagePath)")
        } catch {
            // Best-effort cleanup. It's normal for the file to already be gone.
            AppLog.debug(.camera, "Temporary snapshot cleanup skipped. path=\(imagePath) reason=\(error.localizedDescription)")
        }
    }

    private init() {
        do {
            let mlModel = try garagedoorclassifier(configuration: MLModelConfiguration()).model
            vnModel = try VNCoreMLModel(for: mlModel)
            logger.debug("GarageDoorDetector: model loaded")
            AppLog.info(.camera, "CoreML model loaded for garage door detection")
        } catch {
            logger.error("GarageDoorDetector: failed to load model — \(error.localizedDescription, privacy: .public)")
            AppLog.error(.camera, "Failed to load CoreML model: \(error.localizedDescription)")
        }
    }

    func analyze(imagePath: String) {
        AppLog.debug(.camera, "Analyze called with imagePath=\(imagePath)")
                defer { deleteSnapshotIfTemporary(imagePath) }

        guard let image = UIImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage else {
            logger.warning("GarageDoorDetector: could not load snapshot at \(imagePath, privacy: .public)")
            AppLog.warning(.camera, "Snapshot file could not be loaded. Path=\(imagePath)")
            return
        }

        DispatchQueue.main.async {
            self.lastSnapshot = image
            self.lastSnapshotDate = Date()
        }
        AppLog.debug(.camera, "Snapshot loaded and published to UI")

        guard isEnabled else {
            AppLog.debug(.camera, "Detection disabled in settings; skipping ML inference")
            return
        }
        guard let model = vnModel else {
            logger.warning("GarageDoorDetector: model not available, skipping analysis")
            AppLog.warning(.camera, "Model unavailable at inference time")
            return
        }

        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let self else { return }
            if let error {
                self.logger.error("GarageDoorDetector: request error — \(error.localizedDescription, privacy: .public)")
                AppLog.error(.camera, "Vision request error: \(error.localizedDescription)")
                return
            }
            guard let results = request.results as? [VNClassificationObservation],
                  let top = results.first else { return }

            let detectedConfidence = Double(top.confidence)
            guard detectedConfidence >= self.confidenceThreshold else {
                self.logger.debug("GarageDoorDetector: low confidence \(detectedConfidence, format: .fixed(precision: 2), privacy: .public) for '\(top.identifier, privacy: .public)' — skipping")
                AppLog.debug(.camera, "Low confidence result ignored. label=\(top.identifier) confidence=\(detectedConfidence) threshold=\(self.confidenceThreshold)")
                return
            }

            let newState: DoorState
            switch top.identifier.lowercased() {
            case "open":   newState = .open
            case "closed": newState = .closed
            default:       newState = .unknown
            }

            self.logger.debug("GarageDoorDetector: \(newState.rawValue, privacy: .public) @ \(detectedConfidence, format: .fixed(precision: 2), privacy: .public)")
            AppLog.info(.camera, "Detection accepted. label=\(top.identifier) mappedState=\(newState.rawValue) confidence=\(detectedConfidence)")

            DispatchQueue.main.async {
                self.confidence = detectedConfidence
                self.doorState = newState
                self.handleAlertStateTransition(newState)
            }
        }
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                self.logger.error("GarageDoorDetector: handler error — \(error.localizedDescription, privacy: .public)")
                AppLog.error(.camera, "Vision handler error: \(error.localizedDescription)")
            }
        }
    }

    private func handleAlertStateTransition(_ newState: DoorState) {
        switch newState {
        case .open:
            if lastKnownState != .open {
                lastKnownState = .open
                lastOpenAlertTime = Date()
                AppLog.info(.camera, "Door state changed to open. Triggering Telegram alert.")
                TelegramManager.shared.notifyGarageDoor(isOpen: true)
                return
            }

            let repeatInterval = TimeInterval(max(1, alertRepeatMinutes) * 60)
            guard Date().timeIntervalSince(lastOpenAlertTime) >= repeatInterval else { return }

            lastOpenAlertTime = Date()
            AppLog.info(.camera, "Door still open. Triggering repeated Telegram alert after \(alertRepeatMinutes) minute(s).")
            TelegramManager.shared.notifyGarageDoor(isOpen: true, isReminder: true)

        case .closed:
            let didChange = lastKnownState != .closed
            lastKnownState = .closed
            lastOpenAlertTime = .distantPast

            if didChange {
                AppLog.info(.camera, "Door state changed to closed. Triggering Telegram alert.")
                TelegramManager.shared.notifyGarageDoor(isOpen: false)
            }

        case .unknown:
            break
        }
    }
}
