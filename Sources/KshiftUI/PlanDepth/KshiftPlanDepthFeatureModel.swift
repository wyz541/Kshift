import Foundation
import KshiftPresentation
import Observation

public enum KshiftPlanDepthPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor
@Observable
public final class KshiftPlanDepthFeatureModel {
    public private(set) var phase: KshiftPlanDepthPhase = .idle
    public private(set) var snapshot: KshiftPlanDepthSnapshot?
    public private(set) var presentation: KshiftPlanDepthPresentation?
    public private(set) var report: KshiftWorkReport?
    public private(set) var reportPresentation: KshiftReportPresentation?
    public private(set) var pendingTaskID: UUID?
    public private(set) var isReporting = false
    public private(set) var exportStatus: String?
    public var selectedMode: KshiftPlanDepthViewMode = .board
    public var filter = KshiftPlanDepthFilter() {
        didSet { rebuildPresentation() }
    }
    public var reportRange: KshiftReportRange {
        didSet { report = nil; reportPresentation = nil; exportStatus = nil }
    }
    public var rollbackCandidate: KshiftPlanHistoryEntry?

    public private(set) var viewerRole: KshiftPlanRole

    @ObservationIgnored private let boundary: any KshiftPlanDepthBoundary
    @ObservationIgnored private let capabilities: any KshiftPlatformCapabilities
    @ObservationIgnored private let projectID: UUID
    @ObservationIgnored private let mapper: KshiftPlanDepthPresentationMapper

    public init(
        boundary: any KshiftPlanDepthBoundary,
        capabilities: any KshiftPlatformCapabilities,
        projectID: UUID = KshiftPlanSampleData.projectID,
        viewerRole: KshiftPlanRole = .admin,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        self.boundary = boundary
        self.capabilities = capabilities
        self.projectID = projectID
        self.viewerRole = viewerRole
        mapper = KshiftPlanDepthPresentationMapper(locale: locale, timeZone: timeZone)

        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        reportRange = KshiftReportRange(
            startsOn: calendar.date(byAdding: .day, value: -3, to: today)!,
            endsOn: calendar.date(byAdding: .day, value: 7, to: today)!
        )
    }

    public func loadIfNeeded() async {
        guard phase == .idle || isFailure else { return }
        await load()
    }

    public func load() async {
        phase = .loading
        exportStatus = nil
        do {
            let session = try await boundary.fetchPlanDepth(projectID: projectID)
            viewerRole = session.viewerRole
            apply(session.snapshot)
            phase = .loaded
        } catch {
            phase = .failed(errorMessage(error))
        }
    }

    public func toggle(_ task: KshiftPlanTaskPresentation) async {
        guard pendingTaskID == nil, let snapshot else { return }
        let nextStatus: KshiftPlanTaskStatus = task.isCompleted ? .todo : .done
        pendingTaskID = task.id
        defer { pendingTaskID = nil }
        do {
            let updated = try await boundary.execute(
                projectID: projectID,
                .setTaskStatus(
                    taskID: task.id,
                    status: nextStatus,
                    expectedTaskVersion: currentTaskVersion(id: task.id) ?? 1,
                    expectedRevision: snapshot.revision
                )
            )
            apply(updated)
            phase = .loaded
            capabilities.perform(nextStatus == .done ? .success : .selection)
        } catch {
            phase = .failed(errorMessage(error))
            capabilities.perform(.error)
        }
    }

    public func requestRollback(to revision: UInt64) {
        guard viewerRole.canRollback else { return }
        rollbackCandidate = snapshot?.history.first(where: { $0.revision == revision })
    }

    public func confirmRollback() async {
        guard let candidate = rollbackCandidate, let snapshot else { return }
        rollbackCandidate = nil
        do {
            let updated = try await boundary.execute(
                projectID: projectID,
                .rollback(
                    targetRevision: candidate.revision,
                    reason: "恢复版本 r\(candidate.revision)",
                    expectedRevision: snapshot.revision
                )
            )
            apply(updated)
            phase = .loaded
            capabilities.perform(.success)
        } catch {
            phase = .failed(errorMessage(error))
            capabilities.perform(.error)
        }
    }

    public func cancelRollback() {
        rollbackCandidate = nil
    }

    public func makeReport() async {
        guard !isReporting else { return }
        isReporting = true
        defer { isReporting = false }
        do {
            let report = try await boundary.fetchReport(projectID: projectID, range: reportRange)
            self.report = report
            reportPresentation = mapper.makeReportPresentation(report)
            exportStatus = nil
            phase = .loaded
        } catch {
            phase = .failed(errorMessage(error))
        }
    }

    public func printReport() async {
        guard let reportPresentation else { return }
        let completed = await capabilities.printHTML(reportPresentation.html, jobName: "Kshift 工作报告")
        exportStatus = completed ? "打印面板已关闭。" : "无法打开打印面板。"
    }

    public func exportReportImage() async {
        guard let report else { return }
        guard let data = KshiftReportExporter.renderPNG(report: report) else {
            exportStatus = "无法生成报告图片。"
            return
        }
        let completed = await capabilities.exportImage(
            data,
            suggestedFilename: "kshift-report-r\(report.sourceRevision).png"
        )
        exportStatus = completed ? "报告图片已导出。" : "已取消图片导出。"
    }

    public func dismissError() {
        phase = .loaded
    }

    private var isFailure: Bool {
        if case .failed = phase { true } else { false }
    }

    private func apply(_ snapshot: KshiftPlanDepthSnapshot) {
        self.snapshot = snapshot
        rebuildPresentation()
    }

    private func rebuildPresentation() {
        guard let snapshot else {
            presentation = nil
            return
        }
        presentation = mapper.makePresentation(
            snapshot: snapshot,
            filter: filter,
            viewerRole: viewerRole
        )
    }

    private func currentTaskVersion(id: UUID) -> UInt64? {
        snapshot?.tasks.first(where: { $0.id == id })?.version
    }

    private func errorMessage(_ error: Error) -> String {
        guard let error = error as? KshiftPlanDepthError else {
            return "无法读取计划深度。请稍后重试。"
        }
        switch error {
        case .unavailable:
            return "共享服务不可用。请检查内网连接。"
        case .unauthorized:
            return "当前账号无权执行此操作。"
        case .notFound:
            return "找不到当前项目或任务。"
        case let .revisionConflict(currentRevision):
            return "项目已更新到 r\(currentRevision)。请刷新后重试。"
        case let .versionConflict(currentVersion):
            return "任务已更新到版本 \(currentVersion)。请刷新后重试。"
        case .dependencyCycle:
            return "任务依赖形成循环。请调整依赖。"
        case .rollbackUnavailable:
            return "目标版本不在回退窗口内。"
        case .invalidAttachment:
            return "附件类型或大小不符合规则。"
        case .invalidResponse:
            return "共享服务返回了无法识别的数据。"
        case .released:
            return "客户端已释放。请重新打开页面。"
        }
    }
}
