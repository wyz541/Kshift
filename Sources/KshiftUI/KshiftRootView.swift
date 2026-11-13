import KshiftCore
import SwiftUI

public struct KshiftRootView: View {
    @ObservedObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShowingFilters = false

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        rootContent
        .dynamicTypeSize(.xSmall ... .accessibility5)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "搜索任务")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("视图", selection: $model.viewMode) {
                    ForEach(PlannerViewMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("规划视图")

                Button {
                    isShowingFilters.toggle()
                } label: {
                    Label("筛选", systemImage: model.filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.glass)
                .popover(isPresented: $isShowingFilters, arrowEdge: .bottom) {
                    FilterPopover(model: model)
                }
                .help("筛选任务")

                Button {
                    Swift.Task { await model.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .help("刷新共享快照")

                Button {
                    model.presentNewTask(assigneeIDs: [])
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier(
                    dynamicTypeSize.isAccessibilitySize ? "add-task" : "toolbar-add-task"
                )
            }
        }
        .sheet(item: $model.editorDraft) { draft in
            TaskEditorView(model: model, initialDraft: draft)
        }
        .sheet(item: Binding(
            get: { model.task(withID: model.detailTaskID) },
            set: { if $0 == nil { model.detailTaskID = nil } }
        )) { task in
            TaskDetailView(model: model, taskID: task.id)
        }
        .overlay(alignment: .top) {
            if let conflict = model.conflict {
                ConflictBanner(model: model, notice: conflict)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if !model.selectedTaskIDs.isEmpty {
                BulkActionBar(model: model)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.24), value: model.conflict?.id)
        .animation(.snappy(duration: 0.24), value: model.selectedTaskIDs.isEmpty)
        .confirmationDialog(
            "删除任务？",
            isPresented: Binding(
                get: { model.taskPendingDeletion != nil },
                set: { if !$0 { model.cancelDelete() } }
            ),
            presenting: model.taskPendingDeletion
        ) { task in
            Button("删除“\(task.title)”", role: .destructive) {
                Swift.Task { _ = await model.deleteTask(task) }
            }
            Button("取消", role: .cancel) { model.cancelDelete() }
        } message: { _ in
            Text("删除会写入项目审计记录。此操作不能静默撤销。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("关闭", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.bootstrap() }
        .onChange(of: model.selectedProjectID) { _, newValue in
            guard let newValue else { return }
            Swift.Task { await model.selectProject(newValue) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, model.hasLoaded {
                Swift.Task { await model.refresh() }
            }
        }
    }
    @ViewBuilder
    private var rootContent: some View {
        if horizontalSizeClass == .compact {
            NavigationStack {
                PlannerView(model: model)
            }
        } else {
            NavigationSplitView {
                SidebarView(model: model, usesNavigationLinks: false)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 310)
            } detail: {
                PlannerView(model: model)
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

}
