# Loci 抽取清单与实施计划

状态：**已批准并开始实施。2026-10-06 用户确认在当前 macOS 验收，保留 ACP 支持多种 harness，其余清单建议接受。**

实施补充：逐调用方核对发现上游跨窗口标签搬运仅有未调用的预留 helper；按“不留死代码”删除 transfer 前后端和专属测试，普通新建窗口与退出布局恢复照常保留。

批准后的覆盖规则：下表原建议中删除 ACP 的部分作废；保留 ACP 通用协议、原生子 agent 路由及其测试。当前原始“两家内置 provider”范围未自动扩大；已单独确认是否需要恢复具体 ACP provider，相关实现先保留通用能力，不擅自新增配置 UI。Linux 环境说明仅保留为本次审计记录，不作为交付验收目标。

本文只依据本机上游源码、随仓库提供的说明和当前环境的只读检查编写。上游基线为 `98da85ae7c2b44c2f2427c17b381433ef4f23ea9`，版本 `0.7.1`，工作区干净。下文的源文件路径均相对上游仓库；来源名称、URL 和版权将在实施时集中记录于 `NOTICE`、`LICENSE`，避免其它受跟踪文件留下旧产品名。

## 1. 交付边界

交付一个名为 **Loci** 的 Tauri 2 桌面应用，保留项目即文件夹的模型、窗口外壳、标题栏、侧边栏、标签页、拖拽分栏，以及本地 Claude Code / Codex 聊天、设置、笔记、通知、会话搜索、SQLite 存储和 `/operator` 本地应用控制。

明确删除：源代码管理、git 操作、工作树、文件树、代码编辑器、终端、收件箱及其外部平台集成、应用级多 agent 编排、自动化、远程会话及独立 host、快速输入窗口、检查点、彩蛋游戏、求 star 和上游应用更新/下载/发布接入。相应 Rust 命令、类型、数据表、依赖、菜单、快捷键、样式和测试一起删除。

不增加其它产品功能、扩展接口、空目录或占位窗格；不升级依赖、不更换库、不重新设计保留区域。图标替换成中性的本地几何占位图标。删除功能对应的控件、区域和游戏背景会消失，其余保留区域沿用原样式与动效。

采用**按清单逐文件重新组装**的方式，不先整体复制仓库再删除。除组合根重写、混合文件裁剪、改名及第 3 节明确列出的通用叶子迁移外，保持目录结构和保留实现，便于以后对照基线修复。

## 2. 初次清单阶段的环境检查记录

检查日期：2026-10-06。未安装包，未启动上游应用，未访问其用户数据目录，未发送真实 agent 消息。

| 项目 | 当前会话实测 | 对验收的影响 |
| --- | --- | --- |
| 系统与架构 | macOS 26.5.1 / Darwin 25.5.0，arm64 | 不是需求描述的 Arch Linux / Hyprland / Wayland。不能用 macOS 启动结果冒充 Linux 验收 |
| 目标仓库 | 当前目录 `Luci`，分支 `main`，无提交、无应用文件 | 与描述的 `master` 不一致；建议保留现有分支，产品各处仍命名 Loci，不擅自移动目录 |
| Node / npm | 24.19.0 / 11.17.0 | 满足上游 README 的 Node 20+ 要求 |
| Rust / Cargo | Homebrew rustc 1.97.1 / cargo 1.97.1 | 已安装；不是“没有 Rust”。`rustup` 未安装，但现有工具链可用，不因此要求安装另一套 |
| rustfmt / Clippy | 1.9.0 / 0.1.97 | 用户要求的格式与 lint 工具均存在 |
| C/C++ 工具与 SDK | Xcode Command Line Tools；Apple clang 21.0.0；MacOSX SDK 可定位 | macOS 原生构建前置工具存在 |
| pkg-config / OpenSSL | 3.0.5 / 3.6.4 | 已发现；Linux 是否满足仍未检查 |
| WebKitGTK 4.1 | 当前 pkg-config 未找到 | macOS 使用系统 WebKit，不需要安装 GTK；这不能说明目标 Linux 是否已安装 |
| Linux 包管理与图形会话 | 未发现 pacman/apt-get；没有 Wayland/X11 会话环境变量 | 当前会话无法核验 Hyprland、Mesa、桌面通知服务或 Linux 库 |
| Claude Code CLI | 2.1.290；`claude auth status` 返回未登录 | 当前环境下真实 Claude 对话尚缺登录；不把凭据写入文档或仓库 |
| Codex CLI | 0.160.1；登录状态检查成功，ChatGPT 登录 | CLI 已可定位；实际模型调用、流式回答、权限确认尚未验证 |
| 项目依赖 | 上游无现成 `node_modules`、`target`；新仓库为空 | 批准后按保留依赖和锁文件安装；本阶段没有执行安装或构建 |

macOS 当前没有发现缺失的必需构建工具，但尚未以实际构建证明所有链接条件满足。当前明确缺少的是 Claude 登录以及已确认的最终验收环境。

若最终仍以 Arch aarch64 / Hyprland 验收，需要用户提供该环境的连接方式和桌面操作入口；只连接 SSH 不足以证明实际窗口交互通过。在该环境先检查以下完整类别，再列**实际缺少**的包申请安装：

| 类别 | 待检查内容 | 本阶段状态 |
| --- | --- | --- |
| 编译工具 | Node/npm、Rust/Cargo、rustfmt、Clippy、C/C++ 编译器、make、pkg-config | 未接入 Linux，不能断言存在或缺失 |
| Tauri Linux 原生库 | WebKitGTK 4.1、GTK 3、JavaScriptCoreGTK 4.1、libsoup 3、OpenSSL、librsvg；按保留平台功能核对 appindicator | 上游 README、安装脚本和 Cargo 锁文件明确涉及这些库；未探测目标机 |
| 资源/打包工具 | curl、wget、file、patchelf；原生链接所需开发文件 | 上游 Linux 安装脚本列出；运行开发窗口与制作安装包分别记录 |
| 图形与通知 | Wayland display、Hyprland、WebKit/EGL/Mesa、session D-Bus、桌面通知服务 | 未验证；不得默认改用 X11 后宣称 Wayland 通过 |
| Provider | Claude Code / Codex 的路径、版本、登录与实际请求可达性 | 必须在最终运行环境重新检查 |

上游仅提供 Debian/Fedora 安装脚本，没有 Arch 安装脚本。其 Fedora 脚本明确说明 `libxdo` 仅用于未启用的可选功能；不直接把其它发行版包名或整条安装命令照搬到 Arch。需要安装系统包时，先说明实测缺失项、用途和命令，获得用户批准后再执行。

Wayland 排查顺序：先保留 `tauri dev` 的终端日志，记录是退出、白屏还是窗口内容异常；核对是否出现上游 README 所述 EGL 错误，再核对原生 WebKitGTK/Mesa/Wayland 组合。该 README 的已知问题针对打包的 AppImage 与宿主库组合，不能直接推断所有 Wayland 白屏都是同一原因。任何临时渲染环境变量或后端切换均记录实际观察和影响，不悄悄改变默认运行方式。

## 3. 已审阅的边界与批准结果

以下保留审阅时的冲突及方案。用户已确认 Q1 使用当前 macOS、Q3 保留 ACP，其余建议接受；如表中原建议与本段冲突，以本段及后续用户回复为准。

| 编号 | 冲突或拿不准的项 | 建议处理及其影响 |
| --- | --- | --- |
| Q1 | 要求在 Arch/Hyprland 验收，但当前会话实际为 macOS；分支也不同 | 用户选择 macOS 开发、另接 Arch 验收，或改为当前 macOS 验收。默认不更名分支或移动仓库目录。若保留 Linux 目标，未完成 Linux 实机操作前不能宣称任务完成 |
| Q2 | “完整保留 `/operator`”与删除工作树、应用级多 agent 编排冲突；源码的 CLI 有 `control` 和 `app` 两套命名空间 | 保留 `loci app` 的 11 个通用动作及完整授权/请求/回执机制；删除 `worktrees.list/create`、会话启动的工作树字段以及编排专用 `control` 动作。允许 `/operator` 创建/发送普通会话和拖拽分栏等价操作，这不保留编排调度器 |
| Q3 | “保留 harness/core”与“不留死代码”冲突：部分 core 仅供要删除的八家 provider 或源码管理使用 | 保留 core 目录及 Claude/Codex 使用的生命周期、事件、权限、问答、模型/任务能力；保留 ACP，删除无调用方的 HTTP/SSE/端口辅助、git 文案生成和只供被删 provider 使用的文件/分支。不把整个 core 不加判断地复制过去 |
| Q4 | 聊天/笔记复用 `features/files` 的菜单、Markdown/代码块渲染、文件图标；权限卡片复用只读工具变更预览；文件树/代码编辑器又必须删除 | 保留聊天附件、Markdown 代码块/Mermaid、笔记图片和只读的工具结果/权限预览；把实际仍被调用的通用叶子移到 `shared` 或聊天目录。删除项目文件索引/文件搜索、编辑器和“在应用内打开文件”入口；普通文件链接仅保留已有的默认应用打开、定位、复制路径行为。`@note` 保留，项目文件自动补全不带入 |
| Q5 | 计划的独立 Open 当前创建编辑器 tab；应用 `/plan`、Build 的提示词明确要求调查代码仓库、实施和改文件（`sessions/model/plan.ts:30`） | 建议只保留 provider 返回的计划/任务及其聊天内显示，删除应用自有 `/plan`、Build 和独立计划打开/编辑入口，不另写泛化提示词。保留 plan.ts 中原生计划显示需要的解析/标题/摘要函数；去掉应用命令后同步解除 nativeCommands 的名字占用 |
| Q6 | 设置中的 Skills/MCP、账号/用量、手动会话提醒未被单独列入保留或删除清单 | 建议保留现有通用 agent/通知能力，仅支持两家 provider，MCP 不读取 Claude Desktop 或其余 provider。Skills 保留发现、Markdown 查看及可独立运行的现有管理表单；去掉代码编辑器跳转，不新增技能编辑器。提醒保留手动提醒及通知，不保留自动发起 agent 的自动化 |
| Q7 | MCP 配置发现中的 `.git` 父目录截止规则属于 provider 配置语义，却不满足字面“没有 git”（`mcp.rs:570`） | 建议 MCP 不保留 git 截止规则，以选定项目文件夹及原有个人/provider 配置来源为读取范围，不跨父项目扫描。需要用户批准这项配置发现语义变化；Skills 自己的通用父目录发现不因此顺手重写 |
| Q8 | provider 版本提示会自动查询 npm，按钮还可升级本机 CLI；这不是上游应用更新，但“去掉或停用自动更新、下载地址”可能也包括它 | 建议两种更新机制都删除：Loci 无应用更新器，也不查询/安装 Claude/Codex 新版本；保留本地 CLI 安装状态、版本、路径和登录检测。CLI 由用户自行维护 |
| Q9 | 原生子 agent 事件、旁问、显式交接与应用级编排范围不同；尤其已有聊天跨 provider 选模型依赖 handoff 的摘要移交（App.tsx:5891、:6786），直接删除会丢上下文 | 建议保留原生工具/子 agent 转录、普通会话活动总览、`/btw`，并保留模型切换所需的隐式上下文移交，仅裁掉其 CI/代码仓库专用提示与分支。删除显式 Handoff 和 Second opinion（代码审查）入口及可交互 worker 子窗格。若希望 handoff 全删，需要另外批准“已有会话不跨 provider 切换，改开新会话”这一行为变化 |

