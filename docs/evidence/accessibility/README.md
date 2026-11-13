# iOS 无障碍证据

结论：6 张 iOS 截图已采集。Reduce Transparency 使用应用环境覆盖，不是系统设置开关。

## 环境

| 项目 | 值 |
| --- | --- |
| 日期 | 2026-11-13 |
| 设备 | iPhone 18 Pro Simulator |
| 系统 | iOS 27.0（24A434） |
| Xcode | 27.2（27B52） |
| 数据 | `KSHIFT_DEMO_MODE=1` |

## 截图

| 文件 | 设置 | 用途 |
| --- | --- | --- |
| `ios-light.png` | Light | 基准 |
| `ios-dark.png` | Dark | 深色外观 |
| `ios-increase-contrast.png` | Increase Contrast | 边框和对比检查 |
| `ios-large-text.png` | Accessibility Extra Extra Extra Large | 大号文字布局 |
| `ios-reduce-motion.png` | Reduce Motion | 动画降级状态 |
| `ios-reduce-transparency.png` | `KSHIFT_FORCE_REDUCE_TRANSPARENCY=1` | 不透明卡片和列底 |

`simctl ui` 不提供 Reduce Transparency 开关。脚本使用应用环境变量覆盖 SwiftUI 环境，并强制渲染不透明路径。该证据不替代真实系统设置下的人工检查。

## SHA-256

| 文件 | SHA-256 |
| --- | --- |
| `ios-light.png` | `dc9443f43a85db5a309dc37a0857731d39bba6eae1ae98b482d21e17cd19c821` |
| `ios-dark.png` | `c94cf4c2ba4b9d9a1fdcfa01a4fb7e154502be3f0a372d410523ec8f55af3568` |
| `ios-increase-contrast.png` | `d2e92dfcf0b16d049a6b7b3026493f09a6b56103100c35767722dc92a6644842` |
| `ios-large-text.png` | `fe46dcecb47e4b28e8989bec2e4339047ef0b8b6e356573efe326302ded6e42e` |
| `ios-reduce-motion.png` | `61d86c1ec7f395af4f9b04c761f254f55650d6405fcc68f232f82081d42a1dda` |
| `ios-reduce-transparency.png` | `b09db2036fc0ffa7b26fac9b70fb2837cf72834aded6a0e044cef37fff256476` |

## 自动检查

| 检查 | 结果 |
| --- | --- |
| 触控目标 | 通过 |
| 结构无障碍审计 | 通过 |
| 大号文字核心操作 | 通过 |
| 完整 contrast/Dynamic Type audit | 有未解决项 |
| VoiceOver | 待人工检查 |
| 系统 Reduce Transparency | 待人工检查 |
| Reduce Motion 全流程 | 待人工检查 |

结构审计使用 `performAccessibilityAudit` 的 element detection、hit region、element description 和 trait 检查。完整 audit 仍报告对比度和 Dynamic Type 问题。这些问题不作为通过证据。
