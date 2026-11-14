import Foundation

public actor InMemoryKshiftPlanDepthBoundary: KshiftPlanDepthBoundary {
    private var snapshot: KshiftPlanDepthSnapshot
    private var states: [UInt64: KshiftPlanDepthSnapshot]
    private let viewerRole: KshiftPlanRole

    public init(
        snapshot: KshiftPlanDepthSnapshot = KshiftPlanSampleData.makeSnapshot(),
        viewerRole: KshiftPlanRole = .admin
    ) {
        self.snapshot = snapshot
        states = [snapshot.revision: snapshot]
        self.viewerRole = viewerRole
    }

    public func fetchPlanDepth(projectID: UUID) async throws -> KshiftPlanDepthSession {
        guard snapshot.projectID == projectID else {
            throw KshiftPlanDepthError.notFound
        }
        return KshiftPlanDepthSession(snapshot: snapshot, viewerRole: viewerRole)
    }

    public func execute(
        projectID: UUID,
        _ command: KshiftPlanDepthCommand
    ) async throws -> KshiftPlanDepthSnapshot {
        guard projectID == snapshot.projectID else {
            throw KshiftPlanDepthError.notFound
        }
        switch command {
        case let .setTaskStatus(taskID, status, expectedTaskVersion, expectedRevision):
            guard expectedRevision == snapshot.revision else {
                throw KshiftPlanDepthError.revisionConflict(currentRevision: snapshot.revision)
            }
            guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
                throw KshiftPlanDepthError.notFound
            }
            let current = snapshot.tasks[index]
            guard current.version == expectedTaskVersion else {
                throw KshiftPlanDepthError.versionConflict(currentVersion: current.version)
            }
            let updated = KshiftPlanTask(
                id: current.id,
                projectID: current.projectID,
                parentID: current.parentID,
                title: current.title,
                descriptionMarkdown: current.descriptionMarkdown,
                status: status,
                priority: current.priority,
                assigneeID: current.assigneeID,
                startsOn: current.startsOn,
                dueOn: current.dueOn,
                estimateMinutes: current.estimateMinutes,
                position: current.position,
                version: current.version + 1,
                completedAt: status == .done ? .now : nil
            )
            var tasks = snapshot.tasks
            tasks[index] = updated
            return commit(tasks: tasks, action: "updated", summary: "更新任务「\(current.title)」")

        case let .rollback(targetRevision, reason, expectedRevision):
            guard expectedRevision == snapshot.revision else {
                throw KshiftPlanDepthError.revisionConflict(currentRevision: snapshot.revision)
            }
            guard let target = states[targetRevision], targetRevision < snapshot.revision else {
                throw KshiftPlanDepthError.rollbackUnavailable
            }
            let history = snapshot.history
            let restored = KshiftPlanDepthSnapshot(
                projectID: target.projectID,
                projectName: target.projectName,
                revision: snapshot.revision + 1,
                people: target.people,
                tasks: target.tasks,
                dependencies: target.dependencies,
                attachments: target.attachments,
                attachmentLinks: target.attachmentLinks,
                history: history
            )
            return commit(
                restored: restored,
                action: "rollback",
                summary: reason,
                restoredFromRevision: targetRevision
            )
        }
    }

    public func fetchReport(projectID: UUID, range: KshiftReportRange) async throws -> KshiftWorkReport {
        guard projectID == snapshot.projectID else {
            throw KshiftPlanDepthError.notFound
        }
        let today = Calendar(identifier: .gregorian).startOfDay(for: .now)
        let people = Dictionary(uniqueKeysWithValues: snapshot.people.map { ($0.id, $0.name) })
        let titles = Dictionary(uniqueKeysWithValues: snapshot.tasks.map { ($0.id, $0.title) })
        let dependencies = Dictionary(grouping: snapshot.dependencies, by: \.taskID)
        let subtasks = Dictionary(grouping: snapshot.tasks.compactMap { task in
            task.parentID.map { ($0, task) }
        }, by: \.0)
        let attachments = Dictionary(grouping: snapshot.attachmentLinks, by: \.taskID)
        let calendar = Calendar(identifier: .gregorian)

        let tasks = snapshot.tasks
            .filter { task in
                let scheduled = task.startsOn <= range.endsOn && task.dueOn >= range.startsOn
                let completed = task.completedAt.map {
                    $0 >= calendar.startOfDay(for: range.startsOn)
                        && $0 < calendar.date(byAdding: .day, value: 1, to: range.endsOn)!
                } ?? false
                return scheduled || completed
            }
            .sorted {
                if $0.startsOn != $1.startsOn { return $0.startsOn < $1.startsOn }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .map { task in
                KshiftReportTask(
                    id: task.id,
                    title: task.title,
                    parentTitle: task.parentID.flatMap { titles[$0] },
                    status: task.status,
                    priority: task.priority,
                    assigneeName: task.assigneeID.flatMap { people[$0] },
                    startsOn: task.startsOn,
                    dueOn: task.dueOn,
                    estimateMinutes: task.estimateMinutes,
                    crossDay: task.isCrossDay,
                    overdue: task.dueOn < today && task.status != .done,
                    dependencyCount: UInt32(dependencies[task.id]?.count ?? 0),
                    subtaskCount: UInt32(subtasks[task.id]?.count ?? 0),
                    attachmentCount: UInt32(attachments[task.id]?.count ?? 0)
                )
            }

        let statistics = KshiftReportStatistics(
            taskCount: UInt32(tasks.count),
            completedCount: UInt32(tasks.filter { $0.status == .done }.count),
            overdueCount: UInt32(tasks.filter(\.overdue).count),
            crossDayCount: UInt32(tasks.filter(\.crossDay).count),
            totalEstimateMinutes: tasks.reduce(0) { $0 + $1.estimateMinutes }
        )
        let html = Self.reportHTML(
            revision: snapshot.revision,
            range: range,
            tasks: tasks,
            statistics: statistics
        )
        return KshiftWorkReport(
            sourceRevision: snapshot.revision,
            generatedAt: .now,
            range: range,
            tasks: tasks,
            statistics: statistics,
            html: html
        )
    }

    private func commit(
        tasks: [KshiftPlanTask],
        action: String,
        summary: String
    ) -> KshiftPlanDepthSnapshot {
        let revision = snapshot.revision + 1
        let history = KshiftPlanHistoryEntry(
            id: UUID(),
            revision: revision,
            actorID: KshiftPlanSampleData.viewerID,
            action: action,
            summary: summary,
            occurredAt: .now,
            contentSHA256: UUID().uuidString.lowercased()
        )
        let next = KshiftPlanDepthSnapshot(
            projectID: snapshot.projectID,
            projectName: snapshot.projectName,
            revision: revision,
            people: snapshot.people,
            tasks: tasks,
            dependencies: snapshot.dependencies,
            attachments: snapshot.attachments,
            attachmentLinks: snapshot.attachmentLinks,
            history: [history] + snapshot.history
        )
        snapshot = next
        states[revision] = next
        return next
    }

    private func commit(
        restored: KshiftPlanDepthSnapshot,
        action: String,
        summary: String,
        restoredFromRevision: UInt64
    ) -> KshiftPlanDepthSnapshot {
        let revision = restored.revision
        let history = KshiftPlanHistoryEntry(
            id: UUID(),
            revision: revision,
            actorID: KshiftPlanSampleData.viewerID,
            action: action,
            summary: summary,
            occurredAt: .now,
            restoredFromRevision: restoredFromRevision,
            contentSHA256: UUID().uuidString.lowercased()
        )
        let next = KshiftPlanDepthSnapshot(
            projectID: restored.projectID,
            projectName: restored.projectName,
            revision: revision,
            people: restored.people,
            tasks: restored.tasks,
            dependencies: restored.dependencies,
            attachments: restored.attachments,
            attachmentLinks: restored.attachmentLinks,
            history: [history] + restored.history
        )
        snapshot = next
        states[revision] = next
        return next
    }

    private static func reportHTML(
        revision: UInt64,
        range: KshiftReportRange,
        tasks: [KshiftReportTask],
        statistics: KshiftReportStatistics
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = tasks.map { task in
            "<tr><td>\(task.title)</td><td>\(task.status.rawValue)</td><td>\(task.assigneeName ?? "未分配")</td><td>\(formatter.string(from: task.startsOn))</td><td>\(formatter.string(from: task.dueOn))</td></tr>"
        }.joined()
        return """
        <!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>Kshift 工作报告</title></head>
        <body><h1>工作报告</h1><p>来源版本 revision \(revision)</p>
        <p>\(formatter.string(from: range.startsOn)) 至 \(formatter.string(from: range.endsOn))</p>
        <p>任务 \(statistics.taskCount) 项，完成 \(statistics.completedCount) 项，逾期 \(statistics.overdueCount) 项。</p>
        <table><thead><tr><th>任务</th><th>状态</th><th>负责人</th><th>开始</th><th>截止</th></tr></thead><tbody>\(rows)</tbody></table>
        </body></html>
        """
    }
}

