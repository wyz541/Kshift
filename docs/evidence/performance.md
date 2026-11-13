# iOS 性能读数

结论：3 项 iOS XCUITest 性能读数已采集。macOS 窗口缩放没有有效读数。

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
| 看板左右滚动 | 2.919 s | 1.383% | 3 | 2.869790、2.918323、2.968661 |
| 拖拽 “Ship brief” | 1.673 s | 0% | 1 | 1.673105 |
| Sheet 打开和关闭 | 7.258 s | 0.694% | 3 | 7.296059、7.186682、7.290938 |

## 读取方法

```sh
xcrun xcresulttool get test-results metrics \
  --path '/Users/wyz/Library/Developer/Xcode/DerivedData/Kshift-efiloqhuibevqqdtynrqdqvdqvhs/Logs/Test/Test-Kshift-iOS-2026.11.13_13-53-53-+0800.xcresult' \
  --format json
```

该路径是本地 DerivedData 路径。外部复现时，使用新的 `xcresult` 路径。

## 限制

- `XCTClockMetric` 包含 automation 等待和合成事件时间。
- 读数不是帧耗时。
- 读数不是 Instruments trace。
- 当前没有性能阈值。
- `testDragTaskPerformance` 只有 1 个样本。
- macOS UI test runner 在建立连接前挂起，因此没有窗口缩放读数。
