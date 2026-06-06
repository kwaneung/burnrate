import Foundation

struct UsageLog: Codable, Identifiable {
    var id: String { timestamp }
    let timestamp: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cost: Double
}

struct UsageData: Codable {
    var totalSpent: Double
    var logs: [UsageLog]
    
    static var empty: UsageData {
        return UsageData(totalSpent: 0.0, logs: [])
    }
}
