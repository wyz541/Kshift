#if os(macOS)
  import KshiftAppKitAdapter
  import KshiftCore
  import KshiftUI
  import SwiftUI

  @main
  struct KshiftMacOSApp: App {
    @StateObject private var model = AppModel(
      client: KshiftClientFactory.makeDefault(),
      platform: AppKitPlatformCapabilities()
    )

    var body: some Scene {
      WindowGroup {
        KshiftRootView(model: model)
          .environment(
            \.kshiftForceReduceTransparency,
            ProcessInfo.processInfo.environment["KSHIFT_FORCE_REDUCE_TRANSPARENCY"] == "1"
          )
          .frame(minWidth: 940, minHeight: 620)
          .tint(.accentColor)
          .background {
            AppKitWindowAccessor { window in
              window?.isMovableByWindowBackground = true
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
          }
      }
      .defaultSize(width: 1_180, height: 800)
      .windowToolbarStyle(.unifiedCompact)
      .commands {
        KshiftPlannerCommands(model: model)
      }
    }
  }

  private struct KshiftPlannerCommands: Commands {
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
#endif
