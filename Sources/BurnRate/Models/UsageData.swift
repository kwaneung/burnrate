import Foundation

struct UsageData: Codable {
    var totalSpent: Double
    var quotas: [ModelQuota]
    
    static var empty: UsageData {
        return UsageData(totalSpent: 0.0, quotas: [])
    }
}
