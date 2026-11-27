---
slug: /evidence/v0.2.0-release
title: Kshift v0.2.0 Stable release evidence
type: report
status: review
updated: "2026-11-27"
owner: "@wyz541"
keywords:
  - Kshift
  - v0.2.0
  - Stable
  - release
  - macOS
  - server
description: Records successful Kshift v0.2.0 Stable candidate, Draft, same-Draft Promote, runtime gates, latest manifest and local installation.
---

# Kshift v0.2.0 Stable release evidence

Issue: [#167](https://github.com/wyz541/Kshift/issues/167)
Release PR: [#168](https://github.com/wyz541/Kshift/pull/168)
Release: [v0.2.0](https://github.com/wyz541/Kshift/releases/tag/v0.2.0)

## 结论

`v0.2.0` Stable 已成功发布。server、macOS 和 source 使用同一 source commit；Draft 验证通过后只 Promote 同一个 Draft。macOS 本机应用已替换为发布版 `0.2.0`。

Source commit：`04289a715c498e66c09480852e215cf92062229d`

## Release publication

| Stage | Run / result |
| --- | --- |
| Stable candidate | [45952130399](https://github.com/wyz541/Kshift/actions/runs/45952130399): PASS |
| Prepare Draft | [45952650836](https://github.com/wyz541/Kshift/actions/runs/45952650836): PASS |
| Verify Draft | [45952954690](https://github.com/wyz541/Kshift/actions/runs/45952954690): PASS |
| Promote same Draft | [45953043023](https://github.com/wyz541/Kshift/actions/runs/45953043023): PASS |
| GitHub Release | `v0.2.0`: non-draft, `prerelease=false` |
| Latest manifest | `release_status=promoted`, `version=0.2.0` |

## Published assets

| Asset | SHA-256 |
| --- | --- |
| `kshift-0.2.0-macos-arm64.dmg` | `d9aa955b92f3571b8212c73d2f15eda6bc144f42c8c145be95c743e8ff14ffe5` |
| `kshift-0.2.0-macos-arm64.zip` | `971d25da1b0486cb0368793259fb56670058b06db3fa40a6b9e3ee7c028062cb` |
| `kshift-0.2.0-server-macos-arm64.tar.gz` | `b406dcaf3b8e4bc64b739605fed9c310fa54ddfeb498703a56fbc9b8b916687b` |
| `kshift-0.2.0-source.tar.gz` | `c3bfe7d3e8569e8139682c05eb5eface419706dccd2463cbbb13effe1bf6b063` |
| `release-manifest.json` | `986384a9ea50fe6f30945b914119abe34ab378723b47b7eb7b4390e49d80f0a9` |

完整清单见 [`published-SHA256SUMS`](./published-SHA256SUMS)。

## Runtime gates

Server：

- health
- migration
- backup-restore
- startup-recovery
- logs

macOS：

- install
- upgrade
- uninstall
- rollback
- liquid-glass
- accessibility
- performance

Evidence：

- `release/evidence/server-runtime.json`
- `release/evidence/macos-runtime.json`
- [`macos-accessibility-audit.json`](./macos-accessibility-audit.json)
- Light、Dark、Large Text、Accessibility、Upgrade 和 Performance 截图保存在本目录。

## Local installation

| 项目 | 结果 |
| --- | --- |
| Installed path | `/Users/wyz/Applications/Kshift.app` |
| Bundle identifier | `com.wyz541.kshift.mac` |
| Display name | `Kshift` |
| Version / Build | `0.2.0` / `0.2.0` |
| Signature | ad-hoc，`codesign --verify --deep --strict` 通过 |
| Previous app backup | `~/repo/Kshift/build/local-app-backups/Kshift.app.pre-v0.2.0-20261127T144850` |
| Launch | Demo Mode 下启动成功 |
| Check for Updates | 首次请求超时；Retry 后显示 `No update is available.` |
| Screenshots | [`macos-installed-0.2.0.png`](./macos-installed-0.2.0.png)、[`macos-update-check-0.2.0.png`](./macos-update-check-0.2.0.png) |

本机没有提供 `KSHIFT_ENDPOINT`、CA 和 token，因此真实 server-backed UI 没有在本机安装后重新联调；无配置启动会明确显示缺少 `KSHIFT_ENDPOINT`，不以 Demo 结果替代 live FFI 验证。

## Limits

- iOS 仍仅做内部测试，不属于 Stable 资产。
- Windows Stable 不在本次范围。
- macOS 使用 ad-hoc 签名，未做 Developer ID/notarization。
- 本机更新检查首次超时，Retry 成功；未执行真实下载新版本安装流程，因为当前已是最新 `0.2.0`。
