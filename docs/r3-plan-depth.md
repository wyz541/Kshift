---
slug: /docs/r3-plan-depth
title: R3 计划深度验收
type: reference
status: active
updated: "2026-11-14"
keywords:
  - R3
  - 计划深度
  - 子任务
  - 依赖
  - 附件
  - 历史回退
  - 报告
related_issue: "https://github.com/wyz541/Kshift/issues/8"
description: 记录 R3 业务不变量、跨平台 UI 门禁和运行证据。
---

# R3 计划深度验收

> 结论：R3 的权威业务规则位于 `kshift-core::plan_depth`。PostgreSQL 和 SwiftUI 只使用该切片产生的 snapshot。

## 1. 交付切片

| 切片 | 权威实现 | 输出 |
| --- | --- | --- |
| 子任务 | `kshift-core` | 父子关系、循环检查、删除约束 |
| 依赖 | `kshift-core` | 同项目依赖、直接环和间接环检查 |
| 跨日排期 | `kshift-core` | 开始日期、截止日期和不变量 |
| 附件 | `kshift-core` | SHA-256 去重、10 MiB 上限、类型白名单 |
| 历史 | `kshift-core` | revision、审计、内容摘要 |
| 回退 | `kshift-core` | Admin 限制、目标版本、恢复证据 |
| 报告 | `kshift-core` | 单一 source revision、统计和工作报告 |
| 持久化 | `kshift-plan-store` | snapshot、历史状态、附件内容 |
| gRPC 边界 | `kshift-server` | R3 snapshot、status/rollback command 和 report RPC |
| FFI 边界 | `kshift-ffi` / `KshiftCore.RustClient` | 有界 JSON、server role 和 typed Swift view |
| 双平台 UI | `KshiftUI` | 同一页面和同一 presentation mapping |

## 2. 验收矩阵

| 验收项 | 测试或证据 | 结果 |
| --- | --- | --- |
| 依赖关系不形成环 | `rejects_direct_and_indirect_dependency_cycles` | 通过 |
| 子任务关系不形成环 | `rejects_subtask_cycles_and_cross_day_errors` | 通过 |
| 跨日日期不变量 | `rejects_subtask_cycles_and_cross_day_errors` | 通过 |
| 附件 SHA-256 去重 | `attachment_is_type_checked_and_deduplicated_by_sha256` | 通过 |
| 附件大小和类型限制 | `AttachmentPolicy` 单元测试 | 通过 |
| 回退审计和恢复证据 | `rollback_requires_admin_and_records_restore_evidence` | 通过 |
| PostgreSQL 重启后读取 | `persistent_plan_depth_survives_conflict_attachment_and_rollback` | 通过 |
| 过期 revision 被拒绝 | PostgreSQL 集成测试 | 通过 |
| 报告使用同一 snapshot | Rust、Swift 和 PostgreSQL 测试 | 通过 |
| gRPC snapshot/command/report | `plan_depth_snapshot_command_and_report_use_typed_grpc` | 通过 |
| Swift 到 FFI 的 R3 读写和报告 | `testRustClientReadsSnapshotWhenServerConfigurationIsProvided` | 通过 |
| 图片导出使用报告 revision | `testReportImageExportUsesTypedReportRevision` | 通过 |
| macOS 构建 | `Kshift-macOS` Debug build | 通过 |
| iOS 构建 | `Kshift-iOS` Simulator build | 通过 |
| iOS P0 流程 | `testPlanDepthFlowAndAccessibilityAudit` | 通过 |
| 触控区域、字号和对比度 | XCUI accessibility audit | 通过 |
| Liquid Glass 卡片上限 | `testBoardCapsNativeGlassCardsAtSix` | 通过 |

## 3. 运行证据

本次运行使用以下环境。

| 项目 | 值 |
| --- | --- |
| macOS | 27.0.1 |
| Xcode | 27.2 |
| iOS Simulator | iPhone 17e, iOS 27.0 |
| PostgreSQL | 18.7 |
| Swift | 6.4.2 |
| Rust | 1.99.1 |

运行结果如下。

- Rust 领域测试：11 项通过。
- Swift package tests：通过。
- R3 iOS UI 测试：通过。
- PostgreSQL 18 集成测试：通过。
- macOS app：构建通过。
- iOS app：构建通过。
- 辅助功能大字号截图：筛选栏改为纵向布局，无文字重叠。
- macOS 与 iOS 截图：看板、Glass 卡片和内容底板显示正常。

## 4. 当前限制

- 生产 `RustClient` 通过 R3 gRPC/FFI 边界读取 snapshot、执行 status/rollback command 并读取报告。内存边界只用于 sample 和 preview client。
- R3 snapshot revision 必须等于项目 revision。两者不一致时，server 拒绝 R3 请求，避免覆盖较新的项目数据。
- 当前 R3 UI 只写入任务状态和执行回退。附件上传、依赖编辑和子任务编辑仍使用通用 Task RPC 或后续 UI slice。
- 外部导入、Web、Windows、Android 和离线写入不在本切片范围。
