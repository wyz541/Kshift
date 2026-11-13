import Foundation
import KshiftFFI
import KshiftPresentation
import SwiftUI

@MainActor
public struct KshiftDayPlanFeatureView: View {
  @State private var model: KshiftDayPlanFeatureModel
  private let capabilities: any KshiftPlatformCapabilities

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(
    capabilities: any KshiftPlatformCapabilities,
    locale: Locale = .current,
    timeZone: TimeZone = .current
  ) {
    let now = Date()
    let snapshot = KshiftSampleData.makeSnapshot(now: now)
    let viewer =
      snapshot.members.first(where: { $0.id == snapshot.viewerID })
      ?? KshiftUser(id: snapshot.viewerID, name: "当前用户")
    let model = KshiftDayPlanFeatureModel(
      boundary: InMemoryKshiftFFIBoundary(snapshot: snapshot),
      capabilities: capabilities,
      projectID: snapshot.projectID,
      workDate: snapshot.workDate,
      viewer: viewer,
      locale: locale,
      timeZone: timeZone
    )
    self.capabilities = capabilities
    _model = State(initialValue: model)
  }

  public init(
    model: KshiftDayPlanFeatureModel,
    capabilities: any KshiftPlatformCapabilities
  ) {
    self.capabilities = capabilities
    _model = State(initialValue: model)
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        content
          .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 860)
          .padding(.horizontal, 20)
          .padding(.vertical, 24)
          .frame(maxWidth: .infinity)
      }
      .kshiftScreenBackground()
      .navigationTitle("日计划")
      .toolbar {
        ToolbarItemGroup {
          Button {
            Task {
              await capabilities.openExternalURL(
                URL(string: "https://github.com/wyz541/Kshift/issues/6")!
              )
            }
          } label: {
            Label("打开任务说明", systemImage: "questionmark.circle")
          }

          Button {
            Task { await model.load() }
          } label: {
            Label("刷新", systemImage: "arrow.clockwise")
          }
          .disabled(model.phase == .loading)
        }
      }
    }
    .task {
      await model.loadIfNeeded()
    }
  }

  @ViewBuilder
  private var content: some View {
    if let presentation = model.presentation {
      planContent(presentation)
    } else {
      switch model.phase {
      case .idle, .loading:
        ProgressView("正在读取日计划")
          .frame(maxWidth: .infinity, minHeight: 320)
          .accessibilityLabel("正在读取日计划")
      case .failed(let message):
        ContentUnavailableView {
          Label("无法显示日计划", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          KshiftPrimaryGlassButton {
            Task { await model.load() }
          } label: {
            Label("重试", systemImage: "arrow.clockwise")
          }
        }
        .frame(minHeight: 320)
      case .loaded:
        EmptyView()
      }
    }
  }

  @ViewBuilder
  private func planContent(_ presentation: KshiftDayPlanPresentation) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      summaryCard(presentation)

      if let conflict = model.conflict {
        conflictBanner(conflict)
      }

      if case .failed(let message) = model.phase {
        Text(message)
          .font(.callout)
          .foregroundStyle(Color.kshift(.danger))
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
          .accessibilityLabel("错误：\(message)")
      }

      filterPicker(presentation)
      taskList(presentation)
    }
  }

  private func summaryCard(_ presentation: KshiftDayPlanPresentation) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(presentation.projectTitle)
          .font(.title2.weight(.bold))
        Spacer(minLength: 8)
        Text(presentation.revisionLabel)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      Text(presentation.dateLabel)
        .font(.subheadline)
        .foregroundStyle(.secondary)

      ProgressView(value: presentation.progressFraction) {
        Text(presentation.progressLabel)
          .font(.subheadline)
      }
      .tint(Color.kshift(.accent))
      .accessibilityLabel("完成进度")
      .accessibilityValue(presentation.progressLabel)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(presentation.accessibilitySummary)
  }

  private func conflictBanner(_ conflict: KshiftConflictPresentation) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(conflict.title, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
        .font(.headline)
        .foregroundStyle(Color.kshift(.danger))
      Text(conflict.message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      HStack {
        KshiftPrimaryGlassButton {
          Task { await model.load() }
        } label: {
          Label(conflict.refreshTitle, systemImage: "arrow.clockwise")
        }
        KshiftSecondaryGlassButton {
          model.dismissConflict()
        } label: {
          Text("稍后处理")
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(Color.kshift(.danger).opacity(0.4), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }

  private func filterPicker(_ presentation: KshiftDayPlanPresentation) -> some View {
    @Bindable var bindableModel = model
    return Picker("筛选任务", selection: $bindableModel.filter) {
      ForEach(presentation.filters) { option in
        Text(option.title).tag(option.filter)
      }
    }
    .pickerStyle(.segmented)
    .accessibilityLabel("筛选任务")
  }

  @ViewBuilder
  private func taskList(_ presentation: KshiftDayPlanPresentation) -> some View {
    if presentation.tasks.isEmpty {
      ContentUnavailableView(
        presentation.emptyTitle,
        systemImage: "checkmark.circle",
        description: Text(presentation.emptyMessage)
      )
      .frame(minHeight: 220)
    } else {
      KshiftGlassGroup(spacing: 12) {
        LazyVStack(spacing: 12) {
          ForEach(presentation.tasks) { task in
            KshiftTaskCard(
              task: task,
              isPending: model.pendingTaskID == task.id
            ) {
              Task { await model.toggle(task) }
            }
          }
        }
      }

      if presentation.hiddenTaskCount > 0 {
        Text(
          "还有 \(presentation.hiddenTaskCount) 项任务未显示。当前只渲染 \(KshiftDayPlanPresentationMapper.maximumVisibleInteractiveCards) 个交互玻璃卡片。"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("还有 \(presentation.hiddenTaskCount) 项任务未显示")
      }
    }
  }
}
