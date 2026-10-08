# 长时间运行稳定性：验证与修复

2026-10-08，基线 `ebdfc21df85b16a703aa37e02db3796865f17181`。
环境：macOS 26.5.1 / arm64，Node 24.19.0，Cargo 1.97.1。

测试使用合成会话和故障注入，不读写用户数据库，不调用真实 provider。前两批提交为 `b2291ff`、`5f510bc`；以下按批次记录改动的证据和验证边界。

## 第三批：慢写入与旁问状态

本批验证基线为 `5f510bc`。

| 场景 | 修复前 | 修复后 |
| --- | --- | --- |
| 同一快照在保存完成前被请求 100 次 | 100 次实际 upsert | 共用在途保存，实际 upsert 1 次 |
| 首个写入阻塞期间发生 30 次修改，每次跨过自动保存周期 | 排队 30 个快照，最终写入 30 次 | 阻塞期间只提交首个；完成后读取最新状态，共写入 2 次 |
| 已保存 A，写入 B 尚未完成，随后恢复 A | 因 A 命中旧缓存而漏写，最终存储可能停在 B | 比较最后排队的快照，显式按 B → A 保存 |
| 修改旁问模型或删除旁问 | ref 已改变，但 React state 未提交 | 统一由 runtime 更新 ref 和 React state |
| 旁问连续输出 100 条 delta | 原路径逐次直接保存，且界面可能不更新 | 最终答案完整进入 React state，显式 flush 只写入一次 |

重复保存判断现在同时考虑已完成和最后排队的写入。只复用队尾的相同快照，不跨过不同的显式保存；`sessionStore` 的 FIFO、删除和归档边界没有改动。

后台自动保存遇到同一会话仍有写入时，只保留待保存 ID，完成后再读取最新会话；不提前复制每个中间版本。显式 flush 仍可排入最新快照并等待。失败会保持 dirty 并报告错误，不自行启动无限定时重试；组件卸载后不再启动后台保存计时器。

旁问的两个更新函数原先先赋值 `sessionsRef.current` 再调用 runtime 的 setter。setter 因新旧引用已经相同而提前返回，绕过 React state。这两个入口现在只调用统一 setter，由常规 350 ms 自动保存合并流式更新；主动保存/关闭仍能等待最新状态。

红绿证据：相同快照重复保存、恢复旧值、旁问 React 状态三项先失败；慢存储积压另有独立失败记录。补充通过了保存失败不循环、显式 flush 等待新快照、100 条旁问 delta 最终完整保存等保护场景。

浏览器检查使用新的 `scripts/acceptance/stability/state.html`：真实 runtime/submission hooks 和 AgentTranscript，Tauri 官方 mockIPC 与合成 provider 替身。通过 UI 依次提问、输出两段文字、触发父组件刷新、完成、改模型、删除、再刷新；流式/完成内容可见，最终保存结果一致，删除后界面和存储均无该旁问，运行期错误为 0。没有把替身运行算作真实 provider 或原生 WebView 验收。

最终验证：3,214 项 Web、208 项 Rust、6 项稳定性专项通过；生产构建、夹具生产构建、TypeScript 和夹具类型检查通过。源代码扫描确认 submission 中不再直接赋值 sessionsRef，更新归属 runtime；其他即时保存保留给主回合结束、草稿和压缩完成等路径。

证据保存在 `output/stability/round3-*`。浏览器重跑方式：按下文命令构建并启动夹具后，打开 `http://127.0.0.1:1439/scripts/acceptance/stability/state.html`。本批仍未完成原生两小时长测，也未覆盖真实磁盘故障、跨窗口真实 IPC 或所有 provider 缓存。

## 第二批：提交后的继续优化

本批验证基线为 `b2291ff`。

| 新验证场景 | 基线结果 | 优化后 |
| --- | --- | --- |
| 万条消息的会话，父组件无关更新 100 次 | 重算保存指纹 100 次 | 0 次；初始化改为惰性执行 |
| 保存并移除 1000 个会话，外加初始会话 | 保存指纹和轮次表分别留下 1001 项，随循环增长 | 每 250 次检查，两张表均为 0 |
| 移除后重新打开同一会话 | 被移除的旧轮次仍被判定 current | 移除即失效，新轮次使用单调递增 token，不复用旧身份 |
| 窗口关闭前保存失败 | finally 仍调用原生关闭/隐藏 | 错误向上传递，保留窗口，允许重试 |
| 真实生命周期函数中的会话或布局写入失败 | 默认 unload 模式吞掉错误 | 主动关闭/重新加载使用严格 transition 模式 |

