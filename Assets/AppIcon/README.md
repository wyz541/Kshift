# Kshift 应用图标

结论：图标用一个木制任务夹板表达“共享任务工作台”。图形是现实物体，不是抽象符号。

## 图形语义

| 元素 | 含义 |
| --- | --- |
| 木制夹板 | 共享任务板。团队共用一份任务单。 |
| 3 × 7 计划格 | 人员 × 自然日期。 |
| 彩色任务条 | 项目任务。颜色沿用优先级和状态色。 |
| 纸叠 | 多周计划。 |
| 黄铜夹子 | 固定当前计划。 |

## 配色

| 颜色 | 值 | 用途 |
| --- | --- | --- |
| 黄 | `#FFC400` | P1 徽章色与周末列 |
| 橙 | `#F26E00` | 木板与任务条 |
| 蓝 | `#0066FF` | 背景与任务条 |
| 白 | `#FFFFFF` | 纸面 |

## 文件

| 路径 | 作用 |
| --- | --- |
| `Assets/AppIcon/AppIcon.svg` | 1024 母版。`ART` 标记内是全部图形。 |
| `Assets/AppIcon/preview.png` | 预览图。 |
| `scripts/render-app-icon.py` | 渲染 iOS 和 macOS 的全部尺寸。 |
| `Apps/KshiftIOS/Assets.xcassets/AppIcon.appiconset` | iOS 图标集。 |
| `Apps/KshiftMacOS/Assets.xcassets/AppIcon.appiconset` | macOS 图标集。 |

## 规格

- iOS 图标是满幅 1024 × 1024，无透明通道。系统负责圆角遮罩。
- macOS 图标内容是 824 × 824 圆角方形，居中，带透明边距和投影。
- macOS 图标集包含 16 至 1024 的全部尺寸。

## 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-11-21 | 首版。 |
| 2026-11-21 | 移除蓝鸲和日轮。夹板成为唯一主体。 |

## 重新生成

1. 修改 `Assets/AppIcon/AppIcon.svg`。
2. 运行 `python3 scripts/render-app-icon.py`。
3. 运行 `xcodegen generate`。
4. 构建 app。确认 `Assets.car` 和 `AppIcon.icns` 存在。
