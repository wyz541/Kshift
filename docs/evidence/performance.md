---
slug: /evidence/performance
title: iOS 性能读数
type: report
status: review
updated: "2026-11-14"
keywords:
  - iOS
  - 性能
  - XCUITest
  - XCTClockMetric
  - 证据
description: 记录 iOS 看板滚动、拖拽和 Sheet 打开的 XCUITest 性能读数。
---

# iOS 性能读数

结论：3 项 iOS XCUITest 性能读数已采集。

## 环境

| 项目 | 值 |
| --- | --- |
| 日期 | 2026-11-14 |
| 设备 | iPhone 18 Pro Simulator |
| 系统 | iOS 27.0（24A434） |
| Xcode | 27.2（27B52） |
| 测试 | `KshiftIOSUITests` |
| 指标 | `XCTClockMetric` |

## 读数

| 场景 | 平均值 | RSD | 样本数 | 原始值 |
| --- | ---: | ---: | ---: | --- |
| 看板左右滚动 | 2.952 s | 0.779% | 3 | 2.919952、2.968691、2.968738 |
| 拖拽 “Ship brief” | 1.674 s | 0% | 1 | 1.673827 |
| Sheet 打开和关闭 | 7.357 s | 0.524% | 3 | 7.410147、7.319389、7.342031 |

## 读取方法

```sh
xcrun xcresulttool get test-results metrics \
  --path '/Users/wyz/Library/Developer/Xcode/DerivedData/Kshift-gfxkuaiuirbmgofnwucpkiybigjc/Logs/Test/Test-Kshift-iOS-2026.11.14_10-52-20-+0800.xcresult' \
  --format json
```

该路径是本地 DerivedData 路径。外部复现时，使用新的 `xcresult` 路径。

## 限制

- `XCTClockMetric` 包含 automation 等待和合成事件时间。
- 读数不是帧耗时。
- 读数不是 Instruments trace。
- 当前没有性能阈值。
- `testDragTaskPerformance` 只有 1 个样本。
