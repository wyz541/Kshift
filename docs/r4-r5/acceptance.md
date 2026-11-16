---
slug: "/docs/r4-r5/acceptance"
title: "Issue #9 验收状态"
type: "report"
status: "review"
updated: "2026-11-14"
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
| 2 倍目标负载和多人并发写入 | 通过 | 30 分钟测试通过 100 个持久 gRPC 客户端、64 个并发事件流、40 个并发写尝试、200 次 snapshot 突发、16 个写事务上限和多人冲突检查；无事件丢失、gap、流错误或重连 |
| `pg_dump` 备份和 `pg_restore` 恢复演练 | 通过本地演练 | PostgreSQL 18.7 容器完成备份、恢复、完整性检查和 schema 校验 |
| 服务重启后数据完整，事件流继续 | 通过本地 LaunchAgent | release bundle 经 `SIGKILL` 后自动重启；health、outbox 回放、revision 连续性和新写入通过；系统 LaunchDaemon 未运行 |
| 所有平台资产使用同一 source commit | 部分通过 | 远端 preview server/source candidate 使用同一 commit；macOS、iOS 和 source 的完整集尚未一起构建 |
| Draft 验证后只 Promote 同一 Draft | 通过 preview 演练 | Draft `v0.1.0-preview.1` 通过 bytes、manifest 和 attestation 验证；Promote 只编辑同一个 Draft；server/source hash 未变化 |
| macOS/iOS 安装、升级和回滚证据 | 部分通过 | iOS Simulator 安装、升级、回滚通过；macOS bundle 切换通过；签名和干净机器未验收 |
| Manifest、SHA-256、SBOM、provenance、attestation 可验证 | 部分通过 | Preview candidate、Draft 和 Promote 后的 manifest、SHA-256、SBOM 和 server/source attestation 已验证；Stable 资产尚未验证 |
| 禁止覆盖标签或同名 Stable 资产 | 流程已实现 | prepare 拒绝已有 Release，promote 不上传资产；GitHub 保护规则尚未配置 |

## 当前阻断项

1. R0 的签名和分发策略仍是 `pending`。
2. R2 已有 live P0 证据；R3 和最终发布 UI、无障碍、性能门禁尚未完成。
3. macOS 和 iOS 签名密钥没有配置；已安装 preview lifecycle 证据不等于 Stable 安装证据。
4. Kshift server 的用户 LaunchAgent 重启已通过；系统 LaunchDaemon、root 安装和独立服务用户没有运行。
5. 开发机之外的加密备份目标没有配置。
6. 月度恢复演练和稳定发布恢复演练尚未执行。

## 判定

- `automatic` 检查可以执行。
- `preview` 可以构建部分平台资产。
- Stable 合并校验由 `release/policy.json` 和必需 gate 共同控制。
- 当前配置不能通过 Stable 合并校验。
