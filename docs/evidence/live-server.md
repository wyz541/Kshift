---
slug: /evidence/live-server
title: 真实服务端 E2E
type: report
status: review
updated: "2026-11-13"
keywords:
  - gRPC
  - PostgreSQL
  - TLS
  - E2E
  - FFI
description: 记录 iOS 和 macOS App 通过真实 TLS gRPC server 读取和写入 PostgreSQL 的证据。
---

# 真实服务端 E2E

结论：iOS UI 已通过真实 TLS gRPC server 读取历史、写入任务并刷新 snapshot。macOS App 已从同一 live server 重新采集截图。

## 环境

| 项目 | 值 |
| --- | --- |
| 日期 | 2026-11-13 |
| PostgreSQL | PostgreSQL 18，临时 Docker 实例 |
| PostgreSQL 端口 | `54329` |
| server | `kshift-server serve` |
| server 端口 | 脚本选择空闲 loopback 端口 |
| TLS | `fixtures/tls` 的 loopback 证书 |
| 用户 | `Mia Chen` |
| 项目 | `Live Kshift` |
| token | `live-ui-e2e-token`，只用于本地测试 |

## 数据

初始化程序通过 `kshift-ffi` 写入：

- 1 个项目：`Live Kshift`
- 2 个初始任务：`Live history task`、`Review live audit`
- 1 个 `update_task` 命令：将 `Live history task` 标为 `done`
- 1 个原子 `batch_update_tasks` 命令：更新两个任务的状态
- iOS UI E2E 再创建 1 个任务：`Live UI created task`

截图：

- [iOS live server](ios-live-server.png)
- [macOS live server](macos-live-server.png)

iOS 截图在 UI 写入前采集。截图显示 2 个任务、revision 5。macOS 截图在 UI 写入后采集。截图显示 3 个任务、revision 6。

## 验证

| 检查 | 结果 |
| --- | --- |
| `make live-ui-e2e` | 通过 |
| `kshift-ffi → Rust client → TLS gRPC → PostgreSQL` | 通过 |
| Fixture snapshot | 6 条项目审计，3 条目标任务历史 |
| iOS task history UI | 通过 |
| iOS UI 创建任务 | 通过，snapshot revision 从 5 升到 6 |
| iOS live screenshot | 通过，XCTest attachment |
| macOS demo screenshot | 通过，App 自窗口捕获 |
| macOS live screenshot | 通过，App 自窗口捕获 |

复现命令：

```sh
make live-ui-e2e
```

脚本启动临时 PostgreSQL、迁移数据库、写入用户和 TLS auth、启动 server、运行 fixture、执行 iOS UI E2E，并重采三张截图。

## 限制

- PostgreSQL 是临时本地实例，不是部署环境。
- server 使用 loopback fixture 证书。
- macOS 截图使用 App 自窗口 `CGWindowListCreateImage` 运行时入口，不需要屏幕录制权限。
- 多人并发冲突仍由自动测试覆盖，不在本 E2E 中模拟两个可见客户端。
