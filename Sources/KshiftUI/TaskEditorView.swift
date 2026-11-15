import KshiftCore
import SwiftUI

enum TaskEditorPresentation {
    case sheet
    case popover
}

struct TaskEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskDraft
    @State private var tagText: String
    @State private var validationMessage: String?
    @State private var isSaving = false
    private let presentation: TaskEditorPresentation

    init(
        model: AppModel,
        initialDraft: TaskDraft,
        presentation: TaskEditorPresentation = .sheet
    ) {
        self.model = model
        self.presentation = presentation
        _draft = State(initialValue: initialDraft)
        _tagText = State(initialValue: initialDraft.tags.joined(separator: ", "))
    }

    var body: some View {
        switch presentation {
        case .sheet:
            sheetBody
        case .popover:
            popoverBody
        }
    }

    private var editorFields: some View {
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

            if presentation == .popover {
                assigneeField

                HStack(alignment: .top, spacing: 16) {
                    startDateField
                    dueDateField
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    assigneeField
                    startDateField
                    dueDateField
                }
            }

            fieldGroup("标签") {
                TextField("例如：发布, 审核", text: $tagText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("任务标签")
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
    }

    private var assigneeField: some View {
        fieldGroup("负责人") {
            Menu {
                Button {
                    draft.assigneeIDs.removeAll()
                } label: {
                    Label(
                        "未分配",
                        systemImage: draft.assigneeIDs.isEmpty
                            ? "checkmark"
                            : "person.crop.circle.badge.questionmark"
                    )
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
    }

    private var startDateField: some View {
        fieldGroup("开始日期") {
            DatePicker(
                "开始日期",
                selection: Binding(
                    get: { draft.startDate ?? draft.dueDate },
                    set: { draft.startDate = $0 }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .environment(\.timeZone, model.projectTimeZone)
        }
    }

    private var dueDateField: some View {
        fieldGroup("截止日期") {
            DatePicker(
                "截止日期",
                selection: $draft.dueDate,
                displayedComponents: .date
            )
            .labelsHidden()
            .environment(\.timeZone, model.projectTimeZone)
        }
    }

    private var sheetBody: some View {
        NavigationStack {
            ScrollView {
                editorFields
                    .frame(maxWidth: 620, alignment: .leading)
            }
            .background(.background)
            .navigationTitle(draft.isNew ? "新建任务" : "编辑任务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .buttonStyle(KshiftCompactGlassButtonStyle())
                }
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
            }
            .interactiveDismissDisabled(isSaving)
            .frame(idealWidth: 620, idealHeight: 670)
        }
    }

    private var popoverBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(draft.isNew ? "新建任务" : "编辑任务")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(KshiftCompactGlassButtonStyle())
                .accessibilityLabel("关闭任务编辑")
                .accessibilityIdentifier("close-task-editor")
            }
            .padding(.horizontal, 14)
            .frame(height: 48)

            Divider()

            ScrollView {
                editorFields
            }

            Divider()

            HStack(spacing: 8) {
                Button("取消") { dismiss() }
                    .buttonStyle(KshiftCompactGlassButtonStyle())
                Spacer()
                saveButton
            }
            .padding(12)
        }
        .frame(width: 400, height: 560)
        .background(.background)
        .interactiveDismissDisabled(isSaving)
    }

    private var saveButton: some View {
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
        .buttonStyle(KshiftCompactAccentGlassButtonStyle())
        .disabled(isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("save-task")
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
        if let startDate = draft.startDate, startDate > draft.dueDate {
            validationMessage = "开始日期不能晚于截止日期。"
            return
        }
        validationMessage = nil
        isSaving = true
        var submitted = draft
        submitted.title = trimmedTitle
        submitted.tags = tagText
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
