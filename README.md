---
title: "Kshift"
status: "active"
source: "https://github.com/wyz541/Kshift/issues/8"
---

# Kshift

R3 计划深度纵向切片已实现。这个切片包含子任务、依赖、跨日甘特、Markdown、附件、历史回退和报告。

## 当前交付

- Rust 核心拥有 R3 业务不变量。
- PostgreSQL 18 保存 snapshot、历史状态和附件内容。
- macOS 与 iOS 使用同一个 SwiftUI 页面。
- 任务卡使用原生 Liquid Glass。
- 甘特、历史和报告使用稳定内容底板。
- 打印和图片导出读取同一个 typed report snapshot。

R1 server、R2 shared SwiftUI 和 R3 plan depth 位于同一 workspace。完整 R3 RPC 接线尚未完成。当前 R3 app 使用 typed in-memory boundary 提供运行样例。

## 结构

| 路径 | 职责 |
| --- | --- |
| `crates/kshift-domain` | R1 业务类型、校验和不变量 |
| `crates/kshift-contract` | protobuf 生成代码、wire 转换和 typed error |
| `crates/kshift-server` | gRPC、auth、SQLx 事务、outbox 和健康检查 |
| `crates/kshift-core/src/plan_depth.rs` | R3 业务权威、命令、报告和单元测试 |
| `crates/kshift-plan-store` | R3 PostgreSQL snapshot、历史状态和附件持久化 |
| `migrations/0002_plan_depth.sql` | R3 schema |
| `Sources/KshiftPresentation/PlanDepth` | typed snapshot、command、presentation mapping |
| `Sources/KshiftUI/PlanDepth` | 共享 SwiftUI feature slice 和报告导出 |
| `Sources/KshiftAppKitAdapter` | macOS 保存和打印能力 |
| `Sources/KshiftUIKitAdapter` | iOS 分享和打印能力 |
| `Apps/KshiftMacOS` | macOS 启动入口 |
| `Apps/KshiftIOS` | iOS 启动入口 |
| `Apps/KshiftIOSUITests` | 流程、触控区域、字号和对比度审计 |

## 构建与测试

1. 生成 Xcode 工程。

   ```sh
   xcodegen generate
   ```

2. 运行 Swift 测试。

   ```sh
   swift test
   ```

3. 构建 macOS app。

   ```sh
   xcodebuild -project Kshift.xcodeproj -scheme Kshift-macOS \
     -configuration Debug -destination 'platform=macOS' \
     build CODE_SIGNING_ALLOWED=NO
   ```

4. 构建 iOS app。

   ```sh
   xcodebuild -project Kshift.xcodeproj -scheme Kshift-iOS \
     -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17e' \
     build CODE_SIGNING_ALLOWED=NO
   ```

5. 运行 iOS UI 和无障碍审计。

   ```sh
   xcodebuild -project Kshift.xcodeproj -scheme Kshift-iOS \
     -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17e' \
     test CODE_SIGNING_ALLOWED=NO
   ```

6. 运行 Rust 领域测试。

   ```sh
   cargo test -p kshift-core
   ```

7. 运行 PostgreSQL 18 集成测试。

   ```sh
   ./scripts/test-plan-store.sh
   ```

## 当前边界

- App 当前使用 `InMemoryKshiftPlanDepthBoundary` 提供可运行样例。
- 正式 Rust FFI 接线属于 Issue #5。
- 当前 PostgreSQL 适配器保存 R3 snapshot。完整 server RPC 接线由后续集成完成。
- 当前 SDK 为 Xcode 27.2。部署目标保持 macOS 26.0 和 iOS 26.0。

验收证据见 [`docs/r3-plan-depth.md`](docs/r3-plan-depth.md)。