另有以下验收口径需在批准时一并认可：

- 删除功能的名称会出现在本清单和最终状态报告里，这是审计说明；功能残留检查针对实现、运行资源、依赖、命令、类型、配置和测试。旧产品名在所有受跟踪文件中仍严格只允许出现在 `LICENSE`、`NOTICE`，本文不构成额外豁免。
- provider 原生工具输出里的 `shell`、补丁里的 `diff --git`、Codex 表示计划模式的 `collaborationMode` 不等于应用终端、版本控制或编排功能；按调用链/能力审计，不能为了词面零命中破坏保留的协议。Q7 单列了确实涉及项目扫描语义的 git 截止规则。
- 上游的 `*Live.test.ts` 使用 mock 子进程，并非真实 CLI 集成验证。自动检查通过与实机真实对话分别记录，不能互相替代。Claude 登录由用户在确定的运行环境完成，不从其它项目寻找凭据。

## 4. 前端功能目录清单

标记含义：**保留**允许明确列出的混合部分裁剪；**去掉**包括入口、设置、快捷键、类型、持久化字段、依赖和专属测试；**拿不准**必须先按第 3 节决定。出边为主要直接依赖，入边为主要使用方，列出路径可定位的跨功能边界，不把 React 等共同依赖逐行重复。

缩写：`F = src/features`，`A = src/app`，`H = src/integrations/harness`，`P = src/platform/tauri`，`S = src/shared`。文件数包括测试；前端共有 945 个文件，其中 397 个测试文件；18 个功能目录共 674 个文件，其中 300 个测试文件。

| 功能目录及子目录覆盖 | 结论 | 依赖谁 → | 谁依赖它 ← | 抽取边界 |
| --- | --- | --- | --- | --- |
| `F/agent-app/model`（4） | 保留；Q2 | notes、sessions 的 session/models/folders/operatorCommand、workspace/layout；quick-composer 类型、worktrees | `A/App.tsx:9246` | 保留应用控制请求处理与 sessionConversation；解除 QuickLaunch/worktree 耦合；通用会话启动逻辑迁入此功能或 app 组合层 |
| `F/automations/model`（6）、`ui`（2） | 去掉 | inbox/githubTasks、skills、projects、sessions、workspace | `A/App.tsx:530`、`:7224` | 计划触发、轮询、自动会话、恢复、设置/入口及 `automationId` 一起去掉 |
| `F/connections/model`（17）、`ui`（6） | 去掉 | projects/recents、sessions、source-control/worktrees、H | `src/main.tsx:22`、App、SessionPane、SettingsView、workspaceSnapshot | 删除远程机器/路径/命令分发、附件同步、SSH、远程模型与会话状态 |
| `F/files/editor`（21）、`model`（16）、`ui`（21） | 功能去掉；叶子迁移拿不准 Q4 | source-control、terminal、search、sessions、P/fs | App/shell、Composer、AgentTranscript、AgentMarkdown、AttachmentChip、GeneratedImage、notes、skills、workspace | 文件树/索引/内容搜索/编辑器删除；通用菜单、图标、Markdown、高亮和只读工具预览按 Q4 搬出后不保留此功能目录 |
| `F/inbox/hooks`（4）、`model`（38）、`ui`（26） | 去掉 | files、source-control、notifications、sessions、instructions | App/shell、automations、notes、notifications、sessions、settings、workspace | 删除五类服务、工作项/PR/CI repair、媒体缓存；Notes 使用的通用相对时间格式函数迁到 S/lib |
| `F/notes` 顶层（5）、`ui`（4） | 保留 | sessions/attachments、AgentMarkdown、MarkdownModeToggle、projects、workspace/tabGroups、A/shell、P/fs；fileIndex 类型、inbox 时间格式 | App、agent-app、Composer、promptPreparation、session 模型 | 保留 CRUD、标签、项目关联、图片、`@note`；消除两处被删目录依赖；`delete_path` 仍用于图片暂存清理 |
| `F/notifications/hooks`（7）、`model`（10）、`ui`（6） | 保留；提醒范围 Q6 | sessions、settings/sounds、projects、workspace、files 菜单、inbox/githubTasks | App/shell、SettingsView、聊天 UI | 保留会话完成、权限/提问、静音、dock badge；删收件箱类别/工作项映射与相关测试分支 |
| `F/orchestration/model`（10）、`ui`（4） | 去掉 | notifications、sessions、workspace、H | App、session/store/history、SessionPane、AgentTranscript | 删除调度器、lead/worker/proposal、任务审核/重试/委派、专用面板与存储 |
| `F/projects/hooks`（1）、`model`（23）、`ui`（11） | 保留 | workspace/layout/tabGroups、settings/appearance、sessions、P/fs | App、会话/设置/布局/笔记、H | 项目仍是文件夹；保留最近项目、分组、位置、图标/背景、打开/返回/归档。删 projectTerminal、ProjectSearch 文件搜索、远程路径与外部代码编辑器菜单 |
| `F/providers/model`（17）、`ui`（5） | 保留两家；更新拿不准 Q8 | sessions、H/core 的 child/jsonRpc/registry/auth、codexProtocol；更新引用 opencodeProtocol | App、Usage 显示、SettingsView、sessions、H | 保留 Claude/Codex 的账号、身份、凭据、路径、用量/限额；删 piUsage 和其它八家；升级通知/检查按 Q8 删除 |
| `F/quick-composer` 顶层（1）、`hooks`（1）、`model`（14）、`ui`（19） | 去掉；通用启动逻辑迁出 | sessions、skills、source-control、projects、workspace、H | App、A/model/quickLaunchSession、agent-app、settings | 删除浮窗、截图快输、全局快捷键、快速 git 弹窗；`/operator sessions.start` 所需本地创建/接受提交逻辑必须迁出，不能一起删 |
| `F/search/model`（4）、`ui`（1） | 保留会话搜索，裁剪文件搜索 | sessionStore、transcriptFind、projects/recents、files/fileIndex/FileTypeIcon、A/shell | App、ProjectSearch、files、AgentMarkdown、PaneTree | 保留会话标题/转录搜索、项目过滤、会话内查找；删文件/内容范围、编辑器导航与 Rust search_project/cancel_project_search |
| `F/sessions/data`（9）、`hooks`（4）、`model`（108）、`ui`（107） | 保留；混合裁剪 Q4/Q5/Q9 | A/shell、其余大部分 F、H、P、S | App、workspace、notes、notifications、agent-app、H | 保留历史/列表/转录/输入/模型/权限/问答/计划/任务；删 checkpoint、SessionReview、ciRepairContext、sessionWorkItem、LinkSessionWorkItemDialog、ompInterjections、应用编排、ComposerRunner、EmptySession 游戏背景及对应测试 |
| `F/settings/model`（26）、`ui`（8） | 保留；Q6/Q8 | updater、connections、inbox、notifications、projects、providers、quick-composer、sessions、skills、source-control、workspace、H | App/shell 和所有保留功能 | 保留外观、布局、声音/通知、聊天、两 provider、有效快捷键、归档；删 Connections/Inbox/Worktrees/Jira、编辑器自动保存/格式化、游戏、快输、更新项及搜索索引 |
| `F/skills/model`（5）、`ui`（8） | 拿不准 Q6/Q7；通用 slash 基础保留 | files/fileIndex、sessions/quoteDraft/AgentMarkdown/MarkdownDocumentPreview/useComposerSkills、H/nativeCommands/registry、P/fs | App、Composer、promptPreparation、plan/operator/compact/mcp/draft/folder 命令、SettingsView | `/operator` 等命令共享 BuiltinSkill/斜杠菜单，不能整删；管理能力建议仅保留 Claude/Codex/通用来源，删除编辑器入口 |
| `F/source-control/hooks`（4）、`model`（21）、`ui`（24） | 去掉 | files、inbox、sessions、settings、projects、workspace、H、P/fs | App/shell、agent-app、connections、projects、quick-composer、sessions、settings、workspace、H | git/worktree/diff 页及所有生命周期、LLM 分支/提交/PR 文案接口删除；聊天工具自己的只读预览按 Q4 独立定界 |
| `F/terminal/arcade`（7）、`model`（10）、`ui`（4） | 去掉 | A/shell、files、projects、sessions、settings、workspace、P/pty | App、appLifecycle、UsageFooter、projectTerminal、workspace、EmptySession | 删除终端、PTY 前端、背景棋盘及游戏；CLI 的工具调用输出仍由聊天协议呈现，不等于保留终端 |
| `F/workspace/hooks`（1）、`model`（13）、`ui`（11） | 保留；surface 裁剪 Q5 | A/model/releaseNotes、shell、connections、files、inbox、notifications、projects、search、sessions、settings、source-control、terminal、H | App/shell、sessions、projects、agent-app、notes | 保留 split/move/remove/ratio/neighbor、paneDrop、tabGroups、keys、visitHistory、snapshot、聊天 PaneTree、tab 关闭动效；删除 WorkspacePicker 工作树选择及 editor/terminal/commit/review/worker/release surface |

