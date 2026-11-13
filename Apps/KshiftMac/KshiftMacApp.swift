import KshiftCore
import KshiftPlatform
import KshiftUI
import SwiftUI

@main
struct KshiftMacApp: App {
    @StateObject private var model = AppModel(
        client: RustClient(),
        platform: MacPlatformServices()
    )

    var body: some Scene {
        WindowGroup {
            KshiftRootView(model: model)
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 800)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            KshiftCommands(model: model)
        }
    }
}

private struct KshiftCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建任务") {
                model.presentNewTask(assigneeID: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("规划") {
            Button("刷新共享快照") {
                Swift.Task { await model.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("看板") { model.viewMode = .board }
                .keyboardShortcut("1", modifiers: .command)
            Button("日历") { model.viewMode = .calendar }
                .keyboardShortcut("2", modifiers: .command)
            Button("表格") { model.viewMode = .table }
                .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("删除选中任务") {
                if let task = model.selectedTasks.first {
                    model.requestDelete(task)
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.selectedTaskIDs.isEmpty)

            Button("清除选择") {
                model.clearSelection()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(model.selectedTaskIDs.isEmpty)
        }
    }
}
