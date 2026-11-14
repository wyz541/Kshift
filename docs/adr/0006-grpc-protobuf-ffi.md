---
slug: /adr/0006-grpc-protobuf-ffi
title: ADR-0006 gRPC、protobuf 和 C ABI
type: decision
status: superseded
version: "1.0"
updated: "2026-11-13"
keywords:
  - gRPC
  - protobuf
  - FFI
  - TLS
description: 固定 Rust client/server 使用 gRPC 和 protobuf，Swift host 使用 C ABI。
---

# ADR-0006 gRPC、protobuf 和 C ABI

> 结论：Rust client 和 server 使用 gRPC over HTTP/2 + TLS。接口由 protobuf 定义。SwiftUI host 只使用 `kshift-ffi` 的 C ABI。

> 历史说明：本 ADR 仅用于追溯。当前规则入口见 [Active Spec 索引](../specs/index.md)，目标 ID 为 `KS-ARCH`。

## 1. 状态

`accepted`

## 2. 背景

Kshift 需要 typed command、snapshot、event、deadline、取消和 server streaming。

SwiftUI host 不能依赖 protobuf、tonic、tokio 或 sqlx 类型。

## 3. 决策

- 协议为 gRPC over HTTP/2 + TLS。
- Stable 使用 rustls 和内部 CA。
- Protobuf package 为 `kshift.v1`。
- Rust 使用 tonic、prost、tokio、tower 和 buf。
- `GetProjectSnapshot`、`ExecuteCommand` 和查询 RPC 使用 unary call。
- `WatchProjectChanges` 使用 server-streaming call。
- Stable 禁用 gRPC reflection。
- 健康检查保持启用。
- Client token 放在 gRPC metadata。
- Client 和 server 使用同一 protobuf 合同。
- SwiftUI host 只接收 opaque handle、typed command、bounded snapshot/event 和错误。
- FFI 捕获 panic。panic 不跨 C ABI。
- `unsafe` 只允许出现在 `kshift-ffi` 的适配层。

## 4. 备选方案

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| REST + JSON | 工具多 | 流式、类型和 schema 检查较弱 | 拒绝 |
| Swift 直接使用 gRPC | 少一层 FFI | 共享业务规则困难 | 拒绝 |
| Rust client + C ABI | 业务和协议隔离 | FFI 需要严格内存规则 | 采用 |

## 5. 后果

- 需要跨语言 handle 生命周期规则。
- 需要固定错误映射。
- 需要 `buf lint` 和 breaking-change 检查。
- 需要生成代码漂移检查。
- 需要显式消息大小上限。
- 客户端取消必须传递到 server。

## 6. 验证

- Swift test harness 可以创建、调用和销毁 handle。
- Host 不包含 protobuf、tonic 或 sqlx 类型。
- Deadlines、取消、重试和 revision gap 有测试。
- `buf lint` 和 breaking-change 检查通过。

## 7. 关联

- Active Spec: [KS-ARCH](../specs/architecture.md#7-合同与兼容)
- Decision: `DEC-007`、`DEC-008`
- Contract: [kshift.proto](../../proto/kshift/v1/kshift.proto)