`useSessionRuntime` 随会话移除清理保存指纹、轮次、活跃 turn、绑定、待处理事件和保存 ID；迟到写入不再为已移除会话重新建立保存记录。尚未完成的保存 Promise 仍被跟踪，关闭时可以等待它。

窗口关闭使用 `persistAndCloseWindow` 串联保存与原生命令。主动关闭和重新加载的保存失败会显示在现有错误通道；无法等待的 `beforeunload` 才使用 best-effort 模式。空闲窗口的严格 transition 不清空其他窗口的 in-flight 记录，进程 quit 的原有行为保持独立。

回归均在修复前实际失败：runtime 两项、记录保留一项、窗口关闭两项、实际生命周期写入失败两项。正向对照覆盖正常关闭、隐藏、重试成功和其他窗口记录保护。

最终验证：3,207 项 Web 测试、208 项 Rust 测试、6 项稳定性专项通过，TypeScript、fmt、Clippy、生产构建及测试夹具类型检查通过。新增窗口检查在原生 IPC 边界使用替身，未算作真实 macOS 关闭操作或两小时长测。

记录保留测试观测真实 runtime Map 的项数，并清空测试 spy 自身的调用记录；没有据此宣称整进程 RSS 或所有对象都已归零。100 次无关更新的首组夹具耗时为 40.6 ms → 6.3 ms，后续运行有波动，因此稳定验收采用指纹计算次数，不用该耗时作为真实交互延迟承诺。

证据在 `output/stability/round2-*`：记录保留/重复计算的红绿运行、窗口与实际 transition 的故障回归、完整检查及构建日志。原生长测、真实 provider 子进程、其他模块缓存和多窗口实机操作仍待继续验证。

## 第一批修复后的状态

- 空闲会话现在等待保存成功才进入缓存和释放 provider。失败时保留原会话并报告错误；不因无关的后台更新反复重试同一个失败快照，重新打开后关闭或编辑会话可再次尝试。
- 保存完成后重新核对会话身份和当前状态；重新打开、开始执行、保护中、换成新快照或组件已卸载，都不会被旧写入释放。新快照会另行保存。
- 失败写入重新加入 runtime 的待保存集合。退出前再次 flush 会重试，持续失败会继续抛错，交回现有退出保护；不会把清空队列误当作保存成功。
- 关闭项目且保留数据时，同样等待保存确认，只移除已保存的原快照。关闭标签/分栏的提前保存也会报告错误。
- 用户消息测量尊重现有 `content-visibility:auto`，跳过隐藏/未渲染内容；内容重新渲染时通过 `contentvisibilityautostatechange` 和 ResizeObserver 补测。没有新增虚拟列表或改变历史内容。
- 修订两个过时的画布测试：传入实际 Popover anchor，并验证两个可选画布按钮及选择结果，而非断言旧的 dialog 容器。
- 提交前补齐快速导航边界：失败快照按导航轮次限制重试，快速打开/关闭不再依赖 250 ms 计时器是否看到可见状态。导航发生后才到达的旧写入失败，也会给当前快照一次新的保存机会。

