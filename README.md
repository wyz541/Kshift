# Kshift

结论：Kshift 是只在内网运行的 macOS/iOS 共享任务工作台。Rust server 是业务状态唯一写入权威。

## 当前状态

- 阶段：R1 Rust 服务核心、R1 Rust client/FFI 和 R2 共享 SwiftUI 基座。
- Active Spec：7 篇领域 Spec，状态 `active`。
- 正式评审：[R0 Spec Review](docs/reviews/2026-11-13-r0-spec-review.md)。
- 实现状态：Rust server、Rust client、C ABI、R2 日计划 UI 和 R3 计划深度切片可构建；macOS/iOS live P0 E2E 已验证。
- R4/R5 基座：备份、恢复、RBAC、部署和 Release 合同已加入。
- 权威入口：[Active Spec 索引](docs/specs/index.md)。
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
- 任务支持 0 至 20 个项目成员作为共同负责人。
- 项目 IANA 时区决定自然日期。用户时区只显示绝对时间戳。
- 协议上限固定为 request 1 MiB、response 和 snapshot 16 MiB、event 256 KiB、attachment 256 MiB。
- revision gap 返回 `ResetRequired`。
- Bearer token 先映射用户，再由数据库检查项目成员关系。
- 标准 gRPC health、JSON 日志、TLS、有界队列和 graceful shutdown 已接入。
- Rust client 提供 TLS、认证 metadata、deadline、取消、有限重试和 snapshot cache。
- `kshift-ffi` 提供 opaque handle、bounded JSON buffer 和 panic containment。

| 路径 | 作用 |
| --- | --- |
| `crates/kshift-domain` | 纯业务类型、校验和不变量 |
| `crates/kshift-contract` | protobuf 生成代码、wire 转换和 typed error |
| `crates/kshift-server` | gRPC、auth、SQLx 事务、outbox 和健康检查 |
| `crates/kshift-client` | TLS channel、typed RPC、retry、revision tracking 和 cache |
| `crates/kshift-ffi` | macOS/iOS C ABI、opaque handles 和 bounded buffers |
| `include` | C header 和 Swift C module map |
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
cargo test --locked -p kshift-client -p kshift-ffi
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
| `Sources/KshiftPresentation` | 共享平台 capability 类型 |
| `Sources/KshiftFFI` | 正式 Rust C ABI wrapper |
| `include` | `kshift-ffi` C header 和 Swift C module map |
| `Sources/KshiftUI` | 共享 SwiftUI 页面、组件、语义色和 Liquid Glass 入口 |
| `Sources/KshiftAppKitAdapter` | macOS 系统能力和 `NSViewRepresentable` |
| `Sources/KshiftUIKitAdapter` | iOS 系统能力和 `UIViewControllerRepresentable` |
| `Apps/KshiftMacOS` | macOS 最小启动入口 |
| `Apps/KshiftIOS` | iOS 最小启动入口 |
| `Kshift.xcodeproj` | 两个 app target 和共享 package 引用 |

当前边界：

- macOS 和 iOS 的 P0 入口只组合同一个 `KshiftRootView`。
- AppKit 和 UIKit 只处理系统能力，不承载产品页面。
- 共享代码不使用 HTTP、PostgreSQL 或 protobuf 类型。
- `#if os(...)` 只出现在 app entry。
- `RustClient` 读取 `kshift-ffi` 的 bounded JSON，并映射为共享 UI 模型。
- `KshiftRustClient` 保留底层 C ABI wrapper。`KshiftRootView` 通过 `RustClient` 读取数据。
- 项目 IANA 时区决定今天按钮、日期选择、日历分桶和每日任务数。
- 用户时区只格式化绝对时间戳。测试可设置 `KSHIFT_USER_TIME_ZONE` 和 `KSHIFT_NOW`。
- Debug 截图使用 `DemoKshiftClient`。Release 入口使用 `RustClient`。
- 当前构建使用 Xcode 27.2 SDK。部署目标为 macOS 26.0 和 iOS 26.0。

