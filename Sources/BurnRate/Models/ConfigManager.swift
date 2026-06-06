import Foundation
import Combine

class ConfigManager: ObservableObject {
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
        loadServices()
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
        
        mockTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                var updatedServices = self.services
                let enabledIndices = updatedServices.indices.filter { updatedServices[$0].isEnabled }
                
                if let randomIndex = enabledIndices.randomElement() {
                    let serviceName = updatedServices[randomIndex].name
                    
                    if serviceName == "Antigravity", var quotas = updatedServices[randomIndex].quotas, !quotas.isEmpty {
                        // Antigravity인 경우, 모델 중 임의의 하나의 잔여 쿼터(remainingPercent)를 랜덤 감소
                        let quotaIndex = Int.random(in: 0..<quotas.count)
                        let currentRemaining = quotas[quotaIndex].remainingPercent
                        let depletion = Int.random(in: 2...8)
                        
                        quotas[quotaIndex].remainingPercent = max(currentRemaining - depletion, 0)
                        updatedServices[randomIndex].quotas = quotas
                        
                        // 대표값 설정: 모델 중 가장 많이 소진된(가장 잔여량이 적은) 쿼터 소진율을 대시보드 대표 사용량으로 연산
                        let minRemaining = quotas.map { $0.remainingPercent }.min() ?? 100
                        updatedServices[randomIndex].currentUsage = Double(100 - minRemaining)
                        
                        print("Mock usage: Antigravity - \(quotas[quotaIndex].modelName) remaining: \(quotas[quotaIndex].remainingPercent)% (Representative usage: \(updatedServices[randomIndex].currentUsage)/100)")
                    } else {
                        // 일반 서비스인 경우 단순 가산
                        let addition = Double.random(in: 1.0...15.0)
                        let limit = updatedServices[randomIndex].totalLimit
                        let current = updatedServices[randomIndex].currentUsage
                        
                        updatedServices[randomIndex].currentUsage = min(current + addition, limit)
                        print("Mock usage added to \(serviceName): +\(String(format: "%.1f", addition)) -> \(updatedServices[randomIndex].currentUsage)/\(limit)")
                    }
                    
                    self.services = updatedServices
                    
                    // 합산 사용량을 usageData.totalSpent에 바인딩
                    let totalUsage = updatedServices.filter(\.isEnabled).map(\.currentUsage).reduce(0, +)
                    self.usageData = UsageData(totalSpent: totalUsage)
                }
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
