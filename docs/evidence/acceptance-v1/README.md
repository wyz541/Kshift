---
slug: /evidence/acceptance-v1
title: Kshift v1 验收证据
type: report
status: failed
updated: "2026-11-14"
keywords:
  - Acceptance
  - macOS
  - iOS
  - SwiftUI
  - R3
  - accessibility
description: 记录 Kshift v1 Debug App 构建、自动门禁、人工检查和验收阻断项。
---

# Kshift v1 验收证据

结论：当前提交的两个 Debug App 可以构建。P0 live E2E 和 R3 专项 UI 测试通过。验收失败。构建治理、完整 UI 门禁、R3 数据一致性和开发者人工签收没有通过。

## 构建身份

| 项目 | 值 |
| --- | --- |
| Commit | `d964c115662f4d7604960cff96c587a1db1e38b9` |
| 验收时间 | 2026-11-14 14:29 至 14:54（Asia/Shanghai） |
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
| 文档基线 | `./scripts/check-r0.sh` | 通过 | 3.79 s | [日志](logs/check-r0.log) |
| macOS 构建 | `make mac-build` | 通过 | 42.87 s | [日志](logs/mac-build.log) |
| iOS 构建 | `make ios-build` | 通过 | 41.70 s | [日志](logs/ios-build.log) |
| 构建路径 | `make app-paths` | 两个 App 均为 `present` | < 1 s | [日志](logs/app-paths.log) |
| 构建治理 | `make check-build-governance` | 失败 | < 1 s | [日志](logs/build-governance.log) |
| Rust 与 Swift 门禁 | `make test` | 失败；Rust 和 Swift 测试通过，治理检查失败 | 38.92 s | [日志](logs/make-test.log) |
| R3 PostgreSQL | `./scripts/test-plan-store.sh` | 通过 | 3.78 s | [日志](logs/test-plan-store.log) |
| iOS Xcode 测试 | `make ios-test`，clean DerivedData | 失败；1 项无障碍审计失败 | 272.97 s | [日志](logs/ios-test.log) |
| Live P0 E2E | `scripts/run-live-ui-e2e.sh` 临时副本 | 通过 | 132.56 s | [日志](logs/live-ui-run.log) |
| 增量构建失败 | 同一 live 脚本，旧 `kshift-server` 构建 | 失败，见 #53 | 7.00 s | [日志](logs/live-ui-incremental-build-failure.log) |
| iOS 无障碍截图 | `scripts/capture-accessibility-evidence.sh` 临时副本 | 6 张截图完成 | 37.98 s | [日志](logs/accessibility-capture.log) |

Live UI 临时副本只移除原有脚本末尾的三处证据复制。测试、server、fixture 和截图步骤不变。这样不改写既有 `docs/evidence` 文件。

固定 App 路径如下。

| 平台 | 路径 | 状态 |
| --- | --- | --- |
| macOS | `build/DerivedData/Build/Products/Debug/Kshift-macOS.app` | `present` |
| iOS | `build/DerivedData/Build/Products/Debug-iphonesimulator/Kshift-iOS.app` | `present` |

两个 App 的 Debug 显示名均为 `Kshift Dev`。Bundle identifier 分别为 `com.wyz541.kshift.mac` 和 `com.wyz541.kshift.ios`。`/Applications` 和 `~/Applications` 没有 Kshift App 或 Test Runner。

构建治理失败原文：

```text
ERROR: README.md:265: xcodebuild command has no -derivedDataPath
make: *** [check-build-governance] Error 1
```

## 测试计数

| 范围 | 结果 |
| --- | --- |
| Rust workspace | 51 项通过 |
| Swift package | 25 项执行，23 项通过，2 项 live-only 测试跳过 |
| Adapter boundary | 4 项通过 |
| R3 PostgreSQL | 1 项通过 |
| iOS unit tests | 2 项执行，1 项通过，1 项 live-only 测试跳过 |
| iOS UI tests | 8 项执行，6 项通过，1 项跳过，1 项失败 |
| R3 iOS UI test | 1 项通过 |
| Live macOS P0 | 37 步通过 |
| Live iOS P0 | 37 步通过 |
| Live iOS UI write | 通过 |

完整 UI 门禁失败项：

```text
Contrast failed for SwiftUI.AccessibilityNode [Done item]
Dynamic Type font sizes are partially unsupported [Mia Chen]
Dynamic Type font sizes are partially unsupported [添加任务]
Dynamic Type font sizes are partially unsupported [1 项]
Dynamic Type font sizes are partially unsupported [2 项]
```

Live P0 的 37 个步骤见 [macos-p0-report.json](data/macos-p0-report.json)。server 日志包含 `create_project`、`add_project_member`、`create_task`、`update_task`、`batch_update_tasks` 和 `delete_task`。

