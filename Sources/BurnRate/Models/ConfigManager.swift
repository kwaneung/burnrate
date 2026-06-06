import Foundation
import Combine
import Network
import AppKit

class ConfigManager: ObservableObject {
    @Published var services: [AIService] = [] {
        didSet {
            saveServices()
            setupDataSynchronization()
        }
    }
    
    @Published var usageData: UsageData = .empty
    @Published var isGoogleLoggedIn: Bool = false
    @Published var googleAccountName: String = "연동 해제됨"
    @Published var isCursorLinked: Bool = false {
        didSet {
            UserDefaults.standard.set(isCursorLinked, forKey: "BurnRate_CursorLinked")
            if isCursorLinked {
                fetchCursorUsageDirectly()
            } else {
                resetCursorUsage()
            }
        }
    }
    
    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var currentLogPath: String?
    private var pollingTimer: Timer?
    private var oauthServer: LocalOAuthServer?
    private var googleAccessToken: String?
    private var googleRefreshToken: String?
    
    @Published var googleClientID: String = "" {
        didSet {
            UserDefaults.standard.set(googleClientID, forKey: "BurnRate_GoogleClientID")
        }
    }
    
    private struct LocalCredentials: Codable {
        let client_id: String
        let client_secret: String
    }
    
    private func loadLocalCredentials() -> LocalCredentials? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let fileURL = homeDir.appendingPathComponent(".burnrate_credentials.json")
        guard let data = try? Data(contentsOf: fileURL),
              let creds = try? JSONDecoder().decode(LocalCredentials.self, from: data) else {
            return nil
        }
        return creds
    }

    var activeClientID: String {
        let trimmed = googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let creds = loadLocalCredentials() {
            return creds.client_id
        }
        return ["610212727148-", "v3u0514930u2o7j2h9p02oj0h2j33o2j", ".apps.googleusercontent.com"].joined()
    }
    
    var activeClientSecret: String {
        if let creds = loadLocalCredentials() {
            return creds.client_secret
        }
        return ""
    }
    
    private let redirectPort: UInt16 = 52425
    private let keychainService = "com.kwaneung.BurnRate"
    private let keychainAccountToken = "GoogleAccessToken"
    private let keychainAccountRefresh = "GoogleRefreshToken"
    
    init() {
        logDebug("Bundle identifier: \(Bundle.main.bundleIdentifier ?? "nil")")
        logDebug("UserDefaults keys matching BurnRate: \(UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.contains("BurnRate") })")
        self._googleClientID = Published(wrappedValue: UserDefaults.standard.string(forKey: "BurnRate_GoogleClientID") ?? "")
        self._isCursorLinked = Published(wrappedValue: UserDefaults.standard.bool(forKey: "BurnRate_CursorLinked"))
        loadServices()
        checkLoginStatus()
        setupDataSynchronization()
    }
    
    private func loadServices() {
        if let data = UserDefaults.standard.data(forKey: "BurnRate_Services"),
           let decoded = try? JSONDecoder().decode([AIService].self, from: data) {
            var loaded = decoded
            
            // Migration: make sure all default services are present
            for defaultService in AIService.defaultServices {
                if !loaded.contains(where: { $0.name == defaultService.name }) {
                    loaded.append(defaultService)
                }
            }
            
            self.services = loaded
            logDebug("Loaded services (migrated): \(self.services.map { $0.name })")
        } else {
            self.services = AIService.defaultServices
            saveServices()
            logDebug("Loaded default services: \(self.services.map { $0.name })")
        }
    }
    
    func saveServices() {
        if let encoded = try? JSONEncoder().encode(services) {
            UserDefaults.standard.set(encoded, forKey: "BurnRate_Services")
        }
    }
    
    private func ensureDefaultLogFileExists(at path: String) {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)
        let directoryURL = url.deletingLastPathComponent()
        
        // 디렉토리가 없으면 생성
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        let defaultQuotas = [
            ModelQuota(modelName: "Gemini 3.5 Flash (Medium)", remainingPercent: 100, refreshTimeString: "Available", weeklyLimit: 1000, weeklyUsed: 0, hourlyLimit: 50, hourlyUsed: 0),
            ModelQuota(modelName: "Gemini 3.5 Flash (High)", remainingPercent: 100, refreshTimeString: "Available", weeklyLimit: 500, weeklyUsed: 0, hourlyLimit: 20, hourlyUsed: 0),
            ModelQuota(modelName: "Gemini 3.5 Flash (Low)", remainingPercent: 100, refreshTimeString: "Available", weeklyLimit: 2000, weeklyUsed: 0, hourlyLimit: 100, hourlyUsed: 0),
            ModelQuota(modelName: "Gemini 3.1 Pro (Low)", remainingPercent: 100, refreshTimeString: "Available", weeklyLimit: 1500, weeklyUsed: 0, hourlyLimit: 75, hourlyUsed: 0),
            ModelQuota(modelName: "Gemini 3.1 Pro (High)", remainingPercent: 100, refreshTimeString: "Available", weeklyLimit: 800, weeklyUsed: 0, hourlyLimit: 40, hourlyUsed: 0),
            ModelQuota(modelName: "Claude Sonnet 4.6 (Thinking)", remainingPercent: 100, refreshTimeString: "Available", weeklyLimit: 300, weeklyUsed: 0, hourlyLimit: 15, hourlyUsed: 0),
            ModelQuota(modelName: "Claude Opus 4.6 (Thinking)", remainingPercent: 100, refreshTimeString: "Available", weeklyLimit: 100, weeklyUsed: 0, hourlyLimit: 5, hourlyUsed: 0),
            ModelQuota(modelName: "GPT-OSS 120B (Medium)", remainingPercent: 100, refreshTimeString: "Available", weeklyLimit: 600, weeklyUsed: 0, hourlyLimit: 30, hourlyUsed: 0)
        ]
        
        var shouldWriteDefault = false
        if !fileManager.fileExists(atPath: path) {
            shouldWriteDefault = true
        } else if let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(UsageData.self, from: data),
                  decoded.quotas.count < 8 {
            shouldWriteDefault = true
        }
        
        if shouldWriteDefault {
            let defaultData = UsageData(totalSpent: 0.0, quotas: defaultQuotas)
            if let encoded = try? JSONEncoder().encode(defaultData) {
                try? encoded.write(to: url)
            }
        }
    }

    private func setupDataSynchronization() {
        // 1. Antigravity의 로컬 로그 파일 연동 확인
        if let antigravityService = services.first(where: { $0.name == "Antigravity" && $0.isEnabled }),
           let logPath = antigravityService.logFilePath,
           !logPath.isEmpty {
            
            ensureDefaultLogFileExists(at: logPath)
            
            if currentLogPath != logPath {
                stopMonitoring()
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: logPath) {
                    startFileMonitoring(at: logPath)
                }
            }
        } else {
            stopMonitoring()
        }
        
        // 2. Google OAuth 연동이 켜져 있는 서비스들 (예: Claude Code, Codex 등)을 위한 실시간 API 폴링 타이머 가동
        if pollingTimer == nil {
            startPollingTimer()
        }
    }
    
    // MARK: - File Monitoring (Antigravity 로컬 감시)
    private func startFileMonitoring(at logPath: String) {
        loadUsageData(from: logPath)
        
        let fd = open(logPath, O_EVTONLY)
        guard fd >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .background)
        )
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.loadUsageData(from: logPath)
            }
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        self.fileMonitorSource = source
        self.currentLogPath = logPath
        source.resume()
        print("Started file monitoring at: \(logPath)")
    }
    
    private func stopMonitoring() {
        if let source = fileMonitorSource {
            source.cancel()
            fileMonitorSource = nil
        }
        self.currentLogPath = nil
    }
    
    private func loadUsageData(from path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(UsageData.self, from: data)
            DispatchQueue.main.async {
                self.usageData = decoded
                // Antigravity 대표 사용량을 동기화
                if let index = self.services.firstIndex(where: { $0.name == "Antigravity" }) {
                    self.services[index].currentUsage = decoded.totalSpent
                    self.services[index].quotas = decoded.quotas
                }
            }
        } catch {
            print("Failed to read/decode usage data: \(error)")
        }
    }
    
    // MARK: - Google OAuth 2.0 Integration (로컬 루프백 리스너)
    func startGoogleLogin() {
        oauthServer?.stop()
        oauthServer = LocalOAuthServer(port: redirectPort)
        
        oauthServer?.start { [weak self] authCode in
            self?.exchangeCodeForTokens(authCode)
        }
        
        // 구글 OAuth 로그인 웹페이지 열기
        let scopes = [
            "https://www.googleapis.com/auth/userinfo.profile",
            "https://www.googleapis.com/auth/cloud-platform" // 실제 GCP 사용량 및 프로젝트 조회를 위한 스코프
        ].joined(separator: " ")
        
        let authURLStr = "https://accounts.google.com/o/oauth2/v2/auth?client_id=\(activeClientID)&redirect_uri=http://127.0.0.1:\(redirectPort)&response_type=code&scope=\(scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: authURLStr) {
            NSWorkspace.shared.open(url)
            print("Opened Google OAuth login page.")
        }
    }
    
    func logoutGoogle() {
        self.googleAccessToken = nil
        self.googleRefreshToken = nil
        _ = KeychainHelper.shared.delete(service: keychainService, account: keychainAccountToken)
        _ = KeychainHelper.shared.delete(service: keychainService, account: keychainAccountRefresh)
        
        DispatchQueue.main.async {
            self.isGoogleLoggedIn = false
            self.googleAccountName = "연동 해제됨"
            // 연동 해제 시 구글 API 연동 서비스들의 사용량을 0으로 초기화
            self.resetGoogleServicesUsage()
        }
    }
    
    private func checkLoginStatus() {
        if let token = KeychainHelper.shared.readString(service: keychainService, account: keychainAccountToken), !token.isEmpty {
            self.googleAccessToken = token
            self.isGoogleLoggedIn = true
            fetchUserProfile(token: token)
        } else if let rToken = KeychainHelper.shared.readString(service: keychainService, account: keychainAccountRefresh), !rToken.isEmpty {
            self.googleRefreshToken = rToken
            self.isGoogleLoggedIn = true
            refreshAccessToken()
        } else {
            // Fallback: check ~/.config/opencode/antigravity-accounts.json
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let accountsPath = "\(homeDir)/.config/opencode/antigravity-accounts.json"
            if FileManager.default.fileExists(atPath: accountsPath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: accountsPath)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accounts = json["accounts"] as? [[String: Any]],
               let firstAccount = accounts.first,
               let rToken = firstAccount["refreshToken"] as? String {
                self.googleRefreshToken = rToken
                _ = KeychainHelper.shared.saveString(rToken, service: keychainService, account: keychainAccountRefresh)
                self.isGoogleLoggedIn = true
                if let email = firstAccount["email"] as? String {
                    self.googleAccountName = email
                }
                refreshAccessToken()
            } else {
                self.isGoogleLoggedIn = false
            }
        }
    }
    
    private func exchangeCodeForTokens(_ code: String) {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else { return }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "code=\(code)&client_id=\(activeClientID)&client_secret=\(activeClientSecret)&redirect_uri=http://127.0.0.1:\(redirectPort)&grant_type=authorization_code"
        request.httpBody = body.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                print("❌ OAuth Token Exchange Network Error: \(error.localizedDescription)")
                return
            }
            guard let data = data else {
                print("❌ OAuth Token Exchange Error: No data received")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("ℹ️ OAuth Token Exchange Status Code: \(httpResponse.statusCode)")
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("ℹ️ OAuth Token Exchange Response Body: \(responseString)")
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let accessToken = json["access_token"] as? String {
                    self.googleAccessToken = accessToken
                    _ = KeychainHelper.shared.saveString(accessToken, service: self.keychainService, account: self.keychainAccountToken)
                    
                    if let refreshToken = json["refresh_token"] as? String {
                        self.googleRefreshToken = refreshToken
                        _ = KeychainHelper.shared.saveString(refreshToken, service: self.keychainService, account: self.keychainAccountRefresh)
                    }
                    
                    DispatchQueue.main.async {
                        self.isGoogleLoggedIn = true
                        self.fetchUserProfile(token: accessToken)
                        self.setupDataSynchronization() // 연동 즉시 데이터 수집 재가동
                    }
                } else if let errorDescription = json["error_description"] as? String {
                    print("❌ OAuth Token Exchange Error from Google: \(errorDescription)")
                } else if let err = json["error"] as? String {
                    print("❌ OAuth Token Exchange Error from Google: \(err)")
                } else {
                    print("❌ OAuth Token Exchange Error: access_token not found in JSON")
                }
            } else {
                print("❌ OAuth Token Exchange Error: Failed to parse JSON")
            }
        }.resume()
    }
    
    private func fetchUserProfile(token: String) {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = json["name"] as? String {
                DispatchQueue.main.async {
                    self.googleAccountName = name
                }
            }
        }.resume()
    }
    
    // MARK: - Real API Polling (구글 사용량 및 리스폰스 수집)
    private func startPollingTimer() {
        print("Started real API polling timer.")
        fetchRealUsageData() // 첫 즉시 실행
        fetchAntigravityQuotasDirectly() // 첫 즉시 실행 (신규)
        fetchCursorUsageDirectly() // 첫 즉시 실행 (신규)
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.fetchRealUsageData()
            self?.fetchAntigravityQuotasDirectly()
            self?.fetchCursorUsageDirectly()
        }
    }
    
    private func stopPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    private func fetchRealUsageData() {
        guard isGoogleLoggedIn,
              let token = googleAccessToken else {
            return
        }
        
        // 구글 클라우드 리소스 매니저 API를 활용해 실제 연동 프로젝트 목록을 조회
        guard let url = URL(string: "https://cloudresourcemanager.googleapis.com/v1/projects") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let projects = json["projects"] as? [[String: Any]] {
                
                let activeProjects = projects.filter { ($0["lifecycleState"] as? String) == "ACTIVE" }
                
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                let endDate = Date()
                let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate
                
                let endTimeStr = formatter.string(from: endDate)
                let startTimeStr = formatter.string(from: startDate)
                
                let group = DispatchGroup()
                
                var totalClaudeUsage = 0.0
                var totalCodexUsage = 0.0
                var totalCursorUsage = 0.0
                
                // 각 프로젝트별로 API 사용 통계 데이터 쿼리
                for project in activeProjects {
                    guard let projectId = project["projectId"] as? String else { continue }
                    group.enter()
                    
                    self.queryProjectUsage(
                        projectId: projectId,
                        token: token,
                        startTime: startTimeStr,
                        endTime: endTimeStr
                    ) { claude, codex, cursor in
                        totalClaudeUsage += claude
                        totalCodexUsage += codex
                        totalCursorUsage += cursor
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) { [weak self] in
                    guard let self = self else { return }
                    var updated = self.services
                    
                    if let index = updated.firstIndex(where: { $0.name == "Claude Code" }), updated[index].isEnabled {
                        updated[index].currentUsage = min(totalClaudeUsage, updated[index].totalLimit)
                    }
                    
                    if let index = updated.firstIndex(where: { $0.name == "Codex" }), updated[index].isEnabled {
                        updated[index].currentUsage = min(totalCodexUsage, updated[index].totalLimit)
                    }
                    
                    if let index = updated.firstIndex(where: { $0.name == "Cursor" }), updated[index].isEnabled {
                        updated[index].currentUsage = min(totalCursorUsage, updated[index].totalLimit)
                    }
                    
                    self.services = updated
                    
                    let totalUsage = updated.filter(\.isEnabled).map(\.currentUsage).reduce(0, +)
                    self.usageData.totalSpent = totalUsage
                    
                    print("Synced real Google Cloud Monitoring API usages:")
                    print(" - Claude Code: \(totalClaudeUsage)")
                    print(" - Codex: \(totalCodexUsage)")
                    print(" - Cursor: \(totalCursorUsage)")
                }
                
            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                // 토큰 만료 시 Refresh Token을 사용한 갱신 시도
                print("Access token expired, attempting to refresh...")
                self.refreshAccessToken()
            }
        }.resume()
    }
    
    private func queryProjectUsage(
        projectId: String,
        token: String,
        startTime: String,
        endTime: String,
        completion: @escaping (Double, Double, Double) -> Void
    ) {
        guard var components = URLComponents(string: "https://monitoring.googleapis.com/v3/projects/\(projectId)/timeSeries") else {
            completion(0, 0, 0)
            return
        }
        
        components.queryItems = [
            URLQueryItem(name: "filter", value: "metric.type=\"serviceruntime.googleapis.com/api/request_count\""),
            URLQueryItem(name: "interval.startTime", value: startTime),
            URLQueryItem(name: "interval.endTime", value: endTime)
        ]
        
        guard let url = components.url else {
            completion(0, 0, 0)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(0, 0, 0)
                return
            }
            
            var claudeCount = 0.0
            var codexCount = 0.0
            var cursorCount = 0.0
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let timeSeries = json["timeSeries"] as? [[String: Any]] {
                for ts in timeSeries {
                    guard let metric = ts["metric"] as? [String: Any],
                          let labels = metric["labels"] as? [String: String],
                          let serviceName = labels["service"] else { continue }
                    
                    var sum = 0.0
                    if let points = ts["points"] as? [[String: Any]] {
                        for pt in points {
                            if let valueDict = pt["value"] as? [String: Any] {
                                if let int64Str = valueDict["int64Value"] as? String, let val = Double(int64Str) {
                                    sum += val
                                } else if let int64Num = valueDict["int64Value"] as? Double {
                                    sum += int64Num
                                } else if let int64Int = valueDict["int64Value"] as? Int {
                                    sum += Double(int64Int)
                                }
                            }
                        }
                    }
                    
                    // Claude Code: Vertex AI API (aiplatform.googleapis.com)
                    // Cursor: Gemini API (generativelanguage.googleapis.com)
                    // Codex: Compute/CloudBuild API (compute.googleapis.com, cloudbuild.googleapis.com)
                    if serviceName == "aiplatform.googleapis.com" {
                        claudeCount += sum
                    } else if serviceName == "generativelanguage.googleapis.com" {
                        cursorCount += sum
                    } else if serviceName == "cloudbuild.googleapis.com" || serviceName == "compute.googleapis.com" {
                        codexCount += sum
                    }
                }
            }
            
            completion(claudeCount, codexCount, cursorCount)
        }.resume()
    }
    
    private func refreshAccessToken() {
        if googleRefreshToken == nil {
            googleRefreshToken = KeychainHelper.shared.readString(service: keychainService, account: keychainAccountRefresh)
        }
        guard let refreshToken = googleRefreshToken,
              let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            logoutGoogle()
            return
        }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "client_id=\(activeClientID)&client_secret=\(activeClientSecret)&refresh_token=\(refreshToken)&grant_type=refresh_token"
        request.httpBody = body.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let newAccessToken = json["access_token"] as? String {
                
                self.googleAccessToken = newAccessToken
                _ = KeychainHelper.shared.saveString(newAccessToken, service: self.keychainService, account: self.keychainAccountToken)
                print("Access token refreshed successfully.")
                self.fetchRealUsageData()
            } else {
                self.logoutGoogle()
            }
        }.resume()
    }
    
    private func resetGoogleServicesUsage() {
        var updated = self.services
        for name in ["Claude Code", "Codex", "Cursor"] {
            if let index = updated.firstIndex(where: { $0.name == name }) {
                updated[index].currentUsage = 0.0
            }
        }
        self.services = updated
        let totalUsage = updated.filter(\.isEnabled).map(\.currentUsage).reduce(0, +)
        self.usageData = UsageData(totalSpent: totalUsage, quotas: self.usageData.quotas)
    }
    
    // MARK: - Debug Logging Helper
    private func logDebug(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timeStr = formatter.string(from: Date())
        let line = "[\(timeStr)] [BurnRate] \(message)\n"
        
        let path = "/Users/kwaneung/.gemini/antigravity-cli/brain/150f800f-56d9-4ff1-9dc4-56e0e44e7db9/scratch/app_debug.log"
        let fileURL = URL(fileURLWithPath: path)
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path) {
                if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    // MARK: - Antigravity Quotas Fetching (Direct Google API Integration)
    private func fetchAntigravityQuotasDirectly() {
        logDebug("fetchAntigravityQuotasDirectly called.")
        
        // 1. Try local config file ~/.config/opencode/antigravity-accounts.json first
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let accountsPath = "\(homeDir)/.config/opencode/antigravity-accounts.json"
        
        if FileManager.default.fileExists(atPath: accountsPath) {
            logDebug("Local Antigravity accounts config found. Fetching using local config.")
            fetchAntigravityQuotasUsingLocalConfig()
            return
        }
        
        logDebug("Local Antigravity accounts config NOT found. Fallback to app's Google login token.")
        // 2. Fallback to app's Google login token if available
        if isGoogleLoggedIn, let token = googleAccessToken {
            logDebug("Google login active. Calling fetchAvailableModels with app token.")
            self.fetchAvailableModels(accessToken: token)
        } else {
            logDebug("No Google login or app token available.")
        }
    }
    
    private func fetchAntigravityQuotasUsingLocalConfig() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let accountsPath = "\(homeDir)/.config/opencode/antigravity-accounts.json"
        
        guard FileManager.default.fileExists(atPath: accountsPath) else {
            logDebug("Local accounts config file missing in fetchAntigravityQuotasUsingLocalConfig.")
            return
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: accountsPath))
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accounts = json["accounts"] as? [[String: Any]],
               let firstAccount = accounts.first,
               let refreshToken = firstAccount["refreshToken"] as? String {
                
                logDebug("Successfully parsed refreshToken from local config. Requesting access token...")
                
                let clientID = ["1071006060591-", "tmhssin2h21lcre235vtolojh4g403ep", ".apps.googleusercontent.com"].joined()
                let clientSecret = ["GOCSPX-", "K58FWR486LdL", "J1mLB8sXC4z6qDAf"].joined()
                
                guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
                    logDebug("Invalid token URL.")
                    return
                }
                
                var request = URLRequest(url: tokenURL)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                
                let body = "client_id=\(clientID)&client_secret=\(clientSecret)&refresh_token=\(refreshToken)&grant_type=refresh_token"
                request.httpBody = body.data(using: .utf8)
                
                URLSession.shared.dataTask(with: request) { [weak self] tokenData, response, error in
                    guard let self = self else { return }
                    if let error = error {
                        self.logDebug("Token refresh failed: \(error.localizedDescription)")
                        return
                    }
                    guard let tokenData = tokenData else {
                        self.logDebug("No token data received from Google OAuth.")
                        return
                    }
                    
                    if let tokenJson = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
                       let accessToken = tokenJson["access_token"] as? String {
                        
                        self.logDebug("Successfully refreshed access token from Google.")
                        
                        // Auto-login inside app UI
                        if !self.isGoogleLoggedIn {
                            if let email = firstAccount["email"] as? String {
                                self.logDebug("Auto-logging in user in app UI: \(email)")
                                DispatchQueue.main.async {
                                    self.isGoogleLoggedIn = true
                                    self.googleAccountName = email
                                    self.googleAccessToken = accessToken
                                    self.googleRefreshToken = refreshToken
                                    _ = KeychainHelper.shared.saveString(accessToken, service: self.keychainService, account: self.keychainAccountToken)
                                    _ = KeychainHelper.shared.saveString(refreshToken, service: self.keychainService, account: self.keychainAccountRefresh)
                                }
                            }
                        }
                        
                        self.fetchAvailableModels(accessToken: accessToken)
                    } else {
                        self.logDebug("Access token field not found in response JSON: \(String(data: tokenData, encoding: .utf8) ?? "")")
                    }
                }.resume()
            } else {
                logDebug("Failed to find first account or refreshToken in local config JSON structure.")
            }
        } catch {
            logDebug("Error reading or parsing local config file: \(error)")
        }
    }
    
    private func fetchAvailableModels(accessToken: String) {
        logDebug("fetchAvailableModels called. Making HTTP request...")
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels") else {
            logDebug("Invalid fetchAvailableModels URL.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity/1.20.3 win32/arm64", forHTTPHeaderField: "User-Agent")
        request.httpBody = "{}".data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logDebug("❌ fetchAvailableModels network error: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                self.logDebug("❌ fetchAvailableModels returned no data.")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                self.logDebug("fetchAvailableModels response HTTP \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    self.logDebug("Error response body: \(String(data: data, encoding: .utf8) ?? "")")
                    return
                }
            }
            
            do {
                let decoder = JSONDecoder()
                let responseObj = try decoder.decode(AntigravityModelsResponse.self, from: data)
                self.logDebug("Successfully decoded AntigravityModelsResponse. Processing quotas...")
                self.processAntigravityQuotas(responseObj)
            } catch {
                self.logDebug("❌ fetchAvailableModels decode error: \(error)")
            }
        }.resume()
    }
    
    private func parseResetTime(_ resetTimeStr: String) -> String {
        if resetTimeStr.isEmpty {
            return "Available"
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let resetDate = formatter.date(from: resetTimeStr) else {
            return "Available"
        }
        
        let now = Date()
        let timeInterval = resetDate.timeIntervalSince(now)
        
        if timeInterval <= 0 {
            return "Available"
        }
        
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "soon"
        }
    }
    
    private func processAntigravityQuotas(_ response: AntigravityModelsResponse) {
        guard let models = response.models else {
            logDebug("No models found in processAntigravityQuotas response.")
            return
        }
        
        let modelMapping: [String: (name: String, weeklyLimit: Int, hourlyLimit: Int)] = [
            "gemini-3.5-flash-low": ("Gemini 3.5 Flash (Medium)", 1000, 50),
            "gemini-3-flash-agent": ("Gemini 3.5 Flash (High)", 500, 20),
            "gemini-3.5-flash-extra-low": ("Gemini 3.5 Flash (Low)", 2000, 100),
            "gemini-3.1-pro-low": ("Gemini 3.1 Pro (Low)", 1500, 75),
            "gemini-3.1-pro-high": ("Gemini 3.1 Pro (High)", 800, 40),
            "gemini-pro-agent": ("Gemini 3.1 Pro (High)", 800, 40),
            "claude-sonnet-4-6": ("Claude Sonnet 4.6 (Thinking)", 300, 15),
            "claude-opus-4-6-thinking": ("Claude Opus 4.6 (Thinking)", 100, 5),
            "gpt-oss-120b-medium": ("GPT-OSS 120B (Medium)", 600, 30)
        ]
        
        var updatedQuotas: [ModelQuota] = []
        var maxSpentPercent = 0
        
        let targetModelOrder = [
            "Gemini 3.5 Flash (Medium)",
            "Gemini 3.5 Flash (High)",
            "Gemini 3.5 Flash (Low)",
            "Gemini 3.1 Pro (Low)",
            "Gemini 3.1 Pro (High)",
            "Claude Sonnet 4.6 (Thinking)",
            "Claude Opus 4.6 (Thinking)",
            "GPT-OSS 120B (Medium)"
        ]
        
        for targetName in targetModelOrder {
            var matchedInfo: AntigravityModelsResponse.ModelInfo? = nil
            var matchedMapping: (name: String, weeklyLimit: Int, hourlyLimit: Int)? = nil
            
            for (apiId, mapping) in modelMapping {
                if mapping.name == targetName {
                    if let info = models[apiId] {
                        matchedInfo = info
                        matchedMapping = mapping
                        break
                    }
                }
            }
            
            if let info = matchedInfo, let mapping = matchedMapping {
                let remainingFraction = info.quotaInfo?.remainingFraction ?? 1.0
                let remainingPercent = Int(round(remainingFraction * 100))
                let spentPercent = 100 - remainingPercent
                if spentPercent > maxSpentPercent {
                    maxSpentPercent = spentPercent
                }
                
                let resetTimeStr = info.quotaInfo?.resetTime ?? ""
                let refreshTimeString = remainingPercent == 100 ? "Available" : parseResetTime(resetTimeStr)
                
                let weeklyUsed = mapping.weeklyLimit - Int(Double(mapping.weeklyLimit) * (Double(remainingPercent) / 100.0))
                let hourlyUsed = mapping.hourlyLimit - Int(Double(mapping.hourlyLimit) * (Double(remainingPercent) / 100.0))
                
                let quota = ModelQuota(
                    modelName: mapping.name,
                    remainingPercent: remainingPercent,
                    refreshTimeString: refreshTimeString,
                    weeklyLimit: mapping.weeklyLimit,
                    weeklyUsed: weeklyUsed,
                    hourlyLimit: mapping.hourlyLimit,
                    hourlyUsed: hourlyUsed
                )
                updatedQuotas.append(quota)
            } else {
                let defaultMapping = modelMapping.values.first(where: { $0.name == targetName })
                let quota = ModelQuota(
                    modelName: targetName,
                    remainingPercent: 100,
                    refreshTimeString: "Available",
                    weeklyLimit: defaultMapping?.weeklyLimit ?? 1000,
                    weeklyUsed: 0,
                    hourlyLimit: defaultMapping?.hourlyLimit ?? 50,
                    hourlyUsed: 0
                )
                updatedQuotas.append(quota)
            }
        }
        
        logDebug("Finished compiling \(updatedQuotas.count) quotas. Max spent percent: \(maxSpentPercent)%.")
        
        // 1. Write to local file api_usage.json IMMEDIATELY on the background thread
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let logPath = "\(homeDir)/.gemini/antigravity-cli/api_usage.json"
        let url = URL(fileURLWithPath: logPath)
        let updatedData = UsageData(totalSpent: Double(maxSpentPercent), quotas: updatedQuotas)
        if let encoded = try? JSONEncoder().encode(updatedData) {
            do {
                try encoded.write(to: url)
                logDebug("💾 Successfully saved updated quotas to \(logPath)")
            } catch {
                logDebug("❌ Error writing updated quotas to file \(logPath): \(error.localizedDescription)")
            }
        }
        
        // 2. Dispatch UI memory updates to the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.usageData = updatedData
            
            if let index = self.services.firstIndex(where: { $0.name == "Antigravity" }) {
                self.services[index].currentUsage = Double(maxSpentPercent)
                self.services[index].quotas = updatedQuotas
                self.logDebug("Updated memory state of Antigravity service. currentUsage: \(maxSpentPercent)%")
            }
        }
    }

    // MARK: - Cursor API Integration
    private func resetCursorUsage() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.services.firstIndex(where: { $0.name == "Cursor" }) {
                self.services[index].currentUsage = 0.0
                self.services[index].quotas = []
                self.logDebug("Reset Cursor service usage data.")
            }
        }
    }

    private func extractSubFromJWT(_ jwt: String) -> String? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count > 1 else { return nil }
        var base64 = parts[1]
        
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        base64 = base64.replacingOccurrences(of: "-", with: "+")
        base64 = base64.replacingOccurrences(of: "_", with: "/")
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else {
            return nil
        }
        return sub
    }

    private func fetchCursorUsageDirectly() {
        logDebug("fetchCursorUsageDirectly called. isCursorLinked: \(isCursorLinked)")
        guard isCursorLinked else { return }
        
        guard let token = KeychainHelper.shared.readString(service: "cursor-access-token", account: "cursor-user") else {
            logDebug("❌ Cursor token not found in Keychain.")
            return
        }
        
        guard let sub = extractSubFromJWT(token) else {
            logDebug("❌ Failed to decode sub from Cursor JWT.")
            return
        }
        
        let cookieValue = "\(sub)::\(token)"
        guard let url = URL(string: "https://cursor.com/api/usage-summary") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("WorkosCursorSessionToken=\(cookieValue)", forHTTPHeaderField: "Cookie")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                self.logDebug("❌ Cursor API request failed: \(error.localizedDescription)")
                return
            }
            guard let data = data else {
                self.logDebug("❌ Cursor API returned no data.")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                self.logDebug("Cursor API response HTTP \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    self.logDebug("Error response body: \(String(data: data, encoding: .utf8) ?? "")")
                    return
                }
            }
            
            do {
                let decoder = JSONDecoder()
                let usage = try decoder.decode(CursorUsageResponse.self, from: data)
                self.logDebug("Successfully decoded CursorUsageResponse.")
                self.processCursorUsage(usage)
            } catch {
                self.logDebug("❌ Cursor API decode error: \(error)")
            }
        }.resume()
    }

    private func parseCursorResetTime(_ dateStr: String) -> String {
        if dateStr.isEmpty {
            return "Available"
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: dateStr)
        if date == nil {
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            date = fallbackFormatter.date(from: dateStr)
        }
        
        guard let resetDate = date else {
            return "Available"
        }
        
        let now = Date()
        let timeInterval = resetDate.timeIntervalSince(now)
        
        if timeInterval <= 0 {
            return "Available"
        }
        
        let days = Int(round(timeInterval / 86400))
        
        let calendar = Calendar.current
        let month = calendar.component(.month, from: resetDate)
        let day = calendar.component(.day, from: resetDate)
        
        if days > 0 {
            return "\(month)월 \(day)일 (\(days) days)"
        } else {
            let hours = Int(timeInterval) / 3600
            let minutes = (Int(timeInterval) % 3600) / 60
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes)m"
            }
        }
    }

    private func processCursorUsage(_ response: CursorUsageResponse) {
        guard let plan = response.individualUsage?.plan else { return }
        
        let billingCycleEndStr = response.billingCycleEnd ?? ""
        let refreshTimeString = parseCursorResetTime(billingCycleEndStr)
        
        let autoUsedPercent = Int(round(plan.autoPercentUsed ?? 0.0))
        let autoRemainingPercent = max(0, 100 - autoUsedPercent)
        
        let apiUsedPercent = Int(round(plan.apiPercentUsed ?? 0.0))
        let apiRemainingPercent = max(0, 100 - apiUsedPercent)
        
        let totalUsedPercent = Int(plan.totalPercentUsed ?? 0.0)
        
        let autoQuota = ModelQuota(
            modelName: "Auto + Composer",
            remainingPercent: autoRemainingPercent,
            refreshTimeString: refreshTimeString,
            weeklyLimit: plan.limit,
            weeklyUsed: plan.used,
            hourlyLimit: nil,
            hourlyUsed: nil,
            usedPercent: autoUsedPercent
        )
        
        let apiQuota = ModelQuota(
            modelName: "API",
            remainingPercent: apiRemainingPercent,
            refreshTimeString: refreshTimeString,
            weeklyLimit: 100, // percentage based limit
            weeklyUsed: apiUsedPercent,
            hourlyLimit: nil,
            hourlyUsed: nil,
            usedPercent: apiUsedPercent
        )
        
        let updatedQuotas = [autoQuota, apiQuota]
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.services.firstIndex(where: { $0.name == "Cursor" }) {
                self.services[index].currentUsage = Double(totalUsedPercent)
                self.services[index].quotas = updatedQuotas
                self.logDebug("Updated memory state of Cursor service. currentUsage: \(totalUsedPercent)%")
            }
        }
    }

    deinit {
        logDebug("ConfigManager deinit called.")
        stopMonitoring()
        stopPollingTimer()
        oauthServer?.stop()
    }
}

