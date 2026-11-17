# Hermes ACP 接入结论

2026-11-17 核对并实现。共用 ACP 的离线测试通过；尚未录到 Hermes 真实协议。

## 依赖与证据

- 已合并 `herdr/a2-core` 的 `e6e83aa`，Hermes 直接复用 `Sources/LociAgents/Acp/`，不另写协议实现。
- 旧版依据：`main` 下 `src/integrations/harness/providers/hermes/` 的 `hermes.ts`、`hermesProtocol.ts`、`hermesProtocol.test.ts`、`hermesLive.test.ts`。后者使用 mock，不是真实集成录像。
- 本机 PATH、`~/.local/bin`、`/opt/homebrew/bin` 和 uv tools 中未找到 Hermes，常见的 `~/.hermes`、`~/hermes-agent` 目录也不存在。没有安装 CLI 或改动凭据；真实 fixture 与集成测试尚未完成。

## 旧版确认的协议行为

| 环节 | Hermes 行为 |
|---|---|
| 启动 | 可执行文件由外部传入，参数为 `acp`，工作目录取会话配置 |
| 初始化 | JSON-RPC `initialize`，`protocolVersion: 1`；客户端不提供文件读写和 terminal |
| 新建 | `session/new`，参数 `cwd`、`mcpServers: []`；返回 `sessionId` |
| 模型 | `session/set_model`，参数 `sessionId`、`modelId`；未指定时保留 Hermes 默认模型 |
| 权限 | `session/set_mode`；当前模型里的 `.ask` 对应 `default`，`.full` 对应 `dont_ask` |
| 发送 | `session/prompt`，参数 `sessionId`、`prompt: [{type: "text", text: ...}]` |
| 流式与工具 | `session/update`，旧版直接使用 Grok 共用的 ACP 事件与工具解析 |
| 审批 | `session/request_permission`；响应 `outcome: {outcome: "selected", optionId: ...}`，必须使用服务端给的选项 ID |
| 中断 | `session/cancel` 通知，参数 `sessionId`；撤销尚未回答的审批 |
| 恢复 | `session/load`，参数 `sessionId`、`cwd`、`mcpServers: []`；加载时不重复展示历史通知 |

旧版还接受 `session_id` / `id` 和 `current_model_id` 字段，支持 `accept_edits` 模式。当前 `Mentor.Permission` 只有 `.ask` 和 `.full`，不新增权限档位。字段兼容是否需要保留，以真实录像为准。

旧版恢复失败会新建会话；原生 `AgentError.sessionNotFound` 已有明确合同，接入时应报告恢复失败，不能默默丢失上下文。`SessionHandle.provider` 必须是 `.hermes`，不能泄漏成 `.grok`。

普通 provider-health warning 不等于鉴权失败。保留真实错误；需要登录指引时使用旧版的 `hermes model`、`hermes acp --check`，不把含 `credential` 的 warning 一律提升为失败。

旧版会读取后台 `delegate_task` 的 manifest 和 transcript 再补发提示。这涉及子会话委派，设计中已推迟；本次不搬文件轮询，也不在 Agents 中增加磁盘读取。

## 实现

`Sources/LociAgents/Hermes/HermesDriver.swift` 只提供 `AcpDriver.hermes` 的配置：provider、`acp` 参数、恢复方法、权限模式，以及通过 ACP 选模型。可执行文件、环境、启动器、时钟仍从外部传入。

共用 `AcpDriver` 以 `resumeMethod`、`setModel`、`mode` 表达差异，默认保持 Grok 的路径。`setModel` 与 OpenCode 使用同一份模型选择实现。模型与权限设置失败时关闭进程并返回原始错误，不暴露未配置完成的会话。

测试先暴露两处问题再修复：`AcpChannel` 在加载期间不转发历史通知，取消这期间的审批并拒绝未支持的客户端请求；会话配置完成后才开始转发。`AcpDriver` 在切换模型后取所选模型的上下文容量，未知容量保持为空。

测试在 `Tests/LociAgentsTests/Hermes/`；fixture 在 `Fixtures/Hermes/`。`synthetic-` 文件明确标为按旧版合同构造的用例，不是真实录音。`HermesLiveTests` 默认跳过，以 `LOCI_HERMES` 指定 CLI，`LOCI_HERMES_RECORD` 指定录制目录；不会访问 `~/Loci`。

## 验证范围

| 场景 | 需要的证据 |
|---|---|
| α2-S6 流式回复、工具与审批 | 构造用例验证回复增量、工具结果、允许/拒绝的选项 ID 和结果、模型/权限设置、配置失败 |
| α2-S7 停止后继续聊 | 构造用例验证执行中和审批中取消、审批关闭、唯一末尾事件、同一会话继续发送 |
| α2-S8 恢复上下文 | 构造用例验证 `session/load`、句柄保持、加载历史不混入新回复；加载失败不新建会话 |
| α2-S10 选择 CLI | 验证驱动 provider 为 `.hermes`，错误 provider 的句柄在启动前拒绝；Host 与设置交互未验 |

以上不能替代真实 Hermes 验证。本机缺少 CLI，真实流式、工具、审批、中断与恢复均未跑；后续应按 fixture 目录说明录制、脱敏并核对当前 Hermes 版本，缺失会话的实际错误形状也要据此确认。共用 Grok 的真实录音回放继续通过。整版界面与持久化验收留给统一集成测试。