### 4.1 组合层、平台层、共享层与资源

| 路径/文件组 | 结论 | 依赖与使用方；必要裁剪 |
| --- | --- | --- |
| `src/main.tsx` | 保留、重接启动 | 依赖 App、appLifecycle、appearance/sounds、P/fs、providerBinaryPaths、styles；删 remoteCommands、installedUpdate，性能标记改为 Loci |
| `A/App.tsx` | 重写组合根 | 11,603 行，导入涉及全部 18 个 feature。保留窗口/项目/布局、提交/流式/权限/提问、持久化、operator、笔记/设置/搜索/通知；不搬入 checkpoint、quick composer、remote、automation、orchestration 分支。键盘、native menu、render 必须一起重接 |
| `A/hooks/useWorkspaceNavigation.*` | 去掉工作树导航；项目导航由组合根复用原 projectReturn | 实施核对发现此 hook 的异步状态机全部围绕 worktreeFocus/checkout 切换；删除后用已保留的 projectReturn/layout 驱动文件夹项目与会话导航，不留空状态机 |
| `A/hooks/useIdleSessionDetach.*` | 保留、裁剪 | 依赖 sessions、harness registry；App 使用。删编排 worker 附加处理 |
| `A/model/appLifecycle.*`、`bootWorkspace.test.ts`、`windowTransfer*` | 保留、裁剪 | 依赖 sessionStore/inFlight、workspaceSnapshot、项目位置/最近项目、child/registry；main/App 使用。删 PTY、项目终端、移除 surface；本地跨窗口移 tab 不属于远程会话 |
| `A/model/harnessFlush.*`、`submissionAcceptance.*`、`preloadNavigation.*` | 保留 | 分别做流式事件批处理、提交接受前同步项目位置、绘制后预加载；App/提交逻辑使用 |
| `A/model/managedSubmission.*` | 去掉 | 依赖编排 `ControlOutcome`；实际调用只有自动化和编排。operator send 直接等待提交，start 使用启动接受流程，并不需要此模块 |
| `A/model/quickLaunchSession.*` | 原文件去掉、必要逻辑迁移 | 依赖 QuickLaunch/quickWorkspace、sessions/projects/workspace；App 的 operator 启动也调用。迁移通用创建会话及提交逻辑，删快速窗口特性 |
| `A/model/{updater,updateNotice,releaseNotes,releaseNotesWorkspace}*`、`A/ui/ReleaseNotesSurface.tsx` | 去掉 | 依赖 CHANGELOG raw、updater/process、sounds；main/App/MenuBar/SettingsView/workspace 使用。没有 Loci 发布内容时不建空发布页 |
| `A/shell/{ClosingTab,GlassBackdrop,RailAction,SettingsRail,WindowControls}*` | 保留 | 标题栏、侧边栏、笔记/搜索/设置、Modal/Popover 使用；原视觉与动效不变 |
| `A/shell/{TitleBar,Sidebar,ProjectRail,MenuBar,useProjectMenu}*` | 保留、裁剪 | 原先同时依赖 files/source-control/inbox/orchestration/connections/updater。仅保留 projects/workspace/sessions/settings/notifications/shared 相关入口、菜单与快捷键 |
| `A/shell/{UsageFooter,UsageProviderChip}*` | 保留两家 | 依赖 provider 账号/用量/限额、登录面板、displayPrefs；App 使用。删 Pi 用量及终端状态栏 |
| `A/shell/{GithubStarPrompt,PiUsage,SidebarUpdate,UpdateRailCard,WhatsNewDialog}*` | 去掉 | 原由 Sidebar/ProjectRail/UsageFooter/App 调用；一起删除原产品推广、升级、发布提示 |
| `P/{clipboard,platform}*` | 保留 | clipboard 依赖 Attachment/invoke；Composer/Markdown/附件使用。platform 被全 UI 使用 |
| `P/pty.*` | 去掉 | terminal/TerminalView、appLifecycle 使用；harness 使用 core/child，与该适配器无关 |
| `P/fs.*` | 保留通用部分 | 保留选文件夹、home/路径、项目位置、附件/图片、Claude transcript 恢复；Q4/Q6 决定的文件打开及 skill IO。删 remote runner、OMP、external editors、git、文件树/编辑器专属 IPC |
| `S/hooks` | 保留实际调用及测试 | AnimatedReorder、Sortable、DragResize、LockOverscroll、ColorScheme 为 shell/chat/notes 提供通用交互；后者依赖 appearance |
| `S/lib/{concurrent.*,csp.ts,format.ts,remotePaths.ts}` | 去掉 | 当前调用方仅为 source-control diffs、files/editorChrome、FileEditor、remote；没有保留调用方 |
| `S/lib` 其它文件 | 保留、按调用裁剪 | paths 去 remote；drag 去 explorer/git payload；jsonText 仍供 sessionTitle；fuzzy 供 notes/search/history；markdownFrontmatter 供文档预览；数字/颜色/路径/列表/动画实用函数沿用 |
| `S/ui` | 按保留消费者搬运 | Modal/Popover 依赖 GlassBackdrop，PrivateEmail 依赖 displayPrefs；日期、颜色、tab、图标、轻量预览和 lazySurface 留用。NativePopupHost 也被 Modal/Popover 用到，不能随快速 git 弹窗删除 |
| `src/styles/index.css` | 保留、按选择器裁剪 | 保留主题 token、玻璃、布局、拖拽、tab、流式文字、operator 星光动效；删编排、inbox、终端、游戏、git history 样式。不能整段删掉混合 scrollbar 规则 |
| `src/assets/providers` | 保留 2 / 去掉 8 | 只带 `claude.svg`、`codex.svg`；与 HarnessIcon/model picker/设置的枚举同步 |
| `src/instructions/inbox.md` 及其目录 | 去掉 | inbox 独有，随入口/提示注入删除 |
| `src/vite-env.d.ts` | 保留 | Vite/TypeScript 类型入口 |
| `public`、`src-tauri/icons`、`src-tauri/macos` 的旧产品图标 | 去掉、替换 | 不使用旧 logo/Assets.car/AppIcon 资源；生成中性占位图标，所有平台窗口、HTML favicon、启动页与通知统一指向新资产 |

### 4.2 明确列出的目录迁移例外

在 Q4 批准后才实施。只迁移仍被保留代码调用的函数和相应测试，不留下 `files` / `inbox` 功能壳。

| 原位置 | 新归属 | 原因与消费者 |
| --- | --- | --- |
| `files/ui/ExplorerMenu.tsx` 及通用菜单测试 | `shared/ui/ContextMenu.tsx` | shell、分组、通知静音/提醒、AgentMarkdown 都使用，并非只给文件树 |
| `files/ui/FileTypeIcon.tsx` | `shared/ui/FileTypeIcon.tsx` | 附件、生成图片、聊天工具卡片保持同一图标视觉 |
| `files/ui/FileActionError.tsx` | `shared/ui/FileActionError.tsx` | AgentMarkdown 的默认应用打开、定位、复制失败仍使用原错误展示 |
| `files/ui/FilePreview.tsx` | `sessions/ui/FilePreview.tsx` | 只读工具修改/权限预览，不调用 git、不提供编辑器；对应 ToolDiffPreview 测试保留 |
| `files/editor/{codeHighlightPlugin,mermaidPlugin}` | `shared/lib/markdown/` 对应文件 | 聊天和笔记的 Markdown 渲染依赖；不带 CodeMirror |
| `files/model/{markdownSource,markdownFileLinks,fileName,filePreview}` 的实际保留部分 | `shared/lib/markdown/` 或 `shared/lib/` 的同名文件 | Markdown 标题/链接/高亮和附件辅助；剪掉 editor 导航回调与无消费者部分，不为迁移建空文件 |
| `files/model/fileIndex` 的 `RankedFile` 类型 | 实际仍用它的 notes/mentions 模型 | notes.ts 仅复用了此结构，不因此带入整个项目文件索引 |
| `files/model/fileMentions.ts` 的笔记 mention 解析/匹配/高亮/替换及纯排序 | `features/notes` 的 mention 模型或实际共用的 S/lib | `@note` 除类型外仍用这些函数；删除项目文件索引加载和文件引用注入，不把整个 fileMentions 当文件树删除 |
| `inbox/model/githubTasks` 的 `formatRelativeTime` | `shared/lib/relativeTime.ts` | NotesView 使用的纯时间格式化函数，不带工作项模型 |
| quick-composer 的本地会话启动类型与 `A/model/quickLaunchSession` 的通用部分 | `features/agent-app/model/sessionStart.ts` 与组合层提交 hook | `/operator sessions.start` 需要真正创建 tab、放置 pane、保存草稿/启动 turn；快速窗口 UI/快捷键完全删除 |
| `quick-composer/model/quickComposerShortcut.ts` 的通用按键解析/规范化/显示函数及相应纯测试 | `shared/lib/shortcuts.ts` | settings.ts 与 SettingsView 的普通快捷键录制器也使用 canonicalShortcut/shortcutFromKeyEvent/shortcutTokens/label/preview；去快输默认值、全局快捷键校验/注册及专属 UI 测试，通用函数改为无快输前缀名称 |

