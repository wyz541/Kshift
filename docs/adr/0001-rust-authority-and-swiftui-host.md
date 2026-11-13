---
slug: /adr/0001-rust-authority-and-swiftui-host
title: ADR-0001 Rust 业务权威和 SwiftUI host
type: decision
status: active
version: "1.0"
updated: "2026-11-13"
keywords:
  - Rust
  - SwiftUI
  - FFI
  - 架构
description: 固定 Rust 业务权威、SwiftUI host 和 C ABI 的责任边界。
---

# ADR-0001 Rust 业务权威和 SwiftUI host

> 结论：Rust 拥有全部非 UI 业务规则。SwiftUI host 只负责呈现和临时界面状态，并通过 `kshift-ffi` 调用 Rust client。

## 1. 状态

`accepted`

## 2. 背景

Kshift 需要 macOS 和 iOS 使用同一业务语义。平台 UI 不能拥有第二套规则。

参考架构原则来自 `wyz541/kmp-translator#703`。Kshift 只复用责任边界，不复制旧平台结论。

## 3. 决策

| 层 | 负责 | 禁止 |
| --- | --- | --- |
| SwiftUI UI host | 渲染、输入、焦点、无障碍、动画和临时 UI 状态 | 直接 HTTP、数据库和权威校验 |
| `kshift-ffi` | C ABI、opaque handle、bounded buffer 和错误映射 | 产品页面 |
| Rust client | typed command、认证、取消、重试、revision 和缓存 | 数据库凭据 |
| Rust server | 鉴权、业务规则、事务、历史和 outbox | UI 状态 |
| PostgreSQL | 持久数据、约束和 schema | 客户端直接连接 |

UI 只发送 typed command。UI 只消费 immutable snapshot 或 event。

## 4. 备选方案

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| Swift 拥有业务规则 | 两端调用简单 | 规则分裂；难验证 | 拒绝 |
| 每个平台各自调用 server | 减少一层 FFI | UI 接触协议；平台重复 | 拒绝 |
| Rust 统一业务，单一 FFI | 规则集中；跨平台一致 | FFI 需要严格边界 | 采用 |

## 5. 后果

- 业务规则需要 Rust 测试。
- FFI 必须有 panic 捕获和内存所有权规则。
- UI 不能复用 gRPC 类型。
- 平台差异只进入 adapter。
- 回滚需要同时回滚 client、server 和 contract。

## 6. 验证

- Swift test harness 创建、调用和销毁 client handle。
- FFI 空值、超长消息、非法 UTF-8 和释放后调用有明确错误。
- UI 构建依赖不包含 tonic、sqlx 或数据库类型。

## 7. 关联

- Spec: [7. 架构](../spec/kshift-spec-v0.1.md#7-架构)
- Decision: `DEC-001`、`DEC-007`
- Contract: [kshift.proto](../../proto/kshift/v1/kshift.proto)
