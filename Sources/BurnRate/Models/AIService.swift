import Foundation

struct AIService: Identifiable, Codable {
    var id: String { name }
    let name: String
    var isEnabled: Bool
    var logFilePath: String?
    var apiKey: String?
    var currentUsage: Double
    var totalLimit: Double
    
    static var defaultServices: [AIService] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultAntigravityPath = "\(homeDir)/.gemini/antigravity-cli/api_usage.json"
        
        return [
            AIService(name: "Antigravity", isEnabled: true, logFilePath: defaultAntigravityPath, currentUsage: 15.0, totalLimit: 100.0),
            AIService(name: "Claude Code", isEnabled: false, currentUsage: 0.0, totalLimit: 200.0),
            AIService(name: "Codex", isEnabled: false, currentUsage: 0.0, totalLimit: 150.0),
            AIService(name: "Cursor", isEnabled: false, currentUsage: 0.0, totalLimit: 300.0)
        ]
    }
}