public enum KshiftPlanSampleData {
    public static let projectID = UUID(uuidString: "D0000000-0000-4000-8000-000000000001")!
    public static let viewerID = UUID(uuidString: "D0000000-0000-4000-8000-000000000002")!
    public static let zhouID = UUID(uuidString: "D0000000-0000-4000-8000-000000000003")!
    public static let chenID = UUID(uuidString: "D0000000-0000-4000-8000-000000000004")!

    public static let planTaskID = UUID(uuidString: "E0000000-0000-4000-8000-000000000001")!
    public static let dependencyTaskID = UUID(uuidString: "E0000000-0000-4000-8000-000000000002")!
    public static let ganttTaskID = UUID(uuidString: "E0000000-0000-4000-8000-000000000003")!
    public static let reportTaskID = UUID(uuidString: "E0000000-0000-4000-8000-000000000004")!
    public static let historyTaskID = UUID(uuidString: "E0000000-0000-4000-8000-000000000005")!
    public static let attachmentTaskID = UUID(uuidString: "E0000000-0000-4000-8000-000000000006")!
    public static let exportTaskID = UUID(uuidString: "E0000000-0000-4000-8000-000000000007")!
    public static let attachmentID = UUID(uuidString: "F0000000-0000-4000-8000-000000000001")!

