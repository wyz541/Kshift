import KshiftCore
import SwiftUI

enum TaskEditorPresentation {
    case sheet
    case popover
}

struct TaskEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var draft: TaskDraft
    @State private var markdownMode: MarkdownViewMode
    @State private var tagInput = ""
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
        _markdownMode = State(
            initialValue: initialDraft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .source
                : .preview
        )
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
        VStack(alignment: .leading, spacing: 16) {
            titleField

            markdownSection

            panelSection("属性", systemImage: "slider.horizontal.3") {
                taskPropertyFields
            }

            panelSection("标签", systemImage: "tag") {
                TaskTagEditor(tags: $draft.tags, input: $tagInput)
            }

            if draft.taskID != nil {
                Label(
                    "编辑基于任务版本 \(draft.expectedVersion)",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
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
        .padding(20)
    }

    private var markdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("内容", systemImage: "text.alignleft")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Picker("Markdown 显示模式", selection: $markdownMode) {
                    ForEach(MarkdownViewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
                .accessibilityLabel("Markdown 显示模式")
                .accessibilityIdentifier("markdown-mode")
            }

            MarkdownEditorView(
                text: $draft.notes,
                mode: markdownMode,
                paneHeight: markdownPaneHeight
            )
        }
        .padding(14)
        .background(
            .primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var titleField: some View {
        TextField(
            "任务标题",
            text: $draft.title,
            prompt: Text("任务标题"),
            axis: .vertical
        )
        .font(.title3.weight(.semibold))
        .textFieldStyle(.plain)
        .lineLimit(1...3)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .background(
            .primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("任务标题")
        .accessibilityIdentifier("task-title")
    }

    private func panelSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            content()
        }
        .padding(14)
        .background(
            .primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var taskPropertyFields: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                statusField
                    .frame(maxWidth: .infinity, alignment: .leading)
                priorityField
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if horizontalSizeClass == .compact {
                assigneeField

                HStack(alignment: .top, spacing: 16) {
                    startDateField
                        .frame(maxWidth: .infinity, alignment: .leading)
                    dueDateField
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    assigneeField
                        .frame(maxWidth: .infinity, alignment: .leading)
                    startDateField
                        .frame(maxWidth: .infinity, alignment: .leading)
                    dueDateField
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var statusField: some View {
        fieldGroup("状态") {
            Menu {
                ForEach(TaskStatus.allCases) { status in
                    Button {
                        draft.status = status
                    } label: {
                        Label(
                            status.title,
                            systemImage: status == draft.status ? "checkmark" : status.symbol
                        )
                    }
                }
            } label: {
                TaskMetadataControlLabel(
                    title: draft.status.title,
                    systemImage: draft.status.symbol,
                    tint: draft.status.tint
                )
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .accessibilityLabel("任务状态")
            .accessibilityValue(draft.status.title)
            .accessibilityIdentifier("task-status")
        }
    }

    private var priorityField: some View {
        fieldGroup("优先级") {
            Menu {
                ForEach(TaskPriority.allCases) { priority in
                    Button {
                        draft.priority = priority
                    } label: {
                        Label(
                            priority.title,
                            systemImage: priority == draft.priority ? "checkmark" : "flag.fill"
                        )
                    }
                }
            } label: {
                TaskMetadataControlLabel(
                    title: draft.priority.title,
                    systemImage: "flag.fill",
                    tint: draft.priority.tint
                )
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .accessibilityLabel("任务优先级")
            .accessibilityValue(draft.priority.title)
            .accessibilityIdentifier("task-priority")
        }
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
                TaskMetadataControlLabel(
                    title: assigneeSummary,
                    systemImage: "person.2",
                    tint: .blue
                )
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .accessibilityLabel("任务负责人")
            .accessibilityValue(assigneeSummary)
            .accessibilityIdentifier("task-assignee")
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
            .datePickerStyle(.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.timeZone, model.projectTimeZone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var markdownPaneHeight: CGFloat {
        if isCompactWidth {
            return 180
        }
        return presentation == .popover ? 190 : 220
    }

    private var dueDateField: some View {
        fieldGroup("截止日期") {
            DatePicker(
                "截止日期",
                selection: $draft.dueDate,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.timeZone, model.projectTimeZone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sheetBody: some View {
        NavigationStack {
            ScrollView {
                editorFields
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
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
            .frame(
                minWidth: isCompactWidth ? nil : 680,
                idealWidth: isCompactWidth ? nil : 720,
                minHeight: isCompactWidth ? nil : 640,
                idealHeight: isCompactWidth ? nil : 720
            )
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
        .frame(
            maxWidth: isCompactWidth ? .infinity : nil,
            maxHeight: isCompactWidth ? .infinity : nil
        )
        .frame(
            width: isCompactWidth ? nil : 560,
            height: isCompactWidth ? nil : 580
        )
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        submitted.tags = TaskTagValues.adding(tagInput, to: draft.tags)
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

private struct TaskMetadataControlLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var minimumHeight: CGFloat {
        horizontalSizeClass == .compact ? 44 : 34
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(title)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.16), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