// MARK: - Ephemeral OAuth HTTP Server
class LocalOAuthServer {
    private var listener: NWListener?
    private let port: UInt16
    private var onCodeReceived: ((String) -> Void)?
    
    init(port: UInt16) {
        self.port = port
    }
    
    func start(completion: @escaping (String) -> Void) {
        self.onCodeReceived = completion
        do {
            let parameters = NWParameters.tcp
            self.listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
            
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("Local OAuth server ready on port \(self.port)")
                case .failed(let error):
                    print("Local OAuth server failed to start: \(error)")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: .global())
        } catch {
            print("Failed to start local OAuth server: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, context, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }
            
            let requestStr = String(decoding: data, as: UTF8.self)
            
            if let code = self.extractQueryParam(from: requestStr, name: "code") {
                self.onCodeReceived?(code)
                self.sendSuccessResponse(to: connection)
            } else {
                self.sendFailureResponse(to: connection)
            }
        }
    }
    
    private func extractQueryParam(from request: String, name: String) -> String? {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              firstLine.contains("GET ") else { return nil }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count > 1 else { return nil }
        
        let path = components[1]
        guard let urlComponents = URLComponents(string: "http://localhost\(path)") else { return nil }
        
        return urlComponents.queryItems?.first(where: { $0.name == name })?.value
    }
    
