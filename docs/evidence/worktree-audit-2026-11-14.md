---
slug: /evidence/worktree-audit-2026-11-14
title: Worktree 只读审计证据 2026-11-14
type: report
status: review
version: "1.0"
updated: "2026-11-14"
keywords:
  - Worktree
  - 审计
  - 清理候选
  - Git
  - 证据
description: 记录现有任务 Worktree 的只读审计、清理候选、人工复核项和待批准状态。
---

# Worktree 只读审计证据 2026-11-14

> 结论：审计记录现有 20 个任务 Worktree。15 个是 cleanup-candidate，5 个需要 manual-review。没有取得清理批准，未删除任何 Worktree、branch 或用户文件。

## 1. 范围和数量

| 项目 | 值 |
| --- | --- |
| 审计日期 | `2026-11-14` |
| 审计基准提交 | `d78dbaf09bdc9eb72f0485a2abffe527adb569dc` |
| 基线分支 | `origin/main` at `d964c115662f4d7604960cff96c587a1db1e38b9` |
| Issue #49 正文数量 | 19 个任务 Worktree |
| 创建 #48 Worktree 前实际数量 | 20 个任务 Worktree |
| 创建 #48 Worktree 后实际数量 | 21 个任务 Worktree |
| 本证据审计数量 | 20 个既有任务 Worktree |
| 注册 Worktree 总数 | 22 个，包括主检出和 #48 Worktree |

Issue #49 的 19 个数量与实测 20 个不一致。本证据审计全部 20 个既有任务 Worktree，不按正文数字截断。

## 2. 只读审计方法

运行以下命令。

```bash
python3 scripts/audit_worktrees.py \
  --repo . \
  --format json \
  --expected-task-worktrees 21
```

原始快照：`worktree-audit-2026-11-14.json`。

| 文件 | SHA-256 |
| --- | --- |
| `worktree-audit-2026-11-14.json` | `f37fddf92bc4e397586f80a5af0b03895d03298532bbb7cb1402a23bde392405` |

审计工具只调用 `git worktree list`、`git status`、`git for-each-ref`、`git rev-parse`、`git merge-base` 和 `git rev-list`。工具不执行 fetch、prune、remove、branch 删除或文件写入。

## 3. 主检出

| 路径 | Branch | HEAD | Git 状态 | 合并状态 | 结论 |
| --- | --- | --- | --- | --- | --- |
| `~/repo/Kshift` | `docs/3-r0-spec-v0.1` | `870ad55d43d6` | dirty (23 entries) | yes | manual-review |

原因：主检出不在 `main`，并且有未提交项。禁止自动修复，禁止自动删除。

## 4. 清理候选

以下 15 项路径已注册、Git 状态为 clean，并且 HEAD 已合并到本地的 `origin/main`。这些结论只表示候选。

