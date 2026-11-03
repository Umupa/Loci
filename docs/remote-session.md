# 会话主控：状态流与远程接缝（v0.7 阶段一调研）

> 简体中文。2026-11-02，基线 `b2130dc`。只做调研和设计，不含代码改动。上层方案见 [remote-access 设计稿](remote-access.md)（v0.7 共享设计稿，尚未进仓库时以 `~/.herdr/runs/v7-shared/remote-access.md` 为准）。
>
> 本文回答：一轮对话的数据从哪来、存在哪、何时落库；要让主机窗口成为唯一驱动者并把状态推给远程客户端，接缝开在哪；风险和 P1 的工作量与拆分。行号以基线为准。

## 结论先行

1. **会话状态只有一个写入口。** 主窗口所有会话改动都走 `useSessionRuntime` 的 `updateSessions`（`src/app/hooks/useSessionRuntime.ts:81`）。`App.tsx` 里的 `setSessions` 只交给了 runtime（`src/app/App.tsx:98`、`:143`），其余 hook（submission、store、agents、idle detach、habits）拿到的都是 `runtime.updateSessions`。这里就是广播接缝：在它之后对比前后 `Session[]`，产出增量。
2. **块（Block）是不可变的。** 每次变化都换新对象（`src/features/sessions/data/sessionStore.ts:179` 的注释，`persistFingerprint` 就依赖这一点）。所以“哪些块变了”用引用比较就能算，O(块数)，不需要深比较。
3. **意图表现成就在。** 会话 UI 的所有用户动作都通过 `paneProps` 传给 `SessionPane`（`src/app/App.tsx:584-598`），回调几乎都是 `useSessionSubmission` 的返回值（`src/app/hooks/useSessionSubmission.ts:1364-1370`）。远程客户端把同一组回调换成“发意图”，主机端用同一张表分发，UI 组件可以原样复用。
4. **客户端不能跑同一套 hook。** `useSessionSubmission`、`useAgents`、`useAgentHabits` 在 `useEffect` 里会自己发起回合和写库（自动派发排队消息、到点续聊、退出后自动 Continue、归档旧回合、收文档进库）。客户端照搬会变成第二个驱动者。客户端需要一个只读镜像 store，加上转发意图的回调；渲染组件和 `features/sessions/model` 里的纯函数可以复用。
5. **最大的耦合不在会话流里，而在 localStorage。** 导师名单（含导师→会话 id 的映射）在主机 webview 的 localStorage 里（`src/features/agents/model/agent.ts:172`、`:178`），33 个非测试文件读写 localStorage（跟进行为、canvas MCP 开关、最近模型等）。远程端读不到，必须由主机经会话主控或命令下发。这超出“会话流”，但直接影响 P1 能否在客户端显示导师栏。

## 1. 现状：一轮对话从发送到写库

### 1.1 数据在哪

| 状态 | 所在 | 说明 |
| --- | --- | --- |
| 内存中的会话 `Session[]` | `Workspace` 的 `useState`（`src/app/App.tsx:98`）+ `sessionsRef`（`:99`） | 只放“在内存里”的会话：打开的导师对话、阅读器里的对话、仍在跑的会话、退出时被打断恢复的会话 |
| 未落盘的事件 | `useSessionRuntime` 的 `queued`（`useSessionRuntime.ts:47`） | 每帧（前台 rAF）或 100 ms（后台）批量应用（`src/app/model/harnessFlush.ts:10`）；审批、提问事件立即 flush（`useSessionRuntime.ts:128-135`） |
| 回合身份 | `generations` / `activeTurns`（`useSessionRuntime.ts:49-51`） | `beginTurn`/`isCurrentTurn`/`finishTurn`（`:218-239`），迟到回调靠 generation 丢弃 |
| 加载/移除的簿记 | `useSessionStore`（`src/app/hooks/useSessionStore.ts:21`） | `loadedSessionCache`、`openingSessionIds`、`removingSessionIds` 等；`loadSession`（`:52`）从库里取，`ensureSession`（`:77`）放进内存 |
| 导师名单与 `agent.sessionId` | localStorage `ROSTER_KEY`（`src/features/agents/model/agent.ts:172`），镜像到 `mentor_state_set`（`src/features/agents/model/mentorStore.ts:273`） | `useAgents` 用 `useSyncExternalStore(subscribeAgents, agentsSnapshot)` 读（`src/app/hooks/useAgents.ts:45`） |
| 较早的对话页 | SQLite `agent_transcript`，`useAgents` 的 `earlier`（`useAgents.ts:102`） | 显示时拼在 live 块前面（`App.tsx:604-605`） |
| CLI 协议状态 | 各 adapter 模块级变量 + `child.ts` 的 handler 表（`src/integrations/harness/core/child.ts:71`） | 审批 requestId、resume 状态都在 JS 里，只有这个窗口能回答 |

