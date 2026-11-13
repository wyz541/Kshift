# Kshift

Kshift 是内网 macOS/iOS 共享任务工作台。Rust server 是业务状态唯一写入权威。

当前状态：R1 服务核心已建立。SwiftUI、Rust client 和 FFI 不属于本阶段。

## R1 能力

- Rust workspace 包含 `kshift-domain`、`kshift-contract` 和 `kshift-server`。
- protobuf 契约使用 `kshift.v1` package。
- gRPC 提供 project list、snapshot、typed command 和 event stream。
- PostgreSQL 18 保存业务数据、审计、幂等结果和 transactional outbox。
- 每个成功写入只增加一个 project revision，并生成一个 outbox event。
- `expected_project_revision` 和 `expected_entity_version` 阻止静默覆盖。
- `WatchProjectChanges` 回放 outbox。revision gap 返回 `ResetRequired`。
- Bearer token 先映射用户，再由数据库检查项目成员关系。
- 标准 gRPC health、JSON 日志、TLS、有界队列和 graceful shutdown 已接入。

## Workspace

| 路径 | 作用 |
| --- | --- |
| `crates/kshift-domain` | 纯业务类型、校验和不变量 |
| `crates/kshift-contract` | protobuf 生成代码、wire 转换和 typed error |
| `crates/kshift-server` | gRPC、auth、SQLx 事务、outbox 和健康检查 |
| `migrations` | PostgreSQL schema migration |
| `proto` | `buf` 管理的 protobuf source |
| `scripts` | migration 恢复和验收脚本 |

## 前置条件

- Rust toolchain 按 `rust-toolchain.toml` 安装。
- PostgreSQL 18.x。
- `psql`、`pg_dump` 和 `pg_restore`。
- `buf` 1.50 或更新版本。

## 本地启动

1. 创建 PostgreSQL 数据库。
2. 设置 `KSHIFT_DATABASE_URL`。
3. 执行 migration。

```sh
export KSHIFT_DATABASE_URL='postgres://kshift_owner@127.0.0.1:5432/kshift'
cargo run -p kshift-server -- migrate
```

4. 从 stdin 创建一个 Admin 用户。

```sh
printf '%s\n' '{"id":"11111111-1111-4111-8111-111111111111","display_name":"Kshift Admin","is_admin":true}' \
  | cargo run -p kshift-server -- bootstrap-user
```

5. 从 stdin 计算 bearer token 的 SHA-256。

```sh
printf '%s\n' 'replace-with-a-random-token' \
  | cargo run -p kshift-server -- hash-token
```

6. 创建 auth JSON 文件。

```json
{
  "tokens": [
    {
      "sha256": "replace-with-hash-token-output",
      "user_id": "11111111-1111-4111-8111-111111111111"
    }
  ]
}
```

7. 限制 auth 文件权限。

```sh
chmod 600 /absolute/path/to/kshift-auth.json
```

8. 启动 TLS server。

```sh
export KSHIFT_AUTH_FILE='/absolute/path/to/kshift-auth.json'
export KSHIFT_TLS_CERT_PATH='/absolute/path/to/server.crt'
export KSHIFT_TLS_KEY_PATH='/absolute/path/to/server.key'
cargo run -p kshift-server -- serve
```

本地测试可以显式禁用 TLS。禁止在内网 Stable 环境禁用 TLS。

```sh
export KSHIFT_ALLOW_INSECURE=true
```

## gRPC API

| RPC | 类型 | 作用 |
| --- | --- | --- |
| `ListProjects` | unary | 返回当前身份可见的项目 |
| `GetProjectSnapshot` | unary | 读取授权项目的完整快照 |
| `ExecuteCommand` | unary | 执行 typed command |
| `WatchProjectChanges` | server stream | 回放 revision 连续事件 |
| `grpc.health.v1.Health` | unary/stream | 标准健康检查 |

写入规则：

- `(client_id, command_id)` 是幂等键。
- 同一幂等键只保存一个结果。
- 项目级写使用 `expected_project_revision`。
- 实体更新和删除使用 `expected_entity_version`。
- 冲突返回 gRPC `ABORTED` 和 typed `ErrorDetail`。
- outbox gap 返回 `ResetRequired`。客户端必须重新获取 snapshot。

## 验证

```sh
cargo fmt --check
buf format -d
buf lint
cargo clippy --workspace --all-targets --all-features -- -D warnings
TEST_DATABASE_URL='postgres://postgres:postgres@127.0.0.1:5432/postgres' cargo test --workspace
```

`TEST_DATABASE_URL` 必须允许创建临时数据库。测试会为每个 case 创建独立测试库。

恢复演练：

```sh
KSHIFT_DATABASE_URL='postgres://postgres:postgres@127.0.0.1:5432/postgres' \
  ./scripts/recovery-test.sh
```

## 安全边界

- 数据库凭据只从 server 环境读取。
- 客户端 token 只放在 gRPC `authorization: Bearer ...` metadata。
- server 日志记录 request、user、project、client 和 command ID。
- server 日志不记录 token、数据库 URL、密码或完整 command body。
- auth 文件保存 token hash，不保存 raw token。
- auth 文件必须为 `0600`。
- server 默认拒绝无 TLS 启动。
- PostgreSQL 不是高可用集群。恢复目标以 Spec 的 RPO/RTO 为准。

## 文档

- `docs/architecture.md`：事务、revision、outbox 和错误映射。
- `docs/operations.md`：角色、TLS、健康检查、迁移和恢复。
- `docs/r1-acceptance.md`：Issue #4 验收证据。