## 验收矩阵

| 场景 | 步骤 | 预期 | 实际 | 结论 |
| --- | --- | --- | --- | --- |
| 构建身份 | 记录 commit、系统、Xcode、Swift、Rust 和构建时间 | 两个平台使用同一个 commit | 两个平台都使用 `d964c11` | 通过 |
| macOS 构建 | 运行 `make mac-build` | 构建成功，产物位于固定路径 | 构建成功，产物存在 | 通过 |
| iOS 构建 | 运行 `make ios-build` | 构建成功，产物位于固定路径 | 构建成功，产物存在 | 通过 |
| 构建治理 | 运行 `make app-paths` 和 `make check-build-governance` | Debug 名称为 `Kshift Dev`；App 和 Test Runner 不进入 Applications；治理检查通过 | App 名、Bundle ID 和路径符合要求；治理检查失败，见 #45 | 失败 |
| macOS P0 人工流程 | 启动 App，切换项目，创建、编辑、搜索、筛选、排序，打开任务详情 | 操作可用；状态正确；冲突不会静默覆盖 | 当前 Debug App 完成创建和编辑；revision 从 8 增至 10；搜索、筛选、排序和项目切换可用。Live P0 37 步通过。指针拖拽、删除和冲突未完成人工复验 | 部分通过，验收失败 |
| R3 人工流程 | 打开计划深度，检查子任务、依赖、甘特、历史、附件和报告 | 功能可发现；数据一致；结果和 source revision 一致 | 入口、看板、甘特、历史、报告、Markdown 和附件可打开；报告使用 r7。看板状态计数与顶部进度和报告不一致，见 #52 | 失败 |
| 人员排期人工流程 | 打开默认人员排期，检查人员行、泳道、周/月切换、搜索筛选、拖拽和位置恢复 | 人员排期可发现；交互和数据一致 | 主分支只有看板、日历和表格。#42 未交付 | 失败 |
| iOS P0 人工流程 | 在 Simulator 执行同一组 P0 和 R3 场景 | 业务结果和错误语义与 macOS 一致 | Live iOS P0、iOS UI 写入和 R3 XCUITest 通过；完整无障碍审计失败；独立人工 P0 和 R3 未运行 | 失败 |
| 视觉与无障碍 | 检查亮色、深色、Increase Contrast、大号文字、Reduce Transparency、Reduce Motion 和触控目标 | 文字不裁切；核心操作可用；审计通过 | 6 张当前提交截图完成。浮动新增按钮覆盖列内新增按钮，见 #43；完整审计失败，见 #51 | 失败 |
| 开发者结论 | 填写全部结果、截图、阻断问题和最终结论 | 有证据；失败项进入 Issue；未运行项已标记 | AI 辅助验收已完成；没有开发者人工签收 | 失败 |

## 人工检查记录

| 时间 | 执行者 | 操作 | 结果 |
| --- | --- | --- | --- |
| 2026-11-14 14:42 | Codex，Accessibility UI | 打开“计划深度” | 通过 |
| 2026-11-14 14:42 | Codex，Accessibility UI | 切换看板、甘特、历史、报告 | 通过 |
| 2026-11-14 14:42 | Codex，Accessibility UI | 生成报告并核对 source revision r7 | 通过 |
| 2026-11-14 14:42 | Codex，Accessibility UI | 核对看板完成数 | 失败：顶部和报告为 1，状态行为 0 |
| 2026-11-14 14:42 | Codex，Accessibility UI | 打开任务详情，检查 Markdown 和附件 | 通过：`r3-acceptance.md`，34 bytes |
| 2026-11-14 14:52 | Codex，Accessibility UI | 新建 `Acceptance d964 task` | 通过，revision 8 → 9 |
| 2026-11-14 14:52 | Codex，Accessibility UI | 编辑任务状态为“进行中” | 通过，revision 9 → 10，任务版本 1 → 2 |
| 2026-11-14 14:52 | Codex，Accessibility UI | 打开任务详情 | 通过；演示数据没有历史记录 |
| 2026-11-14 14:52 | Codex，Accessibility UI | 指针拖拽任务到另一负责人列 | 未运行 |
| 2026-11-14 14:52 | Codex，Accessibility UI | 人工删除和冲突复验 | 未运行 |

## 截图

