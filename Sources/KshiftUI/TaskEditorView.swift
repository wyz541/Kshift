import KshiftCore
import SwiftUI

enum TaskEditorPresentation {
    case sheet
    case popover
}

private enum TaskEditorLayoutMode: String, CaseIterable, Identifiable {
    case compact
    case detail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "简约"
        case .detail: "详情"
        }
    }

    var subtitle: String {
        switch self {
        case .compact: "核心字段"
        case .detail: "专注描述"
        }
    }
}

struct TaskEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: TaskDraft
    @State private var markdownMode: MarkdownViewMode
    @State private var tagInput = ""
    @State private var validationMessage: String?
    @State private var isSaving = false
    @State private var layoutMode: TaskEditorLayoutMode = .compact
    @State private var isShowingHistory = false
    @State private var isDuplicating = false
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
        .kshiftGlassCard(tint: Color.accentColor.opacity(0.06))
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
        .kshiftGlassCard(tint: Color.primary.opacity(0.025))
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

    private var sheetLayoutControl: some View {
        Picker("编辑模式", selection: Binding(
            get: { layoutMode },
            set: { nextMode in
                if reduceMotion {
                    layoutMode = nextMode
                } else {
                    withAnimation(.snappy(duration: 0.24)) {
                        layoutMode = nextMode
                    }
                }
            }
        )) {
            ForEach(TaskEditorLayoutMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 144)
        .tint(.gray)
        .accessibilityLabel("任务编辑模式")
        .accessibilityIdentifier("task-editor-layout-mode")
    }

    private var classicTitlebar: some View {
        ZStack {
            titlebarDragSurface

            Text(titleText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 280)
                .allowsHitTesting(false)
                .accessibilityIdentifier("task-detail")

            HStack(spacing: 12) {
                ClassicTitlebarCloseButton(action: dismiss.callAsFunction)
                .accessibilityIdentifier("close-task-editor")

                Spacer(minLength: 0)

                sheetLayoutControl
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator.opacity(0.75))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("任务详情标题栏")
        .accessibilityIdentifier("task-panel-titlebar")
    }

    private var titlebarDragSurface: some View {
#if canImport(AppKit)
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
#else
        Color.clear
#endif
    }

    private var compactSheetContent: some View {
        ScrollView {
            GlassEffectContainer(spacing: 14) {
                compactSheetFields
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
            }
        }
    }

    private var compactSheetFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            fieldGroup("任务名称") {
                titleField
            }
            .padding(14)
            .kshiftGlassCard(tint: Color.accentColor.opacity(0.08))

            descriptionWorkspace(paneHeight: markdownPaneHeight)

            HStack(alignment: .top, spacing: 16) {
                priorityStrip
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusStrip
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .kshiftGlassCard()

            compactMetadataFields
                .padding(14)
                .kshiftGlassCard(tint: Color.blue.opacity(0.06))

            fieldGroup("标签") {
                TaskTagEditor(tags: $draft.tags, input: $tagInput)
            }
            .padding(14)
            .kshiftGlassCard(tint: Color.orange.opacity(0.07))

            editorStatusMessages

            if draft.taskID != nil, let recentHistoryText {
                fieldGroup("最近历史") {
                    Text(recentHistoryText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityIdentifier("task-detail-history-summary")
                }
                .padding(14)
                .kshiftGlassCard()
            }
        }
    }

    private func descriptionWorkspace(paneHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("描述")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Picker("Markdown 显示模式", selection: $markdownMode) {
                    ForEach(MarkdownViewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 148)
                .accessibilityLabel("Markdown 显示模式")
                .accessibilityIdentifier("markdown-mode")
            }

            MarkdownFormattingToolbar(text: $draft.notes, mode: $markdownMode)

            MarkdownEditorView(
                text: $draft.notes,
                mode: markdownMode,
                paneHeight: paneHeight
            )
        }
        .padding(12)
        .kshiftGlassCard(tint: Color.accentColor.opacity(0.07))
    }

    private var priorityStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("优先级")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(orderedPriorities, id: \.self) { priority in
                    let isSelected = draft.priority == priority
                    Button {
                        draft.priority = priority
                    } label: {
                        Text(priority.code)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isSelected ? selectedPriorityForeground : priority.tint)
                            .frame(maxWidth: .infinity, minHeight: metadataControlHeight)
                            .background(
                                isSelected ? priority.tint : Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(priority.code) \(priority.title)")
                    .accessibilityValue(isSelected ? "已选择" : "未选择")
                }
            }
            .padding(3)
        }
    }

    private var statusStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("状态")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(TaskStatus.allCases) { status in
                    let isSelected = draft.status == status
                    Button {
                        draft.status = status
                    } label: {
                        Text(status.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white : status.tint)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: metadataControlHeight)
                            .background(
                                isSelected ? status.tint : Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(status.title)
                    .accessibilityValue(isSelected ? "已选择" : "未选择")
                }
            }
            .padding(3)
        }
    }

    @ViewBuilder
    private var compactMetadataFields: some View {
        if isCompactWidth {
            VStack(spacing: 14) {
                assigneeField
                HStack(alignment: .top, spacing: 14) {
                    startDateField
                    dueDateField
                }
                durationField
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                assigneeField
                    .frame(maxWidth: .infinity, alignment: .leading)
                startDateField
                    .frame(maxWidth: .infinity, alignment: .leading)
                dueDateField
                    .frame(maxWidth: .infinity, alignment: .leading)
                durationField
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var durationField: some View {
        fieldGroup("工时（天）") {
            TextField(
                "工时",
                value: Binding(
                    get: { durationDays },
                    set: { updateDurationDays($0) }
                ),
                format: .number
            )
            .textFieldStyle(.plain)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: metadataControlHeight, alignment: .leading)
            .background(
                .primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            }
            .accessibilityLabel("工时天数")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailSheetContent: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                descriptionWorkspace(paneHeight: isCompactWidth ? 340 : 380)
                editorStatusMessages
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var editorStatusMessages: some View {
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

    private var sheetFooter: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if currentTask != nil {
                    Button {
                        isShowingHistory = true
                    } label: {
                        Label("历史", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(KshiftCompactGlassButtonStyle())
                    .accessibilityIdentifier("task-history-button")

                    Button {
                        duplicateTask()
                    } label: {
                        if isDuplicating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("复制", systemImage: "square.on.square")
                        }
                    }
                    .buttonStyle(KshiftCompactGlassButtonStyle())
                    .disabled(isSaving || isDuplicating)
                    .accessibilityIdentifier("duplicate-task")

                    Button(role: .destructive) {
                        deleteCurrentTask()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .buttonStyle(.glass)
                    .tint(.red)
                    .disabled(isSaving || isDuplicating)
                    .accessibilityIdentifier("delete-task")
                }

                Spacer()

                Button("取消") { dismiss() }
                    .buttonStyle(KshiftCompactGlassButtonStyle())
                    .disabled(isSaving)
                    .accessibilityIdentifier("cancel-task-editor")

                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("保存")
                    }
                }
                .buttonStyle(KshiftCompactAccentGlassButtonStyle())
                .disabled(isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("save-task")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator.opacity(0.7))
                .frame(height: 0.5)
        }
    }

    private var taskHistoryPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("任务历史")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button("关闭") { isShowingHistory = false }
                    .buttonStyle(.bordered)
            }

            Divider()

            if let currentTask, !currentTask.history.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(currentTask.history.reversed())) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.summary)
                                    .font(.callout.weight(.medium))
                                Text("\(model.actorName(for: entry.actorID)) · revision \(entry.revision)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(model.displayTimestamp(entry.occurredAt))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("task-history-\(entry.id)")

                            if entry.id != currentTask.history.first?.id {
                                Divider()
                            }
                        }
                    }
                }
            } else {
                Text("暂无历史记录")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 380, maxWidth: 380, minHeight: 220, maxHeight: 420)
    }

    private var currentTask: TaskItem? {
        model.task(withID: draft.taskID)
    }

    private var recentHistoryText: String? {
        guard let entry = currentTask?.history.last else { return nil }
        return "\(entry.summary) · \(model.actorName(for: entry.actorID))"
    }

    private var metadataControlHeight: CGFloat {
        isCompactWidth ? 44 : 34
    }

    private var orderedPriorities: [TaskPriority] {
        [.urgent, .high, .medium, .low]
    }

    private var selectedPriorityForeground: Color {
        draft.priority == .high ? .black : .white
    }

    private var durationDays: Int {
        let start = draft.startDate ?? draft.dueDate
        return max(
            KshiftDate.daysBetween(
                from: start,
                through: draft.dueDate,
                calendar: model.projectCalendar
            ) + 1,
            1
        )
    }

    private func updateDurationDays(_ value: Int) {
        let nextValue = max(value, 1)
        let start = draft.startDate ?? draft.dueDate
        draft.startDate = start
        draft.dueDate = KshiftDate.addingDays(
            nextValue - 1,
            to: start,
            calendar: model.projectCalendar
        )
    }

    private func deleteCurrentTask() {
        guard let currentTask else { return }
        model.requestDelete(currentTask)
        dismiss()
    }

    private func duplicateTask() {
        guard draft.taskID != nil else { return }
        let copy = TaskDraft(
            projectID: draft.projectID,
            title: "\(draft.title) 副本",
            notes: draft.notes,
            status: draft.status,
            priority: draft.priority,
            assigneeIDs: draft.assigneeIDs,
            startDate: draft.startDate,
            dueDate: draft.dueDate,
            tags: draft.tags,
            position: draft.position
        )
        isDuplicating = true
        Swift.Task {
            let saved = await model.saveTask(copy)
            isDuplicating = false
            if saved {
                dismiss()
            }
        }
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
        VStack(spacing: 0) {
            classicTitlebar

            Group {
                if layoutMode == .compact {
                    compactSheetContent
                } else {
                    detailSheetContent
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: layoutMode)

            Divider()
            sheetFooter
        }
        .frame(
            width: isCompactWidth ? nil : 800,
            height: isCompactWidth ? nil : 720
        )
        .background {
            sheetBackdrop
        }
        .presentationBackground(.clear)
        .interactiveDismissDisabled(isSaving)
        .popover(isPresented: $isShowingHistory, arrowEdge: .bottom) {
            taskHistoryPopover
        }
    }

    private var titleText: String {
        draft.isNew ? "新建任务" : "修改任务"
    }

    @ViewBuilder
    private var sheetBackdrop: some View {
        ZStack {
            if reduceTransparency {
                Rectangle()
                    .fill(.background)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)

                RadialGradient(
                    colors: [
                        Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.16),
                        .clear,
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 500
                )

                RadialGradient(
                    colors: [
                        Color.orange.opacity(colorScheme == .dark ? 0.12 : 0.08),
                        .clear,
                    ],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 440
                )
            }
        }
        .ignoresSafeArea()
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

private struct MarkdownFormattingToolbar: View {
    @Binding var text: String
    @Binding var mode: MarkdownViewMode

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    formatButton("粗体", symbol: "bold") {
                        insert("**", suffix: "**")
                    }
                    formatButton("斜体", symbol: "italic") {
                        insert("*", suffix: "*")
                    }
                    formatButton("下划线", symbol: "underline") {
                        insert("<u>", suffix: "</u>")
                    }
                    formatButton("删除线", symbol: "strikethrough") {
                        insert("~~", suffix: "~~")
                    }
                    formatButton("行内代码", symbol: "chevron.left.forwardslash.chevron.right") {
                        insert("`", suffix: "`")
                    }
                    formatButton("标题", symbol: "textformat.size.larger") {
                        insertBlock("## 标题")
                    }
                    formatButton("无序列表", symbol: "list.bullet") {
                        insertBlock("- 项目")
                    }
                    formatButton("有序列表", symbol: "list.number") {
                        insertBlock("1. 项目")
                    }
                    formatButton("引用", symbol: "quote.opening") {
                        insertBlock("> 引用")
                    }
                    formatButton("链接", symbol: "link") {
                        insert("[标题](https://)")
                    }
                    formatButton("图片", symbol: "photo") {
                        insertBlock("![图片](https://)")
                    }
                }
            }

            Spacer(minLength: 8)

            Text("\(text.count) 字符")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            .primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func formatButton(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.callout.weight(.medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
    }

    private func insert(_ prefix: String, suffix: String = "") {
        mode = .source
        text += "\(prefix)文本\(suffix)"
    }

    private func insertBlock(_ value: String) {
        mode = .source
        if !text.isEmpty, !text.hasSuffix("\n") {
            text += "\n"
        }
        text += value
    }
}

private struct ClassicTitlebarCloseButton: View {
    let action: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isHovered = false

    private var targetSize: CGFloat {
        horizontalSizeClass == .compact ? 44 : 28
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)

                if isHovered {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.black.opacity(0.62))
                        .transition(.opacity)
                }
            }
            .frame(width: targetSize, height: targetSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("关闭")
        .onHover { hovered in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovered
            }
        }
        .accessibilityLabel("关闭")
        .accessibilityHint("关闭任务详情面板")
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
