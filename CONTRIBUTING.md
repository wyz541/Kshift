# Contributing

## 架构边界

- Rust 拥有业务规则、校验和持久化语义。
- SwiftUI 拥有渲染、输入、焦点、无障碍和临时 UI 状态。
- Swift host 只调用 `kshift-ffi`。
- AppKit 和 UIKit 只实现系统 capability adapter。
- `Sources/KshiftUI` 禁止 `#if os(...)`。
- Liquid Glass 只使用 Apple 原生 API。

## 提交前

1. 运行 `make test`。
2. 运行相关 Xcode build。
3. 修改共享 UI 时，运行 `make ios-test`。
4. 记录未运行的证据。
