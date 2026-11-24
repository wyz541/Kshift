# Kshift Windows gpui 外壳

结论：本 crate 是 Windows 客户端窗口。它只负责渲染。

## 为什么是独立 workspace

`gpui` 会引入一个很大的 GUI 依赖树。如果把它放进根 workspace，根 `Cargo.lock` 必须包含全部 gpui 依赖。仓库多处使用 `--locked`，锁文件变更会影响 macOS 和 iOS 构建。

因此：

- 本 crate 使用空 `[workspace]`。
- 根 workspace 只包含 `crates/kshift-windows`，它没有 gpui 依赖。
- 本 crate 只能由 Windows CI 或 Windows 机器构建。

## 运行

```sh
cargo run --release -- \
  --snapshot ../kshift-windows/fixtures/snapshot.json \
  --today 2026-11-25
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

## 边界

- 业务数据只来自 `kshift-ffi::host`。
- 本 crate 不依赖 `kshift-client`、`tonic`、`sqlx`。
- 不使用 Liquid Glass。内容区使用纯色高对比底板。
- 当前只读。编辑、看板、日历和表格是后续 Task。
