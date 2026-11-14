---
slug: "/docs/r4-r5/evidence/2026-11-14-preview-lifecycle"
title: "R4/R5 preview lifecycle evidence"
type: "evidence"
status: "review"
updated: "2026-11-14"
keywords:
  - macOS
  - iOS
  - install
  - upgrade
  - rollback
description: "记录 unsigned preview 的 macOS bundle 和 iOS Simulator 安装升级回滚结果。"
---

# R4/R5 preview lifecycle evidence

结论：preview 的 iOS Simulator 安装、升级和回滚通过。macOS 只验证 ad-hoc bundle 复制和版本切换。

| 平台 | 安装 | 升级 | 回滚 | 证据范围 |
| --- | --- | --- | --- | --- |
| iOS Simulator | 通过 | 通过 | 通过 | `iPhone 18 Pro` |
| macOS | bundle-copy | 通过 | 通过 | ad-hoc Debug bundle |

## 命令

```bash
make preview-lifecycle
```

## 未覆盖

- macOS Developer ID 签名、安装器和干净机器验收。
- iOS TestFlight 或内部签名 IPA 验收。
- macOS 真实用户 Applications 目录写入。
- 发布服务器下载和远端 SHA-256 校验。