### Swift 验证

本地 Xcode 构建统一写入 `build/DerivedData`。完整规则见
[本地构建路径治理](docs/local-build.md)。

| 命令 | 作用 |
| --- | --- |
| `make app-paths` | 输出 macOS 和 iOS Debug App 路径 |
| `make clean-build DRY_RUN=1` | 只输出固定 DerivedData 清理路径 |
| `make check-build-governance` | 检查固定路径、target 和 bundle identifier |

Debug App 显示名为 `Kshift Dev`。Release App 显示名为 `Kshift`。Debug App 禁止复制到 `/Applications` 或 `~/Applications`。Test Runner 只允许测试命令启动。

1. 检查共享边界。

   ```sh
   ./scripts/check-platform-boundaries.sh
   ```

2. 构建 Rust static library。

   ```sh
   ./scripts/build-ffi.sh macos
   ```

3. 运行共享测试。

   ```sh
   swift test
   ```

4. 构建 macOS app。

   ```sh
   xcodebuild -project Kshift.xcodeproj -scheme Kshift-macOS -destination 'platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
   ```

5. 构建 iOS app。

   ```sh
   xcodebuild -project Kshift.xcodeproj -scheme Kshift-iOS -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
   ```

6. 运行 macOS/iOS live P0 E2E。

   ```sh
   make live-ui-e2e
   ```

## Rust client 与 C ABI

Rust client 与 server 共用 `kshift-contract` 和 `kshift-domain`。Swift 只接收 JSON。Swift 不接收 protobuf、tonic 或 SQLx 类型。

| 验收项 | 命令 |
| --- | --- |
| Rust client/FFI tests | `cargo test --locked -p kshift-client -p kshift-ffi` |
| Swift XCTest | `cargo build --locked -p kshift-ffi && swift test` |
| C ABI end-to-end smoke test | `scripts/test-swift-smoke.sh` |
| macOS/iOS XCFramework | `scripts/build-xcframework.sh` |
| Build provenance check | `scripts/verify-xcframework.sh build/kshift-ffi.xcframework` |

`scripts/test-swift-smoke.sh` 启动 loopback TLS gRPC fixture。测试通过 C ABI 调用 project list、snapshot、command 和 subscription。

`kshift-ffi` 的安全规则：

- Handle 是不可解引用的 opaque token。
- 每个 export 捕获 panic。
- 每个 input 和 output 有 byte limit。
- 释放后的 handle 返回 `KSHIFT_STATUS_INVALID_HANDLE`。
- Token 不进入日志、URL、error projection 或 Release asset。
- `unsafe` 只出现在 `kshift-ffi` 的适配层。

## R3 计划深度

R3 已进入共享 `KshiftRootView` 的“计划深度”入口。切片包含以下能力。

- 子任务层级、依赖环检查、跨日排期和延迟任务统计。
- 附件按 SHA-256 去重。单文件上限为 10 MiB。类型白名单校验扩展名和内容。
- Admin 回退创建新 revision。审计记录保存恢复来源和内容摘要。
- 报告固定 source revision。打印和 PNG 导出读取同一份报告。
- 计划深度页面通过 Rust client 的 R3 gRPC/FFI 边界读取 snapshot、写入 status/rollback 并生成报告。Sample boundary 只用于 Demo 和 preview。
- 看板、甘特、历史、报告、Markdown 和附件视图在 macOS/iOS 共用。
- 看板任务卡使用原生 Liquid Glass。甘特、历史和报告使用内容底板。

R3 验收：

```sh
cargo test --workspace
./scripts/test-plan-store.sh
swift test
xcodebuild -project Kshift.xcodeproj -scheme Kshift-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build/DerivedData test
```

验收记录见 [R3 Plan Depth](docs/r3-plan-depth.md)。决策见 [KS-DOMAIN](docs/specs/domain.md) 和 [KS-UI](docs/specs/ui.md)。

