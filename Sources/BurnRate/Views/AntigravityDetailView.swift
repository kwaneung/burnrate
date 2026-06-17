import SwiftUI

struct AntigravityDetailView: View {
    let service: AIService
    @Binding var activeDetailService: AIService?

    var body: some View {
        VStack(spacing: 0) {
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

            if let groups = service.quotaGroups, !groups.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(group.displayName.uppercased())
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)

                                if let description = group.description, !description.isEmpty {
                                    Text(description)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                ForEach(group.buckets) { bucket in
                                    quotaBucketRow(bucket)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
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

    @ViewBuilder
    private func quotaBucketRow(_ bucket: AntigravityQuotaBucket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bucket.displayName)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.bold)

            HStack(spacing: 8) {
                SegmentedProgressBar(percent: bucket.remainingPercent)
                    .frame(height: 14)

                Text("\(bucket.remainingPercent)%")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .frame(width: 32, alignment: .trailing)
            }

            quotaStatusText(for: bucket)
                .font(.system(size: 10, design: .monospaced))
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func quotaStatusText(for bucket: AntigravityQuotaBucket) -> some View {
        if bucket.remainingPercent >= 100 {
            Text("Quota available")
                .foregroundColor(.green)
        } else {
            HStack(spacing: 4) {
                Text("\(bucket.remainingPercent)% remaining")
                    .foregroundColor(.secondary)
                Text("•")
                    .foregroundColor(.secondary)
                Text("Refreshes in \(bucket.refreshTimeString)")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SegmentedProgressBar: View {
    let percent: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<20) { index in
                let segmentThreshold = index * 5
                let isActive = segmentThreshold < percent

                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? Color.green : Color.secondary.opacity(0.18))
            }
        }
    }
}
