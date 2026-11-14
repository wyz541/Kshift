---
slug: /evidence/acceptance-v1
title: Kshift v1 验收证据
type: report
status: blocked
updated: "2026-11-14"
keywords:
  - Acceptance
  - macOS
  - iOS
  - SwiftUI
  - R3
  - People Schedule
  - accessibility
description: 记录 Kshift v1 构建、自动门禁、人工检查和最终验收阻断项。
---

# Kshift v1 验收证据

结论：当前提交的构建、自动门禁、live P0、R3、人员排期和 UI 无障碍测试通过。验收仍保持阻断。Issue #9 和开发者人工签收未完成。

## 构建身份

| 项目 | 值 |
| --- | --- |
| Commit | `c1d6bc6686be6f8fffd7d9458e75b553f4a8686a` |
| 验收时间 | 2026-11-14 16:22 至 16:52（Asia/Shanghai） |
| 主机 | `wyz的MacBook Pro`，arm64 |
| macOS | 27.0.1，Build 26A434 |
| Xcode | 27.2，Build 27B52 |
| Swift | 6.4.2 |
| Rust | 1.99.1 |
| Cargo | 1.99.1 |
| iOS Simulator | iPhone 18 Pro，iOS 27.0 |
| PostgreSQL | 18.7 |

原文见 [environment.txt](environment.txt)。

## 命令结果

| 检查 | 命令 | 结果 | 用时 | 证据 |
| --- | --- | --- | ---: | --- |
| 文档基线 | `./scripts/check-r0.sh` | 通过 | < 10 s | [日志](logs/check-r0.log) |
| macOS 构建 | `make mac-build` | 通过 | 31.15 s | [日志](logs/mac-build.log) |
| iOS 构建 | `make ios-build` | 通过 | 23.56 s | [日志](logs/ios-build.log) |
| 构建路径 | `make app-paths` | 两个 App 均为 `present` | < 1 s | [日志](logs/app-paths.log) |
| 构建治理 | `make check-build-governance` | 通过 | < 1 s | [日志](logs/build-governance.log) |
| Rust 与 Swift 门禁 | `make test` | 通过 | 47.85 s | [日志](logs/make-test.log) |
| iOS Xcode 测试 | `make ios-test` | 通过 | 250.97 s | [日志](logs/ios-test.log) |
| Live UI E2E | `scripts/run-live-ui-e2e.sh` 临时副本 | 通过 | 95.63 s | [日志](logs/live-ui-run.log) |
| iOS 无障碍截图 | `scripts/capture-accessibility-evidence.sh` 临时副本 | 6 张截图完成 | 36.04 s | [日志](logs/accessibility-capture.log) |

Live UI 临时副本只移除原有脚本末尾的三处证据复制。测试、server、fixture 和截图步骤不变。这样不改写既有 `docs/evidence` 文件。

固定 App 路径如下。

| 平台 | 路径 | 状态 |
| --- | --- | --- |
| macOS | `build/DerivedData/Build/Products/Debug/Kshift-macOS.app` | `present` |
| iOS | `build/DerivedData/Build/Products/Debug-iphonesimulator/Kshift-iOS.app` | `present` |

两个 App 的 Debug 显示名均为 `Kshift Dev`。Bundle identifier 分别为 `com.wyz541.kshift.mac` 和 `com.wyz541.kshift.ios`。`/Applications` 和 `~/Applications` 没有 Kshift App 或 Test Runner。

## 测试计数

| 范围 | 结果 |
| --- | --- |
| Rust workspace | 57 项通过 |
| Swift package | 46 项执行，44 项通过，2 项 live-only 测试跳过 |
| iOS unit tests | 2 项执行，1 项通过，1 项 live-only 测试跳过 |
| iOS UI tests | 12 项执行，11 项通过，1 项 live-only 测试跳过 |
| Live macOS P0 | 37 步通过 |
| Live iOS P0 | 37 步通过 |
| Live iOS UI write | 通过 |

Live P0 的 37 个步骤见 [macos-p0-report.json](data/macos-p0-report.json)。server 日志包含 `create_project`、`add_project_member`、`create_task`、`update_task`、`batch_update_tasks` 和 `delete_task`。

## 验收矩阵

