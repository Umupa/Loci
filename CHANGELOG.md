# Changelog

User-visible changes to the native app. The Tauri app's history is on `main`.

## Unreleased

- 课末「下一课」按钮能打开下一课了；正文里术语的别名也会标虚线、悬停看释义。
- 设置窗口新增「Agent」页：列出本机装了哪些 agent CLI、路径、版本、登录状态，可重新检测；可选新导师默认用的 agent 和模型。导师右键菜单和导师页工具栏可进入导师设置，改 agent、模型和权限（每次询问 / Full access）。
- 段落提问失败时关闭对应的 agent 会话，避免后台进程遗留。

- 评测的一手来源计分按仓库路径边界匹配，不再把相似仓库名算作一手来源。

- 同一笔记同时提出多个问题时，各条待答记录分别更新，完成一个回答不会移除另一个问题。

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
- Lessons and items open in a real reader: headings, lists, quotes, code blocks and tables, set in one column. It reopens where you stopped, keeps your place when the window is resized or the text is revised, and marks a lesson read once you reach its end.
- A mentor's page is a catalog tree that marks each lesson read, revised or not yet written, and shows what the mentor is doing while it works. Lessons the mentor revised highlight what changed since you last saw them; glossary terms are underlined where first used, with their definition on hover; at a lesson's end you can go on to the next one or ask the mentor to write it.
- Select a passage to highlight it, write a thought on it, or ask the lesson's mentor about it. Notes are kept in `notes/` files and survive restarts; the text keeps only the underline and a small mark, and the panel beside it lists the contents and every note in reading order, with answers streaming in. Notes whose passage is gone are listed as lost instead of pointing elsewhere.
- Talk with a mentor on its page: replies stream in, tool calls show what they ran and how it went, permission requests wait for your answer, and a running turn can be stopped.
- Mentor replies and answers render full Markdown with Textual; code in lessons is syntax-highlighted and formulas are typeset. Inputs, the floating next-lesson button and the panel header use macOS 26 glass.
