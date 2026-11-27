import KshiftPresentation
import SwiftUI

@MainActor
public struct KshiftPlanDepthFeatureView: View {
    @State private var model: KshiftPlanDepthFeatureModel
    @State private var selectedTask: KshiftPlanTaskPresentation?
    @State private var showsAssigneeFilter = false
    @State private var showsStatusFilter = false
    @State private var rescheduleTaskID: UUID?
    @State private var rescheduleStartsOn = Date()
    @State private var rescheduleDueOn = Date()
    @State private var rescheduleReason = ""
    @State private var rescheduleError: String?
    private let capabilities: any KshiftPlatformCapabilities

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(
        capabilities: any KshiftPlatformCapabilities,
        boundary: any KshiftPlanDepthBoundary,
        projectID: UUID,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        let model = KshiftPlanDepthFeatureModel(
            boundary: boundary,
            capabilities: capabilities,
            projectID: projectID,
            locale: locale,
            timeZone: timeZone
        )
        _model = State(initialValue: model)
        self.capabilities = capabilities
    }

    public init(
        capabilities: any KshiftPlatformCapabilities,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        self.init(
            capabilities: capabilities,
            boundary: KshiftPlanSampleData.makeBoundary(),
            projectID: KshiftPlanSampleData.projectID,
            locale: locale,
            timeZone: timeZone
        )
    }

