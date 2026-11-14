---
slug: "/docs/r4-r5/evidence/2026-11-14-launchd-restart"
title: "R4/R5 launchd restart evidence"
type: "evidence"
status: "review"
updated: "2026-11-14"
keywords:
  - launchd
  - restart
  - supervisor
  - macOS
description: "记录临时 LaunchAgent 在进程终止后由 launchd 自动重启的测试。"
---

# R4/R5 launchd restart evidence

结论：launchd 能自动重启临时 LaunchAgent 进程。

| 检查 | 结果 |
| --- | --- |
| LaunchAgent plist 校验 | 通过 |
| 首次启动 | 通过 |
| `SIGTERM` 终止 | 通过 |
| 自动重启 | 通过 |
| 启动次数 | 2 |
| 旧进程 PID | 已变化 |

## 命令

```bash
./scripts/test-launchd-restart.sh
```

## 覆盖边界

- 测试进程是临时 shell 探针，不是 Kshift server。
- Kshift server 在真实 LaunchDaemon 下的进程级重启仍未运行。
- 生产 LaunchDaemon 需要 root 和独立服务用户。
