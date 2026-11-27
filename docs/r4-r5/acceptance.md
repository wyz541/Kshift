---
slug: "/docs/r4-r5/acceptance"
title: "Issue #9 验收状态"
type: "report"
status: "review"
updated: "2026-11-27"
keywords:
  - Issue 9
  - 验收
  - 阻断项
description: "记录 Issue #9 的已实现范围、未运行门禁和阻断项。"
---

# Issue #9 验收状态

结论：R4/R5 基座已经实现。`v0.1.0` Stable 已按 server、macOS、source scope 发布；系统级安装、外部备份和独立 release manager 仍有未覆盖项。

| Issue #9 验收项 | 状态 | 证据或阻断项 |
| --- | --- | --- |
| 权限越权测试 | 部分通过 | R1 server 测试覆盖项目隔离和冲突拒绝；R4 集成测试覆盖受限视图和 RBAC 授权 |
| 2 倍目标负载和多人并发写入 | 通过 | 30 分钟测试通过 100 个持久 gRPC 客户端、64 个并发事件流、40 个并发写尝试、200 次 snapshot 突发、16 个写事务上限和多人冲突检查；无事件丢失、gap、流错误或重连 |
| `pg_dump` 备份和 `pg_restore` 恢复演练 | 通过本地演练 | PostgreSQL 18.7 容器完成备份、恢复、完整性检查和 schema 校验 |
| 服务重启后数据完整，事件流继续 | 通过本地 LaunchAgent | release bundle 经 `SIGKILL` 后自动重启；health、outbox 回放、revision 连续性和新写入通过；系统 LaunchDaemon 未运行 |
| 所有平台资产使用同一 source commit | 通过 preview 构建 | 远端 preview server、macOS、iOS 和 source candidate 使用同一 commit `96afb71a757c0f8c2f38984f1bc12536a60cefa8` |
| Draft 验证后只 Promote 同一 Draft | 通过 preview 演练 | Draft `v0.1.0-preview.1` 通过 bytes、manifest 和 attestation 验证；Promote 只编辑同一个 Draft；server/source hash 未变化 |
| macOS/iOS 安装、升级和回滚证据 | 部分通过 | macOS/iOS unsigned Preview candidate 构建通过；Simulator 和 bundle preview lifecycle 通过；签名、干净机器和物理设备未验收 |
| Manifest、SHA-256、SBOM、provenance、attestation 可验证 | 通过 | Stable candidate、Draft、same-Draft Promote、manifest、SHA-256、SBOM 和平台 attestation 已验证；latest manifest 返回 `promoted` |
| 禁止覆盖标签或同名 Stable 资产 | 部分通过 | `v*` ruleset 阻止 update 和 deletion；immutable releases 已启用；同名 Stable 资产上传尚未执行 |

## 当前阻断项

1. R0 的签名和分发策略已批准：macOS 使用 ad-hoc，iOS 仅内部测试。
2. R2 live P0、R3、Liquid Glass、无障碍和性能门禁已通过。
3. macOS Stable lifecycle 和 Check for Updates 已通过；iOS 仍不属于 Stable 分发范围。
4. Kshift server 的用户 LaunchAgent 重启已通过；系统 LaunchDaemon、root 安装和独立服务用户没有运行。
5. 开发机之外的加密备份目标没有配置。
6. 月度恢复演练和稳定发布恢复演练尚未执行。

## 判定

- `automatic` 检查可以执行。
- `preview` 可以构建部分平台资产。
- Stable 合并校验由 `release/policy.json` 和必需 gate 共同控制。
- 当前配置已通过 Stable candidate、merge、Draft verification 和 same-Draft Promote；新增变更必须重新提供匹配的 runtime evidence。
