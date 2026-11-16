---
slug: "/docs/r4-r5/evidence/2026-11-16-platform-candidates"
title: "R4/R5 platform candidate evidence"
type: "evidence"
status: "review"
updated: "2026-11-16"
keywords:
  - platform candidate
  - macOS build
  - iOS build
  - attestation
  - release candidate
description: "记录 preview server、macOS、iOS 和 source 的同源 candidate 构建与 attestation。"
---

# R4/R5 platform candidate evidence

结论：Preview candidate 从同一个 `main` commit 构建 server、macOS、iOS 和 source。四个平台资产都有可验证 attestation。Candidate 没有创建 Release 或 tag。

## Run

| 项目 | 值 |
| --- | --- |
| Workflow | `Release candidates` |
| Run ID | `43896233627` |
| Run URL | https://github.com/wyz541/Kshift/actions/runs/43896233627 |
| Source commit | `96afb71a757c0f8c2f38984f1bc12536a60cefa8` |
| Channel | `preview` |
| Version | `0.1.0` |
| Expected tag | `v0.1.0-preview.2` |
| Candidate contract | Passed |
| Server job | Passed |
| macOS job | Passed |
| iOS job | Passed |
| Source job | Passed |

## Artifacts

| Platform | Asset | Size | SHA-256 |
| --- | --- | ---: | --- |
| Source | `kshift-0.1.0-source.tar.gz` | 9,471,541 bytes | `597af241f82c2540e3abf8ba8c51987cec95cbe741edca158fc8fd90e3fcd753` |
| Server | `kshift-0.1.0-server-macos-arm64.tar.gz` | 4,311,930 bytes | `1b51edc0e8ee8b09ebff563ece37b04b9c8e24b45745185b799a0f9643b47a7a` |
| macOS | `kshift-0.1.0-macos-arm64.dmg` | 6,266,611 bytes | `6afbfcf6da007e569019056f19e0afd6bcca6b9e4a299edd35e3278ed5f93192` |
| macOS | `kshift-0.1.0-macos-arm64.zip` | 5,443,494 bytes | `90a83dd915acb812ba72ad0e116dda294051625a782c2f3d0e15e5c2b910b254` |
| iOS | `kshift-0.1.0-ios-arm64.ipa` | 3,961,349 bytes | `da2f4f63f0e01c6a8a30485bb6dd8cdc49abd851b572969532d28185b2cff7e1` |

每个 fragment 的 `source_commit` 都是 `96afb71a757c0f8c2f38984f1bc12536a60cefa8`。

| Artifact archive | Archive SHA-256 |
| --- | --- |
| `release-fragment-source` | `c33b87f7860f1b2eed6958672841b3f52bfc18063450282d470ccdd6982a510e` |
| `release-fragment-server-macos` | `07a6d9bd468385582bf79b427e60685c07fba297bf838b5f6428cf3113a14ecf` |
| `release-fragment-macos` | `4b3a8beaefe873142741ca6572a2eaaa16d529e4ed72cf84344f40c10ab48168` |
| `release-fragment-ios` | `caf6656a0996ed9d304f9d9c6ee3406a95ca42012335f8be05dbb0165c3e1390` |

## Attestation

| Platform | Signer workflow | Result |
| --- | --- | --- |
| Source | `.github/workflows/release-candidates.yml` | Verified |
| Server | `.github/workflows/release-platform-server.yml` | Verified |
| macOS | `.github/workflows/release-platform-macos.yml` | Verified |
| iOS | `.github/workflows/release-platform-ios.yml` | Verified |

```bash
gh attestation verify kshift-0.1.0-macos-arm64.dmg \
  --repo wyz541/Kshift \
  --signer-workflow wyz541/Kshift/.github/workflows/release-platform-macos.yml \
  --source-digest 96afb71a757c0f8c2f38984f1bc12536a60cefa8 \
  --source-ref refs/heads/main

gh attestation verify kshift-0.1.0-ios-arm64.ipa \
  --repo wyz541/Kshift \
  --signer-workflow wyz541/Kshift/.github/workflows/release-platform-ios.yml \
  --source-digest 96afb71a757c0f8c2f38984f1bc12536a60cefa8 \
  --source-ref refs/heads/main
```

## Release State

| 检查 | 结果 |
| --- | --- |
| Release list after candidate | Only existing `v0.1.0-preview.1` |
| Tag `v0.1.0-preview.2` | Not found |
| Release created by candidate | No |
| Tag created by candidate | No |

## Build Fixes Verified

| 问题 | 修复 | 结果 |
| --- | --- | --- |
| macOS selected x86_64 but FFI was arm64 | Explicit arm64 platform build | Passed |
| iOS used simulator Rust target for device build | Select FFI target from `SDK_NAME` | Passed |
| Xcode release linked `target/debug` | Select Rust profile from `KSHIFT_RUST_PROFILE` | Passed |
| CI used a Rust toolchain without iOS target | Use workflow-installed `cargo` and targets | Passed |

## Coverage Boundary

- All platform artifacts are unsigned Preview artifacts.
- macOS signing, notarization, clean-host install, upgrade and rollback are not covered.
- iOS distribution signature, TestFlight and physical-device install are not covered.
- Server runtime gates remain `skipped`.
- The candidate did not create a Draft or Promote a Release.

原始 summary 保存在 [2026-11-16-platform-candidates.json](2026-11-16-platform-candidates.json)。
