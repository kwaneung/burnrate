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
    
    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var currentLogPath: String?
    private var pollingTimer: Timer?
    private var oauthServer: LocalOAuthServer?
    
    // Google Cloud OAuth Credential (기본 데스크톱 클라이언트용 설정)
    private let clientID = "610212727148-v3u0514930u2o7j2h9p02oj0h2j33o2j.apps.googleusercontent.com" // 가상/공용 데스크톱 Client ID
    private let redirectPort: UInt16 = 52425
    private let keychainService = "com.kwaneung.BurnRate"
    private let keychainAccountToken = "GoogleAccessToken"
    private let keychainAccountRefresh = "GoogleRefreshToken"
    
    init() {
        loadServices()
        checkLoginStatus()
        setupDataSynchronization()
    }
    
    private func loadServices() {
        if let data = UserDefaults.standard.data(forKey: "BurnRate_Services"),
           let decoded = try? JSONDecoder().decode([AIService].self, from: data),
           decoded.contains(where: { $0.name == "Codex" || $0.name == "Cursor" }) {
            self.services = decoded
        } else {
            self.services = AIService.defaultServices
            saveServices()
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
        
        // 파일이 없으면 기본 쿼터 JSON 작성
        if !fileManager.fileExists(atPath: path) {
            let defaultQuotas = [
                ModelQuota(modelName: "Gemini 3.5 Flash (Medium)", remainingPercent: 100, refreshTimeString: "Available", weeklyLimit: 1000, weeklyUsed: 0, hourlyLimit: 50, hourlyUsed: 0),
                ModelQuota(modelName: "Gemini 3.5 Flash (High)", remainingPercent: 100, refreshTimeString: "Available", weeklyLimit: 500, weeklyUsed: 0, hourlyLimit: 20, hourlyUsed: 0),
                ModelQuota(modelName: "Claude Sonnet 4.6 (Thinking)", remainingPercent: 100, refreshTimeString: "Available", weeklyLimit: 300, weeklyUsed: 0, hourlyLimit: 15, hourlyUsed: 0)
            ]
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
        
        let authURLStr = "https://accounts.google.com/o/oauth2/v2/auth?client_id=\(clientID)&redirect_uri=http://127.0.0.1:\(redirectPort)&response_type=code&scope=\(scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: authURLStr) {
            NSWorkspace.shared.open(url)
            print("Opened Google OAuth login page.")
        }
    }
    
    func logoutGoogle() {
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
            self.isGoogleLoggedIn = true
            fetchUserProfile(token: token)
        } else {
            self.isGoogleLoggedIn = false
        }
    }
    
    private func exchangeCodeForTokens(_ code: String) {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else { return }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "code=\(code)&client_id=\(clientID)&redirect_uri=http://127.0.0.1:\(redirectPort)&grant_type=authorization_code"
        request.httpBody = body.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessToken = json["access_token"] as? String {
                
                _ = KeychainHelper.shared.saveString(accessToken, service: self.keychainService, account: self.keychainAccountToken)
                
                if let refreshToken = json["refresh_token"] as? String {
                    _ = KeychainHelper.shared.saveString(refreshToken, service: self.keychainService, account: self.keychainAccountRefresh)
                }
                
                DispatchQueue.main.async {
                    self.isGoogleLoggedIn = true
                    self.fetchUserProfile(token: accessToken)
                    self.setupDataSynchronization() // 연동 즉시 데이터 수집 재가동
                }
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
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.fetchRealUsageData()
        }
    }
    
    private func stopPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    private func fetchRealUsageData() {
        guard isGoogleLoggedIn,
              let token = KeychainHelper.shared.readString(service: keychainService, account: keychainAccountToken) else {
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
        guard let refreshToken = KeychainHelper.shared.readString(service: keychainService, account: keychainAccountRefresh),
              let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            logoutGoogle()
            return
        }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "client_id=\(clientID)&refresh_token=\(refreshToken)&grant_type=refresh_token"
        request.httpBody = body.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let newAccessToken = json["access_token"] as? String {
                
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
    
    deinit {
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