    public static func makeSnapshot(now: Date = .now) -> KshiftPlanDepthSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now)
        let people = [
            KshiftPlanPerson(id: viewerID, name: "林澈", initials: "LC", colorHex: "#2F7CF6"),
            KshiftPlanPerson(id: zhouID, name: "周宁", initials: "ZN", colorHex: "#2F9E6B"),
            KshiftPlanPerson(id: chenID, name: "陈默", initials: "CM", colorHex: "#D26A3B"),
        ]
        let tasks = [
            task(
                id: planTaskID,
                parentID: nil,
                title: "冻结 R3 计划深度",
                status: .inProgress,
                priority: .high,
                assigneeID: viewerID,
                startOffset: 0,
                length: 2,
                estimateMinutes: 240,
                position: 0,
                calendar: calendar,
                today: today
            ),
            task(
                id: dependencyTaskID,
                parentID: planTaskID,
                title: "补齐依赖环检测",
                status: .todo,
                priority: .urgent,
                assigneeID: zhouID,
                startOffset: 1,
                length: 1,
                estimateMinutes: 90,
                position: 1,
                calendar: calendar,
                today: today
            ),
            task(
                id: ganttTaskID,
                parentID: planTaskID,
                title: "实现跨日甘特行",
                status: .todo,
                priority: .high,
                assigneeID: chenID,
                startOffset: 2,
                length: 3,
                estimateMinutes: 180,
                position: 2,
                calendar: calendar,
                today: today
            ),
            task(
                id: reportTaskID,
                parentID: nil,
                title: "统一报告 source snapshot",
                status: .blocked,
                priority: .urgent,
                assigneeID: viewerID,
                startOffset: 1,
                length: 2,
                estimateMinutes: 150,
                position: 3,
                calendar: calendar,
                today: today
            ),
            task(
                id: historyTaskID,
                parentID: nil,
                title: "验证回退审计",
                status: .done,
                priority: .medium,
                assigneeID: zhouID,
                startOffset: -2,
                length: 1,
                estimateMinutes: 60,
                position: 4,
                calendar: calendar,
                today: today,
                completed: true
            ),
            task(
                id: attachmentTaskID,
                parentID: planTaskID,
                title: "核对附件 SHA-256",
                status: .todo,
                priority: .medium,
                assigneeID: chenID,
                startOffset: 2,
                length: 1,
                estimateMinutes: 45,
                position: 5,
                calendar: calendar,
                today: today
            ),
            task(
                id: exportTaskID,
                parentID: nil,
                title: "打印与图片导出走同一快照",
                status: .inProgress,
                priority: .high,
                assigneeID: zhouID,
                startOffset: 3,
                length: 2,
                estimateMinutes: 120,
                position: 6,
                calendar: calendar,
                today: today
            ),
        ]
        let dependencies = [
            KshiftPlanDependency(taskID: dependencyTaskID, dependsOnTaskID: planTaskID),
            KshiftPlanDependency(taskID: ganttTaskID, dependsOnTaskID: planTaskID),
            KshiftPlanDependency(taskID: reportTaskID, dependsOnTaskID: ganttTaskID),
        ]
        let attachment = KshiftPlanAttachment(
            id: attachmentID,
            sha256: String(repeating: "a", count: 64),
            mediaType: "text/markdown",
            byteSize: 34,
            filename: "r3-acceptance.md"
        )
        let link = KshiftPlanAttachmentLink(attachmentID: attachmentID, taskID: planTaskID)
        let history = [
            KshiftPlanHistoryEntry(
                id: UUID(uuidString: "F1000000-0000-4000-8000-000000000001")!,
                revision: 7,
                actorID: viewerID,
                action: "seeded",
                summary: "载入 R3 计划深度示例",
                occurredAt: now,
                contentSHA256: String(repeating: "b", count: 64)
            ),
            KshiftPlanHistoryEntry(
                id: UUID(uuidString: "F1000000-0000-4000-8000-000000000002")!,
                revision: 6,
                actorID: zhouID,
                action: "updated",
                summary: "更新任务「验证回退审计」",
                occurredAt: calendar.date(byAdding: .hour, value: -3, to: now)!,
                contentSHA256: String(repeating: "c", count: 64)
            ),
        ]
        return KshiftPlanDepthSnapshot(
            projectID: projectID,
            projectName: "Kshift 计划深度",
            revision: 7,
            people: people,
            tasks: tasks,
            dependencies: dependencies,
            attachments: [attachment],
            attachmentLinks: [link],
            history: history
        )
    }

    public static func makeBoundary(now: Date = .now) -> InMemoryKshiftPlanDepthBoundary {
        InMemoryKshiftPlanDepthBoundary(snapshot: makeSnapshot(now: now))
    }

    private static func task(
        id: UUID,
        parentID: UUID?,
        title: String,
        status: KshiftPlanTaskStatus,
        priority: KshiftPlanPriority,
        assigneeID: UUID,
        startOffset: Int,
        length: Int,
        estimateMinutes: UInt32,
        position: Int64,
        calendar: Calendar,
        today: Date,
        completed: Bool = false
    ) -> KshiftPlanTask {
        KshiftPlanTask(
            id: id,
            projectID: projectID,
            parentID: parentID,
            title: title,
            descriptionMarkdown: """
            ### 目标

            - 完成 **\(title)**
            - 保留 macOS 和 iOS 共享验收语义
            - 依赖与跨日排期由 Rust 快照提供

            > 此内容使用 Markdown 描述。
            """,
            status: status,
            priority: priority,
            assigneeID: assigneeID,
            startsOn: calendar.date(byAdding: .day, value: startOffset, to: today)!,
            dueOn: calendar.date(byAdding: .day, value: startOffset + length, to: today)!,
            estimateMinutes: estimateMinutes,
            position: position,
            version: 1,
            completedAt: completed ? calendar.date(byAdding: .hour, value: -5, to: today) : nil
        )
    }
}
