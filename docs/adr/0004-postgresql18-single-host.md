---
slug: /adr/0004-postgresql18-single-host
title: ADR-0004 PostgreSQL 18 单机部署
type: decision
status: superseded
version: "1.0"
updated: "2026-11-13"
keywords:
  - PostgreSQL 18
  - 备份
  - 恢复
  - 单机
description: 固定 PostgreSQL 18 与 Rust server 同机部署、最小权限和备份恢复边界。
---

# ADR-0004 PostgreSQL 18 单机部署

> 结论：首版使用 PostgreSQL 18.x 和 Rust server 同机部署。数据库只监听 loopback 或 Unix socket。备份使用 `pg_dump`，恢复使用 `pg_restore`。

> 历史说明：本 ADR 仅用于追溯。当前规则入口见 [Active Spec 索引](../specs/index.md)，目标 ID 为 `KS-OPS`。

## 1. 状态

`accepted`

## 2. 背景

首版服务部署在内网 macOS 开发机。当前没有高可用基础设施。

共享数据库需要支持多人协作、事务、版本保护、审计和 outbox。

## 3. 决策

- PostgreSQL 固定 major 18，使用发布时最新 minor。
- Database 与 Rust server 同机。
- 数据库只监听 loopback 或 Unix socket。
- Server 绑定内网接口。
- 使用 `kshift_owner`、`kshift_app` 和 `kshift_backup` 三个角色。
- 运行角色不是超级用户。
- `sqlx::PgPool` 最小 4 个连接，最大 20 个连接。
- 默认隔离级别为 `READ COMMITTED`。
- 跨行不变量使用 `SERIALIZABLE`。
- Migration 先备份。Migration 默认只向前。
- 使用 `pg_dump --format=custom --no-owner --no-acl`。
- 备份保留 42 个四小时、12 个周和 12 个月。
- 初始 RPO 和 RTO 均为 4 小时。

## 4. 备选方案

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| SQLite 数据库 | 部署简单 | 共享并发和多实例受限 | 拒绝 |
| 独立高可用数据库 | 恢复能力高 | 成本和运维范围大 | 首版拒绝 |
| PostgreSQL 18 单机 | 事务完整；部署可控 | 开发机不是高可用 | 采用 |

## 5. 后果

- 开发机的电源、磁盘和网络是首版风险。
- RPO 小于 4 小时需要 pgBackRest 和 WAL 归档 ADR。
- 恢复目标需要开发机之外的加密存储。
- PostgreSQL minor 必须进入 Release manifest、健康检查和备份元数据。

## 6. 验证

- PostgreSQL 18 集成测试通过。
- Migration digest 和 schema version 检查通过。
- `pg_dump` 和 `pg_restore` 演练通过。
- 恢复后 schema、外键、唯一性和业务不变量检查通过。

## 7. 关联

- Spec: [7.3 服务与数据库](../spec/kshift-spec-v0.1.md#73-服务与数据库)
- Spec: [11. 备份与恢复](../spec/kshift-spec-v0.1.md#11-备份与恢复)
- Decision: `DEC-006`、`DEC-011`