所有其余保留模块沿原目录搬运。记录最终迁移文件对照，不顺手重新组织整个 shared 或 harness。

### 4.3 聊天与存储混合文件的裁剪要点

- `session.ts`、`sessionStore.ts`、`sessionHistory.ts`：去 branch/worktree/linkedWorkItem/automation/orchestration/remote 及其它 provider 的恢复字段和回填分支；保留 providerSessionId、草稿、模型、权限模式、operator 标记、任务/计划 blocks、in-flight 和恢复队列。
- `Composer.tsx`、`SessionPane.tsx`、`AgentTranscript.tsx`：保留输入与附件/笔记、流式回答、取消/续发、模型/权限选择、批准/拒绝、agent 提问表单、任务和计划显示；删除被删 feature 的 import、props、按钮、快捷键、上下文菜单及事件路由。
- Codex 的 `editLastTurn` 是聊天编辑重发及 provider 状态回退，保留；文件系统 checkpoint 是另一套机制，删除。不要按“回退”一词误删聊天能力。
- 按 Q9 保留 `handoff` 中模型切换状态机、摘要/恢复所需最少逻辑，删显式转交/Second opinion 的代码审查入口及 CI 修复依赖；不能因删 UI 按钮而让跨 provider 切换默默失去上下文。
- 按 Q5 保留 `plan.ts` 的 `isReviewablePlan`、`planTitle`、`planSummary`、`planMeta` 等实际被 core/apply/转录使用的部分；删除 PLAN_COMMAND、consumePlanCommand、planTurnPrompt、buildPlanPrompt 及对应应用内动作。
- `AgentMarkdown.tsx` 去 inbox 媒体模式与应用内文件编辑路径；保留普通链接、笔记图片、Markdown、代码块/Mermaid 和原文字淡入。`UserLinkPreview` 去工作项匹配，普通链接预览保留。
- `liveAgents.ts` 的普通会话活动总览主动排除了编排 worker，按 Q9 建议留在聊天外壳；应用级编排状态机和交互 worker 面板删除。
- operator 气泡的星光组件/工具调用模型文件名带旧品牌：改为 `LociSparkles`、`lociToolCall`，包括文件名、类型、测试、CSS 和事件名。该星光属于保留的气泡动画；ComposerRunner 与 terminal/arcade 才是要删除的游戏。
- 模型专属非交互欢迎动效按两家保留模型的实际调用继续保留；不把纯动效误判成游戏，不给已删模型留下不可达组件。

## 5. Harness 核心与 provider 清单

`src/integrations` 下只有 `harness`。所有下表文件组连同相应测试一起处理；目录“保留”不表示复制被删 provider 专属分支。

| 路径 | 结论 | 依赖谁 → | 谁依赖它 ← / 裁剪 |
| --- | --- | --- | --- |
| `harness/index.ts` | 保留、裁剪导出 | core、provider 模块 | App、sessions、settings；仅导出实际保留接口 |
| `harness/core` | 保留，Q3 裁剪 | sessions/models/providers、Tauri、shared；部分 source-control | App、sessions、settings、providers、agent-app；逐文件见下表 |
| `providers/claude` | 保留 | core、sessions 的 models/attachments/tasks/questions、provider 账号/限额、Claude hooks、P/fs | register、公共导出、sessions；删除 `claudeGit.ts` 和 adapter 的 git 文案能力 |
| `providers/codex` | 保留 | core、sessions 的 models/attachments/tasks/questions、provider 账号/限额、P/fs、paths | register、公共导出、sessions、provider 用量；删除 `codexGit.ts` 和 adapter 的 git 文案能力 |
| `providers/cursor` | 去掉 | core、sessions、P/fs、source-control | register/index、Cursor SQLite 恢复；所有调用一起删 |
| `providers/antigravity` | 去掉 | core、sessions、P/fs | register/index、模型/设置 |
| `providers/fx` | 去掉 | core、sessions、P/fs | register/index、模型/设置 |
| `providers/grok` | 去掉 | core、sessions、P/fs、source-control | register/index、Hermes 协议 |
| `providers/hermes` | 去掉 | core、sessions、P/fs、Grok 协议 | register/index、模型/设置 |
| `providers/omp` | 去掉 | Pi family、core、sessions | register/index、OMP 特殊消息回填 |
| `providers/opencode` | 去掉 | core、sessions、P/fs、source-control | register/index、provider 更新的 semver 辅助、settings、编排测试；Q8 建议把更新调用方一起删 |
| `providers/pi` | 去掉 | core、sessions、projects、P/fs | register/index、omp、skills 测试、Pi 用量 |

### 5.1 Core 每个生产文件

| 文件 | 结论 | 出边 / 入边；裁剪理由 |
| --- | --- | --- |
| `apply.ts` | 保留 | session/contextUsage/taskList/plan/models、preview/streamText/paths → 通用事件应用；被 App 和协议/会话测试使用 |
| `auth.ts`、`authSupport.ts` | 保留两家 | 依赖 child/providerAccounts/session/Tauri；登录面板、SettingsView、UsageFooter、AgentTranscript 使用；删除其余登录流程 |
| `availability.ts`、`availabilityState.ts` | 保留两家 | 依赖 child/registry/provider 枚举；模型选择、设置、agent-app 使用 |
| `child.ts` | 保留本地进程桥；Q3/Q8 裁剪 | Tauri invoke/event、providerBinaryPaths；两家 provider 使用 spawn/write/kill/stdout/stderr/exec/CLI 检测。删除 headless backend、remote/host 配置、Hermes 文本读取、OpenCode HTTP/SSE/free-port 和其余 resolver |
| `jsonRpc.ts` | 保留 | child → Codex 会话、catalog、text prompt、用量 |
| `nativeCommands.ts` | 保留 | HarnessId → registry、skills、promptPreparation；原生命令与应用命令冲突处理仍需 |
| `preview.ts` | 保留，Q4/Q9 定边界 | session/paths/shellIntent → 两 provider、apply、AgentTranscript、transcriptActivity、sessionStore；工具 shell/file/edit/subagent 元信息并非应用终端/编辑器/编排 |
| `register.ts` | 保留、收窄 | 只 import/register Claude/Codex adapter；不要仍触发八家模块的副作用 |
| `registry.ts` | 保留、裁剪 | session/models/sessionTitle/userQuestion/nativeCommands/types/Tauri → 全局 harness 调度。删 PrContent、commit/PR/branch 生成；保留 idle park、发送串行化、steer、compact、rewind、问题/批准、绑定恢复、turn 授权 |
| `shellIntent.ts` | 保留 | preview/codexProtocol 使用的纯工具命令标题解析，不启动终端 |
| `streamText.ts` | 保留 | apply、两 provider 主会话/文本/协议使用 |
| `types.ts` | 保留、裁剪 | session/userQuestion → 全 harness。删除应用编排字段；原用于 operator 回环权限的 `controlsAgents` 改为应用访问含义，不能把网络许可一起删掉 |
| `acp.ts` | 保留（用户明确要求） | 仅 Cursor/FX/Grok/Hermes/Antigravity 使用 |
| `acpSubagents.ts` | 保留（用户明确要求） | types/transcriptActivity/preview；仅上述 ACP provider 使用 |
| `abortTextPrompt.ts` | 拿不准 Q3，建议去掉 | 仅 Cursor/Grok/Pi/OpenCode 文本后端使用 |
| `textHarness.ts` | 拿不准 Q3，建议去掉 | source-control/gitText、availability、registry；外部调用仅 App 自动分支命名及源码管理面板，通用标题另有调用链 |

### 5.2 两个 provider 的完整对话链

- Claude：`claude.ts`、`claudeProtocol.ts`、`claudeAdapter.ts`、`claudeCatalog.ts`、`claudeText.ts`、`claudeTitle.ts` 保留；协议的 JSON lines、增量文本、工具、stdio 权限请求、提问、任务/计划、provider 会话恢复保留。`claudeGit.ts` 删除；Text/Title 仍供自动标题和 Q9 的旁问，不能一并删除。
- Codex：`codex.ts`、`codexProtocol.ts`、`codexAdapter.ts`、`codexCatalog.ts`、`codexText.ts`、`codexTitle.ts`、`codexQuestions.ts`、`codexElicitation.ts` 保留。保留 JSON-RPC、流式、批准/提问/MCP confirmation、计划、工具、取消/steer/compact/rewind/恢复；`codexGit.ts` 删除。
- 原生 provider 的子 agent/tool 事件与应用级 lead/worker/run 编排不同。按 Q9 保留协议解析和转录显示，不复制应用编排状态机。Codex 的 `collaborationMode` 同时表示原生计划模式，不可按字段名字机械删除。
- 恢复不仅是把 SQLite 行显示出来：保存 providerSessionId，重启时 `bindHarnessSession`，从已有 blocks 恢复 task lists，再由 provider resume 同一会话；实际测试要覆盖后续一轮消息。

## 6. Rust 模块逐项清单

覆盖 `src-tauri/src` 的全部 **47 个 `.rs` 文件**。所有对前端暴露的命令还需同步调整 `lib.rs` 注册；表中使用方不重复写这一共同注册边。