### 1.2 发送一条消息

1. Composer → `paneProps.onSubmit` = `submission.onSubmit`（`App.tsx:589`，`useSessionSubmission.ts:498`）→ `submitSession`（`:151`）。
2. 忙碌时：按 `followUpBehavior`（缺省读主机 localStorage 的 `loadFollowUpBehavior`，`src/features/settings/model/settings.ts:420`）进 `queuedMessages` 或 steer（`useSessionSubmission.ts:194-275`，`steerHarnessTurn` 在 `:247`）。
3. 空闲时：`rt.beginTurn`（`:302`）→ `commitSubmittedTurn` 用 `appendUser`（`src/integrations/harness/core/apply.ts:460`）插入用户块并置 `busy`（`useSessionSubmission.ts:310-325`）→ 异步段准备附件、prompt、学习上下文、导师上下文（`:338-421`）→ `sendHarnessTurn`（`:424`，`src/integrations/harness/core/registry.ts:205`）→ adapter 用 `spawnChild`/`writeChild`（`child.ts:259`、`:292`）调 `harness_spawn`/`harness_write`。
4. CLI 输出：Rust 用 `app.emit("harness-stdout", …)` 广播给所有窗口（`src-tauri/src/harness.rs:831`），`child.ts` 的桥按 sessionId 找 handler（`child.ts:88-99`）；adapter 解析成 `HarnessEvent`（`src/integrations/harness/core/types.ts:13`）→ `onEvent` → `enqueueEvent`（`useSessionRuntime.ts:123`）。
5. flush：`flushEvents`（`useSessionRuntime.ts:108`）对每个会话调 `applyHarnessEvents`（`apply.ts:26`），连续的 delta 合并后只换一次流式块（`apply.ts:37-48`、`patchStreaming` 在 `:728`）→ `updateSessions`。
6. 回合结束：`finally` 里 `stopStreaming`（`apply.ts:512`）→ `rt.finishTurn`（会触发完成通知，`App.tsx:145`）→ `saveAgentDocuments` → `persistSession`（`useSessionSubmission.ts:466-476`）。

### 1.3 何时落库

| 写入 | 触发点 | 说明 |
| --- | --- | --- |
| `session_upsert` | `upsertSession`（`src/features/sessions/data/sessionStore.ts:162`），每会话串行（`:140`） | 调用方：① runtime 的自动保存，`sessions` 变化后 350 ms（`useSessionRuntime.ts:244-254`、`:63-69`），用 `persistFingerprint` 去重（`sessionStore.ts:192`）；② 回合结束、stop、compact、draft 显式 `persistSession`；③ 空闲卸载前（`src/app/hooks/useIdleSessionDetach.ts:82`）；④ 关窗/退出（`src/app/model/appLifecycle.ts:225`、`:236`） |
| `agent_transcript_append` | `archiveOlderTurns`（`src/features/agents/model/agentTranscript.ts:62-78`），由 `useAgents` 的 effect 触发（`useAgents.ts:180-200`） | 不在视图里、空闲（`canArchive`，`agentTranscript.ts:46`）且回合数超限的导师对话，把旧回合写成页，再从 live 会话里删掉这些块 |
| `session_set_in_flight` | 只在退出/关窗时：`persistQuitState`（`appLifecycle.ts:236-262`）、`persistBootingResume`（`:264`） | 记录被打断的会话；下次启动 `loadResumedWorkspaceOnce`（`:164`）读回、`markTurnInterrupted`（`src/features/sessions/model/inFlight.ts:62`），`canAutoContinue` 的会话由 submission 的 effect 自动续聊（`useSessionSubmission.ts:1331-1344`）。`shouldWriteInFlightSnapshot`（`inFlight.ts:117`）目前只有测试在用 |

