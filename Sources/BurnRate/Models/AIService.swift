import Foundation

struct ModelQuota: Identifiable, Codable {
    var id: String { modelName }
    let modelName: String
    var remainingPercent: Int // 잔여량 (예: 80 = 80% 남음)
    var refreshTimeString: String // 예: "3h 18m" 또는 "Available"
}

struct AIService: Identifiable, Codable {
    var id: String { name }
    let name: String
    var isEnabled: Bool
    var logFilePath: String?
    var apiKey: String?
    var currentUsage: Double
    var totalLimit: Double
    var quotas: [ModelQuota]? // 상세 쿼터 데이터
    
    static var defaultServices: [AIService] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultAntigravityPath = "\(homeDir)/.gemini/antigravity-cli/api_usage.json"
        
        return [
            AIService(
                name: "Antigravity",
                isEnabled: true,
                logFilePath: defaultAntigravityPath,
                currentUsage: 20.0, // 대표 소진율 20% (가장 많이 소진된 쿼터 기준)
                totalLimit: 100.0,
                quotas: [
                    ModelQuota(modelName: "Gemini 3.5 Flash (Medium)", remainingPercent: 80, refreshTimeString: "3h 18m"),
                    ModelQuota(modelName: "Gemini 3.5 Flash (High)", remainingPercent: 80, refreshTimeString: "3h 18m"),
                    ModelQuota(modelName: "Gemini 3.5 Flash (Low)", remainingPercent: 80, refreshTimeString: "3h 18m"),
                    ModelQuota(modelName: "Gemini 3.1 Pro (Low)", remainingPercent: 80, refreshTimeString: "3h 18m"),
                    ModelQuota(modelName: "Gemini 3.1 Pro (High)", remainingPercent: 80, refreshTimeString: "3h 18m"),
                    ModelQuota(modelName: "Claude Sonnet 4.6 (Thinking)", remainingPercent: 100, refreshTimeString: "Available"),
                    ModelQuota(modelName: "Claude Opus 4.6 (Thinking)", remainingPercent: 100, refreshTimeString: "Available"),
                    ModelQuota(modelName: "GPT-OSS 120B (Medium)", remainingPercent: 100, refreshTimeString: "Available")
                ]
            ),
            AIService(name: "Claude Code", isEnabled: false, currentUsage: 0.0, totalLimit: 200.0),
            AIService(name: "Codex", isEnabled: false, currentUsage: 0.0, totalLimit: 150.0),
            AIService(name: "Cursor", isEnabled: false, currentUsage: 0.0, totalLimit: 300.0)
        ]
    }
}
