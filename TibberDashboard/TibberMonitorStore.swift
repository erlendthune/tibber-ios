import Foundation
import Combine
import SwiftUI
import OSLog
import AVFoundation

class TibberMonitorStore: ObservableObject {
    @AppStorage("apiKey") var apiKey: String = ""
    @AppStorage("homeId") var homeId: String = ""
    
    @AppStorage("criticalThreshold") var criticalThreshold: Double = 5.0 // kWh or kW target
    
    @AppStorage("breachCount") var breachCount: Int = 0
    @AppStorage("lastBreachMonth") var lastBreachMonth: Int = Calendar.current.component(.month, from: Date())
    
    @AppStorage("idleTimerMinutes") var idleTimerMinutes: Double = 5.0
    @AppStorage("showMonthlyTop3Usage") var showMonthlyTop3Usage: Bool = false
    @AppStorage("showWebsocketTop3Usage") var showWebsocketTop3Usage: Bool = false
    @AppStorage("lastTopUsageMonthKey") var lastTopUsageMonthKey: String = ""
    @AppStorage("lastWebsocketTopUsageMonthKey") var lastWebsocketTopUsageMonthKey: String = ""
    @AppStorage("websocketTrackedHourKey") var websocketTrackedHourKey: String = ""
    @AppStorage("websocketTrackedHourFrom") var websocketTrackedHourFrom: String = ""
    @AppStorage("websocketTrackedHourTo") var websocketTrackedHourTo: String = ""
    @AppStorage("websocketTrackedHourMax") var websocketTrackedHourMax: Double = 0.0

    @Published var liveData: LiveMeasurement?
    @Published var isConnected = false
    @Published var connectionError: String?
    @Published var isScreensaverActive = false
    @Published var isDataStale = false {
        didSet {
            if isDataStale {
                AudioPlayer.shared.playAlert(level: .warning)
            }
        }
    }

    @Published var availableHomes: [Home] = []
    @Published var isFetchingHomes = false
    @Published var fetchHomesError: String?
    @Published var topUsageHours: [HourlyConsumptionNode] = []
    @Published var topUsageAverage: Double?
    @Published var topUsageError: String?
    @Published var isFetchingTopUsage = false
    @Published var topUsageLastUpdated: Date?
    @Published var topUsageRawResponse: String = ""
    @Published var websocketTopUsageHours: [HourlyConsumptionNode] = []
    @Published var websocketTopUsageAverage: Double?
    @Published var websocketTopUsageLastUpdated: Date?
    
    // Console log
    @Published var connectionLogs: [String] = []
    @Published var dataLogs: [String] = []

    private var webSocketTask: URLSessionWebSocketTask?
    private var inactivityTimer: Timer?
    private var staleDataTimer: Timer?
    private var pingTimer: Timer?
    private let logger = Logger(subsystem: "com.erlendthune.tibber", category: "MonitorStore")
    private let topUsageCacheKey = "monthlyTopUsageCache"
    private let websocketTopUsageCacheKey = "monthlyTopUsageCache_websocket"
    private let isoFormatter = ISO8601DateFormatter()
    
    // We keep track of the latest recorded average to trigger resets if it clears
    private var lastRecordedAverage: Double = 0.0
    
    // Connection state tracking
    private var isConnecting = false
    private var reconnectAttempt = 0
    private var isReconnecting = false

    init() {
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        loadTopUsageFromCacheIfValid()
        loadWebsocketTopUsageFromCacheIfValid()
    }

    private func tlog(_ message: String) {
        AppLog.debug(.tibber, message)
    }

    func refreshTopUsage(force: Bool = false) {
        resetTopUsageIfNeeded()

        guard showMonthlyTop3Usage else {
            clearTopUsageDisplay()
            return
        }

        guard !apiKey.isEmpty, !homeId.isEmpty else {
            topUsageError = "Missing API Key or Home ID"
            return
        }

        if !force,
           let cache = loadTopUsageCache(),
           cache.monthKey == currentMonthKey() {
            applyTopUsage(topHours: cache.topHours, average: cache.average, updatedAt: cache.updatedAt)
            return
        }

        fetchTopUsageFromApi()
    }

