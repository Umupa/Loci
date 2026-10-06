# Loci 实施与验收状态

当前状态：应用已在本机 macOS arm64 启动，正在完成实机验收。本文件记录已经得到的证据，不表示全部验收完成。

## 范围与批准

用户已确认在 macOS 开发和验收；保留 ACP 通用协议核心，其余抽取清单建议接受。当前内置 provider 为 Claude Code 和 Codex，未恢复其它八家 provider，也没有新增自定义 ACP 配置页。

已经带入窗口外壳、项目文件夹、聊天、标签、拖拽分栏、模型与权限选择、提问表单、任务与原生计划显示、会话搜索、设置、笔记、通知、手动提醒、Skills/MCP、SQLite 会话/笔记/布局，以及 `/operator` 的 11 个通用 app 动作。组合根拆为 workspace、runtime、submission、commands 和 control 等具体职责。

已经移除源代码管理、工作树、代码编辑器、文件树、应用终端、收件箱及五类平台集成、应用级多 agent 编排、自动化、远程 host/SSH、快速输入、文件检查点、游戏、求 star、上游服务与更新器。仅供这些能力使用的 Rust 命令、模型字段、依赖、菜单、快捷键和测试随之移除。

实施时额外核对并删除了上游未接线的窗口搬运辅助、游戏气泡、文件-only 布局兜底和无消费者的技能预热；普通新建窗口仍保留。原生计划卡沿用现有 Markdown 渲染完整正文，移除了 Open/Build 和应用代码实施模式。

## 环境与自动检查

- macOS 26.5.1，arm64；Node 24.19.0，npm 11.17.0。
- Rust/Cargo 1.97.1、rustfmt、Clippy 和 Xcode 命令行工具已经安装；没有安装系统包。
- Claude Code 2.1.290 的登录检查仍显示未登录；Codex 0.160.1 已登录。
- 保留依赖沿原锁文件版本；npm 保留包版本比对无升级，Rust 锁图只删除无用包并改应用包名。
- `npm run check` 已完整通过：213 个前端测试文件、2394 项测试；`tsc --noEmit`、`cargo fmt --check`、Clippy `-D warnings`、170 项 Rust 测试通过。
- `npm run build` 已通过。
- `npm run tauri dev -- --no-watch` 已实际启动；主窗口有正常内容。

自动测试日志位于本机 `/tmp/loci-check.log`，生产构建日志位于 `/tmp/loci-build.log`。Live 命名的协议测试是 mock 回归，不作为真实对话证据。

## 已实际操作

独立验收文件夹为 `/private/tmp/loci-acceptance.woLh6O`。没有修改已有项目的业务文件。

1. 打开 Loci 窗口，使用原生文件夹选择器选择验收目录；标题与项目栏正确显示目录。
2. 打开模型菜单，看到且只看到 Claude Code、Codex 两个 provider；Codex 的真实 CLI 模型目录加载成功。
3. 选择 GPT-6.1-Sol，发送标记 `LOCI-CODEX-20261006-A`。UI 出现工作状态和真实回答；回答正确给出验收目录。
4. Codex 执行一次创建文件工具调用，SQLite 记录中有 `approval.decided = allow`，验收目录中的 `permission-proof.txt` 内容为约定标记。另一次独立请求已在 UI 观察到 Waiting for approval / Allow / Deny，点击单次 Allow 后工具完成；permission-proof-2.txt 已生成。
5. 初次实机检查发现的失效 Go to File 按钮已完整移除；会话输入框、模型选择、Supervised 权限模式、侧栏转录和工具结果正常显示。
6. 确认实际数据库位于 `~/Library/Application Support/com.loci.desktop/loci.db`；表仅有 sessions、notes、session_reminders、in_flight_sessions、workspace_snapshot 和 schema_migrations，没有已删除功能的数据表。

## 尚未完成的实机验收

正在继续验证：单次权限批准的完整操作、可观察的流式增量、重启后续聊、operator 的全部通用动作、权限拒绝、提问表单、任务/计划事件、拖拽分栏与比例恢复、搜索、笔记 CRUD/图片/@note、设置持久化、通知送达/点击/静音/提醒、本地多窗口。

Claude 的真实对话、权限与重启续聊尚未验证，原因是当前登录状态未就绪。ACP 真实服务会话没有验证，当前只有通用协议回归；没有安装或恢复其它 provider。Linux/Windows 没有实机验证，本次最终运行目标已由用户改为 macOS。

## 留给用户决定的事项

上游启动恢复早期的退出分支 `persistBootingResume` 会忽略写盘失败，导致这个短窗口期的退出可能仍被报告为成功。正常挂载后的退出路径保留严格写盘失败保护，并有测试。此问题在来源实现中已经存在，按“不顺手改进”的约束保留，建议单独决定是否修复。

依赖安装报告了原锁定依赖的 npm audit 提示；本任务没有运行 audit fix 或升级依赖，后续可单独处理依赖维护。

最终提交、残留审计和剩余操作结果会继续更新到本文件。
