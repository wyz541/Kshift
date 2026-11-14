---
slug: /docs/r1-acceptance
title: Kshift R1 acceptance evidence
type: evidence
status: verified
updated: "2026-11-14"
keywords:
  - acceptance
  - integration test
  - PostgreSQL 18
  - migration digest
  - recovery drill
description: 记录 Issue #4 的质量门禁、migration digest 和恢复演练结果。
---


# Kshift R1 acceptance evidence

结论：Issue #4 的本地验收门禁已通过。PostgreSQL 版本为 18.6。

## 命令结果

| 检查 | 结果 |
| --- | --- |
| `cargo fmt --all -- --check` | 通过 |
| `buf format -d` | 通过 |
| `buf lint` | 通过 |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings` | 通过 |
| 单元测试 | 8 个通过 |
| PostgreSQL 集成测试 | 9 个通过 |
| `kshift-server check` | `healthy=true` |
| GitHub Actions `R1 service` | 通过 |

集成测试覆盖以下验收项。

- Admin 和 project member 的项目隔离。
- 未授权项目不进入 `ListProjects` 和 snapshot。
- 并发写入只有一个成功。
- 过期 revision 返回 `ABORTED` 和 typed conflict detail。
- 幂等重放不增加 revision、audit、command result 或 outbox。
- 事务失败不留下业务数据或 outbox。
- task planning fields、assignees、tags、parent 和 dependency 往返成功。
- outbox 连续回放成功。
- retention gap 返回 `ResetRequired`。
- 日志不包含 token、数据库 URL 或完整 command body。
- 标准 gRPC health 返回 `SERVING`。
- graceful shutdown 在 5 秒内完成。
- migration digest mismatch 阻止 startup check。

## Migration evidence

R3 adds `0002_plan_depth.sql`。当前 schema version 为 `3`，migration count 为 `2`。
以下 digest 保留为 R3 之前的 R1 历史证据。

```text
schema_version=2
migration_count=1
migration_digest=aeb741b70beef004eb4d8a5db3d183466a042cf40d91b1e6118d3b8f643b8e49
postgres_version=18.6 (Homebrew)
postgres_version_num=180006
```

## Recovery evidence

命令：

```sh
KSHIFT_DATABASE_URL='postgres://wyz@127.0.0.1:54329/kshift_test' \
  ./scripts/recovery-test.sh
```

输出：

```text
rollback=verified
restore=verified
projects=1
migration_digest=aeb741b70beef004eb4d8a5db3d183466a042cf40d91b1e6118d3b8f643b8e49
```

脚本执行以下步骤。

1. 创建临时 source database。
2. 执行 migration。
3. 创建 `pg_dump --format=custom --no-owner --no-acl` 备份。
4. 执行故意失败的 migration transaction。
5. 验证失败 transaction 没有留下 partial table。
6. 恢复到临时 database。
7. 验证 project count 和 migration digest 一致。

## 未覆盖范围

- SwiftUI、Rust client 和 FFI 不在 Issue #4 范围。
- PostgreSQL 高可用集群不在 Issue #4 范围。
- `launchd` 安装和日志轮转不在 Issue #4 范围。
