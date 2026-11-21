---
slug: /evidence/remote-persistence-111
title: Kshift 默认远端连接验证
type: evidence
status: review
updated: "2026-11-21"
keywords:
  - PostgreSQL
  - 远端持久化
  - iOS Simulator
description: 记录 Task #111 的本地连接、PostgreSQL 和恢复验证结果。
---

# Kshift 默认远端连接验证

[Task #111](https://github.com/wyz541/Kshift/issues/111) 使用现有 `kshift-server` 和 PostgreSQL。客户端默认走远端；没有连接配置时不回退到演示数据。本记录是本地交付证据，不是 [Acceptance #112](https://github.com/wyz541/Kshift/issues/112) 的最终结论。

环境：macOS 27.0.1、Xcode 27.2、iPhone 18 Pro（iOS 27.0 Simulator）、隔离的 PostgreSQL 18.6 和 loopback TLS gRPC。数据库只包含测试数据。完整 iOS 套件结果来自 `2afc803`；合并检查另以 `origin/main` 的 `1b0311f` 为基线对照。

| Check | Result |
| --- | --- |
| `cargo test --workspace --locked`，同时设置 `TEST_DATABASE_URL` 和 `KSHIFT_TEST_DATABASE_URL` | 通过；包含数据库事务、并发冲突、outbox 回放、restart、migration 和 plan store 集成用例。容量测试使用默认 1 秒，不代表 30 分钟门禁。 |
| `kshift-server migrate` 和 `kshift-server check` | `healthy=true`，schema version 3，2 项 migration。 |
| `scripts/recovery-test.sh` | `rollback=verified`、`restore=verified`，恢复后项目数为 1。 |
| macOS Debug `xcodebuild build`，使用 `build/DerivedData` | 构建通过。 |
| `swift test --filter 'LiveP0E2ETests\|KshiftClientFactoryTests'`，连接测试服务 | 6 项通过。macOS P0 完成 38 项检查。两个默认客户端实例通过 snapshot 看到同一任务的创建和删除，各推进一个 revision。 |
| iOS `testIOSLiveP0Scenario` | 通过；共享 P0 场景通过 FFI 对测试服务读写。 |
| iOS `testDefaultClientOpensRemoteProject` | 通过；未启用 `KSHIFT_USE_FFI` 或 Demo，项目切换按钮确认打开的是远端 `Alpha Project`。 |
| iOS `testBothProjectTimeZonesAndLiveUIWriteE2E` | 通过；覆盖两个项目时区、日期导航、日历、任务历史、UI 保存和项目切换。 |
| iOS UI 写入的 PostgreSQL 校验 | 通过；`Alpha Project` 存在一条 `Live UI created task`。计划日期为 `2026-11-15`，任务版本为 `1`，`create_task` 审计记录匹配 outbox revision `14`。 |
| 完整 iOS Simulator `xcodebuild test` | `.xcresult` 记录 25 项通过、1 项失败、0 项跳过。唯一失败是 `testAccessibilityAudit`：看板 Markdown 摘要触发 Dynamic Type 和文字裁切报告。 |
| 合并最新 `main` 后单独复跑 iOS 审计 | `1b0311f` 和 Task 分支 `a285136` 均在同一条看板 Markdown 摘要上复现上述失败。两次局部试改均未修复，已撤回；未放宽审计。 |
| 合并最新 `main` 后完整 `swift test` | `1b0311f` 和 Task 分支 `a285136` 均报 6 个更新测试失败、5 个平台边界断言失败。Task 分支有 3 个跳过（这次未连接测试服务）；服务端路径的定向测试见上。 |
| `scripts/check-platform-boundaries.sh` | Task 分支未通过：现有 `KshiftUpdateModels.swift` 导入 `FoundationNetworking`。 |
| `scripts/check-r0.sh` 与 Issue、Worktree 审计 | 通过；未配置 Mermaid 解析器，跳过可选的 Mermaid 解析。 |

Migration digest：`76d52640b1d854e9d18663b59f08522d6a60c48929b1c69c6424a782836bc164`。

未覆盖：内网主机部署、实体 iOS 设备、长时间负载、两个桌面窗口的自动推送刷新。客户端之间的一致性验证使用重新读取 snapshot；服务端事件流单独由 Rust 集成测试验证。
