---
slug: /evidence/stable-v0.1.0-qualification
title: Kshift v0.1.0 Stable qualification evidence
type: report
status: review
updated: "2026-11-25"
owner: "@wyz541"
keywords:
  - Kshift
  - v0.1.0
  - Stable
  - qualification
  - release
description: 记录 Issue #139 的 Stable candidate、server LaunchAgent、备份恢复、生命周期、负载和剩余发布阻断证据。
---

# Kshift v0.1.0 Stable qualification evidence

> 2026-11-27 update：server 与 macOS 最终 runtime gates 已通过，见 [stable-v0.1.0-final](../stable-v0.1.0-final/README.md)。本页保留 2026-11-25 的阶段性失败记录。

Issue: #139
Source commit: `d3ebc56fb10fb1f25cad710599170ef7e31ade1d`
Date: 2026-11-25

## Conclusion

Automated qualification is partially complete. No Stable Release has been created.

The official Stable candidate run failed closed because iOS signing secrets were absent. Server and macOS candidate jobs passed, but the release workflow still records runtime/UI gates as skipped. Those gaps must be wired to real evidence and `release/policy.json` must become `approved` before Stable promotion.

## Release candidate

- Workflow: `Release candidates`
- Run: [45535545694](https://github.com/wyz541/Kshift/actions/runs/45535545694)
- Channel: `stable`
- Version/tag: `0.1.0` / `v0.1.0`
- Source commit: `d3ebc56fb10fb1f25cad710599170ef7e31ade1d`
- Overall result: **FAILED**
- Source fragment: PASS
- Server bundle/fragment: PASS, but runtime gates remain `skipped`
- macOS ad-hoc build/fragment: PASS, but install/UI gates remain `skipped`
- iOS signed build: **FAILED** at signing import
- Release/Draft created: none

iOS failure: `APPLE_TEAM_ID`, certificate/password, keychain password and provisioning-profile secrets were empty.

## Current severity evidence

| Gate | Evidence | Result |
| --- | --- | --- |
| Server LaunchAgent health/restart/logs | `server-launchd-2026-11-25.json` | PASS |
| Server outbox replay after SIGKILL | `server-launchd-2026-11-25.json` | PASS |
| PostgreSQL migration/RBAC/backup/restore | current ops/PostgreSQL test run | PASS |
| macOS ad-hoc install-copy/upgrade/rollback | `lifecycle-2026-11-25.json` | PASS, bundle-copy scope |
| iOS Simulator install/upgrade/rollback | `lifecycle-2026-11-25.json` | PASS, simulator scope |
| 30-minute 2x load | `load-2026-11-25.json` | PASS |
| iOS signed distribution | protected environment secrets | NOT RUN |
| macOS clean-host signed install lifecycle | clean host unavailable | NOT RUN |
| Stable policy approval | `release/policy.json` | BLOCKED, `pending` |

## 30-minute 2x load evidence

- Source commit: `d3ebc56fb10fb1f25cad710599170ef7e31ade1d`
- Duration: 1800.38 seconds
- Persistent network clients: 100 / 100
- Persistent event streams: 64 / 64
- Write attempts: 70,200; successes: 28,080; bounded resource exhausted: 42,120
- Silent overwrite: false
- Event gaps: 0; event stream errors: 0
- Snapshot RPC requests: 6,000; failures: 0
- RSS post-warmup growth: 74.66 MiB / 128 MiB limit
- RSS peak: 133.38 MiB / 256 MiB limit
- Result: PASS

## Server LaunchAgent evidence

- Supervisor: user LaunchAgent
- Bundle: release server bundle
- Health before/after forced restart: `SERVING`
- Restart signal: `SIGKILL`
- Runs: 2
- Pre-restart revision: 2
- Replayed revision: 2 after restart
- New revision after restart: 3
- Source tree state: clean

## Lifecycle evidence

- iOS Simulator: `iPhone 18 Pro`
- iOS install/upgrade/rollback: PASS
- macOS ad-hoc bundle-copy/upgrade/rollback: PASS
- macOS signing: `adhoc`
- Limitations from the script remain explicit: signed macOS lifecycle and iOS distribution signing are not covered.

## Remaining blockers

1. Configure iOS signing secrets in the protected GitHub environment.
2. Run the official Stable candidate again successfully.
3. Replace `skipped` server/macOS fragment gates with attested current evidence.
4. Approve and close remaining Stable policy decisions.
5. Prepare Draft, run `verify-draft`, then Promote the same Draft through the protected release environment.
6. Verify `/releases/latest/download/release-manifest.json` and the in-app update path against the promoted Stable release.
