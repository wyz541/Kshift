---
slug: /decisions/decision-register
title: Kshift 决策登记表
type: reference
status: review
version: "0.1"
updated: "2026-11-13"
keywords:
  - 决策
  - 状态
  - ADR
  - Kshift
description: 记录 Kshift v1 的确认、待定和拒绝决策。
---

# Kshift 决策登记表

> 结论：实现只能使用 `confirmed` 决策。`pending` 决策必须先由 owner 决定。`rejected` 决策不得在实现 PR 中重新引入。

## 1. 状态规则

| 状态 | 使用规则 |
| --- | --- |
| `confirmed` | 已进入 Spec v0.1，可作为实现依据 |
| `pending` | 没有最终选择；需要 owner、截止日期和影响范围 |
| `rejected` | 明确不进入首版或永久禁止 |

## 2. 已确认决策

| ID | 决策 | 来源 | Owner | 评审日期 |
| --- | --- | --- | --- | --- |
| `DEC-001` | Rust 是业务规则、校验和持久化的唯一 owner | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-002` | 首版只支持 macOS 26.0+ 和 iOS 26.0+ | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-003` | 两端共享一套 SwiftUI feature slices | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-004` | 平台差异只进入 AppKit/UIKit adapter | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-005` | Liquid Glass 只使用 Apple 原生 API | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-006` | 服务使用 Rust server、gRPC 和 PostgreSQL 18 | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-007` | UI 只通过 `kshift-ffi` 调用 Rust client | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-008` | Rust client 和 server 共用 protobuf 合同 | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-009` | 同步使用 revisioned snapshot 和 outbox event stream | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-010` | 首版容量为 50 连接、20 编辑用户和 8 写事务 | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-011` | 备份使用 `pg_dump`/`pg_restore`，RPO/RTO 初始为 4 小时 | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-012` | 业务缓存只在内存；首版禁止离线写入 | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-013` | Release 使用单一 orchestrator 和同一 Draft Promote | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-014` | Rust 质量使用 fmt、clippy、测试、buf 和 deny | Discussion #1 | `@wyz541` | `2026-11-13` |
| `DEC-015` | 首版路线为 R0 至 R5 | Issue #2、Issue #3 | `@wyz541` | `2026-11-13` |
| `DEC-016` | 实现 Issue 只引用 Spec，不复制冲突规则 | Issue #3 | `@wyz541` | `2026-11-13` |

## 3. 待定决策

| ID | 问题 | Owner | 截止日期 | 影响 |
| --- | --- | --- | --- | --- |
| `DEC-017` | 内部身份来源 | `@wyz541` | `2026-11-20` | 认证、Keychain、成员管理 |
| `DEC-018` | macOS 签名和分发 | `@wyz541` | `2026-11-20` | 打包、安装和 Release |
| `DEC-019` | iOS 分发方式 | `@wyz541` | `2026-11-20` | 安装和 Release 证据 |
| `DEC-020` | Release 仓库 | `@wyz541` | `2026-11-20` | workflow 权限和资产 URL |
| `DEC-021` | Release 通道 | `@wyz541` | `2026-11-20` | 版本和发布策略 |
| `DEC-022` | Release 审批人数 | `@wyz541` | `2026-11-20` | GitHub environment |
| `DEC-023` | Server 发行格式 | `@wyz541` | `2026-11-20` | 部署和升级 |
| `DEC-024` | 应用内更新 | `@wyz541` | `2026-11-27` | 更新和回滚 |
| `DEC-025` | 备份存储 provider | `@wyz541` | `2026-11-27` | RPO、RTO 和恢复 |
| `DEC-026` | 产品成功指标数值 | `@wyz541` | `2026-12-11` | 首轮试用和发布评审 |
| `DEC-027` | 协议和附件大小上限 | `@wyz541` | `2026-11-20` | 合同、FFI 和背压 |

## 4. 已拒绝决策

| ID | 决策 | 原因 | 重新讨论条件 |
| --- | --- | --- | --- |
| `DEC-R01` | Web 产品 | 首版只做 macOS/iOS | 新平台 Spec 和 ADR |
| `DEC-R02` | Windows 客户端 | 首版只做 macOS/iOS | 新平台 Spec 和 ADR |
| `DEC-R03` | Android 客户端 | 首版只做 macOS/iOS | 新平台 Spec 和 ADR |
| `DEC-R04` | 外部平台导入 | 不进入首版 | 新 Issue 和验收方案 |
| `DEC-R05` | 公网部署 | 产品只在内网运行 | 安全架构和部署评审 |
| `DEC-R06` | 离线写入 | 首版使用共享数据库 | 新同步模型和 ADR |
| `DEC-R07` | 客户端直接连接 PostgreSQL | 绕过业务权威和安全边界 | 新架构 ADR |
| `DEC-R08` | SwiftUI 直接调用 HTTP | 违反 FFI 边界 | 新架构 ADR |
| `DEC-R09` | macOS/iOS 各写一套产品 UI | 违反复用门禁 | 有证据说明共享实现不可行 |
| `DEC-R10` | 自绘 Liquid Glass | Apple HIG 和原生 API 约束 | 不允许 |
| `DEC-R11` | 静默覆盖并发写入 | 会造成数据丢失 | 不允许 |
| `DEC-R12` | 无界队列或无限重试 | 会造成内存和资源失控 | 不允许 |

## 5. 关联文档

- [Spec v0.1](../spec/kshift-spec-v0.1.md)
- [Open Questions](open-questions.md)
- [ADR Index](../adr/README.md)
- [Traceability](../spec/traceability.md)
