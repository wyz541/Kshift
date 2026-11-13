# Kshift

Kshift 是 macOS/iOS 共享日计划 MVP。共享 SwiftUI 通过 Rust C ABI 读写任务快照。

## 当前范围

| 层 | 实现 |
| --- | --- |
| 共享 UI | `KshiftUI`：项目切换、人员/日期看板、日历、表格、筛选、排序和批量状态 |
| 原生视觉 | SwiftUI Liquid Glass：`GlassEffectContainer`、`glassEffect`、`.glass` 和 `.glassProminent` |
| 平台适配 | AppKit/UIKit 只提供系统设置和触感能力 |
| Swift 边界 | `RustClient` 动态调用 `kshift-ffi` |
| Rust client | 类型化命令、revision 校验和幂等 request ID |
| Rust domain | 项目隔离、任务版本冲突、批量原子校验、历史和审计 |

当前 transport 是进程内 Rust store。真实 gRPC/PostgreSQL 由 #4 接入。UI 的调用边界已经固定为 `kshift-ffi`。

## 构建

环境要求：

- macOS 26.0 或更新版本。
- Xcode 26.0 或更新版本。
- XcodeGen 2.46 或更新版本。
- Rust 1.99.1。

执行以下步骤：

1. 安装 XcodeGen。

   ```bash
   brew install xcodegen
   ```

2. 生成 Rust FFI、Xcode 工程和 Swift package 缓存。

   ```bash
   make bootstrap
   ```

3. 构建 macOS App。

   ```bash
   make mac-build
   ```

4. 构建 iOS App。

   ```bash
   make ios-build
   ```

## 运行

1. 打开 `Kshift.xcodeproj`。
2. 选择 `KshiftMac` 或 `KshiftIOS` scheme。
3. 启动 App。

Xcode 的 pre-build script 会构建并复制 `libkshift_ffi.dylib`。Swift 代码不链接 protobuf、tonic、SQLx 或数据库类型。

## 测试

运行 Rust 和 Swift 单元测试：

```bash
make test
```

运行 macOS/iOS 构建和 iOS UI 测试：

```bash
make verify
```

查看 FFI 和冲突证据：

```bash
make ffi
make rust-test
make swift-test
```

## 界面证据

- macOS 看板：[`docs/evidence/macos-board.jpg`](docs/evidence/macos-board.jpg)
- iOS 看板：[`docs/evidence/ios-board.png`](docs/evidence/ios-board.png)
- 测试说明：[`docs/evidence/README.md`](docs/evidence/README.md)

## 关键规则

- 每个命令携带 `expected_revision`。
- 每个任务写入携带 `expected_task_version`。
- 冲突返回 `version_conflict` 或 `revision_conflict`。
- 冲突不替换当前快照。编辑器保留用户草稿。
- 批量状态更新先校验全部版本。任一版本过期时，批量更新不写入。
- 同一 request ID 只执行一次。
- 项目 ID 只读取对应项目快照。
- 共享 UI 不使用 `#if os(...)`。
- 交互卡片使用原生 `Glass.regular`。
- 同列卡片共用一个 `GlassEffectContainer`。
- 每列最多显示 12 个玻璃卡片。其余任务使用清晰内容行。
- 卡片文字放在系统内容底板上。
- Reduce Transparency 和 Increase Contrast 会改用不透明内容底板。

## 目录

```text
crates/                 Rust domain、client 和 C ABI
Sources/KshiftCore/     Swift typed models 和 FFI bridge
Sources/KshiftUI/       共享 SwiftUI feature slice
Sources/KshiftPlatform/ AppKit/UIKit capability adapter
Apps/                   macOS/iOS app entry 和 UI tests
Tests/                  Swift unit 和 FFI integration tests
scripts/                FFI 和验收脚本
docs/                   实现和证据说明
```

## 已知限制

- Rust transport 当前是内存实现。进程重启会恢复演示数据。
- 真实实时事件流依赖 #4。
- 动态 FFI 产物用于开发构建。发布版仍应生成签名 XCFramework。
- macOS/iOS 性能读数尚未采集。
- VoiceOver 和系统文字大小的最终人工验收尚未完成。
- 未运行证据不标记为已通过。
