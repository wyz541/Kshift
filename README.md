# Kshift

结论：Kshift 是只在内网运行的 macOS/iOS 共享任务工作台。Rust server 是业务状态唯一写入权威。

## 当前状态

- 阶段：R1 Rust 服务核心和 R2 共享 SwiftUI 基座。
- Spec 版本：`0.1`。
- 实现状态：Rust server、PostgreSQL schema 和共享 UI 基座可构建；正式 Rust client、FFI 和 P0 日计划 MVP 尚未完成。
- 权威入口：[Kshift Spec v0.1](docs/spec/kshift-spec-v0.1.md)。
- 讨论来源：[Discussion #1](https://github.com/wyz541/Kshift/discussions/1)。
- 总任务：[Issue #2](https://github.com/wyz541/Kshift/issues/2)。

## 首版边界

| 项目 | 首版决策 |
| --- | --- |
| 平台 | macOS 26.0+、iOS 26.0+ |
| UI | 一套共享 SwiftUI；平台能力使用 adapter |
| 视觉 | Apple 原生 Liquid Glass |
| 业务逻辑 | Rust 唯一 owner |
| 服务 | Rust server、gRPC、PostgreSQL 18 |
| 部署 | 内网 macOS 开发机 |
| 同步 | revisioned snapshot 和 transactional outbox |
| 发布 | GitHub 多平台 Release |

## 系统边界

下图展示首版的唯一定位链。UI 不绕过 Rust client。

```mermaid
flowchart LR
  UI["macOS / iOS SwiftUI UI"] -->|"C ABI"| FFI["kshift-ffi"]
  FFI --> CL["Rust client"]
  CL -->|"gRPC over TLS"| SV["Rust server"]
  SV -->|"SQL transaction"| DB[("PostgreSQL 18")]
  SV -->|"snapshot / events"| CL
```

## R1 服务核心

- protobuf 契约使用 `kshift.v1` package。
- gRPC 提供 `ListProjects`、`GetProjectSnapshot`、`ExecuteCommand` 和 `WatchProjectChanges`。
- PostgreSQL 18 保存业务数据、审计、幂等结果和 transactional outbox。
- 每个成功写入只增加一个 project revision，并生成一个 outbox event。
- `expected_project_revision` 和 `expected_entity_version` 阻止静默覆盖。
- revision gap 返回 `ResetRequired`。
- Bearer token 先映射用户，再由数据库检查项目成员关系。
- 标准 gRPC health、JSON 日志、TLS、有界队列和 graceful shutdown 已接入。

| 路径 | 作用 |
| --- | --- |
| `crates/kshift-domain` | 纯业务类型、校验和不变量 |
| `crates/kshift-contract` | protobuf 生成代码、wire 转换和 typed error |
| `crates/kshift-server` | gRPC、auth、SQLx 事务、outbox 和健康检查 |
| `migrations` | PostgreSQL schema migration |
| `proto` | `buf` 管理的 protobuf source |
| `scripts/recovery-test.sh` | migration rollback 和 restore 演练 |

### 服务启动

1. 创建 PostgreSQL 18 数据库。
2. 设置 `KSHIFT_DATABASE_URL`。
3. 执行 migration。

```sh
export KSHIFT_DATABASE_URL='postgres://kshift_owner@127.0.0.1:5432/kshift'
cargo run -p kshift-server -- migrate
```

4. 从 stdin 创建 Admin 用户。

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

### Rust 验证

```sh
cargo fmt --all -- --check
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

## 共享 SwiftUI 基座

| 路径 | 职责 |
| --- | --- |
| `Sources/KshiftPresentation` | 业务快照、typed command 和 presentation mapping |
| `Sources/KshiftFFI` | Swift FFI 边界和可替换的内存实现 |
| `Sources/KshiftUI` | 共享 SwiftUI 页面、组件、语义色和 Liquid Glass 入口 |
| `Sources/KshiftAppKitAdapter` | macOS 系统能力和 `NSViewRepresentable` |
| `Sources/KshiftUIKitAdapter` | iOS 系统能力和 `UIViewControllerRepresentable` |
| `Apps/KshiftMacOS` | macOS 最小启动入口 |
| `Apps/KshiftIOS` | iOS 最小启动入口 |
| `Kshift.xcodeproj` | 两个 app target 和共享 package 引用 |

当前边界：

- macOS 和 iOS 组合同一个 `KshiftDayPlanFeatureView`。
- AppKit 和 UIKit 只处理系统能力，不承载产品页面。
- 共享代码不使用 HTTP、PostgreSQL 或 protobuf 类型。
- `#if os(...)` 只出现在 app entry。
- `InMemoryKshiftFFIBoundary` 只提供界面基座样例。Issue #5 接入正式 `kshift-ffi`。
- 当前构建使用 Xcode 27.2 SDK。部署目标为 macOS 26.0 和 iOS 26.0。

### Swift 验证

1. 检查共享边界。

   ```sh
   ./Scripts/check-platform-boundaries.sh
   ```

2. 运行共享测试。

   ```sh
   swift test
   ```

3. 构建 macOS app。

   ```sh
   xcodebuild -project Kshift.xcodeproj -scheme Kshift-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
   ```

4. 构建 iOS app。

   ```sh
   xcodebuild -project Kshift.xcodeproj -scheme Kshift-iOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
   ```

## 文档入口

| 内容 | 入口 |
| --- | --- |
| 产品、技术、UI 和验收规范 | [Spec v0.1](docs/spec/kshift-spec-v0.1.md) |
| Discussion 到 Spec 的映射 | [Traceability](docs/spec/traceability.md) |
| 关键决策状态 | [Decision Register](docs/decisions/decision-register.md) |
| 未决项、owner 和截止日期 | [Open Questions](docs/decisions/open-questions.md) |
| 架构决策记录 | [ADR Index](docs/adr/README.md) |
| 协议和 Release 合同 | [Contracts](docs/contracts/README.md) |
| R1 事务和同步 | [Architecture](docs/architecture.md) |
| R1 运维和恢复 | [Operations](docs/operations.md) |
| R1 验收证据 | [Acceptance](docs/r1-acceptance.md) |
| 贡献与评审流程 | [CONTRIBUTING](CONTRIBUTING.md) |

## 当前限制

- 身份认证数据源尚未最终确认。R1 使用可控 bearer token hash。
- 正式 Rust client 和 FFI 尚未完成。
- macOS 和 iOS 分发方式尚未确认。
- Release 仓库、通道和审批人尚未确认。
- 业务成功指标尚未确认。
- P0 日计划流程、无障碍证据和性能读数尚未完成。
- PostgreSQL 高可用集群不在首版范围。

## 安全边界

- 数据库凭据只从 server 环境读取。
- 客户端 token 只放在 gRPC `authorization: Bearer ...` metadata。
- server 日志不记录 token、数据库 URL、密码或完整 command body。
- auth 文件保存 token hash，不保存 raw token。
- auth 文件必须为 `0600`。
- server 默认拒绝无 TLS 启动。

## 来源

- [Discussion #1：Kshift 内网 macOS/iOS Spec、路线与 Release](https://github.com/wyz541/Kshift/discussions/1)
- [Issue #2：Kshift v1 总目标](https://github.com/wyz541/Kshift/issues/2)
- [Apple HIG：Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
