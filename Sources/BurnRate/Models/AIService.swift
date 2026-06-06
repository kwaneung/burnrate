import Foundation

struct AIService: Identifiable, Codable {
    var id: String { name }
    let name: String
    var isEnabled: Bool
    var logFilePath: String?
    var apiKey: String?
    
    static var defaultServices: [AIService] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultAntigravityPath = "\(homeDir)/.gemini/antigravity-cli/api_usage.json"
        
        return [
            AIService(name: "Antigravity", isEnabled: true, logFilePath: defaultAntigravityPath),
            AIService(name: "Claude Code", isEnabled: false),
            AIService(name: "Cursor", isEnabled: false),
            AIService(name: "GitHub Copilot", isEnabled: false)
        ]
    }
}
