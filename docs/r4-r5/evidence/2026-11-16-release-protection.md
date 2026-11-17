---
slug: "/docs/r4-r5/evidence/2026-11-16-release-protection"
title: "R4/R5 release protection evidence"
type: "evidence"
status: "review"
updated: "2026-11-16"
keywords:
  - release environment
  - tag protection
  - immutable releases
  - release governance
  - GitHub settings
description: "记录 release environment reviewer、main branch policy、版本标签保护和 immutable releases 配置。"
---

# R4/R5 release protection evidence

结论：`release` environment 已有 required reviewer。Deployment 只允许 `main`。Active ruleset 阻止 `v*` tag update 和 deletion。Immutable releases 已启用。

## Release Environment

| 项目 | 值 |
| --- | --- |
| Environment ID | `27471742908` |
| Name | `release` |
| Required reviewer | `@wyz541` |
| Prevent self review | `false` |
| Admin bypass | `true` |
| Deployment branch policy | `main` only |
| Branch policy ID | `66969019` |

## Tag Ruleset

| 项目 | 值 |
| --- | --- |
| Ruleset ID | `27386079` |
| Name | `Protect version tags` |
| Target | `tag` |
| Enforcement | `active` |
| Included refs | `refs/tags/v*` |
| Rules | `deletion`, `update` |
| Bypass actors | Empty |
| Current user bypass | `never` |

## Protection Test

| Step | Result |
| --- | --- |
| Create temporary `v0.1.0-protection-test` tag | Passed |
| Update protected tag | Rejected with HTTP `422` and `Cannot update this protected ref.` |
| Delete protected tag | Rejected with HTTP `422` and `Cannot delete this tag` |
| Temporarily disable ruleset for cleanup | Passed |
| Delete temporary tag | Passed |
| Restore active ruleset | Passed |
| Read temporary tag after cleanup | HTTP `404` |

## Immutable Releases

```json
{"enabled":true,"enforced_by_owner":false}
```

Published Release assets cannot be replaced after immutable release protection is effective. Draft assets and future releases follow GitHub immutable-release behavior.

## Limitations

- `prevent_self_review` is `false`. A user who can trigger deployment can also approve it.
- Repository admins can bypass the environment protection rule.
- The Active Spec requires a release manager approval. The current configuration provides a required reviewer but does not enforce separation of duties.
- Stable asset overwrite remains blocked by workflow checks and immutable releases. This test did not upload a Stable asset with an existing name.

原始 summary 保存在 [2026-11-16-release-protection.json](2026-11-16-release-protection.json)。
