---
slug: "/docs/r4-r5/evidence/2026-11-16-network-capacity"
title: "R4/R5 network capacity evidence"
type: "evidence"
status: "review"
updated: "2026-11-16"
keywords:
  - network capacity
  - gRPC clients
  - event streams
  - load test
  - PostgreSQL
description: "记录 100 个持久 gRPC 客户端和 64 个并发事件流的 30 分钟容量证据。"
---

# R4/R5 network capacity evidence

结论：100 个持久 gRPC 客户端和 64 个并发事件流通过 30 分钟容量测试。测试没有发现连接失败、事件丢失、事件 gap、流错误或静默覆盖。

## 环境

| 项目 | 值 |
| --- | --- |
| 主机 | Apple M1 Max，64 GiB |
| macOS | 27.0.1 |
| PostgreSQL | 18.7 |
| 测试层 | loopback TCP 上的 actual Tonic gRPC server |
| 持久 gRPC 客户端 | 100 |
| 并发事件流 | 64 |
| 事件流用户 | 64 |
| 同时编辑用户 | 40 |
| 写事务上限 | 16 |
| unary RPC 上限 | 200 |
| 数据库连接上限 | 20 |
| 持续时间 | 1800.29 秒 |

## 网络容量

| 检查 | 结果 |
| --- | ---: |
| 启动时健康客户端 | 100/100 |
| 结束时健康客户端 | 100/100 |
| 启动失败 | 0 |
| 打开的网络事件流 | 64 |
| 网络事件写入 | 61 |
| 每个流的期望事件数 | 61 |
| 每个流的最小事件数 | 61 |
| 每个流的最大事件数 | 61 |
| 期望事件投递 | 3,904 |
| 实际事件投递 | 3,904 |
| event gap | 0 |
| stream error | 0 |
| unexpected stream close | 0 |
| reconnect | 0 |
| network event delay p50 | 522 ms |
| network event delay p95 | 994 ms |
| network event delay max | 1,031 ms |

64 个事件流使用 64 个不同的认证用户。每个用户只打开 1 个事件流。100 个 Tonic channel 在测试开始和结束时都完成 health check。测试持续保留这些 channel。

## 持续负载

| 检查 | 结果 |
| --- | ---: |
| 写波次 | 1,756 |
| 写尝试 | 70,240 |
| 成功写入 | 28,096 |
| `RESOURCE_EXHAUSTED` | 42,144 |
| 其他错误 | 0 |
| snapshot 突发 | 30 |
| snapshot 请求 | 6,000 |
| snapshot 失败 | 0 |
| command latency p50 | 20.39 ms |
| command latency p95 | 63.87 ms |
| command latency max | 191.46 ms |

## 写入冲突

| 检查 | 结果 |
| --- | ---: |
| 同时写尝试 | 40 |
| 成功写入 | 16 |
| `RESOURCE_EXHAUSTED` | 24 |
| 同一项目多人写尝试 | 40 |
| 冲突 | 15 |
| 成功写入 | 1 |
| 其他错误 | 0 |
| 静默覆盖 | 未发生 |

## 事件和资源

| 检查 | 结果 |
| --- | ---: |
| service API event stream | 1 |
| 期望 service API event | 1,588 |
| 收到 service API event | 1,588 |
| service API event gap | 0 |
| service API stream error | 0 |
| service API event delay p50 | 702 ms |
| service API event delay p95 | 1,002 ms |
| service API event delay max | 1,266 ms |
| CPU 平均 | 10.04% |
| CPU 峰值 | 109.9% |
| RSS 起始 | 34.33 MiB |
| RSS 5 分钟后 | 58.14 MiB |
| RSS 结束 | 148.48 MiB |
| RSS 峰值 | 148.48 MiB |
| RSS 5 分钟后增长 | 90.34 MiB |
| RSS 增长上限 | 128 MiB |
| RSS 峰值上限 | 256 MiB |
| PostgreSQL 连接峰值 | 21 |
| PostgreSQL lock waiter 峰值 | 15 |

CPU 指标来自测试进程。测试进程同时包含 load generator、direct service API 和 network server。

## 命令

```bash
export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH"
export TEST_DATABASE_URL='postgres://postgres:REDACTED@127.0.0.1:54329/postgres'
KSHIFT_LOAD_DURATION_SECS=1800 \
KSHIFT_LOAD_WAVE_INTERVAL_MS=1000 \
KSHIFT_LOAD_REPORT=/tmp/kshift-network-load-1800.json \
  ./scripts/run-load-evidence.sh
```

脚本检查 report 中的以下条件。

- 100 个持久网络客户端。
- 64 个并发网络事件流。
- 结束时全部客户端健康。
- 无 stream error、unexpected close 或 event gap。
- 期望事件投递数等于实际事件投递数。

原始 report 保存在 [2026-11-16-network-capacity.json](2026-11-16-network-capacity.json)。

## 覆盖边界

- 测试使用 loopback TCP 和明文 gRPC。测试没有使用 release TLS bundle。
- 测试使用实际 Tonic server、认证、授权、数据库和 outbox 路径。
- 测试在一个测试进程中运行 load generator 和 server。测试没有运行独立 server 安装包。
- 测试没有替代系统 LaunchDaemon、签名分发或 Stable Release 验收。
