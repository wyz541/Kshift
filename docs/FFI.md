# Kshift FFI

结论：Swift host 只读取 JSON，不接收 protobuf、tonic、SQLx 或数据库类型。

## C ABI

| 函数 | 作用 |
| --- | --- |
| `kshift_ffi_schema_version` | 返回 ABI schema version |
| `kshift_client_new` | 创建 opaque client handle |
| `kshift_client_free` | 释放 client handle |
| `kshift_client_projects_json` | 返回项目列表 JSON |
| `kshift_client_snapshot_json` | 返回项目快照 JSON |
| `kshift_client_execute_json` | 执行 typed command JSON |
| `kshift_string_free` | 释放 Rust 返回的字符串 |

## 所有权

- Rust 返回的 `char *` 由 Rust 分配。
- 调用方必须用 `kshift_string_free` 释放字符串。
- `KshiftClientHandle *` 必须用 `kshift_client_free` 释放。
- 同一 handle 的调用由 Rust `Mutex` 串行化。
- panic 在 FFI 内捕获。panic 不跨 C ABI。

## Swift 加载

`RustClient` 按以下顺序查找动态库：

1. `KSHIFT_FFI_PATH`。
2. App 的 `Frameworks/libkshift_ffi.dylib`。
3. App resource 中的 `libkshift_ffi.dylib`。
4. 开发目录的 `.build/ffi/macos/libkshift_ffi.dylib`。
5. 开发目录的 `.build/ffi/ios-simulator/libkshift_ffi.dylib`。

生产发布需要生成、签名和嵌入 XCFramework。
