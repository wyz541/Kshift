---
slug: "/docs/r4-r5/evidence/2026-11-14-load-restart"
title: "R4/R5 service 2x load and restart evidence"
type: "evidence"
status: "review"
updated: "2026-11-14"
keywords:
  - load test
  - restart
  - outbox
  - concurrency
  - PostgreSQL
description: "记录 R4/R5 服务层 30 分钟 2 倍负载、多人写入和 API 重启证据。"
---

# R4/R5 service 2x load and restart evidence

结论：30 分钟服务层 2 倍负载通过。饱和写入返回有界错误。多人冲突没有静默覆盖。事件流无丢失。API 重启后 outbox 可回放。

## 环境

| 项目 | 值 |
| --- | --- |
| 主机 | Apple M1 Max，64 GiB |
| macOS | 27.0.1 |
| PostgreSQL | 18.7 |
| 测试层 | `KshiftApi` service API |
| 编辑器 | 40 |
| 写事务上限 | 16 |
| unary RPC 上限 | 200 |
| event stream 上限 | 64 |
| 数据库连接上限 | 20 |
| 持续时间 | 1801.14 秒 |

## 饱和写入

| 检查 | 结果 |
| --- | ---: |
| 同时写尝试 | 40 |
| 成功写入 | 16 |
| `RESOURCE_EXHAUSTED` | 24 |
| 其他错误 | 0 |
| 测试方法 | 锁定 `kshift.project`，让 16 个写事务保持占用 |

## 多人冲突

| 检查 | 结果 |
| --- | ---: |
| 同一项目同时写尝试 | 40 |
| 成功写入 | 1 |
| revision conflict | 15 |
| `RESOURCE_EXHAUSTED` | 24 |
| 其他错误 | 0 |
| 最终 snapshot revision | 42 |
| 最终 task 数 | 1 |
| 静默覆盖 | 未发生 |

## 持续负载

| 检查 | 结果 |
| --- | ---: |
| 写波次 | 1757 |
| 写尝试 | 70,280 |
| 成功写入 | 28,112 |
| `RESOURCE_EXHAUSTED` | 42,168 |
| 其他错误 | 0 |
| snapshot 突发 | 30 |
| snapshot 请求 | 6,000 |
| snapshot 失败 | 0 |
| command latency p50 | 26.38 ms |
| command latency p95 | 70.96 ms |
| command latency max | 698.92 ms |

快照突发每 60 个写波次执行一次。快照突发需要额外时间，因此写波次少于 1800。

## 事件和资源

| 检查 | 结果 |
| --- | ---: |
| event stream | 1 |
| 预期事件 | 1573 |
| 收到事件 | 1573 |
| event gap | 0 |
| event stream error | 0 |
| reconnect | 0 |
| event delay p50 | 452 ms |
| event delay p95 | 1,001 ms |
| event delay max | 1,567 ms |
| CPU 平均 | 3.72% |
| CPU 峰值 | 99.4% |
| RSS 起始 | 16.72 MiB |
| RSS 5 分钟后 | 39.69 MiB |
| RSS 5 分钟后增长 | 83.00 MiB |
| RSS 结束 | 122.69 MiB |
| RSS 增长 | 105.97 MiB |
| RSS 峰值 | 122.69 MiB |
| PostgreSQL 连接峰值 | 21 |
| PostgreSQL lock waiter 峰值 | 14 |

RSS 在 5 分钟后的增长上限为 128 MiB。RSS 峰值上限为 256 MiB。本次结果低于两个上限。PostgreSQL 连接峰值包含 1 个监控查询连接。

## API 重启

| 检查 | 结果 |
| --- | --- |
| 重启前 outbox 事件 | revision 2 |
| 重启后回放 | revision 2 |
| 重启后新写入 | revision 3 |
| 重启后 snapshot | revision 3，2 个 task |

## 验证

| 检查 | 结果 |
| --- | --- |
| Rust workspace tests | 56 个通过 |
| Python ops tests | 16 个通过 |
| Release contract tests | 11 个通过 |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings` | 通过 |
| `scripts/check-r0.sh` | 通过 |
| `scripts/check-r4-r5.sh` | 通过 |
| `actionlint` | 通过 |
| `buf lint` | 通过 |

## 命令

```bash
export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH"
export TEST_DATABASE_URL='postgres://postgres:REDACTED@127.0.0.1:55432/postgres'
KSHIFT_LOAD_DURATION_SECS=1800 \
KSHIFT_LOAD_WAVE_INTERVAL_MS=1000 \
  ./scripts/run-load-evidence.sh
```

```bash
cargo test --locked -p kshift-server --test restart_integration
```

## 覆盖边界

- 测试在 service API 层运行。测试没有建立 100 个持久网络客户端。
- 测试保持 1 个事件流。测试没有同时保持 64 个事件流。
- CPU 和 RSS 来自测试进程。测试进程包含 load generator 和 API service。
- 测试没有测量已安装 release server 的 CPU 和 RSS。
- 当前结果不替代系统 LaunchDaemon、签名分发或 Stable Release 验收。
