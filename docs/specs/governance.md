---
slug: /specs/governance
title: KS-GOV Kshift 工程治理规范
type: standard
status: active
updated: "2026-11-14"
owner: "@wyz541"
keywords:
  - 工程治理
  - Issue
  - PR
  - Project
  - Spec
  - Worktree
description: 定义 Kshift 的 Issue、PR、Project、证据、决策、Worktree 和本地构建规则。
---

# KS-GOV Kshift 工程治理规范

> 结论：Issue 保存决策过程。Active Spec 保存当前规则。Project `Status` 是唯一状态源。Worktree 只保存活跃交付状态。

## 1. 文档控制

| 字段 | 值 |
| --- | --- |
| Spec ID | `KS-GOV` |
| Owner | `@wyz541` |
| 作用域 | 工程协作、事项关系、证据、Worktree 和本地构建 |
| 状态 | `active` |
| 更新入口 | Issue、PR 和 [Spec 索引](index.md) |

## 2. 规范规则

- `KS-GOV-001`：Discussion 用于形成问题。Issue 用于形成决策和交付。Active Spec 用于保存当前规则。
- `KS-GOV-002`：Active Spec 是项目规则的唯一当前入口。实现 Issue 和 PR 只链接 Spec，不复制完整规则。
- `KS-GOV-003`：新决策不再创建 ADR。Issue 保存选项、证据、结论、影响和回滚。
- `KS-GOV-004`：Issue 类型使用 `type:` 标签。每个开放 Issue 恰有一个类型标签。
- `KS-GOV-005`：领域使用 `area:` 标签。每个开放 Issue 至少有一个领域标签。
- `KS-GOV-006`：Project `Status` 使用 `Inbox`、`Triage`、`Ready`、`In Progress`、`In Review`、`Blocked` 和 `Done`。
- `KS-GOV-007`：Project `Priority` 使用 `P0`、`P1`、`P2` 和 `P3`。Project `Target` 使用 `R0` 至 `R5` 和 `v1.0`。
- `KS-GOV-008`：状态、优先级、Target 和负责人只保存在 Project。禁止建立状态、优先级或负责人标签。
- `KS-GOV-009`：Feature 使用原生 sub-issues。Feature 至少有一个交付子 Issue 和一个 Acceptance 子 Issue。
- `KS-GOV-010`：Acceptance 等待全部交付子 Issue。Acceptance 只验收、记录证据和给出结论。
- `KS-GOV-011`：硬依赖使用 `blocked_by`。软关联写在正文，不阻止开始。
- `KS-GOV-012`：一个 PR 只关闭一个主 Issue。非 Worktree 交付最终关闭写 `Closes #N`。Worktree 交付写 `Part of #N`，清理后手工关闭。
- `KS-GOV-013`：PR 正文保存交付证据。Issue 或 Acceptance 保存最终证据。评论不能成为唯一证据。
- `KS-GOV-014`：每个 PR 必须判断文档、FAQ 和 Release note 的影响。不适用时写原因。
- `KS-GOV-015`：Research 完成后回写来源 Discussion。RFC 类 Discussion 保持 Open。
- `KS-GOV-016`：本地 `xcodebuild` 使用 `build/DerivedData`。清理命令只删除校验后的仓库生成目录。
- `KS-GOV-017`：Debug 显示名是 `Kshift Dev`。Release 显示名是 `Kshift`。
- `KS-GOV-018`：禁止把 Debug App 复制到 `/Applications` 或 `~/Applications`。Test Runner 只由测试命令启动。
- `KS-GOV-019`：每个平台只保留一个活跃 Debug 构建。历史 DerivedData 清理前必须列清单并取得确认。
- `KS-GOV-020`：未运行的检查必须写“未运行”和原因。禁止写成通过。
- `KS-GOV-021`：会修改仓库的 Task 和 Bug 各使用一个独立 Worktree 和 branch。Feature、Research 和 Acceptance 不要求实现 Worktree。
- `KS-GOV-022`：主检出保持在 `main` branch，并保持干净工作区。现有偏离只进入人工复核，禁止自动修复。
- `KS-GOV-023`：Worktree 交付的 PR 使用 `Part of #N`。合并后先迁移证据、清理产物、移除 Worktree、删除 branch，再由 Issue owner 手工关闭 Issue。
- `KS-GOV-024`：移除 Worktree 前必须确认路径已登记、没有未提交修改、没有未推送提交、没有未合并提交，并且证据已迁移。
- `KS-GOV-025`：Worktree 只使用 `git worktree remove <path>` 移除。命令失败时停止并人工复核。禁止 `git worktree remove --force`。
- `KS-GOV-026`：Branch 只在已合并到 `origin/main` 且 Worktree 已移除后删除。只使用 `git branch -d`。禁止 `git branch -D`。
- `KS-GOV-027`：保留 Worktree 必须记录 owner、原因、批准人和复核日期。批准人是 `@wyz541`。最长复核周期是 14 天。
- `KS-GOV-028`：清理前必须取得 `@wyz541` 的明确批准。批准记录包含固定路径、branch、Issue、证据目标、检查结果、批准人和日期。
- `KS-GOV-029`：Worktree 审计只读取本地 Git 状态，不联网，不提供删除参数。审计输出按固定顺序排序。
- `KS-GOV-030`：Worktree 不是归档位置。证据先迁移到 `docs/evidence` 或登记的项目证据目录。生成物不进入证据目录。

