import Foundation

enum AntigravityQuotaClient {
    private static let quotaSummaryURL = URL(
        string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"
    )!
    private static let userAgent = "antigravity/1.0.6 darwin/arm64"

    static func fetchQuotas(accessToken: String, completion: @escaping (Result<UsageData, AntigravityQuotaError>) -> Void) {
        var request = URLRequest(url: quotaSummaryURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = "{}".data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }

            guard let data else {
                completion(.failure(.invalidResponse))
                return
            }

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                completion(.failure(http.statusCode == 401 ? .unauthorized : .invalidResponse))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(AntigravityQuotaSummaryResponse.self, from: data)
                completion(.success(processQuotaSummary(decoded)))
            } catch {
                completion(.failure(.decode))
            }
        }.resume()
    }

    static func cacheUsageData(_ usageData: UsageData) {
        let path = ConfigManager.defaultAntigravityUsagePath
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let encoded = try? JSONEncoder().encode(usageData) {
            try? encoded.write(to: URL(fileURLWithPath: path))
        }
    }

    private static func processQuotaSummary(_ response: AntigravityQuotaSummaryResponse) -> UsageData {
        let groups = (response.groups ?? []).map { group in
            AntigravityQuotaGroup(
                displayName: group.displayName ?? "Unknown Group",
                description: group.description,
                buckets: (group.buckets ?? []).map { bucket in
                    let remainingFraction = bucket.remainingFraction ?? 1.0
                    let remainingPercent = Int(round(remainingFraction * 100))
                    let resetTime = bucket.resetTime ?? ""

                    return AntigravityQuotaBucket(
                        bucketId: bucket.bucketId ?? bucket.window ?? UUID().uuidString,
                        displayName: bucket.displayName ?? bucket.window ?? "Limit",
                        window: bucket.window ?? "",
                        remainingPercent: remainingPercent,
                        refreshTimeString: remainingPercent >= 100 ? "Available" : parseResetTime(resetTime)
                    )
                }
            )
        }

        let maxSpentPercent = groups
            .flatMap(\.buckets)
            .map { max(0, 100 - $0.remainingPercent) }
            .max() ?? 0

        return UsageData(
            totalSpent: Double(maxSpentPercent),
            quotas: [],
            quotaGroups: groups
        )
    }

    private static func parseResetTime(_ resetTime: String) -> String {
        if resetTime.isEmpty {
            return "Available"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var resetDate = formatter.date(from: resetTime)
        if resetDate == nil {
            formatter.formatOptions = [.withInternetDateTime]
            resetDate = formatter.date(from: resetTime)
        }

        guard let resetDate else {
            return "Available"
        }

        let interval = resetDate.timeIntervalSince(Date())
        if interval <= 0 {
            return "Available"
        }

        let totalHours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if totalHours > 0 {
            return "\(totalHours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "soon"
    }
}

enum AntigravityQuotaError: Error {
    case unauthorized
    case invalidResponse
    case decode
    case network(String)
}

struct AntigravityQuotaSummaryResponse: Codable {
    struct Group: Codable {
        struct Bucket: Codable {
            let bucketId: String?
            let displayName: String?
            let window: String?
            let resetTime: String?
            let description: String?
            let remainingFraction: Double?
        }

        let displayName: String?
        let description: String?
        let buckets: [Bucket]?
    }

    let groups: [Group]?
    let description: String?
}
