---
slug: /docs/ffi
title: Kshift FFI
type: reference
status: review
updated: "2026-11-14"
keywords:
  - FFI
  - C ABI
  - Swift
  - Rust
  - JSON
description: 说明 Kshift C ABI 的函数、所有权、Swift 加载规则和内存边界。
---

# Kshift FFI

结论：Swift host 只读取 JSON，不接收 protobuf、tonic、SQLx 或数据库类型。

## C ABI

| 函数组 | 作用 |
| --- | --- |
| `kshift_client_create` / `kshift_client_destroy` | 创建和释放 opaque client handle |
| `kshift_client_list_projects` / `kshift_client_get_snapshot` | 返回项目列表和项目快照 JSON |
| `kshift_client_execute_command` | 执行通用 Task command JSON |
| `kshift_client_get_plan_depth_snapshot` | 返回 R3 snapshot 和 server role JSON |
| `kshift_client_execute_plan_depth_command` | 执行 R3 status 或 rollback command JSON |
| `kshift_client_get_plan_depth_report` | 返回绑定 source revision 的报告 JSON |
| `kshift_client_watch_project` / `kshift_subscription_next` | 创建和轮询事件订阅 |
| `kshift_cancel_token_*` | 创建、取消和释放 cancel token |
| `kshift_last_error_json` | 返回当前线程的最后错误 |
| `kshift_buffer_free` | 释放 Rust owned output buffer |

## 所有权

- Rust 返回的 `KshiftBuffer` 由 Rust 分配。
- 调用方必须用 `kshift_buffer_free` 释放输出 buffer。
- `KshiftClientHandle` 必须用 `kshift_client_destroy` 释放。
- 同一 handle 的调用由 Rust `Mutex` 串行化。
- panic 在 FFI 内捕获。panic 不跨 C ABI。

## Swift 加载

Swift package 通过 `KSHIFT_FFI_PATH` 链接静态库。`scripts/build-ffi.sh macos` 生成 macOS 静态库。生产发布需要生成、签名和嵌入 XCFramework。

Snapshot JSON 的 `audit` 数组包含有界审计记录。Swift 按 `task_id` 将记录映射到任务历史。
