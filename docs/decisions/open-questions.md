---
slug: /decisions/open-questions
title: Kshift 未决问题
type: reference
status: active
version: "0.1"
updated: "2026-11-13"
keywords:
  - 未决问题
  - owner
  - 截止日期
  - 风险
description: 记录 Kshift v1 尚未决定的问题、负责人、截止日期和影响。
---

# Kshift 未决问题

> 结论：所有未决项都有 owner、截止日期和影响范围。未决项关闭前，受影响实现暂停。

## 1. 未决项

| ID | 问题 | Decision | Owner | 截止日期 | 影响范围 | 当前处理 |
| --- | --- | --- | --- | --- | --- | --- |
| `OQ-001` | 内部身份使用本地账号、LDAP 还是 SSO | `DEC-017` | `@wyz541` | `2026-11-20` | 认证、Keychain、成员管理 | 使用 opaque principal ID |
| `OQ-002` | macOS 使用 ad-hoc、Developer ID 或 notarization | `DEC-018` | `@wyz541` | `2026-11-20` | 打包、安装和 Stable | 不生成正式 macOS 资产 |
| `OQ-003` | iOS 使用 TestFlight、企业分发或签名 IPA | `DEC-019` | `@wyz541` | `2026-11-20` | 安装和升级证据 | 不生成正式 iOS 资产 |
| `OQ-004` | Release 放在当前仓库还是独立仓库 | `DEC-020` | `@wyz541` | `2026-11-20` | workflow 权限和 URL | 只在本地验证 manifest |
| `OQ-005` | 首版使用 Stable、Preview 还是 internal channel | `DEC-021` | `@wyz541` | `2026-11-20` | 版本和 Promotion | 只写 Preview 示例 |
| `OQ-006` | Release manager 使用单人还是双人批准 | `DEC-022` | `@wyz541` | `2026-11-20` | GitHub environment | 不开启 Stable Promote |
| `OQ-007` | Server 使用 tar 包、安装脚本或其他格式 | `DEC-023` | `@wyz541` | `2026-11-20` | 部署、升级和回滚 | 不冻结 server 包装格式 |
| `OQ-008` | 首版是否支持应用内更新 | `DEC-024` | `@wyz541` | `2026-11-27` | 更新检查和回滚 | 默认打开 Release 页面 |
| `OQ-009` | 加密备份目标由谁提供 | `DEC-025` | `@wyz541` | `2026-11-27` | RPO、RTO 和恢复证据 | 只规定加密和离机复制 |
| `OQ-010` | 产品成功指标的具体数值 | `DEC-026` | `@wyz541` | `2026-12-11` | 首轮试用和发布评审 | 使用发布门禁，不填虚构数值 |

## 2. 关闭条件

未决项关闭时必须满足以下条件。

1. Owner 写出最终选择。
2. Owner 写出被拒绝的备选方案。
3. Owner 写出迁移和回滚影响。
4. 更新 decision register。
5. 更新 Spec 和合同。
6. 需要时增加 ADR。
7. 更新受影响 Issue 的 Spec 入口。

## 3. 过期处理

截止日期过后，问题仍未关闭时执行以下步骤。

1. 将状态标为 `overdue`。
2. 在 Issue #3 增加阻塞说明。
3. 暂停依赖该问题的实现。
4. 由 owner 重新设置截止日期。

禁止用默认实现替代未决决策。

## 4. 已关闭项

| ID | 结论 | Decision | 证据 |
| --- | --- | --- | --- |
| `OQ-011` | request 1 MiB；response/snapshot 16 MiB；event 256 KiB；附件缓存项 256 MiB | `DEC-027` | [R0 Spec Review](../reviews/2026-11-13-r0-spec-review.md) |
