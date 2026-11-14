---
slug: /decisions/decision-register
title: Kshift 决策登记表
type: reference
status: active
version: "0.2"
updated: "2026-11-14"
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
| `DEC-027` | 协议 request、response、event 和附件使用固定上限 | Formal review | `@wyz541` | `2026-11-13` |
| `DEC-028` | 任务负责人是 0 至 20 个唯一项目成员的集合 | Issue #16 | `@wyz541` | `2026-11-13` |
| `DEC-029` | 项目 IANA 时区决定自然日期和共享计划视图 | Issue #16 | `@wyz541` | `2026-11-13` |
| `DEC-030` | 用户时区只影响绝对时间戳显示，并回退到项目时区 | Issue #16 | `@wyz541` | `2026-11-13` |
| `DEC-031` | `KshiftRootView` 是唯一日计划 UI | ADR-0009 | `@wyz541` | `2026-11-13` |
| `DEC-032` | 类型标签使用 `type:`，领域标签使用 `area:` | Issue #23、ADR-0010 | `@wyz541` | `2026-11-14` |
| `DEC-033` | Project `Status` 是唯一状态来源 | Issue #23、ADR-0010 | `@wyz541` | `2026-11-14` |
| `DEC-034` | 一个 PR 只有一个主 Issue | Issue #23、ADR-0010 | `@wyz541` | `2026-11-14` |
| `DEC-035` | 用户可见变更必须判断文档、FAQ 和 Release note 影响 | Issue #23、ADR-0010 | `@wyz541` | `2026-11-14` |
| `DEC-036` | Research 完成后回写来源 Discussion，但不强制关闭 Discussion | Issue #23、ADR-0010 | `@wyz541` | `2026-11-14` |
| `DEC-037` | PR 保存交付证据，Issue 或 Acceptance 保存最终验收证据 | Issue #23、ADR-0010 | `@wyz541` | `2026-11-14` |
| `DEC-038` | 本地 DerivedData 固定为 `build/DerivedData` | Issue #23、ADR-0010 | `@wyz541` | `2026-11-14` |
| `DEC-039` | Debug App 显示名为 `Kshift Dev` | Issue #23、ADR-0010 | `@wyz541` | `2026-11-14` |

## 3. 待定决策

| ID | 问题 | Open Question | Owner | 截止日期 | 影响 |
| --- | --- | --- | --- | --- | --- |
| `DEC-017` | 内部身份来源 | `OQ-001` | `@wyz541` | `2026-11-20` | 认证、Keychain、成员管理 |
| `DEC-018` | macOS 签名和分发 | `OQ-002` | `@wyz541` | `2026-11-20` | 打包、安装和 Release |
| `DEC-019` | iOS 分发方式 | `OQ-003` | `@wyz541` | `2026-11-20` | 安装和 Release 证据 |
| `DEC-020` | Release 仓库 | `OQ-004` | `@wyz541` | `2026-11-20` | workflow 权限和资产 URL |
| `DEC-021` | Release 通道 | `OQ-005` | `@wyz541` | `2026-11-20` | 版本和发布策略 |
| `DEC-022` | Release 审批人数 | `OQ-006` | `@wyz541` | `2026-11-20` | GitHub environment |
| `DEC-023` | Server 发行格式 | `OQ-007` | `@wyz541` | `2026-11-20` | 部署和升级 |
| `DEC-024` | 应用内更新 | `OQ-008` | `@wyz541` | `2026-11-27` | 更新和回滚 |
| `DEC-025` | 备份存储 provider | `OQ-009` | `@wyz541` | `2026-11-27` | RPO、RTO 和恢复 |
| `DEC-026` | 产品成功指标数值 | `OQ-010` | `@wyz541` | `2026-12-11` | 首轮试用和发布评审 |

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
