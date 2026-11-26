#if os(macOS)
  import AppKit
  import Darwin
  import KshiftAppKitAdapter
  import KshiftCore
  import KshiftUI
  import SwiftUI

  @main
  struct KshiftMacOSApp: App {
    @StateObject private var model: AppModel
    private let launchUptime: TimeInterval

    init() {
      launchUptime = ProcessInfo.processInfo.systemUptime
      let platform = AppKitPlatformCapabilities()
      platform.installScrollWheelRouting()
      _model = StateObject(
        wrappedValue: KshiftRuntimeEnvironment.makeModel(
          client: KshiftClientFactory.makeDefault(),
          platform: platform
        )
      )
    }

    var body: some Scene {
      WindowGroup {
        KshiftRootView(model: model)
          .modifier(
            KshiftEvidenceEnvironmentModifier(
              environment: ProcessInfo.processInfo.environment
            )
          )
          .environment(\.kshiftScheduleHoverPresenter, { isPresented, preview in
            AnyView(AppKitScheduleHoverPopover(isPresented: isPresented, preview: preview))
          })
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
          .background {
            let environment = ProcessInfo.processInfo.environment
            let capturePath = environment["KSHIFT_CAPTURE_PNG"]
            let auditPath = environment["KSHIFT_ACCESSIBILITY_AUDIT_PATH"]
            let metricsPath = environment["KSHIFT_CAPTURE_METRICS_PATH"]
            if capturePath != nil || auditPath != nil || metricsPath != nil {
              MacReleaseEvidenceCoordinator(
                model: model,
                launchUptime: launchUptime,
                screenshotPath: capturePath,
                auditPath: auditPath,
                metricsPath: metricsPath
              )
            }
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
          model.presentNewTask(assigneeIDs: [])
        }
        .keyboardShortcut("n", modifiers: .command)
      }

      CommandMenu("规划") {
        Button("刷新共享快照") {
          Swift.Task { await model.refresh() }
        }
        .keyboardShortcut("r", modifiers: .command)

        Divider()

        Button("人员排期") { model.viewMode = .peopleSchedule }
          .keyboardShortcut("1", modifiers: .command)
        Button("看板") { model.viewMode = .board }
          .keyboardShortcut("2", modifiers: .command)
        Button("日历") { model.viewMode = .calendar }
          .keyboardShortcut("3", modifiers: .command)
        Button("表格") { model.viewMode = .table }
          .keyboardShortcut("4", modifiers: .command)

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
