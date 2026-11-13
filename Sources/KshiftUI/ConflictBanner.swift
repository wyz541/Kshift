import KshiftCore
import SwiftUI

struct ConflictBanner: View {
    @ObservedObject var model: AppModel
    let notice: ConflictNotice

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("检测到并发修改")
                        .font(.callout.weight(.semibold))
                    Text(notice.message)
                        .font(.caption)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                Button("刷新") {
                    Swift.Task { await model.resolveConflictByRefreshing() }
                }
                .buttonStyle(.glassProminent)
                Button("保留草稿") {
                    model.dismissConflict()
                }
                .buttonStyle(.glass)
            }
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: 720)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("并发修改警告：\(notice.message)")
        .accessibilityIdentifier("conflict-banner")
    }
}
