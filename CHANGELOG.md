# Changelog

User-visible changes to the native app. The Tauri app's history is on `main`.

## Unreleased

- 新增 Grok（ACP）驱动，支持流式回复、工具调用、权限询问、中断和会话恢复；其余 ACP 系 agent 只需提供启动参数。
- 新建的导师会立刻开始工作：先写目录，再写第一课；目录里未写的课可以请导师写。
- 和导师对话：回复流式出现，可以停止、回答权限询问；对话记录只追加，重开应用后都在。
- 对一段话提问：问题和定位符一起发给导师，回答流式出现，完成后存进这条笔记。
- 新增 LociEval：经命令层在 Pi 上建导师、等第一课、计时并按 0.11 的评分表打分。
- 停止对话统一在 30 秒内返回；Claude Code 拒绝未知控制请求后继续对话，ACP 自动批准优先只允许一次。

- 新增 Antigravity 原生会话驱动，复用本机 ACP 服务端，支持工具审批、停止和恢复对话。
- Cursor 的 ACP 驱动支持流式回复、工具调用、权限回答、中断和恢复会话。
- 增加 Hermes ACP 驱动，支持模型与权限设置、流式对话、工具审批、中断和会话恢复。
- OpenCode 驱动支持流式回复、工具调用、权限询问、中断和恢复会话。
- omp 接入共享的 Pi RPC 驱动，支持流式回复、工具调用、权限询问、中断和恢复会话。
- 新增 Claude Code 驱动，支持流式回复、工具调用、权限询问、中断和恢复会话。
- 原生版接入 Codex app-server，支持流式回复、工具调用、权限询问、停止与会话恢复。

- The native app opens to a start page: type a sentence to make a mentor, or drop a text file to add it to the library; browse mentors, lessons and items, with each lesson's sources and each item's citing lessons beside them. Warm-night look in light and dark, English and Chinese.
