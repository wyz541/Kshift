---
slug: "/docs/r4-r5/operations"
title: "R4 运维手册"
type: "runbook"
status: "review"
updated: "2026-11-13"
keywords:
  - 备份
  - 恢复
  - 迁移
  - 日志
description: "定义备份、恢复、迁移、角色和启动恢复步骤。"
---

# R4 运维手册

结论：先验证备份，再执行迁移或恢复。任何失败都保留原始证据。

## 角色

| 角色 | 权限 |
| --- | --- |
| `kshift_owner` | schema 和迁移 |
| `kshift_app` | 应用 DML；server 执行项目授权 |
| `kshift_backup` | 只读备份，允许读取全部备份数据 |
| `kshift_admin` | 只读管理视图和项目成员维护 |

## 备份周期

| 类型 | 时间 | 保留 |
| --- | --- | ---: |
| 四小时备份 | 每 4 小时 | 42 个 |
| 周备份 | 每周日 02:00 | 12 个 |
| 月备份 | 每月 1 日 03:00 | 12 个 |
| 迁移备份 | 每次迁移前 | 不自动删除 |
| 发布备份 | 每次 Stable 发布前 | 不自动删除 |

## 恢复演练

1. 选择备份和对应元数据。
2. 校验文件大小和 SHA-256。
3. 解密到临时文件。
4. 恢复临时数据库。
5. 运行 `ops/sql/verify_integrity.sql`。
6. 校验 schema 版本。
7. 保存恢复证据。
8. 删除临时数据库。

**警告：** 恢复演练需要使用唯一数据库名。禁止把备份恢复到生产数据库。

## 服务启动恢复

`launchd` 保持服务运行。服务异常退出时，任务在 10 秒后重启。

1. 查看 `/Library/Logs/Kshift/server.error.log`。
2. 执行 `kshift-ops health --server-bin ...`。
3. 检查数据库连接和 schema digest。
4. 检查磁盘剩余空间。
5. 修复原因后执行 `launchctl kickstart -k system/com.wyz541.kshift.server`。

## 日志轮转

`newsyslog` 配置保留 14 个日志文件。单个日志达到 10 MiB 时轮转。日志只保存结构化事件，不保存 token、密码或完整敏感请求体。

## 事件流恢复

1. 客户端保存当前 revision。
2. 客户端重新连接 `WatchProjectChanges`。
3. 服务端从 outbox 回放事件。
4. revision 不连续时返回 `ResetRequired`。
5. 客户端清除项目缓存并获取新 snapshot。

Outbox 保留 7 天。更旧客户端必须获取 snapshot。
