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

环境：macOS 27.0.1、Xcode 27.2、iPhone 18 Pro / Pro Max（iOS 27.0 Simulator）、隔离的 PostgreSQL 18.6 和 loopback TLS gRPC。数据库只包含测试数据。合并检查以 `origin/main` 的 `1b0311f` 为基线对照。

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
| 完整 `swift test`（连接 PostgreSQL 测试服务） | 73 项通过，0 项失败、0 项跳过；包括 10 项更新测试、平台隔离测试、远端 snapshot / report 和 macOS P0。 |
| `scripts/check-platform-boundaries.sh` | 通过；发布资源请求及 macOS 悬停预览由平台适配器提供。项目数据仍经 Rust FFI。 |
| 定向 iOS 可访问性检查 | 看板审计通过；新增测试验证最大 Dynamic Type 下能滚动到卡片并打开备注，Markdown 文字实际可见。iOS 27 对无关联节点的玻璃容器会产生一次 contrast 诊断，已按现有 People Schedule 规则记录为平台诊断，不针对可定位控件放宽检查。 |
| `scripts/check-r0.sh` 与 Issue、Worktree 审计 | 通过；未配置 Mermaid 解析器，跳过可选的 Mermaid 解析。 |

Migration digest：`76d52640b1d854e9d18663b59f08522d6a60c48929b1c69c6424a782836bc164`。

修复前，`2afc803` 的完整 iOS 套件记录 25 项通过、1 项失败、0 项跳过。`1b0311f` 和 `a285136` 均复现同一看板 Markdown 备注的 Dynamic Type 与裁切告警，以及 6 项更新测试失败和 5 个平台隔离断言失败。

模拟器截图：[修复前看板](remote-persistence-111/ios-board-before.png)、[修复后看板](remote-persistence-111/ios-board-after.png)、[最大字体备注面板](remote-persistence-111/ios-board-notes-axxxl.png)。原始卡片上的 Markdown 已移到可滚动面板，避免在窄列内裁切；截图为 Demo 数据。

未覆盖：内网主机部署、实体 iOS 设备、长时间负载、两个桌面窗口的自动推送刷新、实际发布和安装更新。客户端之间的一致性验证使用重新读取 snapshot；服务端事件流单独由 Rust 集成测试验证。
