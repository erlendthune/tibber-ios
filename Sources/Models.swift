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
