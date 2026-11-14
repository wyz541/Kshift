---
slug: /specs/operations
title: KS-OPS Kshift 运行与运维规范
type: standard
status: active
updated: "2026-11-14"
owner: "@wyz541"
keywords:
  - 安全
  - 容量
  - 备份
  - 恢复
  - 部署
description: 定义 Kshift 的内网安全、授权、容量、备份、恢复、迁移和部署规则。
---

# KS-OPS Kshift 运行与运维规范

> 结论：Kshift 只在内网运行。数据库使用最小权限角色。备份使用一致性快照。恢复必须进入临时数据库并检查业务不变量。

## 1. 适用范围

本 Spec 约束安全、隐私、授权、容量、备份、恢复、数据库部署和运维入口。

调用链、缓存和数据库角色实现见 [KS-ARCH](architecture.md)。Release 程序和签名门禁见 [KS-RELEASE](release.md)。

## 2. 运行和数据库边界

| 项目 | 首版决策 |
| --- | --- |
| PostgreSQL | 18.x 最新可用 minor |
| 数据库位置 | 与 Rust server 同机 |
| 数据库监听 | loopback 或 Unix socket |
| Server 监听 | 内网接口 |
| 备份格式 | `pg_dump --format=custom --no-owner --no-acl` |
| 恢复格式 | `pg_restore` 到临时数据库 |
| 初始 RPO | 4 小时 |
| 初始 RTO | 4 小时 |

Migration 默认只向前。Migration 前必须创建备份。PostgreSQL minor 必须进入 Release manifest、健康检查和备份元数据。

## 3. 备份与管理功能

- `FR-OPS-001`：Admin 必须可以查看备份状态。
- `FR-OPS-002`：Admin 必须可以执行恢复演练。
- `FR-OPS-003`：受限数据库管理必须使用只读查询，或使用受审计的受控操作。
- `FR-OPS-004`：服务必须支持 `launchd` 启动、健康检查和日志轮转。
- `FR-OPS-005`：迁移前必须创建备份。

## 4. 安全与隐私

- `SEC-001`：服务只在内网提供。
- `SEC-002`：服务禁止直接暴露到公网。
- `SEC-003`：Server 证书 SAN 必须覆盖内网 DNS 名称和 loopback 名称。
- `SEC-004`：Stable gRPC 必须使用 TLS。禁止明文。
- `SEC-005`：客户端 token 必须放入 gRPC metadata。
- `SEC-006`：token 禁止进入 URL、日志、崩溃报告和 Release 资产。
- `SEC-007`：所有 RPC 必须有 deadline。
- `SEC-008`：客户端取消必须传递到服务端。
- `SEC-009`：Stable 禁止启用 gRPC reflection。
- `SEC-010`：健康检查继续启用。
- `SEC-011`：所有 unary message、event、snapshot 和附件必须有显式大小上限。具体值见 `CTR-008` 至 `CTR-011`。
- `SEC-012`：每个请求必须执行鉴权和项目级授权。
- `SEC-013`：Server 必须拒绝客户端提供的 role 或 permission。
- `SEC-014`：日志必须使用 request、project、client 和 command 标识。
- `SEC-015`：日志禁止记录 token、数据库密码、完整敏感请求体和附件内容。

## 5. 并发与容量

| 资源 | 首版目标 | 2 倍发布测试 |
| --- | ---: | ---: |
| 已连接客户端 | 50 | 100 |
| 同时编辑用户 | 20 | 40 |
| 并发写事务 | 8 | 16 |
| 并发事件流 | 32 | 64 |
| 并发 RPC | 100 | 200 |

- `CAP-001`：每个客户端最多 4 个并发 unary RPC。
- `CAP-002`：每个客户端最多 1 个事件流。
- `CAP-003`：Server 必须使用 semaphore 和 tower layer 限制连接、RPC、写事务和事件流。
- `CAP-004`：写事务超时为 10 秒。
- `CAP-005`：命令 deadline 必须大于写事务超时。
- `CAP-006`：超过容量时返回 `RESOURCE_EXHAUSTED`。
- `CAP-007`：队列必须有界。
- `CAP-008`：2 倍负载测试持续至少 30 分钟。
- `CAP-009`：测试必须记录 CPU、内存、连接数、事务等待、事件延迟和重连次数。
- `CAP-010`：发布门禁要求无崩溃、无内存无界增长、无丢事件和无静默覆盖。

## 6. 备份与恢复

- `BKP-001`：使用 `pg_dump --format=custom --no-owner --no-acl` 创建全量备份。
- `BKP-002`：每 4 小时创建一次备份。
- `BKP-003`：每次 migration 和 Stable Release 前必须创建备份。
- `BKP-004`：保留 42 个四小时备份。
- `BKP-005`：保留 12 个周备份。
- `BKP-006`：保留 12 个月备份。
- `BKP-007`：备份必须加密后复制到开发机之外。
- `BKP-008`：备份必须记录 PostgreSQL 版本、schema version、source commit、大小和 SHA-256。
- `BKP-009`：备份必须使用一致性快照。禁止复制正在写入的数据库目录。
- `BKP-010`：恢复必须进入临时数据库。
- `BKP-011`：恢复后必须检查 schema、外键、唯一性、引用和业务不变量。
- `BKP-012`：每月执行一次恢复演练。
- `BKP-013`：Stable Release 必须保留恢复证据。
- `BKP-014`：初始 RPO 和 RTO 均为 4 小时。
- `BKP-015`：备份 provider 状态为 `pending`。

## 7. 关联合同

- [Protocol Contract](../contracts/protocol-v0.1.md)：TLS、认证 metadata、deadline、取消、大小上限和错误映射。
- [Release Contract](../contracts/release-v0.1.md)：数据库版本、migration digest、备份和恢复证据。

## 8. 验收入口

- PostgreSQL 集成测试：`cargo test --workspace`，并设置 `TEST_DATABASE_URL`。
- 恢复演练：`./scripts/recovery-test.sh`
- 运维单元测试：`python3 -m unittest discover -s ops/tests`
- R4/R5 检查：`./scripts/check-r4-r5.sh`
- 迁移来源：[ADR-0004](../adr/0004-postgresql18-single-host.md)

## 9. 变更和回滚

改变安全边界、容量目标、备份格式、恢复程序或数据库版本时，必须先建立 Research 或 Task Issue。

回滚使用 Git 中上一版 Active Spec。数据库回滚默认只向前；需要逆向 migration 时，先建立独立 Issue 并保留备份证据。
