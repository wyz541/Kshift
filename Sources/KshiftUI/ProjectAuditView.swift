import KshiftCore
import SwiftUI

struct ProjectAuditView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var entries: [ProjectAuditEntry] {
        Array((model.snapshot?.audit ?? []).reversed())
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "暂无项目审计",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("成功写入后，服务端会返回有界审计记录。")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(entries) { entry in
                                auditRow(entry)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("项目审计")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                        .buttonStyle(.glass)
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 660, minHeight: 480, idealHeight: 680)
        .accessibilityIdentifier("project-audit-sheet")
    }

    private func auditRow(_ entry: ProjectAuditEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.summary)
                    .font(.headline)
                Spacer()
                if entry.revision > 0 {
                    Text("r\(entry.revision)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(detail(entry))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(entry.occurredAt)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kshiftContentBoard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("project-audit-entry-\(entry.id)")
    }

    private func detail(_ entry: ProjectAuditEntry) -> String {
        var parts = [model.actorName(for: entry.actorID), entry.action]
        if let taskID = entry.taskID, let task = model.task(withID: taskID) {
            parts.append(task.title)
        }
        return parts.joined(separator: " · ")
    }
}
