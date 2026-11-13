# 贡献与评审流程

结论：每个实现 Issue 必须引用 Spec、ADR 和合同。冲突规则只在一个权威位置维护。

## 权威顺序

1. 已确认的 Spec 规则。
2. 已接受的 ADR。
3. 版本化协议和 JSON Schema。
4. Issue 和 PR 的实施说明。

下层文档不得覆盖上层规则。需要改变上层规则时，先提交决策变更。

## Issue 要求

每个实现 Issue 必须包含以下字段。

- `Spec`：链接到 `docs/spec/kshift-spec-v0.1.md` 的具体章节。
- `Decision`：链接到受影响的 ADR 或 decision ID。
- `Contract`：列出受影响的 protobuf 或 JSON Schema 文件。
- `Acceptance`：写出可以观察的完成结果。
- `Evidence`：写出需要保留的测试或运行证据。

Issue 不复制 Spec 的完整规则。Issue 只写本次交付范围和验证方法。

## 工作流

1. 从 `main` 创建短生命周期分支。
2. 更新 Spec、ADR 或合同。必要时同步更新。
3. 增加测试、示例或评审记录。
4. 运行 R0 检查。
5. 打开 PR。PR 必须链接 Issue。
6. 评审人检查 Spec 追踪、决策状态和证据。
7. 合并后更新 Issue 的验收清单。

## 决策变更

已确认决策只能通过以下方式改变。

1. 新建 ADR，状态为 `proposed`。
2. 写出旧决策、新决策、迁移和回滚影响。
3. 更新 decision register。
4. 更新 Spec 和合同。
5. 完成评审后，把 ADR 改为 `accepted`。

禁止在实现 PR 中静默改变已确认决策。

## 合同变更

- `kshift.v1` 内只做兼容变更。
- 删除字段或改变语义时，必须新增 package 版本。
- 字段编号不得复用。
- 删除字段时，使用 `reserved` 标记编号和名称。
- Release JSON Schema 使用新增可选字段保持兼容。
- 破坏性变更必须更新 schema version，并保留迁移说明。

## PR 检查

- [ ] PR 链接了实现 Issue。
- [ ] Spec 章节链接有效。
- [ ] 决策状态已更新。
- [ ] ADR 已链接。
- [ ] 合同变更兼容或已有新版本。
- [ ] 验收结果来自实际运行。
- [ ] 未运行的项目没有写成通过。
- [ ] 没有提交秘密、令牌、私钥或数据库凭据。

## R0 检查

运行以下命令。

```bash
./scripts/check-r0.sh
```

命令必须成功。检查结果需要写入 PR。
