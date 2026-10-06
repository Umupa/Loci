# Loci 实施与验收状态

**实现已组装并可运行；验收尚未全部完成。** 当前外部阻塞是 Claude Code 未登录，以及后半段原生 UI 自动化连接失效。本文件没有把未验证项算作通过。

## 范围与批准

用户确认在 macOS 开发和验收，保留 ACP 通用协议核心，其余抽取清单建议接受。内置 provider 为 Claude Code 和 Codex；没有恢复其它八家 provider，也没有新增自定义 ACP 配置页。

已带入窗口外壳、项目文件夹、聊天、标签、拖拽分栏、模型与权限选择、提问表单、任务与原生计划显示、会话搜索、设置、笔记、通知、手动提醒、Skills/MCP、SQLite 会话/笔记/布局，以及 `/operator` 的 11 个通用 app 动作。组合根拆为 workspace、runtime、submission、commands、control 等具体职责。

已移除源代码管理、工作树、代码编辑器、文件树、应用终端、收件箱及五类平台集成、应用级多 agent 编排、自动化、远程 host/SSH、快速输入、文件检查点、游戏、求 star、上游服务与更新器。对应 Rust 命令、模型字段、依赖、菜单、快捷键和专属测试一并移除。

通用菜单、文件图标、Markdown 渲染、只读工具预览和笔记 mention 从被删目录迁到实际保留的 shared/notes/sessions 目录。没有留下功能空壳。计划卡使用原有 Markdown 渲染完整正文，移除 Open/Build 及应用代码实施模式。

实施核对还删除了上游未接线的窗口搬运辅助、游戏气泡、文件-only 布局兜底和无消费者的原生技能预热。普通新建窗口保留。具体源目录和入出依赖见 extraction.md。

## 环境与自动检查

| 项目 | 结果 |
| --- | --- |
| 验收系统 | macOS 26.5.1，arm64 |
| Node/npm | 24.19.0 / 11.17.0 |
| Rust/Cargo | 1.97.1；rustfmt、Clippy、Xcode 命令行工具已存在 |
| 系统包 | 没有安装系统包 |
| CLI | Claude Code 2.1.290 未登录；Codex 0.160.1 已登录 |
| 依赖 | 保留项与上游锁文件版本一致，未升级；Rust 删除无用依赖包 |
| `npm run check` | 完整通过：213 个 Vitest 文件、2394 项测试、TypeScript、Rust fmt、Clippy `-D warnings`、170 项 Rust 测试 |
| `npm run build` | 通过，实际 Vite 生产包生成成功 |
| Tauri 启动 | `npm run tauri dev -- --no-watch` 实际启动并正常显示窗口；默认 `npm run tauri dev` 使用同一入口 |

本机自动检查与构建日志为 `/tmp/loci-check.log`、`/tmp/loci-build.log`。Live 命名的协议测试使用 mock，未用它们替代真实对话验收。

## 实际操作与证据

验收使用独立文件夹 `/private/tmp/loci-acceptance.woLh6O`。没有修改已有项目业务文件或来源应用的数据。

| 功能 | 实际操作及结果 |
| --- | --- |
| 窗口/项目 | 启动真实 Tauri 窗口，用原生文件夹选择器打开验收目录；项目栏、最近项目、标题正确，普通文件夹无需版本库 |
| provider/模型 | 打开模型目录，仅有 Claude Code、Codex；真实 Codex CLI 目录加载，选 GPT-6.1-Sol |
| Codex 对话 | 发送标记 `LOCI-CODEX-20261006-A`，得到真实回答和当前工作目录 |
| 流式渲染 | 逐行输出测试中，同一回答在 Working/Stop 状态从第 42 条增长到第 71 条，随后完成 150 条 |
| 工具批准 | 观察 Waiting for approval / Allow / Deny，点击单次 Allow；`permission-proof-2.txt` 成功写入约定标记。首次独立工具调用也产生正确的 `permission-proof.txt` |
| 工具拒绝 | 点击 Deny，agent 明确停止；`permission-denied.txt` 不存在，没有换工具或重试 |
| operator | 真实执行 models.list、sessions.list/read/start/send/draft、folders.list/move、notes.list/read/write，均返回 `ok:true`；另一会话实际分别回复 OPERATOR-SEED、OPERATOR-FOLLOWUP 后保存草稿 |
| 分栏/标签 | operator 创建右侧未发送草稿 B，界面实际显示；拖动分隔线，SQLite 比例从 0.5/0.5 变为约 0.401/0.599；拖动面板并增加下方 pane，最终保存三叶上下布局；多标签、草稿和会话文件夹正确显示 |
| 会话搜索 | 用 Cmd+K 搜唯一消息标记，得到会话消息命中并用 Return 返回该会话；没有文件搜索范围 |
| 笔记 | 新建、改标题、编辑 Markdown、加标签、预览；Add to chat 创建独立的新会话并带入笔记。operator 另外创建并读回 Operator QA 笔记 |
| 设置 | 实际切换 Light 主题、Blue 强调色、Tab animations、Notifications；重启后相同值仍在。设置中没有已删除功能入口 |
| 静音 | 在验收项目设置静音 1 小时，显示具体截止时间，再点击 Resume notifications 恢复 |
| Skills | 从 UI 在验收项目创建 `.agents/skills/loci-qa/SKILL.md`，目录发现成功；筛选、关闭/打开目录包含开关及 Markdown 预览正常。未修改已有个人技能 |
| MCP | 只读打开实际配置列表，显示 Claude Code/Codex 的用户配置；没有改动既有连接或凭据 |
| 重启恢复 | 通过 Cmd+Q 真正退出，再启动。SQLite 的 tabs/layout、activeTabId、projectCwd 与退出前完全一致，草稿和两条笔记仍在；Codex 保持同一 provider thread，并正确回答最初标记 |
| 数据隔离 | 实际数据库为 `~/Library/Application Support/com.loci.desktop/loci.db`；仅有 sessions、notes、session_reminders、in_flight_sessions、workspace_snapshot、schema_migrations。没有旧目录导入/fallback，也没有访问旧 host 目录 |

