---
slug: /adr/0005-revisioned-snapshot-outbox
title: ADR-0005 revision snapshot 和 transactional outbox
type: decision
status: superseded
version: "1.0"
updated: "2026-11-13"
keywords:
  - revision
  - transactional outbox
  - 同步
  - 并发
description: 固定 Kshift 的 revisioned snapshot、事务 outbox 和冲突处理模型。
---

# ADR-0005 revision snapshot 和 transactional outbox

> 结论：客户端从完整 snapshot 起步。服务端用 transactional outbox 提供有序增量事件。revision gap 触发重新获取 snapshot。

> 历史说明：本 ADR 仅用于追溯。当前规则入口见 [Active Spec 索引](../specs/index.md)，目标 ID 为 `KS-ARCH`。

## 1. 状态

`accepted`

## 2. 背景

多人编辑需要一致读取和有序增量。独立消息队列会增加部署和恢复风险。

任务、审计、命令结果和事件必须同时成功或同时失败。

## 3. 决策

- 每个项目有单调递增 `revision`。
- 每次成功写事务只生成一个 `change_event`。
- 业务数据、审计、命令结果、revision 和 outbox 原子提交。
- Outbox 唯一约束为 `(project_id, revision)`。
- `pg_notify` 只发送 `project_id`，并只用于唤醒。
- Dispatcher 按 revision 顺序读取。
- `WatchProjectChanges(since_revision)` 回放缺失事件。
- 客户端通过 `ResetRequired` 处理 revision gap。
- Outbox 保留 7 天。
- Heartbeat 每 15 秒。
- Client 重连使用 jitter 指数退避，500 ms 起，30 秒封顶。
- 慢消费者使用有界 channel。超限时断开并重新 snapshot。
- 写命令携带 `client_id`、`command_id`、`project_id` 和 precondition。
- `(client_id, command_id)` 唯一。结果保留 7 天。
- 冲突返回 `ABORTED` 和当前版本信息。
- Client 不自动合并或覆盖冲突。
- 业务缓存只在内存，最多 3 个项目。
- 首版禁止离线写入。

## 4. 备选方案

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| 只轮询 snapshot | 简单 | 延迟和流量高 | 拒绝 |
| Kafka 或外部队列 | 扩展性高 | 首版运维过重 | 拒绝 |
| PostgreSQL outbox | 事务原子；可恢复 | 需要分发器和清理 | 采用 |

## 5. 后果

- UI 必须处理冲突和 reset。
- Event stream 需要 heartbeat、背压和重连。
- Outbox 需要清理和监控。
- Snapshot 和 event 必须共享 schema version。
- 恢复后必须从持久 outbox 继续分发。

## 6. 验证

- 并发写入不会静默覆盖。
- 事务失败时不产生 outbox。
- Revision gap 返回 `ResetRequired`。
- 断线重连、heartbeat 和 revision gap 有测试。
- 慢消费者不阻塞写请求。

## 7. 关联

- Spec: [8. 同步与缓存](../spec/kshift-spec-v0.1.md#8-同步与缓存)
- Decision: `DEC-009`、`DEC-010`、`DEC-012`
- Contract: [kshift.proto](../../proto/kshift/v1/kshift.proto)
