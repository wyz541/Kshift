---
slug: "/docs/r4-r5/evidence/2026-11-14-load-restart"
title: "R4/R5 load and restart evidence"
type: "evidence"
status: "review"
updated: "2026-11-14"
keywords:
  - load test
  - restart
  - outbox
  - concurrency
description: "记录 R4/R5 的目标并发冒烟测试和 API 重启恢复测试。"
---

# R4/R5 load and restart evidence

## 结果

| 检查 | 观测结果 | 判定 |
| --- | --- | --- |
| 2 倍目标并发冒烟测试 | 40 个编辑器、100 次并发 snapshot、16 个并发写事务上限 | 通过 |
| 1 秒持续运行 | 840 次写入、0 个失败 | 通过 |
| API 重启后的 outbox 回放 | revision 2 和 revision 3 连续回放 | 通过 |
| 重启后的数据完整性和新写入 | snapshot revision 3，任务数为 2 | 通过 |
| Rust workspace tests | 38 个通过 | 通过 |
| 30 分钟持续负载 | 未运行 | 未通过验收 |

## 命令

```bash
export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH"
export TEST_DATABASE_URL='postgres://postgres:REDACTED@127.0.0.1:55432/postgres'
./scripts/run-load-evidence.sh
```

完整 30 分钟负载使用以下命令。

```bash
KSHIFT_LOAD_DURATION_SECS=1800 ./scripts/run-load-evidence.sh
```

## 覆盖边界

- 当前结果来自 PostgreSQL 18 测试数据库。
- 当前结果来自 service API 层。
- `launchd` 进程级重启和真实两台客户端连接尚未运行。
- 没有将 1 秒冒烟结果写成 30 分钟验收通过。
