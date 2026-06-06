import Foundation

struct UsageData: Codable {
    var totalSpent: Double
    
    static var empty: UsageData {
        return UsageData(totalSpent: 0.0)
    }
}