| Issue | Branch | HEAD | 路径 | 证据 | 批准 |
| --- | --- | --- | --- | --- | --- |
| #7 | `task/day-plan-ui-consolidation` | `71d83b18da9e` | `~/repo/_worktrees/Kshift/day-plan-ui-consolidation` | Git history; no worktree-only evidence | pending `@wyz541` |
| #24 | `issue-24-issue-forms` | `542bec8cd61f` | `~/repo/_worktrees/Kshift/issue-24-issue-forms` | Git history; no worktree-only evidence | pending `@wyz541` |
| #26 | `detached` | `56802725f128` | `~/repo/_worktrees/Kshift/issue-26-relations` | Git history; no worktree-only evidence | pending `@wyz541` |
| #3, #16 | `task/16-ownership-time-semantics` | `a2583e983b5d` | `~/repo/_worktrees/Kshift/issue-3-r0-formal-review` | Git history; no worktree-only evidence | pending `@wyz541` |
| #6 | `issue-6-shared-swiftui-foundation` | `b74032f736e8` | `~/repo/_worktrees/Kshift/issue-6-shared-swiftui-foundation` | Git history; no worktree-only evidence | pending `@wyz541` |
| #7 | `issue-7-live-history-e2e` | `844fd7bff7d4` | `~/repo/_worktrees/Kshift/issue-7-live-history-e2e` | Git history; no worktree-only evidence | pending `@wyz541` |
| #7 | `issue-7-r2-daily-planner` | `6cba4c57ea6c` | `~/repo/_worktrees/Kshift/issue-7-r2-daily-planner` | Git history; no worktree-only evidence | pending `@wyz541` |
| #7 | `issue-7-timezone-p0-e2e` | `5dfd5a90de8b` | `~/repo/_worktrees/Kshift/issue-7-timezone-p0-e2e` | Git history; no worktree-only evidence | pending `@wyz541` |
| #9 | `issue-9-acceptance` | `92d589110aa1` | `~/repo/_worktrees/Kshift/issue-9-acceptance` | Git history; no worktree-only evidence | pending `@wyz541` |
| #9 | `issue-9-preview-lifecycle` | `c9cb6d8fd7cb` | `~/repo/_worktrees/Kshift/issue-9-preview-lifecycle` | Git history; no worktree-only evidence | pending `@wyz541` |
| #9 | `issue-9-r4-r5` | `651c40f74038` | `~/repo/_worktrees/Kshift/issue-9-r4-r5` | Git history; no worktree-only evidence | pending `@wyz541` |
| #25 | `task/25-labels-project` | `c56b395b6037` | `~/repo/_worktrees/Kshift/task-25-labels-project` | Git history; no worktree-only evidence | pending `@wyz541` |
| #27 | `task/27-deriveddata-governance` | `19feefa60bac` | `~/repo/_worktrees/Kshift/task-27-deriveddata-governance` | Git history; no worktree-only evidence | pending `@wyz541` |
| #4 | `task-4-r1-server-postgres` | `2db27fe8a112` | `~/repo/_worktrees/Kshift/task-4-r1-server-postgres` | Git history; no worktree-only evidence | pending `@wyz541` |
| #8 | `task/8-r3-plan-depth` | `5bce503bab53` | `~/repo/_worktrees/Kshift/task-8-r3-plan-depth` | Git history; no worktree-only evidence | pending `@wyz541` |

