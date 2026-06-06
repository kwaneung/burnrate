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
                    
                    // AI 서비스 리스트 및 연동 설정
                    Text("AI 서비스 연동")
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
                            
                            // Antigravity 파일 경로 설정
                            if configManager.services[index].name == "Antigravity" && configManager.services[index].isEnabled {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("로그 파일 경로 (api_usage.json)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    TextField("Log File Path", text: Binding(
                                        get: { configManager.services[index].logFilePath ?? "" },
                                        set: { configManager.services[index].logFilePath = $0.isEmpty ? nil : $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.caption, design: .monospaced))
                                }
                                .padding(.leading, 24)
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
