# 贡献与评审流程

结论：Active Spec 保存当前规则。Issue 保存决策过程。PR 交付实现和证据。

## 1. 权威顺序

1. Active Spec。
2. 版本化协议和 JSON Schema。
3. Issue 和 PR 的实施说明。

ADR 只用于历史追溯。ADR 不在权威顺序中。下层文档不得覆盖 Active Spec。

## 2. 先读入口

- [Active Spec 索引](docs/specs/index.md)
- [工程治理 Spec](docs/specs/governance.md)
- [Issue 与 PR 关系](docs/governance/issue-relations.md)
- [标签与 Project](docs/governance/labels-and-project.md)
- [Issue Forms](.github/ISSUE_TEMPLATE)
- [PR template](.github/pull_request_template.md)

## 3. Issue 要求

每个实现 Issue 必须包含以下字段。

- `Spec`：链接到 Active Spec 的具体规则。
- `Decision Issue`：链接决策 Issue。材料足够时可链接本 Issue。
- `Contract`：列出受影响的 protobuf 或 JSON Schema。
- `Acceptance`：写出可观察的完成结果。
- `Evidence`：写出需要的测试或运行证据。

Issue 不复制 Active Spec 的完整规则。Issue 只写本次交付范围、决策过程和验证方法。

Feature 必须使用原生 sub-issues。Feature 至少有 1 个交付子 Issue，并且恰好有 1 个 Acceptance 子 Issue。Acceptance 必须阻塞于全部交付子 Issue。

Research 必须写决策问题、来源 Discussion、Owner、Decision owner 和预期输出。直接创建的 Research Issue 在来源处写“无”。

## 4. 工作流

1. 从 `main` 创建短生命周期分支。
2. 在 Discussion 或 Issue 中形成问题。
3. 在 Research 或 Task Issue 中记录决策和证据。
4. 更新受影响的 Active Spec。
5. 更新合同、模板和检查。
6. 增加实现、测试或评审证据。
7. 运行 R0 和关系审计。
8. 打开 PR。PR 正文必须写 `Closes #N` 或 `Part of #N`。
9. 使用 `Closes` 前，确认主 Issue 已完成交付和验收。
10. 合并后写 Issue 验收记录。

### 4.1 Worktree 交付

会修改仓库的 Task 或 Bug 使用一个独立 Worktree。Feature、Research 和 Acceptance 不要求实现 Worktree。

1. 运行 `git status --short --branch`，确认主检出位于 `main` 且没有输出。
2. 创建 Worktree。替代命令中的 `<N>` 和 `<slug>`。

```bash
git worktree add -b issue/<N>-<slug> \
  ~/repo/_worktrees/Kshift/issue-<N>-<slug> origin/main
```

3. 在 Issue 或 PR 记录 Worktree 路径和 branch。
4. 在 Worktree 完成实现、测试和证据。
5. PR 正文使用 `Part of #N`。不要依赖 `Closes` 自动关闭 Worktree 交付。
6. 迁移唯一证据。证据只进入 `docs/evidence` 或已登记的项目证据目录。
7. 清理已登记的生成物。无法确认归属时停止，并进入人工复核。

### 4.2 Worktree 清理和关闭

清理前运行只读审计。

```bash
python3 scripts/audit_worktrees.py --repo . --expected-task-worktrees <N>
```

审计必须显示以下全部结果。

- Worktree 路径已登记。
- Git 状态没有未提交修改。
- 本地提交没有未推送项，或未推送项已人工确认。
- Branch 已合并到 `origin/main`。
- 唯一证据已迁移。

在 Issue 记录批准人、固定路径、branch、Issue、证据目标、检查结果和批准日期。批准人必须是 `@wyz541`。

取得明确批准后执行以下步骤。

1. 运行 `git worktree remove <path>`。命令失败时停止，禁止使用 `--force`。
2. 运行 `git branch -d <branch>`。Branch 为 `detached` 时跳过本步。
3. 再次运行 Worktree 审计。
4. 核对结果与批准记录一致。
5. 由 Issue owner 手工关闭 Issue。

保留 Worktree 时，在 Issue 记录 owner、原因、批准人、批准日期和复核日期。复核日期不得超过批准日期后 14 天。

## 5. 决策变更

已确认决策只能通过以下方式改变。

1. 建立 Research 或 Task Issue。
2. 写出问题、Owner、选项、判断标准、影响和回滚。
3. 由 Decision owner 确认最终选择。
4. 更新受影响的 Active Spec。
5. 更新合同、模板和检查。
6. 完成评审和验收。

禁止在实现 PR 中静默改变 Active Spec。禁止为新决策创建 ADR。

## 6. Spec 变更

- 一个规则只出现在一个 Active Spec。
- Active Spec 的文件名不包含版本号。
- Spec 路径保持稳定。
- Spec 只保存当前规则。
- 决策选项和讨论历史留在 Issue。
- 改变规则时，在同一个 PR 更新规则、影响和验证。
- Spec 合并后立即成为当前规则入口。

入口见 [Active Spec 索引](docs/specs/index.md)。

## 7. 合同变更

- `kshift.v1` 内只做兼容变更。
- 删除字段或改变语义时，必须新增 package 版本。
- 字段编号不得复用。
- 删除字段时，使用 `reserved` 标记编号和名称。
- Release JSON Schema 使用新增可选字段保持兼容。
- 破坏性变更必须更新 schema version，并保留迁移说明。

## 8. 标签与 Project

- 每个开放 Issue 只增加 1 个 `type:` 标签。
- 每个开放 Issue 至少增加 1 个 `area:` 标签。
- `risk:`、`needs:` 和 `accessibility` 按影响增加。
- Project `Status` 是唯一状态来源。
- 配置、迁移和审计见 [标签与 Project 配置](docs/governance/labels-and-project.md)。

## 9. PR 检查

- [ ] PR 链接了实现 Issue。
- [ ] PR 正文使用 `Closes #N` 或 `Part of #N`。
- [ ] Worktree 交付使用 `Part of #N`。
- [ ] PR 已记录 Worktree 路径和 branch。
- [ ] 证据迁移和清理结果已记录，或已写明不适用原因。
- [ ] 清理项已有 `@wyz541` 的明确批准。
- [ ] Active Spec 链接有效。
- [ ] Decision Issue 已链接。
- [ ] 合同变更兼容或已有新版本。
- [ ] 验收结果来自实际运行。
- [ ] 未运行的项目没有写成通过。
- [ ] 已判断文档、FAQ 或 Release note 影响。
- [ ] 没有提交秘密、令牌、私钥或数据库凭据。

## 10. 本地构建

本地 Xcode 构建只写入 `build/DerivedData`。执行构建命令时，必须增加 `-derivedDataPath build/DerivedData`。

- 运行 `make app-paths` 查看当前 Debug App 路径。
- 运行 `make check-build-governance` 检查固定路径和稳定标识。
- Debug App 显示名为 `Kshift Dev`。Release App 显示名为 `Kshift`。
- 禁止把 Debug App 复制到 `/Applications` 或 `~/Applications`。
- 只允许测试命令启动 Test Runner。

完整规则和旧 DerivedData 清理清单格式见
[本地构建路径治理](docs/local-build.md)。

## 11. 检查

运行以下命令。

```bash
./scripts/check-r0.sh
python3 scripts/audit_issue_relations.py --repo wyz541/Kshift --issue <N>
python3 scripts/audit_worktrees.py --repo . --expected-task-worktrees <N>
```

命令必须成功。检查结果写入 PR 的 `## 验收证据`。
