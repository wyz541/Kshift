---
slug: /contracts/release-v0.1
title: Kshift Release Contract v0.1
type: reference
status: active
version: "0.1"
updated: "2026-11-13"
keywords:
  - GitHub Release
  - manifest
  - fragment
  - provenance
  - rollback
description: 定义 Kshift Release manifest、fragment、通道、门禁和回滚合同。
---

# Kshift Release Contract v0.1

> 结论：一次 Release 只有一个 manifest 和一个 GitHub Release。所有平台 fragment 必须来自同一 source commit。Draft 验证通过后只提升同一个 Draft。当前规则见 [KS-RELEASE](../specs/release.md)。

## 1. 合同文件

| 项目 | 文件 |
| --- | --- |
| Manifest schema | [`release-manifest.schema.json`](../../schemas/release-manifest.schema.json) |
| Fragment schema | [`release-fragment.schema.json`](../../schemas/release-fragment.schema.json) |
| Manifest 示例 | [`release-manifest.example.json`](../../schemas/examples/release-manifest.example.json) |
| Fragment 示例 | [`release-fragment.example.json`](../../schemas/examples/release-fragment.example.json) |

Schema version 为 `1`。

## 2. 通道

| 通道 | 版本格式 | GitHub Release | Stable 资产 |
| --- | --- | --- | --- |
| Preview | `0.x.y-preview.n` | Prerelease | 不适用 |
| Stable | `x.y.z` | 正式 Release | 必须签名 |
| Hotfix | `x.y.z` | 正式 Release | 使用新 patch |

- `REL-C-001`：版本使用 SemVer 核心。
- `REL-C-002`：标签必须为 `v<version>`。
- `REL-C-003`：Preview 标签必须包含 `-preview.<n>`。
- `REL-C-004`：Stable 禁止 debug、ad-hoc 或 unsigned 资产。
- `REL-C-005`：Ops channel 尚未确认。`OQ-005` 关闭前不生成正式 Stable。

## 3. Manifest

Manifest 是 Release 的唯一事实源。

| 字段组 | 必填内容 |
| --- | --- |
| Product | 产品名、version、channel、tag 和 source commit |
| OS | macOS 和 iOS 最低系统版本 |
| Database | PostgreSQL 18、exact version、schema version 和 migration digest |
| Assets | 文件名、平台、架构、角色、大小、SHA-256 和签名状态 |
| Signing | 签名状态、身份摘要和 notarization |
| Provenance | workflow、run ID、run attempt 和 artifact ID |
| Gates | gate 名称、结果和证据 |
| Limitations | 已知限制和非目标 |
| Rollback | 策略和说明 |
| Status | `draft`、`promoted` 或 `failed` |

Manifest 禁止包含以下内容。

- 密码、token、私钥或证书内容。
- 本机绝对路径。
- 未脱敏的用户数据。
- 未验证的 gate 结果。
- 同一文件名的重复资产。

## 4. Fragment

每个平台只上传一个 fragment artifact。

| 字段 | 规则 |
| --- | --- |
| `source_commit` | 必须与 manifest 一致 |
| `platform` | `macos`、`ios`、`server` 或 `source` |
| `architecture` | 必须与资产一致 |
| `assets` | 至少一个资产 |
| `signing` | 必须写出实际状态 |
| `provenance` | 必须对应真实 workflow run |
| `gates` | 至少一个 gate |
| `limitations` | 可以写空数组 |

文件名必须匹配 `^[A-Za-z0-9][A-Za-z0-9._-]*$`。禁止路径分隔符和控制字符。

## 5. 校验顺序

Release orchestrator 按以下顺序校验。

1. 解析 manifest 和 fragment。
2. 校验 JSON Schema。
3. 校验所有 source commit 相同。
4. 校验 version、channel 和 tag 相同。
5. 校验平台资产是否完整。
6. 校验文件名、大小和 SHA-256。
7. 校验签名和 notarization 状态。
8. 校验 gate 结果。
9. 校验 SBOM 和 provenance。
10. 校验 manifest 没有秘密和本机路径。
11. 创建 Draft。
12. 下载远端资产并重新计算 SHA-256。
13. 完成安装和升级验证。
14. Promote 同一个 Draft。

任一步失败时，Draft 不得 Promote。

## 6. Stable 门禁

Stable manifest 必须满足以下条件。

- [ ] 所有必需平台存在。
- [ ] 所有平台使用同一 source commit。
- [ ] 所有资产 digest 唯一且有效。
- [ ] macOS 签名和分发策略已批准。
- [ ] iOS 分发策略已批准。
- [ ] macOS 安装、升级、卸载和回滚证据存在。
- [ ] iOS 安装和升级证据存在。
- [ ] Server 健康检查、启动恢复和日志检查通过。
- [ ] PostgreSQL 18 版本在支持范围内。
- [ ] Migration 从上一发布版本成功执行。
- [ ] 多人并发和 revision gap 测试通过。
- [ ] 2 倍目标负载测试通过。
- [ ] 备份和恢复演练通过。
- [ ] Liquid Glass 和无障碍门禁通过。
- [ ] SBOM、provenance 和 attestation 可验证。
- [ ] Release notes 包含最低系统、数据库、安装和限制。
- [ ] Release manager 已批准。

## 7. Draft 与 Promote

- Draft 在门禁完成前不可发布。
- Promote 只发布已验证 Draft。
- Promote 不重建资产。
- Draft 失败时删除 Draft。
- 失败 Draft 的资产不得直接发布。
- 部分成功不能进入 Stable。
- Stable 发布后禁止移动标签。
- Stable 发布后禁止覆盖同名资产。
- Stable 修复使用新 patch Release。
- Preview 修复使用下一个 preview 编号。

## 8. 更新

- Update feed 只读取 Stable Release。
- Update checker 只接受 GitHub Release URL。
- 下载后必须校验 byte count 和 SHA-256。
- 安装前必须校验签名和最低系统版本。
- Schema migration 默认只向前。
- 已发布 Stable 的回滚使用新 patch Release。
- 不能原地更新的平台打开 Release 页面。

## 9. Release 证据

每个 Release 必须保留以下证据。

- Draft 和 Promote 的 workflow run ID。
- Manifest、fragment、checksums、SBOM 和 attestation。
- 平台构建日志和 gate 结果。
- macOS 安装、升级、卸载和回滚记录。
- iOS 安装和升级记录。
- Server 启动、健康、日志和恢复记录。
- PostgreSQL 版本、schema 和 migration digest。
- 备份和恢复演练记录。
- 并发、revision gap 和 2 倍负载结果。
- UI 复用、Liquid Glass、无障碍和性能记录。
- Release manager 的批准记录。

## 10. 未决项

以下项目必须关闭后，Stable 才能生成。

| ID | 问题 |
| --- | --- |
| `OQ-002` | macOS 签名和分发 |
| `OQ-003` | iOS 分发 |
| `OQ-004` | Release 仓库 |
| `OQ-005` | Release 通道 |
| `OQ-006` | Release 审批人数 |
| `OQ-007` | Server 发行格式 |
| `OQ-008` | 应用内更新 |
| `OQ-009` | 备份目标 |
| `OQ-010` | 成功指标 |

## 11. 关联

- [KS-RELEASE](../specs/release.md)
- [ADR-0007](../adr/0007-github-release-orchestrator.md)
- [Open Questions](../decisions/open-questions.md)
