# Kshift Rust Client 与 C ABI

本文记录 Issue #5 的实现边界。Transport 和业务类型由 R1 workspace 提供。

## 边界

| 层 | 输入 | 输出 | 禁止事项 |
| --- | --- | --- | --- |
| Swift host | JSON command、handle、cancel token | JSON snapshot、event、error | 不接收 protobuf、tonic、SQLx |
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
