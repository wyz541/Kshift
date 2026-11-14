import KshiftCore
import SwiftUI

struct BoardView: View {
    @ObservedObject var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columnWidth: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return horizontalSizeClass == .compact ? 352 : 340
        }
        return horizontalSizeClass == .compact ? 286 : 304
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(model.columns) { column in
                    BoardColumnView(
                        model: model,
                        column: column,
                        width: columnWidth
                    )
                }
                Color.clear
                    .frame(width: 1)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.visible)
        .accessibilityIdentifier("board-view")
    }
}

private struct BoardColumnView: View {
    @ObservedObject var model: AppModel
    let column: PersonColumn
    let width: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.kshiftForceReduceTransparency) private var forceReduceTransparency

    private let maximumGlassCards = 6

    private var positions: (max: Int64, next: Int64) {
        let maximum = column.tasks.map(\.position).max() ?? 0
        return (maximum, maximum + 1024)
    }

    var body: some View {
        VStack(spacing: 12) {
            columnHeader

            ScrollView(.vertical) {
                GlassEffectContainer(spacing: 12) {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(column.tasks.prefix(maximumGlassCards))) { task in
                            TaskCard(
                                model: model,
                                task: task,
                                isSelected: model.selectedTaskIDs.contains(task.id)
                            )
                            .glassEffectID(task.id, in: namespace)
                        }
                    }
                }

                if column.tasks.count > maximumGlassCards {
                    VStack(spacing: 6) {
                        ForEach(column.tasks.dropFirst(maximumGlassCards)) { task in
                            CompactTaskRow(model: model, task: task)
                            Divider()
                        }
                    }
                    .padding(10)
                    .kshiftContentBoard()
                    .padding(.top, 12)
                }

                if column.tasks.isEmpty {
                    emptyState
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("board-column-\(column.id)")

            Button {
                model.presentNewTask(
                    assigneeIDs: column.person.map { [$0.id] } ?? [],
                    date: model.selectedDate
                )
            } label: {
                Label("添加任务", systemImage: "plus")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(hex: "#003F80"), in: Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular, in: Capsule())
            .accessibilityLabel("为\(column.title)添加任务")
        }
        .padding(12)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(reduceTransparency || forceReduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.thinMaterial))
        )
        .dropDestination(for: String.self) { taskIDs, _ in
            guard let taskID = taskIDs.first else { return false }
            Swift.Task {
                await model.moveTask(
                    taskID: taskID,
                    assigneeIDs: column.person.map { [$0.id] } ?? [],
                    date: model.selectedDate,
                    position: positions.next
                )
            }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title)，\(column.tasks.count) 项任务")
    }

    @Namespace private var namespace

    private var columnHeader: some View {
        HStack(spacing: 10) {
            if let person = column.person {
                PersonAvatar(person: person, size: 34)
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title3)
                    .frame(width: 34, height: 34)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(column.title)
                    .font(.headline)
                Text("\(column.tasks.count) 项")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("这一天暂无任务")
                .font(.subheadline.weight(.medium))
            Text("拖入任务或新建一项。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