    func clearTopUsageDisplay() {
        topUsageHours = []
        topUsageAverage = nil
        topUsageError = nil
        isFetchingTopUsage = false
    }

    private func trackWebsocketTopUsage(measurement: LiveMeasurement) {
        guard let measurementDate = parseIsoDate(measurement.timestamp) else { return }

        resetWebsocketTopUsageIfNeeded(referenceDate: measurementDate)

        let calendar = Calendar.current
        guard let hourStart = calendar.dateInterval(of: .hour, for: measurementDate)?.start,
              let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) else { return }

        let hourKey = hourStorageKey(for: hourStart)
        let accumulatedKWh = max(0.0, measurement.accumulatedConsumptionLastHour ?? 0.0)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let hourFromString = formatter.string(from: hourStart)
        let hourToString = formatter.string(from: hourEnd)

        if websocketTrackedHourKey.isEmpty {
            websocketTrackedHourKey = hourKey
            websocketTrackedHourFrom = hourFromString
            websocketTrackedHourTo = hourToString
            websocketTrackedHourMax = accumulatedKWh
            publishWebsocketTopUsage()
            return
        }

        if websocketTrackedHourKey == hourKey {
            if accumulatedKWh > websocketTrackedHourMax {
                websocketTrackedHourMax = accumulatedKWh
            }
            publishWebsocketTopUsage()
            return
        }