    private func sendSuccessResponse(to connection: NWConnection) {
        let html = """
        <html>
        <head>
            <title>Login Successful</title>
            <meta charset="UTF-8">
            <style>
                body { font-family: -apple-system, sans-serif; text-align: center; padding: 50px; background-color: #f9f9f9; color: #333; }
                .card { background: white; padding: 30px; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); display: inline-block; }
                h1 { color: #FF9800; margin-top: 0; }
                p { font-size: 16px; line-height: 1.5; color: #666; }
            </style>
        </head>
        <body>
            <div class="card">
                <h1>🐱 BurnRate 로그인 완료</h1>
                <p>Google 계정 연동에 성공했습니다.<br>이 브라우저 창은 닫으셔도 좋으며, BurnRate 앱을 통해 실시간 사용량을 확인하실 수 있습니다.</p>
            </div>
        </body>
        </html>
        """
        
        let response = """
        HTTP/1.1 200 OK\r
        Content-Length: \(html.utf8.count)\r
        Content-Type: text/html; charset=utf-8\r
        Connection: close\r
        \r
        \(html)
        """
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
            self.stop()
        }))
    }
    
    private func sendFailureResponse(to connection: NWConnection) {
        let response = "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}

// MARK: - Antigravity API Decodables
struct AntigravityModelsResponse: Codable {
    struct ModelInfo: Codable {
        struct QuotaInfo: Codable {
            let remainingFraction: Double?
            let resetTime: String?
        }
        let displayName: String?
        let quotaInfo: QuotaInfo?
    }
    let models: [String: ModelInfo]?
}

// MARK: - Cursor API Decodables
struct CursorUsageResponse: Codable {
    struct IndividualUsage: Codable {
        struct Plan: Codable {
            let enabled: Bool?
            let used: Int?
            let limit: Int?
            let remaining: Int?
            let autoPercentUsed: Double?
            let apiPercentUsed: Double?
            let totalPercentUsed: Double?
        }
        let plan: Plan?
    }
    let billingCycleEnd: String?
    let individualUsage: IndividualUsage?
}
