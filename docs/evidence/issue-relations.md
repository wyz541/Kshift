---
slug: /evidence/issue-relations
title: Issue 关系审计证据
type: report
status: active
version: "1.0"
updated: "2026-11-14"
keywords:
  - Issue 关系
  - 原生查询
  - 子 Issue
  - blocked_by
  - 审计证据
description: 记录 Kshift Issue 原生关系查询、审计命令和实际结果。
---

# Issue 关系审计证据

> 结论：Feature #22 使用原生 sub-issues。Acceptance #28 阻塞于全部 5 个交付子 Issue。

## 1. 查询环境

| 项目 | 值 |
| --- | --- |
| 仓库 | `wyz541/Kshift` |
| 查询日期 | `2026-11-14` |
| GitHub CLI | `gh` |
| API | GitHub GraphQL API |

## 2. 原生关系查询

查询 Issue 的 `parent`、`subIssues`、`blockedBy`、`blocking` 和 `duplicateOf` 字段。

```bash
gh api graphql -f query='query RelationAudit {
  repository(owner:"wyz541", name:"Kshift") {
    feature: issue(number:22) {
      number
      subIssues(first:50) { nodes { number title state } }
    }
    research: issue(number:23) {
      number
      body
      parent { number title state }
    }
    acceptance: issue(number:28) {
      number
      parent { number title state }
      blockedBy(first:50) { nodes { number title state } }
    }
  }
}' --jq '.data.repository | {
  feature: {number: .feature.number, subIssues: [.feature.subIssues.nodes[].number]},
  research: {
    number: .research.number,
    parent: .research.parent.number,
    sourceDiscussion: ([.research.body | scan("https://github.com/[^ ]+/discussions/[0-9]+")] | unique)
  },
  acceptance: {
    number: .acceptance.number,
    parent: .acceptance.parent.number,
    blockedBy: [.acceptance.blockedBy.nodes[].number]
  }
}'
```

查询结果摘要如下。

```json
{
  "acceptance": {"blockedBy": [27, 26, 25, 24, 23], "number": 28, "parent": 22},
  "feature": {"number": 22, "subIssues": [23, 24, 25, 26, 27, 28]},
  "research": {
    "number": 23,
    "parent": 22,
    "sourceDiscussion": ["https://github.com/wyz541/Kshift/discussions/1"]
  }
}
```

实际结果如下。

| 对象 | 结果 |
| --- | --- |
| Acceptance #28 | 父 Issue 为 Feature #22 |
| Acceptance #28 `blockedBy` | #23、#24、#25、#26、#27 |
| Feature #22 `subIssues` | #23、#24、#25、#26、#27、#28 |
| Research #23 父 Issue | Feature #22 |
| Research #23 来源 Discussion | Discussion #1 |

## 3. 审计命令

运行以下命令。

```bash
python3 scripts/audit_issue_relations.py \
  --repo wyz541/Kshift \
  --issue 22 \
  --issue 23 \
  --issue 26 \
  --issue 28
```

实际结果如下。

```text
PASS #22 [Feature] 工程治理：落地 Issue/PR 工作流与本地构建产物治理
  INFO  type=Feature
  INFO  sub-issues=#23, #24, #25, #26, #27, #28
PASS #23 [Research] 工程协作：确认 Issue/PR 与本地构建产物规则
  INFO  type=Research
  INFO  blocking=#24, #25, #26, #27, #28
PASS #26 [Task] 关系：落地 Discussion、Research、Feature 和 Acceptance 规则
  INFO  type=Task
  INFO  blocked_by=#23
  INFO  blocking=#28
PASS #28 [Acceptance] 工程治理：验收 Issue/PR 工作流与构建产物治理
  INFO  type=Acceptance
  INFO  blocked_by=#23, #24, #25, #26, #27
SUMMARY: 4 subject(s), 0 error(s), 0 warning(s)
```

## 4. 单元测试

运行以下命令。

```bash
python3 scripts/test_audit_issue_relations.py
```

实际结果如下。

```text
Ran 10 tests in 0.000s
OK
```

## 5. 限制

自动审计不能判断 `blocked_by` 是否为真实硬阻塞。Owner 必须执行人工检查。

跨仓库依赖没有同仓库原生 `blocked_by`。Owner 必须使用完整仓库引用并人工复核。

## 6. 来源

1. [Issue #22：工程治理 Feature](https://github.com/wyz541/Kshift/issues/22)，访问日期 `2026-11-14`。
2. [Issue #23：工程治理 Research](https://github.com/wyz541/Kshift/issues/23)，访问日期 `2026-11-14`。
3. [Issue #26：关系规则 Task](https://github.com/wyz541/Kshift/issues/26)，访问日期 `2026-11-14`。
4. [Issue #28：工程治理 Acceptance](https://github.com/wyz541/Kshift/issues/28)，访问日期 `2026-11-14`。
