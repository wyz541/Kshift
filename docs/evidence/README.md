# R2 证据

以下截图来自 2026-11-13 本地运行。

| 文件 | 平台 | 内容 |
| --- | --- | --- |
| `macos-board.jpg` | macOS 27.0.1 | 侧栏、项目快照、人员/日期看板和 Liquid Glass 卡片 |
| `ios-board.png` | iOS 27.0 模拟器 | 紧凑项目菜单、日期控制、看板和浮动操作 |

## 已运行门禁

- `cargo fmt --all -- --check`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test --workspace`
- `swift test`
- macOS `xcodebuild build`
- iOS `xcodebuild test`
- iOS UI 创建任务流程

## 未覆盖

- Reduce Transparency 视觉截图。
- Increase Contrast 视觉截图。
- Reduce Motion 视觉截图。
- VoiceOver 人工检查。
- Instruments 性能读数。
