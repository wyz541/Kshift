import CoreGraphics
import Foundation
import ImageIO
import KshiftPresentation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public enum KshiftReportExporter {
    public static func renderPNG(report: KshiftWorkReport, scale: CGFloat = 2) -> Data? {
        let content = KshiftReportRenderCard(report: report)
            .frame(width: 900)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: 900, height: nil)
        guard let image = renderer.cgImage else { return nil }

        let data = CFDataCreateMutable(nil, 0)
        guard let data,
              let destination = CGImageDestinationCreateWithData(
                  data,
                  UTType.png.identifier as CFString,
                  1,
                  nil
              )
        else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

private struct KshiftReportRenderCard: View {
    let report: KshiftWorkReport

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Kshift 工作报告")
                .font(.largeTitle.bold())
            HStack {
                Text("来源 r\(report.sourceRevision)")
                Spacer()
                Text(report.generatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                metric("任务", "\(report.statistics.taskCount)")
                metric("完成", "\(report.statistics.completedCount)")
                metric("逾期", "\(report.statistics.overdueCount)")
                metric("跨日", "\(report.statistics.crossDayCount)")
            }

            Divider()

            VStack(spacing: 0) {
                ForEach(report.tasks) { task in
                    HStack(alignment: .top, spacing: 14) {
                        Text(task.title)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(task.status.title)
                            .font(.caption.weight(.semibold))
                        Text(task.assigneeName ?? "未分配")
                            .font(.caption)
                            .frame(width: 72, alignment: .leading)
                        Text("\(task.estimateMinutes) 分钟")
                            .font(.caption.monospacedDigit())
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    Divider()
                }
            }
        }
        .padding(44)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}
