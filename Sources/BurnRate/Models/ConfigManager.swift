import Foundation
import Combine

class ConfigManager: ObservableObject {
    @Published var dailyBudget: Double = 10.0 {
        didSet {
            UserDefaults.standard.set(dailyBudget, forKey: "BurnRate_DailyBudget")
        }
    }
    
    @Published var services: [AIService] = [] {
        didSet {
            saveServices()
            setupDataSynchronization()
        }
    }
    
    @Published var usageData: UsageData = .empty
    
    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var mockTimer: Timer?
    
    init() {
        self.dailyBudget = UserDefaults.standard.double(forKey: "BurnRate_DailyBudget")
        if self.dailyBudget == 0.0 {
            self.dailyBudget = 10.0 // 기본 일일 제한 $10
        }
        
        loadServices()
        setupDataSynchronization()
    }
    
    private func loadServices() {
        if let data = UserDefaults.standard.data(forKey: "BurnRate_Services"),
           let decoded = try? JSONDecoder().decode([AIService].self, from: data) {
            self.services = decoded
        } else {
            self.services = AIService.defaultServices
        }
    }
    
    func saveServices() {
        if let encoded = try? JSONEncoder().encode(services) {
            UserDefaults.standard.set(encoded, forKey: "BurnRate_Services")
        }
    }
    
    private func setupDataSynchronization() {
        stopMonitoring()
        stopMockTimer()
        
        // Antigravity 서비스가 활성화되어 있고 로그 파일 경로가 있으면 파일 모니터링을 시도
        if let antigravityService = services.first(where: { $0.name == "Antigravity" && $0.isEnabled }),
           let logPath = antigravityService.logFilePath,
           !logPath.isEmpty {
            
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: logPath) {
                // 실제 파일이 존재하면 모니터링 모드 시작
                startFileMonitoring(at: logPath)
                return
            }
        }
        
        // 파일이 없거나 연동 전일 때는 모의(Mock) 데이터 누적 타이머 작동
        startMockTimer()
    }
    
    // MARK: - File Monitoring (실제 파일 연동용)
    private func startFileMonitoring(at logPath: String) {
        loadUsageData(from: logPath)
        
        fileDescriptor = open(logPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("Failed to open log file for monitoring: \(logPath)")
            startMockTimer() // 실패 시 mock 타이머로 fallback
            return
        }
        
        fileMonitorSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .background)
        )
        
        fileMonitorSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.loadUsageData(from: logPath)
            }
        }
        
        fileMonitorSource?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        
        fileMonitorSource?.resume()
        print("Started file monitoring at: \(logPath)")
    }
    
    private func stopMonitoring() {
        if let source = fileMonitorSource {
            source.cancel()
            fileMonitorSource = nil
        }
    }
    
    private func loadUsageData(from path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(UsageData.self, from: data)
            DispatchQueue.main.async {
                self.usageData = decoded
            }
        } catch {
            print("Failed to read/decode usage data: \(error)")
        }
    }
    
    // MARK: - Mock Data Simulation (연동 전 뼈대 테스트용)
    private func startMockTimer() {
        print("Started mock data simulation timer.")
        // 앱이 켜졌을 때 초기 mock 데이터 세팅
        self.usageData = UsageData(totalSpent: 0.15)
        
        mockTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let cost = Double.random(in: 0.01...0.35)
            
            DispatchQueue.main.async {
                var currentData = self.usageData
                currentData.totalSpent += cost
                self.usageData = currentData
                print("Mock usage added: $ \(String(format: "%.4f", cost)) -> Total: $\(String(format: "%.4f", currentData.totalSpent))")
            }
        }
    }
    
    private func stopMockTimer() {
        mockTimer?.invalidate()
        mockTimer = nil
    }
    
    deinit {
        stopMonitoring()
        stopMockTimer()
    }
}

extension Array {
    mutating func push(_ element: Element) {
        self.append(element)
    }
}

extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}
