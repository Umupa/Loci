# fx 接入调查

2026-11-17。当前只完成协议调查与接入计划，尚未实现 Swift 驱动。

## 前置条件

任务要求复用 `herdr/a2-core` 的 Grok ACP 实现，不另写传输、会话或事件解析。开工检查时，该分支停在 `709fa01`，`Sources/LociAgents` 只有 Pi，没有 ACP/Grok。等共用实现提交后，先合并该分支，再按它实际提供的接口接 fx。

本机登录 shell 的 PATH 和旧版解析器列出的常见安装位置均未找到 fx。没有真实协议录音，也未运行真实集成测试。旧版测试中的手写消息不作为真实 fixture。

## 已有协议依据

只参考 `main` 中以下文件的协议与行为，不沿用其结构：

- `src/integrations/harness/providers/fx/fx.ts`：启动、初始化、会话、模型、模式、权限、中断。
- `src/integrations/harness/providers/fx/fxProtocol.ts`、`fxProtocol.test.ts`：文本块、选项、事件、模型配置。
- `src/integrations/harness/providers/fx/fxTool.ts`：旧版从 fx 0.0.5 抓包总结的工具输出差异。
- `src-tauri/src/harness.rs`：程序识别与凭据环境变量传递。

| 环节 | 旧版使用的协议 | 原生版接入决定 |
|---|---|---|
| 启动 | `fx acp`；指定模型时追加 `--model <原生模型 ID>` | 可执行文件、环境、工作目录、launcher、clock 从外部传入，形状对齐 `PiDriver` |
| 初始化 | `initialize`，`protocolVersion: 1`，`clientCapabilities.fs.readTextFile/writeTextFile: false`、`terminal: false` | 交给共用 ACP；只声明实际支持的客户端能力 |
| 新会话 | `session/new`，`{cwd, mcpServers: []}` | 保存返回的 `sessionId` 为 `.fx` 的 `SessionHandle` |
| 恢复 | 先 `session/resume`，`{sessionId}`；失败后尝试 `session/load`，`{sessionId, cwd, mcpServers: []}` | 验证当前 fx 支持哪条路径；恢复失败应报告 `.sessionNotFound`，不能静默新建并丢失上下文 |
| 模型 | 启动参数；另有 `session/set_config_option`，`{sessionId, configId, value}` | 首次接入优先使用启动参数；只有真实录音证明恢复后需要额外设置，才加差异 |
| 权限模式 | `session/set_mode`，`{sessionId, modeId}`；有 `ask` 和 `code` | `.ask` 对应 `ask`，`.full` 对应 `code`；必须用真实权限请求确认行为 |
| 发消息 | `session/prompt`，`{sessionId, prompt: [{type: "text", text}]}` | 当前接口只发文本；请求回复标记本回合结束 |
| 流式消息 | `session/update` 的 `agent_message_chunk`、`agent_thought_chunk` | 复用 ACP 映射到 `.text`、`.thinking` |
| 工具 | `tool_call`、`tool_call_update`、`tool_call_content_chunk` | 复用共用事件和工具状态；缺失输入不伪造参数 |
| 权限请求 | `session/request_permission`，含 `toolCall` 与 `options` | 复用共用 `PermissionRequest`，按选项的 `kind` 理解角色，保留原始 `optionId` |
| 权限回复 | `{outcome: {outcome: "selected", optionId}}` | `.ask` 等待 `answer`；取消、失效答案与中断交给共用 ACP 的处理 |
| 中断 | `session/cancel` 通知，`{sessionId}` | 等待回合结束，清理待答权限，验证下一轮能继续；超时处理复用 ACP |

旧版对 `session/resume` 和 `session/load` 失败后会新建会话，且普通对话总用 `code` 模式并自动允许残留权限请求。这些是旧界面策略，不能直接成为原生版合同：`AgentSession` 和 α2-S6 要求 `.ask` 下由用户决定，恢复失败也必须可见。

旧版初始化超时为 12 秒，会话建立为 45 秒，控制请求为 15 秒。它把初始化时的 `needs access`、`AI Gateway`、`API key`、`Keychain` 错误解释为凭据不可读，提示 `fx login` 或 `fx setup`。原生版先保留 provider 原始错误；是否需要专门提示和超时差异，待真实执行确认。

旧版透传 `AI_GATEWAY_API_KEY`、`FX_AI_GATEWAY_API_KEY`、`VERCEL_OIDC_TOKEN`。驱动复用注入环境，不自行读 Keychain、不打印凭据。程序探测还要区分 Vercel coding agent 与同名 JSON viewer；该问题属于现有 CLI 探测任务，本任务不实现另一套探测器。

## 需要录音确认的差异

旧版记载 fx 工具可能只给动名词标题（如 `Reading`、`Running`）、`kind`、状态和文本结果，没有 `rawInput`、`locations` 或 diff。命令结果还可能带 `command_result` / `commandResult`（`command`、退出码），正文形如 `exit_code=0` 加 `<stdout>`；读文件结果形如 `<path>` 加 `<content>`。接入时先检验共用 ACP 能否如实呈现这些字段，只有确实缺少调用方所需结果时才加 fx 局部归一化，不搬旧版展示用的整套字符串推断。

旧版支持下划线和短横线两种权限选项 ID，如 `allow_once` / `allow-once`。不能用客户端猜出的 ID 回答；测试应覆盖选项 `kind` 与 ID 不同的情况。

## 实施与验收顺序

1. 核对共用 ACP 的启动配置、恢复策略和模式设置入口。fx 的启动和实际差异放在 `LociAgents` 里新建的 Fx 文件夹；不新增注册表、工厂、协议层。`.fx` 已存在于 `Runtime`，无需改它。
2. 先写调用方可见行为测试，再实现 `FxDriver`。测试复用 `RecordingLauncher`、`ScriptedLauncher`、`TurnPipe` 的现有方式，按真实录音验证启动参数、流式回复、工具结果、权限允许与拒绝、停止后继续、恢复与恢复不存在的会话。
3. 增加默认跳过的 `FxLiveTests`；建议以 `LOCI_FX=<程序路径>` 打开，以 `LOCI_FX_RECORD=<目录>` 保存录音。所有文件操作都在临时工作目录，绝不使用 `~/Loci`。fixture 放在 `Fixtures` 下新建的 Fx 文件夹，沿用 `launch`、`to`、`from`、`close`、`exit` 的 JSONL 格式，并脱敏本机路径与凭据。
4. 在已安装且已登录的 fx 上小额跑一次，优先录 `reply`、`tool`、`permission-allow`、`permission-deny`、`interrupt`、`interrupt-asking`、`resume`、`resume-missing` 和 `bad-model`。无法稳定触发的边界另用明确标为 `synthetic-` 的 fixture，不能冒充抓包。
5. 对照 α2-S6 检查流式与一律完全权限下的工具执行；对照 α2-S7 检查停止与续聊。会话恢复提供 α2-S8 的驱动层证据，不能据此声称应用的对话持久化也已验证。设置探测与 provider 选择由相应任务接线。
6. 有用户可见能力时再更新 `CHANGELOG.md`。合并最新 `main`，运行 `script/check`，报告真实测试结果、差距和共用层改动后提交。

本次未增加 Swift 文件、fixture、依赖或共用层改动；没有可交付的 fx 运行能力。
