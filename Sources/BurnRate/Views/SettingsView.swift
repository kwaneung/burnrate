import SwiftUI

struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @Binding var isPresented: Bool
    
    @State private var isResetConfirming = false
    
    var body: some View {
        VStack(spacing: 20) {
            // 헤더 (좌측 뒤로가기 버튼)
            HStack(spacing: 12) {
                Button(action: {
                    isResetConfirming = false
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
                    // 에이전트 개별 연동 섹션
                    VStack(alignment: .leading, spacing: 8) {
                        Text("에이전트 연동")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 8) {
                            // 1. Antigravity (CLI 세션 + Usage API)
                            HStack(alignment: .top) {
                                Image(systemName: "sparkles")
                                    .font(.title3)
                                    .foregroundColor(configManager.isAntigravityLinked ? .orange : .secondary)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Antigravity")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(configManager.isAntigravityLinked ? .primary : .secondary)
                                    
                                    if configManager.isAntigravityLinked {
                                        Text(configManager.antigravityStatusMessage)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    } else {
                                        Text("Antigravity CLI 로그인 세션으로 사용량 API를 조회합니다.")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                
                                Spacer(minLength: 8)
                                
                                if configManager.isAntigravityLinked {
                                    Button("연동 해제") {
                                        configManager.isAntigravityLinked = false
                                    }
                                    .buttonStyle(BorderedButtonStyle())
                                    .controlSize(.small)
                                } else {
                                    Button("연동하기") {
                                        if AntigravitySessionReader.hasActiveSession {
                                            configManager.isAntigravityLinked = true
                                        } else {
                                            configManager.antigravityStatusMessage = "Antigravity CLI에 로그인되어 있지 않습니다. agy를 실행해 로그인해 주세요."
                                        }
                                    }
                                    .buttonStyle(BorderedProminentButtonStyle())
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.secondary.opacity(configManager.isAntigravityLinked ? 0.06 : 0.03))
                            .cornerRadius(8)
                            
                            // 1-2. Cursor (로컬 세션 + Usage API)
                            HStack(alignment: .top) {
                                Image(systemName: "cursorarrow")
                                    .font(.title3)
                                    .foregroundColor(configManager.isCursorLinked ? .blue : .secondary)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cursor")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(configManager.isCursorLinked ? .primary : .secondary)
                                    
                                    if configManager.isCursorLinked {
                                        Text(configManager.cursorStatusMessage)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    } else {
                                        Text("Cursor 앱의 로컬 세션 파일을 읽어 사용량을 수집합니다. (비공식 API 연동)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                
                                Spacer(minLength: 8)
                                
                                if configManager.isCursorLinked {
                                    Button("연동 해제") {
                                        configManager.isCursorLinked = false
                                    }
                                    .buttonStyle(BorderedButtonStyle())
                                    .controlSize(.small)
                                } else {
                                    Button("연동하기") {
                                        if CursorSessionReader.hasActiveSession {
                                            configManager.isCursorLinked = true
                                        } else if CursorSessionReader.hasStoredSession {
                                            configManager.cursorStatusMessage = "세션이 만료되었습니다. Cursor를 실행해 다시 로그인해 주세요."
                                        } else {
                                            configManager.cursorStatusMessage = "Cursor에 로그인되어 있지 않습니다. Cursor를 실행해 로그인해 주세요."
                                        }
                                    }
                                    .buttonStyle(BorderedProminentButtonStyle())
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.secondary.opacity(configManager.isCursorLinked ? 0.06 : 0.03))
                            .cornerRadius(8)
                            
                            // 2. 나머지 준비중인 에이전트들
                            ForEach(["Claude Code", "Codex"], id: \.self) { name in
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
                                    set: { newValue in
                                        var updated = configManager.services
                                        updated[index].isEnabled = newValue
                                        configManager.services = updated
                                        configManager.refreshDataSynchronization()
                                    }
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
            
            if isResetConfirming {
                VStack(spacing: 10) {
                    Text("설정을 초기화할까요?")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("연동 상태, 대시보드 표시 설정, 사용량 데이터가 처음 설치한 상태로 돌아갑니다.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 12) {
                        Button("취소") {
                            isResetConfirming = false
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .controlSize(.small)
                        
                        Button("초기화") {
                            configManager.resetAllSettings()
                            isResetConfirming = false
                        }
                        .buttonStyle(BorderedProminentButtonStyle())
                        .controlSize(.small)
                        .tint(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            } else {
                HStack(spacing: 20) {
                    Button("설정 초기화") {
                        isResetConfirming = true
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    
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
