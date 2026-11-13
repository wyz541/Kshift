# Kshift 服务部署

结论：安装脚本把每个版本放入独立目录。脚本用 `launchd` 启动服务。备份、健康和日志轮转由独立任务运行。

## 路径

| 类型 | 路径 |
| --- | --- |
| 安装根目录 | `/Library/Application Support/Kshift` |
| 版本目录 | `/Library/Application Support/Kshift/versions/<version>` |
| 当前版本 | `/Library/Application Support/Kshift/current` |
| 环境文件 | `/Library/Application Support/Kshift/etc/kshift.env` |
| 备份目录 | `/Library/Application Support/Kshift/backups` |
| 日志目录 | `/Library/Logs/Kshift` |
| LaunchDaemon | `/Library/LaunchDaemons/com.wyz541.kshift.*.plist` |

## 安装前检查

1. 创建专用服务用户 `_kshift`。服务用户的主组使用 `staff`。
2. 把数据库 URL 写入只允许 root 和服务用户读取的环境文件。
3. 准备 `age` 公共密钥文件。
4. 使用 `kshift-ops db migrate` 创建迁移前备份。
5. 确认 schema 版本与发布 manifest 一致。
6. 确认服务二进制带 `bin/kshift-server` 和 `bin/kshift-ops`。

环境文件格式如下。数据库密码只在受限文件中保存。

```bash
KSHIFT_DATABASE_URL='postgresql://kshift_app@db/kshift'
KSHIFT_BACKUP_DATABASE_URL='postgresql://kshift_backup@db/kshift'
KSHIFT_AUTH_FILE='/secure/path/kshift-auth.json'
KSHIFT_TLS_CERT_PATH='/secure/path/server.crt'
KSHIFT_TLS_KEY_PATH='/secure/path/server.key'
```

## 安装

```bash
sudo deploy/install.sh \
  --bundle dist/kshift-0.1.0-server-macos-arm64 \
  --service-user _kshift \
  --env-file /secure/path/kshift.env \
  --version 0.1.0 \
  --source-commit "$(git rev-parse HEAD)" \
  --age-recipient-file /secure/path/age-recipient.txt
```

安装脚本执行以下动作。

1. 检查参数和文件权限。
2. 复制版本文件。
3. 原子切换 `current` 符号链接。
4. 渲染并校验 LaunchDaemon plist。
5. 安装 `newsyslog` 配置。
6. 启动服务和定时任务。
7. 执行 HTTP、数据库和磁盘健康检查。

## 卸载

**警告：** 卸载会停止服务。默认保留数据库、备份和日志。

```bash
sudo deploy/uninstall.sh --confirm
```

**警告：** `--purge-data` 永久删除安装目录和日志。执行前先验证备份和恢复。

```bash
sudo deploy/uninstall.sh --confirm --purge-data
```

## 版本回滚

**警告：** 只有新旧版本使用兼容 schema 时，才能原地回滚应用二进制。

```bash
sudo deploy/rollback.sh --version 0.0.9 --allow-schema-compatibility
```

schema 不兼容时，恢复迁移前备份。不要只替换二进制。
