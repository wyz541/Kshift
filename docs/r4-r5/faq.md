---
slug: "/docs/r4-r5/faq"
title: "R4/R5 FAQ"
type: "reference"
status: "review"
updated: "2026-11-13"
keywords:
  - 运维
  - 发布
  - 备份
  - RBAC
description: "回答 R4/R5 基座的常见使用和安全问题。"
---

# R4/R5 FAQ

## 为什么工具拒绝创建未加密备份？

Stable 备份必须离开开发机。未加密备份可能暴露任务、人员、附件元数据和审计记录。`--allow-unencrypted` 只用于一次性恢复演练。

## 数据库密码放在哪里？

数据库密码只放在 macOS Keychain 或 root 管理的受限环境文件中。密码不得进入仓库、命令行、日志、Release 资产或备份元数据。

## 为什么 Stable 现在是关闭的？

`release/policy.json` 的 `decision_status` 是 `pending`。macOS 和 iOS 的分发方式、签名身份和审批人尚未决定。Stable 合并器会拒绝生成 `stable-ready` manifest。

## 怎样给项目添加成员？

使用 `kshift-ops rbac grant`。项目角色只有 `viewer`、`editor` 和 `admin`。服务端必须继续执行最终鉴权。

## 为什么管理界面不能执行任意 SQL？

任意 SQL 会绕过最小权限、数据脱敏和审计边界。管理命令只允许固定视图和分页参数。

## 恢复后客户端为什么要求刷新？

恢复后的数据库 revision 可能落后或跳变。客户端必须丢弃旧 snapshot，重新获取完整 snapshot。

## 发布失败后是否重新构建全部平台？

不重新构建。只重跑失败平台的同一个 candidate context。所有成功 fragment 必须继续使用同一 source commit。

## 是否可以覆盖已发布资产？

禁止。发现问题时发布新的 patch 版本。Stable 标签和资产保持不可变。

## 日志轮转在哪里配置？

配置位于 `ops/newsyslog/com.wyz541.kshift.conf`，安装到 `/etc/newsyslog.d/com.wyz541.kshift.conf`。
