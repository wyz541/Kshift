---
slug: "/docs/r4-r5/known-limitations"
title: "R4/R5 已知限制"
type: "reference"
status: "review"
updated: "2026-11-27"
keywords:
  - 已知限制
  - 发布门禁
  - 运行证据
description: "列出 R4/R5 基座尚未完成的产品和发布能力。"
---

# R4/R5 已知限制

结论：当前代码是 R4/R5 基座，不是完整产品发布。

- R1 和 R2 已有测试；R3 和完整发布验收尚未完成。
- 100 个持久 gRPC 客户端和 64 个并发事件流已通过 30 分钟 loopback 容量测试。该测试不替代 release TLS bundle 或独立 server 安装包证据。
- Kshift server release bundle 已有用户 LaunchAgent 崩溃重启证据；系统 LaunchDaemon 和 root 安装尚未运行。
- macOS Stable DMG/ZIP 的安装、升级、卸载和回滚已通过；干净外部 Mac 的 Gatekeeper 验收尚未生成。
- Liquid Glass、无障碍和性能最终门禁已通过。
- macOS 使用 policy-approved `ad-hoc`；iOS 仅内部测试，不进入 Stable 分发。
- `release/policy.json` 的决策状态是 `approved`。
- 当前没有开发机之外的加密备份存储。
- 当前没有执行月度恢复演练。
- 远端 Stable server、macOS 和 source candidate、Draft、same-Draft Promote、attestation、latest manifest 和 Check for Updates 已通过。
- `release` environment 有 required reviewer，但 `prevent_self_review=false`，且 repository admin 可以 bypass。独立 release manager approval 尚未强制。
- `v*` tag update/deletion 和 immutable releases 已启用。Stable 同名资产上传仍未执行。
- `kshift_admin` 只提供固定管理视图，不提供在线 schema 编辑。
- SQL 备份方案提供 4 小时 RPO 和 4 小时 RTO，不提供高可用承诺。