| 场景 | 步骤 | 预期 | 实际 | 结论 |
| --- | --- | --- | --- | --- |
| 构建身份 | 记录 commit、系统、Xcode、Swift、Rust 和构建时间 | 两个平台使用同一个 commit | 两个平台都使用 `c1d6bc6` | 通过 |
| macOS 构建 | 运行 `make mac-build` | 构建成功，产物位于固定路径 | 构建成功，产物存在 | 通过 |
| iOS 构建 | 运行 `make ios-build` | 构建成功，产物位于固定路径 | 构建成功，产物存在 | 通过 |
| 构建治理 | 运行 `make app-paths` 和 `make check-build-governance` | Debug 名称为 `Kshift Dev`；App 和 Test Runner 不进入 Applications | 两个条件都满足；治理检查通过 | 通过 |
| macOS P0 人工流程 | 启动 App，切换项目，创建、编辑、搜索、筛选、排序，打开任务详情 | 操作可用；状态正确；冲突不会静默覆盖 | 人工创建和编辑通过，revision 8 → 10；Live P0 37 步通过；冲突和删除由 live P0 验证 | 通过 |
| R3 人工流程 | 打开计划深度，检查看板、甘特、历史、报告、Markdown 和附件 | 功能可发现；数据一致；报告与 source revision 一致 | 看板、甘特、历史、报告和附件可打开；状态计数为 7 项，报告使用 r7 | 通过 |
| 人员排期人工流程 | 打开默认人员排期，检查人员行、泳道、周/月切换、设置和任务 | 人员排期可发现；交互和数据一致 | 默认人员排期可打开；周/月、今天、密度、设置和任务可访问 | 通过 |
| iOS P0 和 R3 | 在 Simulator 执行 live P0、UI 写入和 R3 专项场景 | 业务结果和错误语义与 macOS 一致 | Live iOS P0 37 步、iOS UI 写入和 R3 UI test 通过 | 通过 |
| 视觉与无障碍 | 检查 Liquid Glass、Dark Mode、大号文字、Increase Contrast、Reduce Transparency、Reduce Motion 和触控目标 | 文字无裁切；核心操作可用；审计通过 | 6 张截图完成；R2/P0、人员排期和 R3 的无障碍审计通过；精确 SwiftUI 误报已记录 | 通过 |
| Release 前置条件 | 检查 Issue #9 的发布与运维验收 | 全部 Release 前置条件完成 | #9 仍为 Open；签名、30 分钟负载、远端 Release 和最终发布资产未完成 | 失败 |
| 开发者结论 | 填写全部结果、截图、阻断问题和最终结论 | 有证据；失败项进入 Issue；未运行项已标记 | AI 辅助验收完成；没有开发者人工签收 | 失败 |

## 人工检查记录

| 时间 | 执行者 | 操作 | 结果 |
| --- | --- | --- | --- |
| 2026-11-14 16:44 | Codex，Accessibility UI | 打开默认人员排期，检查人员行、日期、密度和设置 | 通过 |
| 2026-11-14 16:44 | Codex，Accessibility UI | 打开计划深度，核对看板状态统计 | 通过：7 项中 1 项完成 |
| 2026-11-14 16:44 | Codex，Accessibility UI | 切换甘特、历史并生成报告 | 通过：报告来源为 r7 |
| 2026-11-14 16:50 | Codex，Accessibility UI | 新建 `Acceptance final task` | 通过：revision 8 → 9 |
| 2026-11-14 16:50 | Codex，Accessibility UI | 编辑任务状态为“进行中” | 通过：revision 9 → 10，任务版本 1 → 2 |
| 2026-11-14 16:50 | Codex，Accessibility UI | 打开任务详情 | 通过 |

## 截图

