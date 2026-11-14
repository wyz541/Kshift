---
slug: "/docs/r4-r5/evidence/2026-11-14-launchd-restart"
title: "R4/R5 Kshift server LaunchAgent restart evidence"
type: "evidence"
status: "review"
updated: "2026-11-14"
keywords:
  - launchd
  - LaunchAgent
  - restart
  - TLS
  - outbox
description: "记录 Kshift release bundle 在临时 PostgreSQL、TLS 和 LaunchAgent 环境中的崩溃重启测试。"
---

# R4/R5 Kshift server LaunchAgent restart evidence

结论：Kshift server release bundle 可由 LaunchAgent 启动。server 被强制终止后，LaunchAgent 自动重启 server。健康检查、outbox 回放和新写入通过。

| 检查 | 结果 |
| --- | --- |
| 测试环境 | PostgreSQL 18 临时数据库、TLS 证书、受限 auth 文件 |
| server bundle | `release/platform/build-server.sh` 生成 |
| 启动入口 | `kshift-server-run` |
| 监管方式 | 用户 LaunchAgent |
| 首次健康检查 | `SERVING` |
| 重启触发 | `SIGKILL` |
| 启动次数 | 2 |
| PID | `99356` → `99386` |
| 重启前 snapshot | revision 2，1 个 task |
| 重启后 outbox 回放 | revision 2 |
| 重启后新写入 | revision 3 |
| 重启后 snapshot | revision 3，2 个 task |
| 重启后健康检查 | `SERVING` |

## 命令

```bash
export TEST_DATABASE_URL='postgres://postgres:REDACTED@127.0.0.1:55432/postgres'
./scripts/test-server-launchd-restart.sh
```

## 测试步骤

1. 创建临时 PostgreSQL 数据库。
2. 生成临时 CA、server 证书、auth 文件和 TLS 配置。
3. 构建 release server bundle。
4. 通过 LaunchAgent 启动 `kshift-server-run`。
5. 验证 gRPC health 和 revision 2 snapshot。
6. 使用 `SIGKILL` 终止 server 进程。
7. 等待 LaunchAgent 启动新 PID。
8. 验证 gRPC health。
9. 验证 revision 2 outbox 事件回放。
10. 写入 revision 3 task。
11. 验证 revision 3 snapshot 包含 2 个 task。

## 覆盖边界

- 测试使用用户 LaunchAgent，不使用系统 LaunchDaemon。
- 生产 LaunchDaemon 需要 root 安装和独立服务用户。
- 测试证书是临时自签名证书，不是 Apple 签名分发证书。
- 测试强制终止 server。正常 `SIGTERM` 会触发 graceful shutdown，不触发 `SuccessfulExit=false` 重启。
