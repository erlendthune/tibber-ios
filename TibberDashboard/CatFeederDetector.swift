import Foundation
import SwiftUI
import Vision
import CoreML
import OSLog
import Photos

class CatFeederDetector: ObservableObject {
    static let shared = CatFeederDetector()

    enum BowlState: String {
        case empty
        case notEmpty
        case unknown
    }

    @Published var bowlState: BowlState = .unknown
    @Published var confidence: Double = 0
    @Published var lastSnapshot: UIImage? = nil
    @Published var lastSnapshotDate: Date? = nil

    @AppStorage("catFeederDetectionEnabled") var isEnabled: Bool = false
    @AppStorage("catFeederLearnModeEnabled") var learnModeEnabled: Bool = false
    @AppStorage("catFeederLearnModeIntervalMinutes") var learnModeIntervalMinutes: Int = 15
    @AppStorage("catFeederConfidenceThreshold") var confidenceThreshold: Double = 0.75
    @AppStorage("catFeederAlertRepeatMinutes") var alertRepeatMinutes: Int = 30

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TibberDashboard", category: "CatFeederDetector")
    private var vnModel: VNCoreMLModel?
    private var lastKnownState: BowlState = .unknown
    private var lastEmptyAlertTime: Date = .distantPast
    private var lastLearnSnapshotSavedAt: Date = .distantPast

    private init() {
        loadModel()
    }

    private func loadModel() {
        do {
            guard let compiledURL = Bundle.main.url(forResource: "foodbowlclassifier", withExtension: "mlmodelc") else {
                throw NSError(domain: "CatFeederDetector", code: 404, userInfo: [NSLocalizedDescriptionKey: "foodbowlclassifier.mlmodel is not in the app target bundle"])
            }
            let mlModel = try MLModel(contentsOf: compiledURL)
            vnModel = try VNCoreMLModel(for: mlModel)
            logger.debug("CatFeederDetector: model loaded")
            AppLog.info(.camera, "CoreML model loaded for cat feeder detection")
        } catch {
            logger.error("CatFeederDetector: failed to load model - \(error.localizedDescription, privacy: .public)")
            AppLog.error(.camera, "Failed to load cat feeder CoreML model: \(error.localizedDescription)")
        }
    }

    private func deleteSnapshotIfTemporary(_ imagePath: String) {
        let tempDir = NSTemporaryDirectory()
        guard imagePath.hasPrefix(tempDir) else { return }
        do {
            try FileManager.default.removeItem(atPath: imagePath)
            AppLog.debug(.camera, "Deleted temporary cat feeder snapshot at path=\(imagePath)")
        } catch {
            AppLog.debug(.camera, "Cat feeder snapshot cleanup skipped. path=\(imagePath) reason=\(error.localizedDescription)")
        }
    }

    func analyze(imagePath: String) {
        AppLog.debug(.camera, "Cat feeder analyze called with imagePath=\(imagePath)")
        defer { deleteSnapshotIfTemporary(imagePath) }

        guard let image = UIImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage else {
            logger.warning("CatFeederDetector: could not load snapshot at \(imagePath, privacy: .public)")
            AppLog.warning(.camera, "Cat feeder snapshot file could not be loaded. Path=\(imagePath)")
            return
        }

        DispatchQueue.main.async {
            self.lastSnapshot = image
            self.lastSnapshotDate = Date()
        }
        maybeSaveSnapshotToPhotosForLearning(image: image)

        guard isEnabled else {
            AppLog.debug(.camera, "Cat feeder detection disabled in settings; skipping ML inference")
            return
        }
        guard let model = vnModel else {
            logger.warning("CatFeederDetector: model not available, skipping analysis")
            AppLog.warning(.camera, "Cat feeder model unavailable at inference time")
            return
        }

        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let self else { return }
            if let error {
                self.logger.error("CatFeederDetector: request error - \(error.localizedDescription, privacy: .public)")
                AppLog.error(.camera, "Cat feeder vision request error: \(error.localizedDescription)")
                return
            }
            guard let results = request.results as? [VNClassificationObservation],
                  let top = results.first else { return }

            let detectedConfidence = Double(top.confidence)
            guard detectedConfidence >= self.confidenceThreshold else { return }

            let newState: BowlState
            switch top.identifier.lowercased() {
            case "empty":
                newState = .empty
            case "not_empty":
                newState = .notEmpty
            default:
                newState = .unknown
            }

            DispatchQueue.main.async {
                guard newState != self.bowlState else {
                    if detectedConfidence != self.confidence {
                        self.confidence = detectedConfidence
                    }
                    return
                }

                self.confidence = detectedConfidence
                self.bowlState = newState
                self.handleAlertStateTransition(newState)
            }
        }
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                self.logger.error("CatFeederDetector: handler error - \(error.localizedDescription, privacy: .public)")
                AppLog.error(.camera, "Cat feeder vision handler error: \(error.localizedDescription)")
            }
        }
    }

    private func handleAlertStateTransition(_ newState: BowlState) {
        switch newState {
        case .empty:
            if lastKnownState != .empty {
                lastKnownState = .empty
                lastEmptyAlertTime = Date()
                TelegramManager.shared.notifyCatFeeder(isEmpty: true)
                return
            }

            let repeatInterval = TimeInterval(max(1, alertRepeatMinutes) * 60)
            guard Date().timeIntervalSince(lastEmptyAlertTime) >= repeatInterval else { return }

            lastEmptyAlertTime = Date()
            TelegramManager.shared.notifyCatFeeder(isEmpty: true, isReminder: true)

        case .notEmpty:
            let didChange = lastKnownState != .notEmpty
            lastKnownState = .notEmpty
            lastEmptyAlertTime = .distantPast

            if didChange {
                TelegramManager.shared.notifyCatFeeder(isEmpty: false)
            }

        case .unknown:
            break
        }
    }

    private func maybeSaveSnapshotToPhotosForLearning(image: UIImage) {
        guard learnModeEnabled else { return }

        let now = Date()
        let intervalMinutes = max(1, learnModeIntervalMinutes)
        let intervalSeconds = TimeInterval(intervalMinutes * 60)
        guard now.timeIntervalSince(lastLearnSnapshotSavedAt) >= intervalSeconds else { return }

        lastLearnSnapshotSavedAt = now

        let saveToPhotos: () -> Void = {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if success {
                    AppLog.info(.camera, "Cat feeder learn mode saved snapshot to Photos")
                } else if let error {
                    AppLog.error(.camera, "Cat feeder learn mode failed to save snapshot: \(error.localizedDescription)")
                }
            }
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            saveToPhotos()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    saveToPhotos()
                } else {
                    AppLog.warning(.camera, "Cat feeder learn mode photo permission not granted")
                }
            }
        case .denied, .restricted:
            AppLog.warning(.camera, "Cat feeder learn mode cannot save photos because Photos permission is denied/restricted")
        @unknown default:
            AppLog.warning(.camera, "Cat feeder learn mode encountered unknown Photos authorization status")
        }
    }
}
