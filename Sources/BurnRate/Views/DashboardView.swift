import SwiftUI

struct DashboardView: View {
    @ObservedObject var configManager: ConfigManager
    @State private var showingSettings = false
    @State private var activeDetailService: AIService? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            if let detailService = activeDetailService, detailService.name == "Antigravity" {
                let currentService = configManager.services.first(where: { $0.id == detailService.id }) ?? detailService
                AntigravityDetailView(service: currentService, activeDetailService: $activeDetailService)
            } else if showingSettings {
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
                
                // 서비스 리스트 영역
                List {
                    Section(header: Text("연동된 AI").font(.caption).foregroundColor(.secondary)) {
                        ForEach(configManager.services.filter(\.isEnabled)) { service in
                            if service.name == "Antigravity" {
                                Button(action: {
                                    activeDetailService = service
                                }) {
                                    ServiceRowView(service: service, isLinked: configManager.isGoogleLoggedIn)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            } else {
                                ServiceRowView(service: service, isLinked: false)
                            }
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