## R4/R5 运维与发布

| 内容 | 入口 |
| --- | --- |
| 运维工具 | [`ops/README.md`](ops/README.md) |
| 服务部署 | [`deploy/README.md`](deploy/README.md) |
| Release 合同 | [`release/README.md`](release/README.md) |
| 验收状态 | [`docs/r4-r5/acceptance.md`](docs/r4-r5/acceptance.md) |
| 常用问题 | [`docs/r4-r5/faq.md`](docs/r4-r5/faq.md) |

R4/R5 基座不能替代 R1 至 R3 的产品运行证据。Stable Release 保持关闭。

检查命令：

```bash
./scripts/check-r4-r5.sh
```

PostgreSQL 集成测试需要 `KSHIFT_TEST_ADMIN_DATABASE_URL`。

## 文档入口

| 内容 | 入口 |
| --- | --- |
| Active Spec 索引 | [Specs](docs/specs/index.md) |
| 工程治理规范 | [KS-GOV](docs/specs/governance.md) |
| 产品、领域、架构、运维、UI 和 Release 规范 | [Active Specs](docs/specs/index.md) |
| Discussion 到 Spec 的映射 | [Traceability](docs/spec/traceability.md) |
| 决策过程 | [Research Issues](https://github.com/wyz541/Kshift/issues?q=is%3Aissue+label%3Atype%3Aresearch) |
| 历史决策记录 | [Decision Register](docs/decisions/decision-register.md) |
| 待迁移未决问题 | [Open Questions](docs/decisions/open-questions.md) |
| ADR 历史 | [ADR Index](docs/adr/README.md) |
| 协议和 Release 合同 | [Contracts](docs/contracts/README.md) |
| R1 事务和同步 | [Architecture](docs/architecture.md) |
| R1 运维和恢复 | [Operations](docs/operations.md) |
| R1 验收证据 | [Acceptance](docs/r1-acceptance.md) |
| Rust client、cache 和 C ABI | [Client/FFI](docs/client-ffi.md) |
| R2 功能和证据 | [MVP](docs/MVP.md) |
| R2 截图和性能 | [Evidence](docs/evidence/README.md) |
| R3 计划深度和报告 | [R3 Plan Depth](docs/r3-plan-depth.md) |
| 贡献与评审流程 | [CONTRIBUTING](CONTRIBUTING.md) |

## 当前限制

- 身份认证数据源尚未最终确认。R1 使用可控 bearer token hash。
- Release app 需要配置 `KSHIFT_ENDPOINT`、CA 和 token。登录界面尚未实现。
- UI 已通过 `kshift-ffi` 读取真实 gRPC/PostgreSQL server 数据。
- macOS 和 iOS 分发方式尚未确认。
- Release 仓库、通道和审批人尚未确认。
- 业务成功指标尚未确认。
- PostgreSQL 高可用集群不在首版范围。
- R4/R5 的 30 分钟负载、真实 server launchd 重启和签名平台安装证据尚未运行。
- Stable 签名和分发策略仍为 `pending`。

## 安全边界

- 数据库凭据只从 server 环境读取。
- 客户端 token 只放在 gRPC `authorization: Bearer ...` metadata。
- server 日志不记录 token、数据库 URL、密码或完整 command body。
- auth 文件保存 token hash，不保存 raw token。
- auth 文件必须为 `0600`。
- server 默认拒绝无 TLS 启动。
- FFI 释放后的 handle 返回明确错误。
- FFI 不向 Swift 暴露 protobuf、tonic 或 SQLx 类型。

## 来源

- [Discussion #1：Kshift 内网 macOS/iOS Spec、路线与 Release](https://github.com/wyz541/Kshift/discussions/1)
- [Issue #2：Kshift v1 总目标](https://github.com/wyz541/Kshift/issues/2)
- [Apple HIG：Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