    public init(
        model: KshiftPlanDepthFeatureModel,
        capabilities: any KshiftPlatformCapabilities
    ) {
        _model = State(initialValue: model)
        self.capabilities = capabilities
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    modePicker
                    filterBar
                    errorBanner
                    modeContent
                }
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 1_120)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("plan-depth-content-scroll")
            .kshiftScreenBackground()
            .navigationTitle("计划深度")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("close-plan-depth")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.load() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.phase == .loading)
                }
            }
        }
        .frame(
            minWidth: horizontalSizeClass == .compact ? nil : 860,
            minHeight: horizontalSizeClass == .compact ? nil : 700
        )
        .task {
            await model.loadIfNeeded()
        }
        .sheet(item: $selectedTask) { task in
            taskDetail(task)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "选择负责人",
            isPresented: $showsAssigneeFilter,
            titleVisibility: .visible
        ) {
            Button("全部负责人") {
                model.filter = KshiftPlanDepthFilter(
                    searchText: model.filter.searchText,
                    status: model.filter.status
                )
            }
            ForEach(model.snapshot?.people ?? []) { person in
                Button(person.name) {
                    model.filter = KshiftPlanDepthFilter(
                        searchText: model.filter.searchText,
                        assigneeID: person.id,
                        status: model.filter.status
                    )
                }
            }
        }
        .confirmationDialog(
            "选择状态",
            isPresented: $showsStatusFilter,
            titleVisibility: .visible
        ) {
            Button("全部状态") {
                model.filter = KshiftPlanDepthFilter(
                    searchText: model.filter.searchText,
                    assigneeID: model.filter.assigneeID
                )
            }
            ForEach(KshiftPlanTaskStatus.allCases, id: \.self) { status in
                Button(status.title) {
                    model.filter = KshiftPlanDepthFilter(
                        searchText: model.filter.searchText,
                        assigneeID: model.filter.assigneeID,
                        status: status
                    )
                }
            }
        }
        .alert(
            "确认回退",
            isPresented: Binding(
                get: { model.rollbackCandidate != nil },
                set: { if !$0 { model.cancelRollback() } }
            )
        ) {
            Button("取消", role: .cancel) { model.cancelRollback() }
            Button("回退", role: .destructive) {
                Task { await model.confirmRollback() }
            }
        } message: {
            Text("回退会创建新版本和审计记录。已有历史不会删除。")
        }
    }

    @ViewBuilder
    private var header: some View {
        if let presentation = model.presentation {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(presentation.projectTitle)
                        .font(.title.bold())
                    Spacer(minLength: 8)
                    Text(presentation.revisionLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                }
                Text(presentation.progressLabel)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.8))
                ProgressView(value: presentation.progressFraction)
                    .tint(.accentColor)
                    .accessibilityHidden(true)
            }
            .padding(18)
            .contentSurface(cornerRadius: 18)
        } else {
            ProgressView("正在读取计划深度")
                .frame(maxWidth: .infinity, minHeight: 180)
        }
    }

    private var modePicker: some View {
        Picker("计划视图", selection: $model.selectedMode) {
            ForEach(KshiftPlanDepthViewMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("计划深度视图")
    }

    @ViewBuilder
    private var filterBar: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                searchField
                HStack(spacing: 12) {
                    assigneeFilterButton
                    statusFilterButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 12) {
                searchField
                    .frame(maxWidth: 360)
                assigneeFilterButton
                statusFilterButton
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var searchField: some View {
        TextField(
            "搜索任务",
            text: Binding(
                get: { model.filter.searchText },
                set: { value in
                    model.filter = KshiftPlanDepthFilter(
                        searchText: value,
                        assigneeID: model.filter.assigneeID,
                        status: model.filter.status
                    )
                }
            )
        )
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity)
    }

    private var assigneeFilterButton: some View {
        Button {
            showsAssigneeFilter = true
        } label: {
            Label("负责人", systemImage: "person.2")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("选择负责人筛选条件")
    }

    private var statusFilterButton: some View {
        Button {
            showsStatusFilter = true
        } label: {
            Label("状态", systemImage: "line.3.horizontal.decrease.circle")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("选择任务状态筛选条件")
    }

    @ViewBuilder
    private var errorBanner: some View {
        if case let .failed(message) = model.phase {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.kshift(.danger))
                Text(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("关闭") { model.dismissError() }
                    .buttonStyle(.borderless)
            }
            .padding(14)
            .contentSurface(cornerRadius: 14)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        if let presentation = model.presentation {
            switch model.selectedMode {
            case .board:
                board(presentation)
            case .gantt:
                gantt(presentation)
            case .history:
                history(presentation)
            case .report:
                report
            }
        } else if case .failed = model.phase {
            ContentUnavailableView(
                "无法显示计划深度",
                systemImage: "exclamationmark.triangle",
                description: Text("请检查内网连接后重试。")
            )
            .frame(minHeight: 260)
        }
    }

    private func board(_ presentation: KshiftPlanDepthPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(presentation.columns) { column in
                        boardColumn(column)
                            .frame(width: dynamicTypeSize.isAccessibilitySize ? 320 : 280)
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.visible)

            if presentation.hiddenTaskCount > 0 {
                Text("还有 \(presentation.hiddenTaskCount) 项任务。请使用搜索或筛选缩小范围。")
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.8))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilitySummary)
    }

    private func boardColumn(_ column: KshiftPlanBoardColumn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(column.title)
                    .font(.headline)
                Spacer()
                Text("\(column.totalCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.8))
            }

            if column.tasks.isEmpty {
                Text("此列没有任务")
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .contentSurface(cornerRadius: 14)
            } else {
                KshiftGlassGroup(spacing: 10) {
                    ForEach(column.tasks) { task in
                        KshiftInteractiveGlassCard {
                            selectedTask = task
                        } content: {
                            taskCard(task)
                        }
                        .disabled(model.pendingTaskID != nil)
                    }
                }
            }
        }
        .padding(12)
        .contentSurface(cornerRadius: 18)
    }

    private func taskCard(_ task: KshiftPlanTaskPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(Color.kshift(task.isCompleted ? .success : .accent))
                    .accessibilityHidden(true)
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.isCompleted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.pendingTaskID == task.id {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            HStack(spacing: 6) {
                KshiftSemanticBadge(task.status.title, role: statusRole(task.status))
                KshiftSemanticBadge("P\(task.priority.title)", role: priorityRole(task.priority))
            }
            Text(task.scheduleLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary.opacity(0.8))
            HStack(spacing: 10) {
                Label(task.assigneeName, systemImage: "person")
                Label("\(task.dependencyCount)", systemImage: "arrow.triangle.branch")
                Label("\(task.attachmentCount)", systemImage: "paperclip")
                if task.isCrossDay {
                    Label("跨日", systemImage: "calendar.badge.clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.8))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(task.accessibilityLabel)
        .accessibilityHint(task.accessibilityHint)
    }

    private func gantt(_ presentation: KshiftPlanDepthPresentation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("跨日排期")
                    .font(.headline)
                Spacer()
                Text("\(presentation.gantt.startDateLabel) – \(presentation.gantt.endDateLabel)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.8))
            }

            if presentation.gantt.rows.isEmpty {
                Text("没有可显示的任务")
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if horizontalSizeClass == .compact {
                VStack(spacing: 1) {
                    ganttRows(presentation.gantt.rows, compact: true)
                }
            } else {
                ScrollView(.horizontal) {
                    VStack(spacing: 1) {
                        ganttRows(presentation.gantt.rows, compact: false)
                    }
                    .frame(minWidth: 760)
                }
                .accessibilityIdentifier("plan-depth-gantt-scroll")
            }
        }
        .padding(18)
        .contentSurface(cornerRadius: 18)
    }

    private func ganttRows(_ rows: [KshiftGanttRow], compact: Bool) -> some View {
        ForEach(rows) { row in
            Button {
                selectedTask = row.taskPresentation
            } label: {
                ganttRow(row, compact: compact)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }

    private func ganttRow(_ row: KshiftGanttRow, compact: Bool) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    ganttHeader(row)
                    ganttTimeline(row)
                }
            } else {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        ganttTitle(row)
                    }
                    .frame(width: 210, alignment: .leading)

                    ganttTimeline(row)

                    ganttStatus(row)
                        .frame(width: 92, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(row.delayLabel ?? "")
        .accessibilityIdentifier("plan-depth-gantt-task-\(row.id.uuidString.lowercased())")
    }

    private func ganttHeader(_ row: KshiftGanttRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ganttTitle(row)
                .frame(maxWidth: .infinity, alignment: .leading)
            ganttStatus(row)
        }
    }

    private func ganttTitle(_ row: KshiftGanttRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(row.assigneeName)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.8))
            if row.rescheduleCount > 0 {
                Text("改期 \(row.rescheduleCount) 次")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ganttStatus(_ row: KshiftGanttRow) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(row.status.title)
                .font(.caption.weight(.semibold))
            if let delayLabel = row.delayLabel {
                Text(delayLabel)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Color.kshift(.warning).opacity(0.16),
                        in: Capsule(style: .continuous)
                    )
                    .foregroundStyle(.primary)
            }
            if row.dependencyCount > 0 {
                Label("\(row.dependencyCount)", systemImage: "arrow.triangle.branch")
                    .font(.caption2)
            }
        }
    }

    private func ganttTimeline(_ row: KshiftGanttRow) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let baselineX = width * row.baselineStartFraction
            let baselineWidth = min(
                width - baselineX,
                max(18, width * row.baselineWidthFraction)
            )
            let currentX = width * row.startFraction
            let currentWidth = min(
                width - currentX,
                max(28, width * row.widthFraction)
            )
            let baselineEndX = min(width, baselineX + baselineWidth)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.055))

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.kshift(statusRole(row.status)).gradient)
                    .frame(width: currentWidth)
                    .offset(x: currentX)

                if row.hasDelay {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.02))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    Color.primary.opacity(0.58),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                                )
                        }
                        .frame(width: baselineWidth)
                        .offset(x: baselineX)
                }

                if let start = row.extensionStartFraction,
                   let extensionWidth = row.extensionWidthFraction {
                    DelayStripeOverlay()
                        .frame(
                            width: max(0, width * extensionWidth),
                            height: 30
                        )
                        .offset(x: width * start)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                }

                if row.hasDelay {
                    Rectangle()
                        .fill(Color.kshift(.warning))
                        .frame(width: 2, height: 38)
                        .offset(x: max(0, min(width - 2, baselineEndX - 1)))
                        .accessibilityHidden(true)
                }

                if let start = row.connectorStartFraction,
                   let end = row.connectorEndFraction {
                    DelayConnectorShape(
                        startX: width * start,
                        endX: width * end
                    )
                    .stroke(
                        Color.kshift(.warning),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
                    .accessibilityHidden(true)
                }

                Text(row.dateLabel)
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .offset(x: currentX + 4)
                    .foregroundStyle(.primary)
            }
        }
        .frame(height: 38)
    }

    private func history(_ presentation: KshiftPlanDepthPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("审计与回退")
                .font(.headline)
            ForEach(presentation.history) { entry in
                historyRow(entry, currentRevision: model.snapshot?.revision ?? 0)
            }
        }
        .padding(18)
        .contentSurface(cornerRadius: 18)
    }

    private func historyRow(_ entry: KshiftHistoryRow, currentRevision: UInt64) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(entry.revisionLabel)
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.actorName) · \(entry.actionLabel)")
                    .font(.subheadline.weight(.semibold))
                Text(entry.summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.8))
                HStack(spacing: 10) {
                    Text(entry.timeLabel)
                    if let restored = entry.restoredFromLabel {
                        Text(restored)
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary.opacity(0.75))
            }
            Spacer(minLength: 8)
            if entry.canRollback, entry.revision < currentRevision {
                Button("回退") {
                    model.requestRollback(to: entry.revision)
                }
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .accessibilityHint("创建新版本，并恢复 r\(entry.revision) 的任务内容")
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.accessibilityLabel)
    }

    @ViewBuilder
    private var report: some View {
        VStack(alignment: .leading, spacing: 16) {
            reportControls

            if let report = model.reportPresentation {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(report.sourceRevisionLabel)
                            .font(.title3.bold().monospacedDigit())
                        Spacer()
                        Text(report.rangeLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                    Text(report.summaryLabel)
                    Divider()
                    VStack(spacing: 8) {
                        ForEach(report.rows) { row in
                            reportRow(row)
                        }
                    }
                    reportExportControls
                    if let exportStatus = model.exportStatus {
                        Text(exportStatus)
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                }
                .padding(18)
                .contentSurface(cornerRadius: 18)
            } else {
                ContentUnavailableView(
                    "尚未生成报告",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("打印和图片导出会使用同一个报告版本。")
                )
                .frame(minHeight: 220)
                .contentSurface(cornerRadius: 18)
            }
        }
        .padding(18)
        .contentSurface(cornerRadius: 18)
    }

    @ViewBuilder
    private var reportControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                reportStartPicker
                reportEndPicker
                reportGenerateButton
            }
        } else {
            HStack(spacing: 12) {
                reportStartPicker
                reportEndPicker
                reportGenerateButton
            }
        }
    }

    private var reportStartPicker: some View {
        DatePicker(
            "开始",
            selection: Binding(
                get: { model.reportRange.startsOn },
                set: {
                    model.reportRange = KshiftReportRange(
                        startsOn: $0,
                        endsOn: model.reportRange.endsOn
                    )
                }
            ),
            displayedComponents: .date
        )
    }

    private var reportEndPicker: some View {
        DatePicker(
            "结束",
            selection: Binding(
                get: { model.reportRange.endsOn },
                set: {
                    model.reportRange = KshiftReportRange(
                        startsOn: model.reportRange.startsOn,
                        endsOn: $0
                    )
                }
            ),
            displayedComponents: .date
        )
    }

    private var reportGenerateButton: some View {
        KshiftPrimaryGlassButton {
            Task { await model.makeReport() }
        } label: {
            Label(model.isReporting ? "生成中" : "生成报告", systemImage: "doc.text.magnifyingglass")
        }
        .disabled(model.isReporting)
    }

    @ViewBuilder
    private var reportExportControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                reportPrintButton
                reportImageButton
            }
        } else {
            HStack(spacing: 12) {
                reportPrintButton
                reportImageButton
            }
        }
    }

    private var reportPrintButton: some View {
        KshiftSecondaryGlassButton {
            Task { await model.printReport() }
        } label: {
            Label("打印", systemImage: "printer")
        }
    }

    private var reportImageButton: some View {
        KshiftSecondaryGlassButton {
            Task { await model.exportReportImage() }
        } label: {
            Label("导出图片", systemImage: "photo")
        }
    }

    private func reportRow(_ row: KshiftReportRowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                KshiftSemanticBadge(row.status.title, role: statusRole(row.status))
                Text(row.risk)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 5) {
                reportMetadata(row)
            }
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.8))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    @ViewBuilder
    private func reportMetadata(_ row: KshiftReportRowPresentation) -> some View {
        Label(row.assignee, systemImage: "person")
        Label(row.schedule, systemImage: "calendar")
        Label(row.estimate, systemImage: "clock")
    }

    private func taskDetail(_ task: KshiftPlanTaskPresentation) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        KshiftSemanticBadge(task.status.title, role: statusRole(task.status))
                        KshiftSemanticBadge("优先级 \(task.priority.title)", role: priorityRole(task.priority))
                    }
                    detailRow("负责人", task.assigneeName, systemImage: "person")
                    detailRow("当前排期", task.scheduleLabel, systemImage: "calendar")
                    if let baseline = task.baselineScheduleLabel {
                        detailRow("原始排期", baseline, systemImage: "clock.arrow.circlepath")
                    }
                    if task.delayDays > 0 {
                        detailRow(
                            "累计延期",
                            "延期 \(task.delayDays) 天" + (task.latestRescheduleWasOverdue ? " · 逾期后改期" : ""),
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                    if let reason = task.latestRescheduleReason {
                        detailRow("最近改期原因", reason, systemImage: "text.bubble")
                    }
                    detailRow("依赖 / 子任务", "\(task.dependencyCount) / \(task.subtaskCount)", systemImage: "arrow.triangle.branch")
                    if !task.reschedules.isEmpty {
                        DisclosureGroup("改期历史 \(task.reschedules.count) 次") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(task.reschedules.reversed()) { entry in
                                    rescheduleRow(entry)
                                }
                            }
                            .padding(.top, 8)
                        }
                        .font(.subheadline)
                    }
                    if model.viewerRole.canWrite {
                        if rescheduleTaskID == task.id {
                            rescheduleEditor(task)
                        } else {
                            KshiftSecondaryGlassButton {
                                beginReschedule(task)
                            } label: {
                                Label("修改排期", systemImage: "calendar.badge.clock")
                            }
                            .accessibilityIdentifier(
                                "plan-depth-reschedule-\(task.id.uuidString.lowercased())"
                            )
                        }
                    }
                    Divider()
                    markdown(task.markdown)
                    if let snapshot = model.snapshot {
                        let attachments = snapshot.attachments.filter {
                            snapshot.attachmentIDs(for: task.id).contains($0.id)
                        }
                        if !attachments.isEmpty {
                            Divider()
                            Text("附件")
                                .font(.headline)
                            ForEach(attachments) { attachment in
                                Label(
                                    "\(attachment.filename) · \(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteSize), countStyle: .file))",
                                    systemImage: "paperclip"
                                )
                                .font(.subheadline)
                            }
                        }
                    }
                    KshiftPrimaryGlassButton {
                        Task {
                            await model.toggle(task)
                            selectedTask = nil
                        }
                    } label: {
                        Label(task.isCompleted ? "重新打开" : "标记完成", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                    }
                }
                .padding(20)
            }
            .kshiftScreenBackground()
            .navigationTitle("任务详情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { selectedTask = nil }
                }
            }
        }
    }

    private func rescheduleRow(_ entry: KshiftReschedulePresentation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(entry.revisionLabel)
                    .font(.caption.monospacedDigit().weight(.semibold))
                Text(entry.delayLabel)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(entry.timeLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("\(entry.previousScheduleLabel) → \(entry.newScheduleLabel)")
                .font(.caption.monospacedDigit())
            Text("\(entry.timingLabel) · \(entry.actorName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.reason)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityLabel)
    }

    private func beginReschedule(_ task: KshiftPlanTaskPresentation) {
        guard let source = model.snapshot?.tasks.first(where: { $0.id == task.id }) else {
            return
        }
        rescheduleStartsOn = source.startsOn
        rescheduleDueOn = source.dueOn
        rescheduleReason = ""
        rescheduleError = nil
        rescheduleTaskID = task.id
    }

    private func rescheduleEditor(_ task: KshiftPlanTaskPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("修改排期")
                .font(.headline)
            DatePicker("开始日期", selection: $rescheduleStartsOn, displayedComponents: .date)
                .onChange(of: rescheduleStartsOn) { _, newValue in
                    if rescheduleDueOn < newValue {
                        rescheduleDueOn = newValue
                    }
                }
            DatePicker("截止日期", selection: $rescheduleDueOn, displayedComponents: .date)
            TextField("改期原因", text: $rescheduleReason, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            if rescheduleDueOn < rescheduleStartsOn {
                Text("开始日期不能晚于截止日期。")
                    .font(.caption)
                    .foregroundStyle(Color.kshift(.danger))
            }
            if let rescheduleError {
                Text(rescheduleError)
                    .font(.caption)
                    .foregroundStyle(Color.kshift(.danger))
            }
            HStack {
                Button("取消") {
                    rescheduleTaskID = nil
                    rescheduleError = nil
                }
                Spacer()
                KshiftPrimaryGlassButton {
                    Task {
                        let succeeded = await model.reschedule(
                            taskID: task.id,
                            startsOn: rescheduleStartsOn,
                            dueOn: rescheduleDueOn,
                            reason: rescheduleReason
                        )
                        if succeeded {
                            rescheduleTaskID = nil
                            rescheduleError = nil
                            selectedTask = nil
                        } else {
                            rescheduleError = "改期保存失败，请检查日期、原因或刷新后重试。"
                        }
                    }
                } label: {
                    Label("保存改期", systemImage: "checkmark")
                }
                .accessibilityIdentifier("plan-depth-save-reschedule")
                .disabled(
                    model.pendingTaskID != nil
                        || rescheduleDueOn < rescheduleStartsOn
                        || rescheduleReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func markdown(_ source: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(source)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailRow(_ title: String, _ value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.primary.opacity(0.8))
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func statusRole(_ status: KshiftPlanTaskStatus) -> KshiftSemanticRole {
        switch status {
        case .todo: .neutral
        case .inProgress: .accent
        case .blocked: .danger
        case .done: .success
        }
    }

    private func priorityRole(_ priority: KshiftPlanPriority) -> KshiftSemanticRole {
        switch priority {
        case .low: .secondary
        case .medium: .warning
        case .high: .danger
        case .urgent: .danger
        }
    }
}

private struct DelayStripeOverlay: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 7
            }
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color.kshift(.warning).opacity(0.12))
            )
            context.stroke(
                path,
                with: .color(Color.kshift(.warning).opacity(0.7)),
                lineWidth: 1
            )
        }
    }
}

private struct DelayConnectorShape: Shape {
    let startX: CGFloat
    let endX: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        let tipX = max(startX, endX - 6)
        path.move(to: CGPoint(x: startX, y: y))
        path.addLine(to: CGPoint(x: tipX, y: y))
        path.move(to: CGPoint(x: tipX, y: y - 5))
        path.addLine(to: CGPoint(x: endX, y: y))
        path.addLine(to: CGPoint(x: tipX, y: y + 5))
        return path
    }
}

private extension View {
    func contentSurface(cornerRadius: CGFloat) -> some View {
        background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}