### 1.4 用户动作的入口

| 动作 | UI 入口 | 函数 |
| --- | --- | --- |
| 发送、steer、重发编辑、发草稿 | `onSubmit` | `submission.onSubmit`（`useSessionSubmission.ts:498`） |
| 停止 | `onStop` | `submission.stop`（`:1154`）；归档/删除用 `stopSessionWork`（`:1174`） |
| 权限审批 | `onApproval`；导师对话里换成 `agentHabits.approve`（`App.tsx:608`） | `useAgentHabits.ts:92` → 习惯运行的转发审批，或 `submission.approve`（`useSessionSubmission.ts:1185`）→ `respondHarnessApproval`（`registry.ts:313`）；隐藏窗口的审批 toast 也走 `submission.approve`（`App.tsx:679`） |
| 回答卡片/提问 | `onQuestionReply`、`onQuestionInteraction` | `submission.answer`（`:1189`，悬置问题会转成下一条消息）、`keepQuestionOpen`（`:1203`） |
| 切模型/参数/权限模式 | `onModelChange` 等 | `changeModel`（`:1090`）、`changeModelSettings`（`:1112`）、`changeRuntimeMode`（`:1118`） |
| 压缩上下文 | `onCompactContext` | `compact`（`:1208`） |
| 排队消息 | `onDeleteQueuedMessage` 等 | `:1239-1265` |
| 用量限制 | `onUsageLimit*` | `:1288-1301` |
| 旁问（BTW） | `onBtw*` | `onBtwSubmit`（`:794`）等 |
| 草稿 | `onSaveDraft`、`onRemoveDraft` | `:1124`、`:1142` |
| 新对话（重置导师）、删除导师 | 导师栏/详情 | `agents.reset`（`useAgents.ts:306`）、`agents.remove`（`:334`） |
| 打开导师对话 | 导师栏 | `agents.open`（`:240`）/ `agents.chat`（`:232`） |
| 归档、删除会话 | 阅读器、会话列表 | `store.archiveSession`（`useSessionStore.ts:138`）、`removeSession`（`:145`）；删除会弹主机原生对话框（`:102`） |

### 1.5 `loci-control-request` 如何由窗口回答

`control.rs` 在 127.0.0.1 上收请求，挂一个 `Pending { window, reply: mpsc::Sender }`（`src-tauri/src/control.rs:391-401`），`emit_to(window, "loci-control-request", …)`（`:411`；导师的 app 请求按 grant 找窗口，`:488`），阻塞等 `control_reply`（`:727`）。前端 `useAppControl` 监听（`src/app/hooks/useAppControl.ts:41`），按 namespace 分到 `runCommand`（`cli`）、`handleCanvasBridge`（`canvas`）、`handleAgentApp`（`app`），用 requestId 去重（`:27-40`），回 `control_reply`（`:69-75`）。外部命令挑窗口用 `pick_window`：优先 `main`（`control.rs:201`），没有就打开或显示窗口再等（`external_window`，`:314`）。

**这正是 Gateway 把“会话动作”交给主窗口所需的机制**：Rust 挂起请求 → 发事件给主窗口 → 窗口执行 → 回复。P1 照抄，不必新发明。

## 2. 接缝

### 2.1 广播什么

**单位：会话级 patch，块按 id 增量。** 不广播 HarnessEvent（客户端得重跑 `apply.ts` 并复制 adapter 状态，且 submission 在事件外还直接改会话，如 `appendUser`、`stopStreaming`、排队、标题），也不广播整份快照（长对话每帧几 MB）。

```ts
/** 主机进程内单调递增；epoch 是主控窗口这次加载的随机 id，窗口重载即换。 */
type SessionFeed =
  | { kind: "snapshot"; epoch: string; seq: number; sessions: Session[]; roster: Agent[] }
  | { kind: "patch"; epoch: string; seq: number; changes: SessionChange[] };

type SessionChange =
  | { id: string; removed: true }               // 离开主机内存（卸载、归档、删除）
  | {
      id: string;
      meta?: Partial<SessionMeta>;              // 变了的顶层字段（busy、title、model、pendingQuestion、queuedMessages…）
      unset?: (keyof SessionMeta)[];            // 被删掉的可选字段，JSON 表达不了 undefined
      order?: string[];                         // 块 id 顺序；只在增删/换序时发（appendUser、归档旧回合）
      blocks?: Block[];                         // 新块或被替换的块，整块发送
      append?: { id: string; text: string }[];  // 流式块只追加文字时发后缀
    };
```

