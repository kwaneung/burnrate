import Foundation

struct ModelQuota: Identifiable, Codable {
    var id: String { modelName }
    let modelName: String
    var remainingPercent: Int // 잔여량 (예: 80 = 80% 남음)
    var refreshTimeString: String // 예: "3h 18m" 또는 "Available"
    
    // 상세 주간 및 시간당(5시간) 쿼터 정보 추가
    var weeklyLimit: Int?
    var weeklyUsed: Int?
    var hourlyLimit: Int?
    var hourlyUsed: Int?
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
                currentUsage: 0.0, // 모킹 제거: 초기에는 0으로 시작
                totalLimit: 100.0,
                quotas: [] // 모킹 제거: 실제 연동 데이터 로드 전에는 비어있음
            ),
            AIService(name: "Claude Code", isEnabled: false, currentUsage: 0.0, totalLimit: 200.0),
            AIService(name: "Codex", isEnabled: false, currentUsage: 0.0, totalLimit: 150.0),
            AIService(name: "Cursor", isEnabled: false, currentUsage: 0.0, totalLimit: 300.0)
        ]
    }
}
