import SwiftUI

struct KshiftAppSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingUpdateConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    settingsSection("排期布局") {
                        ScheduleLayoutSettingsSection(model: model)
                    }

                    Divider()

                    settingsSection("Updates") {
                        KshiftUpdateSettingsSection(
                            model: model,
                            isShowingConfirmation: $isShowingUpdateConfirmation
                        )
                    }

                    Divider()

                    settingsSection("无障碍") {
                        Button {
                            Swift.Task { await model.openAccessibilitySettings() }
                        } label: {
                            Label("打开系统辅助功能设置", systemImage: "accessibility")
                        }
                        .buttonStyle(KshiftCompactGlassButtonStyle())
                        .accessibilityIdentifier("open-accessibility-settings")

                        Text("系统辅助功能设置控制 Reduce Transparency、Increase Contrast 和 Reduce Motion。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    settingsSection("关于") {
                        LabeledContent("应用", value: "Kshift")
                        LabeledContent("版本", value: model.updateService.configuration.installed.version.description)
                        LabeledContent("Build", value: model.updateService.configuration.installed.build)
                        LabeledContent("项目", value: model.selectedProject?.name ?? "未选择")
                        LabeledContent("时区", value: model.projectTimeZone.identifier)
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .buttonStyle(KshiftCompactAccentGlassButtonStyle())
                        .accessibilityIdentifier("close-settings")
                }
            }
        }
        .frame(idealWidth: 540, idealHeight: 620)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
            content()
        }
    }
}

struct ScheduleLayoutSettingsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "人员列宽度 \(Int(model.schedulePeopleColumnWidth))pt",
                    systemImage: "person.2"
                )
                .font(.caption.weight(.semibold))
                Slider(
                    value: Binding(
                        get: { Double(model.schedulePeopleColumnWidth) },
                        set: { model.setSchedulePeopleColumnWidth(CGFloat($0)) }
                    ),
                    in: 168...320,
                    step: 4
                )
                .accessibilityLabel("人员列宽度")
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "日期列宽度 \(Int(model.scheduleDateColumnWidth))pt",
                    systemImage: "calendar"
                )
                .font(.caption.weight(.semibold))
                Slider(
                    value: Binding(
                        get: { Double(model.scheduleDateColumnWidth) },
                        set: { model.setScheduleDateColumnWidth(CGFloat($0)) }
                    ),
                    in: 96...360,
                    step: 8
                )
                .accessibilityLabel("日期列宽度")
            }

            Picker("显示密度", selection: $model.scheduleDensity) {
                ForEach(ScheduleDensity.allCases) { density in
                    Text(density.title).tag(density)
                }
            }
            .pickerStyle(.segmented)

            Text("布局设置按项目保存。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}


private struct KshiftUpdateSettingsSection: View {
    @ObservedObject var model: AppModel
    @Binding var isShowingConfirmation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Installed version", value: model.updateService.configuration.installed.version.description)
            LabeledContent("Build", value: model.updateService.configuration.installed.build)

            switch model.updateState {
            case .idle:
                Text("Check for a newer published Stable release.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .checking:
                ProgressView("Checking for updates…")
                    .controlSize(.small)
            case let .available(candidate):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Version \(candidate.version.description) is available.", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                    if let notes = candidate.releaseNotes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .textSelection(.enabled)
                    } else {
                        Text("Release notes are available on the release page.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let notesURL = candidate.releaseNotesURL {
                        Button("View Release Notes") {
                            Swift.Task { _ = await model.platformCapabilities.openExternalURL(notesURL) }
                        }
                        .buttonStyle(.link)
                        .accessibilityIdentifier("view-release-notes")
                    }
                    Button("Install Update") {
                        isShowingConfirmation = true
                    }
                    .buttonStyle(KshiftCompactAccentGlassButtonStyle())
                    .accessibilityIdentifier("install-update")
                }
            case .noUpdate:
                Label("No update is available.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("update-no-update")
            case let .incompatible(version, reason):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Version \(version.description) is not compatible.", systemImage: "exclamationmark.triangle")
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("update-incompatible")
            case let .failed(message):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Update check failed.", systemImage: "wifi.exclamationmark")
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Swift.Task { await model.checkForUpdates() }
                    }
                    .buttonStyle(KshiftCompactGlassButtonStyle())
                    .accessibilityIdentifier("retry-update-check")
                }
                .accessibilityIdentifier("update-failed")
            case .installing:
                ProgressView("Preparing update…")
                    .controlSize(.small)
            case .installed:
                Label("The approved installer was opened.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            if !isCheckingOrInstalling {
                Button("Check for Updates") {
                    Swift.Task { await model.checkForUpdates() }
                }
                .buttonStyle(KshiftCompactGlassButtonStyle())
                .accessibilityIdentifier("check-for-updates")
            }
        }
        .confirmationDialog(
            "Install Kshift update?",
            isPresented: $isShowingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Continue") {
                Swift.Task { await model.installAvailableUpdate() }
            }
            .accessibilityIdentifier("confirm-install-update")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Kshift will verify the release before opening the approved platform installer.")
        }
    }

    private var isCheckingOrInstalling: Bool {
        switch model.updateState {
        case .checking, .installing: return true
        default: return false
        }
    }
}
