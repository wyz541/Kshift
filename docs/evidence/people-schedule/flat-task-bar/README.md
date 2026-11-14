---
slug: /evidence/people-schedule/flat-task-bar-2026-11-14
title: 人员排期纯色任务条证据（2026-11-14）
type: report
status: review
updated: "2026-11-14"
keywords:
  - 人员排期
  - 任务条
  - 纯色
  - 扁平化
  - 视觉验收
description: 记录人员排期任务条改为纯色、扁平、单行紧凑样式的实现与验证证据。
---

# 人员排期纯色任务条证据（2026-11-14）

## 触发原因

用户再次判定视觉验收不通过。用户要求任务条改为纯色背景、扁平化并紧凑显示一行标题。

## 修复内容

- 任务条使用纯色优先级背景，不使用 Glass、渐变、模糊和阴影。
- 任务条固定为 44pt 高，标题限制为一行。
- 状态控件位于任务条前端，保留 44pt 触控区域。
- 状态选择继续使用原生 `Menu`。
- P0 使用红底白字。
- P1 使用深黄底黑字。
- P2 使用蓝底白字。
- P3 使用灰底白字。
- 任务条保留清晰边框，支持普通、悬停、键盘焦点和 Increase Contrast。
- 人员行继续使用原有密度间距，任务条单独收紧高度。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| `make swift-test` | 通过；42 项执行，2 项 live 测试跳过，0 项失败 |
| macOS Debug build | 通过 |
| iOS core controls、touch targets、large text、native status menu | 4 项通过 |
| iOS accessibility audit | 通过 |
| `./scripts/check-r0.sh` | 通过 |
| `make check-build-governance` | 通过 |
| Operations CI | 待运行 |

## 候选截图

| 文件 | 内容 | SHA-256 |
| --- | --- | --- |
| `macos-task-bar-2026-11-14.png` | macOS Dark Mode Demo 人员排期任务条 | `2630eb8166204b8edec6bb3895d22637454ce2dcd752e7b0c36d3be40d06e7a6` |
| `ios-task-bar-2026-11-14.png` | iPhone 18 Pro Simulator Light Mode 人员排期任务条 | `a1ee7e011b2b1c133c8f695ccc35a5a9437271400ad34f3bf6f21ea0814ecb39` |

## 未覆盖

- 用户视觉验收尚未完成。
- Increase Contrast 和 Reduce Transparency 截图尚未生成。
- macOS 和 iOS 人工拖拽录屏尚未生成。
- 50 人、30 日、每人 20 项任务的渲染性能尚未用 Instruments 测量。

本文件中的“通过”只表示自动检查结果。用户视觉验收通过前，Issue #42 保持打开。
