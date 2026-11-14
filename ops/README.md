# Kshift 运维工具

结论：`kshift-ops` 提供受限数据库管理、RBAC、备份、恢复演练、迁移和健康检查。

## 运行要求

- macOS 或 Linux。
- Python 3.9 或更新版本。
- PostgreSQL 18 客户端工具：`psql`、`pg_dump`、`pg_restore`、`createdb`、`dropdb`。
- 加密备份需要 `age`。

本地运行时设置 Python 路径。

```bash
export PYTHONPATH=ops
ops/bin/kshift-ops --version
```

## 数据库连接

工具只从环境变量读取数据库连接。禁止把数据库 URL 放入命令行参数。

| 环境变量 | 用途 |
| --- | --- |
| `KSHIFT_DATABASE_URL` | 运行时数据库连接 |
| `KSHIFT_BACKUP_DATABASE_URL` | 备份角色连接 |
| `KSHIFT_OWNER_DATABASE_URL` | 迁移所有者连接 |
| `KSHIFT_ADMIN_DATABASE_URL` | 受限管理视图连接 |
| `KSHIFT_SERVER_BIN` | `kshift-server` 二进制路径 |

连接必须使用 `postgresql://` URI。工具从 URI 提取凭据，然后通过 libpq 环境变量传递。

## 初始化和迁移

1. 使用超级用户执行 `ops/sql/bootstrap.sql`。
2. 使用密码管理器设置数据库角色密码。
3. 使用所有者连接执行 `kshift-server migrate`。
4. 执行 `ops/sql/admin_views.sql`。
5. 对所有者角色设置 `KSHIFT_OWNER_DATABASE_URL`。
6. 对运行时角色设置 `KSHIFT_DATABASE_URL`。
7. 对备份角色设置 `KSHIFT_BACKUP_DATABASE_URL`。

服务器 migration 是 schema 的权威来源。配置 `KSHIFT_SERVER_BIN` 后运行迁移包装器。

```bash
export KSHIFT_SERVER_BIN='/Library/Application Support/Kshift/current/bin/kshift-server'
export KSHIFT_OWNER_DATABASE_URL='postgresql://kshift_owner@db/kshift'
export KSHIFT_BACKUP_DATABASE_URL='postgresql://kshift_backup@db/kshift'
export KSHIFT_SOURCE_COMMIT="$(git rev-parse HEAD)"
ops/bin/kshift-ops db migrate \
  --server-bin "$KSHIFT_SERVER_BIN" \
  --backup-output "$HOME/Library/Application Support/Kshift/backups" \
  --age-recipient-file "$HOME/.config/kshift/age-recipient.txt"
```

包装器先创建加密备份。它随后调用 `kshift-server migrate` 和 `kshift-server check`。服务器启动时会校验 migration digest。

**警告：** 只有一次性测试数据可以使用 `--allow-no-backup`。此参数跳过迁移前备份。

## 备份

创建加密备份。

```bash
ops/bin/kshift-ops backup create \
  --output "$HOME/Library/Application Support/Kshift/backups" \
  --kind scheduled-4h \
  --database-url-env KSHIFT_BACKUP_DATABASE_URL \
  --age-recipient-file "$HOME/.config/kshift/age-recipient.txt" \
  --source-commit "$(git rev-parse HEAD)"
```

备份使用 `pg_dump --format=custom --no-owner --no-acl`。每个备份包含元数据文件。元数据记录 PostgreSQL 版本、schema 版本、source commit、文件大小和 SHA-256。

**警告：** 不提供 `--age-recipient-file` 时，工具拒绝创建未加密备份。`--allow-unencrypted` 只用于临时恢复演练。

查看保留计划。

```bash
ops/bin/kshift-ops backup list \
  --directory "$HOME/Library/Application Support/Kshift/backups"
```

执行保留计划。

```bash
ops/bin/kshift-ops backup prune \
  --directory "$HOME/Library/Application Support/Kshift/backups" \
  --apply --yes
```

保留数量如下。

| 类型 | 数量 |
| --- | ---: |
| `scheduled-4h` | 42 |
| `weekly` | 12 |
| `monthly` | 12 |

迁移备份、发布备份和手工备份不自动删除。

## 恢复演练

设置管理连接。管理连接需要创建和删除临时数据库的权限。

```bash
export KSHIFT_ADMIN_DATABASE_URL='postgresql://kshift_admin@db/postgres'
ops/bin/kshift-ops backup restore-drill \
  --backup path/to/backup.dump.age \
  --metadata path/to/backup.metadata.json \
  --age-identity "$HOME/.config/kshift/age-identity.txt"
```

工具执行以下动作。

1. 校验备份文件大小和 SHA-256。
2. 解密备份。
3. 恢复到一个唯一临时数据库。
4. 运行完整性检查。
5. 校验 schema 版本。
6. 删除临时数据库。
7. 写入恢复证据 JSON。

## RBAC

项目角色只有 `viewer`、`editor` 和 `admin`。

```bash
export KSHIFT_ADMIN_DATABASE_URL='postgresql://kshift_admin@db/kshift'
ops/bin/kshift-ops rbac grant \
  --project-id PROJECT_UUID \
  --user-id USER_UUID \
  --role editor
```

查看成员。

```bash
ops/bin/kshift-ops rbac list --project-id PROJECT_UUID
```

## 受限数据库管理

管理命令只访问固定视图。命令不支持任意 SQL。

```bash
ops/bin/kshift-ops admin tables
ops/bin/kshift-ops admin show --view task_overview --limit 50 --offset 0
```

## 健康检查

```bash
ops/bin/kshift-ops health \
  --server-bin "$KSHIFT_SERVER_BIN" \
  --database-url-env KSHIFT_DATABASE_URL \
  --disk-path "$HOME/Library/Application Support/Kshift" \
  --minimum-free-gib 10
```

命令输出 JSON。任一检查失败时，命令返回非零状态。

## 测试

```bash
PYTHONPATH=ops python3 -m unittest discover -s ops/tests -p 'test_*.py' -v
```

PostgreSQL 集成测试需要 `KSHIFT_TEST_ADMIN_DATABASE_URL`。

## 操作数据清理

计划清理过期命令结果和旧 outbox 事件。

```bash
ops/bin/kshift-ops db maintain --database-url-env KSHIFT_OWNER_DATABASE_URL
```

**警告：** `--apply` 删除过期行。执行前先完成备份，并阅读保留计划。

```bash
ops/bin/kshift-ops db maintain \
  --database-url-env KSHIFT_OWNER_DATABASE_URL \
  --apply --yes
```
