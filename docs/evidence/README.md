---
slug: /evidence
title: R2 证据
type: report
status: review
updated: "2026-11-13"
keywords:
  - R2
  - 截图
  - 无障碍
  - 性能
  - 证据
description: 汇总 R2 的截图、自动门禁、性能读数和剩余限制。
---

# R2 证据

结论：R2 的 macOS 和 iOS 主页面已截图。iOS 自动测试、无障碍审计和性能读数已通过。

## 主截图

| 文件 | 平台 | 内容 |
| --- | --- | --- |
| `macos-board.png` | macOS 27.2 | 演示数据看板 |
| `macos-live-server.png` | macOS 27.2 | 真实 TLS server 数据 |
| `accessibility/ios-light.png` | iOS 27.0 Simulator | 演示数据亮色看板 |
| `accessibility/ios-dark.png` | iOS 27.0 Simulator | 演示数据深色看板 |
| `ios-live-server.png` | iOS 27.0 Simulator | 真实 TLS server 数据 |

macOS 截图只包含 Kshift 窗口。普通截图使用 Debug 演示数据；`*-live-server.png` 使用真实 TLS server 和 PostgreSQL。

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
| `cargo test --offline --workspace` | 32 项通过 |
| `swift test` | 21 项执行，20 项通过，1 项 live server test 跳过 |
| macOS `xcodebuild build` | 通过 |
| iOS `xcodebuild test` | 8 项通过 |
| iOS UI tests | 7 项通过 |
| 完整无障碍审计 | 通过，2 项误报豁免 |

## 限制

| 项目 | 状态 |
| --- | --- |
| 真实 gRPC/PostgreSQL UI E2E | 已采集，见 [live-server.md](live-server.md) |
| Instruments frame trace | 未采集 |
| macOS 主截图 | 当前截图来自旧 UI |

## 性能

性能读数见 [performance.md](performance.md)。读数是 `XCTClockMetric`，不是帧耗时。
