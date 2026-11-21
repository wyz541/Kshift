---
slug: /evidence/remote-persistence-111
title: Kshift 默认远端连接验证
type: evidence
status: review
updated: "2026-11-21"
description: 记录 Task #111 的本地连接、PostgreSQL 和恢复验证结果。
---

# Kshift 默认远端连接验证

[Task #111](https://github.com/wyz541/Kshift/issues/111) 使用现有 `kshift-server` 和 PostgreSQL。客户端默认走远端；没有连接配置时不回退到演示数据。本记录是本地交付证据，不是 [Acceptance #112](https://github.com/wyz541/Kshift/issues/112) 的最终结论。

环境：macOS 27.0.1、Xcode 27.2、iPhone 18 Pro（iOS 27.0 Simulator）、隔离的 PostgreSQL 18.6 和 loopback TLS gRPC。数据库只包含测试数据。全量 Swift 对照基线为 `b16d3c7`。

| Check | Result |
| --- | --- |
| `cargo test --workspace --locked`，同时设置 `TEST_DATABASE_URL` 和 `KSHIFT_TEST_DATABASE_URL` | 通过；包含数据库事务、并发冲突、outbox 回放、restart、migration 和 plan store 集成用例。容量测试使用默认 1 秒，不代表 30 分钟门禁。 |
| `kshift-server migrate` 和 `kshift-server check` | `healthy=true`，schema version 3，2 项 migration。 |
| `scripts/recovery-test.sh` | `rollback=verified`、`restore=verified`，恢复后项目数为 1。 |
| macOS Debug `xcodebuild build`，使用 `build/DerivedData` | 构建通过。 |
| `swift test --filter 'LiveP0E2ETests\|KshiftClientFactoryTests'`，连接测试服务 | 6 项通过。macOS P0 完成 38 项检查。两个默认客户端实例通过 snapshot 看到同一任务的创建和删除，各推进一个 revision。 |
| iOS `testIOSLiveP0Scenario` | 通过；共享 P0 场景通过 FFI 对测试服务读写。 |
| iOS `testDefaultClientOpensRemoteProject` | 通过；应用未设置 `KSHIFT_USE_FFI`，成功打开远端项目。 |
| iOS `testBothProjectTimeZonesAndLiveUIWriteE2E` | 未通过；到达远端项目后停在日期或当日任务数断言，未走到 UI 保存。 |
| 完整 `swift test` 与 `b16d3c7` 对照 | 两者均未通过：更新模块报 6 个失败，平台边界测试报 5 个断言失败。未在此任务修复。 |

Migration digest：`76d52640b1d854e9d18663b59f08522d6a60c48929b1c69c6424a782836bc164`。

未覆盖：内网主机部署、实体 iOS 设备、长时间负载、两个桌面窗口的自动推送刷新。客户端之间的一致性验证使用重新读取 snapshot；服务端事件流单独由 Rust 集成测试验证。