`task/day-plan-ui-consolidation` 的 Issue 映射来自 [PR #19](https://github.com/wyz541/Kshift/pull/19) 的 `Refs #7`。本地审计工具只从 branch 和路径提取 Issue 提示。

## 5. 人工复核项

| Issue | Branch | HEAD | Git 状态 | 合并状态 | 未推送提交 | 路径 | 原因 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| #3 | `docs/3-r0-spec` | `45db149a85ae` | clean | no | 1 | `~/repo/_worktrees/Kshift/issue-3-r0-spec` | unmerged-to-origin-main |
| #42 | `issue-42-people-schedule` | `daa12b2c4202` | dirty (20 entries) | yes | 0 | `~/repo/_worktrees/Kshift/issue-42-people-schedule` | uncommitted-changes |
| #5 | `issue-5-r3-boundary` | `d964c115662f` | dirty (35 entries) | yes | 0 | `~/repo/_worktrees/Kshift/issue-5-r3-boundary` | uncommitted-changes |
| #9 | `issue-9-concurrency-launchd` | `2695a2cf4acd` | dirty (2 entries) | no | 1 | `~/repo/_worktrees/Kshift/issue-9-concurrency-launchd` | uncommitted-changes, unmerged-to-origin-main |
| #39 | `task/39-acceptance` | `c72419a1fdb0` | clean | no | 12 | `~/repo/_worktrees/Kshift/task-39-acceptance` | unmerged-to-origin-main |

## 6. 未提交项

以下 Worktree 有未提交项。未提交项可能包含唯一本地证据或未合入工作，因此不得进入 cleanup-candidate。

### `~/repo/_worktrees/Kshift/issue-42-people-schedule`

```text
 M Apps/KshiftIOSUITests/KshiftIOSUITests.swift
 M Apps/KshiftMacOS/KshiftMacOSApp.swift
 M Sources/KshiftCore/DemoClient.swift
 M Sources/KshiftCore/Models.swift
 M Sources/KshiftCore/RustClient.swift
 M Sources/KshiftUI/AppModel.swift
 M Sources/KshiftUI/FilterPopover.swift
 M Sources/KshiftUI/PlannerView.swift
 M Sources/KshiftUI/RuntimeEnvironment.swift
 M Sources/KshiftUI/SidebarView.swift
 M Sources/KshiftUI/TaskDetailView.swift
 M Sources/KshiftUI/TaskEditorView.swift
 M Tests/KshiftCoreTests/FakeClient.swift
 M docs/specs/core.md
 M docs/specs/domain.md
 M docs/specs/ui.md
?? Sources/KshiftUI/PeopleSchedule/
?? Sources/KshiftUI/PlannerViewPreferences.swift
?? Tests/KshiftCoreTests/PeopleScheduleTests.swift
?? docs/evidence/people-schedule/
```

### `~/repo/_worktrees/Kshift/issue-5-r3-boundary`

```text
 M Cargo.lock
 M Cargo.toml
 M Package.swift
 M Sources/KshiftCore/RustClient.swift
 M Sources/KshiftFFI/KshiftRustClient.swift
 M Sources/KshiftPresentation/PlanDepth/KshiftPlanDepthModels.swift
 M Sources/KshiftPresentation/PlanDepth/KshiftPlanDepthSampleBoundary.swift
 M Sources/KshiftUI/KshiftRootView.swift
 M Sources/KshiftUI/PlanDepth/KshiftPlanDepthFeatureModel.swift
 M Sources/KshiftUI/PlanDepth/KshiftPlanDepthFeatureView.swift
 M Tests/KshiftCoreTests/KshiftPlanDepthFeatureTests.swift
 M Tests/KshiftCoreTests/RustFFIIntegrationTests.swift
 M crates/kshift-client/Cargo.toml
 M crates/kshift-client/examples/mock_server.rs
 M crates/kshift-client/src/client.rs
 M crates/kshift-client/src/lib.rs
 M crates/kshift-client/tests/tls_client.rs
 M crates/kshift-contract/Cargo.toml
 M crates/kshift-contract/src/lib.rs
 M crates/kshift-core/src/lib.rs
 M crates/kshift-core/src/plan_depth.rs
 M crates/kshift-ffi/Cargo.toml
 M crates/kshift-ffi/src/command.rs
 M crates/kshift-ffi/src/lib.rs
 M crates/kshift-plan-store/src/lib.rs
 M crates/kshift-plan-store/tests/postgres_plan_store.rs
 M crates/kshift-server/Cargo.toml
 M crates/kshift-server/src/service.rs
 M docs/client-ffi.md
 M docs/contracts/protocol-v0.1.md
 M docs/r3-plan-depth.md
 M include/kshift_ffi.h
 M proto/kshift/v1/kshift.proto
?? crates/kshift-contract/src/plan_depth.rs
?? crates/kshift-server/tests/plan_depth_transport.rs
```

### `~/repo/_worktrees/Kshift/issue-9-concurrency-launchd`

```text
 M crates/kshift-server/build.rs
 M docs/r4-r5/evidence/2026-11-14-launchd-restart.md
```

## 7. 批准记录

| 字段 | 值 |
| --- | --- |
| Approver | 待填写，批准人必须是 `@wyz541` |
| Approved at | 待填写 |
| Approved paths | 无 |
| Approved branches | 无 |
| Evidence target | 15 个候选的证据位于已合并 Git 历史；清理前再次核对 |
| Checks | 本证据的快照 |

批准记录完成前，15 个候选都不得删除。批准后必须重新运行审计。路径、branch 或状态变化时，原批准失效。

## 8. 执行结果

- Worktree removal：未执行。
- Branch deletion：未执行。
- User file deletion：未执行。
- Cleanup result：等待 `@wyz541` 对固定路径和 branch 清单的明确批准。

## 9. 复验方法

批准并执行清理后，再次运行以下命令。

```bash
python3 scripts/audit_worktrees.py --repo . --format markdown
```

复验输出必须与批准清单一致。未处理项保留在 `manual-review`，并写明原因。

## 10. 来源

1. [Issue #46](https://github.com/wyz541/Kshift/issues/46)
2. [Research #47](https://github.com/wyz541/Kshift/issues/47)
3. [Task #48](https://github.com/wyz541/Kshift/issues/48)
4. [Task #49](https://github.com/wyz541/Kshift/issues/49)
5. [KS-GOV](../specs/governance.md)
