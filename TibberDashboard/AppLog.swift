import Foundation
import OSLog

enum LogTopic: String, CaseIterable, Identifiable {
    case camera
    case tibber
    case zaptec
    case hue
    case telegram

    var id: String { rawValue }

    var defaultsKey: String {
        "log.enabled.\(rawValue)"
    }

    var category: String {
        switch self {
        case .camera: return "Camera"
        case .tibber: return "Tibber"
        case .zaptec: return "Zaptec"
        case .hue: return "Hue"
        case .telegram: return "Telegram"
        }
    }
}

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "TibberDashboard"

    static func isEnabled(_ topic: LogTopic) -> Bool {
        if UserDefaults.standard.object(forKey: topic.defaultsKey) == nil {
            // Default: camera on for active debugging, others off.
            return topic == .camera
        }
        return UserDefaults.standard.bool(forKey: topic.defaultsKey)
    }

    static func debug(_ topic: LogTopic, _ message: String) {
        guard isEnabled(topic) else { return }
        let logger = Logger(subsystem: subsystem, category: topic.category)
        logger.debug("\(message, privacy: .public)")
    }

    static func info(_ topic: LogTopic, _ message: String) {
        guard isEnabled(topic) else { return }
        let logger = Logger(subsystem: subsystem, category: topic.category)
        logger.info("\(message, privacy: .public)")
    }

    static func warning(_ topic: LogTopic, _ message: String) {
        guard isEnabled(topic) else { return }
        let logger = Logger(subsystem: subsystem, category: topic.category)
        logger.warning("\(message, privacy: .public)")
    }

    static func error(_ topic: LogTopic, _ message: String) {
        guard isEnabled(topic) else { return }
        let logger = Logger(subsystem: subsystem, category: topic.category)
        logger.error("\(message, privacy: .public)")
    }
}
