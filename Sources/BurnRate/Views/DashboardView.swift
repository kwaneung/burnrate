import SwiftUI

struct DashboardView: View {
    @ObservedObject var configManager: ConfigManager
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                SettingsView(configManager: configManager, isPresented: $showingSettings)
            } else {
                // 헤더 영역
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                            .font(.title3)
                        Text("BurnRate")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.secondary)
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                // 중앙 대시보드 요약 (원형 그래프)
                VStack(spacing: 12) {
                    let todaySpent = configManager.usageData.totalSpent
                    let dailyBudget = configManager.dailyBudget
                    let pct = dailyBudget > 0 ? todaySpent / dailyBudget : 0.0
                    
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 12)
                        
                        Circle()
                            .trim(from: 0.0, to: CGFloat(min(pct, 1.0)))
                            .stroke(
                                AngularGradient(colors: [.yellow, .orange, .red], center: .center),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .rotationEffect(Angle(degrees: -90))
                            .animation(.easeOut(duration: 0.8), value: todaySpent)
                        
                        VStack(spacing: 2) {
                            Text(String(format: "$%.2f", todaySpent))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                            Text("오늘 사용액")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 130, height: 130)
                    .padding(.vertical, 10)
                    
                    HStack(spacing: 4) {
                        Text("일일 한도:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(String(format: "$%.2f", dailyBudget))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(todaySpent >= dailyBudget ? .red : .primary)
                    }
                }
                .padding()
                
                Divider()
                
                // 서비스 리스트 영역
                List {
                    Section(header: Text("연동된 AI").font(.caption).foregroundColor(.secondary)) {
                        ForEach(configManager.services) { service in
                            let spent: Double = {
                                guard service.isEnabled else { return 0.0 }
                                switch service.name {
                                case "Antigravity": return configManager.usageData.totalSpent
                                case "Claude Code": return configManager.usageData.totalSpent * 0.4
                                case "Cursor": return configManager.usageData.totalSpent * 0.6
                                case "GitHub Copilot": return configManager.usageData.totalSpent * 0.3
                                default: return 0.0
                                }
                            }()
                            ServiceRowView(service: service, spent: spent)
                        }
                    }
                    
                    // 최근 호출 로그 내역 섹션 제거됨
                }
                .listStyle(.sidebar)
                
                Divider()
                
                // 하단 상태바 정보
                HStack {
                    Text("실시간 동기화 중")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(width: 280, height: 420)
    }
}
