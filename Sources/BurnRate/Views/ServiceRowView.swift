import SwiftUI

struct ServiceRowView: View {
    let service: AIService
    
    var body: some View {
        HStack {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(service.isEnabled ? .orange : .secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.body)
                    .fontWeight(.medium)
                if service.isEnabled {
                    Text("연동 활성화됨")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Text("연동 해제됨")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if service.isEnabled {
                HStack(spacing: 2) {
                    Text(String(format: "%.0f", service.currentUsage))
                        .fontWeight(.bold)
                    Text("/")
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f", service.totalLimit))
                        .foregroundColor(.secondary)
                }
                .font(.system(.body, design: .rounded))
            } else {
                Text("—")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
    
    private var iconName: String {
        switch service.name {
        case "Antigravity":
            return "sparkles"
        case "Claude Code":
            return "terminal"
        case "Codex":
            return "cpu"
        case "Cursor":
            return "cursorarrow"
        default:
            return "questionmark.circle"
        }
    }
}
