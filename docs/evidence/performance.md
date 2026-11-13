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
| 看板左右滚动 | 2.941 s | 0.877% | 3 | 2.904966、2.954079、2.963938 |
| 拖拽 “Ship brief” | 1.689 s | 0% | 1 | 1.688760 |
| Sheet 打开和关闭 | 7.378 s | 0.344% | 3 | 7.406994、7.345282、7.382282 |

## 读取方法

```sh
xcrun xcresulttool get test-results metrics \
  --path '/Users/wyz/Library/Developer/Xcode/DerivedData/Kshift-fvzzwfvjswduwihbpwffjlhipova/Logs/Test/Test-Kshift-iOS-2026.11.13_19-41-29-+0800.xcresult' \
  --format json
```

该路径是本地 DerivedData 路径。外部复现时，使用新的 `xcresult` 路径。

## 限制

- `XCTClockMetric` 包含 automation 等待和合成事件时间。
- 读数不是帧耗时。
- 读数不是 Instruments trace。
- 当前没有性能阈值。
- `testDragTaskPerformance` 只有 1 个样本。
