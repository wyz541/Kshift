---
slug: /evidence/stable-v0.1.0-final
title: Kshift v0.1.0 Stable final runtime gates
type: report
status: review
updated: "2026-11-27"
owner: "@wyz541"
keywords:
  - Kshift
  - v0.1.0
  - Stable
  - macOS
  - server
  - runtime-gates
description: 记录 v0.1.0 Stable server 与 macOS runtime evidence、macOS 制品生命周期、Liquid Glass、无障碍和性能结果。
---

# Kshift v0.1.0 Stable final runtime gates

Issue: #139
PR: #160
Date: 2026-11-27

## 结论

Server 与 macOS 的 Stable runtime gates 已通过，并绑定到平台输入摘要和实际制品摘要。

- Server evidence: `release/evidence/server-runtime.json`
- macOS evidence: `release/evidence/macos-runtime.json`
- Evidence source commit: `7fff44d7628e9bedcd9c8c49814bc0db8980bb6b`

Stable 尚未发布。Release candidate、Draft、`verify-draft`、Promote、`/releases/latest` 和 Check for Updates 仍需在 PR #160 合并后运行。

## Server gates

| Gate | Result |
| --- | --- |
| Health | PASS: TLS endpoint serving before and after restart |
| Migration | PASS: `v0.1.0-preview.4` bundle upgraded a PostgreSQL 18.7 database while preserving project rows |
| Backup/restore | PASS: restore and transaction rollback verified; project count and migration digest matched |
| Startup recovery | PASS: LaunchAgent restarted after SIGKILL and replayed the pre-restart event |
| Logs | PASS: stdout/stderr present; no token, database URL or panic found; newsyslog config valid |

Server binary SHA-256: `16976650b2d864165dd4c02666e809b33c790dc1498e8841cfe0d58566499697`.

## macOS lifecycle gates

| Gate | Result |
| --- | --- |
| Install | PASS: copied from Stable DMG, code signature verified, launched |
| Upgrade | PASS: replaced `v0.1.0-preview.4` app with `0.1.0` Stable app, launched |
| Uninstall | PASS: isolated application removed and process stopped |
| Rollback | PASS: previous application restored and launched |
| Liquid Glass | PASS: native `GlassEffectContainer` and `Glass.regular` present; light, dark and accessibility text captures |
| Accessibility | PASS: 343 AX elements, 38 interactive elements, zero issues; native window chrome/stepper exemptions recorded |
| Performance | PASS: 3 iterations, average 2074 ms, max 2105 ms; thresholds 5000/8000 ms |

macOS executable SHA-256: `943252a0ec33098cfb8d342da5a3780b2c039c57e401b5c345ee300e7b92bb0a`.

## Visual evidence

| File | Purpose |
| --- | --- |
| `macos-liquid-glass-light.png` | Light mode native glass task surfaces |
| `macos-liquid-glass-dark.png` | Dark mode native glass task surfaces |
| `macos-large-text.png` | Accessibility XXXL reflow |
| `macos-accessibility-audit.json` | External AX audit details and exemptions |

## Limits

- Lifecycle ran in an isolated application directory on the internal Apple-silicon macOS host.
- The previous macOS artifact is `v0.1.0-preview.4` and does not embed `CFBundleShortVersionString`.
- Increase Contrast and Reduce Motion source branches are statically checked; system-level toggling was not automated.
- The accessibility audit checks labels, hit regions, actions and core identifiers. It does not replace a human VoiceOver review or pixel-by-pixel contrast inspection.
