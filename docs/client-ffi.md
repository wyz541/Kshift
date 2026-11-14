---
slug: /docs/client-ffi
title: Kshift Rust Client 与 C ABI
type: reference
status: review
updated: "2026-11-14"
keywords:
  - Rust client
  - C ABI
  - FFI
  - TLS gRPC
  - Swift
description: 说明 Kshift Rust client、C ABI、缓存、重试和 Swift 边界。
---

# Kshift Rust Client 与 C ABI

本文记录 Issue #5 的实现边界。Transport、R1 业务类型和 R3 plan-depth boundary 由 Rust workspace 提供。

## 边界

| 层 | 输入 | 输出 | 禁止事项 |
| --- | --- | --- | --- |
| Swift host | JSON command、R3 command、handle、cancel token | JSON snapshot、R3 view、report、event、error | 不接收 protobuf、tonic、SQLx |
| `kshift-ffi` | bounded C slice、opaque token | bounded C buffer、status enum | 不保存 Swift memory |
| `kshift-client` | `domain` command、`kshift.v1` RPC | `domain` snapshot/event | 不执行数据库事务 |
| `kshift-server` | `kshift.v1` RPC | snapshot、event stream、`ErrorDetail` | 不信任客户端 role |

## 运行规则

| 能力 | 规则 |
| --- | --- |
| TLS | 只接受 `https://` endpoint 和 PEM CA |
| Auth | `authorization: Bearer <token>` metadata |
| Deadline | 每次 unary RPC 设置 deadline |
| Cancellation | 调用方通过 cancel token 取消 |
| Retry | 只重试 `Unavailable` 和 `ResourceExhausted` |
| Idempotency | Retry 复用 `(client_id, command_id)` |
| Cache | 最多 3 个项目，128 MiB |
| Gap | 清除项目 cache，发 `reset_required`，再取 snapshot |
| Stream | 有界 queue、heartbeat timeout、jittered backoff |
| Attachment budget | 256 MiB LRU 边界 |
| Unary request | 1 MiB |
| Unary response / snapshot | 16 MiB |
| Single event | 256 KiB |
| Attachment item | 256 MiB |

## R3 C ABI

| 函数 | 用途 |
| --- | --- |
| `kshift_client_get_plan_depth_snapshot` | 返回 R3 snapshot 和 server-authoritative actor role |
| `kshift_client_execute_plan_depth_command` | 执行 status 或 rollback command |
| `kshift_client_get_plan_depth_report` | 返回绑定 source revision 的报告和 HTML 投影 |

R3 command 使用 `request_id`、`project_id`、`expected_revision` 和 tagged command。Server 从认证身份取得 actor 和 role。Client 提供的 actor 或 role 不进入 wire request。

```json
{
  "request_id": "99999999-8888-4777-8666-555555555555",
  "project_id": "11111111-2222-4333-8444-555555555555",
  "expected_revision": 7,
  "command": {
    "type": "set_task_status",
    "value": {
      "task_id": "e0000000-0000-4000-8000-000000000001",
      "status": "done",
      "expected_version": 1
    }
  }
}
```

R3 snapshot JSON 不包含 protobuf 或数据库类型。Swift 将 JSON 投影映射为 `KshiftPlanDepthSnapshot`。

## C ABI 内存

| 对象 | Owner | 释放方式 |
| --- | --- | --- |
| Client handle | `kshift-ffi` | `kshift_client_destroy` |
| Subscription handle | `kshift-ffi` | `kshift_subscription_destroy` |
| Cancel token | `kshift-ffi` | `kshift_cancel_token_destroy` |
| JSON output | `kshift-ffi` | `kshift_buffer_free` |
| Input slice | Swift | FFI 只在调用期间读取 |

## Command JSON

Command envelope 使用 UUID、`expected_project_revision` 和 tagged command。

```json
{
  "client_id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
  "command_id": "99999999-8888-4777-8666-555555555555",
  "project_id": "11111111-2222-4333-8444-555555555555",
  "expected_project_revision": 1,
  "command": {
    "type": "create_task",
    "value": {
      "title": "Ship client",
      "description_markdown": "",
      "status": "todo",
      "priority": "medium",
      "assignee_ids": [],
      "planned_on": "2026-11-13",
      "due_on": "2026-11-20",
      "tags": ["client"],
      "dependency_task_ids": []
    }
  }
}
```

包含 `mutations` 的 `batch_update_tasks` 使用同一 project revision 提交。server 在一个事务内应用全部 mutation。任一版本冲突会回滚整批：

```json
{
  "client_id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
  "command_id": "88888888-7777-4666-8555-444444444444",
  "project_id": "11111111-2222-4333-8444-555555555555",
  "expected_project_revision": 3,
  "command": {
    "type": "batch_update_tasks",
    "value": {
      "mutations": [
        {
          "type": "update_task",
          "value": {
            "task_id": "22222222-2222-4222-8222-222222222222",
            "expected_entity_version": 1,
            "status": "done"
          }
        }
      ]
    }
  }
}
```

## 构建

| 产物 | 命令 |
| --- | --- |
| macOS debug static library | `cargo build -p kshift-ffi` |
| macOS/iOS XCFramework | `scripts/build-xcframework.sh` |
| Artifact verification | `scripts/verify-xcframework.sh build/kshift-ffi.xcframework` |
| Swift XCTest | `swift test` |
| Swift C ABI smoke test | `scripts/test-swift-smoke.sh` |

## 未验证项

- iOS 设备安装和运行不在 Issue #5 内。
- Keychain 实现和登录 UI 不在 Issue #5 内。
- 生产签名和 notarization 不在 Issue #5 内。
- R3 附件上传和通用依赖编辑仍由独立 Task 跟踪。
