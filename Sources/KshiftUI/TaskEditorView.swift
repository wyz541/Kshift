import KshiftCore
import SwiftUI

struct TaskEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskDraft
    @State private var validationMessage: String?
    @State private var isSaving = false

    init(model: AppModel, initialDraft: TaskDraft) {
        self.model = model
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fieldGroup("标题") {
                        TextField("例如：确认发布清单", text: $draft.title, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...3)
                            .accessibilityLabel("任务标题")
                            .accessibilityIdentifier("task-title")
                    }

                    fieldGroup("说明") {
                        TextEditor(text: $draft.notes)
                            .font(.body)
                            .frame(minHeight: 130)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .kshiftContentBoard()
                            .accessibilityLabel("任务说明")
                    }

                    HStack(alignment: .top, spacing: 16) {
                        fieldGroup("状态") {
                            Picker("状态", selection: $draft.status) {
                                ForEach(TaskStatus.allCases) { status in
                                    Label(status.title, systemImage: status.symbol)
                                        .tag(status)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        fieldGroup("优先级") {
                            Picker("优先级", selection: $draft.priority) {
                                ForEach(TaskPriority.allCases) { priority in
                                    Text(priority.title).tag(priority)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    HStack(alignment: .top, spacing: 16) {
                        fieldGroup("负责人") {
                            Menu {
                                Button {
                                    draft.assigneeIDs.removeAll()
                                } label: {
                                    Label("未分配", systemImage: draft.assigneeIDs.isEmpty ? "checkmark" : "person.crop.circle.badge.questionmark")
                                }
                                ForEach(model.people) { person in
                                    Button {
                                        toggleAssignee(person.id)
                                    } label: {
                                        Label(
                                            person.name,
                                            systemImage: draft.assigneeIDs.contains(person.id)
                                                ? "checkmark.circle.fill"
                                                : "circle"
                                        )
                                    }
                                }
                            } label: {
                                Text(assigneeSummary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .pickerStyle(.menu)
                        }
                        fieldGroup("日期") {
                            DatePicker(
                                "任务日期",
                                selection: $draft.dueDate,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .environment(\.timeZone, model.projectTimeZone)
                        }
                    }

                    if draft.taskID != nil {
                        Label(
                            "编辑基于任务版本 \(draft.expectedVersion)",
                            systemImage: "lock.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("task-validation")
                    }

                    if let conflict = model.conflict {
                        ConflictInlineView(model: model, notice: conflict, dismiss: dismiss.callAsFunction)
                    }
                }
                .padding(22)
                .frame(maxWidth: 620, alignment: .leading)
            }
            .background(.background)
            .navigationTitle(draft.isNew ? "新建任务" : "编辑任务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .buttonStyle(.glass)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("保存")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("save-task")
                }
            }
            .interactiveDismissDisabled(isSaving)
            .frame(idealWidth: 620, idealHeight: 670)
        }
    }

    private func fieldGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func save() {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            validationMessage = "任务标题不能为空。"
            return
        }
        guard trimmedTitle.count <= 200 else {
            validationMessage = "任务标题不能超过 200 个字符。"
            return
        }
        validationMessage = nil
        isSaving = true
        var submitted = draft
        submitted.title = trimmedTitle
        Swift.Task {
            let saved = await model.saveTask(submitted)
            isSaving = false
            if saved {
                draft = submitted
                dismiss()
            }
        }
    }

    private var assigneeSummary: String {
        guard !draft.assigneeIDs.isEmpty else { return "未分配" }
        return draft.assigneeIDs
            .compactMap { id in model.people.first(where: { $0.id == id })?.name }
            .joined(separator: "、")
    }

    private func toggleAssignee(_ id: String) {
        if draft.assigneeIDs.contains(id) {
            draft.assigneeIDs.removeAll { $0 == id }
        } else {
            draft.assigneeIDs.append(id)
        }
    }
}

private struct ConflictInlineView: View {
    @ObservedObject var model: AppModel
    let notice: ConflictNotice
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("任务已被其他编辑者修改", systemImage: "person.2.badge.gearshape")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text(notice.message)
                .font(.callout)
            Text("当前草稿保留在编辑器中。刷新会载入最新版本。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("保留草稿") { model.dismissConflict() }
                    .buttonStyle(.glass)
                Button("刷新并关闭") {
                    Swift.Task {
                        await model.resolveConflictByRefreshing()
                        dismiss()
                    }
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(14)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conflict-inline")
    }
}
