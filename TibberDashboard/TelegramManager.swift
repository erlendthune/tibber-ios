import Foundation
import SwiftUI

class TelegramManager: ObservableObject {
    static let shared = TelegramManager()

    @AppStorage("telegramBotToken") var botToken: String = ""
    @AppStorage("telegramEnabled") var isEnabled: Bool = false

    @Published var chatRecipients: [TelegramChatRecipient] = [] {
        didSet { saveRecipients() }
    }

    private let recipientsKey = "telegramChatRecipients"

    private init() {
        loadRecipients()
    }

    // MARK: - Recipient management

    struct TelegramChatRecipient: Identifiable, Codable {
        var id: UUID = UUID()
        var name: String
        var chatId: String
    }

    func addRecipient(name: String, chatId: String) {
        chatRecipients.append(TelegramChatRecipient(name: name, chatId: chatId))
    }

    func removeRecipients(at offsets: IndexSet) {
        chatRecipients.remove(atOffsets: offsets)
    }

    private func saveRecipients() {
        if let data = try? JSONEncoder().encode(chatRecipients) {
            UserDefaults.standard.set(data, forKey: recipientsKey)
        }
    }

    private func loadRecipients() {
        guard let data = UserDefaults.standard.data(forKey: recipientsKey),
              let decoded = try? JSONDecoder().decode([TelegramChatRecipient].self, from: data) else {
            return
        }
        chatRecipients = decoded
    }

    // MARK: - Notifications

    private var lastAlertTime: Date = .distantPast
    private let alertCooldown: TimeInterval = 15 * 60 // 15 minutes

    enum TelegramSendResult {
        case success
        case failure(String)
    }

    // MARK: - Garage Door Alerts

    private var lastGarageDoorAlertTime: Date = .distantPast
    private var lastAlertedDoorState: Bool? = nil
    private let garageDoorAlertCooldown: TimeInterval = 5 * 60 // 5 minutes

    func notifyGarageDoor(isOpen: Bool) {
        guard isEnabled, !botToken.isEmpty else { return }

        let now = Date()
        // Always send on state change; apply cooldown only for repeated same-state alerts
        if lastAlertedDoorState == isOpen {
            guard now.timeIntervalSince(lastGarageDoorAlertTime) >= garageDoorAlertCooldown else { return }
        }
        lastGarageDoorAlertTime = now
        lastAlertedDoorState = isOpen

        let stateText = isOpen ? "OPEN" : "CLOSED"
        let text = "🚗 *Garage door is now \(stateText)*"

        for recipient in chatRecipients {
            guard !recipient.chatId.isEmpty else { continue }

            let urlString = "https://api.telegram.org/bot\(botToken)/sendMessage?chat_id=\(recipient.chatId)&text=\(text)&parse_mode=Markdown"
            guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: encoded) else { continue }

            URLSession.shared.dataTask(with: url) { _, _, error in
                if let error = error {
                    print("Garage door Telegram alert failed for \(recipient.name): \(error.localizedDescription)")
                } else {
                    print("Garage door alert (\(stateText)) sent to \(recipient.name)!")
                }
            }.resume()
        }
    }

    func notifyTelegram(powerValue: Double) {
        guard isEnabled, !botToken.isEmpty else { return }

        let now = Date()
        guard now.timeIntervalSince(lastAlertTime) >= alertCooldown else { return }
        lastAlertTime = now

        let text = "⚡️ *High Usage Detected!*\nCurrent load: \(Int(powerValue))W"

        for recipient in chatRecipients {
            guard !recipient.chatId.isEmpty else { continue }

            let urlString = "https://api.telegram.org/bot\(botToken)/sendMessage?chat_id=\(recipient.chatId)&text=\(text)&parse_mode=Markdown"

            guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: encoded) else {
                continue
            }

            URLSession.shared.dataTask(with: url) { _, _, error in
                if let error = error {
                    print("Telegram alert failed for \(recipient.name): \(error.localizedDescription)")
                } else {
                    print("Alert sent to \(recipient.name)!")
                }
            }.resume()
        }
    }

    func sendTestMessage(to recipient: TelegramChatRecipient, completion: @escaping (TelegramSendResult) -> Void) {
        let trimmedToken = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedChatId = recipient.chatId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedToken.isEmpty else {
            completion(.failure("Missing bot token"))
            return
        }

        guard !trimmedChatId.isEmpty else {
            completion(.failure("Missing chat ID"))
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let text = "Tibber Dashboard test message for \(recipient.name). Time: \(timestamp)"
        let urlString = "https://api.telegram.org/bot\(trimmedToken)/sendMessage?chat_id=\(trimmedChatId)&text=\(text)"

        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else {
            completion(.failure("Failed to build Telegram request URL"))
            return
        }

        URLSession.shared.dataTask(with: url) { _, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error.localizedDescription))
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                DispatchQueue.main.async {
                    completion(.failure("Telegram returned HTTP \(httpResponse.statusCode)"))
                }
                return
            }

            DispatchQueue.main.async {
                completion(.success)
            }
        }.resume()
    }
}
