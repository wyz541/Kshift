---
slug: /evidence/live-server
title: 真实服务端 E2E
type: report
status: review
updated: "2026-11-14"
keywords:
  - gRPC
  - PostgreSQL
  - TLS
  - E2E
  - FFI
description: 记录 macOS 和 iOS 通过真实 TLS gRPC server 验证时区、核心操作、历史和 UI 写入的证据。
---

# 真实服务端 E2E

结论：macOS 和 iOS 已运行同一个 live P0 场景。iOS live UI E2E 另外验证项目时区、今天按钮、日历和 UI 写入。

## 环境

| 项目 | 值 |
| --- | --- |
| 日期 | 2026-11-14 |
| PostgreSQL | PostgreSQL 18，临时 Docker 实例 |
| PostgreSQL 端口 | `54329` |
| server | `kshift-server serve` |
| server 端口 | 脚本选择空闲 loopback 端口 |
| TLS | `fixtures/tls` 的 loopback 证书 |
| 用户 | `Mia Chen` |
| 第二项目成员 | `Noah Li` |
| token | `live-ui-e2e-token`，只用于本地测试 |
| 固定时刻 | `2026-11-14T10:30:00Z` |
| 用户时区 | `America/Los_Angeles` |

## 时区 fixture

| 项目 | IANA 时区 | 固定时刻的项目日期 | 初始任务 |
| --- | --- | --- | ---: |
| `Alpha Project` | `Pacific/Kiritimati` | `2026-11-15` | 3 |
| `Beta Project` | `America/Los_Angeles` | `2026-11-14` | 1 |

`Alpha Project` 有 3 个任务和 5 条审计记录。`Beta Project` 有 1 个任务和 3 条审计记录。

## P0 场景

`KshiftP0E2EProbe` 在 macOS 和 iOS 运行 37 个检查步骤：

- 两个项目及其数据隔离。
- 两个项目时区、今天日期和每日任务数。
- 看板、日历和表格。
- 搜索、筛选和排序。
- 创建多负责人任务。
- 编辑状态、优先级和负责人。
- 拖拽到目标负责人列。
- 完成和恢复任务。
- 批量更新和批量恢复。
- revision 冲突和静默覆盖检查。
- live task history。
- 删除任务及其验证。

macOS 通过 `KshiftCoreTests` 直接驱动共享 `AppModel`。iOS 通过 App target 的 DEBUG harness 驱动同一个 probe。两条路径都使用真实 `RustClient`、`kshift-ffi`、TLS gRPC 和 PostgreSQL。

## iOS UI E2E

`testBothProjectTimeZonesAndLiveUIWriteE2E` 验证：

- Alpha 项目显示 `November 15`。
- 前一天和今天按钮使用项目时区。
- 日历显示 `calendar-day-2026-11-15`、`3 项任务` 和“今天”。
- live history 显示创建任务记录。
- UI 创建 `Live UI created task` 后，当日任务数从 3 升到 4。
- 切换到 Beta 后显示 `November 14` 和 1 个任务。

截图：

- [iOS live server](ios-live-server.png)
- [macOS live server](macos-live-server.png)

iOS 截图在 UI 写入前采集，显示 3 个任务。macOS 截图在 P0 和 UI 写入后采集，显示 4 个任务和 revision 22。

## 验证

| 检查 | 结果 |
| --- | --- |
| `make live-ui-e2e` | 通过 |
| macOS live P0 scenario | 通过，37 步 |
| iOS live P0 scenario | 通过，37 步 |
| iOS live UI E2E | 通过 |
| `kshift-ffi → Rust client → TLS gRPC → PostgreSQL` | 通过 |
| 两个项目时区 | 通过 |
| 历史映射 | 通过 |
| 冲突和静默覆盖检查 | 通过 |
| 三张当前 UI 截图 | 通过，自动重采 |

server 日志确认 live 运行包含 `create_project`、`add_project_member`、`create_task`、`update_task`、`batch_update_tasks` 和 `delete_task`。

复现命令：

```sh
make live-ui-e2e
```

脚本启动临时 PostgreSQL、迁移数据库、写入用户和 TLS auth、启动 server、写入双项目 fixture、运行 macOS/iOS P0、运行 iOS UI E2E，并重采三张截图。

## 限制

- PostgreSQL 是临时本地实例，不是部署环境。
- server 使用 loopback fixture 证书。
- macOS live P0 驱动共享 `AppModel`，不执行 macOS UI automation。
- iOS UI E2E 在模拟器运行，不在物理设备运行。
- macOS 截图使用 App 自窗口 `CGWindowListCreateImage` 运行时入口，不需要屏幕录制权限。
- 本 E2E 不在两个可见客户端中模拟人工并发冲突。