计算方式（新文件 `src/app/remote/sessionFeed.ts`，纯函数，可单测）：

- 维护 `lastSent: Map<id, Session>`。对比当前 `sessionsRef.current`：会话引用相同跳过；块数组引用相同只比 meta；否则按 id 逐块比引用。新块 `text` 以旧块 `text` 开头且其余字段只变了 `streaming` 时，发 `append`。
- **节流而非逐次广播**：`updateSessions` 结束时（`useSessionRuntime.ts:87` 之后）调一个 `onSessionsChanged` 回调，主控 50 ms 内合并成一次 diff。对比的是“上次发出的状态”，所以自然合并了多帧，背压时也只需推迟下一次 diff。审批、提问不另开快车道：50 ms 对人足够，runtime 已经保证它们立即 flush 到 state。
- 发送前去掉只在主机有意义的字段：附件的 `previewUrl`（对象 URL，`src/features/sessions/model/session.ts:240`）、`data`。图片、附件路径由客户端经 Transport 的 `fileUrl` 取。

**序号与补齐：**

- `seq` 由主控窗口（JS）分配，快照带“已包含到哪个 seq”，因此快照和后续 patch 的先后不依赖 Rust 线程调度。
- Gateway（Rust）只保存最近 N 条 patch（建议按字节，约 8 MiB）的环形缓冲。客户端订阅时带 `{ epoch, seq }`：epoch 相同且缓冲覆盖 → 重放；否则 Gateway 向主控窗口要快照（走 2.3 的意图通道，`session.snapshot`）。
- 客户端丢弃 `seq ≤ 已应用` 的 patch；发现跳号就重新订阅。

**范围：** P1 广播主机内存里的全部非 `ephemeral` 会话，加一份精简的导师名单。主机内存里的会话本来就不多（打开的导师、阅读器里的、正在跑的）。客户端在看的会话通过“视图租约”留在主机内存（见 2.4）。

### 2.2 远程意图列表

意图名直接对应现有函数，参数照原签名（第一个参数都是 `sessionId`）。主机端用一张表分发，`paneProps` 也从同一张表取回调，保证两边一致。

| 意图 | 主机函数 | 需要额外处理 |
| --- | --- | --- |
| `session.submit` | `submission.onSubmit`（`useSessionSubmission.ts:498`） | 附件须已上传到主机（Transport 的 blob）；`followUpBehavior` 由客户端显式带上，不用主机的 localStorage 缺省；`onResendRejected`、`onSettled` 是函数，改成主机以事件 `session.resendRejected` 回给发起的客户端；返回值 `SubmissionAcceptance` 可能是 Promise，等它 resolve 再回复 |
| `session.stop` | `submission.stop`（`:1154`） | — |
| `session.approve` | `agentHabits.approve`（`useAgentHabits.ts:92`） | 必须走 habits 版本，否则习惯运行转发的审批会答错；它对非转发审批会落回 `submission.approve` |
| `session.answer` / `session.keepQuestionOpen` | `submission.answer`（`:1189`）/ `keepQuestionOpen`（`:1203`） | — |
| `session.changeModel` / `changeModelSettings` / `changeRuntimeMode` | `:1090` / `:1112` / `:1118` | 客户端的模型选择器要用主机的模型目录（`modelSource.ts` 调 `refreshHarnessCatalogs`，见第 3 节） |
| `session.compact` | `submission.compact`（`:1208`） | — |
| `session.saveDraft` / `removeDraft` | `:1124` / `:1142` | — |
| `session.queue.*`（delete/edit/editing/steer/resume） | `:1239-1265` | `editingQueuedMessageId` 是会阻止自动派发的全局状态，两台设备同时编辑排队消息时后者覆盖前者，P1 接受 |
| `session.usageLimit.*` | `:1288-1301` | — |
| `session.btw.*` | `btwSubmit`/`btwRetry`/`btwStop`/`btwDelete`/`btwModelChange` | — |
| `session.dismissNoteCard` | `App.tsx:594` 的内联函数 | 抽成具名函数放进同一张表 |
| `agent.open` | `agents.chat`（`useAgents.ts:232`） | 返回 sessionId；**不调用 `agents.open`**，它会切换主机窗口的视图 |
| `agent.reset` / `agent.remove` / `agent.create` | `agents.reset`（`:306`）/ `remove`（`:334`）/ `create`（`:257`） | 传 `confirmed: true`，确认框在客户端弹，不在主机弹（命令层已这样做：`src/app/hooks/useCommandContext.ts:49`） |
| `session.archive` / `session.delete` | `store.archiveSession`（`useSessionStore.ts:138`）/ `removeSession`（`:145`） | 删除会调主机的 `ask`（`:102`），要加一个 `confirmed` 参数绕过 |
| `session.view` | 新增：更新视图租约 | 见 2.4 |
| `session.snapshot` | 新增：Gateway 内部用 | 返回 `sessionFeed` 当前快照 |

