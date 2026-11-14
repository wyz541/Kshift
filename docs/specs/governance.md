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
description: 定义 Kshift 的 Issue、PR、Project、证据、决策和本地构建规则。
---

# KS-GOV Kshift 工程治理规范

> 结论：Issue 保存决策过程。Active Spec 保存当前规则。Project `Status` 是唯一状态源。

## 1. 文档控制

| 字段 | 值 |
| --- | --- |
| Spec ID | `KS-GOV` |
| Owner | `@wyz541` |
| 作用域 | 工程协作、事项关系、证据和本地构建 |
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
- `KS-GOV-012`：一个 PR 只关闭一个主 Issue。最终关闭写 `Closes #N`。部分交付写 `Part of #N`。
- `KS-GOV-013`：PR 正文保存交付证据。Issue 或 Acceptance 保存最终证据。评论不能成为唯一证据。
- `KS-GOV-014`：每个 PR 必须判断文档、FAQ 和 Release note 的影响。不适用时写原因。
- `KS-GOV-015`：Research 完成后回写来源 Discussion。RFC 类 Discussion 保持 Open。
- `KS-GOV-016`：本地 `xcodebuild` 使用 `build/DerivedData`。清理命令只删除校验后的仓库生成目录。
- `KS-GOV-017`：Debug 显示名是 `Kshift Dev`。Release 显示名是 `Kshift`。
- `KS-GOV-018`：禁止把 Debug App 复制到 `/Applications` 或 `~/Applications`。Test Runner 只由测试命令启动。
- `KS-GOV-019`：每个平台只保留一个活跃 Debug 构建。历史 DerivedData 清理前必须列清单并取得确认。
- `KS-GOV-020`：未运行的检查必须写“未运行”和原因。禁止写成通过。

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

## 6. 本地构建

- `make app-paths` 输出固定 App 路径。
- `make clean-build DRY_RUN=1` 只输出清理目标。
- `make clean-build` 只删除 `build/DerivedData`。
- 清理命令拒绝符号链接和预期路径之外的目录。
- 禁止按 App 名称跨目录删除。

## 7. 历史和迁移

- ADR 是历史来源。ADR 不再约束当前实现。
- Decision Register 和 Open Questions 是迁移来源。
- 新规则只进入 Active Spec。
- 旧规则保存在 Git 历史。
- 删除历史文档需要独立 Issue、迁移映射和明确确认。

## 8. 关联合同和验收入口

- Issue 关系审计：`python3 scripts/audit_issue_relations.py`
- 文档检查：`./scripts/check-r0.sh`
- Issue Forms：`.github/ISSUE_TEMPLATE/`
- PR template：`.github/pull_request_template.md`
- 标签和 Project：[标签与 Project 配置](../governance/labels-and-project.md)
- ADR 历史：[ADR 索引](../adr/README.md)

## 9. 变更和回滚

本 Spec 只在决策 Issue 完成后改变。回滚使用 Git 中上一版 Active Spec。回滚不恢复已删除的决策证据。回滚不改变产品数据。
