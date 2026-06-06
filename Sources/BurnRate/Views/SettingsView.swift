import SwiftUI

struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // 헤더 (좌측 뒤로가기 버튼)
            HStack(spacing: 12) {
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.primary)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                
                Text("설정")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
            }
            .padding([.top, .horizontal])
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Google 계정 연동 섹션
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Google 계정 연동 (사용량 수집)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: 12) {
                            Image(systemName: configManager.isGoogleLoggedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.xmark")
                                .font(.title2)
                                .foregroundColor(configManager.isGoogleLoggedIn ? .green : .secondary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(configManager.googleAccountName)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text(configManager.isGoogleLoggedIn ? "구글 클라우드 사용량 실시간 동기화 중" : "Claude Code, Codex, Cursor 연동을 위해 로그인하세요.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if configManager.isGoogleLoggedIn {
                                Button("로그아웃") {
                                    configManager.logoutGoogle()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Button("로그인") {
                                    configManager.startGoogleLogin()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(12)
                    }
                    
                    Divider()
                    
                    // 에이전트 개별 연동 섹션 (준비중)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("에이전트 개별 연동")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 8) {
                            ForEach(["Antigravity", "Claude Code", "Codex", "Cursor"], id: \.self) { name in
                                HStack {
                                    Image(systemName: iconForService(name))
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(.secondary)
                                        Text("개별 API 및 계정 연동 준비 중")
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.8))
                                    }
                                    
                                    Spacer()
                                    
                                    Text("준비중")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.12))
                                        .foregroundColor(.secondary)
                                        .cornerRadius(6)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.secondary.opacity(0.03))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // 대시보드 노출 설정
                    Text("대시보드 노출 설정")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    ForEach(0..<configManager.services.count, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { configManager.services[index].isEnabled },
                                    set: { configManager.services[index].isEnabled = $0 }
                                )) {
                                    Text(configManager.services[index].name)
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                                .toggleStyle(.checkbox)
                                
                                Spacer()
                            }
                            

                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Button("저장 및 닫기") {
                    configManager.saveServices()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                
                Button("앱 종료") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
            .padding(.bottom)
        }
    }
    
    private func iconForService(_ name: String) -> String {
        switch name {
        case "Antigravity": return "sparkles"
        case "Claude Code": return "terminal"
        case "Codex": return "cpu"
        case "Cursor": return "cursorarrow"
        default: return "questionmark.circle"
        }
    }
}

extension NumberFormatter {
    static var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
}
