# Kshift Windows 客户端库

结论：本 crate 保存 Windows 客户端的快照模型和人员排期布局。

## 结构

| 文件 | 作用 |
| --- | --- |
| `src/model.rs` | 解析 `kshift-ffi` 的 snapshot JSON。 |
| `src/schedule.rs` | 人员排期布局。纯函数。 |
| `fixtures/snapshot.json` | 演示快照。用于本地预览和 Windows CI。 |

## 边界

- 本 crate 只做数据解析和布局计算。它不依赖 gpui。
- 本 crate 不包含业务校验。命令走 FFI。
- gpui 窗口在 `crates/kshift-windows-gpui`。该 crate 是独立 workspace。

## 测试

```sh
cargo test -p kshift-windows
```

布局测试不需要 gpui，因此在 macOS 和 Linux 也能运行。