较早的对话页（`agent_transcript_page`）、文档、笔记等是普通读命令，走 Transport 转发，不经主控。

### 2.3 意图怎么到主窗口

照搬 `loci-control-request`：Gateway 收到 `call("session.intent", …)` → 选主控窗口（`pick_window` 的规则，`control.rs:201`，没有就 `show_hidden_or_open_new` 再等）→ 挂 Pending → `emit_to(window, "loci-remote-intent", …)` → 前端新 hook `useSessionHost` 监听、查表执行、`invoke("remote_intent_reply", …)`。用独立事件名和独立 Pending 表，不复用 `control_reply`，避免把远程请求混进 CLI 的权限模型（CONTRIBUTING 要求 control channel 改动按安全变更处理）。

去重沿用 `useAppControl.ts:27-40` 的做法：每个意图带 `requestId`，主机记最近 256 个，断线重发不会发两次消息。

### 2.4 主机端还要改的地方

| 位置 | 现状 | 要改成 |
| --- | --- | --- |
| `keepIds`（`App.tsx:300`） | 只有主机窗口看着的会话 | 加上远程视图租约里的 sessionId，否则 250 ms 后 `useIdleSessionDetach` 会把客户端正在看的会话卸载（`useIdleSessionDetach.ts:67-74`） |
| `visibleSessionIds`（`App.tsx:164`）→ `useAgents` 归档 | 只看主机视图 | 同上，否则客户端正读着的旧回合会被归档掉（`useAgents.ts:183`） |
| `isForeground`（`App.tsx:140`） | 决定 flush 用 rAF 还是 100 ms | 不必改：节流在 50 ms 广播层；主机窗口隐藏时 100 ms flush 已够 |
| 完成通知 `onFinished`（`App.tsx:145`） | 主机弹系统通知 | P1 不变；客户端由镜像状态自己判断（`busy` 由真变假）弹本机通知 |

视图租约：客户端每 30 s 发一次 `session.view { ids }`，Gateway 断线时清掉该连接的租约，主控把所有连接的并集加进 `keepIds`。

### 2.5 客户端复用多少

**能直接复用：** `SessionPane`、`AgentSessionPane`、`AgentTranscript`、Composer、审批/提问卡片等全部渲染组件（它们只吃 `session` + 回调），`features/sessions/model` 里的纯函数（`sessionNeedsInput`、`agentState`、`sessionDisplayTitle` 等）。

**不能复用，要换成镜像：** `useSessionRuntime`（会启动 harness 桥 `useSessionRuntime.ts:258`、自动保存）、`useSessionSubmission`（effect 会自动派发排队消息 `:1266-1286`、到点续聊 `:1303-1330`、自动 Continue `:1331-1344`）、`useAgents`（effect 会归档、收文档、写预览和默认值 `useAgents.ts:79-216`）、`useAgentHabits`、`useIdleSessionDetach`、`useAppControl`。

客户端新增 `useRemoteSessions`：持有 `Session[]` 镜像，应用 feed，暴露和 `paneProps` 同形的回调（每个回调 = `remote.intent(name, args)`）。乐观更新 P1 不做：意图往返在局域网/relay 上通常 < 300 ms，主机状态回来就是结果，避免两份逻辑。

**结构问题：** `Workspace`（`App.tsx:94`）把上面这些 hook 和布局写在一个 700 行的组件里。客户端模式要么抽出一层“会话后端”接口（`{ sessions, paneProps(session), agents, states, earlierBlocksFor… }`）由本机实现和远程实现分别提供，要么另写一个精简的 `RemoteWorkspace`。建议前者，但只抽会话相关的部分，阅读器、设置等走 Transport 的命令转发，不进这个接口。

