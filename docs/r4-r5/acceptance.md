---
slug: "/docs/r4-r5/acceptance"
title: "Issue #9 验收状态"
type: "report"
status: "review"
updated: "2026-11-13"
keywords:
  - Issue 9
  - 验收
  - 阻断项
description: "记录 Issue #9 的已实现范围、未运行门禁和阻断项。"
---

# Issue #9 验收状态

结论：R4/R5 基座已经实现。Issue #9 尚未完整验收。稳定发布保持关闭，直到依赖阶段提供运行证据。

| Issue #9 验收项 | 状态 | 证据或阻断项 |
| --- | --- | --- |
| 权限越权测试 | 部分通过 | R1 server 测试覆盖项目隔离和冲突拒绝；R4 集成测试覆盖受限视图和 RBAC 授权 |
| 2 倍目标负载和多人并发写入 | 未运行 | 依赖 R1/R2 的可运行服务、客户端和 UI |
| `pg_dump` 备份和 `pg_restore` 恢复演练 | 通过本地演练 | PostgreSQL 18.7 容器完成备份、恢复、完整性检查和 schema 校验 |
| 服务重启后数据完整，事件流继续 | 部分通过 | R1 已有恢复和健康证据；R4 尚未执行完整服务重启演练 |
| 所有平台资产使用同一 source commit | 工具已实现 | 合并器拒绝 commit、channel、version 不一致 |
| Draft 验证后只 Promote 同一 Draft | 流程已实现 | workflow 只编辑已验证 Draft，不重建资产；尚未在 GitHub 远端执行 |
| macOS/iOS 安装、升级和回滚证据 | 未运行 | 依赖 R2/R3、签名凭据和干净测试设备 |
| Manifest、SHA-256、SBOM、provenance、attestation 可验证 | 部分实现 | Manifest、SBOM 和 attestation workflow 已实现；远端 attestation 尚未执行 |
| 禁止覆盖标签或同名 Stable 资产 | 流程已实现 | prepare 拒绝已有 Release，promote 不上传资产；GitHub 保护规则尚未配置 |

## 当前阻断项

1. R0 的签名和分发策略仍是 `pending`。
2. R1 服务运行、事件流和 2 倍负载没有证据。
3. R2/R3 的 macOS/iOS UI、无障碍和性能没有证据。
4. macOS 和 iOS 签名密钥没有配置。
5. 开发机之外的加密备份目标没有配置。
6. 月度恢复演练和稳定发布恢复演练尚未执行。

## 判定

- `automatic` 检查可以执行。
- `preview` 可以构建部分平台资产。
- Stable 合并校验由 `release/policy.json` 和必需 gate 共同控制。
- 当前配置不能通过 Stable 合并校验。
