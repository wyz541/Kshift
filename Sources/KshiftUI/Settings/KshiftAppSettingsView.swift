import SwiftUI

struct KshiftAppSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    settingsSection("排期布局") {
                        ScheduleLayoutSettingsSection(model: model)
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
                        LabeledContent("应用", value: "Kshift Dev")
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
