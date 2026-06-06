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
                
                // 중앙 대시보드 요약 카드
                VStack(spacing: 8) {
                    let todaySpent = configManager.usageData.totalSpent
                    
                    VStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.orange)
                            .padding(.bottom, 2)
                        
                        Text(String(format: "$%.2f", todaySpent))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        
                        Text("오늘 총 사용 요금")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(16)
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
                                case "Codex": return configManager.usageData.totalSpent * 0.3
                                case "Cursor": return configManager.usageData.totalSpent * 0.6
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
