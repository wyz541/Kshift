---
slug: /evidence/internal-preview-4
title: Kshift v0.1.0 Internal Preview 4 evidence
type: report
status: review
updated: "2026-11-26"
owner: "@wyz541"
keywords:
  - Internal Preview
  - macOS
  - iOS
  - ad-hoc
  - unsigned
description: 记录 Issue #143 的 Internal Preview 4 本地 macOS ad-hoc 与 unsigned iOS 构建、签名边界、发布限制和后续 workflow 证据入口。
---

# Kshift v0.1.0 Internal Preview 4 evidence

Issue: #143
Source commit: `e194a5c24f9148eb70ab0fed4adeeaf3dbd26409`
Date: 2026-11-26

## Decision

`@wyz541` 选择 Internal Preview，而不是使用正式 iOS 分发签名。

- GitHub Release 必须是 Prerelease。
- iOS IPA 保持 unsigned；它不可直接安装到普通 iPhone。
- macOS DMG/ZIP 使用 ad-hoc 签名并验证。
- Preview 不进入 Stable update feed。
- 公开仓库不携带 development `mobileprovision`、p12 或设备 UDID。

## Local build evidence

| Asset | Size/signature check | SHA-256 |
| --- | --- | --- |
| macOS DMG | `Signature=adhoc`; `codesign --verify --deep --strict` passed | `ddc1a17ea0f1e8dce5488b8b0f52a26c84778fff27119eac1d73c06b5a391454` |
| macOS ZIP | codesign-verified source app packed by `ditto` | `93152cfbf5df3cd78469c728a6ddd95072121478aff447bfb3dfc659c21b704d` |
| iOS IPA | unsigned; embedded profile absent | `4a9e063c79393352531b27dde29445b344a549cc2e9347086a392613d8b40e23` |

Local commands:

```bash
env -u MACOS_SIGN_IDENTITY \
  KSHIFT_CHANNEL=preview \
  KSHIFT_VERSION=0.1.0 \
  KSHIFT_OUTPUT_DIR=/tmp/kshift-preview4-macos.39l064 \
  ./release/platform/build-macos.sh
```

```bash
KSHIFT_CHANNEL=preview \
KSHIFT_VERSION=0.1.0 \
KSHIFT_OUTPUT_DIR=/tmp/kshift-preview4-ios.oXBIfJ \
  ./release/platform/build-ios.sh
```

Both builds completed with `BUILD SUCCEEDED`.

## Release output

- Candidate workflow run: pending
- Prepare Draft run: pending
- Verify Draft run: pending
- Promote Prerelease run: pending
- Published Release URL: pending
- Final Release must remain `prerelease=true`.

## Not run

- iPhone installation: **NOT RUN**; IPA is unsigned.
- TestFlight or formal iOS distribution: **NOT RUN** and out of Preview scope.
- Notarization: **NOT RUN**; Developer ID/notarization is not required by the current policy.
- Stable update feed: intentionally not applicable.
- Stable Release: not created.
