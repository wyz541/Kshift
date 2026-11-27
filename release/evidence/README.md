# Stable runtime evidence

结论：Stable 的 server 和 macOS gate 只读取本目录中的机器可读证据，不接受 YAML 中手工写入的 `passed`。

| 文件 | 生成入口 | 目标 |
| --- | --- | --- |
| `server-runtime.json` | `./scripts/run-server-release-gates.sh` | PostgreSQL 18、迁移、备份恢复、LaunchAgent 恢复、日志 |
| `macos-runtime.json` | `./scripts/run-macos-release-gates.sh` | Stable 制品生命周期、Liquid Glass、无障碍、性能 |

证据必须记录 clean source commit、`kshift-runtime-inputs-v1` 输入摘要、主机信息、实际制品摘要和逐 gate 观测。生成后运行 `release/tools/runtime-evidence.mjs verify`，通过后再提交。

证据文件禁止包含密码、token、私钥、数据库 URL、本机绝对路径或未脱敏用户数据。
