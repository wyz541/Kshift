---
slug: "/docs/r4-r5/evidence/2026-11-16-release-candidate"
title: "R4/R5 release candidate evidence"
type: "evidence"
status: "review"
updated: "2026-11-16"
keywords:
  - release candidate
  - GitHub Actions
  - attestation
  - source archive
  - server bundle
description: "记录远端 preview Release candidate、server/source fragments 和 GitHub attestation 验证。"
---

# R4/R5 release candidate evidence

结论：远端 preview candidate 通过。Server 和 source 资产来自同一个 `main` commit。两个资产的 GitHub attestation 可以验证。Candidate 没有创建 Release 或 tag。

## Run

| 项目 | 值 |
| --- | --- |
| Workflow | `Release candidates` |
| Run ID | `43882883172` |
| Run URL | https://github.com/wyz541/Kshift/actions/runs/43882883172 |
| Source commit | `8214716fc7da387005a836820cd66b057511ea1f` |
| Channel | `preview` |
| Version | `0.1.0` |
| Expected tag | `v0.1.0-preview.1` |
| Candidate contract | Passed |
| Server job | Passed |
| Source job | Passed |
| macOS job | Skipped by input |
| iOS job | Skipped by input |

## Artifacts

| Platform | Asset | Size | SHA-256 |
| --- | --- | ---: | --- |
| Source | `kshift-0.1.0-source.tar.gz` | 9,162,328 bytes | `bb20c897e14a50c50704ba2168187aebb67beaa64b4880df713f016a9a3e3e5e` |
| Server | `kshift-0.1.0-server-macos-arm64.tar.gz` | 4,311,937 bytes | `753b68b7227c4462e15612ddd4df2020fdf86db202a3394d841a802d2dd2ed0b` |

| Artifact archive | Archive SHA-256 |
| --- | --- |
| `release-fragment-source` | `8b044f762747a714ee5e7c573975ac2142aee7a6dcc2d990c2a0f0d08edffd0b` |
| `release-fragment-server-macos` | `a0379e56e094612c79f88970c56214992fc407039df22ce59d30215ee7ff8957` |

两个 fragment 的 `source_commit` 都是 `8214716fc7da387005a836820cd66b057511ea1f`。两个 fragment 的 `version` 都是 `0.1.0`，`channel` 都是 `preview`。

## Attestation

| Platform | Signer workflow | Result |
| --- | --- | --- |
| Source | `.github/workflows/release-candidates.yml` | Verified |
| Server | `.github/workflows/release-platform-server.yml` | Verified |

```bash
gh attestation verify kshift-0.1.0-source.tar.gz \
  --repo wyz541/Kshift \
  --signer-workflow wyz541/Kshift/.github/workflows/release-candidates.yml \
  --source-digest 8214716fc7da387005a836820cd66b057511ea1f \
  --source-ref refs/heads/main

gh attestation verify kshift-0.1.0-server-macos-arm64.tar.gz \
  --repo wyz541/Kshift \
  --signer-workflow wyz541/Kshift/.github/workflows/release-platform-server.yml \
  --source-digest 8214716fc7da387005a836820cd66b057511ea1f \
  --source-ref refs/heads/main
```

## Release State

| 检查 | 结果 |
| --- | --- |
| Release list after candidate | Empty |
| Tag `v0.1.0-preview.1` | Not found |
| Release created by candidate | No |
| Tag created by candidate | No |

Candidate workflow 使用 `contents: read`。它只构建和上传 workflow artifacts。Draft 和 Promote 仍由 `release-orchestrate.yml` 处理。

## Coverage Boundary

- macOS candidate 使用 input `build_macos=false`。
- iOS candidate 使用 input `build_ios=false`。
- Server runtime gates 仍为 `skipped`，因为 runner 不是目标主机。
- 本次没有创建 Draft，也没有 Promote。
- 本次没有验证 Stable signing、TestFlight、tag protection 或 immutable release。

原始 summary 保存在 [2026-11-16-release-candidate.json](2026-11-16-release-candidate.json)。
