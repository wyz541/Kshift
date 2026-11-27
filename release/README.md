# Kshift Release 合同

结论：Release manifest 是发布的唯一事实源。平台 fragment 只描述已经构建和验证的资产。

## 合同文件

| 项目 | 文件 |
| --- | --- |
| Manifest schema | [`schemas/release-manifest.schema.json`](../schemas/release-manifest.schema.json) |
| Fragment schema | [`schemas/release-fragment.schema.json`](../schemas/release-fragment.schema.json) |
| Candidate schema | [`release/schema/candidate.schema.json`](schema/candidate.schema.json) |
| 合同说明 | [`docs/contracts/release-v0.1.md`](../docs/contracts/release-v0.1.md) |

Schema version 为 `1`。

## 命令

```bash
node release/tools/kshift-release.mjs validate-candidate \
  --candidate release/examples/candidate.json

node release/tools/kshift-release.mjs fragment \
  --spec release/examples/fragment-spec.json \
  --assets-dir release-assets \
  --output server.fragment.json

node release/tools/kshift-release.mjs merge \
  --candidate release/examples/candidate.json \
  --fragments-dir fragments \
  --sbom sbom.spdx.json \
  --notes release-notes.md \
  --output release-manifest.json \
  --mode draft

node release/tools/kshift-release.mjs validate \
  --manifest release-manifest.json \
  --mode stable

node release/tools/kshift-release.mjs verify-assets \
  --manifest release-manifest.json \
  --assets-dir release-assets

node release/tools/runtime-evidence.mjs verify \
  --root . \
  --evidence release/evidence/server-runtime.json \
  --platform server \
  --version 0.1.0 \
  --channel stable \
  --candidate-commit "$(git rev-parse HEAD)" \
  --bundle /path/to/server-bundle \
  --expected-gates health,migration,backup-restore,startup-recovery,logs \
  --output server-runtime-gates.json
```

## 平台

| 平台 | 必需资产 |
| --- | --- |
| `server` | Server bundle |
| `macos` | DMG 或 ZIP application |
| `ios` | 内部测试构建；无 Apple Developer Program 时不属于 Stable required platform |
| `source` | Source archive |

## Stable 状态

`release/policy.json` 控制 Stable 必需平台、角色、gate 和签名状态。当前决策已批准为 server、macOS、source；iOS 没有 Apple Developer Program，仅保留内部测试证据，不属于 Stable required platform。`v0.2.0` 已通过 runtime evidence、candidate、Draft、`verify-draft` 和 same-Draft Promote；后续 Stable 合并和验证仍会 fail closed，直到新候选的 server 与 macOS 运行时 gate 通过。

## Runtime evidence

Stable runtime evidence 固定位于 `release/evidence/server-runtime.json` 和 `release/evidence/macos-runtime.json`，目录规则见 [`evidence/README.md`](evidence/README.md)。平台 workflow 在校验源码输入摘要和实际制品摘要后，才把对应 gate 写入 fragment。

生成入口：

```bash
./scripts/run-server-release-gates.sh
./scripts/run-macos-release-gates.sh
```

生成脚本要求 clean source tree。证据文件本身和 `docs/evidence/` 中的截图在生成后提交；不得手工把 `skipped` 改成 `passed`。

## 资产规则

- 文件名只能是安全的基础文件名。
- 所有 fragment 必须使用同一 channel、version 和 source commit。
- 所有资产必须有 `size_bytes` 和 SHA-256。
- 重复资产名会被拒绝。
- 绝对本地路径和 secret-like 字段会被拒绝。
- Stable 不允许 unsigned application 资产；macOS `ad-hoc` 仅在 policy 允许时可用于内部 Stable。

## 测试

```bash
node --test release/test/release.test.mjs
```
