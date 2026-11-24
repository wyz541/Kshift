# Kshift Windows gpui 外壳

结论：本 crate 是 Windows Preview 客户端窗口。它负责人员排期和任务编辑器的渲染、焦点、键盘输入与临时 UI 状态。

## 为什么是独立 workspace

`gpui` 会引入一个很大的 GUI 依赖树。如果把它放进根 workspace，根 `Cargo.lock` 必须包含全部 gpui 依赖。仓库多处使用 `--locked`，锁文件变更会影响 macOS 和 iOS 构建。

因此：

- 本 crate 使用空 `[workspace]`。
- 根 workspace 只包含 `crates/kshift-windows`，它没有 gpui 依赖。
- 本 crate 由 Windows CI 验证。

## 运行

```sh
cargo run --release -- \
  --snapshot ../kshift-windows/fixtures/snapshot.json \
  --today 2026-11-25
```

打开只读 fixture 任务详情：

```sh
cargo run --release -- \
  --snapshot ../kshift-windows/fixtures/snapshot.json \
  --today 2026-11-25 \
  --open-task aaaaaaaa-0000-4000-8000-000000000001
```

连接真实服务时设置：

| 变量 | 作用 |
| --- | --- |
| `KSHIFT_ENDPOINT` | gRPC endpoint。 |
| `KSHIFT_CA_PEM` | CA 文件路径。 |
| `KSHIFT_TOKEN` | Bearer token。 |
| `KSHIFT_PROJECT_ID` | 项目 UUID。 |
| `KSHIFT_TLS_DOMAIN` | 可选 TLS server name。 |
| `KSHIFT_SMOKE_SECONDS` | 指定秒数后退出。用于无桌面 CI。 |

## 交互

- 点击人员排期中的任务条打开 editor panel。
- `Esc` 关闭；`Ctrl+S` 保存。
- `Tab` 在标题、说明和计划日期之间切换。
- 方向键、Home、End、Backspace、Delete 和粘贴编辑当前文本字段。
- `--snapshot` / `KSHIFT_SNAPSHOT` 永远是只读 fixture。
- server 模式保存 typed `update_task` command。

## 边界

- 业务数据和写入只来自 `kshift-ffi::host`。
- 本 crate 不依赖 `kshift-client`、`tonic`、`sqlx`。
- 版本冲突保留用户草稿，并要求显式刷新，不自动重放。
- 不使用 Liquid Glass。内容区使用纯色高对比底板。
- 1280×800 / 150% 截图必须在 Windows 桌面环境单独验收。
