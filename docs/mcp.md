---
slug: /mcp
title: Kshift MCP Server
type: reference
status: active
updated: "2026-11-26"
keywords:
  - MCP
  - Agent
  - stdio
  - 只读
  - 项目
description: 说明 Kshift MCP Server 的只读 stdio 入口、配置环境变量、工具和资源边界。
---

# Kshift MCP Server

> 结论：`kshift-mcp` 是只读 stdio MCP adapter。它通过共享 `kshift-client` 读取 Kshift server，不直接访问 PostgreSQL，也不复制 Core API 业务规则。

## 启动

```sh
export KSHIFT_ENDPOINT='https://kshift.internal:8443'
export KSHIFT_CA_PATH='/absolute/path/to/ca.pem'
export KSHIFT_TOKEN='agent-scoped-token'
cargo run -p kshift-mcp
```

可选变量：

| 变量 | 用途 |
| --- | --- |
| `KSHIFT_TLS_DOMAIN` | 覆盖 TLS server name |
| `KSHIFT_MCP_DEADLINE_SECS` | 单次读取 deadline，默认 10 秒 |

## 工具

首版只读工具：

- `list_projects`
- `get_project_overview`
- `search_tasks`
- `get_task`
- `get_mind_map`

`get_mind_map` 使用任务父子关系和依赖关系生成只读导图投影。写入工具不注册；调用 `create_task`、`update_task` 等名称会返回 `read_only` 错误。

## 资源

- `kshift://projects`
- `kshift://project/{project_id}/snapshot`
- `kshift://project/{project_id}/mind-map`

资源读取返回紧凑 JSON，不返回完整项目 snapshot。

## 安全边界

- 认证 token 由 `kshift-client` 发送，不写入日志。
- 项目授权由 server 执行；MCP 不信任 shell 传入的 actor 或 role。
- 工具结果有列表、搜索和节点上限。
- 不直连 PostgreSQL，不暴露原始堆栈，不注册写工具。