| 模块 | 结论 | 依赖谁 → | 谁依赖它 ← / 裁剪边界 |
| --- | --- | --- | --- |
| `account_identity.rs` | 保留 | harness/provider_account_dir、base64、JSON、home | provider 账号菜单/设置/侧栏；目前只支持 Claude/Codex，保持凭据不出现在 UI 返回值 |
| `automations.rs` | 去掉 | session_store、SQLite | 自动化页面/调度、store 的迁移调用；一起删除 |
| `azure_devops.rs` | 去掉 | ureq、URL、本地配置 | inbox/设置；API/配置/测试都不带 |
| `chat_background.rs` | 保留 | fs/expand_home、app data | 项目/聊天外观；图片归 Loci 数据目录 |
| `checkpoint.rs` | 去掉 | fs Git helper/diff 类型 | 会话 checkpoint；调用/测试同时删 |
| `control.rs` | 保留、裁剪 Q2 | fs、harness；原 session_store 编排表 | harness 子进程环境、App、operator；保留 app 回环授权/请求/回复，删 control 编排 namespace、worker、scope/scratch 与编排存储 |
| `control_cli.rs` | 保留、裁剪 Q2 | TCP loopback、JSON、UUID、env | main；保留 app 子命令、参数/JSON/stdin/request-id/错误输出；去工作树及 lead/worker 控制动作 |
| `cursor_store.rs` | 去掉 | SQLite、Cursor 用户数据 | Cursor provider/子 agent 恢复 |
| `external_editor.rs` | 去掉 | home、fs/expand_home、harness CLI 路径 | 外部代码编辑器菜单/设置 |
| `fs.rs` | 保留、大幅裁剪 Q4/Q6 | home、harness、系统文件 API、base64、open | projects、attachments、notes、harness、skills 等；详见 6.1，不能整搬或整删 |
| `gitlab.rs` | 去掉 | ureq、本地配置 | inbox/设置 |
| `harness.rs` | 保留、裁剪 | fs、control、rate_limits、Windows 进程 helper；原 worktree reservation | core/child、两个 provider、账号/设置；保留管道进程、CLI 检测、账户隔离与必要 MCP 调用，删除八家 resolver/HTTP/SSE/工作树等 |
| `harness_updates.rs` | 拿不准 Q8，建议去掉 | harness/exec_output、ureq、npm registry | provider 自动版本查询/手动升级按钮；与应用更新是不同机制 |
| `inbox_media.rs` | 去掉 | fs、harness、ureq、GitHub CLI | inbox 媒体 |
| `jira.rs` | 去掉 | ureq、URL、本地配置 | inbox/Jira 设置 |
| `lib.rs` | 保留、重写接线 | 所有已保留 Rust 模块及 Tauri plugins | main；仅管理真实保留的 state、命令、启动/退出生命周期 |
| `linear.rs` | 去掉 | ureq、本地配置 | inbox/Linear 设置 |
| `link_preview.rs` | 保留 | ureq、URL、base64、DNS | 普通会话 URL 预览；沿用公网目标/重定向检查，改 User-Agent 品牌 |
| `macos.rs` | 保留、改名/裁剪资源 | window、objc2、通知框架、raw-window-handle | lib/window；窗口/Dock/dev bundle 保留，旧图标和快输调用方去掉 |
| `macos_background.rs` | 去掉 | objc2 activation guard | window 隐藏打开；唯一 `reveal=false` 来源是 quick_composer，不属于普通窗口外壳必需 |
| `main.rs` | 保留、裁剪 | 库 run、control_cli、macOS dev bundle | 桌面二进制/CLI 入口；删 ssh askpass/control 编排分支，保留 app 分支 |
| `mcp.rs` | 拿不准 Q6/Q7，建议保留裁剪 | fs/expand_home、harness、TOML、URL、home | MCP 设置/聊天；仅 Claude Code/Codex，去 Claude Desktop、Cursor/OpenCode；项目发现边界按 Q7 |
| `menu.rs` | 保留、裁剪 | window、Tauri native menu | App native menu 事件/快捷键；删文件查找/编辑器/auto-save/项目文件搜索/终端/inbox/更新/上游帮助链接 |
| `notes.rs` | 保留 | fs/expand_home、session_store、SQLite | 笔记 UI/operator；CRUD、slug、标签、图片、会话/项目关联 |
| `notifications.rs` | 保留；提醒 Q6 | 平台通知 API、reminders | 输入/完成通知与设置；改 app name、icon、category/action/事件、平台类名 |
| `pasteboard.rs` | 保留 | fs 附件路径/大小检查、arboard、PNG、URL、原生 API | clipboard/聊天附件；保留 Wayland 文件/图片粘贴逻辑 |
| `pi_usage.rs` | 去掉 | ureq、time、Pi 认证文件 | Pi 用量；time 依赖随之删除 |
| `project_logo.rs` | 保留 | fs/expand_home、app data | 用户自选项目图标；不是旧产品 logo，资产落入 Loci 目录 |
| `pty.rs` | 去掉 | fs、harness、windows、worktrees/lifecycle、portable-pty | 应用终端与工作树占用保护；两个保留 provider 不依赖它 |
| `quick_composer.rs` | 去掉 | window、macos、global-shortcut、三个子模块 | 快速输入窗口/设置 |
| `quick_composer/delivery.rs` | 去掉 | quick_composer 数据类型 | 快输 delivery 及其测试 |
| `quick_composer/git_popup.rs` | 去掉 | window、macos | 快速 git 弹窗 |
| `quick_composer/screenshots.rs` | 去掉 | window、截图暂存 | 快速输入截图 |
| `rate_limits.rs` | 保留、裁剪 | harness/provider_account_dir、ureq；macOS sha2/unicode-normalization | Claude 账号/用量；去 OpenCode Go 查询及认证探测 |
| `reminders.rs` | 拿不准 Q6，建议保留 | session_store、notifications、window、SQLite | 手动会话提醒/通知；不启动自动 agent，与 automations 区别明确 |
| `remote.rs` | 去掉 | remote_ssh、ureq、连接记录 | connections/lib state/退出处理 |
| `remote_ssh.rs` | 去掉 | ssh_askpass、remote、bootstrap 脚本、ssh | remote；包括上游 host 下载和旧 host 数据目录访问 |
| `search.rs` | 去掉 | fs 项目枚举、Git grep | 项目文件内容搜索；**会话搜索在 session_store.rs，不在此模块** |
| `session_store.rs` | 保留、大幅裁剪 | rusqlite、notes、fs 图片清理；原 worktrees/reminders/automations | 会话 CRUD/搜索/布局/笔记；按 6.2 裁剪 schema、字段、查询、迁移、测试 |
| `skills.rs` | 拿不准 Q6，建议保留裁剪 | fs/expand_home/path_to_js、home、JSON | Skills/输入框 slash skills；仅通用 `.agents`、Claude、Codex 与 Claude plugins 来源 |
| `ssh_askpass.rs` | 去掉 | loopback socket、ssh env | main/remote_ssh |
| `tray.rs` | 保留 | window、Tauri tray | Windows 窗口恢复/退出；跨平台源逻辑保留，不宣称未操作平台已验收 |
| `window.rs` | 保留、裁剪 | harness、macOS/window API；原 pty/macos_background | 外壳/菜单/生命周期；删快输 label/隐藏窗口/PTY cleanup，保留退出前落盘握手 |
| `window_transfer.rs` | 去掉（实施核对后更正） | Tauri state、JSON | 只有未调用的预留；不新增搬运入口，普通新建窗口保留 |
| `windows.rs` | 保留、裁剪 | windows-sys JobObjects/线程/DLL API；原 portable-pty | harness/spawn_managed；保留子进程管理，删 spawn_pty/PTY 专属测试 |
| `worktree_lifecycle.rs` | 去掉 | worktrees/contains_working_dir | harness/PTY/worktree 的预约互斥，harness 引用一起删 |
| `worktrees.rs` | 去掉 | fs Git、SQLite、PTY、harness、lifecycle | 工作树 UI/编排/store reconciliation，全链删除 |

其它 Rust 侧源文件：`remote_bootstrap.sh`、`remote_bootstrap.ps1` 去掉，使用方是 remote_ssh；`src-tauri/build.rs` 保留 Tauri 构建和必要平台链接处理，去旧 Assets.car watch，更新为实际新图标资源。

### 6.1 通用文件和进程服务

`fs.rs` 保留以下真实调用链：

- 项目文件夹：`resolve_project_location`、`expand_home`、`path_to_js`、home/路径处理；不把项目改造成仓库或其它实体。
- 聊天与笔记附件：`inspect_paths`、`read_file_base64`、`read_binary_file`、`write_attachment`；生成图片的保存及会话删除清理。
- Claude 会话恢复：`claude_shell_commands` 只补读 provider 原生 transcript 的工具命令记录，不提供应用终端。
- Q4 的现有默认应用打开/定位：`reveal_path`、`open_path_with_default_app`；删除外部代码编辑器发现与专用打开入口。
- 笔记图片暂存清理仍需要 `delete_path`；若 Q6 保留技能管理，`create_path/read_text_file/write_text_file` 的实际使用部分仍需要，不能因为“文件 IO”一律删掉。

去掉所有 Git/GitHub/star 相关函数与类型、OMP 回放、文件树/list_dir、项目文件枚举、clone、编辑器 stat/watch、项目文件移动/重命名入口及其专属测试。剩余 Tauri 注册命令必须都有前端/内部调用，不保留给未来可能使用的接口。

`harness.rs:824` 的进程使用 `std::process::Command` 和 stdin/stdout/stderr 管道。删除 `pty.rs` 不影响它；保留 spawn race 防护、进程组/取消/退出、缓冲与 Windows JobObject。删除工作树预约及仅供已去 provider 使用的 HTTP/SSE。`windows.rs::spawn_managed` 保留，`spawn_pty` 删除。

