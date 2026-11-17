# Claude Code 协议录音

2026-11-17 使用 Claude Code 2.1.326 实录。`ClaudeCodeLiveTests` 与 `ClaudeCodeReplayTests` 共用场景，真实测试默认跳过。

```sh
. script/toolchain
LOCI_CLAUDE_CODE="$(command -v claude)" \
LOCI_CLAUDE_CODE_RECORD="$PWD/Tests/LociAgentsTests/Fixtures/ClaudeCode" \
swift test --filter ClaudeCodeLiveTests
```

测试读取用户的 API 配置，禁用 hooks、隔离 MCP，使用临时工作目录。每个进程最多四轮、预算上限 0.50 美元。录音把工作目录和用户目录替换成占位符，并删去初始化响应中的账号、命令列表等无关元数据，保留协议结构与回合输出。

- `reply`、`tool`、`allow`、`deny`、`interrupt`、`interrupt-asking`、`resume`、`missing`：真实 CLI 输出。
- `auth-error`：未读取用户连接配置时真实返回的认证失败，验证 `subtype: success` 且 `is_error: true` 仍然以失败结束。
- `synthetic-died`、`synthetic-silent`：手写的故障场景，覆盖进程退出与初始化超时。

`interrupt` 等收到 `tool_progress` 后才中断 Python 的 60 秒等待；同一会话随后再次回答 `pong`。
