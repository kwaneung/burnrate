import SwiftUI

struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @Binding var isPresented: Bool
    
    @State private var showCursorAlert = false
    @State private var cursorAlertMessage = ""
    
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
                    // 에이전트 개별 연동 섹션
                    VStack(alignment: .leading, spacing: 8) {
                        Text("에이전트 연동")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 8) {
                            // 1. Antigravity (로컬 사용량 파일 연동)
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
                                        Text("Antigravity CLI 로그인 세션의 로컬 사용량 파일을 감시하여 사용량을 수집합니다.")
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
                                        configManager.isAntigravityLinked = true
                                    }
                                    .buttonStyle(BorderedProminentButtonStyle())
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.secondary.opacity(configManager.isAntigravityLinked ? 0.06 : 0.03))
                            .cornerRadius(8)
                            
                            // 1-2. Cursor (실제 키체인 연동 카드)
                            HStack {
                                Image(systemName: "cursorarrow")
                                    .font(.title3)
                                    .foregroundColor(configManager.isCursorLinked ? .blue : .secondary)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cursor")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(configManager.isCursorLinked ? .primary : .secondary)
                                    
                                    if configManager.isCursorLinked {
                                        Text("Cursor 로컬 세션 연동 완료 (사용량 동기화 중)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Cursor 앱의 로컬 세션 파일을 읽어 사용량을 수집합니다. (비공식 API 연동)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
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
                                        } else {
                                            cursorAlertMessage = "Cursor 로그인 세션을 찾을 수 없습니다. Cursor 에디터에 로그인되어 있는지 확인해 주세요."
                                            showCursorAlert = true
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
            
            Button("앱 종료") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
            .padding(.bottom)
        }
        .alert(isPresented: $showCursorAlert) {
            Alert(title: Text("연동 실패"), message: Text(cursorAlertMessage), dismissButton: .default(Text("확인")))
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
