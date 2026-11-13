---
slug: /evidence/performance
title: iOS 性能读数
type: report
status: review
updated: "2026-11-13"
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
| 日期 | 2026-11-13 |
| 设备 | iPhone 18 Pro Simulator |
| 系统 | iOS 27.0（24A434） |
| Xcode | 27.2（27B52） |
| 测试 | `KshiftIOSUITests` |
| 指标 | `XCTClockMetric` |

## 读数

| 场景 | 平均值 | RSD | 样本数 | 原始值 |
| --- | ---: | ---: | ---: | --- |
| 看板左右滚动 | 2.948 s | 1.009% | 3 | 2.987950、2.916906、2.938454 |
| 拖拽 “Ship brief” | 1.671 s | 0% | 1 | 1.671183 |
| Sheet 打开和关闭 | 7.386 s | 0.270% | 3 | 7.412667、7.382007、7.364356 |

## 读取方法

```sh
xcrun xcresulttool get test-results metrics \
  --path '/Users/wyz/Library/Developer/Xcode/DerivedData/Kshift-efiloqhuibevqqdtynrqdqvdqvhs/Logs/Test/Test-Kshift-iOS-2026.11.13_16-15-15-+0800.xcresult' \
  --format json
```

该路径是本地 DerivedData 路径。外部复现时，使用新的 `xcresult` 路径。

## 限制

- `XCTClockMetric` 包含 automation 等待和合成事件时间。
- 读数不是帧耗时。
- 读数不是 Instruments trace。
- 当前没有性能阈值。
- `testDragTaskPerformance` 只有 1 个样本。
