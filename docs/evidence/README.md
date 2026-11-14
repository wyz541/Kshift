---
slug: /evidence
title: R2 证据
type: report
status: review
updated: "2026-11-14"
keywords:
  - R2
  - 截图
  - 无障碍
  - 性能
  - 证据
description: 汇总 R2 的截图、自动门禁、性能读数和剩余限制。
---

# R2 证据

结论：R2 的 macOS 和 iOS 主页面已用当前 UI 重采截图。macOS/iOS live P0、iOS live UI E2E、无障碍审计和性能读数已通过。

## 主截图

| 文件 | 平台 | 内容 |
| --- | --- | --- |
| `macos-board.png` | macOS 27.2 | 演示数据看板 |
| `macos-live-server.png` | macOS 27.2 | 真实 TLS server 数据 |
| `accessibility/ios-light.png` | iOS 27.0 Simulator | 演示数据亮色看板 |
| `accessibility/ios-dark.png` | iOS 27.0 Simulator | 演示数据深色看板 |
| `ios-live-server.png` | iOS 27.0 Simulator | 真实 TLS server 数据 |

macOS 截图只包含 Kshift 窗口。三张主截图均在 2026-11-14 由当前 UI 重采。`macos-board.png` 使用 Debug 演示数据；`*-live-server.png` 使用真实 TLS server 和 PostgreSQL。

## 主截图 SHA-256

| 文件 | SHA-256 |
| --- | --- |
| `macos-board.png` | `8b31b4d752e07244c83e7b35b9a0859062a90a47e95e8c450d2132c68697b904` |
| `macos-live-server.png` | `b2f95f8bf2cd3d2ea5c119ab4edd9ee799828ac0d0676bad736144de038bd3fb` |
| `ios-live-server.png` | `aac7f72ac757eae8209aa5014a3b2b27f1f2664217e3041e37c9df095fc80465` |

## 无障碍截图

| 文件 | 状态 |
| --- | --- |
| `accessibility/ios-increase-contrast.png` | Increase Contrast 已启用 |
| `accessibility/ios-large-text.png` | Accessibility Extra Extra Extra Large |
| `accessibility/ios-reduce-motion.png` | Reduce Motion 已启用 |
| `accessibility/ios-reduce-transparency.png` | 应用环境覆盖已启用 |

Reduce Transparency 的验证方法见 [Accessibility evidence](accessibility/README.md)。该截图证明 UI 降级分支可执行。该截图不证明模拟器系统设置入口存在。

## 已运行门禁

| 检查 | 结果 |
| --- | --- |
| `cargo fmt --all -- --check` | 通过 |
| `cargo clippy --offline --workspace --all-targets -- -D warnings` | 通过 |
| `cargo test --offline --workspace` | 36 项通过 |
| `swift test` | 25 项执行，23 项通过，2 项 live test 跳过 |
| macOS `xcodebuild build` | 通过 |
| iOS 单元测试 | 2 项执行，1 项通过，1 项 live P0 跳过 |
| iOS UI tests | 8 项执行，7 项通过，1 项 live UI 测试在普通 verify 中跳过 |
| `make live-ui-e2e` | 通过：macOS/iOS live P0、iOS UI 写入、历史和截图 |
| 完整无障碍审计 | 通过，2 项误报豁免 |

## 限制

| 项目 | 状态 |
| --- | --- |
| Instruments frame trace | 未采集 |
| macOS 主截图 | 当前截图对应唯一 UI |

真实 gRPC/PostgreSQL UI E2E 和截图复现方法见 [live-server.md](live-server.md)。

## 性能

性能读数见 [performance.md](performance.md)。读数是 `XCTClockMetric`，不是帧耗时。

## v1 验收

| 项目 | 入口 |
| --- | --- |
| Kshift v1 构建与人工验收 | [acceptance-v1](acceptance-v1/README.md) |

v1 验收当前为失败。阻断项见验收报告。
