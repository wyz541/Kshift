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
```

## 平台

| 平台 | 必需资产 |
| --- | --- |
| `server` | Server bundle |
| `macos` | DMG 或 ZIP application |
| `ios` | 签名 IPA application |
| `source` | Source archive |

## Stable 状态

`release/policy.json` 控制 Stable 必需平台、角色、gate 和签名状态。当前决策状态为 `pending`。Stable 合并和验证会失败，直到决策变更为 `approved` 且所有运行时 gate 通过。

## 资产规则

- 文件名只能是安全的基础文件名。
- 所有 fragment 必须使用同一 channel、version 和 source commit。
- 所有资产必须有 `size_bytes` 和 SHA-256。
- 重复资产名会被拒绝。
- 绝对本地路径和 secret-like 字段会被拒绝。
- Stable 不允许 `ad-hoc` 或 `unsigned` application 资产。

## 测试

```bash
node --test release/test/release.test.mjs
```