Codex 验收会话 ID 为 `c7cca634-1893-4565-add3-7c437ccb4887`，provider thread 为 `01a10f96-53ec-7b51-9de3-4bbabd530ed4`。重启后两者保持不变，续聊没有从本地文件取标记。

## 未完成的验收与原因

| 项目 | 原因 / 当前结论 |
| --- | --- |
| Claude 成功对话、流式、权限、重启续聊 | 已实际发消息，返回 `Not logged in · Please run /login`；`claude auth status` 同样未登录。需要用户完成登录后继续 |
| agent 提问表单、原生任务/计划事件 | 本机当前 Codex 会话明确报告没有 update_plan，request_user_input 仅限 Plan 模式；未产生相应原生事件。Claude 未登录。协议/UI 回归保留且通过，实机不算通过 |
| ACP 真实服务会话 | 保留通用 client/router 和协议测试；本次没有恢复或配置其它 ACP provider，未连接真实 ACP 服务 |
| 系统通知横幅、点击返回与到期提醒 | 已验证开关、持久化、项目静音和通知代码测试；没有取得系统横幅、点击与到期提醒的完整实机证据 |
| 原生图片/附件流程、笔记删除及剩余快捷键/多窗口操作 | 后半段原生自动化连续报 `Sky Computer Use native pipe startup failed`，重新绑定与重置后仍失败；不能继续操作，未以模拟操作代替 |
| Skills/MCP 的所有外部服务行为 | 只验证发现与保留 UI；没有为验收改用户连接、安装服务或执行既有个人技能 |
| Linux/Windows | 没有实机验证；最终运行目标已由用户改为 macOS |

## 残留审计

- 受跟踪文件旧品牌全文及文件名扫描，除 LICENSE/NOTICE 外没有命中。
- 生产源码扫描已删除功能名/目录/导入，无工作树、编排、检查点、快输、收件箱或平台集成残留。
- manifest/capability 没有 updater/process、PTY/vendor、xterm、CodeMirror 或更新签名/发布配置。
- 287 个生产 TypeScript 模块均能从主入口沿 import/export/dynamic Worker 路径到达，没有孤立功能目录。
- ACP 的 `_meta.cursor/grok/fx` 等仍是保留的协议元字段，不代表带回对应 adapter 或 UI；聊天中 shell/file/diff 工具展示也不是应用终端/代码编辑器。
- 来源仓库工作区保持干净；保留依赖版本没有升级。
- Tauri 生成的 schema 已从版本控制移出，并纳入忽略规则；本地构建仍正常生成它们。

## 提交与剩余决定

首个可运行提交为 `29e98a3`：`feat: assemble Loci desktop shell and local agent core`。为保证显示的入口都已接通，原计划 P1–P3 在此提交中贯通；验收记录及生成文件清理另作提交，每次提交前仍检查与构建。

保留待用户决定的上游问题：启动恢复早期的 `persistBootingResume` 会忽略写盘失败。正常挂载后的退出严格失败保护保留且有测试；未顺手修改这一来源行为。原锁定依赖的 npm audit 提示也未通过升级处理。

下一步需要 Claude 登录和可用的原生自动化连接，补齐上述实机项。当前不能宣称所有“完成时应该是什么样”的验收要求已达成。
