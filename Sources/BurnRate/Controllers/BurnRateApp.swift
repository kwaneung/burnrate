import SwiftUI

@main
struct BurnRateApp: App {
    @StateObject private var configManager = ConfigManager()
    
    @State private var frameIndex = 0
    @State private var frameCounter = 0
    
    // 0.05초(50ms) 간격으로 동작하는 타이머. 소진율에 따라 프레임 갱신 주기를 제어합니다.
    let animationTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    
    var body: some Scene {
        MenuBarExtra {
            DashboardView(configManager: configManager)
        } label: {
            // 상태별 실시간 캐릭터/SF Symbol 프레임만 단독으로 렌더링
            imageForStatus()
                .environment(\.imageScale, .large)
                .onReceive(animationTimer) { _ in
                    animateFrames()
                }
        }
        .menuBarExtraStyle(.window)
    }
    
    // 로컬 에셋이 있으면 일반 이미지로, 없으면 SF Symbol로 이미지 생성
    private func imageForStatus() -> Image {
        let name = currentFrameName
        if hasLocalAsset(name: name) {
            return Image(name)
        } else {
            return Image(systemName: name)
        }
    }
    
    private var totalSpent: Double {
        return configManager.usageData.totalSpent
    }
    
    // 사용 금액에 따라 프레임에 어울리는 이미지명 혹은 SF Symbol명을 리턴
    private var currentFrameName: String {
        let spent = totalSpent
        
        let baseName: String
        if spent >= 10.0 {
            baseName = "cat_fire"
        } else if spent >= 5.0 {
            baseName = "cat_run"
        } else if spent >= 1.0 {
            baseName = "cat_walk"
        } else {
            baseName = "cat_sleep"
        }
        
        let imageName = "\(baseName)_\(frameIndex)"
        if hasLocalAsset(name: imageName) {
            return imageName
        } else {
            // Asset 리소스가 없을 경우 시스템 아이콘으로 대체 (기본값 flame.fill)
            if spent >= 10.0 { return "flame.fill" }
            if spent >= 5.0 { return "bolt.fill" }
            if spent >= 1.0 { return "sparkles" }
            return "flame.fill"
        }
    }
    
    private func hasLocalAsset(name: String) -> Bool {
        return NSImage(named: name) != nil
    }
    
    private func animateFrames() {
        let spent = totalSpent
        
        // 50ms 타이머 기준으로 프레임당 유지할 틱(tick) 수 결정
        // $10.0 이상: 50ms 마다 갱신 (1틱)
        // $5.0 이상: 100ms 마다 갱신 (2틱)
        // $1.0 이상: 200ms 마다 갱신 (4틱)
        // $1.0 미만: 400ms 마다 갱신 (8틱)
        let ticksPerFrame: Int
        if spent >= 10.0 {
            ticksPerFrame = 1
        } else if spent >= 5.0 {
            ticksPerFrame = 2
        } else if spent >= 1.0 {
            ticksPerFrame = 4
        } else {
            ticksPerFrame = 8
        }
        
        frameCounter += 1
        if frameCounter >= ticksPerFrame {
            frameCounter = 0
            frameIndex = (frameIndex + 1) % 5 // 각 애니메이션은 5프레임(0~4)으로 구성됨
        }
    }
}
