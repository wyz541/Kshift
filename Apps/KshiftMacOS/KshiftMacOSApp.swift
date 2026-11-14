#if os(macOS)
  import AppKit
  import Darwin
  import KshiftAppKitAdapter
  import KshiftCore
  import KshiftUI
  import SwiftUI

  @main
  struct KshiftMacOSApp: App {
    @StateObject private var model = KshiftRuntimeEnvironment.makeModel(
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
          .background {
            if let capturePath = ProcessInfo.processInfo.environment["KSHIFT_CAPTURE_PNG"],
               !capturePath.isEmpty
            {
              MacWindowCaptureCoordinator(model: model, outputPath: capturePath)
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

  private struct MacWindowCaptureCoordinator: View {
    @ObservedObject var model: AppModel
    let outputPath: String
    @State private var window: NSWindow?

    var body: some View {
      Color.clear
        .frame(width: 0, height: 0)
        .background {
          AppKitWindowAccessor { window = $0 }
        }
        .task {
          for _ in 0..<150 {
            if model.hasLoaded, let window {
              try? await Task.sleep(for: .milliseconds(750))
              capture(window)
              return
            }
            try? await Task.sleep(for: .milliseconds(100))
          }
          fputs("KSHIFT_CAPTURE_TIMEOUT\n", stderr)
          NSApplication.shared.terminate(nil)
        }
    }

    private func capture(_ window: NSWindow) {
      NSApplication.shared.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      window.displayIfNeeded()

      let data = windowImage(window)?.representation(using: .png, properties: [:])
      guard let data else {
        fputs("KSHIFT_CAPTURE_PNG_FAILED\n", stderr)
        NSApplication.shared.terminate(nil)
        return
      }
      do {
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print("KSHIFT_CAPTURE_READY \(outputPath)")
      } catch {
        fputs("KSHIFT_CAPTURE_WRITE_FAILED \(error)\n", stderr)
      }
      NSApplication.shared.terminate(nil)
    }

    private func windowImage(_ window: NSWindow) -> NSBitmapImageRep? {
      typealias WindowImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
      guard let handle = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        RTLD_LAZY
      ), let symbol = dlsym(handle, "CGWindowListCreateImage") else {
        return nil
      }
      defer { dlclose(handle) }
      let createImage = unsafeBitCast(symbol, to: WindowImageFunction.self)
      guard let image = createImage(
        .null,
        8,
        UInt32(window.windowNumber),
        9
      )?.takeRetainedValue() else {
        return nil
      }
      return NSBitmapImageRep(cgImage: image)
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
