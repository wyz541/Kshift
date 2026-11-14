---
slug: /reviews/2026-11-13-r0-spec
title: Kshift R0 Spec 正式评审记录
type: report
status: active
version: "1.0"
updated: "2026-11-13"
keywords:
  - R0
  - Spec review
  - ADR
  - contract
  - evidence
description: 记录 Kshift Spec v0.1 的正式评审、结论、修正项和生效条件。
---

# Kshift R0 Spec 正式评审记录

> 结论：Kshift Spec v0.1 通过 R0 正式评审。Spec 状态改为 `active`。本次评审关闭 `OQ-011`，剩余 10 个待决项继续跟踪。

## 1. 评审控制

| 项目 | 内容 |
| --- | --- |
| Issue | [#3](https://github.com/wyz541/Kshift/issues/3) |
| 评审日期 | `2026-11-13` |
| 生效日期 | `2026-11-13` |
| 评审基线 | `84a8d1d`，`main` |
| 评审分支 | `docs/3-r0-formal-review` |
| Issue owner | `@wyz541` |
| 批准依据 | Issue owner 要求执行正式评审，并在评审后关闭 Issue #3 |
| 评审执行 | Codex，执行文档审查和自动检查 |
| 结论 | `approved` |

本次评审不批准密码、签名身份或分发凭据。

## 2. 范围

本次评审覆盖以下内容。

- Spec v0.1 的章节、规范词和验收门禁。
- Discussion #1 到 Spec 的追踪表。
- 确认、待定和拒绝决策。
- 7 个关键 ADR。
- protobuf 合同、Release manifest 和 fragment Schema。
- 当前 `main` 的 R1/R2 构建证据。

以下内容不在本次评审范围。

- Issue #7 的全部 UI 验收。
- Issue #8 和 Issue #9 的实现。
- macOS/iOS 正式签名。
- 内部身份源和正式分发通道。
- 公网部署和高可用数据库。

## 3. 评审清单

| 检查项 | 结果 | 依据 |
| --- | --- | --- |
| Discussion #1 可追踪 | 通过 | [Traceability](../spec/traceability.md) |
| 决策状态完整 | 通过 | [Decision Register](../decisions/decision-register.md) |
| 待决项有 owner、日期和影响 | 通过 | [Open Questions](../decisions/open-questions.md) |
| macOS/iOS 复用门禁 | 通过 | Spec §6.2 |
| Liquid Glass 门禁 | 通过 | Spec §6.3、ADR-0003 |
| 子 Issue 引用 Spec | 通过 | Issue #4 至 #9 |
| protobuf 格式、lint 和构建 | 通过 | `buf format -d`、`buf lint`、`buf build` |
| Release Schema | 通过 | `release-manifest.example.json`、`release-fragment.example.json` |
| Markdown 结构和链接 | 通过 | `scripts/check_docs.py` |
| Mermaid 图 | 通过 | 3 个文件中的全部图 |
| 平台边界 | 通过 | `scripts/check-platform-boundaries.sh` |
| Shared UI 结构 | 通过 | `KSHIFT_SKIP_XCODE_TESTS=1 ./scripts/verify.sh` |
| `main` CI | 通过 | R1 service、R1 client FFI |

## 4. 评审发现

| ID | 严重度 | 发现 | 处理结果 |
| --- | --- | --- | --- |
| `R0-F01` | 流程 | R0 曾被提前关闭，正式评审没有记录 | Issue #3 已重开。本记录补齐正式评审。 |
| `R0-F02` | 合同 | “Unary request/response 1 MiB”与 16 MiB snapshot/response 冲突 | 已拆分 request、response、event 和附件上限。 |
| `R0-F03` | 追踪 | 待定决策没有显式映射到 OQ ID | Decision Register 和 Open Questions 已增加交叉映射。 |
| `R0-F04` | 决策 | `OQ-011` 仍待定，但实现已使用固定上限 | 本次评审确认上限，关闭 `OQ-011`。 |
| `R0-F05` | 风险 | 10 个产品、身份、分发和操作决策仍未关闭 | 保留 owner、截止日期和影响范围。相关实现继续受限。 |

没有发现以下阻断项。

- Rust 业务权威被绕过。
- Shared SwiftUI 出现第二套平台产品页面。
- UI 直接访问 HTTP、protobuf 或 PostgreSQL。
- 使用自绘 Liquid Glass。
- 合同字段编号被复用。
- 已确认决策没有 ADR 来源。

## 5. 已确认大小上限

| 对象 | 上限 | 实现依据 |
| --- | ---: | --- |
| gRPC unary request | 1 MiB | `crates/kshift-server/src/server.rs` |
| gRPC unary response | 16 MiB | `crates/kshift-server/src/server.rs` |
| Snapshot response | 16 MiB | `crates/kshift-client/src/config.rs` |
| Single event | 256 KiB | `crates/kshift-server/src/service.rs` |
| Attachment cache item | 256 MiB | `crates/kshift-client/src/cache.rs` |

这些值进入 `DEC-027` 和 Protocol Contract。调整这些值需要新 ADR、测试和回滚说明。

## 6. 评审结论

- Spec v0.1 状态改为 `active`。
- `OQ-011` 关闭。
- 剩余待决项为 `OQ-001` 至 `OQ-010`。
- R1 和 R2 已完成部分必须继续服从 active Spec。
- Issue #7、#8 和 #9 保持独立验收。
- 本次评审不关闭上述下游 Issue。

## 7. 自动检查证据

| 命令 | 结果 |
| --- | --- |
| `MERMAID_EXTRACTOR=... ./scripts/check-r0.sh` | 通过 |
| `buf format -d proto` | 通过 |
| `buf lint` | 通过 |
| `buf build` | 通过 |
| `./scripts/check-platform-boundaries.sh` | 通过 |
| `KSHIFT_SKIP_XCODE_TESTS=1 ./scripts/verify.sh` | 通过 |
| R1 service workflow | 成功 |
| R1 client FFI workflow | 成功 |

CI 证据：
- [R1 service](https://github.com/wyz541/Kshift/actions/runs/43406659511)
- [R1 client FFI](https://github.com/wyz541/Kshift/actions/runs/43406659521)

## 8. 生效条件

Spec v0.1 可以进入实施。

待决项必须继续满足以下规则：

1. Owner 在截止日期前确认、拒绝或重新排期。
2. 截止日期过期时，相关实现标记为 `overdue`。
3. Release 不得绕过未关闭的分发、签名和备份决策。
4. 改变 active 决策时，先提交新 ADR。
5. 合同破坏性变更必须使用新的 package major version。

## 9. 关联记录

- [Spec v0.1](../spec/kshift-spec-v0.1.md)
- [Traceability](../spec/traceability.md)
- [Decision Register](../decisions/decision-register.md)
- [Open Questions](../decisions/open-questions.md)
- [ADR Index](../adr/README.md)
- [Contracts](../contracts/README.md)
- [Issue #3](https://github.com/wyz541/Kshift/issues/3)
