import Foundation

struct AntigravityQuotaBucket: Codable, Identifiable, Hashable {
    var id: String { bucketId }
    let bucketId: String
    let displayName: String
    let window: String
    let remainingPercent: Int
    let refreshTimeString: String
}

struct AntigravityQuotaGroup: Codable, Identifiable, Hashable {
    var id: String { displayName }
    let displayName: String
    let description: String?
    let buckets: [AntigravityQuotaBucket]
}

struct UsageData: Codable {
    var totalSpent: Double
    var quotas: [ModelQuota]
    var quotaGroups: [AntigravityQuotaGroup]

    static var empty: UsageData {
        UsageData(totalSpent: 0.0, quotas: [], quotaGroups: [])
    }

    init(totalSpent: Double, quotas: [ModelQuota], quotaGroups: [AntigravityQuotaGroup] = []) {
        self.totalSpent = totalSpent
        self.quotas = quotas
        self.quotaGroups = quotaGroups
    }

    enum CodingKeys: String, CodingKey {
        case totalSpent
        case quotas
        case quotaGroups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalSpent = try container.decode(Double.self, forKey: .totalSpent)
        quotas = try container.decodeIfPresent([ModelQuota].self, forKey: .quotas) ?? []
        quotaGroups = try container.decodeIfPresent([AntigravityQuotaGroup].self, forKey: .quotaGroups) ?? []
    }
}