        finalizeTrackedWebsocketHour()
        websocketTrackedHourKey = hourKey
        websocketTrackedHourFrom = hourFromString
        websocketTrackedHourTo = hourToString
        websocketTrackedHourMax = accumulatedKWh
        publishWebsocketTopUsage()
    }

    private func finalizeTrackedWebsocketHour() {
        guard !websocketTrackedHourFrom.isEmpty, !websocketTrackedHourTo.isEmpty else { return }

        let trackedNode = HourlyConsumptionNode(
            from: websocketTrackedHourFrom,
            to: websocketTrackedHourTo,
            consumption: websocketTrackedHourMax
        )

        let persisted = loadWebsocketTopUsageCache()?.topHours ?? []
        let merged = mergeTopThree(existing: persisted, with: trackedNode)
        guard let average = calculateAverage(for: merged) else { return }
        let now = Date()

        saveWebsocketTopUsageCache(
            MonthlyTopUsageCache(
                monthKey: currentMonthKey(),
                topHours: merged,
                average: average,
                updatedAt: now
            )
        )
        lastWebsocketTopUsageMonthKey = currentMonthKey()
        websocketTopUsageHours = merged
        websocketTopUsageAverage = average
        websocketTopUsageLastUpdated = now
    }

    private func publishWebsocketTopUsage() {
        var nodes = loadWebsocketTopUsageCache()?.topHours ?? []

        if !websocketTrackedHourFrom.isEmpty, !websocketTrackedHourTo.isEmpty {
            let trackedNode = HourlyConsumptionNode(
                from: websocketTrackedHourFrom,
                to: websocketTrackedHourTo,
                consumption: websocketTrackedHourMax
            )
            nodes = mergeTopThree(existing: nodes, with: trackedNode)
        }

        websocketTopUsageHours = nodes
        websocketTopUsageAverage = calculateAverage(for: nodes)
        websocketTopUsageLastUpdated = Date()
    }

    private func mergeTopThree(existing: [HourlyConsumptionNode], with node: HourlyConsumptionNode) -> [HourlyConsumptionNode] {
        var uniqueByHour: [String: HourlyConsumptionNode] = Dictionary(uniqueKeysWithValues: existing.map { ($0.from, $0) })
        if let old = uniqueByHour[node.from], (old.consumption ?? 0) > (node.consumption ?? 0) {
            uniqueByHour[node.from] = old
        } else {
            uniqueByHour[node.from] = node
        }

        return Array(uniqueByHour.values)
            .sorted { ($0.consumption ?? 0) > ($1.consumption ?? 0) }
            .prefix(3)
            .map { $0 }
    }

    private func calculateAverage(for nodes: [HourlyConsumptionNode]) -> Double? {
        guard !nodes.isEmpty else { return nil }
        let sum = nodes.reduce(0.0) { $0 + ($1.consumption ?? 0) }
        return sum / Double(nodes.count)
    }

    private func resetWebsocketTopUsageIfNeeded(referenceDate: Date) {
        let key = monthKey(for: referenceDate)
        if lastWebsocketTopUsageMonthKey != key {
            removeWebsocketTopUsageCache()
            websocketTopUsageHours = []
            websocketTopUsageAverage = nil
            websocketTopUsageLastUpdated = nil
            websocketTrackedHourKey = ""
            websocketTrackedHourFrom = ""
            websocketTrackedHourTo = ""
            websocketTrackedHourMax = 0.0
            lastWebsocketTopUsageMonthKey = key
        }
    }

    private func monthKey(for date: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return String(format: "%04d-%02d", year, month)
    }

    private func hourStorageKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func loadWebsocketTopUsageFromCacheIfValid() {
        guard let cache = loadWebsocketTopUsageCache(), cache.monthKey == currentMonthKey() else { return }
        websocketTopUsageHours = cache.topHours
        websocketTopUsageAverage = cache.average
        websocketTopUsageLastUpdated = cache.updatedAt
        lastWebsocketTopUsageMonthKey = cache.monthKey
    }

    private func loadWebsocketTopUsageCache() -> MonthlyTopUsageCache? {
        guard let data = UserDefaults.standard.data(forKey: websocketTopUsageCacheKey) else { return nil }
        return try? JSONDecoder().decode(MonthlyTopUsageCache.self, from: data)
    }

    private func saveWebsocketTopUsageCache(_ cache: MonthlyTopUsageCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: websocketTopUsageCacheKey)
    }

    private func removeWebsocketTopUsageCache() {
        UserDefaults.standard.removeObject(forKey: websocketTopUsageCacheKey)
    }

    private func fetchTopUsageFromApi() {
        isFetchingTopUsage = true
        topUsageError = nil
        topUsageRawResponse = ""

        let query = """
        {
            viewer {
                homes {
                    id
                    consumption(resolution: HOURLY, last: 800) {
                        nodes {
                            from
                            to
                            consumption
                        }
                    }
                }
            }
        }
        """

        // Keep a home-scoped fallback query if needed by older/newer schema variants.
        let fallbackHomeQuery = """
        {
            viewer {
                home(id: \"\(homeId)\") {
                    consumption(resolution: HOURLY, last: 800) {
                        nodes {
                            from
                            to
                            consumption
                        }
                    }
                }
            }
        }
        """

        guard let url = URL(string: "https://api.tibber.com/v1-beta/gql") else {
            isFetchingTopUsage = false
            topUsageError = "Invalid API URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = ["query": query]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetchingTopUsage = false

                if let error = error {
                    self.topUsageError = "Failed to fetch usage: \(error.localizedDescription)"
                    return
                }

                guard let data = data else {
                    self.topUsageError = "No usage data received"
                    return
                }

                self.topUsageRawResponse = self.truncatedRawResponse(from: data)
                self.logTopUsageRawToConsole(self.topUsageRawResponse, source: "primary")

                do {
                    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        self.topUsageError = "Unexpected usage response"
                        return
                    }

                    if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
                        let message = (errors.first?["message"] as? String) ?? "Unknown GraphQL error"

                        // If the homes-shape query fails in this account/schema, retry once with home(id:).
                        if message.localizedCaseInsensitiveContains("home") || message.localizedCaseInsensitiveContains("homes") {
                            self.fetchTopUsageFromApiWithQuery(fallbackHomeQuery)
                            return
                        }

                        self.topUsageError = "Tibber error: \(message)"
                        return
                    }

                    let nodes = self.extractConsumptionNodes(from: root)
                    self.logTopUsageNodesToConsole(nodes, source: "primary")
                    let thisMonth = self.filterNodesToCurrentMonth(nodes)
                    let ranked = thisMonth
                        .filter { $0.consumption != nil }
                        .sorted { ($0.consumption ?? 0) > ($1.consumption ?? 0) }
                    let top = Array(ranked.prefix(3))

                    guard !top.isEmpty else {
                        self.topUsageHours = []
                        self.topUsageAverage = nil
                        self.topUsageError = "No hourly usage found for this month"
                        return
                    }

                    let average = top.reduce(0.0) { partial, node in
                        partial + (node.consumption ?? 0)
                    } / Double(top.count)

                    let now = Date()
                    self.applyTopUsage(topHours: top, average: average, updatedAt: now)
                    self.saveTopUsageCache(
                        MonthlyTopUsageCache(
                            monthKey: self.currentMonthKey(),
                            topHours: top,
                            average: average,
                            updatedAt: now
                        )
                    )
                    self.lastTopUsageMonthKey = self.currentMonthKey()
                } catch {
                    self.topUsageError = "Failed to parse usage: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func fetchTopUsageFromApiWithQuery(_ query: String) {
        isFetchingTopUsage = true
        topUsageRawResponse = ""

        guard let url = URL(string: "https://api.tibber.com/v1-beta/gql") else {
            isFetchingTopUsage = false
            topUsageError = "Invalid API URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetchingTopUsage = false

                if let error = error {
                    self.topUsageError = "Failed to fetch usage: \(error.localizedDescription)"
                    return
                }

                guard
                    let data = data,
                    let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                else {
                    if let data = data {
                        self.topUsageRawResponse = self.truncatedRawResponse(from: data)
                    }
                    self.topUsageError = "Unexpected usage response"
                    return
                }

                self.topUsageRawResponse = self.truncatedRawResponse(from: data)
                self.logTopUsageRawToConsole(self.topUsageRawResponse, source: "fallback")

                if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
                    let message = (errors.first?["message"] as? String) ?? "Unknown GraphQL error"
                    self.topUsageError = "Tibber error: \(message)"
                    return
                }

                let nodes = self.extractConsumptionNodes(from: root)
                self.logTopUsageNodesToConsole(nodes, source: "fallback")
                let thisMonth = self.filterNodesToCurrentMonth(nodes)
                let ranked = thisMonth
                    .filter { $0.consumption != nil }
                    .sorted { ($0.consumption ?? 0) > ($1.consumption ?? 0) }
                let top = Array(ranked.prefix(3))

                guard !top.isEmpty else {
                    self.topUsageHours = []
                    self.topUsageAverage = nil
                    self.topUsageError = "No hourly usage found for this month"
                    return
                }

                let average = top.reduce(0.0) { $0 + ($1.consumption ?? 0) } / Double(top.count)
                let now = Date()
                self.applyTopUsage(topHours: top, average: average, updatedAt: now)
                self.saveTopUsageCache(
                    MonthlyTopUsageCache(
                        monthKey: self.currentMonthKey(),
                        topHours: top,
                        average: average,
                        updatedAt: now
                    )
                )
                self.lastTopUsageMonthKey = self.currentMonthKey()
            }
        }.resume()
    }

    private func truncatedRawResponse(from data: Data, maxLength: Int = 8000) -> String {
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
        if raw.count <= maxLength {
            return raw
        }
        let cutoff = raw.index(raw.startIndex, offsetBy: maxLength)
        return String(raw[..<cutoff]) + "\n... [truncated]"
    }

    private func logTopUsageRawToConsole(_ raw: String, source: String) {
        tlog("TOP_USAGE_RAW_\(source.uppercased())_START")
        tlog(raw)
        tlog("TOP_USAGE_RAW_\(source.uppercased())_END")
    }

    private func logTopUsageNodesToConsole(_ nodes: [HourlyConsumptionNode], source: String) {
        tlog("TOP_USAGE_POINTS_\(source.uppercased())_START count=\(nodes.count)")
        for (idx, node) in nodes.enumerated() {
            let value = node.consumption.map { String(format: "%.4f", $0) } ?? "nil"
            tlog("[\(idx)] from=\(node.from) to=\(node.to) consumption=\(value)")
        }
        tlog("TOP_USAGE_POINTS_\(source.uppercased())_END")
    }

    private func extractConsumptionNodes(from root: [String: Any]) -> [HourlyConsumptionNode] {
        guard
            let data = root["data"] as? [String: Any],
            let viewer = data["viewer"] as? [String: Any]
        else {
            return []
        }

        // Handle both possible shapes:
        // 1) viewer.home { consumption { nodes } }
        // 2) viewer.homes [ { id, consumption { nodes } } ]
        if let home = viewer["home"] as? [String: Any] {
            return extractNodesFromHome(home)
        }

        if let homes = viewer["homes"] as? [[String: Any]] {
            let selected = homes.first { ($0["id"] as? String) == self.homeId } ?? homes.first
            if let selected = selected {
                return extractNodesFromHome(selected)
            }
        }

        return []
    }

    private func extractNodesFromHome(_ home: [String: Any]) -> [HourlyConsumptionNode] {
        guard
            let consumption = home["consumption"] as? [String: Any],
            let rawNodes = consumption["nodes"] as? [[String: Any]]
        else {
            return []
        }

        return rawNodes.compactMap { raw in
            guard
                let from = raw["from"] as? String,
                let to = raw["to"] as? String,
                !from.isEmpty,
                !to.isEmpty
            else {
                return nil
            }

            let parsedConsumption: Double?
            if let number = raw["consumption"] as? Double {
                parsedConsumption = number
            } else if let number = raw["consumption"] as? NSNumber {
                parsedConsumption = number.doubleValue
            } else if let str = raw["consumption"] as? String {
                parsedConsumption = Double(str.replacingOccurrences(of: ",", with: "."))
            } else {
                parsedConsumption = nil
            }

            return HourlyConsumptionNode(from: from, to: to, consumption: parsedConsumption)
        }
    }

    private func applyTopUsage(topHours: [HourlyConsumptionNode], average: Double, updatedAt: Date) {
        topUsageHours = topHours
        topUsageAverage = average
        topUsageLastUpdated = updatedAt
        topUsageError = nil
    }

    private func filterNodesToCurrentMonth(_ nodes: [HourlyConsumptionNode]) -> [HourlyConsumptionNode] {
        let calendar = Calendar.current
        let currentComponents = calendar.dateComponents([.year, .month], from: Date())

        return nodes.filter { node in
            guard let date = parseIsoDate(node.from) else { return false }
            let components = calendar.dateComponents([.year, .month], from: date)
            return components.year == currentComponents.year && components.month == currentComponents.month
        }
    }

    private func parseIsoDate(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }

    private func currentMonthKey() -> String {
        return monthKey(for: Date())
    }

    private func resetTopUsageIfNeeded() {
        let key = currentMonthKey()
        if lastTopUsageMonthKey != key {
            topUsageHours = []
            topUsageAverage = nil
            topUsageLastUpdated = nil
            topUsageError = nil
            removeTopUsageCache()
            lastTopUsageMonthKey = key
        }
    }

    private func loadTopUsageFromCacheIfValid() {
        guard let cache = loadTopUsageCache(), cache.monthKey == currentMonthKey() else { return }
        applyTopUsage(topHours: cache.topHours, average: cache.average, updatedAt: cache.updatedAt)
        lastTopUsageMonthKey = cache.monthKey
    }

    private func loadTopUsageCache() -> MonthlyTopUsageCache? {
        guard let data = UserDefaults.standard.data(forKey: topUsageCacheKey) else { return nil }
        return try? JSONDecoder().decode(MonthlyTopUsageCache.self, from: data)
    }

    private func saveTopUsageCache(_ cache: MonthlyTopUsageCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: topUsageCacheKey)
    }

    private func removeTopUsageCache() {
        UserDefaults.standard.removeObject(forKey: topUsageCacheKey)
    }

    func fetchHomes() {
        guard !apiKey.isEmpty else {
            fetchHomesError = "Missing API Key"
            return
        }

        isFetchingHomes = true
        fetchHomesError = nil

        let query = """
        {
            viewer {
                homes {
                    id
                    appNickname
                    address {
                        address1
                    }
                }
            }
        }
        """

        guard let url = URL(string: "https://api.tibber.com/v1-beta/gql") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = ["query": query]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isFetchingHomes = false

                if let error = error {
                    self?.fetchHomesError = error.localizedDescription
                    return
                }

                guard let data = data else {
                    self?.fetchHomesError = "No data received"
                    return
                }

                do {
                    let decodedData = try JSONDecoder().decode(HomesResponse.self, from: data)
                    self?.availableHomes = decodedData.data?.viewer?.homes ?? []
                    if self?.availableHomes.isEmpty == true {
                        self?.fetchHomesError = "No homes found"
                    }
                } catch {
                    self?.fetchHomesError = "Failed to parse homes: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    func connect() {
        // Prevent multiple simultaneous connection attempts
        guard !isConnecting else {
            tlog("Already connecting, skipping duplicate connection attempt")
            return
        }
        
        // If already connected, don't reconnect
        if isConnected {
            tlog("Already connected, skipping connection attempt")
            return
        }
        
        guard !apiKey.isEmpty, !homeId.isEmpty else {
            connectionError = "Missing API Key or Home ID"
            self.logger.error("Cannot connect: Missing API Key or Home ID")
            return
        }
        
        isConnecting = true
        
        // Ensure UI stays awake
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        let urlSession = URLSession(configuration: .default)
        let url = URL(string: "wss://websocket-api.tibber.com/v1-beta/gql/subscriptions")!
        var request = URLRequest(url: url)
        request.setValue("graphql-transport-ws", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        request.setValue("AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        // Note: Authorization header is not needed when sending token in connection_init payload

        tlog("Attempting WebSocket connection to: \(url)")
        tlog("API Key being used: \(apiKey)")
        tlog("Home ID being used: \(homeId)")
        self.logger.info("Attempting WebSocket connection to Tibber API")
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        DispatchQueue.main.async {
            self.addConnectionLog("Connecting...")
        }

        // Start receiving messages immediately
        receiveMessage()
        
        // Send connection_init after a short delay to ensure socket is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let initMessage: [String: Any] = [
                "type": "connection_init",
                "payload": ["token": self.apiKey]
            ]
            
            tlog("Sending connection_init message with token: \(self.apiKey)")
            self.sendMessage(initMessage)
        }
    }
    
    func disconnect() {
        isConnecting = false
        isReconnecting = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        staleDataTimer?.invalidate()
        pingTimer?.invalidate()
        DispatchQueue.main.async {
            self.isConnected = false
            // self.liveData = nil // Keep old data rather than blanking out the UI totally
            self.isDataStale = false
            UIApplication.shared.isIdleTimerDisabled = false
            self.addConnectionLog("Disconnected")
        }
    }
    
    private func sendMessage(_ dictionary: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let jsonString = String(data: data, encoding: .utf8) else { 
            tlog("Failed to serialize message")
            return 
        }
        
        tlog("Sending message: \(jsonString)")
        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                self?.tlog("Failed to send message: \(error)")
                self?.logger.error("Failed to send message: \(error.localizedDescription)")
            } else {
                self?.tlog("Message sent successfully")
            }
        }
    }
    
    private func subscribeToLiveMeasurement() {
        let query = """
        subscription {
            liveMeasurement(homeId: "\(homeId)") {
                timestamp
                power
                accumulatedConsumption
                accumulatedConsumptionLastHour
                accumulatedCost
                currency
                averagePower
                voltagePhase1
                currentL1
                powerFactor
            }
        }
        """
        
        tlog("Subscribing with query: \(query)")
        
        let startMessage: [String: Any] = [
            "id": "1",
            "type": "subscribe",
            "payload": ["query": query]
        ]
        sendMessage(startMessage)
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                tlog("WebSocket receive error: \(error)")
                self.logger.error("WebSocket receive error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.isConnecting = false
                    self.connectionError = "Connection failed: \(error.localizedDescription)"
                    self.addConnectionLog("Error: \(error.localizedDescription)")
                    self.triggerReconnect()
                }
                
            case .success(let message):
                switch message {
                case .string(let text):
                    tlog("WebSocket message received: \(text)")
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        tlog("WebSocket data received: \(text)")
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                
                // Always keep listening for new messages
                self.receiveMessage()
            }
        }
    }
    
    private func handleMessage(_ jsonString: String) {
        // Reset stale data tracking whenever we get any message from the server (even pings)
        resetStaleDataTimer()

        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String else { return }
        
        switch type {
        case "connection_ack":
            tlog("Connection acknowledged by server")
            DispatchQueue.main.async {
                self.isConnecting = false
                self.isConnected = true
                self.connectionError = nil
                self.reconnectAttempt = 0 // Reset backoff on success
                self.isReconnecting = false
                self.addConnectionLog("Connected")
                self.startPingTimer()
            }
            subscribeToLiveMeasurement()
            
        case "next":
            do {
                let response = try JSONDecoder().decode(LiveMeasurementResponse.self, from: data)
                if let measurement = response.payload?.data?.liveMeasurement {
                    DispatchQueue.main.async {
                        self.liveData = measurement
                        self.trackWebsocketTopUsage(measurement: measurement)
                        self.isDataStale = false
                        self.evaluateThresholds(measurement: measurement)
                        // Add log silently for incoming data
                        let consumption = String(format: "%.3f", measurement.accumulatedConsumptionLastHour ?? 0.0)
                        self.addDataLog("Hour use: \(consumption) kWh")
                    }
                }
            } catch {
                tlog("Decode error: \(error)")
            }
            
        case "error":
            tlog("GraphQL Error: \(dict)")
            if let errorMsg = dict["payload"] as? [String: Any] {
                tlog("Error details: \(errorMsg)")
            }
            
        case "ping":
            tlog("Received ping, sending pong")
            self.sendMessage(["type": "pong"])
            DispatchQueue.main.async {
                self.addConnectionLog("Keep-alive (ping) received")
            }
            
        case "ka":
            tlog("Received keep-alive (ka)")
            DispatchQueue.main.async {
                self.addConnectionLog("Keep-alive (ka) received")
            }
            
        case "pong":
            tlog("Received pong")
            DispatchQueue.main.async {
                self.addConnectionLog("Keep-alive (pong) received")
            }
            
        default:
            tlog("Received unknown message type: \(type)")
            DispatchQueue.main.async {
                // Log unknown message types so they can be seen in the UI's connection log
                self.addConnectionLog("Unknown msg type: \(type)")
            }
            break
        }
    }
    
    private func evaluateThresholds(measurement: LiveMeasurement) {
        let currentMinute = Calendar.current.component(.minute, from: Date())
        
        // Grace period for the first 2 minutes of the hour to avoid false alerts from previous boundary data
        if currentMinute < 2 {
            return
        }
        
        let accumulatedKWh = measurement.accumulatedConsumptionLastHour ?? 0.0
        let currentPowerKW = measurement.power / 1000.0
        let minutesRemaining = 60.0 - Double(currentMinute)
        
        // Projected kWh = [Accumulated kWh so far this hour] + ([Current Power in kW]) * ([Minutes remaining] / 60)
        let projectedKWh = accumulatedKWh + (currentPowerKW * (minutesRemaining / 60.0))
        
        var alertLevel: AudioPlayer.AlertLevel = .none
        
        if projectedKWh >= criticalThreshold {
            alertLevel = .critical
        }
        
        if alertLevel != .none {
            // Wake screen explicitly
            wakeScreen()
            AudioPlayer.shared.playAlert(level: alertLevel)
            
            // Trigger Philips Hue critical alert
            if alertLevel == .critical {
                HueManager.shared.triggerCriticalAlert()
                TelegramManager.shared.notifyTelegram(powerValue: measurement.power)
            }
            
            // Increment breaches based on actual accumulated (not projected) vs critical
            if accumulatedKWh >= criticalThreshold && lastRecordedAverage < criticalThreshold {
                incrementBreach()
            }
        }
        
        lastRecordedAverage = accumulatedKWh
    }
    
    private func incrementBreach() {
        resetBreachCounterIfNeeded()
        breachCount += 1
    }
    
    private func resetBreachCounterIfNeeded() {
        let currentMonth = Calendar.current.component(.month, from: Date())
        if currentMonth != lastBreachMonth {
            breachCount = 0
            lastBreachMonth = currentMonth
        }
    }

    private func startPingTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer?.invalidate()
            // Send a ping every 30 seconds to keep NAT/firewalls open
            self?.pingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
                // Using graphql-ws standard ping
                self?.sendMessage(["type": "ping"])
            }
        }
    }

    // MARK: - Stale Data check
    
    private func resetStaleDataTimer() {
        DispatchQueue.main.async { [weak self] in
            // Must invalidate existing timer to prevent duplicates
            self?.staleDataTimer?.invalidate()
            
            // Remove the stale warning immediately since we just got activity
            self?.isDataStale = false
            
            // Re-arm the timer
            self?.staleDataTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
                // Timer fired: No activity for 60 seconds
                DispatchQueue.main.async {
                    self?.isDataStale = true
                    self?.addConnectionLog("Stale connection (60s). Reconnecting...")
                    self?.triggerReconnect()
                }
            }
        }
    }
    
    // MARK: - Reconnect Logic
    
    private func triggerReconnect() {
        guard !isReconnecting else { return }
        isReconnecting = true
        
        // Ensure old socket is dead and stale states are reset
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        isConnected = false
        isConnecting = false
        
        // Exponential backoff: 2^attempt (1s, 2s, 4s, 8s, 16s, 32s, 60s max)
        let maxDelay: TimeInterval = 60.0
        let baseDelay = pow(2.0, Double(min(reconnectAttempt, 6)))
        
        // Jitter: Add random offset between 0 and 2 seconds
        let jitter = Double.random(in: 0...2.0)
        let delay = min(baseDelay + jitter, maxDelay)
        
        reconnectAttempt += 1
        
        let logMsg = "Triggering reconnect in \(String(format: "%.1f", delay))s (Attempt \(reconnectAttempt))"
        tlog(logMsg)
        
        DispatchQueue.main.async { [weak self] in
            self?.addConnectionLog("Delaying: \(String(format: "%.1f", delay))s")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.isReconnecting = false
            self?.connect()
        }
    }

    // MARK: - Screensaver / Inactivity
    
    func wakeScreen() {
        DispatchQueue.main.async {
            self.isScreensaverActive = false
            self.startInactivityTimer() // reset timer
        }
    }
    
    func startInactivityTimer() {
        inactivityTimer?.invalidate()
        let timeout: TimeInterval = idleTimerMinutes * 60
        
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isScreensaverActive = true
            }
        }
    }
    
    // MARK: - Logging
    
    func addConnectionLog(_ message: String, source: String = "TIBBER") {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        let timeString = formatter.string(from: Date())
        
        let prefix = source.padding(toLength: 6, withPad: " ", startingAt: 0)
        
        // Add new log at the start and keep last 50 lines to prevent memory bloat
        connectionLogs.insert("[\(timeString)] [\(prefix)] \(message)", at: 0)
        if connectionLogs.count > 50 {
            connectionLogs.removeLast()
        }
    }
    
    func addDataLog(_ message: String, source: String = "TIBBER") {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        let timeString = formatter.string(from: Date())
        
        let prefix = source.padding(toLength: 6, withPad: " ", startingAt: 0)
        
        dataLogs.insert("[\(timeString)] [\(prefix)] \(message)", at: 0)
        if dataLogs.count > 50 {
            dataLogs.removeLast()
        }
    }
}
