import Foundation
import Combine
import AppKit

class ConfigManager: ObservableObject {
    static var defaultAntigravityUsagePath: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/.gemini/antigravity-cli/api_usage.json"
    }

    @Published var services: [AIService] = [] {
        didSet {
            saveServices()
        }
    }

    @Published var usageData: UsageData = .empty
    @Published var antigravityStatusMessage: String = "Antigravity CLI 로그인 세션을 확인하는 중"
    @Published var cursorStatusMessage: String = "Cursor 로그인 세션을 확인하는 중"
    @Published var isAntigravityLinked: Bool = false {
        didSet {
            UserDefaults.standard.set(isAntigravityLinked, forKey: "BurnRate_AntigravityLinked")
            if isAntigravityLinked {
                fetchAntigravityUsageDirectly()
            } else {
                resetAntigravityUsage()
                antigravityStatusMessage = "연동 해제됨"
            }
        }
    }
    @Published var isCursorLinked: Bool = false {
        didSet {
            UserDefaults.standard.set(isCursorLinked, forKey: "BurnRate_CursorLinked")
            if isCursorLinked {
                fetchCursorUsageDirectly()
            } else {
                resetCursorUsage()
                cursorStatusMessage = "연동 해제됨"
            }
        }
    }

    private var pollingTimer: Timer?
    private let usageQueue = DispatchQueue(label: "com.kwaneung.BurnRate.usage-sync", qos: .utility)

    init() {
        _isAntigravityLinked = Published(wrappedValue: Self.initialAntigravityLinked())
        _isCursorLinked = Published(wrappedValue: UserDefaults.standard.bool(forKey: "BurnRate_CursorLinked"))
        loadServices()
        if isAntigravityLinked {
            loadCachedAntigravityUsage()
            fetchAntigravityUsageDirectly()
        }
        if isCursorLinked {
            fetchCursorUsageDirectly()
        }
        startPollingTimer()
    }

    private static func initialAntigravityLinked() -> Bool {
        if UserDefaults.standard.object(forKey: "BurnRate_AntigravityLinked") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "BurnRate_AntigravityLinked")
    }

    private func loadServices() {
        if let data = UserDefaults.standard.data(forKey: "BurnRate_Services"),
           let decoded = try? JSONDecoder().decode([AIService].self, from: data) {
            var loaded = decoded

            for defaultService in AIService.defaultServices {
                if !loaded.contains(where: { $0.name == defaultService.name }) {
                    loaded.append(defaultService)
                }
            }

            self.services = loaded
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

    func refreshDataSynchronization() {
        if isAntigravityLinked {
            fetchAntigravityUsageDirectly()
        }
        if isCursorLinked {
            fetchCursorUsageDirectly()
        }
    }

    func resetAllSettings() {
        for key in Self.userDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        usageData = .empty
        antigravityStatusMessage = "Antigravity CLI 로그인 세션을 확인하는 중"
        cursorStatusMessage = "Cursor 로그인 세션을 확인하는 중"
        services = AIService.defaultServices
        isCursorLinked = false
        isAntigravityLinked = false
        isAntigravityLinked = Self.initialAntigravityLinked()
    }

    private static let userDefaultsKeys = [
        "BurnRate_AntigravityLinked",
        "BurnRate_CursorLinked",
        "BurnRate_Services",
        "BurnRate_GoogleClientID"
    ]

    private func loadCachedAntigravityUsage() {
        let path = Self.defaultAntigravityUsagePath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let cached = try? JSONDecoder().decode(UsageData.self, from: data),
              !cached.quotaGroups.isEmpty else {
            return
        }

        usageData = cached
        updateAntigravityService(usage: cached.totalSpent, quotaGroups: cached.quotaGroups)
    }

    private func updateAntigravityStatusMessage(_ message: String) {
        DispatchQueue.main.async {
            self.antigravityStatusMessage = message
        }
    }

    private func resetAntigravityUsage() {
        DispatchQueue.main.async { [weak self] in
            self?.usageData = .empty
            self?.updateAntigravityService(usage: 0.0, quotaGroups: [])
        }
    }

    private func updateAntigravityService(usage: Double, quotaGroups: [AntigravityQuotaGroup]) {
        guard let index = services.firstIndex(where: { $0.name == "Antigravity" }) else { return }
        var updated = services
        updated[index].currentUsage = usage
        updated[index].quotas = []
        updated[index].quotaGroups = quotaGroups
        services = updated
    }

    private func updateServiceUsage(name: String, usage: Double, quotas: [ModelQuota]) {
        guard let index = services.firstIndex(where: { $0.name == name }) else { return }
        var updated = services
        updated[index].currentUsage = usage
        updated[index].quotas = quotas
        services = updated
    }

    // MARK: - Polling

    private func startPollingTimer() {
        fetchCursorUsageDirectly()
        fetchAntigravityUsageDirectly()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.fetchCursorUsageDirectly()
            self?.fetchAntigravityUsageDirectly()
        }
    }

    private func stopPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Antigravity API Integration

    private func fetchAntigravityUsageDirectly() {
        guard isAntigravityLinked else { return }

        guard services.contains(where: { $0.name == "Antigravity" && $0.isEnabled }) else {
            updateAntigravityStatusMessage("대시보드에서 Antigravity를 활성화해 주세요.")
            return
        }

        guard AntigravitySessionReader.hasActiveSession else {
            updateAntigravityStatusMessage("Antigravity CLI에 로그인해 주세요. (~/.gemini/antigravity-cli)")
            return
        }

        usageQueue.async { [weak self] in
            guard let self else { return }

            AntigravitySessionReader.resolveAccessToken { [weak self] accessToken in
                guard let self else { return }

                guard let accessToken else {
                    self.updateAntigravityStatusMessage("CLI 세션을 갱신하지 못했습니다. agy를 실행해 다시 로그인해 주세요.")
                    return
                }

                AntigravityQuotaClient.fetchQuotas(accessToken: accessToken) { [weak self] result in
                    guard let self else { return }

                    switch result {
                    case .success(let usageData):
                        AntigravityQuotaClient.cacheUsageData(usageData)
                        DispatchQueue.main.async {
                            self.usageData = usageData
                            self.updateAntigravityService(
                                usage: usageData.totalSpent,
                                quotaGroups: usageData.quotaGroups
                            )
                            self.antigravityStatusMessage = usageData.quotaGroups.isEmpty
                                ? "쿼터 데이터가 비어 있습니다."
                                : "CLI 세션 연동 완료 (15초마다 동기화)"
                        }
                    case .failure(let error):
                        switch error {
                        case .unauthorized:
                            self.updateAntigravityStatusMessage("CLI 세션이 만료되었습니다. agy를 실행해 다시 로그인해 주세요.")
                        case .invalidResponse, .decode:
                            self.updateAntigravityStatusMessage("Antigravity 사용량 API 응답을 처리하지 못했습니다.")
                        case .network(let message):
                            self.updateAntigravityStatusMessage("네트워크 오류: \(message)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cursor API Integration

    private func updateCursorStatusMessage(_ message: String) {
        DispatchQueue.main.async {
            self.cursorStatusMessage = message
        }
    }

    private func resetCursorUsage() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let index = self.services.firstIndex(where: { $0.name == "Cursor" }) else { return }
            var updated = self.services
            updated[index].currentUsage = 0.0
            updated[index].quotas = []
            updated[index].membershipLabel = nil
            updated[index].onDemandEnabled = nil
            updated[index].onDemandUsed = nil
            updated[index].onDemandLimit = nil
            self.services = updated
        }
    }

    private func formatCursorMembershipLabel(_ membershipType: String?) -> String {
        switch membershipType {
        case "pro_plus":
            return "Pro+"
        case "pro":
            return "Pro"
        case "ultra":
            return "Ultra"
        case "business":
            return "Business"
        case "free", "hobby":
            return "Free"
        default:
            guard let membershipType, !membershipType.isEmpty else { return "Pro" }
            return membershipType
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }

    private func fetchCursorUsageDirectly() {
        guard isCursorLinked else { return }

        guard services.contains(where: { $0.name == "Cursor" && $0.isEnabled }) else {
            updateCursorStatusMessage("대시보드에서 Cursor를 활성화해 주세요.")
            return
        }

        guard CursorSessionReader.hasStoredSession else {
            updateCursorStatusMessage("Cursor에 로그인해 주세요.")
            return
        }

        guard let token = CursorSessionReader.readAccessToken() else {
            updateCursorStatusMessage("Cursor에 로그인해 주세요.")
            return
        }

        guard CursorSessionReader.extractSubFromJWT(token) != nil else {
            updateCursorStatusMessage("세션을 읽지 못했습니다. Cursor를 실행해 다시 로그인해 주세요.")
            return
        }

        if CursorSessionReader.isAccessTokenExpired(token) {
            updateCursorStatusMessage("세션이 만료되었습니다. Cursor를 실행해 다시 로그인해 주세요.")
            return
        }

        usageQueue.async { [weak self] in
            guard let self else { return }

            guard let sub = CursorSessionReader.extractSubFromJWT(token) else {
                self.updateCursorStatusMessage("세션을 읽지 못했습니다. Cursor를 실행해 다시 로그인해 주세요.")
                return
            }

            let cookieValue = "\(sub)::\(token)"
            guard let url = URL(string: "https://cursor.com/api/usage-summary") else {
                self.updateCursorStatusMessage("Cursor 사용량 API 요청을 준비하지 못했습니다.")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("WorkosCursorSessionToken=\(cookieValue)", forHTTPHeaderField: "Cookie")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")

            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self else { return }

                if let error {
                    self.updateCursorStatusMessage("네트워크 오류: \(error.localizedDescription)")
                    return
                }

                guard let data else {
                    self.updateCursorStatusMessage("Cursor 사용량 API 응답을 처리하지 못했습니다.")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    if httpResponse.statusCode == 401 {
                        self.updateCursorStatusMessage("세션이 만료되었습니다. Cursor를 실행해 다시 로그인해 주세요.")
                    } else {
                        self.updateCursorStatusMessage("Cursor 사용량 API 응답을 처리하지 못했습니다.")
                    }
                    return
                }

                do {
                    let usage = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
                    self.processCursorUsage(usage)
                } catch {
                    self.updateCursorStatusMessage("Cursor 사용량 API 응답을 처리하지 못했습니다.")
                }
            }.resume()
        }
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
        guard let plan = response.individualUsage?.plan else {
            updateCursorStatusMessage("사용량 데이터가 비어 있습니다.")
            return
        }

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
            weeklyLimit: 100,
            weeklyUsed: apiUsedPercent,
            hourlyLimit: nil,
            hourlyUsed: nil,
            usedPercent: apiUsedPercent
        )

        let updatedQuotas = [autoQuota, apiQuota]
        let membershipLabel = formatCursorMembershipLabel(response.membershipType)
        let onDemand = response.individualUsage?.onDemand

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let index = self.services.firstIndex(where: { $0.name == "Cursor" }) else { return }
            var updated = self.services
            updated[index].currentUsage = Double(totalUsedPercent)
            updated[index].quotas = updatedQuotas
            updated[index].membershipLabel = membershipLabel
            updated[index].onDemandEnabled = onDemand?.enabled
            updated[index].onDemandUsed = onDemand?.used
            updated[index].onDemandLimit = onDemand?.limit
            self.services = updated
            self.cursorStatusMessage = "로컬 세션 연동 완료 (15초마다 동기화)"
        }
    }

    deinit {
        stopPollingTimer()
    }
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
        struct OnDemand: Codable {
            let enabled: Bool?
            let used: Int?
            let limit: Int?
            let remaining: Int?
        }
        let plan: Plan?
        let onDemand: OnDemand?
    }
    let membershipType: String?
    let billingCycleEnd: String?
    let individualUsage: IndividualUsage?
}
