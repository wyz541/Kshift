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

结论：R2 的 macOS 和 iOS 主页面已用当前 UI 截图。iOS live UI E2E、无障碍审计和性能读数已通过。

## 主截图

| 文件 | 平台 | 内容 |
| --- | --- | --- |
| `macos-board.png` | macOS 27.2 | 演示数据看板 |
| `macos-live-server.png` | macOS 27.2 | 真实 TLS server 数据 |
| `accessibility/ios-light.png` | iOS 27.0 Simulator | 演示数据亮色看板 |
| `accessibility/ios-dark.png` | iOS 27.0 Simulator | 演示数据深色看板 |
| `ios-live-server.png` | iOS 27.0 Simulator | 真实 TLS server 数据 |

macOS 截图只包含 Kshift 窗口。普通截图使用 Debug 演示数据；`*-live-server.png` 使用真实 TLS server 和 PostgreSQL。

## 主截图 SHA-256

| 文件 | SHA-256 |
| --- | --- |
| `macos-board.png` | `63f3f474b5cf564e44a5a6c87b35517e5873ee209f9246dfe62b4ab2a9e0b777` |
| `macos-live-server.png` | `4e5a7240d5de27c01680489fd07102a7af731cbd21bb04001f9d105b21d81cd9` |
| `ios-live-server.png` | `676bf6c840647fc590999ba067ef4a6b5cc23497b677a5db57ffe7ba1360c234` |

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
| `swift test` | 20 项执行，19 项通过，1 项 live server test 跳过 |
| macOS `xcodebuild build` | 通过 |
| iOS `xcodebuild test` | 9 项执行，8 项通过，1 项 live test 跳过 |
| iOS UI tests | 8 项执行，7 项通过，1 项 live test 在普通 verify 中跳过 |
| `make live-ui-e2e` | 通过：真实 FFI、历史、UI 写入和截图 |
| 完整无障碍审计 | 通过，2 项误报豁免 |

## 限制

| 项目 | 状态 |
| --- | --- |
| Instruments frame trace | 未采集 |
| macOS 主截图 | 当前截图对应唯一 UI |

真实 gRPC/PostgreSQL UI E2E 和截图复现方法见 [live-server.md](live-server.md)。

## 性能

性能读数见 [performance.md](performance.md)。读数是 `XCTClockMetric`，不是帧耗时。
