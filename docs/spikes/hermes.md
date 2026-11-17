# Hermes ACP 接入准备

2026-11-17 核对。尚未实现驱动，也未录到真实协议。

## 依赖与证据

- `herdr/a2-core` 当前为 `709fa01`，`Sources/LociAgents` 只有共用接口和 Pi，没有 ACP/Grok。等它提供 ACP 后再合并，绝不另写协议实现。
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

## 恢复工作时的顺序

1. 检查并合并 `herdr/a2-core`。先读其 ACP/Grok 驱动及测试，确认它承载启动参数、provider、模式差异的实际方式，不预先设计适配接口。
2. 先写 Hermes 行为测试，再在 `Sources/LociAgents/Hermes/` 加启动与差异配置，沿用 ACP 会话、事件、权限、中断、恢复实现。共用层若确实容纳不了上述差异，仅做最小修改并说明原因。
3. CLI 可用时，用临时工作目录录制真实双向 JSONL，沿用 Pi 的 `launch` / `to` / `from` / `close` / `exit` 格式及 `ProgramLauncher` 注入方式。保留请求和通知顺序，脱敏路径、会话 ID、服务地址和模型配置；不把 mock 数据标成真实 fixture。
4. Hermes 测试与 fixture 放在各自的 Hermes 目录。新增默认跳过的真实测试，以 `LOCI_HERMES` 指定可执行路径，`LOCI_HERMES_RECORD` 指定录制目录；`script/check` 只回放，不依赖 CLI 或网络。
5. 合并 `native`，运行 `script/check`，记录实际覆盖范围；实现产生用户可见变化时补 Unreleased。按步骤提交，更新 run 目录中的报告。

## 待验证场景

| 场景 | 需要的证据 |
|---|---|
| α2-S6 流式回复、工具与审批 | 回复增量、工具开始到结果、允许后执行、拒绝后不执行；`.ask` / `.full` 的实际模式请求 |
| α2-S7 停止后继续聊 | 执行中和审批中取消，审批关闭，每轮恰有一个末尾 `.ended`；同一会话可再发消息 |
| α2-S8 恢复上下文 | 关闭进程后 `session/load` 仍记得前一轮；缺失会话报错，历史通知不重复进入新回合 |
| α2-S10 选择 CLI | 驱动 provider 为 `.hermes`；设置与 Host 的选择、发现和持久化需整版集成后验证 |

以上是待验证计划，不代表原生版已支持这些行为。真实录像还要覆盖启动失败、未知模型、进程退出和不同 provider 的恢复句柄；通用 ACP 错误行为沿用核心测试，Hermes 仅补真实差异。