| 文件 | 内容 |
| --- | --- |
| [macos-board.png](screenshots/macos-board.png) | macOS 演示数据看板 |
| [macos-live-server.png](screenshots/macos-live-server.png) | macOS 真实 TLS gRPC 和 PostgreSQL 数据 |
| [macos-people-schedule.png](screenshots/macos-people-schedule.png) | macOS 默认人员排期 |
| [macos-new-task-sheet.png](screenshots/macos-new-task-sheet.png) | macOS 新建任务 Sheet |
| [macos-edit-task-sheet.png](screenshots/macos-edit-task-sheet.png) | macOS 编辑任务 Sheet |
| [macos-task-detail-sheet.png](screenshots/macos-task-detail-sheet.png) | macOS 任务详情 Sheet |
| [r3-board.png](screenshots/r3-board.png) | R3 计划看板，状态统计已修复 |
| [r3-gantt.png](screenshots/r3-gantt.png) | R3 甘特 |
| [r3-history.png](screenshots/r3-history.png) | R3 历史与回退 |
| [r3-report.png](screenshots/r3-report.png) | R3 报告 |
| [r3-task-detail.png](screenshots/r3-task-detail.png) | R3 Markdown 和附件详情 |
| [ios-live-server.png](screenshots/ios-live-server.png) | iOS 真实 TLS gRPC 和 PostgreSQL 数据 |
| [ios-light.png](screenshots/ios-light.png) | iOS 亮色人员排期 |
| [ios-dark.png](screenshots/ios-dark.png) | iOS 深色人员排期 |
| [ios-increase-contrast.png](screenshots/ios-increase-contrast.png) | iOS Increase Contrast |
| [ios-large-text.png](screenshots/ios-large-text.png) | iOS Accessibility XXXL |
| [ios-reduce-transparency.png](screenshots/ios-reduce-transparency.png) | iOS Reduce Transparency |
| [ios-reduce-motion.png](screenshots/ios-reduce-motion.png) | iOS Reduce Motion |

## 关键截图 SHA-256

| 文件 | SHA-256 |
| --- | --- |
| `macos-live-server.png` | `58923b7a22463af152efbf569dcefb7175d054e5d622398e35ff0193c6c62045` |
| `ios-live-server.png` | `3a6663c56588552418582cbe90266c6ffe3cf8277e4e7b655c0259e66da543bb` |
| `macos-people-schedule.png` | `9b92c1f92385097e07940cf663eaf334c7ade0cac6d8d362e9fe8913948f2209` |
| `r3-board.png` | `c0adfc531eb4cd3a7aef393480fe13ade17066afeeb4ff8ed44b9ef2948ac1e6` |
| `r3-report.png` | `0d75cd4a83a0f881c5ae9659ad998ea288c2e728075a05eee3a841d1a248383e` |
| `ios-light.png` | `68ef31b68b932d6969e59a2dd068ad028a0ae7d3d8cfaf591eefffda5d90edbe` |
| `ios-large-text.png` | `f5af60339ce257e3a9807cf0a89c1047071beb39a085f0bc2dc532d534f0986e` |

完整清单见 [SHA256SUMS](SHA256SUMS)。

## 已关闭的验收阻断

| Issue | 修复 PR |
| --- | --- |
| #43 iOS 新增按钮重叠 | #61 |
| #45 构建治理 | #58 |
| #51 完整无障碍审计 | #62 |
| #52 R3 状态计数 | #60 |
| #53 migration 增量构建 | #59 |
| #63 iOS live 卡片点击测试 | #64 |

## 当前阻断问题

| Issue | 状态 | 阻断内容 |
| --- | --- | --- |
| #9 | Open | R4-R5 交付和最终 Release 验收未完成 |
| 开发者人工签收 | 未完成 | 本记录是 AI 辅助验收，不替代开发者最终结论 |

Issue #9 的已记录外部前置项包括签名和分发决策、30 分钟负载、真实 launchd 重启、远端 Release、不可变发布和干净机器安装证据。

## 未运行项

| 项目 | 原因 | 后续入口 |
| --- | --- | --- |
| 最终 Release 资产验收 | #9 未关闭 | #9 |
| 30 分钟 2 倍负载 | 当前任务只执行验收；需要发布环境窗口 | #9 |
| 真实 LaunchDaemon 安装与重启 | 需要目标 host 和审批 | #9 |
| 签名、公证和远端 attestation | 需要签名身份和 GitHub environment | #9 |
| 开发者人工签收 | 需要开发者本人完成 | #39 |

## 结论

**失败。**

本地构建、P0、R3、人员排期和 UI 无障碍门禁通过。Issue #39 仍不能关闭。关闭 #39 前，必须关闭 #9，并完成开发者人工签收。
