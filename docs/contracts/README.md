---
slug: /contracts
title: Kshift 合同基线
type: reference
status: active
updated: "2026-11-14"
keywords:
  - 合同
  - protobuf
  - JSON Schema
  - Release
description: 列出 Kshift v0.1 的协议、FFI 和 Release 合同入口。
---

# Kshift 合同基线

> 结论：`kshift.v1` 是 Rust client 和 server 的协议基线。Release JSON Schema 是 manifest 和 fragment 的结构基线。

## 1. 文件

| 合同 | 文件 | 用途 |
| --- | --- | --- |
| gRPC/protobuf | [kshift.proto](../../proto/kshift/v1/kshift.proto) | 命令、snapshot、事件和服务 |
| Buf 配置 | [buf.yaml](../../buf.yaml) | lint 和 breaking-change 配置 |
| Release manifest | [release-manifest.schema.json](../../schemas/release-manifest.schema.json) | 一次 Release 的事实源 |
| Release fragment | [release-fragment.schema.json](../../schemas/release-fragment.schema.json) | 单平台构建贡献 |
| Manifest 示例 | [release-manifest.example.json](../../schemas/examples/release-manifest.example.json) | Preview 结构示例 |
| Fragment 示例 | [release-fragment.example.json](../../schemas/examples/release-fragment.example.json) | Server 结构示例 |

## 2. 合同文档

| 文档 | 内容 |
| --- | --- |
| [Protocol Contract](protocol-v0.1.md) | 传输、错误、幂等、快照、事件和 FFI 边界 |
| [Release Contract](release-v0.1.md) | 发布通道、manifest、Promotion 和回滚 |

## 3. 状态

合同状态为 `active`。合同结构已冻结。`OQ-011` 已在 R0 正式评审中关闭。

## 4. 变更规则

- `kshift.v1` 内只允许兼容变更。
- 删除字段时保留 field number 和 field name。
- 破坏性变更使用新的 package major version。
- JSON Schema 使用新增可选字段保持兼容。
- 删除或收紧字段时更新 schema version。
- 所有合同变更必须链接 Active Spec 和 Decision Issue。
- 所有示例必须通过自动校验。