### 6.2 SQLite 与布局快照

SQLite 继续使用原 rusqlite（bundled/hooks）。保留 sessions、会话搜索/归档/pin/draft、providerSessionId、in-flight、workspace snapshot、notes；reminders 按 Q6。前后端 payload 同时精简。

必须删除的混合点包括：

- `SessionStore::open` 的 worktree reconciliation（`:45`）。
- SessionUpsert/Summary/Record 的 branch/worktree/linked work item/automation/orchestration 字段及索引，以及 repo/additions/deletions 的仓库统计。
- upsert/list_by_project 的 Git 元数据查询（`:1105`、`:1565` 附近）。
- worktree removals、orchestration runs/sidebar/workers、automations 的表、建表调用、迁移、查询及 fixture。
- 历史 `inbox_ask` 列、`sessions_legacy_inbox` 索引、查询过滤和 fixture（`:934`、`:1279`、`:1575` 等），不能只删 linkedWorkItem 就认为收件箱存储已清完。
- 布局 snapshot 内 editor/terminal/commit/review/worker/remote/release surface 及原产品兼容键。

Loci 从自己的空 schema 开始，不读取、迁移、导入上游数据；不为了兼容从未属于 Loci 的历史版本保留被删字段。保留 WAL/事务、会话写入队列、退出时 flush、in-flight 恢复等现有一致性机制。改完后从空目录启动、写入、重启读取，再检查实际 schema，不只断言 mock payload。

## 7. `/operator` 的保留合同（Q2 批准后）

CLI 形式为 `loci app ACTION [--json JSON | --input FILE|-] [--request-id ID]`；`/operator` 仍只在用户启用的会话中授予应用访问，并在该会话后续 turn 中继承。不把本地回环操作改成远程 API，不新增服务。

保留动作共 11 个：

| 类别 | 动作 | 必须实际有效的行为 |
| --- | --- | --- |
| 模型 | `models.list` | 仅报告 Claude/Codex 可用模型、设置和权限模式 |
| 会话 | `sessions.list/read` | 当前项目会话、有限的 user/assistant 历史及 cursor；不泄露控制 token |
| 会话 | `sessions.send/draft` | 空闲会话发后续消息/保存未提交草稿；忙碌或已有草稿冲突沿用原错误语义 |
| 会话 | `sessions.start` | 真正创建 tab，支持默认位置或 right/down 分栏、besideSessionId、draft、模型与权限继承；去工作树参数 |
| 文件夹 | `folders.list/move` | 原会话文件夹组织，包括新建目标文件夹；不是操作磁盘项目目录 |
| 笔记 | `notes.list/read/write` | 列表/全文/创建更新，保留项目与来源会话关联 |

完整链路必须共同搬运并验证：

```text
Composer /operator + session 标记
  -> 会话提交准备（去前缀，注入 loci CLI 用法）
  -> registry 授权当前 turn
  -> harness 子进程环境（LOCI_APP_ENDPOINT / LOCI_APP_TOKEN）
  -> loci app CLI -> 127.0.0.1 随机端口 -> control.rs 鉴权
  -> 定向到当前窗口的请求事件 -> agent-app -> 会话/布局/笔记
  -> 带 request-id 的响应 -> CLI JSON 输出
  -> turn 结束 / 会话关闭 / 窗口关闭时失效与清理
```

保留 token、请求大小、并发/超时、窗口/会话绑定、活跃 turn 限制、request-id 幂等与重试语义。删除编排专有 reservation/scope/scratch/worker 处理；删除 `control` CLI namespace 及其提示词，不把它藏起来继续运行。

Codex 为访问本地回环启用的网络权限需要保留。原 `controlsAgents` 同时服务 operator，改名为准确的应用访问含义后保持原生沙箱/网络设置行为；不能因移除编排使 operator 在 Codex 中不可用，也不能给所有普通会话自动开启应用访问。

## 8. 依赖、配置、脚本和许可

### 8.1 依赖处理

以现有锁文件的解析版本为准，不能只复制 package.json 的范围后重新解析到新版本。上游当前锁定 React/ReactDOM `19.2.8`、Tailwind `4.3.3`、TypeScript `5.8.3`、Vite `7.3.6`、Vitest `3.2.7`、Tauri JS API `2.11.1`、Tauri CLI `2.11.4`、Rust tauri `2.11.5`、rusqlite `0.40.2`。这些只是基线记录，不是升级目标。

| 依赖组 | 结论与用途 |
| --- | --- |
| React/ReactDOM、Tailwind/Vite/TypeScript、Vitest/happy-dom、现有构建类型依赖 | 保留实际需要的直接项和原锁定版本；不要升级或更换测试框架 |
| HugeIcons、streamdown、rehype-harden、cuelume | 保留；UI 图标、Markdown、声音 |
| `@streamdown/code`、`@streamdown/mermaid`、shiki | 保留；聊天/笔记 Markdown 和 Mermaid 仍在使用，并非编辑器专属 |
| `react-material-icon-theme` | Q4 保留；附件/工具卡片 FileTypeIcon 仍使用 |
| 所有直接 `@codemirror/*`、`codemirror`、`@lezer/highlight`、prettier | 去掉；源调用在代码编辑器/源码 diff。笔记文本框和 MarkdownSourceHighlight 不依赖它们。锁文件中的传递项按实际剩余依赖图判断，不能机械删掉别的包所需项 |
| `@xterm/xterm`、`@xterm/addon-fit` | 去掉；终端专属 |
| JS/Rust Tauri api、dialog、opener、window-state | 保留各自实际使用项 |
| JS/Rust Tauri updater、process | 去掉；process 前端唯一业务调用是 updater relaunch，不能留下无效 capability |
| Rust global-shortcut、portable-pty、`vendor/portable-pty` | 去掉；分别只供快速输入和终端使用 |
| tauri/tauri-build、serde/serde_json、uuid、rusqlite | 保留；桌面/协议/SQLite |
| base64、png、arboard（含 Wayland 支持） | 保留；附件/图片/剪贴板 |
| ureq、url | 保留；Claude 用量、通用链接预览及必要 MCP URL，不因删除收件箱而全删 |
| toml | Q6 保留；MCP/Codex 配置 |
| sha2、unicode-normalization | 保留；Claude macOS keychain 账号路径仍用到 |
| open、libc | 保留；默认应用打开与 Unix 进程/系统能力 |
| notify-rust、objc2/block2/raw-window-handle/原生通知、windows-sys/Windows 通知 | 保留对应平台实际功能；去快速输入/PTY 独占 feature，不升级 |
| time | 去掉；上游直接业务调用仅 pi_usage |

锁文件只做应用包改名、移除直接项后的必要依赖图收敛；每次比对仍保留的依赖版本和来源。若发现原锁在目标平台无法解析或构建，先报告实际错误，不擅自升级解决。

### 8.2 配置和仓库文件

| 文件/目录 | 结论 | 依赖与处理 |
| --- | --- | --- |
| `package.json`、`package-lock.json` | 按保留依赖重新组装 | 新包名 `loci-desktop`；保留 dev/build/test/check/tauri，去 host、快输与原发布专用脚本；核对保留版本 |
| 根 `Cargo.toml`、`Cargo.lock`、`src-tauri/Cargo.toml` | 按保留依赖重新组装 | workspace 继续只有 src-tauri，去 portable-pty exclude/vendor；包/二进制 `loci`、库 `loci_lib`，去旧 repository/homepage，不虚构新的公开地址 |
| `vite.config.ts`、`vitest.config.ts`、`tsconfig*.json` | 保留、最小裁剪 | 只保留主 HTML 构建入口，移除 quickComposer；沿用原测试环境/严格 TS 规则 |
| `index.html` | 保留启动行为、改名/图标 | CSS 变量预初始化、启动渐隐继续保留，localStorage key/favicon/title 改名 |
| `quick-composer.html`、`host/`、`vendor/portable-pty` | 去掉 | 不创建替代空目录；构建/测试脚本和锁文件一起清理 |
| `src-tauri/tauri.conf.json` 及 linux/windows/stable overlays | 保留必要配置、改名 | productName/title/identifier、CSP、图标全部校准；去 updater block 和 updater artifacts；Linux category 不再用 DeveloperTool，可用 Utility；保留原窗口尺寸/装饰/透明设定 |
| `src-tauri/capabilities/default.json` | 保留、裁剪 | 去 updater/process 权限，去已消失的窗口专用能力；保留真实使用的事件/菜单/窗口/dialog/opener/window-state |
| `src-tauri/Info.plist`、`Entitlements.plist` | 保留必要平台项 | 目录访问用途文案改 Loci；不带旧 Assets.car 的图标绑定；保留原生开发运行所需设置 |
| `scripts/bump-version.mjs` | 保留、裁剪 | 只处理 Loci 的实际版本文件，不再处理 host/旧品牌 |
| `scripts/install-linux-deps-debian.sh`、`install-linux-deps-fedora.sh` | 不搬入本次交付 | 用作上游前置条件证据；当前目标不是这两个发行版，不增加未被验收的安装入口，不自动运行它们 |
| `scripts/test-remote-ssh.py` | 去掉 | remote/host 专属 |
| `.github/workflows/release.yml` | 去掉 | 原产品签名、更新 feed、下载、R2、host 分发工作流均不复制 |
| `.github/workflows/ci.yml` | 仅取保留检查部分 | 可复用 npm/tsc/fmt/clippy/test 检查；删 host job、旧产品包安装断言/发布相关 job，不配置新的发布服务 |
| 上游 issue 模板、CHANGELOG、截图、远程/Jira 文档、社区运营文件 | 不搬入 | 它们不属于运行外壳，且含已删除产品功能或上游链接；不沿用上游反馈/发布入口 |
| `.gitignore`、`.gitattributes`、`src-tauri/.gitignore` | 保留适用规则 | 忽略依赖、编译、日志与密钥等；去仅服务已删产物的专门规则 |
| `LICENSE` | 保留原 MIT 全文 | 必须保留 `Copyright (c) 2026 Nick`，不得替换原作者版权行 |
| `NOTICE` | 写明派生来源 | 写明来自上游及基线 revision、MIT、Loci 的裁剪改名；保留 Claude/Codex 商标归属说明，删未带入的 provider 标识清单 |
| `README.md`、`docs/extraction.md`、`docs/status.md` | Loci 文档 | 中文说明范围、运行/检查方式、批准结论、实际验证与未验证原因；不沿用旧品牌/服务地址 |

