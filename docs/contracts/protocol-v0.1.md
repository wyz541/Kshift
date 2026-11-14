---
slug: /contracts/protocol-v0.1
title: Kshift Protocol Contract v0.1
type: reference
status: active
version: "0.1"
updated: "2026-11-13"
keywords:
  - gRPC
  - protobuf
  - FFI
  - 幂等
  - revision
description: 定义 Kshift v1 的传输、错误、幂等、快照、事件和 FFI 协议规则。
---

# Kshift Protocol Contract v0.1

> 结论：Rust client 和 server 只使用 `kshift.v1` protobuf。SwiftUI host 只使用 `kshift-ffi`。所有写入必须幂等并携带并发前置条件。当前规则见 [KS-ARCH](../specs/architecture.md) 和 [KS-DOMAIN](../specs/domain.md)。

## 1. 合同文件

| 项目 | 值 |
| --- | --- |
| Protobuf | [`proto/kshift/v1/kshift.proto`](../../proto/kshift/v1/kshift.proto) |
| Package | `kshift.v1` |
| 传输 | gRPC over HTTP/2 + TLS |
| 流式接口 | `WatchProjectChanges` |
| Schema version | `2` |
| 状态 | `review` |

## 2. RPC

| RPC | 类型 | 用途 |
| --- | --- | --- |
| `ListProjects` | unary | 返回当前身份可见项目 |
| `GetProjectSnapshot` | unary | 获取完整项目快照 |
| `ExecuteCommand` | unary | 提交一个幂等写命令 |
| `WatchProjectChanges` | server streaming | 回放增量事件和 heartbeat |

- `PROTO-001`：所有 RPC 必须设置 deadline。
- `PROTO-002`：取消必须传递到 server。
- `PROTO-003`：Stable 禁止明文 gRPC。
- `PROTO-004`：Stable 禁止启用 gRPC reflection。
- `PROTO-005`：健康检查保持启用。

## 3. 标识与时间

- 所有 ID 都是 opaque string。客户端不得解析 ID。
- `project_id` 标识隔离边界。
- `client_id` 标识一个客户端安装实例。
- `command_id` 标识一次幂等命令。
- 时间戳使用 UTC RFC 3339。
- 自然日期使用 `YYYY-MM-DD`。
- 项目 `time_zone` 使用 IANA 时区名称。项目时区决定所有自然日期语义。
- 用户时区只影响 UTC 时间戳的显示。用户时区不改变 `planned_on`、`starts_on` 或 `due_on`。
- 用户时区缺失或非法时，客户端回退到项目时区。
- 客户端不得按用户时区移动自然日期，也不得把自然日期转换为 UTC 时间。
- 服务端按用户 ID 升序输出 `assignee_ids`。列表顺序不表示主负责人。
- 空 `assignee_ids` 表示未分配。非空列表最多包含 20 个唯一项目成员。
- 金额和二进制数据不进入 v1 任务合同。

### 3.1 负责人集合

- 任务负责人是无序集合。集合元素是项目成员用户 ID。
- 新建和更新使用替换语义。`TaskPatch.assignee_ids` 缺失表示不变，空 `StringList` 表示清空。
- 服务端拒绝重复 ID、nil ID、非项目成员、停用用户和超过 20 项的列表。
- 多负责人任务在人员看板中出现在每个负责人的人员列。
- 人员筛选使用交集判断。任务命中任一已选负责人时显示。
- 拖到人员列时，负责人集合替换为目标人员。拖到未分配列时，负责人集合清空。

### 3.2 时区

- 项目时区在项目创建时写入，首版不支持修改。
- 项目时区决定看板人员列日期、日历分桶、报告范围、今天和逾期判断。
- 用户时区由当前设备提供，不作为业务数据持久化。
- 用户时区用于显示 `created_at`、`updated_at`、`occurred_at` 等绝对时间戳。
- 同一任务在不同用户时区下必须保持相同 `planned_on`、`starts_on` 和 `due_on`。

## 4. 写入

### 4.1 命令信封

每个写命令使用 `CommandEnvelope`。

| 字段 | 规则 |
| --- | --- |
| `client_id` | 非空；客户端安装内稳定 |
| `command_id` | 非空；客户端生成，建议 UUID |
| `project_id` | 非空；必须匹配授权项目 |
| `expected_project_revision` | 可选；项目级前置条件 |
| `command` | 必须有一个 `oneof` 分支 |

### 4.2 幂等

- `(client_id, command_id)` 在 server 内唯一。
- 重复命令返回首次提交结果。
- 幂等记录保留 7 天。
- 重复请求不得产生第二次写入。
- 命令 ID 不能跨项目复用。
- 冲突不是成功结果。冲突不得写入幂等成功表。

### 4.3 实体版本

- 更新和删除任务必须携带 `expected_entity_version`。
- 批量命令中每个更新或删除独立携带实体版本。
- 任一实体版本过期时，整个批次拒绝。
- 项目级操作可以携带 `expected_project_revision`。
- 授权失败优先于并发冲突。
- 输入校验失败优先于数据库事务。

### 4.4 冲突

- 实体版本不匹配时返回 gRPC `ABORTED`。
- `ErrorDetail.code` 使用 `ERROR_CODE_CONFLICT`。
- 冲突详情包含 `current_project_revision`。
- 冲突详情包含 `entity_id` 和 `current_entity_version`。
- Client 不得自动合并任务内容。
- Client 不得自动覆盖冲突。
- UI 必须让用户选择刷新或重新提交。

## 5. Snapshot

`ProjectSnapshot` 是不可变完整视图。

