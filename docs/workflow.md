---
slug: /workflow
title: Kshift Project Workflow
type: standard
status: active
updated: "2026-11-16"
owner: "@wyz541"
keywords:
  - workflow
  - Project Workflow
  - Issue
  - PR
  - Worktree
  - AI Agent
description: Defines the Kshift project delivery workflow from structured input through merge and UX acceptance.
---

# Kshift Project Workflow

> **一句话**：用户输入先由 AI Agent 整理为结构化草案，再经过业务分流、Issue 模板准入、路径路由、开发验证和合并验收，最终形成可关闭的交付结果。
>
> **权威来源**：[`docs/workflow.drawio`](workflow.drawio) 是 Kshift 项目工作流的 normative source。本文将工作流图第 3 页整理为可搜索的 explanatory mirror（解释性镜像）。图中已定义的 workflow 规则优先于本文和 KS-GOV 中重复的工作流文字。
>
> **适用读者**：产品负责人、技术负责人、Issue 负责人、开发人员、评审者，以及参与需求整理和交付的 AI Agent。

## Authority

`docs/workflow.drawio` 是项目工作流的权威来源。本文是它的文字镜像。KS-GOV 只在图中没有定义对应 workflow 规则时补充约束。

- Authority scope：项目交付的阶段、状态、分支、回退、角色、产物和门禁。
- Baseline page：工作流图第 3 页。第 1 页和第 2 页只作为同一 draw.io 文件内的工作视图。
- Imported source：ObsidianVault commit `d63af060ac0e53ff508e4436198205e919569743`。
- File digest：`9defce4eb388cf58089ee43e8da4791fd4169676d4c1fd0959bac1889d8f2055`。
- Runtime dependency：仓库中的 `docs/workflow.drawio`。本地 Windows path 不是运行时依赖，也不是项目 authority。

Change `docs/workflow.drawio` and this page in the same PR. If this page differs from the draw.io page 3, fix this page unless the authority itself changes through a decision.

GitHub implementation mapping:

| Draw.io definition | Kshift implementation |
| --- | --- |
| `Ready to Dev` | Project `Status = Ready` |
| `need-info` | GitHub label `need-info` |
| Bug / Feature / Task templates | `.github/ISSUE_TEMPLATE/` |
| Worktree | `~/repo/_worktrees/Kshift/issue-<N>-<slug>` |
| Main | `origin/main` |

## 结论先行

工作流图第 3 页定义的不是一条“输入需求、直接生成 PR”的直线流程，而是一条带准入校验和回退路径的交付链。

这条交付链有五个阶段：

1. **Input & AI**：收集原始输入，并由 AI Agent 生成结构化草案。
2. **Triage & Explore**：判断问题是否明确。需要讨论时，先形成可执行共识。
3. **Format & Route**：选择 Issue 模板，通过信息完整性校验，再按任务复杂度选择执行路径。
4. **Dev & PR**：创建 worktree，完成开发和 PR，并通过格式、功能、视觉、Review 与 CI 验证。
5. **Merge & Accept**：合并到 Main，触发 CD Build，并执行 UX 终态验收和文档沉淀。

其中最重要的判断有三条：

- **Issue 必须先具备可执行信息，再进入开发。** 信息缺失时使用 `need-info` 回路补齐。
- **复杂项目必须先建立 Parent Issue/Epic，再拆分 Sub-Issues。** 不能把复杂项目直接压成一个执行 Issue。
- **Merge 不等于完成。** 工作流图第 3 页在 Merge 后继续要求 CD Build、UX 终态验收和文档沉淀。

## 一、文档定位

### 1.1 本文解决什么问题

本文把工作流图第 3 页中的节点和连线整理成一份可阅读、可交接的项目工作流说明，重点回答以下问题：

