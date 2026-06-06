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
                
                // 중앙 대시보드 요약 카드 (전체 AI 합산 사용량 & 프로그레스 바)
                VStack(spacing: 8) {
                    let totalUsage = configManager.services.filter(\.isEnabled).map(\.currentUsage).reduce(0, +)
                    let totalLimit = configManager.services.filter(\.isEnabled).map(\.totalLimit).reduce(0, +)
                    let ratio = totalLimit > 0 ? totalUsage / totalLimit : 0.0
                    
                    VStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.orange)
                        
                        HStack(alignment: .bottom, spacing: 4) {
                            Text(String(format: "%.0f", totalUsage))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                            Text("/")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.0f", totalLimit))
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("전체 AI 합산 사용량")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 6)
                        
                        // 수평형 프로그레스 바 (그라데이션 및 애니메이션 제거하여 CLI 번들 셰이더 로더 크래시 방지)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(height: 8)
                                
                                let barColor: Color = ratio >= 0.8 ? .red : (ratio >= 0.5 ? .orange : .yellow)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(barColor)
                                    .frame(width: geo.size.width * CGFloat(min(ratio, 1.0)), height: 8)
                            }
                        }
                        .frame(height: 8)
                        .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(16)
                }
                .padding()
                
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