| 字段 | 规则 |
| --- | --- |
| `schema_version` | 必须为 `2` |
| `revision` | 对应项目快照 revision |
| `project` | 必须有值 |
| `users` | 只包含项目成员身份 |
| `members` | 只包含当前项目成员 |
| `tasks` | 只包含当前项目任务 |
| `audit` | 最多 100 条项目审计记录，按时间升序 |
| `project.time_zone` | 项目 IANA 时区；决定自然日期 |
| `generated_at` | UTC 时间；客户端按用户时区显示 |

审计记录包含 `id`、`revision`、`action`、`summary`、`task_id`、`actor_id` 和 `occurred_at`。`revision` 在 outbox 记录过期后可以为空。

- `PROTO-101`：Snapshot 必须通过 `project_id` 隔离。
- `PROTO-102`：Snapshot 不得包含数据库凭据。
- `PROTO-103`：Snapshot 不得包含未授权项目实体。
- `PROTO-104`：Server 必须执行项目级授权。
- `PROTO-105`：客户端提交的 role 或 permission 不作为授权依据。
- `PROTO-106`：Snapshot 审计记录必须有固定上限，不得随审计表无限增长。

## 6. 事件流

`WatchProjectChanges(since_revision)` 从 outbox 回放事件。

- 事件 revision 必须单调递增。
- 每个成功写事务只生成一个 `ProjectChangeEvent`。
- Revision 不连续时返回 `ResetRequired`。
- Client 收到 `ResetRequired` 后清除对应项目缓存。
- Client 随后调用 `GetProjectSnapshot`。
- Heartbeat 间隔为 15 秒。
- 重连退避从 500 ms 开始，上限 30 秒。
- 慢消费者超限时断开。
- 写请求不得等待慢消费者。
- Outbox 保留 7 天。

## 7. 错误

| gRPC code | App code | 场景 |
| --- | --- | --- |
| `UNAUTHENTICATED` | `ERROR_CODE_AUTH_REQUIRED` | 缺少或无效身份 |
| `PERMISSION_DENIED` | `ERROR_CODE_FORBIDDEN` | 项目授权失败 |
| `INVALID_ARGUMENT` | `ERROR_CODE_INVALID_INPUT` | 字段或大小非法 |
| `NOT_FOUND` | `ERROR_CODE_INVALID_STATE` | 实体不存在或已删除 |
| `ALREADY_EXISTS` | `ERROR_CODE_ALREADY_EXISTS` | 唯一约束或幂等键冲突 |
| `FAILED_PRECONDITION` | `ERROR_CODE_FAILED_PRECONDITION` | 状态不允许或事件无效 |
| `ABORTED` | `ERROR_CODE_CONFLICT` | 实体版本过期 |
| `FAILED_PRECONDITION` | `ERROR_CODE_RESET_REQUIRED` | revision gap 或 schema mismatch |
| `RESOURCE_EXHAUSTED` | `ERROR_CODE_LIMIT_EXCEEDED` | 容量或消息大小超限 |
| `UNAVAILABLE` | `ERROR_CODE_INTERNAL` | 服务暂时不可用 |
| `INTERNAL` | `ERROR_CODE_INTERNAL` | 未分类服务端失败 |

`ErrorDetail` 放入 gRPC status details。错误消息不得包含秘密或完整敏感请求体。

## 8. 大小限制

所有消息和缓冲必须有显式上限。以下值由 `DEC-027` 固定。

| 对象 | 上限 |
| --- | ---: |
| gRPC unary request | 1 MiB |
| gRPC unary response | 16 MiB |
| Snapshot response | 16 MiB |
| Single event | 256 KiB |
| Attachment cache item | 256 MiB |

- 超过上限时返回 `RESOURCE_EXHAUSTED`。
- Server、Rust client 和 FFI 必须使用同一组上限常量。
- 长度检查必须在分配大缓冲前完成。
- FFI 必须传递 buffer length。
- FFI 不得依赖 NUL 终止符。
- FFI 不得让 Rust 持有未定义生命周期的 Swift 内存。

## 9. C ABI 边界

`kshift-ffi` 的 v1 设计边界如下。

| 能力 | 规则 |
| --- | --- |
| Client handle | opaque pointer；create 和 destroy 配对 |
| Snapshot | 有界 byte buffer 或 typed FFI view |
| Command | typed FFI struct 转换为 Rust command |
| Event stream | callback 或 poll handle；必须支持取消 |
| Error | stable status enum、error code 和 owned message |
| Panic | 在 FFI 边界捕获；不得跨 C ABI |
| Ownership | Rust 分配的结果由显式 release 函数释放 |
| Threading | handle 的并发规则必须写入头文件 |

- `FFI-001`：Swift host 不接收 protobuf 类型。
- `FFI-002`：Swift host 不接收 tonic channel。
- `FFI-003`：Swift host 不接收 sqlx 类型。
- `FFI-004`：释放后的 handle 调用必须返回明确错误。
- `FFI-005`：空指针、非法 UTF-8 和超长消息必须返回明确错误。
- `FFI-006`：panic 不得跨 C ABI。
- `FFI-007`：`unsafe` 只允许出现在 FFI 适配层。

## 10. 兼容

- Package major version 变化表示 breaking change。
- 字段编号不得复用。
- 删除字段时使用 `reserved` 标记编号和名称。
- 新字段必须可被旧客户端忽略。
- Enum 新值必须保持 zero 值语义。
- 生成代码必须可重现。
- CI 必须执行 `buf lint` 和 breaking-change 检查。

## 11. 关联

- [KS-DOMAIN](../specs/domain.md)
- [KS-ARCH](../specs/architecture.md)
- [KS-OPS](../specs/operations.md)
- [ADR-0005](../adr/0005-revisioned-snapshot-outbox.md)
- [ADR-0006](../adr/0006-grpc-protobuf-ffi.md)
