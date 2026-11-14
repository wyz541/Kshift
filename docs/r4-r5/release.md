---
slug: "/docs/r4-r5/release"
title: "R5 内网发布手册"
type: "runbook"
status: "review"
updated: "2026-11-13"
keywords:
  - Release
  - Draft
  - Promote
  - Manifest
description: "定义 Candidate、Draft、Promote 和 GitHub 设置。"
---

# R5 内网发布手册

结论：平台 workflow 只构建和验证。单一的 Release orchestrator 创建 Draft 并 Promote 同一个 Draft。

## 发布门禁

1. R0 的所有权、签名和分发决策必须为 `approved`。
2. 所有 fragment 必须使用同一 source commit。
3. 所有 Stable 平台必须存在。
4. 所有必需 gate 必须为 `passed`。
5. Manifest、资产、SBOM 和 evidence 必须有 SHA-256。
6. Draft 下载后的字节必须与 manifest 一致。
7. GitHub attestation 必须可验证。
8. Release manager 必须在 `release` environment 批准 Promote。

## GitHub 设置

1. 保护 `v*` 标签。
2. 只允许 release automation 和 release manager 创建标签。
3. 创建 `release` environment。
4. 为 `release` environment 设置 required reviewers。
5. 平台 workflow 使用 `contents: read`。
6. 只有 orchestrator 的 Draft/Promote job 使用 `contents: write`。
7. 开启 immutable releases。
8. 禁止移动标签或替换 Stable 资产。

## Candidate

1. 从 `main` 运行 `release-candidates.yml`。
2. 选择 `preview`、`stable` 或 `hotfix`。
3. 写出 SemVer core 版本。
4. Preview 写出正的 preview 编号。
5. Stable 必须构建 server、macOS、iOS 和 source。
6. Preview 可以关闭 macOS 或 iOS。
7. 失败时只重跑同一 workflow run 的失败 job。

## Draft

1. 运行 `release-orchestrate.yml`，操作选择 `prepare`。
2. 传入 candidate run id、source commit、版本和标签。
3. 传入实际 PostgreSQL 18 minor 版本。
4. 下载所有 fragment。
5. 生成 SBOM 和 release notes。
6. 从迁移文件计算 schema 版本和 digest。
7. 合并并通过 schema v1 合同校验。
8. 校验资产字节。
9. 创建 Draft。
10. 在 Draft 上追加 evidence 和 `SHA256SUMS`。

## Promote

1. 运行 `release-orchestrate.yml`，操作选择 `promote`。
2. workflow 下载 Draft 资产。
3. workflow 校验 `SHA256SUMS`、manifest 和 attestation。
4. release manager 批准受保护的 `release` environment。
5. workflow 只把已验证 Draft 改为非 Draft。
6. workflow 不重新构建资产。
7. workflow 不上传新资产。

## 回滚

1. Stable 发布后发现问题时，创建新的 patch 版本。
2. 禁止移动已发布标签。
3. 禁止覆盖同名 Stable 资产。
4. 数据库回滚使用迁移前备份。
5. macOS 应用回滚使用已批准版本。
6. 确认目标版本支持当前 schema。
7. schema 不兼容时恢复迁移前备份。
8. 安装旧版本 macOS 应用。
9. iOS 回滚使用上一个内部签名版本或 TestFlight build。
