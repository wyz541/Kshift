---
slug: /adr/0008
title: ADR 0008：计划深度使用版本化快照和不可变历史状态
type: decision
status: accepted
updated: "2026-11-13"
keywords:
  - R3
  - plan depth
  - snapshot
  - history
  - attachment
description: 定义 R3 子任务、依赖、附件、回退和报告的快照边界。
---

# ADR 0008：计划深度使用版本化快照和不可变历史状态

> 结论：R3 使用单一 typed snapshot 表示当前计划。每次成功写入创建新 revision 和不可变历史状态。

## 上下文

R3 要同时支持以下能力。

- 子任务和依赖。
- 跨日排期。
- Markdown 描述。
- 附件去重。
- 历史回退。
- 工作报告和导出。

这些能力共享同一组任务关系和日期。分散命令容易产生不一致结果。

## 决策

1. `kshift-core::plan_depth` 是 R3 业务规则的唯一权威。
2. 所有写入先验证完整 snapshot 不变量。
3. 成功写入生成新 revision。
4. 历史状态按 revision 保存，历史记录不原地修改。
5. 回退创建新 revision。回退记录保留目标 revision 和内容 SHA-256。
6. 附件按项目内 SHA-256 去重。附件内容独立保存。
7. 报告固定一个 source revision。打印和图片导出使用同一 typed report。
8. PostgreSQL 使用 snapshot payload 保存当前状态和每个历史状态。

## 原因

- 完整 snapshot 让层级、依赖和日期使用同一验证入口。
- revision 让并发写入和冲突处理可追踪。
- 不可变历史让回退可审计。
- 内容 SHA-256 让附件去重和恢复证据可验证。
- 单一报告 snapshot 防止打印和图片导出显示不同数据。

## 取舍

- 每次写入保存完整 snapshot，存储量高于增量事件。
- 查询复杂统计时需要加载 snapshot。
- 大型项目需要后续增加增量投影或归档策略。

首版团队规模较小。正确性和审计优先于最小存储量。

## 后果

- 过期 revision 必须返回冲突。
- 报告请求必须记录 source revision。
- 附件缓存键必须使用 SHA-256。
- 回退必须要求 Admin 角色。
- 后续优化不得绕过 `kshift-core` 不变量。

## 关联

- Issue #8
- [R3 验收](../r3-plan-depth.md)
- [ADR 0005](0005-revisioned-snapshot-outbox.md)
- [ADR 0006](0006-grpc-protobuf-ffi.md)