## 3. 风险与工作量

### 3.1 耦合深的地方

1. **导师名单在 localStorage。** `listAgents`（`agent.ts:172`）读 localStorage，`agent.sessionId` 也在里面。客户端没有这份数据就画不出导师栏、不知道该打开哪个会话。P1 方案：名单随 feed 下发（快照带 `roster`，`AGENTS_CHANGED` 事件触发一次 patch）；导师的增删改走意图。更彻底的做法是让名单以 Rust 为准，不在 P1 范围。
2. **设置在 localStorage。** 33 个文件。影响会话的有 `loadFollowUpBehavior`、`loadCanvasMcpEnabled`（`useSessionSubmission.ts:191`）、最近模型（`saveRecentModelChoice`）。会话意图里把客户端的选择显式带上即可；“远程改设置”需要单独的设置通道，建议列为阶段四的独立任务。
3. **副作用写在 effect 里。** 见 2.5。主机端没问题，客户端必须不挂这些 hook。这也意味着客户端代码路径不能“开个开关复用 App”，测试要专门覆盖“客户端模式不调用任何 `harness_*`”。
4. **主机侧原生对话框。** `useSessionStore.ts:102`（删除）、`agents.reset/remove` 的确认、`ProviderSignInDialog` 的 `loginHarness`。远程意图一律带 `confirmed`；登录 provider 只能在主机做，客户端显示“请在主机上登录”。
5. **模型目录在主机 JS 里。** `ModelPicker`/`modelSource.ts` 调 `refreshHarnessCatalogs`（`registry.ts`）探测本机 CLI。客户端要么用 `models.list` 命令（`src/app/commands/library.ts:221`）经主控取，要么把目录也放进 feed。P1 建议前者，加一个 `session.models` 意图。
6. **主机多窗口。** 每个窗口各有一份 `Session[]`，`harness-stdout` 广播给所有窗口、靠 handler 表认领（`child.ts:88-99`）。同一会话在主机两个窗口里同时打开时现在就没有互斥。P1 规定只有 `main`（或 `pick_window` 选中的那个）是主控；Gateway 只订阅它。
7. **主控窗口重载/关闭。** 重载会丢 JS 状态（运行中的回合按退出处理），epoch 改变 → 客户端取快照。窗口被销毁时 Gateway 像 `external_window`（`control.rs:314`）一样重开窗口。关窗到托盘是隐藏，不受影响。
8. **大块。** 工具预览（diff、文件内容）可以很大。relay 客户端→主机单条 ≤ 24 MiB，主机→客户端也应在 Gateway 帧层分块；feed 里单块超过 1 MiB 时可以只发截断版并标记，客户端按需读。P1 先测量，不先做。
9. **流式块整块重发。** `patchStreaming` 每批替换整块（`apply.ts:728`），`append` 优化覆盖了正文和推理；工具块的 `detail` 增长仍整块发，P1 接受。

### 3.2 P1 改动面（Gateway + 会话主控 + LoopbackTunnel）

前提：阶段一的 Transport 抽象和命令清单由其他任务完成，这里只算会话主控相关部分和它依赖的最小 Gateway。

