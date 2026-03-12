import Foundation
import AVFoundation

class AudioPlayer {
    static let shared = AudioPlayer()
    var player: AVAudioPlayer?
    var lastAlertLevel: AlertLevel = .none
    var lastAlertTime: Date = .distantPast

    enum AlertLevel {
        case warning, critical, none
    }

    func playAlert(level: AlertLevel) {
        // Enforce cooldown (e.g. 30 seconds) to avoid spam
        let now = Date()
        if level == lastAlertLevel && now.timeIntervalSince(lastAlertTime) < 30 {
            return
        }
        
        lastAlertLevel = level
        lastAlertTime = now
        
        // Ensure AVAudioSession logic is set appropriately
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session: \(error.localizedDescription)")
        }

        let systemSoundID: SystemSoundID = level == .critical ? 1016 : 1005
        AudioServicesPlaySystemSound(systemSoundID)
    }
}
