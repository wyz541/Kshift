---
slug: /governance/issue-relations
title: Kshift Issue 与 PR 关系规则
type: standard
status: active
version: "1.0"
updated: "2026-11-14"
keywords:
  - Issue 关系
  - sub-issues
  - blocked_by
  - PR 追踪
  - 工程治理
description: 规定 Discussion、Research、Feature、Acceptance 和 PR 的原生关系与审计方法。
---

# Kshift Issue 与 PR 关系规则

> 结论：GitHub 原生关系是父子、硬阻塞和重复事项的唯一真源。正文只补充来源、软关联和跨仓库依赖。

## 1. 目的与范围

本规则适用于 Kshift 的新 Issue 和新 PR。历史事项只在发生实质修改时逐步补齐关系。

本规则落实 [KS-GOV](../specs/governance.md)。规则冲突时，Active Spec 优先。

## 2. 关系选择

| 关系 | GitHub 机制 | 使用条件 |
| --- | --- | --- |
| Discussion 升级为事项 | 双向链接 | 问题已有明确范围、Owner 和预期输出 |
| Research 与来源 Discussion | Issue 正文链接 | Research 只有 1 个活跃来源 Discussion |
| Feature 与交付子 Issue | 原生 sub-issues | 子 Issue 属于父 Feature 的交付范围 |
| Feature 与 Acceptance | 原生 sub-issues | 每个 Feature 恰好有 1 个 Acceptance 子 Issue |
| Acceptance 与交付 | `blocked_by` | Acceptance 等待全部交付子 Issue 完成 |
| 硬依赖 | `blocked_by` | 前置事项未完成时，当前事项不能开始 |
| 软关联 | 正文链接或“关系”说明 | 关联不阻止当前事项开始 |
| 重复事项 | Duplicate 关系 | 规范事项必须可追踪 |
| PR 与 Issue | PR 正文 `Closes #N` 或 `Part of #N` | 按交付和验收状态选择 |
| 跨仓库依赖 | `OWNER/REPO#N` | 原生 `blocked_by` 不可用，必须人工复核 |

`blocked_by` 不表达建议、顺序偏好或参考关系。错误使用 `blocked_by` 会隐藏可并行工作。

## 3. Discussion 升级规则

Discussion 用于探索问题。Research、Task 或交付 Issue 用于记录可执行结论。

满足以下全部条件时，创建 Issue。

1. 决策问题或交付目标已经明确。
2. 范围和非目标已经明确。
3. Owner 已经明确。
4. 预期输出和完成条件已经明确。

Research Issue 是活跃研究事项的唯一入口。创建 Research Issue 后，在来源 Discussion 添加结论摘要和 Issue 链接。

Research Issue 的 `## 来源 Discussion` 章节只写 1 个 Discussion 链接。直接创建的 Research Issue 写“无”。

Discussion 直接形成结论时，不创建 Research Issue。结论改变 Active Spec 时，同步更新权威入口。

## 4. Feature、交付和 Acceptance

Feature 使用以下结构。

```text
[Feature]
├─ [交付子 Issue] 1..N
└─ [Acceptance] 恰好 1 个
```

父 Feature 负责用户结果、整体范围和完成条件。交付子 Issue 负责实现、局部验证和交付证据。

Acceptance 只执行最终验收。Acceptance 不修改产品实现，不复制实现 PR 的结论。

创建 Feature 时执行以下步骤。

1. 创建父 Feature。
2. 创建至少 1 个交付子 Issue。
3. 创建 1 个 Acceptance 子 Issue。
4. 使用原生 sub-issues 添加全部子 Issue。
5. 为 Acceptance 添加全部交付子 Issue 的 `blocked_by`。

父 Issue 正文禁止复制子 Issue 清单。读者通过 GitHub 的 sub-issues 区域查看子 Issue。

Feature 只由 Acceptance 给出通过或失败结论。父 Feature 的关闭条件包括全部交付子 Issue 和 Acceptance 已完成。

## 5. PR 追踪规则

