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
                    // Google Client ID 설정 섹션
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Google OAuth Client ID 설정")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        TextField("Client ID 입력", text: $configManager.googleClientID)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        
                        Text("GCP 콘솔에서 '데스크톱 앱' 유형의 OAuth 클라이언트 ID를 발급받아 입력해주세요. 입력하지 않으면 기본 공용 Client ID가 사용됩니다.")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    Divider()
                    
                    // 에이전트 개별 연동 섹션 (Antigravity는 실제 구글 로그인 연동 버튼으로 기능 할당)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("에이전트 연동")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 8) {
                            // 1. Antigravity (실제 활성화된 구글 OAuth 연동 카드)
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.title3)
                                    .foregroundColor(configManager.isGoogleLoggedIn ? .orange : .secondary)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Antigravity")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(configManager.isGoogleLoggedIn ? .primary : .secondary)
                                    
                                    if configManager.isGoogleLoggedIn {
                                        Text("\(configManager.googleAccountName) 계정 연동 완료 (사용량 동기화 중)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("구글 계정을 연동하여 사용량을 실시간 수집합니다.")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if configManager.isGoogleLoggedIn {
                                    Button("연동 해제") {
                                        configManager.logoutGoogle()
                                    }
                                    .buttonStyle(BorderedButtonStyle())
                                    .controlSize(.small)
                                } else {
                                    Button("연동하기") {
                                        configManager.startGoogleLogin()
                                    }
                                    .buttonStyle(BorderedProminentButtonStyle())
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.secondary.opacity(configManager.isGoogleLoggedIn ? 0.06 : 0.03))
                            .cornerRadius(8)
                            
                            // 2. 나머지 준비중인 에이전트들
                            ForEach(["Claude Code", "Codex", "Cursor"], id: \.self) { name in
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
