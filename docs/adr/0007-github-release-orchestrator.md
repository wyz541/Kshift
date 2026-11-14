---
slug: /adr/0007-github-release-orchestrator
title: ADR-0007 GitHub Release orchestrator
type: decision
status: superseded
version: "1.0"
updated: "2026-11-13"
keywords:
  - GitHub Release
  - orchestrator
  - manifest
  - provenance
description: 固定 GitHub 多平台 Release 的单一写入者、Draft 提升和不可覆盖规则。
---

# ADR-0007 GitHub Release orchestrator

> 结论：一个版本只对应一个标签、一个 manifest 和一个 GitHub Release。平台 workflow 只构建和验证。单一 orchestrator 负责 Draft 和 Promote。

> 历史说明：本 ADR 仅用于追溯。当前规则入口见 [Active Spec 索引](../specs/index.md)，目标 ID 为 `KS-RELEASE`。

## 1. 状态

`accepted`

## 2. 背景

macOS、iOS 和 Server 可能由不同 workflow 构建。多个写入者会造成资产漂移和部分发布。

Stable Release 需要同一 source commit、完整证据、签名和 digest 校验。

## 3. 决策

- 平台 workflow 使用 `contents: read`。
- 平台 workflow 上传 fragment，不写 Release。
- Release orchestrator 合并 manifest、创建 Draft 和 Promote。
- 只有 release environment 中的 orchestrator 获得 `contents: write`。
- 所有平台使用同一 source commit 和同一标签。
- Draft 通过签名、安装和 digest 校验后，只提升同一个 Draft。
- 已发布标签和同名 Stable 资产禁止覆盖。
- Stable 禁止包含 debug、ad-hoc 或 unsigned 资产。
- Update feed 只读取 Stable Release。
- 已发布 Stable 的问题使用新 patch Release 修复。
- 已发布 Stable 的回滚使用新 patch Release，不回退标签。

## 4. 备选方案

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| 每个平台直接发布 | workflow 简单 | 多写入者；部分发布风险 | 拒绝 |
| 手工上传资产 | 灵活 | 难审计；易覆盖 | 拒绝 |
| 单一 orchestrator | 一致性和审计强 | 编排复杂度高 | 采用 |

## 5. 后果

- macOS 签名、iOS 分发、Release 仓库和审批人数必须先关闭未决项。
- Manifest 和 fragment 需要版本化 schema。
- Stable 发布前必须有安装、恢复和性能证据。
- Release notes 必须写明平台、最低系统、数据库和限制。
- 失败 Draft 不提升。修复后重新准备。

## 6. 验证

- Manifest 和 fragment 通过 JSON Schema。
- 所有 fragment 的 source commit 相同。
- 远端下载 digest 与 manifest 一致。
- Draft 验证后资产没有重建。
- 发布后标签和 Stable 资产没有被覆盖。

## 7. 关联

- Spec: [13.3 Release 门禁](../spec/kshift-spec-v0.1.md#133-release-门禁)
- Decision: `DEC-013`
- Contract: [Release Contract](../contracts/release-v0.1.md)
