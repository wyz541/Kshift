---
slug: /local-build
title: 本地构建路径治理
type: guide
status: active
updated: "2026-11-14"
keywords:
  - DerivedData
  - 本地构建
  - Debug App
  - Test Runner
  - 清理清单
description: 规定本地 Xcode 构建路径、Debug App 和 Test Runner 规则。
---

# 本地构建路径治理

结论：本地 Debug 构建只写入 `build/DerivedData`。Debug App 显示名为 `Kshift Dev`。Debug App 和 Test Runner 不进入 Applications。

## 固定路径

| 平台 | App 路径 |
| --- | --- |
| macOS | `build/DerivedData/Build/Products/Debug/Kshift-macOS.app` |
| iOS Simulator | `build/DerivedData/Build/Products/Debug-iphonesimulator/Kshift-iOS.app` |

以下命令使用固定路径。

| 命令 | 作用 |
| --- | --- |
| `make app-paths` | 输出两个 App 路径和存在状态 |
| `make mac-build` | 构建 macOS Debug App |
| `make ios-build` | 构建 iOS Simulator Debug App |
| `make ios-test` | 构建并启动 iOS Test Runner |

## 本地规则

1. 禁止把 Debug App 复制到 `/Applications` 或 `~/Applications`。
2. 用 Xcode Run 启动 App。也可用 `open` 打开 `make app-paths` 输出的 macOS App 路径。
3. 禁止从 Finder 或 `open` 启动 Test Runner。只允许测试命令启动 Test Runner。
4. 保持 target 名称和 bundle identifier 不变。
5. 每个平台只保留 `build/DerivedData` 中的一套活跃 Debug 构建。
6. 提交前运行 `make check-build-governance`。

Target 和 bundle identifier 的固定值：

| Target | Bundle identifier |
| --- | --- |
| `Kshift-macOS` | `com.wyz541.kshift.mac` |
| `Kshift-iOS` | `com.wyz541.kshift.ios` |

Debug 构建的显示名固定为 `Kshift Dev`。Release 构建的显示名固定为 `Kshift`。产品名和 bundle identifier 不随配置改名。

## 清理固定构建目录

先查看路径。

```sh
make clean-build DRY_RUN=1
```

再删除固定生成目录。

```sh
make clean-build
```

`clean-build` 只接受 `build/DerivedData`。命令拒绝符号链接和预期路径之外的目录。命令不按 App 名称搜索目录。

## 旧 DerivedData 清单

旧 Xcode DerivedData 不在固定路径内。生成只读清单。

```sh
make legacy-deriveddata-manifest
```

清单字段如下。

| 字段 | 含义 |
| --- | --- |
| Path | 待复核的精确目录 |
| Size | `du -sh` 输出 |
| Modified | 目录修改时间 |
| Debug products | 目录中的 Kshift App 和测试包 |

清理旧目录前执行以下步骤。

1. 保存清单到 `~/workspace/scratch/<task>/`。
2. 逐项确认目录属于旧 Kshift 构建。
3. 确认目录不是当前固定 `build/DerivedData`。
4. 取得用户确认后，逐项删除精确路径。
5. 再运行 `make legacy-deriveddata-manifest`。确认清单为空。

`make legacy-deriveddata-manifest` 不删除文件。

## 回滚

恢复 Xcode 默认 DerivedData 时，移除本地命令中的 `-derivedDataPath`。回滚前先保留本文件中的旧路径清单。回滚不修改 target、bundle identifier 或用户数据。
