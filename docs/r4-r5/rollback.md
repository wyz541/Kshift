---
slug: "/docs/r4-r5/rollback"
title: "回滚手册"
type: "runbook"
status: "review"
updated: "2026-11-13"
keywords:
  - 回滚
  - 数据库
  - macOS
  - iOS
description: "定义应用、服务和数据库的安全回滚步骤。"
---

# 回滚手册

结论：先判断 schema 是否兼容。schema 不兼容时，恢复备份，不替换旧二进制。

## macOS 应用回滚

1. 确认目标版本已批准。
2. 确认目标版本支持当前 schema。
3. 退出当前应用。
4. 安装目标版本。
5. 启动应用并运行健康检查。
6. 验证项目、任务、附件和历史。

## 服务二进制回滚

1. 验证目标版本目录存在。
2. 验证 schema compatibility。
3. 运行 `deploy/rollback.sh`。
4. 检查 `/Library/Logs/Kshift/server.error.log`。
5. 运行 HTTP、数据库和磁盘健康检查。

**警告：** 不要用旧二进制连接新 schema。schema 不兼容时，恢复迁移前备份。

## 数据库恢复

1. 停止写入。
2. 创建当前数据库的最后备份。
3. 校验恢复备份。
4. 恢复到唯一临时数据库。
5. 运行完整性检查。
6. 切换服务到恢复数据库。
7. 重新获取客户端 snapshot。
8. 保存恢复证据。

## iOS 回滚

1. 从内部签名分发渠道选择上一个批准版本。
2. 验证 bundle id、签名和最低系统版本。
3. 安装旧版本。
4. 重新登录并获取 snapshot。
5. 记录安装和设备证据。

## Release 回滚

1. 禁止移动 Stable 标签。
2. 禁止覆盖同名 Stable 资产。
3. 创建新的 patch 版本。
4. 在 Release notes 写明问题和回滚步骤。
5. 保留原 Stable Release。
