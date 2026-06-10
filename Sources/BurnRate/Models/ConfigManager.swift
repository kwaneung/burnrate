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
    @Published var antigravityStatusMessage: String = "Antigravity CLI 로그인 후 사용량 파일을 기다리는 중"
    @Published var isAntigravityLinked: Bool = false {
        didSet {
            UserDefaults.standard.set(isAntigravityLinked, forKey: "BurnRate_AntigravityLinked")
            if isAntigravityLinked {
                setupDataSynchronization()
            } else {
                stopMonitoring()
                stopAntigravityRetryTimer()
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
            }
        }
    }

    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var currentLogPath: String?
    private var pollingTimer: Timer?
    private var antigravityRetryTimer: Timer?
    private var antigravityReloadWorkItem: DispatchWorkItem?
    private let usageQueue = DispatchQueue(label: "com.kwaneung.BurnRate.usage-sync", qos: .utility)

    init() {
        _isAntigravityLinked = Published(wrappedValue: Self.initialAntigravityLinked())
        _isCursorLinked = Published(wrappedValue: UserDefaults.standard.bool(forKey: "BurnRate_CursorLinked"))
        loadServices()
        if isAntigravityLinked {
            setupDataSynchronization()
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
        setupDataSynchronization()
    }

    func resetAllSettings() {
        stopMonitoring()
        stopAntigravityRetryTimer()
        antigravityReloadWorkItem?.cancel()
        antigravityReloadWorkItem = nil

        for key in Self.userDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        usageData = .empty
        antigravityStatusMessage = "Antigravity CLI 로그인 후 사용량 파일을 기다리는 중"
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

    var antigravityUsageFilePath: String? {
        guard let service = services.first(where: { $0.name == "Antigravity" }),
              let path = service.logFilePath,
              !path.isEmpty else {
            return nil
        }
        return path
    }

    private func setupDataSynchronization() {
        guard isAntigravityLinked else { return }

        guard let antigravityService = services.first(where: { $0.name == "Antigravity" && $0.isEnabled }),
              let logPath = antigravityService.logFilePath,
              !logPath.isEmpty else {
            stopMonitoring()
            stopAntigravityRetryTimer()
            updateAntigravityStatusMessage("대시보드에서 Antigravity를 활성화해 주세요.")
            return
        }

        if currentLogPath != logPath {
            stopMonitoring()
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: logPath) {
            stopAntigravityRetryTimer()
            if currentLogPath != logPath || fileMonitorSource == nil {
                startFileMonitoring(at: logPath)
            } else {
                scheduleUsageReload(from: logPath)
            }
        } else {
            stopMonitoring()
            updateAntigravityStatusMessage("Antigravity CLI에 로그인하면 \(logPath) 파일이 생성됩니다.")
            startAntigravityRetryTimer(for: logPath)
        }
    }

    private func updateAntigravityStatusMessage(_ message: String) {
        DispatchQueue.main.async {
            self.antigravityStatusMessage = message
        }
    }

    private func resetAntigravityUsage() {
        DispatchQueue.main.async { [weak self] in
            self?.usageData = .empty
            self?.updateServiceUsage(name: "Antigravity", usage: 0.0, quotas: [])
        }
    }

    private func startAntigravityRetryTimer(for logPath: String) {
        guard antigravityRetryTimer == nil else { return }

        antigravityRetryTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard FileManager.default.fileExists(atPath: logPath) else { return }
            self.stopAntigravityRetryTimer()
            self.startFileMonitoring(at: logPath)
        }
    }

    private func stopAntigravityRetryTimer() {
        antigravityRetryTimer?.invalidate()
        antigravityRetryTimer = nil
    }

    // MARK: - File Monitoring (Antigravity local usage file)

    private func startFileMonitoring(at logPath: String) {
        scheduleUsageReload(from: logPath)

        let fd = open(logPath, O_EVTONLY)
        guard fd >= 0 else {
            updateAntigravityStatusMessage("사용량 파일을 읽을 수 없습니다.")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .background)
        )

        source.setEventHandler { [weak self] in
            self?.scheduleUsageReload(from: logPath)
        }

        source.setCancelHandler {
            close(fd)
        }

        fileMonitorSource = source
        currentLogPath = logPath
        source.resume()
    }

    private func scheduleUsageReload(from path: String) {
        antigravityReloadWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.loadUsageData(from: path)
        }
        antigravityReloadWorkItem = workItem
        usageQueue.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func stopMonitoring() {
        antigravityReloadWorkItem?.cancel()
        antigravityReloadWorkItem = nil

        if let source = fileMonitorSource {
            source.cancel()
            fileMonitorSource = nil
        }
        currentLogPath = nil
    }

    private func loadUsageData(from path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(UsageData.self, from: data)

            DispatchQueue.main.async {
                self.usageData = decoded
                self.updateServiceUsage(
                    name: "Antigravity",
                    usage: decoded.totalSpent,
                    quotas: decoded.quotas
                )

                let hasQuotaData = !decoded.quotas.isEmpty
                self.antigravityStatusMessage = hasQuotaData
                    ? "로컬 사용량 파일 연동 완료 (실시간 동기화 중)"
                    : "사용량 파일은 있지만 아직 쿼터 데이터가 없습니다."
            }
        } catch {
            updateAntigravityStatusMessage("사용량 파일을 읽지 못했습니다. Antigravity CLI가 실행 중인지 확인해 주세요.")
        }
    }

    private func updateServiceUsage(name: String, usage: Double, quotas: [ModelQuota]) {
        guard let index = services.firstIndex(where: { $0.name == name }) else { return }
        var updated = services
        updated[index].currentUsage = usage
        updated[index].quotas = quotas
        services = updated
    }

    // MARK: - Polling (Cursor usage refresh)

    private func startPollingTimer() {
        fetchCursorUsageDirectly()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.fetchCursorUsageDirectly()
        }
    }

    private func stopPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Cursor API Integration

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

        usageQueue.async { [weak self] in
            guard let self = self else { return }

            guard let token = CursorSessionReader.readAccessToken() else {
                return
            }

            guard let sub = CursorSessionReader.extractSubFromJWT(token) else {
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
                guard let self = self, error == nil, let data = data else { return }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    return
                }

                do {
                    let usage = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
                    self.processCursorUsage(usage)
                } catch {
                    return
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
        }
    }

    deinit {
        stopMonitoring()
        stopAntigravityRetryTimer()
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
