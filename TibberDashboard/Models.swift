import Foundation

struct LiveMeasurementResponse: Codable {
    let type: String?
    let payload: Payload?
}

struct Payload: Codable {
    let data: SubscriptionData?
}

struct SubscriptionData: Codable {
    let liveMeasurement: LiveMeasurement?
}

struct LiveMeasurement: Codable {
    let timestamp: String
    let power: Double
    let accumulatedConsumption: Double
    let accumulatedConsumptionLastHour: Double?
    let accumulatedCost: Double?
    let currency: String?
    let averagePower: Double? // This is what the user wants to trust instead of calculating projection
    
    // Additional fields if needed
    let voltagePhase1: Double?
    let currentL1: Double?
    let powerFactor: Double?
}

struct SubscriptionPayload: Codable {
    let query: String
}

struct Home: Codable, Identifiable {
    let id: String
    let appNickname: String?
    let address: Address?
}

struct Address: Codable {
    let address1: String?
}

struct HomesResponse: Codable {
    let data: HomesData?
}

struct HomesData: Codable {
    let viewer: Viewer?
}

struct Viewer: Codable {
    let homes: [Home]?
}
