---
slug: "/docs/r4-r5/known-limitations"
title: "R4/R5 已知限制"
type: "reference"
status: "review"
updated: "2026-11-14"
keywords:
  - 已知限制
  - 发布门禁
  - 运行证据
description: "列出 R4/R5 基座尚未完成的产品和发布能力。"
---

# R4/R5 已知限制

结论：当前代码是 R4/R5 基座，不是完整产品发布。

- R1 和 R2 已有测试；R3 和完整发布验收尚未完成。
- 30 分钟服务层 2 倍负载已运行；100 个持久网络客户端和 64 个并发事件流尚未测量。
- Kshift server release bundle 已有用户 LaunchAgent 崩溃重启证据；系统 LaunchDaemon 和 root 安装尚未运行。
- iOS Simulator 和 macOS preview bundle 已有安装升级回滚证据；签名分发和干净机器证据尚未生成。
- Liquid Glass、无障碍和性能已有开发证据；最终发布门禁尚未审核。
- macOS 签名身份、公证方式和 iOS 分发方式尚未批准。
- `release/policy.json` 的决策状态是 `pending`。
- 当前没有开发机之外的加密备份存储。
- 当前没有执行月度恢复演练。
- Release workflows 尚未在 GitHub 远端运行。
- GitHub `release` environment、标签保护和 immutable releases 尚未配置。
- `kshift_admin` 只提供固定管理视图，不提供在线 schema 编辑。
- SQL 备份方案提供 4 小时 RPO 和 4 小时 RTO，不提供高可用承诺。
