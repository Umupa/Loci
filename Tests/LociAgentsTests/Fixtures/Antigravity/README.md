# Antigravity 协议录音

`reply.jsonl` 于 2026-11-17 对本机官方 `agy_acp_server.par` 录制，`initialize` 返回 `antigravity-acp` 1.3.0。不是交互式 `agy`（本机版本 1.5.3）。

- macOS 启动参数为空，进程工作目录为 `.par` 所在目录；`session/new.cwd` 是独立临时目录，未使用 `~/Loci`。
- 按 Pi 的录音格式保存 `launch`、`to`、`from`、`close`、`exit`，保留实际 JSON-RPC 消息顺序。
- 本机目录替换为 `$FOLDER`，服务端生成的会话 ID 替换为 `recorded-antigravity-session`。含账户信息的标准错误日志全部移除，未改写协议响应和模型名称。
- 输入关闭后等待三秒，进程仍未退出，发送 SIGTERM，实际退出码为 `-15`。
- 已录到握手、创建会话、权限模式设置、单个 `pong` 文本块、上下文用量、`end_turn`。本录音不证明多块流式、工具调用、权限询问、中断或恢复。

共用 ACP/Grok 尚未进入 `herdr/a2-core`，本录音暂未接入 Swift 回放测试。接入计划和验证结果在任务目录的 `report.md`；本次没有另写 ACP 实现。