PR 正文必须使用以下一种追踪语句。

| 语句 | 使用条件 | 结果 |
| --- | --- | --- |
| `Closes #N` | 主 Issue 的交付和验收已经完成 | 合并后关闭主 Issue |
| `Part of #N` | 只交付父 Feature 或主 Issue 的一部分 | 合并后保留主 Issue |

一个 PR 默认只关闭 1 个主 Issue。只有全部 Issue 已完成验收且变更无法安全拆分时，PR 才关闭多个 Issue。

PR 评论只补充证据。PR 评论不替代 `## 验收证据`、Issue 验收记录或 Acceptance 结论。

跨仓库 Issue 使用完整引用，例如 `OWNER/REPO#123`。当前仓库的 `blocked_by` 不表示跨仓库关系。

## 6. Duplicate 与软关联

重复事项优先使用 GitHub Duplicate 关系。Duplicate 关系不可用时，关闭事项并写明原因和规范 Issue 链接。

软关联写在 Issue 或 PR 的“关系”章节。软关联示例包括背景来源、后续计划、实现参考和同一目标的非阻塞事项。

跨仓库关系必须写仓库名、Issue 编号和当前事项需要等待的行为。需要等待的跨仓库关系同时由 Owner 人工复核。

## 7. 审计

运行以下命令审计 1 个或多个 Issue。

```bash
python3 scripts/audit_issue_relations.py --repo wyz541/Kshift --issue 22 --issue 23 --issue 28
```

审计 PR 时运行以下命令。

```bash
python3 scripts/audit_issue_relations.py --repo wyz541/Kshift --pr 42
```

命令检查以下规则。

| 编号 | 规则 |
| --- | --- |
| `FEATURE-DELIVERY` | Feature 至少有 1 个交付子 Issue |
| `FEATURE-ACCEPTANCE` | Feature 恰好有 1 个 Acceptance 子 Issue |
| `FEATURE-CHILD-LIST` | 父 Feature 正文不复制多个子 Issue 引用 |
| `ACCEPTANCE-BLOCKERS` | Acceptance 阻塞于全部交付子 Issue |
| `RESEARCH-SOURCE-MISSING` | Research 写来源 Discussion 或“无” |
| `RESEARCH-SOURCE-MULTIPLE` | Research 只有 1 个活跃来源 Discussion |
| `PR-TRACKING` | PR 写 `Closes #N` 或 `Part of #N` |
| `PR-CLOSING-REFERENCE` | `Closes` 有可识别的关闭 Issue |

命令返回 `0` 表示没有错误。命令返回 `1` 表示规则错误。命令返回 `2` 表示 GitHub 查询或输入错误。

`blocked_by` 的语义、跨仓库等待条件和软关联需要人工复核。命令只检查 GitHub 可以稳定读取的结构。

## 8. 人工检查

执行以下检查。

1. 检查每个 `blocked_by` 是否真正阻止开始。
2. 检查软关联是否仍被写成 `blocked_by`。
3. 检查跨仓库事项是否有 Owner 和复核方式。
4. 检查 Duplicate 事项是否指向唯一规范事项。
5. 检查 Acceptance 是否只记录最终验收。
6. 检查 PR 是否使用正确的追踪语句。

## 9. 示例与证据

[Issue 关系审计证据](../evidence/issue-relations.md)记录当前原生查询结果。

## 10. 来源

1. [Discussion #1：Kshift Issue/PR 风格 Spec](https://github.com/wyz541/Kshift/discussions/1)，访问日期 `2026-11-14`。
2. [Spec v0.1：项目治理](../spec/kshift-spec-v0.1.md)，访问日期 `2026-11-14`。
3. [GitHub Docs：About sub-issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues)，访问日期 `2026-11-14`。
4. [GitHub Docs：About issue dependencies](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-issue-dependencies)，访问日期 `2026-11-14`。

## 11. 版本记录

| 版本 | 日期 | 变更 |
| --- | --- | --- |
| 1.0 | 2026-11-14 | 建立关系规则和审计命令。 |