## 9. 改名、数据隔离与联网边界

以下改名必须在**第一次运行 Loci 之前**一起完成，而不是最后查漏再补：

| 位置 | Loci 结果 |
| --- | --- |
| 产品/窗口/启动页/菜单/通知/用途说明 | `Loci` |
| Tauri identifier / macOS 开发 bundle 标识 | `com.loci.desktop`；开发 bundle 使用独立 Loci 名称 |
| npm / Rust binary / Rust lib | `loci-desktop` / `loci` / `loci_lib` |
| 版本 | Loci 初始产品版本 `0.1.0`；依赖仍用上游锁定版本，二者不混淆 |
| 数据库 | Tauri 新 identifier 解析的 app_data_dir 下 `loci.db` |
| 用户资产/隔离账户 | notes 图片、backgrounds、project-logos、generated-images、provider-accounts 均只在 Loci app data 下 |
| localStorage/事件/性能标记 | `loci.*`、`loci:*` 及对应窗口/通知事件；不设置读取旧 key 的兼容 fallback |
| operator 环境变量 | `LOCI_APP_ENDPOINT`、`LOCI_APP_TOKEN`；删编排环境变量 |
| 子进程归属标记 | `LOCI_HARNESS_PARENT`，包括清理器和测试；避免误识别/结束原应用启动的 agent 进程 |
| macOS dev 环境变量 | `LOCI_DEV_APP_NAME`；其它应用自定义旧前缀逐一替换 |
| 临时附件/测试文件/日志/User-Agent | Loci 名称与路径；无旧产品别名 |
| 图标与 logo | 本地生成中性几何占位图标，不复制旧产品位图、icns/ico、Assets.car 或通知图标 |

不创建或运行任何 host，不检查、不迁移、不删除已安装上游的 host 数据目录。也不沿旧 identifier 查找数据库或迁移 WebView localStorage。Claude/Codex 自身的登录、配置和会话恢复目录属于 provider 的现有运行方式，与上游应用数据不是同一类；保留它们，且不自动迁入 Loci。

联网边界：

- 删除上游网站/下载/发布/求 star/反馈帮助链接、自动更新设置、签名公钥配置和发布注入机制；当前上游配置公钥虽为空，整个机制仍须去掉。
- 源码检索未发现独立遥测 SDK 或上报实现；实施后还需扫描实际搬入的前端、Rust、资源、依赖和工作流，不能把此初步结果当最终证明。
- 删除收件箱来源的 CSP 域名，账号头像来源按剩余真实消费者决定是否留用；不扩大 CSP 来绕过问题。
- 保留两家 agent 自身的模型服务/认证/MCP、Claude 用量查询、用户点击的普通 URL 或已有通用链接预览；这些不属于上游应用服务。不改变 provider 的既有服务地址。
- Q8 建议同时去掉 provider npm 版本检查/升级；不新增 Loci 更新服务、下载站点或遥测。

## 10. 新组合根和分步提交

这次涉及数百个源文件的取舍，明显超过 8 个文件。最大的工程风险是混合状态模型和组合根接线：删目录容易，漏掉一个 restore 字段、快捷键或 operator 提交回执就可能造成启动后失效。处理方式是按能运行的功能链提交，而不是按“先前端、后 Rust”提交半个应用。

### 10.1 组合根职责

重写 `src/app/App.tsx`，只组合现有视图和下面的具体 hook；不引入新状态库、依赖注入框架、通用插件层或未来功能占位接口。

| 目标文件 | 职责 |
| --- | --- |
| `src/main.tsx` + 原 `app/model/appLifecycle.ts` | 外观/CLI 路径/布局恢复启动、窗口退出协调；保持原初始化时序和 splash |
| `src/app/App.tsx` | 选择项目/设置/笔记等实际 surface，组合 shell 和 PaneTree；传递状态/动作，不直接容纳所有生命周期与协议分支 |
| `src/app/hooks/useAppWorkspace.ts` | 项目/会话/tab/pane 的 UI 状态，复用 layout/navigation，布局恢复/变更/跨窗口转移 |
| `src/app/hooks/useSessionRuntime.ts` | 两个 harness 绑定/流式事件/批准与问答/取消/空闲 detach，与原保存队列、in-flight、通知交接 |
| `src/app/hooks/useSessionSubmission.ts` | 输入、模型/权限、附件/笔记、有效 slash 命令、operator prompt 的准备，调用 registry，报告接受或失败 |
| `src/app/hooks/useAppCommands.ts` | 把保留的原生菜单事件和全局键盘映射到同一组现有动作；不让被删功能留下快捷键 |
| `src/app/hooks/useAppControl.ts` | operator 请求监听、request-id、窗口/会话路由、handleAgentApp 调用及 reply；复用会话提交和 workspace 动作 |

文件按首次真正用到时创建；不提前建立空 hook。实现中若出现不能放入这些职责的已有逻辑，优先放回原功能模块；若必须改变上述边界且影响批准范围，报告具体冲突。

```text
main / appLifecycle
        |
        v
App -- useAppWorkspace ----------------> shell + workspace/PaneTree
 |          |                                    |
 |          +---- sessions/store <--- SQLite <----+（快照）
 |
 +-- useSessionSubmission -> registry -> Claude/Codex -> Rust harness -> CLI
 |                              |             |
 +-- useSessionRuntime <--------+--- events ---+
 |       |
 |       +--> 转录 / 权限 / 提问 / 通知 / 保存队列
 |
 +-- useAppCommands -> workspace/submission 动作
 +-- useAppControl -> agent-app -> workspace/submission/notes 动作
                                  ^
                            Rust loopback / CLI
```

hook 通过 App 提供具体状态/动作；operator 不反过来导入 App，两个 provider 不导入 UI hook，避免新的循环接线。保留上游 feature/core 已有必要类型依赖，本任务不另做全仓分层重构。

### 10.2 提交顺序与每步完成条件

当前文档已经批准；不把“空仓库只有文档”宣称为可构建阶段。批准后从 P1 起，每个提交前均运行完整 `npm run check` 和 `npm run build`，并启动该阶段应用确认真实可操作；失败就修复，不先提交红色阶段。当前清单随第一个可运行提交进入版本记录。

| 阶段 | 英文提交信息 | 同步完成的内容 | 阶段可运行与验证结果 |
| --- | --- | --- | --- |
| P1 | `feat: assemble Loci desktop shell and local agent chat` | 最小 manifests/锁/配置/中性图标/许可/NOTICE；所有首跑隔离改名；原 shell、文件夹项目、标签/拖拽分栏；重写组合根；sessions/UI、两 provider/core、本地 Rust harness、基础设置、SQLite sessions/in-flight/layout；带入对应通用叶子和测试 | 应用能启动；选择文件夹、新建会话、切 Claude/Codex、输入/流式/批准/问答/任务计划链可用；会话/布局保存恢复。尚未带入的功能没有入口或占位区。Claude 未登录只显示已有登录/错误行为，不伪造通过 |
| P2 | `feat: restore notes search and desktop preferences` | 带入笔记/图片/标签、会话搜索、通知/静音/声音、项目外观、账号/用量，以及 Q6/Q7 已批准的 Skills/MCP/提醒；连接全部保留设置与快捷键 | 笔记 CRUD/@note、会话搜索跳转、外观变更和通知点击/静音可操作；完整 check/build；本次 Loci 数据在升级提交后仍可恢复 |
| P3 | `feat: enable scoped local operator control` | 裁剪并接通 control.rs/control_cli.rs、app 命令路由、环境 token/活跃 turn、Codex 回环许可、11 个 app actions、原 operator 气泡/工具动效；彻底解除快速窗口/编排依赖 | 通过真实启用 operator 的会话执行模型/会话/文件夹/笔记操作，包括创建分栏与草稿；未授权/已结束 turn 被拒绝；重复 request-id 不重复创建；完整 check/build |
| P4 | `test: verify extraction boundaries and document Loci status` | 对保留功能逐项实机验收、两 provider 真对话/权限/重启续聊、数据隔离/旧入口/品牌/联网审计；仅修复本次抽取导致的问题；整理 README 和中文 status | 所有自动检查绿；每项实际操作有记录；没验证的明确标未验证与原因。若目标环境/认证/桌面操作仍不具备，不能宣称最终完成 |

P1 是最小能真实使用的贯通阶段，内容较大，因为 shell、会话、provider 和存储无法各自作为空接线提交。P2/P3 只添加本次已批准保留的上游功能，不重新设计 UI。P4 不以“清理”名义引入新库、新功能或架构优化。

回退只回退 Loci 代码提交；不回退或操作上游仓库，不删除任何用户会话。Loci 初次启用后的 schema 增补应保证本次自身数据连续可读；必要的备份也只针对 Loci。没有部署、发布、推送上游或修改其它项目的步骤。

## 11. 验证计划和证据要求

### 11.1 每步自动检查

`npm run check` 必须保持下列检查的原强度，不用关闭 lint、弱化断言、跳过保留测试或宽泛 `any` 掩盖裁剪错误：