| 文件 | 新/改 | 估计行数 | 内容 |
| --- | --- | --- | --- |
| `src/app/remote/sessionFeed.ts` + test | 新 | 180 + 220 | diff、apply、节流无关的纯函数；`apply(diff(a, b), a) == b` 的性质测试 |
| `src/app/remote/sessionIntents.ts` + test | 新 | 120 + 120 | 意图表类型；由 submission/agents/habits/store 组装；参数校验 |
| `src/app/hooks/useSessionHost.ts` + test | 新 | 180 + 200 | 主控：监听 `loci-remote-intent`、执行、回复；节流广播；视图租约 |
| `src/app/hooks/useSessionRuntime.ts` | 改 | ~10 | `updateSessions` 后调 `onSessionsChanged` |
| `src/app/hooks/useSessionStore.ts` | 改 | ~10 | 删除带 `confirmed` |
| `src/app/App.tsx` | 改 | ~40 | 挂 `useSessionHost`；`keepIds`/`visibleSessionIds` 并入租约；`paneProps` 改从意图表取回调 |
| `src/app/hooks/useRemoteSessions.ts` + test | 新 | 200 + 200 | 客户端镜像 store 与回调 |
| 客户端工作区（抽会话后端接口或 `RemoteWorkspace`） | 新/改 | 250–400 | 视方案而定，见 2.5 |
| `src-tauri/src/remote/gateway.rs` | 新 | 350 | WS 帧（call/result、subscribe/event）、白名单查表、意图 Pending、feed 环形缓冲与扇出 |
| `src-tauri/src/remote/session_master.rs` | 新 | 150 | `remote_session_publish`、`remote_intent_reply`、主控窗口选择与 epoch |
| `src-tauri/src/remote/tunnel.rs`（trait + `LoopbackTunnel`） | 新 | 150 | 本机 WS 监听或进程内通道，供两个窗口互连 |
| `src-tauri/src/lib.rs` | 改 | ~15 | 注册命令与状态 |
| Rust 测试 | 新 | 200 | 环形缓冲、补齐/快照判定、Pending 超时与窗口关闭 |

合计约 2,800–3,000 行，其中测试约 1,100 行。改动现有文件的部分很小（约 75 行），风险集中在新文件。

## 4. P1 任务拆分

**T1 会话 feed（纯前端，可最先开始）**
- 目标：`sessionFeed.ts` 的 diff/apply、`append` 优化、附件字段清理；`useSessionRuntime` 加 `onSessionsChanged`。
- 验收：性质测试覆盖流式、增块、`appendUser`、归档删头部块、字段删除、会话移除；对 2,000 块的会话做一次 diff 的耗时记录在测试注释里（目标 < 2 ms）；`npm run check` 通过，现有行为不变。
- 范围：`src/app/remote/sessionFeed.ts`、`useSessionRuntime.ts`。

**T2 主机会话主控（依赖 T1 的类型）**
- 目标：`sessionIntents.ts`、`useSessionHost.ts`；`App.tsx` 接入，`paneProps` 从意图表取回调；`keepIds`/`visibleSessionIds` 并入视图租约；删除带 `confirmed`。
- 验收：单测里用假事件驱动每个意图，结果与直接调 UI 回调一致；重复 `requestId` 只执行一次；租约中的会话不被卸载、不被归档；本机 UI 行为不变。
- 范围：`src/app/remote/sessionIntents.ts`、`src/app/hooks/useSessionHost.ts`、`App.tsx`、`useSessionStore.ts`。

**T3 Gateway 与 LoopbackTunnel（Rust，可与 T1/T2 并行）**
- 目标：`remote/gateway.rs`、`remote/session_master.rs`、`remote/tunnel.rs`；意图 Pending 按 `control.rs` 的模式；feed 环形缓冲、按 `{epoch, seq}` 补齐或取快照；白名单接阶段一的命令清单（清单未合入时先只放会话意图和 `agent_transcript_page`）。
- 验收：Rust 单测覆盖补齐、缓冲溢出改取快照、epoch 变化、主控窗口关闭时挂起请求得到错误；`cargo clippy -D warnings` 通过。
- 范围：`src-tauri/src/remote/*`、`lib.rs`。

**T4 客户端镜像与端到端（依赖 T1–T3 和 Transport）**
- 目标：`useRemoteSessions.ts`；客户端工作区复用 `SessionPane`/`AgentSessionPane`；导师名单随 feed 下发；LoopbackTunnel 下两个窗口互连。
- 验收：Loci Dev 开两个窗口，一个连另一个：在客户端发消息、停止、回答审批和提问卡片、切模型，主机窗口同步可见；断开再连能补齐；客户端模式下没有任何 `harness_*` 调用（测试断言）。
- 范围：`src/app/hooks/useRemoteSessions.ts`、客户端工作区相关文件。

T1 和 T3 可以并行；T2 在 T1 的类型定下后开始；T4 最后。

## 未覆盖

- 没有实机测量 feed 的带宽和 diff 耗时，第 3.2 节的数字是估计。
- 习惯运行（`useAgentHabits`）的隐藏会话不广播，只广播它转发到导师对话里的审批块；没有逐一核对习惯的其他交互。
- 设置、阅读器、笔记、PDF 等非会话状态的远程化不在本文范围。