## 3. 决策流程

```text
(开始)
  │
  ▼
[Discussion 或 Issue]
  │
  ▼
[Research / Task 决策记录]
  │
  ▼
[更新 Active Spec]
  │
  ▼
[实现 PR 和验收]
  │
  ▼
(结束)
```

改变当前规则时执行以下步骤。

1. 建立 Research 或 Task Issue。
2. 写决策问题、Owner、选项、判断标准、证据和影响。
3. 取得 Decision owner 的最终选择。
4. 更新受影响的 Active Spec。
5. 更新受影响的合同、模板和检查。
6. 增加实现和验收证据。
7. 在来源 Discussion 回写结论。
8. 关闭决策 Issue。

## 4. Issue 和 PR

| 对象 | 必填入口 |
| --- | --- |
| Feature | 用户结果、范围、交付子 Issue、Acceptance 和 Spec |
| Task | 目标、范围、验收、证据、Spec 和 Decision Issue |
| Bug | 环境、复现、期望、实际、影响、回归证据和 Spec |
| Research | 决策问题、来源 Discussion、Owner、Decision owner 和预期输出 |
| Acceptance | 验收矩阵、环境、证据、阻断问题和结论 |
| PR | 追踪、变更、验收证据、文档影响、风险与回滚、未覆盖和检查 |

详细程序见以下文档。详细文档不得覆盖本 Spec。

- [Issue 与 PR 关系规则](../governance/issue-relations.md)
- [标签与 Project 配置](../governance/labels-and-project.md)

## 5. 证据和关闭

- Task 关闭前必须有实际验收记录。
- Research 关闭前必须有最终结论和来源 Discussion 回写。
- Acceptance 关闭前必须完成验收矩阵。
- Feature 关闭前必须关闭全部必需子 Issue，并取得 Acceptance 通过结论。
- 关闭后发现错误时，重开 Issue 并增加 `needs:evidence`。
- 用户可见变更必须链接文档、FAQ 或 Release note。无需更新时写原因。

## 6. Worktree 生命周期

### 6.1 创建和交付

1. 确认主检出位于 `main`，且 `git status --short` 没有输出。
2. 从 `origin/main` 创建独立 Worktree。
3. 在 Issue 或 PR 记录 Worktree 路径和 branch。
4. 在 Worktree 完成实现、测试和证据。

