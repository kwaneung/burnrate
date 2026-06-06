import SwiftUI

struct ServiceRowView: View {
    let service: AIService
    let spent: Double
    
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
                Text(String(format: "$%.4f", spent))
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.bold)
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
        case "Cursor Agent":
            return "cursorarrow"
        case "GitHub Copilot":
            return "cpu"
        default:
            return "questionmark.circle"
        }
    }
}
