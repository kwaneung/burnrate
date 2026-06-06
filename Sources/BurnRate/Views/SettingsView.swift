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