- 一项工作从什么输入开始？
- 什么时候可以创建或进入 Issue？
- 什么情况下需要讨论、RFC 或 PoC？
- Issue 在什么条件下才能进入开发？
- 简单任务和复杂项目分别走什么路径？
- PR 需要提交哪些说明和证据？
- Merge 后还需要完成哪些验收和沉淀动作？
- 出现信息缺失、评审拒绝或 UX 返工时，工作回到哪里？

### 1.2 本文不解决什么问题

工作流图第 3 页没有给出以下参数的完整定义：

- 简单任务与复杂项目的具体 Size 阈值。
- 各类审批所需的角色、人数和权限。
- CD Build 失败后的完整处理步骤。
- 非 GitHub 平台的字段映射。
- 具体 CI 命令、截图工具和代码评审规则。

本文保留这些边界，不根据其他页面或外部框架补充强制规则。

### 1.3 与其他工作流文档的关系

本文描述 GitHub 场景下的一张具体交付流程图。[Universal Project Development Workflow](https://github.com/wyz541/ObsidianVault/blob/master/Structure/工程实践/工作流/通用项目开发底层工作流.md) 提供跨项目类型的通用阶段和门禁模型；[Discuss to PR Workflow](https://github.com/wyz541/ObsidianVault/blob/master/Structure/工程实践/工作流/Discuss-Research-Issue-子议题-PR工作流.md) 提供 Discuss、Research、Issue、子议题和 PR 之间的证据链。

本文的重点不是重新定义通用项目模型，而是说明工作流图第 3 页如何把 AI 输入、Issue 模板、Router、worktree、PR 验证和 UX 验收组织成一条 GitHub 交付链路。

## 二、核心概念

| 概念 | 本文中的含义 | 在工作流图第 3 页中的位置或产物 |
| --- | --- | --- |
| **Raw Input** | 用户提供的 Idea、Feature、材料、文档或聊天记录。 | Idea、Feature、材料、Message |
| **Agent Spec** | AI Agent 使用的系统提示词或行为规范。 | Agent Spec |
| **Project Spec** | 项目规范、项目约束或模板库。 | Project Spec |
| **Draft Spec** | AI Agent 对原始输入进行提炼和格式化后的结构化草案。 | Draft Spec / Proposed Issue |
| **Issue** | 承载 Bug、Feature 或 Task 的可追踪工作项。 | 工业级 Bug、Feature、Task 模板 |
| **Ready to Dev** | Issue 已通过模板信息完整性校验，可以进入路径路由和开发准备。 | Ready to Dev |
| **Router** | 根据任务性质选择简单任务或复杂项目路径的决策点。 | as a Router / 路由判定 |
| **Worktree** | 一个 Issue 对应的隔离开发空间。 | 一条 Issue 对应一个 Worktree |
| **PR** | 承载变更说明、截图、验证结果和审查结论的变更请求。 | Pull Request |
| **UX 终态验收** | Merge 后对真实 UI 结果进行的最终验收。 | UX 终态验收 |
| **Icebox** | 讨论未形成共识时的暂存位置。 | 挂起 / Icebox |

术语说明：

- 工作流图第 3 页的 `Issue` 是工作承诺，不是单纯的“问题记录”。
- 工作流图第 3 页的 `Router` 是流程决策点，不是负责人职位。
- 工作流图第 3 页的 `PR` 是交付和验证对象，不是讨论现场。
- 工作流图第 3 页的 `AI Agent` 参与需求提炼、格式化、PR 说明辅助和截图对比，但不代替人工验收和评审。

## 三、流程总览

### 3.1 主流程

```text
(开始)
  │
  ▼
[Input & AI]
收集输入，生成结构化草案
  │
  ▼
[Triage & Explore]
判断业务性质，必要时形成共识
  │
  ▼
[Format & Route]
选择模板，校验信息，选择执行路径
  │
  ▼
[Dev & PR]
创建 Worktree，开发，提交 PR，执行验证
  │
  ▼
[Merge & Accept]
合并，构建，UX 验收，文档沉淀
  │
  ▼
(结束)
```

### 3.2 五个阶段的职责与产物

| 阶段 | 核心问题 | 主要产物 | 进入下一阶段的条件 |
| --- | --- | --- | --- |
| **Input & AI** | 用户要解决什么，现有输入能否被结构化？ | Draft Spec 或 Proposed Issue | 草案已经形成 |
| **Triage & Explore** | 问题是否明确，是否需要先讨论？ | 明确任务、正式 Issue 或 Icebox 记录 | 有明确 Issue 类型，或形成可执行共识 |
| **Format & Route** | Issue 信息是否完整，应该走哪条路径？ | Ready to Dev、执行路径、Assignee、Milestone | Issue 已格式化并完成分配 |
| **Dev & PR** | 变更是否完成，是否有可复核证据？ | Worktree、Commit、PR、验证记录 | Review 与 CI 通过 |
| **Merge & Accept** | 合并结果是否满足真实使用要求？ | CD Build、UX 验收、截图、文档更新 | UX 验收通过并完成沉淀 |

### 3.3 路径与回退关系

工作流图第 3 页包含四类关键分支：

| 分支 | 触发条件 | 去向 |
| --- | --- | --- |
| 明确任务分支 | 业务性质已经清楚，属于 Task 或 Bug。 | 直接应用工业级 Issue 模板 |
| 探索分支 | 业务性质、方向或可行性仍不明确。 | RFC、Discussion、异步讨论、评审会或 PoC |
| 简单任务分支 | Router 判定为简单任务。 | 按 Issue 模板格式化，分配 Assignee 和 Milestone |
| 复杂项目分支 | Router 判定为复杂项目。 | 创建 Parent Issue/Epic，说明分工，拆分 Sub-Issues |

流程中的主要回退关系如下：

- 信息缺失：进入 `need-info`，由提出者补充后重新应用模板。
- 讨论未达成共识：进入 Icebox。
- Review 或 CI 拒绝：回到本地开发和 Commit。
- UX 终态验收需要修改：提交 UX 修复 PR，再回到本地开发。

## 四、阶段说明

### 4.1 Input & AI：把原始输入变成结构化草案

**目标**：把分散在聊天、文档、灵感和需求描述中的信息整理成可判断、可分流的草案。

工作流图第 3 页定义的输入包括：

- Idea 或灵感。
- Feature 或需求。
- 材料或文档。
- Message 或聊天记录。

AI Agent 同时读取用户输入、Agent Spec 和 Project Spec。Agent Spec 约束 AI 的行为，Project Spec 提供项目规范、模板和约束。AI Agent 的输出是 Draft Spec 或 Proposed Issue。

```text
[Idea / Feature / 材料 / Message]
                 │
                 ▼
       [User Input: 多模态原始诉求]
                 │
                 ▼
[AI Agent: 需求提炼与格式化] ◀── [Agent Spec & Project Spec]
                 │
                 ▼
[Draft Spec / Proposed Issue]
```

**阶段产物**：结构化草案。草案应能让下一阶段判断业务性质、复杂度和确定性。

**退出条件**：草案已经形成，可以进入业务分流。

**常见失败信号**：

- 原始输入只有零散聊天，没有可识别的目标或问题。
- 草案只复述用户原话，没有整理出可判断的结构。
- AI Agent 的草案没有引用项目规范，导致后续模板不一致。
- 团队把 Draft Spec 当成已经批准的 Issue。

### 4.2 Triage & Explore：先判断问题，再决定是否执行

**目标**：判断当前工作属于明确任务，还是仍需要讨论、调研或验证。

工作流图第 3 页在 Draft Spec 后设置“判断业务性质 / 复杂度 / 确定性”节点。

#### 明确 Task 或 Bug

当业务性质已经清楚时，直接应用工业级 Issue 模板，进入阶段 3。

```text
[Draft Spec]
  │
  ▼
<明确 Task / Bug?>
  ├─ 是 ─▶ [应用工业级 Issue 模板]
  └─ 否 ─▶ [进入探索路径]
```

#### 模糊或需要探讨

当输入仍属于 Idea、Feature Plan 或需要讨论的方向时，进入以下探索路径：

1. GitHub Discussions 或 RFC。
2. 异步讨论、评审会或 PoC。
3. 判断是否达成可执行共识。
4. 达成共识后，转化为正式 Issue。

未达成共识时，工作进入 Icebox。

```text
[模糊 / 需探讨]
      │
      ▼
[RFC / Discussion]
      │
      ▼
[异步讨论 / 评审会 / PoC]
      │
      ▼
<达成可执行共识?>
  ├─ 是 ─▶ [转化为正式 Issue]
  └─ 否 ─▶ [挂起 / Icebox]
```

**阶段产物**：明确 Issue 类型、正式 Issue，或 Icebox 记录。

**退出条件**：已经选择一个可执行的 Issue 类型，或明确暂不执行。

**常见失败信号**：

- 方向不清楚，却直接进入开发。
- 讨论持续进行，但没有判断是否达成共识。
- 没有形成可执行结果，却把讨论记录当成 Issue。
- 未达成共识的工作没有进入 Icebox，也没有明确后续条件。

### 4.3 Format & Route：用模板建立开发准入

**目标**：把 Issue 写成可执行的工作承诺，并选择与复杂度匹配的交付路径。

#### 选择 Issue 模板

工作流图第 3 页定义了 Bug、Feature 和 Task 三类工业级模板。

| 模板 | 关注点 | 工作流图第 3 页中的字段 |
| --- | --- | --- |
| **Bug** | 溯源与防回归 | 标题与现象、环境与影响面、精准复现路径、现场证据、修复验收标准 |
| **Feature** | 业务价值与技术边界 | 核心价值产出、业务上下文、工程约束（NFR）、交互与设计、验收标准（AC）、回滚预案 |
| **Task** | 执行与依赖 | 明确动作、技术方案摘要、依赖网络、完成定义（DoD） |

模板选择应服从 Issue 的主要目的：

- 修复已发生的缺陷，使用 Bug 模板。
- 交付新的用户价值，使用 Feature 模板。
- 执行边界明确的工作，使用 Task 模板。

#### 信息完整性校验

模板填写完成后，进入信息完整性校验。

```text
[选择并填写 Issue 模板]
            │
            ▼
<信息完整且可执行?>
  ├─ 否 ─▶ [need-info]
  │          │
  │          ▼
  │       [提出者补充信息]
  │          │
  │          └─ 补充完毕 ─▶ [重新应用模板]
  │
  └─ 是 ─▶ {Ready to Dev}
```

信息缺失时，Issue 打上 `need-info`，并由提出者补充信息。补充完成后重新应用模板，再次校验。

校验通过后，Issue 进入 Ready to Dev。

#### Router 路由

Ready to Dev 后，流程进入 Router。工作流图第 3 页将路径分为简单任务和复杂项目。

```text
{Ready to Dev}
      │
      ▼
[as a Router: 路由判定]
      ├─ 简单任务 ─▶ [按模板规范格式]
      │                    │
      │                    ▼
      │          [分配 Assignee / Milestone]
      │
      └─ 复杂项目 ─▶ [创建 Parent Issue / Epic]
                           │
                           ▼
                    [负责说明与分工]
                           │
                           ▼
                    [拆分 Sub-Issues]
                           │
                           ▼
                    [按模板规范格式]
                           │
                           ▼
                    [分配 Assignee / Milestone]
```

**简单任务路径**：按 Issue 模板规范格式，随后分配 Assignee 和 Milestone。

**复杂项目路径**：创建 Parent Issue/Epic，写明负责说明与分工，拆分 Sub-Issues，再按模板规范格式并分配 Assignee 和 Milestone。

**阶段产物**：已格式化的 Issue、执行路径、Assignee 和 Milestone。

**退出条件**：Issue 已经通过完整性校验，并完成路径选择和执行分配。

**常见失败信号**：

- Issue 使用错误模板，导致关键字段缺失。
- `need-info` 未补充，却直接进入开发。
- 复杂项目没有建立 Parent Issue/Epic，直接开始写代码。
- Sub-Issues 没有分工、依赖或 Assignee。
- Router 选择路径时没有考虑复杂度，只按人员偏好分配。

### 4.4 Dev & PR：在隔离空间中完成可审查变更

**目标**：让每一个 Issue 在独立 worktree 中完成开发，并通过一个可审查的 PR 提交变更和证据。

#### 开发路径

```text
[Assignee / Milestone]
          │
          ▼
[创建 Worktree:
 一条 Issue 对应一个 Worktree]
          │
          ▼
[本地开发 & Commit]
          │
          ▼
[发起 Pull Request]
          │
          ▼
[填写 PR 格式说明]
```

工作流图第 3 页明确规定“一条 Issue 对应一个 Worktree”。因此，worktree 是 Issue 的执行边界，不应混入多个主 Issue 的无关工作。

#### PR 说明

PR 说明至少包含以下必填内容：

- 变更说明。
- 核心结论。
- Before 与 After UI 截图对比。

填写 PR 说明时，工作流图第 3 页允许 AI 辅助提取 Commit，并生成初始说明。初始说明仍然需要作者复核。

#### 自动验证流水线

工作流图第 3 页在 PR 后设置自动化验证流水线，并标注为并发执行。

```text
[Pull Request]
  │
  ├─▶ [格式校验:
  │     PR 模板是否填全] ────┐
  │                          │
  ├─▶ [功能验收:
  │     Local App 独立测试] ──┤
  │                          │
  └─▶ [视觉验收:
        AI 截图对比] ─────────┤
                               ▼
                    [Code Review / CI 测试]
```

三个检查项分别是：

| 检查项 | 检查对象 | 失败后的去向 |
| --- | --- | --- |
| 格式校验 | PR 模板是否填写完整 | 返回 PR 修改 |
| 功能验收 | Local App 独立测试 | 返回本地开发与 Commit |
| 视觉验收 | AI 截图对比 | 返回本地开发或补充截图 |
| Code Review / CI | 实现、测试、构建和评审要求 | 拒绝或打回本地开发 |

Review 或 CI 拒绝时，工作回到本地开发和 Commit。通过后，PR 进入 Merge to Main。

**阶段产物**：Worktree、Commit、PR、PR 说明、自动验证记录、Code Review 与 CI 结果。

**退出条件**：PR 已通过 Review 与 CI，可以合并到 Main。

**常见失败信号**：

- 一个 worktree 同时处理多个无关 Issue。
- PR 缺少变更说明、核心结论或 Before/After 截图。
- 把 AI 生成的 PR 说明直接提交，没有人工复核。
- 功能测试没有独立执行。
- 视觉验收没有截图证据。
- Review 拒绝后继续扩大变更范围。

### 4.5 Merge & Accept：合并后完成终态验收

**目标**：确认合并后的真实结果满足 UX 要求，并把结果沉淀为可复用文档。

```text
[Merge to Main]
      │
      ├─▶ [触发 CD 自动 Build]
      │          │
      │          ▼
      │   <UX 终态验收>
      │      ├─ 通过 ─▶ [提供 Before / After UI 截图记录]
      │      │                    │
      │      │                    ▼
      │      │          [更新 Concept Definition / 沉淀文档]
      │      │
      │      └─ 需 UX 更改 ─▶ [提交 UX 修复 PR]
      │                              │
      │                              └─▶ [本地开发 & Commit]
      │
      ├─▶ [自动清理本地 Worktree]
      │
      └─▶ [自动关闭关联 Issue & PR]
```

Merge 后，工作流图第 3 页同时画出三类动作：

1. 触发 CD 自动 Build。
2. 自动清理本地 Worktree。
3. 自动关闭关联 Issue 与 PR。

其中 CD Build 完成后进入 UX 终态验收。

UX 验收通过时，团队必须提供 Before 与 After UI 截图记录，并更新 Concept Definition 或相关文档。

UX 验收需要更改时，团队提交 UX 修复 PR。该 PR 回到本地开发与 Commit，再进入阶段 4 的 PR 验证和 merge 路径。

**阶段产物**：CD Build 结果、UX 验收结论、Before/After 截图、文档更新，以及清理和关闭结果。

**退出条件**：CD Build 和 UX 终态验收已经给出结论，Before/After 截图与文档沉淀已经完成，工作流图第 3 页要求的清理和关闭动作已经执行。若 UX 需要更改，则由 UX 修复 PR 继续承接。

**常见失败信号**：

- PR merge 后直接宣布完成，没有执行 CD Build。
- UX 没有检查真实运行结果。
- UX 需要修改，但没有建立修复 PR。
- 验收通过后没有保留 Before/After 截图。
- 完成实现后没有更新 Concept Definition 或相关文档。

## 五、验证与交接

### 5.1 每个阶段的交接内容

| 交接 | 上游提供 | 下游接收 |
| --- | --- | --- |
| Input & AI → Triage | 原始输入、Draft Spec、项目规范 | 可判断的草案 |
| Triage → Format & Route | Issue 类型、共识结果或 Icebox 决定 | 可选择的 Issue 模板 |
| Format & Route → Dev & PR | Ready to Dev、Assignee、Milestone、Worktree | 可执行开发任务 |
| Dev & PR → Merge & Accept | PR、验证结果、Review 与 CI 结论 | 可合并变更 |
| Merge & Accept → 关闭 | CD Build、UX 验收、截图、文档更新 | 可关闭的交付结果 |

### 5.2 验证证据

工作流图第 3 页把验证分成四个层次：

| 层次 | 目的 | 证据 |
| --- | --- | --- |
| 格式校验 | 确认 PR 说明可审查。 | PR 模板、变更说明、核心结论 |
| 功能验收 | 确认变更在 Local App 中工作。 | 独立测试结果 |
| 视觉验收 | 确认 UI 前后差异符合预期。 | Before/After 截图、AI 截图对比 |
| Review 与 CI | 确认实现、测试和构建符合要求。 | Code Review 结论、CI 结果 |

## 六、异常与回退路径

工作流图第 3 页明确画出的回退路径如下：

| 异常 | 触发点 | 处理动作 | 回到位置 |
| --- | --- | --- | --- |
| 信息缺失 | 信息完整性校验 | 打上 `need-info`，由提出者补充信息 | 重新应用 Issue 模板 |
| 未达成共识 | Triage & Explore | 挂起并进入 Icebox | 不进入正式 Issue |
| Review 或 CI 拒绝 | 阶段 4 验证 | 打回并修复 | 本地开发与 Commit |
| UX 需要更改 | UX 终态验收 | 提交 UX 修复 PR | 本地开发与 Commit |

这些回退路径是流程的一部分。团队不应把回退视为个人失败，也不应绕过回退直接进入下一阶段。

## 七、角色与协作边界

| 角色或对象 | 主要责任 | 不应替代 |
| --- | --- | --- |
| **用户或提出者** | 提供原始输入、业务背景和补充信息。 | 不能代替 Issue 负责人确认执行范围。 |
| **AI Agent** | 提炼需求、格式化草案、辅助 PR 说明和截图对比。 | 不能代替 Review、CI 和 UX 终态验收。 |
| **Issue 负责人** | 维护 Issue 模板、目标、依赖和 Ready to Dev 状态。 | 不能隐藏未确认的信息缺口。 |
| **Assignee** | 在 worktree 内完成开发和 Commit。 | 不能把多个无关 Issue 混入同一 PR。 |
| **Reviewer** | 检查变更、验证证据和实现风险。 | 不能把新需求塞进当前 PR。 |
| **UX** | 对 Merge 后的真实 UI 结果执行终态验收。 | 不能用 PR 阶段的截图代替真实结果验收。 |

工作流图第 3 页没有定义完整的审批权限和评审人数。团队应在项目规范中补充这些规则。

## 八、执行检查表

### 开始前

- [ ] 原始输入已经收集。
- [ ] Agent Spec 和 Project Spec 可供 AI Agent 使用。
- [ ] Draft Spec 或 Proposed Issue 已形成。
- [ ] 业务性质、复杂度和确定性已经判断。

### 进入开发前

- [ ] Issue 已选择 Bug、Feature 或 Task 模板。
- [ ] 模板字段已经填写。
- [ ] 信息完整性校验已经通过。
- [ ] Issue 已进入 Ready to Dev。
- [ ] Router 已选择简单任务或复杂项目路径。
- [ ] Assignee 和 Milestone 已分配。
- [ ] 复杂项目已经建立 Parent Issue/Epic 和 Sub-Issues。

### 合并前

- [ ] 一条 Issue 对应一个 Worktree。
- [ ] PR 已填写变更说明和核心结论。
- [ ] PR 已提供 Before/After UI 截图。
- [ ] 格式校验已通过。
- [ ] Local App 独立测试已通过。
- [ ] AI 截图对比已完成。
- [ ] Code Review 和 CI 已通过。

### 终态验收与收尾

- [ ] CD Build 已完成。
- [ ] UX 终态验收已通过。
- [ ] Before/After UI 截图已经归档。
- [ ] Concept Definition 或相关文档已更新。
- [ ] 本地 Worktree 已清理。
- [ ] 关联 Issue 与 PR 已关闭。

## 九、边界与未定义事项

### 9.1 本文的边界

- 本文只解释工作流图第 3 页画出的五个阶段和连线。
- 本文不把其他页面的扩展节点写入正文。
- 本文不把未出现的阈值、审批规则和发布策略写成团队制度。
- 本文中的流程阶段可以直接映射到 GitHub，但不等同于完整研发管理制度。

### 9.2 工作流图第 3 页未定义的事项

- 简单任务与复杂项目的具体判定阈值。
- Issue 模板各字段的最低填写标准。
- Parent Issue、Sub-Issues 的命名和追踪规则。
- Review 人数、审批角色和合并权限。
- CD Build 失败后的重试、回滚或重新发布路径。
- 非 GitHub 平台的 Issue、PR、CI 和 Merge 映射。
- UX 验收不通过时的最终升级路径。

这些事项由 KS-GOV、仓库规则或后续流程图补充。补充规则不得改变工作流图已定义的阶段、分支、角色和门禁。

## 结语

工作流图第 3 页的核心价值在于把“需求进入、Issue 准入、开发执行、验证合并和终态验收”放在同一张图上。

这张图提醒团队：开发不是流程的起点，PR 不是流程的终点，Merge 也不是交付的完成标志。只有输入被结构化、Issue 通过准入、变更获得验证，并完成 UX 终态验收和文档沉淀，工作流才真正闭环。

## 相关笔记

- [Universal Project Development Workflow](https://github.com/wyz541/ObsidianVault/blob/master/Structure/工程实践/工作流/通用项目开发底层工作流.md)
- [Discuss to PR Workflow](https://github.com/wyz541/ObsidianVault/blob/master/Structure/工程实践/工作流/Discuss-Research-Issue-子议题-PR工作流.md)
- [Engineering Workflow Index](https://github.com/wyz541/ObsidianVault/blob/master/Structure/工程实践/工作流/工作流.md)
