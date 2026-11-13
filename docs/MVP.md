# R2 MVP 证据

结论：#7 已完成可运行代码路径。当前 transport 是 Rust 内存实现。真实 gRPC 和 PostgreSQL 尚未接入。

## 功能映射

| 验收项 | 实现 | 自动证据 |
| --- | --- | --- |
| 项目切换 | `SidebarView` 调用项目快照 | `testProjectSwitchKeepsDataIsolated` |
| 人员与日期看板 | `BoardView` 按负责人分组 | `testBootstrapLoadsFirstProjectAndDailyBoard` |
| 新增任务 | `TaskEditorView` 发送 typed command | `testCreateCommandUsesCurrentRevision` |
| 编辑任务 | 版本化 `UpdateTaskCommand` | Rust `create_update_and_conflict_are_audited` |
| 删除任务 | 确认对话框和审计记录 | Rust store test |
| 拖拽 | SwiftUI `draggable` 和 `dropDestination` | iOS build |
| 状态/优先级/人员/日期 | typed enum 和模型字段 | `ModelEncodingTests` |
| 日历 | `CalendarView` 月视图 | iOS build |
| 表格 | `TaskTableView` 共享视图 | iOS build |
| 搜索/筛选/排序 | `AppModel.filteredTasks` | `testSearchAndFiltersReduceDailyTasks` |
| 批量处理 | `set_tasks_status` 原子命令 | Rust `batch_update_is_atomic` |
| 并发冲突 | revision 和 task version 双重保护 | Rust tests、`testConflictIsExplicitAndDoesNotReplaceSnapshot` |
| 历史 | task history 和 project audit | Rust `create_update_and_conflict_are_audited` |
| Liquid Glass | 原生 API only | `scripts/verify.sh` 结构检查 |
| 单 UI 实现 | `Sources/KshiftUI` 无平台条件分支 | `scripts/verify.sh` 结构检查 |
| FFI-only boundary | `KshiftUI` 不调用 HTTP/protobuf/DB | `scripts/verify.sh` 结构检查 |

## 未完成证据

| 项目 | 状态 | 原因 |
| --- | --- | --- |
| macOS/iOS 截图对比 | 已采集 | 见 `docs/evidence` |
| iOS 创建任务 E2E | 已通过 | `KshiftIOSUITests` |
| Reduce Transparency | 待人工检查 | 需要系统设置和视觉读数 |
| Increase Contrast | 待人工检查 | 需要系统设置和视觉读数 |
| Reduce Motion | 待人工检查 | 需要系统设置和视觉读数 |
| VoiceOver | 待人工检查 | 需要 macOS/iOS Accessibility Inspector |
| 性能读数 | 待采集 | 需要 Instruments 滚动、拖拽、Sheet 和窗口缩放记录 |
| 真机多用户冲突 | 待集成 | #4 尚未提供 gRPC/PostgreSQL transport |

## 冲突语义

| 情况 | 返回 | 写入 |
| --- | --- | --- |
| 项目 revision 过期 | `revision_conflict` | 拒绝 |
| 任务 version 过期 | `version_conflict` | 拒绝 |
| 批量中一个任务过期 | `version_conflict` | 全部拒绝 |
| 同一 request ID 重试 | 缓存响应 | 不重复写入 |

## Liquid Glass 预算

| 区域 | 玻璃策略 |
| --- | --- |
| 导航、侧栏、工具栏、Sheet | 使用系统组件 |
| 看板交互卡片 | 原生 `Glass.regular` |
| 同列卡片 | 一个 `GlassEffectContainer` |
| 每列玻璃卡片 | 最多 12 个 |
| 卡片文字 | 系统内容底板 |
| 表格、长文本、日历网格 | 清晰内容底板 |
| 冲突提示和批量栏 | 一个受控 `GlassEffectContainer` |
