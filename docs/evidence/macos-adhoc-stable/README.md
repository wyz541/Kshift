---
slug: /evidence/macos-adhoc-stable
title: macOS ad-hoc Stable signing evidence
type: report
status: review
updated: "2026-11-25"
owner: "@wyz541"
keywords:
  - macOS
  - Stable
  - ad-hoc
  - codesign
  - notarization
description: 记录 Issue #140 删除 Developer ID/notarization 强制门禁后的 policy、release validator、in-app update eligibility 和真实 ad-hoc macOS 构建证据。
---

# macOS ad-hoc Stable signing evidence

Issue: #140
Branch: `issue/140-remove-macos-signing-gate`
Date: 2026-11-25

## Decision

`@wyz541` 明确要求删除 macOS Stable 的 Developer ID + notarization 强制门禁。

实现结果：

- macOS Stable policy 接受 `ad-hoc`、`signed`、`notarized`。
- 没有 Developer ID 时，Stable build 自动执行 ad-hoc 签名并运行 `codesign --verify --deep --strict`。
- `unsigned` 和 debug application 仍禁止进入 Stable。
- In-app update 只有在 manifest 和 asset 同为 `ad-hoc`，或同为正式签名时才接受。
- macOS DMG 安装前挂载镜像并验证内部 `.app` 的 code signature，不再依赖 notarization/Gatekeeper assessment。
- `release/policy.json` 的总体 `decision_status` 仍为 `pending`；其他 Stable 决策和 runtime gates 仍由 #139 管理。

## Automated checks

| Check | Command | Result |
| --- | --- | --- |
| Release tool tests | `node --test release/test/release.test.mjs` | PASS: 14 tests |
| Update checker tests | `swift test --filter KshiftUpdateTests` | PASS: 12 tests |
| Full Swift suite | `make swift-test` | PASS: 68 core + 6 adapter tests; 3 live-only core tests skipped |
| R0 | `./scripts/check-r0.sh` | PASS |
| R4/R5 | `./scripts/check-r4-r5.sh` | PASS; 7 PostgreSQL tests skipped because `TEST_DATABASE_URL` is unset |

Covered assertions:

- repository policy includes macOS/global `ad-hoc`;
- Stable merge accepts a fully gated ad-hoc macOS fragment;
- Stable merge rejects unsigned macOS;
- update checker accepts manifest+asset both `ad-hoc`;
- update checker rejects unsigned and mismatched signing status;
- YAML parsing, workflow contract, release schema and shell syntax pass.

## Real ad-hoc Stable package

Command:

```bash
env -u MACOS_SIGN_IDENTITY \
  KSHIFT_CHANNEL=stable \
  KSHIFT_VERSION=0.1.0 \
  KSHIFT_OUTPUT_DIR=/tmp/kshift-adhoc-stable.xXTOcX \
  ./release/platform/build-macos.sh
```

Result:

```text
** BUILD SUCCEEDED **
signing macOS application ad-hoc
Kshift-macOS.app: replacing existing signature
Kshift-macOS.app: valid on disk
Kshift-macOS.app: satisfies its Designated Requirement
```

DMG verification:

```text
Identifier=com.wyz541.kshift.mac
Signature=adhoc
TeamIdentifier=not set
Sealed Resources version=2 rules=13 files=2
Kshift-macOS.app: valid on disk
Kshift-macOS.app: satisfies its Designated Requirement
SecStaticCodeCheckValidity=0
tampered SecStaticCodeCheckValidity=-67030
```

The tamper check modified the extracted ZIP app's `Info.plist`; static code validation failed closed.

Artifacts from this local run:

| Asset | SHA-256 |
| --- | --- |
| `kshift-0.1.0-macos-arm64.dmg` | `4579bdee0352fc4636574e3179bacaae64dcd14a88d4815bfd3aa64cac137eee` |
| `kshift-0.1.0-macos-arm64.zip` | `3849cdcc0f76e9a62ee12a2b17e4de693b0e942c25482ad9ab790f44bbbb3086` |
| `macos-sha256.txt` | `622f25f0637c06da92ffcb36788b91a446f8ceaa773a264ae17bd91207ac8c1b` |

The generated binaries are local verification artifacts and are not committed.

## Not run

- Notarization: intentionally removed from the Stable gate.
- Gatekeeper acceptance on a clean external Mac: **NOT RUN**.
- Stable Release candidates/prepare/verify-draft/promote: **NOT RUN**; other #139 gates remain blocking.
- Install/upgrade/uninstall/rollback on a clean macOS host: **NOT RUN**.
- macOS Settings update screenshot: **NOT RUN** in this Task.
