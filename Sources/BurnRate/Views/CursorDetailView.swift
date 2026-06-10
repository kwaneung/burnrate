import SwiftUI

struct CursorDetailView: View {
    let service: AIService
    @Binding var activeDetailService: AIService?
    
    var body: some View {
        VStack(spacing: 0) {
            // 헤더 (좌측 뒤로가기 버튼)
            HStack(spacing: 12) {
                Button(action: {
                    activeDetailService = nil
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.primary)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                
                Text("\(service.name) 상세 사용량")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 모델별 쿼터 목록
            if let quotas = service.quotas, !quotas.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Included in \(service.membershipLabel ?? "Pro")")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if let firstQuota = quotas.first {
                                Text("Resets on \(firstQuota.refreshTimeString)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 8)
                        
                        // 1. Total 게이지 바
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Total")
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.bold)
                            
                            HStack(spacing: 8) {
                                CursorSegmentedProgressBar(percent: Int(service.currentUsage))
                                    .frame(height: 14)
                                
                                Text("\(Int(service.currentUsage))%")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.bold)
                                    .frame(width: 32, alignment: .trailing)
                            }
                            
                            let autoUsed = quotas.first(where: { $0.modelName == "Auto + Composer" })?.usedPercent ?? 0
                            let apiUsed = quotas.first(where: { $0.modelName == "API" })?.usedPercent ?? 0
                            Text("\(autoUsed)% Auto and \(apiUsed)% API used")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 4)
                        
                        Divider()
                        
                        // 2. 개별 게이지 바 (Auto + Composer & API)
                        ForEach(quotas) { quota in
                            let usedPercent = quota.usedPercent ?? (100 - quota.remainingPercent)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(quota.modelName)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .fontWeight(.bold)
                                
                                HStack(spacing: 8) {
                                    CursorSegmentedProgressBar(percent: usedPercent)
                                        .frame(height: 14)
                                    
                                    Text("\(usedPercent)%")
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.bold)
                                        .frame(width: 32, alignment: .trailing)
                                }
                                
                                // 각 쿼터별 하단 고유 가이드 텍스트
                                if quota.modelName == "Auto + Composer" {
                                    Text("Additional usage beyond limits consumes API quota or on-demand spend.")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else if quota.modelName == "API" {
                                    Text("Additional usage beyond limits consumes on-demand spend. Your plan includes at least $20 of API usage.")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        
                        Divider()
                        
                        // 3. 온디맨드 섹션
                        VStack(alignment: .leading, spacing: 10) {
                            Text("On-Demand Usage")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            let onDemandEnabled = service.onDemandEnabled ?? false
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("On-Demand Spending")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Spacer()
                                    Text(onDemandEnabled ? "Enabled" : "Disabled")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Text(onDemandEnabled
                                     ? "On-demand spending is enabled"
                                     : "On-demand spending is currently disabled")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Monthly Limit")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Spacer()
                                    if onDemandEnabled, let limit = service.onDemandLimit {
                                        Text("$\(limit)")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Disabled")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                if onDemandEnabled, let used = service.onDemandUsed {
                                    Text("Used $\(used) this cycle")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Set a fixed amount or make it unlimited.")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            } else {
                VStack {
                    Spacer()
                    Text("상세 사용량 정보를 가져오는 중...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .frame(width: 280, height: 420)
    }
}

// Cursor 전용 블루 테마의 레트로 격자 게이지바
struct CursorSegmentedProgressBar: View {
    let percent: Int // 0 ~ 100
    
    // Cursor 특유의 블루 칼라 매핑
    private var barColor: Color {
        Color(red: 0.2, green: 0.55, blue: 0.95)
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<20) { index in
                let segmentThreshold = index * 5
                let isActive = segmentThreshold < percent
                
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? barColor : Color.secondary.opacity(0.18))
            }
        }
    }
}
