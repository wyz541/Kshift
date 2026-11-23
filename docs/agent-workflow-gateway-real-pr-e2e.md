---
slug: agent-workflow-gateway-real-pr-e2e
title: Agent Workflow Gateway 真实 PR 合并验证
type: evidence
status: active
updated: "2026-11-23"
keywords:
  - Agent Workflow Gateway
  - Pull Request
  - Branch Protection
  - Merge
description: 记录用真实 Pull Request 验证 Agent Workflow Gateway 绑定、MCP 请求、Web 批准和合并事实展示的最小文档。
---

# Agent Workflow Gateway 真实 PR 合并验证

这个 PR 用于验证 Agent Workflow Gateway 的真实 GitHub 路径，而不是替身数据：

- 绑定 Pull Request 时读取 head、检查、评审和 `main` 分支保护。
- MCP 只提交 `merge` 推进请求，不调用 GitHub 合并 API。
- Web 批准时重新读取 GitHub；只有 PR 已真实合并，且 head、检查、评审和保护规则仍满足时，才记录迁移。
- 实例页保存并展示合并提交、合并时间、head、检查覆盖、评审结论和分支保护事实。

`main` 的保护规则要求：

- `ops-and-release-unit` 与 `postgresql18-integration` 两个检查通过。
- 至少一个批准评审。
- 分支必须与 `main` 同步。
- 管理员同样受保护规则约束。