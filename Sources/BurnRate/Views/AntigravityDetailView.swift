import SwiftUI

struct AntigravityDetailView: View {
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
                        Text("Model Quota")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        
                        ForEach(quotas) { quota in
                            VStack(alignment: .leading, spacing: 6) {
                                // 모델 이름
                                Text(quota.modelName)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .fontWeight(.bold)
                                
                                // 레트로 격자형 게이지 바 + 퍼센트
                                HStack(spacing: 8) {
                                    SegmentedProgressBar(percent: quota.remainingPercent)
                                        .frame(height: 14)
                                    
                                    Text("\(quota.remainingPercent)%")
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.bold)
                                        .frame(width: 32, alignment: .trailing)
                                }
                                
                                // 하단 가이드 텍스트 (남은 용량 및 갱신 시각)
                                HStack {
                                    if quota.remainingPercent == 100 && quota.refreshTimeString == "Available" {
                                        Text("Quota available")
                                            .foregroundColor(.green)
                                    } else {
                                        Text("\(quota.remainingPercent)% remaining")
                                            .foregroundColor(.secondary)
                                        Text("•")
                                            .foregroundColor(.secondary)
                                        Text("Refreshes in \(quota.refreshTimeString)")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .font(.system(size: 10, design: .monospaced))
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            } else {
                VStack {
                    Spacer()
                    Text("상세 쿼터 정보가 없습니다.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .frame(width: 280, height: 420)
    }
}

// 스크린샷과 유사한 격자형 레트로 게이지 바를 구현하는 컴포넌트
struct SegmentedProgressBar: View {
    let percent: Int // 0 ~ 100
    
    var body: some View {
        HStack(spacing: 2) {
            // 20개의 세그먼트 (각 세그먼트당 5% 점유)
            ForEach(0..<20) { index in
                let segmentThreshold = index * 5
                let isActive = segmentThreshold < percent
                
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? Color.green : Color.secondary.opacity(0.18))
            }
        }
    }
}
