---
slug: "/docs/r4-r5"
title: "R4/R5 文档入口"
type: "reference"
status: "review"
updated: "2026-11-13"
keywords:
  - R4
  - R5
  - 运维
  - 发布
description: "提供 R4/R5 基座的验收、运维、发布和回滚入口。"
---

# R4/R5 文档入口

| 文档 | 用途 |
| --- | --- |
| [acceptance.md](acceptance.md) | Issue #9 验收状态和阻断项 |
| [operations.md](operations.md) | 备份、恢复、角色、日志和启动恢复 |
| [release.md](release.md) | Candidate、Draft、Promote 和 GitHub 设置 |
| [rollback.md](rollback.md) | macOS、iOS、服务和数据库回滚 |
| [faq.md](faq.md) | 常见问题 |
| [known-limitations.md](known-limitations.md) | 当前限制和不实声明边界 |
| [evidence/2026-11-13-local.md](evidence/2026-11-13-local.md) | PostgreSQL 18.7 本地证据 |
| [evidence/2026-11-14-load-restart.md](evidence/2026-11-14-load-restart.md) | 2 倍负载、多人写入和 API 重启证据 |
| [evidence/2026-11-16-network-capacity.md](evidence/2026-11-16-network-capacity.md) | 100 个持久 gRPC 客户端和 64 个并发事件流证据 |
| [evidence/2026-11-16-release-candidate.md](evidence/2026-11-16-release-candidate.md) | Preview server/source candidate 和 attestation 证据 |
| [evidence/2026-11-16-draft-promote.md](evidence/2026-11-16-draft-promote.md) | Preview Draft、byte verification 和 same-Draft Promote 证据 |
| [evidence/2026-11-16-platform-candidates.md](evidence/2026-11-16-platform-candidates.md) | Server、macOS、iOS 和 source 同源 Preview candidate 证据 |
| [evidence/2026-11-16-release-protection.md](evidence/2026-11-16-release-protection.md) | Release environment、tag protection 和 immutable releases 证据 |
| [evidence/2026-11-14-launchd-restart.md](evidence/2026-11-14-launchd-restart.md) | Kshift server LaunchAgent 重启证据 |
| [evidence/2026-11-14-preview-lifecycle.md](evidence/2026-11-14-preview-lifecycle.md) | iOS Simulator 和 macOS preview lifecycle 证据 |