| 文件 | 内容 |
| --- | --- |
| [macos-board.png](screenshots/macos-board.png) | macOS 演示数据看板 |
| [macos-live-server.png](screenshots/macos-live-server.png) | macOS 真实 TLS gRPC 和 PostgreSQL 数据 |
| [macos-new-task-sheet.png](screenshots/macos-new-task-sheet.png) | macOS 新建任务 Sheet |
| [macos-edit-task-sheet.png](screenshots/macos-edit-task-sheet.png) | macOS 编辑任务 Sheet |
| [macos-task-detail-sheet.png](screenshots/macos-task-detail-sheet.png) | macOS 任务详情 Sheet |
| [r3-board.png](screenshots/r3-board.png) | R3 计划看板，显示状态计数矛盾 |
| [r3-gantt.png](screenshots/r3-gantt.png) | R3 甘特 |
| [r3-history.png](screenshots/r3-history.png) | R3 历史与回退 |
| [r3-report.png](screenshots/r3-report.png) | R3 报告 |
| [r3-task-detail.png](screenshots/r3-task-detail.png) | R3 Markdown 和附件详情 |
| [ios-live-server.png](screenshots/ios-live-server.png) | iOS 真实 TLS gRPC 和 PostgreSQL 数据 |
| [ios-light.png](screenshots/ios-light.png) | iOS 亮色布局，显示按钮重叠 |
| [ios-dark.png](screenshots/ios-dark.png) | iOS 深色布局 |
| [ios-increase-contrast.png](screenshots/ios-increase-contrast.png) | iOS Increase Contrast |
| [ios-large-text.png](screenshots/ios-large-text.png) | iOS Accessibility XXXL |
| [ios-reduce-transparency.png](screenshots/ios-reduce-transparency.png) | iOS Reduce Transparency |
| [ios-reduce-motion.png](screenshots/ios-reduce-motion.png) | iOS Reduce Motion |

没有人员排期截图。原因是 #42 未交付。

## 关键截图 SHA-256

| 文件 | SHA-256 |
| --- | --- |
| `macos-live-server.png` | `7dad7993a3d10c659d47b9bf6ab0a7c4b46e754c94bccf445f1c9d2355f0a55a` |
| `ios-live-server.png` | `e8db956a4c03654c43ccd2ff76ce2237717c4ceb8979aa6bd2bd912bc1d65f1b` |
| `r3-board.png` | `f516957076e39ec1b989c9b8933c41b8481c5f7ff97e509a0bb88c0626fa230f` |
| `r3-report.png` | `0cd527f7381697a1276afb6743a8f77f89da18b242be5585511cc25541a61c4c` |
| `r3-task-detail.png` | `0377c43c6cfb6b5c1379bedbc3531b15884eeb407a11a6d0af10b4172d4354e6` |
| `ios-light.png` | `4b0aa33b4334688fae92ca56a65796954e2b4afc625e20115e8aa1e11031ff29` |
| `ios-large-text.png` | `2b80acbd78c7e89982ca31f4261fdfbffde4af9567ba55289d60ffb3568ea56e` |

完整清单见 [SHA256SUMS](SHA256SUMS)。

## 阻断问题

| Issue | 状态 | 阻断内容 |
| --- | --- | --- |
| #8 | Open | R3 Feature 尚未关闭 |
| #9 | Open | R4-R5 交付和发布验收未完成 |
| #42 | Open | 人员排期视图未交付；该 Task 明确阻塞 #39 |
| [#43](https://github.com/wyz541/Kshift/issues/43) | Open | iOS 紧凑布局的新增任务按钮重叠 |
| [#45](https://github.com/wyz541/Kshift/issues/45) | Open | R3 README 示例绕过 DerivedData 构建治理 |
| [#51](https://github.com/wyz541/Kshift/issues/51) | Open | iOS 完整无障碍审计失败 |
| [#52](https://github.com/wyz541/Kshift/issues/52) | Open | R3 看板状态计数遗漏第 7 项已完成任务 |
| [#53](https://github.com/wyz541/Kshift/issues/53) | Open | 新增 migration 后增量构建保留旧 migration count |
| 开发者人工签收 | 未完成 | 本记录是 AI 辅助验收，不替代开发者最终结论 |

## 未运行项

| 项目 | 原因 | 后续入口 |
| --- | --- | --- |
| 人员排期全流程 | #42 未交付 | #42 完成后重验 |
| macOS 人工删除、拖拽和冲突全流程 | 当前验收已有关键阻断 | #39 重验 |
| iOS 独立人工 P0 和 R3 | 当前证据来自 XCUITest 和 live E2E | #39 重验 |
| 最终 Release 资产验收 | #9 未关闭 | #9 |

## 结论

**失败。**

构建和 live P0 基线可用。R3 已进入主分支，但完整验收没有通过。关闭 #39 前，必须关闭 #8、#42 和 #9，修复 #43、#45、#51、#52 和 #53，并完成开发者人工签收。