标准路径和 branch 如下。

```text
~/repo/_worktrees/Kshift/issue-<N>-<slug>
issue/<N>-<slug>
```

创建命令如下。

```bash
git worktree add -b issue/<N>-<slug> \
  ~/repo/_worktrees/Kshift/issue-<N>-<slug> origin/main
```

### 6.2 合并和关闭时序

```text
(开始)
  │
  ▼
[Worktree 内完成交付]
  │
  ▼
[PR 写 Part of #N 并合并]
  │
  ▼
[迁移唯一证据]
  │
  ▼
[清理已登记生成物]
  │
  ▼
[取得清理批准]
  │
  ▼
[git worktree remove]
  │
  ▼
[git branch -d]
  │
  ▼
[再次审计]
  │
  ▼
[Issue owner 手工关闭 Issue]
  │
  ▼
(结束)
```

Worktree 交付不依赖 PR 的 `Closes`。PR 合并会早于本地清理。因此，PR 使用 `Part of #N`，清理完成后手工关闭 Issue。

### 6.3 保留例外

保留 Worktree 时，在 Issue 记录以下字段。

| 字段 | 要求 |
| --- | --- |
| Owner | 对复核负责的人员 |
| 原因 | 复现、调试或证据保留的具体原因 |
| 批准人 | `@wyz541` |
| 批准日期 | ISO 8601 日期 |
| 复核日期 | 批准日期后不超过 14 天 |

复核日期到达后，Owner 必须再次批准保留。禁止无限期保留，禁止把 Worktree 当归档。

### 6.4 清理批准

清理候选必须列出以下记录。

| 字段 | 要求 |
| --- | --- |
| Worktree | 已登记的绝对路径 |
| Branch | Branch 名或 `detached` |
| Issue | 关联 Issue。无法确认时写“待确认” |
| Evidence target | 迁移后的稳定路径，或“不适用”及原因 |
| Checks | 未提交、未推送、未合并状态和审计结果 |
| Approver | `@wyz541` |
| Approved at | ISO 8601 日期 |

批准只覆盖记录中的固定路径和 branch。路径、branch 或检查结果变化时，重新批准。未批准项不得删除。

### 6.5 只读审计

运行以下命令。

```bash
python3 scripts/audit_worktrees.py --repo . --expected-task-worktrees <N>
```

命令使用本地 `origin/main`。命令不执行 `fetch`、`prune`、`remove`、`branch -d` 或 `branch -D`。需要最新远端状态时，由人员单独运行只读的 `git fetch` 后重新审计。

## 7. 本地构建

- `make app-paths` 输出固定 App 路径。
- `make clean-build DRY_RUN=1` 只输出清理目标。
- `make clean-build` 只删除 `build/DerivedData`。
- 清理命令拒绝符号链接和预期路径之外的目录。
- 禁止按 App 名称跨目录删除。

## 8. 历史和迁移

- ADR 是历史来源。ADR 不再约束当前实现。
- Decision Register 和 Open Questions 是迁移来源。
- 新规则只进入 Active Spec。
- 旧规则保存在 Git 历史。
- 删除历史文档需要独立 Issue、迁移映射和明确确认。

## 9. 关联合同和验收入口

- Issue 关系审计：`python3 scripts/audit_issue_relations.py`
- Worktree 审计：`python3 scripts/audit_worktrees.py --repo .`
- 文档检查：`./scripts/check-r0.sh`
- Issue Forms：`.github/ISSUE_TEMPLATE/`
- PR template：`.github/pull_request_template.md`
- 标签和 Project：[标签与 Project 配置](../governance/labels-and-project.md)
- ADR 历史：[ADR 索引](../adr/README.md)

## 10. 变更和回滚

本 Spec 只在决策 Issue 完成后改变。回滚使用 Git 中上一版 Active Spec。回滚不恢复已删除的决策证据。回滚不改变产品数据。
