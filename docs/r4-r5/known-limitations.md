---
slug: "/docs/r4-r5/known-limitations"
title: "R4/R5 已知限制"
type: "reference"
status: "review"
updated: "2026-11-13"
keywords:
  - 已知限制
  - 发布门禁
  - 运行证据
description: "列出 R4/R5 基座尚未完成的产品和发布能力。"
---

# R4/R5 已知限制

结论：当前代码是 R4/R5 基座，不是完整产品发布。

- R1、R2 和 R3 的产品代码尚未在本分支验证。
- 2 倍负载、多人并发写入和事件流重启恢复尚未运行。
- macOS 和 iOS 的安装、升级、卸载、回滚和分发证据尚未生成。
- Liquid Glass、VoiceOver、键盘导航、系统文字大小和性能证据尚未生成。
- macOS 签名身份、公证方式和 iOS 分发方式尚未批准。
- `release/policy.json` 的决策状态是 `pending`。
- 当前没有开发机之外的加密备份存储。
- 当前没有执行月度恢复演练。
- Release workflows 尚未在 GitHub 远端运行。
- GitHub `release` environment、标签保护和 immutable releases 尚未配置。
- `kshift_admin` 只提供固定管理视图，不提供在线 schema 编辑。
- SQL 备份方案提供 4 小时 RPO 和 4 小时 RTO，不提供高可用承诺。