浏览器 API 的语义已核对：[checkVisibility](https://developer.mozilla.org/en-US/docs/Web/API/Element/checkVisibility)、[contentvisibilityautostatechange](https://developer.mozilla.org/en-US/docs/Web/API/Element/contentvisibilityautostatechange_event)。不支持 checkVisibility 的环境保留原测量行为；仍需原生 WebView 验收。

### 回归证据

新断言先在未修复代码上实际失败，再运行修复后的代码：

| 回归组 | 红灯运行 | 修复后 |
| --- | --- | --- |
| 空闲释放：慢写入、失败、重新打开、执行中、快照变化、保护、卸载 | 7 项新测试失败 | 文件内 14 项通过 |
| 项目关闭与提前保存错误 | 3 项新测试失败 | 文件内 28 项通过 |
| 失败后退出再次 flush | 1 项新测试失败 | runtime 文件内 4 项通过 |
| 跳过未渲染历史、停止隐藏消息的测量和订阅 | 2 项新测试失败 | 消息交互文件内 10 项通过 |
| 故障与事件压力验收 | 原 2 项保存合同失败 | 5 项全部通过 |

提交前新增的 0/100 ms 快速重开与导航后迟到失败共 3 项回归，在原逻辑上失败，修复后通过；空闲释放文件现有 17 项测试。架构及四类对抗复核完成，发现的导航重试问题已解决。

提交前最终 Web：285 个文件、3,198 项通过，TypeScript 通过；生产构建通过。Rust fmt、Clippy 与完整 208 项测试通过。
一次完整检查中的 `harness::tests::omp_accepts_rpc_capable_binary_and_rejects_other_names` 瞬时失败，随后该项单独重跑以及完整 `check:rust` 均通过。相关 Rust 代码未修改，失败原因未证实；保留失败日志，不把重跑通过当作已修复该不稳定项。

### 同负载性能对比

同一机器、同一生产模式浏览器夹具，10 个聊天各展开 200 轮，切换 500 次：

| 指标 | 修复前 | 修复后 |
| --- | --- | --- |
| 同步 React 提交 p95 | 311.1 ms | 93.6 ms（降低约 69.9%） |
| 前 100 / 后 100 次提交 p95 | 362.0 / 311.1 ms | 95.4 / 89.1 ms |
| 池内 DOM 元素 | 56,030 | 56,030 |
| 池内条目 | 10 | 10 |
| 运行期错误 | 0 | 0 |

没有通过少渲染历史或缩小缓存来改变负载。仍为 timer 调度下的同步提交耗时，不等于输入到绘制延迟，也没有宣称内存占用已下降。

真实浏览器行为检查：原先跳过的历史滚入可见区后能测量；窄栏提示 Show more（内容高度 180 px、折叠高度 80 px），点击后展开到 180 px；恢复宽度后回到单行 20 px、圆角恢复、Show more 消失，无运行期错误。

### 同类调用检查

- 保存后释放：空闲 detach 和项目关闭两条有相同数据风险，均已修复；关闭标签和分栏保留 live session，由安全 detach 负责后续释放，提前保存失败改为显式报告。
- submission 内的 5 处吞掉保存异常分别涉及回合结束、旁问更新/删除、草稿、压缩结束。它们不直接删除 live session；失败现在保留 dirty ID，后续 flush 仍能失败/重试。本轮没有宣称所有错误提示时机已统一。
- transcript 其余尺寸读取主要是可见 scroller 的定位、滚动锚定或启用中的子 agent 跟随；未发现与本次“每条隐藏用户消息同步测量”相同的无条件批量路径，没有扩大改写。

修复后证据：`output/stability/fixed-expanded-results.json`、`fixed-browser-behavior.json`、`fixed-check.log`、`fixed-build.log`、`rust-recheck.log`、`stability-fixed.log`，以及各组 `*-red.log` / `*-green.log`。

## 以下为首轮基线（修复前）

### 首轮结论

1. **P0：保存失败后仍释放会话，缓存淘汰后最新内容不可恢复。**
   两个故障验收明确失败；这是生产 hooks 组合上的可重复故障，不表示本轮观察到了用户数据丢失。
2. **P1：展开大量历史后，缓存命中的会话切换仍有显著同步布局成本。**
   200 轮历史场景中，切换的同步 React 提交 p95 为 311.1 ms；用户消息高度测量是主要采样热点。
3. 短时重复测试没有显示聊天池随切换次数无限增长。不能据此排除其他缓存、后台进程、睡眠唤醒或数小时运行的问题。

## 自动检查

| 检查 | 结果 |
| --- | --- |
| 原有 Web 测试 | 285 个文件，3180 通过、2 失败；失败均在 `useSaveToCanvas.test.ts` |
| 画布失败单独重跑 | 7 项中 5 通过、同样 2 项失败，不是只在并行完整运行中出现 |
| `npx tsc --noEmit` | 通过；完整 `check:web` 因测试失败短路，因此单独执行类型检查 |
| `npm run check:rust` | fmt、Clippy `-D warnings` 通过；208 项 Rust 测试通过 |
| `npm run build` | 通过，包括 TypeScript 和 Vite 生产构建 |
| `npm run test:stability` | 3 通过、2 失败；失败未跳过，也未标记成预期通过 |
| 新增测试及渲染夹具类型检查 | 通过，沿用项目 ES2020 配置；临时 tsconfig 将新增脚本纳入检查 |
| 隔离渲染夹具生产构建 | 通过 |

首轮时画布测试仍断言 `role="dialog"`，而 `SelectCanvasDialog` 已使用未提供该 role 的 `Popover`。两个红灯不能直接当作画布保存功能失败；后续修订见上。

## 保存故障的复现

入口：`scripts/acceptance/stability/persistence.test.ts`。
组合真实 `useSessionRuntime`、`useIdleSessionDetach`、序列化与缓存逻辑；只在 IPC 边界注入存储成功或失败。

正向对照：关闭 30 个会话，触发缓存淘汰后，全部内容仍能从模拟存储恢复。

失败路径：

1. 放入 13 个有未保存内容、无打开标签的空闲会话。
2. 第一个会话的 `session_upsert` 拒绝，其余 12 个正常写入。
3. 推进计时器执行释放和保存逻辑。
4. 观察到 13 次 `forgot:*` 先于 `write:*`；第一个写入随后失败。
5. 剩余挂载会话为 0、缓存为 12；第一个会话不在缓存或存储中，恢复返回 null。
6. 应用的 `onPersistenceError` 被调用 0 次。

测试在旁路捕获被丢弃 Promise 的 rejection，避免测试运行器提前退出；没有增加重试、恢复或应用错误通知。真实 App 对应调用直接 `void runtime.persistSession(session)`。

相关实现：

- `src/app/hooks/useIdleSessionDetach.ts`：保存调用后立即忘记 provider 并从会话状态移除。
- `src/app/App.tsx`：传给 detach 的保存回调丢弃 Promise。
- `src/features/sessions/data/sessionCache.ts`：按 12 条和 32 MiB 的预算淘汰；缓存不是失败写入的可靠副本。

下一次修复的验收合同：未持久化内容必须保留可恢复副本；保存失败必须抵达应用错误通道；重开或重新发送与保存完成交错时，不得释放新的活跃会话。

## 通过的事件压力场景

入口：`scripts/acceptance/stability/runtime.test.ts`。

- 100 次停止并重发：旧轮次结束后继续注入迟到文字、批准和结束事件；新轮次保持 busy、输出正确，没有旧批准混入。每轮结束后 active turn 正确清除。
- 三个会话交错输入共 30,000 条 delta：批量刷新后逐字验证完整输出，顺序和会话归属正确。

这些场景经过真实 submission/runtime/registry 代码，但 provider、进程桥和 IPC 使用测试替身。不能把它们算作真实 CLI 或原生进程回收验收。

## 真实浏览器渲染与内存

夹具直接使用生产 `AgentTranscript`、`TranscriptPool`、Markdown 和样式，通过 Vite 生产构建运行于 Ego Lite 的 Chromium。
30 个合成聊天，每个 200 轮，回答包含标题、强调和列表；不包含图片、代码高亮、画布或实际 provider。

| 指标 | 默认历史窗口，30 个聊天 | 全部展开，10 个聊天 |
| --- | --- | --- |
| 负载 | 60 次预热后切换 500 次 | 每个聊天展开到 200 轮，再切换 500 次 |
| 池内条目 | 13：1 显示、12 隐藏 | 10：1 显示、9 隐藏 |
| 稳定后的池内 DOM 元素 | 7,345 → 7,345 | 56,030 → 56,030 |
| CDP DOM 节点 | 12,199 → 12,199 | 93,271 → 93,271 |
| CDP JS 事件监听器 | 2,301 → 2,301 | 3,603 → 3,603 |
| GC 后 JS heap used | 41.53 → 42.23 MiB | 105.57 → 101.44 MiB |
| 同步提交 p95 | 15.7 ms | 311.1 ms |
| 前 100 / 后 100 次提交 p95 | 18.1 / 15.7 ms | 362.0 / 311.1 ms |
| 运行期错误 | 0 | 0 |

两列是不同负载，**不是修复前后对比**。heap 不等于进程 RSS，也不包含全部 DOM、图像、GPU 或 Rust/CLI 内存。

测量边界：宿主中 rAF 出现约 1 秒的调度间隔，截图也曾超时，因此本轮使用 timer 调度比较同步提交和保留量，**不报告 FPS、输入到绘制延迟或原生会话切换达标**。默认历史场景快速切换期间可能只构建首屏 3 轮，空闲后才补齐 20 轮；表中稳定 DOM 和堆在运行结束并稳定后采集。全部展开场景的每个检查点均实际保留 200 轮。

全部展开场景额外采样 20 次切换，p95 为 304.6 ms。CPU profile 的 3,555 个采样中，2,182 个（约 61%）落在 `UserMessageBlock` 的 `measure` 回调。已对照生产 bundle 定位到 `src/features/sessions/ui/AgentTranscript.tsx:1697`：

- layout effect 依赖 `visible`，切换隐藏/显示会重新执行。
- 回调读取 `scrollHeight`、`clientHeight`，聊天布局下还读取宽度和行高。
- `loadEarlier` 增加已渲染轮数，直到完整历史；池会保留这些已展开组件与 DOM。

这支持下一轮优先验证“限制长历史的同步测量范围、避免隐藏消息重复测量”的改动，再决定是否需要完整窗口化。尚未证明它就是用户所有卡顿的唯一原因。

最后卸载夹具：池条目和池内元素均归零，文档剩余 8 个元素，JS heap 降至 28.85 MiB。CDP 仍报告 9,227 个 DOM 节点和 380 个监听器，尚未进一步区分框架/浏览器保留或延迟清理，因此没有宣称所有对象都已释放。

## 重跑与证据

```sh
npm ci --no-audit --no-fund
npm run test:stability
npx vite build --config scripts/acceptance/stability/renderer.config.ts
npx vite preview --config scripts/acceptance/stability/renderer.config.ts
```

打开 `http://127.0.0.1:1439/scripts/acceptance/stability/renderer.html`。控制台提供：

```js
await window.lociStability.runCycles(60, 30, "timers")
await window.lociStability.runCycles(500, 30, "timers")
window.lociStability.snapshot()
```

重现展开场景：重新加载夹具，逐个调用 `show(0)` 到 `show(9)`，在每个聊天反复点击 “Load earlier messages”，确认 `snapshot().visibleTurns === 200`，再运行 `runCycles(500, 10, "timers")`。只有前台绘制调度正常时，才使用默认的 `"frames"` 模式观察绘制机会延迟；它仍不等于真实用户输入延迟。

首轮基线的 `npm run test:stability` 非零退出，显示两个保存合同失败；修复后应 5 项全部通过。套件独立于普通 `npm test`，不使用 skip 或 expected-failure 隐藏回归。

本次机器上的原始证据保存在忽略目录 `output/stability/`：

- `web-baseline.log`、`canvas-isolated.log`、`rust-check.log`、`production-build.log`。
- `stability-acceptance.log`：故障注入序列和断言结果。
- `renderer-results.json`、`expanded-results.json`：两类负载的检查点及前后堆/DOM计数。
- `expanded-cpu-profile.json`：额外 20 次切换的 CPU profile。
- `renderer-cleanup.json`：卸载后的计数。

## 仍未覆盖

- 完整 macOS Tauri/WKWebView 应用连续 2 小时，包括输入延迟、睡眠唤醒和后台完成。
- 真实 agent 子进程树、Rust RSS、SQLite 实际故障、跨窗口和退出重启交错。
- runtime 的保存指纹/轮次记录已补 1000 次移除循环；其他 provider 缓存和真实运行时的长期保留量尚未覆盖。
- 图片、代码高亮、画布与超大工具输出，以及临时失败后的真实恢复 UI。

保存合同和长历史测量范围的修复、短时回归现已完成。下一项是隔离原生应用和数据目录中的两小时测试，以及其余未覆盖资源的测量；不能以本报告替代这部分验收。
