import KshiftCore
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    var usesNavigationLinks = false

    var body: some View {
        List(selection: Binding(
            get: { model.selectedProjectID },
            set: { projectID in
                guard let projectID, projectID != model.selectedProjectID else { return }
                Swift.Task { await model.selectProject(projectID) }
            }
        )) {
            Section("项目") {
                ForEach(model.projects) { project in
                    projectCell(project)
                    .tag(project.id)
                    .accessibilityIdentifier("project-\(project.id)")
                    .accessibilityLabel("\(project.name)，项目代码 \(project.code)")
                }
            }

            Section("规划视图") {
                ForEach(PlannerViewMode.allCases) { mode in
                    Button {
                        model.viewMode = mode
                    } label: {
                        HStack {
                            Label(mode.title, systemImage: mode.symbol)
                            Spacer()
                            if model.viewMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("团队") {
                ForEach(model.people) { person in
                    HStack(spacing: 10) {
                        PersonAvatar(person: person, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name)
                            Text(person.id == model.client.actorID ? "当前编辑者" : "项目成员")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section {
                TimelineSummary(model: model)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                if let actor = model.currentActor {
                    PersonAvatar(person: actor, size: 30)
                    Text(actor.name)
                        .font(.callout.weight(.medium))
                }
                Spacer()
                Button {
                    Swift.Task { await model.openAccessibilitySettings() }
                } label: {
                    Image(systemName: "accessibility")
                }
                .buttonStyle(.glass)
                .help("打开系统辅助功能设置")
                .accessibilityLabel("打开系统辅助功能设置")
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func projectCell(_ project: ProjectSummary) -> some View {
        if usesNavigationLinks {
            NavigationLink {
                PlannerView(model: model)
            } label: {
                projectRow(project)
            }
        } else {
            projectRow(project)
        }
    }

    private func projectRow(_ project: ProjectSummary) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .lineLimit(1)
                Text(project.code)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Circle()
                .fill(Color(hex: project.colorHex))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        }
    }
}

struct TimelineSummary: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("当前快照", systemImage: "clock.arrow.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Text("Revision")
                Spacer()
                Text(String(model.snapshot?.project.revision ?? 0))
                    .monospacedDigit()
            }
            .font(.caption)
            HStack {
                Text("今日完成")
                Spacer()
                Text("\(model.completedToday)/\(model.selectedDateTasks.count)")
                    .monospacedDigit()
            }
            .font(.caption)
            ProgressView(
                value: Double(model.completedToday),
                total: Double(max(model.selectedDateTasks.count, 1))
            )
            .tint(.green)
            .accessibilityLabel("今日任务完成进度")
            .accessibilityValue("\(model.completedToday) 项已完成，共 \(model.selectedDateTasks.count) 项")
        }
        .padding(.vertical, 4)
    }
}

struct PersonAvatar: View {
    let person: Person
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: "person.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(Color(hex: person.colorHex))
                    .overlay {
                        Circle().fill(.black.opacity(0.28))
                    }
            }
            .accessibilityHidden(true)
    }
}
