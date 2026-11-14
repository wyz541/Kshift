---
slug: /adr/0010-issue-pr-and-local-build-governance
title: ADR-0010 Issue/PR 与本地构建治理
type: decision
status: superseded
version: "1.0"
updated: "2026-11-14"
keywords:
  - Issue
  - Pull Request
  - Project
  - DerivedData
  - 治理
description: 固定 Issue/PR 标签、状态、关系、证据和本地调试构建的唯一规则。
---

# ADR-0010 Issue/PR 与本地构建治理

> 结论：Project `Status` 是唯一状态源。一个 PR 只关闭一个主 Issue。研究结论回写来源 Discussion，但不强制关闭 Discussion。

> 历史说明：本 ADR 仅用于追溯。当前规则入口见 [Active Spec 索引](../specs/index.md)，目标 ID 为 `KS-GOV`。

## 1. 状态

`accepted`

## 2. 背景

Discussion #1 已形成 Issue/PR 治理草案。以下八项仍待确认。

- 标签命名。
- Project 状态来源。
- PR 和 Issue 的关系。
- 用户可见变更的文档判断。
- Research Issue 和来源 Discussion 的关系。
- 交付证据和最终验收证据的位置。
- 本地 DerivedData 路径。
- Debug App 的显示名。

这些项会同时影响模板、标签、Project、关系检查和本地构建。实现不能继续使用八个并行默认值。

## 3. 决策

### 3.1 标签命名

- 类型标签使用 `type:` 前缀。
- 领域标签使用 `area:` 前缀。
- 每个开放实现 Issue 必须有一个类型标签。
- 每个开放实现 Issue 必须至少有一个领域标签。
- `accessibility` 是正交关注点标签，可以和类型、领域标签共存。
- `status:`、`priority:` 和负责人标签禁止新增。
- 历史关闭 Issue 保留原标签。开放 Issue 只迁移一次。

### 3.2 Project 状态

- GitHub Project 的 `Status` 字段是唯一状态来源。
- `Status` 值固定为 `Inbox`、`Triage`、`Ready`、`In Progress`、`In Review`、`Blocked` 和 `Done`。
- 迁移期间，Issue 正文的 `Status:` 行只能镜像 Project 状态。
- 迁移验收后，Issue 正文不得继续维护独立状态。
- 标签和 Issue 正文不得成为第二套状态来源。

### 3.3 PR 和主 Issue

- 一个 PR 只能有一个主 Issue。
- 最终关闭主 Issue 的 PR 在正文写 `Closes #N`。
- 主 Issue 需要多个 PR 时，前置 PR 写 `Part of #N`。
- 一个 PR 可以关联多个软关系 Issue。
- 多范围 PR 必须指定一个主 Issue，并用 `Part of` 链接其他 Issue。
- 未关联 Issue 的 PR 不得进入评审。

### 3.4 用户可见变更

- 每个 PR 必须判断文档、FAQ 和 Release note 的影响。
- PR 正文必须写出影响结论。
- 需要更新时，PR 必须包含更新或链接后续 Issue。
- 不需要更新时，PR 必须写“不适用”及原因。
- 判断通过不等于每个 PR 都必须修改文档。

### 3.5 Research 和来源 Discussion

- Research Issue 是研究执行、决策和证据的唯一入口。
- 来源 Discussion 保存原始背景和评审上下文。
- Research Issue 创建后，来源 Discussion 保持 Open。
- 研究完成后，必须在来源 Discussion 增加结论评论。
- 结论评论必须链接 Research Issue、Decision 和 ADR。
- 只有 Q&A 类 Discussion 且全部问题已有答案时，才可标记已答复。
- 不得自动关闭 RFC 类 Discussion。

### 3.6 证据位置

- PR 正文的 `## 验收证据` 保存交付和集成证据。
- Issue 的 `## 证据` 保存最终验收证据。
- Acceptance Issue 的验收矩阵保存最终验收结论。
- 评论可以解释证据，但评论不能成为唯一证据。
- 证据必须包含命令、结果或可访问链接。
- 未运行的检查必须写“未运行”和原因。

### 3.7 本地 DerivedData

- 本地 `xcodebuild` 统一使用仓库内 `build/DerivedData`。
- `make app-paths` 和构建目标必须使用同一路径变量。
- `build/` 是生成目录，不进入 Git。
- 清理命令只处理已校验的仓库内生成目录。
- 默认 `~/Library/Developer/Xcode/DerivedData` 不用于 Kshift 本地构建。

### 3.8 Debug App

- Debug 构建显示名使用 `Kshift Dev`。
- Release 构建显示名保持 `Kshift`。
- 平台 target、产品名和 bundle identifier 保持稳定。
- Debug App 不复制到 `/Applications` 或 `~/Applications`。
- 测试 Runner 只由测试命令启动。
- 每个平台只保留一个活跃 Debug 构建。

