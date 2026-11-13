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

结论：iOS 和 macOS App 已通过真实 TLS gRPC server 读取 PostgreSQL 数据。批量状态命令也已通过 service integration test。

## 环境

| 项目 | 值 |
| --- | --- |
| 日期 | 2026-11-13 |
| PostgreSQL | 18.6，临时本地实例 |
| PostgreSQL 端口 | `55432` |
| server | `kshift-server serve` |
| server 端口 | `7443` |
| TLS | `fixtures/tls` 的 loopback 证书 |
| 用户 | `Mia Chen` |
| 项目 | `Live Kshift` |
| token | `live-token`，只用于本地测试 |

## 数据

初始化程序通过 `kshift-ffi` 写入：

- 1 个项目：`Live Kshift`
- 3 个任务：`Publish release draft`、`Review accessibility`、`Send launch brief`
- 1 个原子 `batch_update_tasks` 命令，将前 2 个任务标记为 `done`

截图：

- [iOS live server](ios-live-server.png)
- [macOS live server](macos-live-server.png)

iOS 和 macOS 截图都显示 `Live Kshift`、3 个任务、2 个已完成任务和 revision 5。

## 验证

| 检查 | 结果 |
| --- | --- |
| `cargo test --offline -p kshift-server --test service_integration` | 8 项通过 |
| `kshift-ffi → Rust client → TLS gRPC → PostgreSQL` | 通过 |
| iOS App 读取 live snapshot | 通过 |
| macOS App 读取 live snapshot | 通过 |
| 真实 server 批量状态写入 | 通过 |

## 限制

- PostgreSQL 是临时本地实例，不是部署环境。
- server 使用 loopback fixture 证书。
- 截图只证明读取和已有写入结果。多人并发冲突由自动测试覆盖。
