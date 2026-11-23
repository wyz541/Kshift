# Windows GPUI spike

结论：本目录只验证一件事。已发布的 `gpui` crate 能否在 Windows 上编译。

## 为什么独立

- Windows 客户端在 Active Spec 中状态为 `rejected`。决策入口是 Issue #120。
- 本 crate 使用空 `[workspace]`，不进入根 workspace。
- 本 crate 不参与 Release。

## 运行

1. 推送分支。
2. 运行 `Windows GPUI spike` workflow。
3. 读取构建日志和 artifact。

## 当前边界

| 项 | 状态 |
| --- | --- |
| Windows 编译 | 通过。见 run 45105238463。 |
| 打开窗口 | 由 workflow 验证 |
| 连接 kshift-client | 未实现 |
| 安装包 | 未实现 |

## 已知限制

- 本地开发机是 macOS。本地不能编译或运行 Windows GUI。
- 本仓库没有 Windows runner。本 workflow 使用 `windows-latest`。