## 4. 备选方案

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| 无前缀类型和领域标签 | 名称较短 | 命名空间冲突；检查难 | 拒绝 |
| `type:` 和 `area:` 标签 | 可组合；可自动检查 | 名称较长 | 采用 |
| Project `Status` 作为唯一状态源 | 单一事实源；视图一致 | 依赖 Project 可用性 | 采用 |
| Issue 正文保存主状态 | 离线可见 | 和 Project 双写；容易分叉 | 拒绝 |
| 一个 PR 一个主 Issue | 追踪清楚；验收边界明确 | 多范围工作需要拆分 | 采用 |
| 一个 PR 关闭多个主 Issue | PR 数量少 | 验收和回滚边界混乱 | 拒绝 |
| 用户可见变更必须判断文档影响 | 防止漏文档；允许不适用 | 增加一个检查项 | 采用 |
| 所有 PR 强制改文档 | 规则简单 | 产生无意义修改 | 拒绝 |
| Research 结论回写 Discussion | 保留上下文；不破坏讨论 | 需要一次人工评论 | 采用 |
| 自动关闭来源 Discussion | 归档简单 | RFC 后续无法继续评审 | 拒绝 |
| PR 保存交付证据，Issue 保存验收证据 | 证据层次清楚 | 需要维护两个入口 | 采用 |
| 评论作为唯一证据 | 操作快 | 难以审计；容易丢失 | 拒绝 |
| 仓库内 `build/DerivedData` | 可清理；路径可预测 | 占用仓库目录 | 采用 |
| 默认 Xcode DerivedData | 不需要配置 | 多构建路径；清理风险高 | 拒绝 |
| `Kshift Dev` Debug 显示名 | 能区分 Debug 和 Release | 显示名与产品名不同 | 采用 |
| Debug 和 Release 同名 | 名称一致 | 运行实例容易混淆 | 拒绝 |

## 5. 后果

- 下游模板必须使用同一组标题和字段。
- 标签迁移必须先创建新标签，再迁移开放 Issue。
- Project 不可用时，迁移暂停；Issue 正文状态行只能临时镜像。
- 多范围 PR 必须先拆分，或指定一个主 Issue。
- PR 评审必须检查文档影响结论。
- Discussion 清理不得删除原始上下文。
- 证据入口必须稳定，评论只能补充说明。
- 本地构建脚本必须共享 DerivedData 路径。
- Debug App 路径必须只指向 `build/DerivedData` 下的产物。

## 6. 迁移和回滚

### 6.1 迁移

1. 创建 `type:` 和 `area:` 标签。
2. 更新 Issue Forms 和 PR template。
3. 配置 Project `Status`、`Priority` 和 `Target` 字段。
4. 迁移开放 Issue 的标签和状态。
5. 更新本地构建目标。
6. 完成关系审计和验收。

### 6.2 回滚

- 标签回滚时恢复旧标签映射。历史标签不删除。
- Project 回滚时保留 Issue 正文状态行，但不得同时创建第二套标签状态。
- PR 规则回滚时恢复旧模板。已关闭 Issue 不重写。
- DerivedData 回滚时恢复默认路径，并删除仓库内生成目录。
- Debug 显示名回滚时保留 target 和 bundle identifier。

## 7. 验证

- `gh label list` 显示全部 `type:` 和 `area:` 标签。
- 开放 Issue 标签审计显示每个实现 Issue 有且仅有一个类型标签，并且至少有一个领域标签。
- Project 字段查询显示七个固定 Status 值和四个 Priority 值。
- PR 模板包含 `## 验收证据`、`## 未覆盖` 和文档影响字段。
- Research Issue 的来源 Discussion 有结论评论和 Decision 链接。
- 关系查询显示下游 Issue 的 `blocked_by` 已移除。
- `make app-paths` 输出 `build/DerivedData` 下的产物路径。
- `make clean-build` 的 dry-run 只列出仓库内生成目录。
- macOS 和 iOS Debug App 都显示 `Kshift Dev`。

## 8. 关联

- Spec: [14. 项目治理](../spec/kshift-spec-v0.1.md#14-项目治理)
- Decision: `DEC-032` 至 `DEC-039`
- Issue: [#23](https://github.com/wyz541/Kshift/issues/23)
- Source Discussion: [#1](https://github.com/wyz541/Kshift/discussions/1)
- Downstream: [#24](https://github.com/wyz541/Kshift/issues/24)、[#25](https://github.com/wyz541/Kshift/issues/25)、[#26](https://github.com/wyz541/Kshift/issues/26)、[#27](https://github.com/wyz541/Kshift/issues/27)