```sh
npm run check
npm run build
```

其中 check 包含：

```sh
vitest run
tsc --noEmit
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test
```

保留测试的取舍：

- core：保留 apply/applyBatch、auth、child 本地进程部分、jsonRpc、preview、registry、shellIntent、streamText；收窄 provider 参数矩阵，保留 ACP 测试，去 abort/SSE 专属测试。
- `fileAttachments.test.ts` 是混合测试，保留通用/Claude 断言，去 Pi/Grok/OpenCode/ACP；Codex 附件测试独立保留。
- Claude 的 Live/Protocol 测试及 Codex 的 Live/Protocol/ApprovalUi/Attachments/Questions/Elicitation 测试随实现带入；名字里有 Live 也只算 mock 协议回归。
- 保留 sessions/notes/layout/search/settings/notification 等实际功能测试及 Rust 模块内相应测试；混合 fixture 去掉移除字段，不能借调整 fixture 改变保留行为。
- 对本次新拆的组合接线补必要的行为验证：提交接收/失败、流式落盘与重启、批准/提问回传、模型切换上下文、operator 无授权拒绝/结束失效/重复 ID、分栏恢复。测试围绕用户可见结果和权限边界，不写只镜像新 hook 实现的测试。
- `git diff --check`、依赖版本差异、import/导出、Tauri invoke-handler 对照一起检查；类型通过不代表无死代码，因此还要沿调用方检查被删 feature 入口和仅剩自身测试引用的模块。

本阶段只检查文档，没有运行上面这些应用检查；目标仓库还没有 package.json 或 Rust manifest，不能声称检查通过。

### 11.2 实际桌面操作清单

在用户确认的目标环境运行 `npm run tauri dev`，记录日期、OS/架构/图形会话、CLI 版本、启动日志和操作结果。使用独立的 Loci 验收文件夹/会话/笔记，不在已有项目里制造测试文件。

| 范围 | 实际操作 | 合格证据 |
| --- | --- | --- |
| 启动/窗口 | 打开窗口、拖标题栏、最大化/还原、关闭/再打开；检查标题、图标、原窗口尺寸/透明/控件 | 有内容的真实 Tauri 窗口；无白屏/崩溃；日志无启动失败；记录目标平台外观 |
| 项目 | 选择一个普通文件夹，切换/返回/最近项目/归档恢复 | 无需 git 仓库；仍以路径/文件夹 identity 组织会话 |
| 标签/侧边栏/分栏 | 创建两个会话、拖拽 tab 重排、左右/上下分栏、调整比例、关闭/恢复、跨本地窗口转移 | 保留原拖拽/关闭动画；重启后布局和选中会话恢复，没有 editor/terminal 等空 pane |
| Claude 对话 | 发一条包含独特验证标记的消息，观察逐段/逐字流入；让 agent 执行一项会触发批准的无破坏工具调用；在 UI 确认 | 用户消息/真实流式回答/工具权限 UI/批准后的工具结果均可见；不能用预填 transcript 或 mock 代替 |
| Codex 对话 | 与 Claude 相同，独立完成一轮 | 同上，记录 provider session/thread ID 是否持久化；不记录认证 token |
| 权限拒绝/错误 | 在验收目录内再验证一次拒绝；触发可控错误或取消 | 拒绝没有执行，错误显示/取消/后续输入可恢复；如果所选工具没触发弹窗，就不算完成权限验收 |
| 重启与续聊 | 完成两家会话后退出进程并重新启动，打开同一会话，追问先前标记 | SQLite 转录/模型/任务/布局存在；provider 续接，能回答先前上下文；只在页面里看见历史不算恢复全通过 |
| 模型/账号 | 选择模型/设置/权限模式，按 Q9 切换 provider，再切回或取消待切换；使用已有登录入口 | 无静默丢上下文、无错误旧 provider；未登录有真实提示，无八家残留 |
| 提问/任务/计划 | 触发 provider 的用户提问表单，填选项和文本提交；请求任务进度和原生计划输出 | UI 渲染、回答回传、任务更新/计划显示与重启保持；若 provider 没产生对应事件，明确该项未验证 |
| 搜索 | 搜会话标题/唯一文本，打开命中会话并定位；测试会话内查找 | 不出现项目文件搜索页/编辑器跳转；命中仍正确 |
| 设置 | 改外观、缩放、聊天、两 provider 路径/模型、有效快捷键，重启 | 原控件/视觉保留、设置持久化；没有被删功能的设置项或搜索别名 |
| 笔记 | 新建/编辑/删除笔记、标签、粘贴图片、`@note` 加入会话、从 agent 读取/写入 | UI/SQLite/图片路径一致；重启可读；没有依赖文件编辑器的失效按钮 |
| 通知 | 应用失焦时完成一轮/触发权限或提问，点击系统通知返回会话；测试静音及 Q6 提醒 | 真实桌面通知送达/点击目标/静音生效，不仅 mock 通知 API |
| Skills/MCP（若批准） | 选择两家来源、查看已有技能、操作保留的现有表单、读取项目/个人配置范围、验证原生命令菜单 | 不出现其它 provider/Claude Desktop、外部代码编辑器；范围符合 Q7。实际外部 MCP 需要可用配置；没有就写未验证，不临时安装服务冒充完成 |
| operator | 各 provider 启用 `/operator`；执行 11 个动作中的读取、创建、草稿/发送、分栏、folders、notes；重复请求 ID、结束 turn 后再请求 | 命令实际修改/读取 Loci 状态、错误/回执正确；普通未启用会话无 app 授权；工作树/编排动作不存在 |
| 数据隔离 | 记录 Loci 实际 app_data_dir、DB/资产/临时路径/进程标记；关闭再开核对自己的数据 | 均属新 identifier/命名空间；不存在旧目录 fallback、迁移器或 host 启动路径；无需读取上游数据做对照 |
| 删除完整性 | UI 逐菜单/上下文菜单/快捷键/设置搜索，静态查依赖/类型/注册/测试/资产 | 删除功能无入口、无空页、无“暂不可用”占位、无残留 backend command；旧产品服务没有运行时访问路径 |

**真实对话前提**：在最终运行环境安装并登录两家 CLI、可访问它们的服务，并能操作 Tauri 桌面窗口。当前只核验 CLI 存在和登录状态，没有核验模型服务可达性。登录不能通过读取其它项目的 secret 解决；需要用户登录时明确指出是缺认证，而不是把 UI 测试降格成 mock。

### 11.3 残留扫描

按三层检查，不靠一次宽泛全文搜索假装证明功能消失：

1. **文件/依赖层**：被删除 feature、provider、Rust 文件、host/vendor、快输 HTML、旧图标均不存在；package/Cargo manifest 和锁依赖图没有孤立的专属依赖。
2. **调用/数据层**：检查 import/exports、provider 枚举、Tauri invoke 注册、CLI help/action 列表、菜单/快捷键/设置索引、序列化字段/SQLite schema、恢复/兼容分支、CSS 和测试 fixture。所有仍保留的命令/模块有真实调用方。
3. **品牌/联网层**：不区分大小写搜索旧产品名及旧服务域名，旧产品名只允许 LICENSE/NOTICE；搜索更新插件/签名 key/发布 feed/下载链接/遥测地址，人工核对剩余 URL 的消费者。检查文件名及资源名，不能只查文本。

扫描输入是受跟踪源文件和实际运行资源，不包括 `.git` 对象、node_modules/target 等第三方生成目录；否则依赖自带的词汇/仓库元数据无法作为应用是否保留功能的证据。本清单和 status 中对删除项的说明不是功能实现。原生协议字段和工具文本的限定见第 3 节；所有此类保留理由记录在 status，不能借它给死代码开口子。

### 11.4 最终 `docs/status.md`

使用简体中文，至少记录：实际带入/删除模块；与批准清单的差异及用户决定；每个阶段提交；自动检查的命令与结果；平台/CLI/模型/权限模式和真实操作证据；两家对话、权限和重启是否分别通过；operator 及数据隔离验证；未验证项和具体原因；尚需用户决定的问题。

不把“已实现”写成“已验证”，不把“macOS 通过”写成“Wayland 通过”，不把“mock Live 测试通过”写成“真实对话通过”。外部环境缺失导致的阻塞需要如实报告，不能为了结束任务改验收标准。

## 12. 初次清单阶段的审批记录

已完成：源目录/入出依赖盘点、47 个 Rust 模块逐项核对、两 provider/core/operator 贯通路径审阅、前置环境只读检查、冲突与分步计划整理；未发现上游仓库内 AGENTS.md/CLAUDE.md/.claude/rules 指令，已阅读其 CONTRIBUTING 和相关配置/README。

清单首次提交给用户时尚未执行应用源码搬运、安装、构建或启动；随后用户已批准实施。当前进度与实际验证记录以 status.md 为准。上游仓库保持不变。

用户已批准继续实施，并确认 macOS 和保留 ACP。按上述阶段持续推进；系统包安装许可、缺失登录信息或新的实质冲突按用户要求再询问。

## 13. 实施提交安排的校准

为了让第一个提交中所有已显示的入口都真实接通，原计划 P1–P3 的代码组装在首个可运行提交中贯通。首次完整检查通过：213 个前端测试文件、2394 项测试，以及 170 项 Rust 测试；生产构建通过。后续按实机发现的抽取问题和最终验收文档分别提交，每个提交仍执行完整检查与构建。功能范围没有扩大。

实施核对同时删除了确实没有保留调用方的模块/字段，例如仅供应用 Plan 的 intent、摘要/构建辅助、游戏气泡、文件-only 布局兜底、原生技能预热和未接线窗口搬运。原生计划卡改为沿用聊天 Markdown 展示完整正文，避免删除独立编辑器后只剩摘要而无法读取完整计划。
