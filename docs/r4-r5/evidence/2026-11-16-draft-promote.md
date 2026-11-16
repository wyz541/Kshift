---
slug: "/docs/r4-r5/evidence/2026-11-16-draft-promote"
title: "R4/R5 Draft and Promote evidence"
type: "evidence"
status: "review"
updated: "2026-11-16"
keywords:
  - Draft
  - Promote
  - release evidence
  - checksums
  - attestation
description: "记录 preview Draft prepare、byte verification 和 same-Draft Promote 的远端证据。"
---

# R4/R5 Draft and Promote evidence

结论：Preview Draft 通过 bytes、manifest 和 attestation 验证。Promote 只把同一个 Draft 改为 Preview Release。Server 和 source 资产 hash 在 candidate、Draft 和 Promote 后保持一致。

## Runs

| 阶段 | Run ID | 结果 |
| --- | ---: | --- |
| Prepare Draft | `43888138339` | Passed |
| Standalone Draft verification | `43889591915` | Passed |
| Verify and Promote same Draft | `43890092316` | Passed |

Run `43888308121`、`43888451065`、`43888898383` 和 `43889425396` 暴露了 Draft verification defects。修复后，Draft verification 通过。本记录不把这些 failed runs 写成通过。

## Draft

| 项目 | 值 |
| --- | --- |
| Tag | `v0.1.0-preview.1` |
| Source commit | `8214716fc7da387005a836820cd66b057511ea1f` |
| Draft state before Promote | `draft` |
| Missing platforms | `macos`, `ios` |
| Release manifest SHA-256 | `9c362c796a3c784b46c2546fa96c96474a9a12d15f235e3d9c1ef71dc13036d7` |

Prepare 从 candidate run `43882883172` 下载 server/source fragments。它生成 SBOM、release notes、manifest、release evidence 和 `SHA256SUMS`。Draft 包含以下 checksum-listed files。

- Server bundle
- Source archive
- Server fragment
- Source fragment
- Release manifest
- Release evidence
- Release notes
- SBOM

## Verification

| 检查 | 结果 |
| --- | --- |
| `SHA256SUMS` verification | 8/8 files OK |
| Manifest schema validation | Passed |
| Manifest asset bytes | Passed |
| Server/server attestation | Passed |
| Source asset attestation | Passed |
| Draft remained draft before Promote | Passed |

Verifier 只对 `application`、`server-bundle` 和 `source` assets 执行 build-attestation verification。SBOM 和 release notes 使用 checksum verification。

## Promote

| 项目 | 值 |
| --- | --- |
| Release ID | `447164898` |
| Release URL | https://github.com/wyz541/Kshift/releases/tag/v0.1.0-preview.1 |
| `isDraft` | `false` |
| `isPrerelease` | `true` |
| Tag target | `8214716fc7da387005a836820cd66b057511ea1f` |
| Manifest `release_status` | `promoted` |
| Promotion actor | `wyz541` |
| Promotion run ID | `43890092316` |

Promote 下载同一个 Draft，校验 checksums 和 manifest，更新 promotion metadata，然后只执行 `gh release edit --draft=false`。它没有运行平台 build，也没有上传同名平台资产。

## Asset Identity

| Asset | Candidate SHA-256 | Promoted SHA-256 | Changed |
| --- | --- | --- | --- |
| Server bundle | `753b68b7227c4462e15612ddd4df2020fdf86db202a3394d841a802d2dd2ed0b` | `753b68b7227c4462e15612ddd4df2020fdf86db202a3394d841a802d2dd2ed0b` | No |
| Source archive | `bb20c897e14a50c50704ba2168187aebb67beaa64b4880df713f016a9a3e3e5e` | `bb20c897e14a50c50704ba2168187aebb67beaa64b4880df713f016a9a3e3e5e` | No |

Post-promotion `SHA256SUMS` verification passed for all 8 files. The final checksums SHA-256 is `53e2ab4569855a7219b8ac63baa8f6f6ed0fa331c8f33863a0367d87729f9339`.

## Coverage Boundary

- This Release is `preview`, not Stable.
- macOS and iOS fragments are missing.
- Server runtime gates remain `skipped`.
- Stable signing and TestFlight are not verified.
- Tag protection and immutable releases are not configured.
- The Preview Release is public in the repository, but the product deployment remains internal-only.

原始 summary 保存在 [2026-11-16-draft-promote.json](2026-11-16-draft-promote.json)。
