# Excalidraw 画布与官方 MCP

## 结论

Claude Code / Codex 会话默认带上内置的 `loci_excalidraw` MCP。Antigravity / Pi 会话通过应用自带的 CLI 调用同一个服务，见“[通过应用 CLI 调用](#通过应用-cli-调用antigravitypi)”。Settings → MCP 的 **Built-in MCP** 区域显示服务名、用途、支持的 provider 和可用状态；全局开关会保存到 Loci 设置，不写入 provider 的用户配置。关闭或重新开启后，已有会话在下一轮用新配置恢复原对话，正在执行的 turn 正常完成。缺少运行时时可在设置页查看原因并重新检查。

它运行**未经修改的官方 Excalidraw MCP 服务**（v0.3.2 `.mcpb` 里的 `dist/server.js`），由 bridge 接入 Loci checkpoint 存储，并调整工具描述和保存结果。agent 用官方的 `read_me`、`create_view` 创建画布、添加或删除元素；修改已有元素用 Loci 提供的 `get_elements` 和 `update_elements`，按原 ID 合并属性，不需要重建整个元素。人工修改被保留，已打开的面板立即更新，结果写入 SQLite，重启后旧 checkpoint 仍可续画。

之前的结论“官方 MCP 只做预览，落盘走应用 CLI”已作废。`app` CLI 的 `canvas.*` 动作保留，用于列出、改名、删除和整幅替换。

## 调查到的事实

| 对象 | 事实 | 对设计的影响 |
| --- | --- | --- |
| 官方 `.mcpb` | `manifest.json` 以 `node dist/index.js --stdio` 启动；包内 `dist/server.js` 导出 `createServer(store)`，官方自己就有文件、内存、Redis 三种 store | store 是官方留出的接入点，无需改官方代码，也无需自写一套 MCP |
| 官方工具 | 对模型只有 `read_me`、`create_view`；`save_checkpoint`、`read_checkpoint`、`export_to_excalidraw` 标记为仅 widget 可见。实测 Claude Code 2.1.287 与 Codex 0.160 都不会把后三个给模型 | agent 没有读取工具，需要宿主补上 |
| 官方返回文本 | `create_view` 的结果要求模型先用 `read_widget_context` 查看人工修改。这是 Claude 应用作为宿主提供的工具，CLI 没有 | Loci 作为宿主提供同名工具 |
| checkpoint 内容 | 只有 `elements`，没有图片 `files` 和 `appState` | Loci 保存时只应用差异，图片和画布设置留在原画布 |
| 官方 widget 的转换 | 每次用 `convertToExcalidrawElements` 重建全部元素，文字一律改成 Excalifont；参考文档教的 `startBinding` 被 Excalidraw 0.18 的 `newArrowElement` 置空，箭头实际没有绑定 | Loci 不重建已有元素；只转换新增元素，并把 `startBinding.elementId` 变成真实的双向绑定 |
| Claude Desktop | 本机（Arch Linux ARM）没有 Claude Desktop。以上关于它的结论来自 `.mcpb` 清单和官方源码，**没有在 Claude Desktop 实机验证** | 不依赖它的任何未公开行为 |
| CLI 接入 | Claude Code 接受 `--mcp-config` 追加服务并把环境变量传给它；Codex `app-server` 接受 `-c mcp_servers.*` 覆盖，需用 `env_vars` 列出要转发的变量。均已实测 | 会话凭据只走环境变量，不出现在命令行 |

## 架构

```
Claude Code / Codex（Loci 会话子进程，环境里有会话凭据）
  └─ stdio MCP “loci_excalidraw”：node resources/excalidraw-mcp/loci-bridge.mjs
       ├─ official/server.js      官方服务，逐字节等于发布包（SOURCE 记录哈希）
       └─ Loci store ── 本机回环 + 会话令牌，命名空间 canvas ──▶ control.rs
                                                                └─ 会话所在窗口
                                                                     checkpoints.ts
                                                                       load：先让面板落盘，再返回当前元素
                                                                       save：把差异应用到当前场景 → SQLite → 面板
```

- `loci-bridge.mjs` 实现 store，补上读取画布、精确读取元素和按 ID 更新属性的宿主工具；屏蔽 `export_to_excalidraw`（它会把图上传到 excalidraw.com）。
- 官方服务把 `restoreCheckpoint` 解析为“加载的元素 − 删除 + 新增”。bridge 只把删除的 ID 和新增元素发给 Loci，Loci 在保存队列里对**当时的**场景应用，所以用户正在画的内容不会被旧读数覆盖。
- 场景和 checkpoint 在同一个 SQLite 事务里保存：不会出现已告诉 agent 却找不到的 checkpoint。
- 更新携带读取时的版本；SQLite 在同一事务内检查版本，冲突时重读并重算修改。手绘保存只合入用户相对本地基线改动的内容，agent 写入完成后也会先保存期间产生的新草稿，再更新面板，避免并发绘图互相覆盖。
- `canvas` 命名空间比 `app` 命名空间窄：只需会话有进行中的 turn，只能读写本项目的画布。

## 语义

- 不带 `restoreCheckpoint` 的 `create_view` 新建画布，标题取最大的独立文字。
- 画布的每个 checkpoint ID，以及画布 ID 本身，都指向画布**当前**内容。手工创建的画布也能续画。与官方的差别：旧 checkpoint 不会回到旧快照；回退用面板的撤销。
- `read_widget_context` 不带参数列出本项目画布；带 ID 返回精简后的当前元素，以及按官方 widget 措辞写的人工修改摘要（新增、删除、移动、改字）。
- 同一 ID 重画即替换，保留原来的层次位置；删除形状会一并删除它的标签，并释放指向它的箭头和框架成员。
- 删除写成 Excalidraw 的墓碑元素。面板打开时，agent 的一次调用是一步撤销；面板未打开时直接落盘，没有撤销。
- 画布会出现在正在作画的会话旁边且不抢焦点；已在别的标签页打开时，只有用户正看着该会话才会移过来。面板跟随 agent 最后一个 `cameraUpdate`，首次打开时缩放到看全，不放大。
- 批准：读取类工具从不询问；`create_view` 在 Supervised 询问，其余模式直接执行，计划 turn 拒绝。bridge 将官方 `create_view` 的 `readOnlyHint` 修正为 `false`，Codex 同时保留显式 `approval_mode="prompt"`，由 Loci 按模式作答。

## 保存回执与应用内链接

内置和远端 Excalidraw 服务可以同时存在。内置 `create_view` 的标题为 **Draw and Save Loci Canvas**，工具描述明确说明它会持久保存到 Loci，并建议在 Loci 中绘图时默认使用它。宿主引导只放在工具描述和调用结果里，不添加 `initialize.instructions` 或会话 system/developer 提示。选择仍由模型决定，不能保证模型每次都选对；远端工具成功不代表已保存到 Loci。

SQLite 保存成功后才返回 `canvasId`、`title`、`url`、`saved:true` 及现有 `checkpointId`。bridge 按 MCP 请求 ID 关联回执，并在结果开头提供可直接引用的 Markdown 链接；保存失败返回错误，不提供成功回执。`update_elements` 同样返回保存链接；`read_widget_context` 和 `get_elements` 返回当前画布地址。官方 widget 的私有 `save_checkpoint` 保留原有返回格式。

`app` CLI 的笔记、画布列表和读取结果包含 `url`，创建和更新结果额外包含 `saved:true`，其他字段保留。回复可写为 `[笔记标题](loci://note/<noteId>)` 或 `[画布标题](loci://canvas/<canvasId>)`。地址使用稳定 ID，资源重命名后仍可打开。

聊天正文将这两类地址显示为带图标的紧凑资源链接。sanitize 和 harden 仅额外允许 `loci` 协议，资源类型与 ID 在 URL 标准化之前校验；其他协议的限制保留。链接由当前窗口处理，不注册系统协议，不从外部唤起应用。既有绘图工具行的 Open 按钮也走同一导航，旧 checkpoint 可继续使用。

同项目画布在当前标签的画布面板打开并聚焦；已在另一标签打开则切换标签，跨项目画布在所属项目的标签打开。笔记进入现有 Notes 页面，清除搜索和时间筛选，按目标笔记所属项目定位；全局笔记显示全局列表。聊天项目和会话不变，关闭 Notes 返回聊天。重复点击会产生新的定位请求，读取失败或资源删除时明确显示错误，不打开另一条笔记。

## 精确修改已有元素

`get_elements` 接受 `checkpointId`（或画布 ID）和可选的 `elementIds`，返回原生元素记录、精确坐标、画布 `revision`、元素/图片数量和文件 ID，不返回图片二进制数据。`read_widget_context` 用于发现画布和快速浏览，不能把概览当完整元素重绘。

`update_elements` 接受同一画布的 `checkpointId`、刚读取的 `expectedRevision` 和一组 `{id, changes}`。服务端合并明确指定的属性，保留 ID、图片资源、分组、绑定目标和其他未指定字段；几何变化时同步重算文字尺寸及箭头的 focus/gap。支持位置、尺寸、旋转、字体、字号、颜色、行高、文字宽度、边框样式和图片翻转。

```json
{
  "checkpointId": "existing-drawing-id",
  "expectedRevision": 123456789,
  "updates": [
    {"id": "title", "changes": {"fontSize": 32, "strokeColor": "#1971c2"}},
    {"id": "photo", "changes": {"x": 120.5, "y": 640.25}},
    {"id": "paragraph", "changes": {"width": 260, "lineHeight": 1.5, "autoResize": false}}
  ]
}
```

整批先校验再保存；未知 ID、重复 ID、非法字段或过期版本会拒绝整批，不创建、删除或更换元素。修改期间的手绘内容按属性合并：手动移动同一段文字时，不会覆盖 agent 刚改的字号；两方改同一属性时，后续手绘值优先。返回新的 checkpoint、revision、受影响 ID 与最终数量；打开的面板把整个批次作为一次撤销。

文字采用 Excalidraw 的测量和换行规则；绑定文字随容器移动，直线箭头端点随绑定形状移动，框架平移携带成员。绑定文字的几何应通过容器修改；其宽度由容器决定，重排要求 `autoResize:true`，导入的固定宽度标签仍可修改颜色等样式，但移动容器或改字体前需显式开启自动排版。绑定箭头不独立拖离端点。弯折箭头和旋转箭头涉及路由，相关形状移动暂时整批拒绝并提示使用编辑器，不做猜测性的重排。

读取无需批准；`update_elements` 和 `create_view` 在 Supervised 模式询问，Plan turn 拒绝写入。官方参考和绘图回复会补充 Loci 的精确编辑说明，官方 bundle 保持原样。

## 通过应用 CLI 调用（Antigravity、Pi）

> 2026-10-09 更新：`/learn` 技能和它的 `loci_learn` 服务、`learn` 命名空间、`loci learn …` 命令已经移除，学习改由常驻 agent 承担（见 [architecture.md](architecture.md) 的 Agents 一节）。下文“怎么调用”和“agent 怎么知道”描述的是现状；验证记录里提到 `/learn` 的条目是当时的历史记录，保留原样。

### 为什么不是给它们也挂 MCP

内置服务此前只支持 Claude Code 和 Codex，是因为“挂载”这一步用的是这两家各自的启动参数（`--mcp-config`、`-c mcp_servers.*`）。能力本身不分 provider：控制通道的 `canvas` 命名空间和窗口里的处理器对谁都一样。其余 provider 缺的只是“模型怎么调用、怎么知道能调用”。

2026-10-08 核对到的事实：

| 对象 | 事实 | 结论 |
| --- | --- | --- |
| 上游 MonoCode（`d26871f`） | 不给任何 Agent 注入 MCP，所有 ACP 适配器都发 `mcpServers: []`。它的内置能力（内置命令、编排、Mono 的记忆与 artifacts）一律是：内置命令 → 在该轮消息后追加说明 → 应用自身的可执行文件充当 CLI → 回环控制通道 | 只要求 Agent 能跑 shell，十个 provider 一致。Loci 的 `app` CLI 就是这条路 |
| Pi 1.1.0（本机实测） | 0.99.0（2026-09-29）才有内置 MCP；配置只在 `~/.pi/agent/mcp.json` 和项目的 `.pi/mcp.json`，都是用户自己的配置。不改配置的唯一办法是 `--extension` 调 `pi.registerMcpServer`，实测可行，但要求新版本。Pi 没有批准协议，shell 会继承 `LOCI_APP_*` | 走 CLI 对所有 Pi 版本都成立 |
| Antigravity | 本机未安装，无法实测。ACP 的 `mcpServers` 是否被它的官方 server 采纳没有文档，且已有其他 ACP Agent 忽略该字段的报告；它自己的 MCP 配置是全局用户文件 | 不依赖未证实的行为，也不写用户配置 |
| Antigravity 的进程 | 以 `<会话ID>#<n>` 启动，而会话凭据按会话 ID 查，所以此前它的进程里没有 `LOCI_APP_ENDPOINT/TOKEN`（`app` CLI 在它上面同样连不上） | 凭据改为按所属会话查找 |

所以没有再做一套各家专用的挂载，而是给同一组服务加了一种调用方式。Claude Code 和 Codex 的 MCP 挂载没有改动。

### 怎么调用

```sh
loci canvas create_view --input drawing.json
loci canvas read_widget_context --json '{"checkpointId":"<id>"}'
loci canvas --help        # 工具、说明和参数，直接取自服务的 tools/list
```

`loci` 是应用自己的可执行文件，与 `loci app` 并列（`src-tauri/src/control_cli.rs`）。一次调用做四件事：

1. 用环境里的会话凭据向应用询问“这个服务用什么命令启动”。这是保留请求 `mcp.server`，由 `control.rs` 直接回答，受该命名空间自己的授权规则约束，窗口看不到它。应用已经知道资源路径和 Node/Bun 在哪，CLI 不重复解析。
2. 启动这条命令。它就是 MCP 客户端会挂的那个进程（`loci-bridge.mjs`），继承同一份凭据。
3. 做 MCP 握手，调用这一个工具。
4. 把结果的文本块原样打印；失败时退出码非 0。

因此官方 Excalidraw 服务、工具说明、保存回执和窗口里的全部规则都与 MCP 路径逐字相同，没有第二份实现。CLI 只接受给 agent 的那五个工具；官方 widget 私有的 `save_checkpoint`（会整幅替换）、`read_checkpoint` 和被屏蔽的 `export_to_excalidraw` 不可调用，与 Claude Code / Codex 看不到它们一致。输入上限 6 MiB，大的参数用 `--input 文件` 或 `--input -`。

### agent 怎么知道

没有工具列表可看，所以由 Loci 在消息后追加说明（`src/app/hooks/useSessionSubmission.ts`，文本在 `features/sessions/model/builtinCli.ts`）：

- 画布开关开启、会话在项目里时，**每个 provider 对话的第一轮**附带 `<loci_canvas>`，约 190 token。带过说明的用户消息记 `canvasCli` 标记；provider 会话换新（切换 provider、无法恢复）后重新附带；开关由关到开后的下一轮附带。
- 令牌只在环境变量里，说明里只有可执行文件路径。

走这条路的 provider 列在 `BUILTIN_CLI_HARNESSES`，目前是 Antigravity 和 Pi。

### 开关、批准和显示

- **开关。** turn 开始时把 Settings → MCP 的 Excalidraw 开关记进这一轮的授权，`canvas` 命名空间按它放行或拒绝（`control.rs`）。关闭后下一轮起请求被拒并说明原因，进行中的 turn 正常完成。这对两种调用方式一视同仁；Claude Code / Codex 关闭后本来就不再挂载，行为不变。`app` CLI 的 `canvas.*` 走 `app` 命名空间，不受开关影响，与此前相同。
- **批准（Antigravity）。** 它运行命令前会发批准请求并带上命令。`builtinCliCall` 只在命令**恰好是本应用可执行文件的一次工具调用**时才认：路径必须等于应用自己的路径，参数只能是一个 `--json` 或 `--input`，任何会被 shell 展开、串接或重定向的写法（`;`、`&&`、管道、`$()`、反引号、heredoc）都不认。认出后按 MCP 工具的同一套规则作答：读取不问；`create_view` / `update_elements` 在 Supervised 询问、其余模式直接执行；学习工具不问；计划 turn 只读。认不出的照常作为普通命令询问。
- **批准（Pi）。** Pi 没有批准协议，任何工具都不询问，画布写入也一样；计划 turn 里 Pi 没有 shell，这些工具不可用，包括读取。
- **显示。** 对话记录把这样的 shell 行显示成对应的画布调用，绘图行的 Open 按钮照常可用；查看工具列表显示为“View canvas tools”。

### 这条路的限制

- 说明只存在于对话里。上下文被压缩后 agent 可能不再知道这个 CLI；提醒它即可。
- 大的 `create_view` 参数要经文件或标准输入传入。在 Supervised 下这通常意味着先批准一次文件写入，再批准一次绘图。
- 需要 agent 的 shell 能连本机回环，并继承会话进程的环境变量。
- 每次调用启动一次 Node 进程。

## 存储：继续用 SQLite

画布是有两个写入方（人和 agent）的实时状态，需要串行写入、读前落盘和撤销集成；这些都在应用内完成。改成项目里的 `.excalidraw` 文件会多出一条绕过校验的写入路径（agent 直接改 JSON），并需要文件监听和冲突处理。会话、笔记、布局也都在同一个库里。

SQLite 方案的真实代价是不可移植、不随项目进版本库。需要时应增加显式的 `.excalidraw` 导出和导入，而不是更换存储。另一个已知弱点是图片以 base64 存在场景 JSON 里，每次保存都重写整幅；图片多时应把 `files` 拆表。两者本次都没有做。

新增表 `canvas_checkpoints(checkpoint_id, canvas_id, baseline_json, created_at)`，随画布删除。

## 限制

- 需要本机有 Node.js 20.11+ 或 Bun。没有时会话照常启动但没有绘图工具，Excalidraw 页面会显示原因。应用包没有自带运行时。
- agent 不能新增图片：官方格式没有图片数据通道。已有图片只要不删除就保留。
- 同一画布在另一个窗口打开时不会实时刷新。
- Antigravity 和 Pi 通过 CLI 调用，另有“[这条路的限制](#这条路的限制)”。
- `loci_excalidraw` 是应用保留的服务名；用户自己的 `excalidraw` 或远端官方连接器保留原配置，不接到本地画布。内置工具只识别保留名称，不会给用户服务套用本地画布的自动批准规则。

Codex 的 `-c` 覆盖会逐字段合并，连完整 inline table 也不会清除旧字段。如果复用用户的远端 `excalidraw` 名称，遗留的 `url` 和新增 `command` 会使整个 Codex 会话启动失败；独立的应用名称避免了这一冲突。

## 更新官方服务

改 `scripts/vendor-excalidraw-mcp.mjs` 里的版本和包哈希，运行它，再跑 `src/features/canvas/mcpBridge.test.ts`。`--check` 校验已提交文件与 `SOURCE` 一致。`createServer(store)` 的签名或 store 调用方式变化时需要人工复核 bridge。

## 验证记录（2026-10-07，Arch Linux ARM aarch64）

自动检查：Vitest 227 个文件、2569 项测试；TypeScript；`cargo fmt --check`；Clippy `-D warnings`；Rust 165 项测试；`npm run build`。`mcpBridge.test.ts` 启动真实 bridge 进程和官方服务，经真实的行协议调用生产处理代码与实际安装的 Excalidraw 0.18.1，只替换了 Tauri 窗口和 SQLite。

实机流程使用真实的 Tauri debug 二进制、WebKitGTK 2.52.6、真实 SQLite、Claude Code 2.1.287（Sonnet 5）和 Codex 0.160（GPT-6.1-Sol）。本机缺少 `webkit2gtk-4.1` 等系统包且无法 sudo，所以把官方软件包解到临时目录，通过 `bwrap` 叠加运行，窗口在 Xvfb 里，用真实鼠标键盘事件操作。应用数据目录重定向到临时目录。

| 步骤 | 结果 |
| --- | --- |
| 手工建画布 | 鼠标画两个带标签的矩形、绑定箭头、红色 Code 字体文字、框架、经系统文件对话框插入图片；SQLite 中 8 个元素、1 个文件 |
| Claude 续画（Supervised） | 读取免批准，绘图弹出批准；新增 Cache 方框和绑定到手绘 API 方框的箭头；手绘元素、图片文件、字体、框架归属不变；画布自动出现在会话旁 |
| 人工再改 | 拖动 Database 和文字；手绘箭头跟随移动 |
| agent 读出修改 | Claude 准确报告两处移动的前后坐标，然后新增 Queue |
| 撤销 / 重做 | 面板内 Ctrl+Z 一步撤掉 agent 的整次修改，Ctrl+Shift+Z 恢复；两次都已落盘 |
| 重启 | 关闭窗口正常退出，场景与退出前逐字节相同；重启后布局和画布恢复；Claude 恢复会话后用重启前的 checkpoint 续画（Auto-accept edits，无批准提示） |
| Codex | 同一画布上新增绑定到手绘方框的 Auth；重启后续画；Supervised 下绘图弹出批准，删除并新增元素；画布移到 Codex 会话旁 |

共 6 个 checkpoint 指向同一张画布，画布数始终为 1。

上述完整绘图流程未验证：macOS（主要目标平台）与 Windows；打包后应用的资源路径（该轮只验证了开发构建的 `target/debug/resources`）；Claude Desktop；Bun 只做了协议冒烟，没有接到 Loci 实测；多窗口。

## 内置 MCP 设置验证（2026-10-07，macOS）

使用独立 identifier 的 release 应用包、真实 Tauri 页面和 SQLite，验证 Built-in MCP 区域、开关、状态与用途说明；关闭后退出并重启应用，开关仍保持关闭。Codex 同一条对话依次完成关闭、开启、再关闭三轮：关闭时实际 app-server 参数没有内置服务且没有 bridge 进程；开启后使用包内资源启动 bridge，真实调用 `loci_excalidraw:read_me`，SQLite 中工具状态为 completed；再次关闭的下一轮恢复原对话且移除注入和 bridge。三轮的 Loci 会话 ID 与 Codex thread ID 均一致。验收后恢复默认开启并退出测试实例。

自动检查：256 个 Vitest 文件、2910 项测试通过（4 个 worker）；TypeScript 和生产前端构建通过。新增回归覆盖开关持久化、跨窗口同步、缺少运行时的提示与重查，以及 Claude Code / Codex 新会话和已有会话的关闭、重新开启、原对话恢复。Claude Code 本轮仅做自动回归，未登录实测；本轮没有在 macOS 验证完整绘图写入流程。

## 精确属性编辑验证（2026-10-07，macOS）

自动检查：257 个 Vitest 文件、2946 项测试，TypeScript、Rust 格式检查、Clippy 和 204 项 Rust 测试通过。真实 bridge 进程经 MCP 行协议调用生产处理代码和 Excalidraw 0.18.1，验证 75 个既有元素、2 张图片保持原 ID 与资源；过期版本或非法批次不写入。并发回归覆盖手动移动、输入文字和调整绑定形状，合并后的字号、文字尺寸、标签位置及箭头端点保持一致。

本轮同时验证 macOS release 应用包构建、启动及包内 MCP 工具和 schema；未登录 provider 重跑完整人工绘图流程。复杂弯折/旋转箭头的路由仍需编辑器；并发合并遇到这类路由冲突时保留手绘草稿并报错。

## 保存回执与资源链接验证（2026-10-08，macOS）

自动检查：283 个 Vitest 文件、3167 项测试通过（4 个 worker）；TypeScript、生产前端构建、Rust 格式检查、Clippy 和 208 项 Rust 测试通过。官方 Excalidraw bundle 的 SOURCE 哈希校验通过。新增回归首先在旧实现上复现了初始化注入指令、绘图缺少本地保存回执和正文资源链接被移除；修改后通过。真实 bridge 的测试覆盖并发请求回执隔离、保存失败不返回链接、精确属性更新和 checkpoint 续画。

提交前补充 6 项先失败、修复后通过的回归：手动选择使待完成的链接读取失效；旧编辑器的延迟保存不改变新目标的项目范围；导航读取保留期间已保存的内容和项目变更（项目单独移动不会改变 `updatedAt`）；链接 ID 格式兼容已有存储规范，支持超过 256 字符的合法复合笔记 ID，写入、重试和列表均返回正常链接。

原生验收使用独立 identifier 的 release 包和独立 SQLite 数据库。没有替换日常使用的 Loci 应用或用户 MCP 配置；仅在临时验收项目为 Claude 添加远端 Excalidraw 配置。

| 场景 | 结果 |
| --- | --- |
| 正文资源链接 | 实际 Tauri/WebKit 页面显示笔记和画布图标；点击打开指定资源 |
| 键盘与跨项目画布 | Tab 聚焦资源链接，Enter 打开跨项目画布，切换到所属项目；已有画布复用原标签 |
| 笔记定位 | 跨项目笔记、全局笔记、笔记内连续跳转均成功；关闭 Notes 返回原聊天项目 |
| 失效笔记 | 显示 “This note no longer exists”，不显示另一条笔记的编辑器 |
| Codex 默认绘图 | GPT-6.1-Sol 首轮调用 `loci_excalidraw:read_me`、`create_view`，保存 Kubernetes 简单架构，回复自带可点击画布入口 |
| Codex 保存笔记 | `app` CLI 调用 `notes.write` 返回 `saved:true` 和 `url`；回复中的笔记、画布链接均可打开，笔记内可跳回画布 |
| 远端仍可用 | Codex 显式指定远端后成功调用 `excalidraw:read_me`；未增加本地画布 |
| 重启与 Open 按钮 | 正常退出并重启，3 张画布与 4 条笔记的内容哈希不变；正文链接和工具行 checkpoint Open 均可继续定位 |
| Claude Code | Sonnet 5 在内置、远端同时可用时仍先调用远端 `mcp__excalidraw__read_me`；随后模型接口返回 429 会话额度限制，本轮未完成 Claude 的绘图保存验收 |

工具描述降低误选概率，不能保证选择结果；本轮 Claude 的调用再次证明这一限制。若要求每次默认绘图都保存到 Loci，需要另外决定会话内是否屏蔽远端工具。跨平台及多窗口的完整原生验收未在本轮执行。另发现既有 debug 启动逻辑会重写 bundle identifier，本轮使用 release 包隔离验收，未修改该逻辑。

上述原生流程在提交前竞态修正之前完成。修正后的完整 release 包已重新构建；额外 GUI 复验时驱动返回 `cgWindowNotFound`，未取得最终包的新界面证据。新增竞态和长 ID 行为已通过生产组件/处理器的控制时序回归验证，不将它们记为额外原生实测通过。

## CLI 调用的检查记录（2026-10-08，Arch Linux ARM aarch64）

这一轮按要求只完成实现，没有做实机验收。下面如实区分做过的检查和没做的验收。

自动检查：Vitest 303 个文件、3584 项测试；TypeScript；`cargo fmt --check`；Clippy `-D warnings`；Rust 212 项测试。新增的覆盖：

- 授权：画布开关关闭时 `canvas` 被拒而 `app` / `learn` 不受影响；带代号的子进程 ID 找到所属会话的凭据（`control.rs`）。
- CLI：参数解析、只接受给 agent 的工具、解析失败不回显文件内容、结果按文本打印；对随应用发布的两个服务做真实的 MCP 握手并核对每个工具都存在（`control_cli.rs`，需要本机有 Node）。
- 说明注入：Pi / Antigravity 每个 provider 对话只附带一次、provider 会话换新后重发、开关关闭时不发且该轮无画布权限、开关打开后的下一轮补发、非项目目录不发、Claude Code / Codex 不受影响；`/learn` 在这两个 provider 上使用 CLI 措辞（`useSessionSubmission.test.ts`）。
- 命令识别与批准：只认本应用可执行文件的单次调用，串接、展开、重定向和别处的 `loci` 一律不认；批准规则逐模式核对（`builtinCli.test.ts`）；Antigravity 适配器经脚本化的 ACP 线路走完“读取不问、Supervised 下绘图询问、计划 turn 拒绝写入、认不出就照常询问”（`antigravityBuiltinCli.test.ts`）。
- 显示：shell 行被命名为对应的画布或学习调用并带出 checkpoint；用生产代码生成 Pi 的 bash 行和 Antigravity 的 execute 行、批准行，确认都能认出。
- Claude Code / Codex：原有的 MCP 挂载、批准和显示测试没有改动，全部通过；发给它们的 `/learn` 说明文字与改动前逐字节相同。

手动检查（不是验收）：用真实的调试版二进制运行 `loci learn map_read`、`loci canvas read_widget_context`、`loci canvas create_view`（文件和标准输入两种）、两个 `--help`，以及未知工具、非法 JSON、错误凭据、没有凭据、命名空间被拒五种失败。服务是真实的 `loci-bridge.mjs`（含官方服务）和 `loci-learn.mjs`（Node 24.21）；控制端点是一个按协议应答的替身脚本，不是应用。`create_view` 返回了保存回执和 `Checkpoint id: "…"`。另在本机的 Pi 1.1.0 上确认 RPC 模式的 shell 会继承 `LOCI_APP_*`。

没有验证的：

- 在运行中的应用里走完整流程，包括 `control.rs` 回答 `mcp.server`、画布面板随调用更新、会话重启后恢复。
- 任何真实的 agent turn。本机的 Pi 没有登录模型；本机没有安装 Antigravity，它的官方 ACP server 还需要 Google 账号登录。因此“真实模型是否按说明使用 CLI”“Antigravity 的 shell 是否继承会话环境变量”“它的批准请求里命令放在哪个字段”都只有推断和脚本化测试。
- macOS、Windows 和打包后的应用。

在装有并登录了 Antigravity 和 Pi 的机器上验收时，建议按这个顺序看：

1. 新开 Pi 会话，直接让它画一张图：对话记录出现“Drew on the canvas”，画布出现在会话旁，回复带画布链接。接着手动改图，再让它“在原图上加一个方框”：手动改动保留。
2. 同一会话里关闭 Settings → MCP 的 Excalidraw 开关，再让它画：它被告知工具已关闭；重新打开后的下一轮恢复。
3. 退出并重启应用，回到该会话继续让它改图：不需要重新说明。
4. 在项目里输入 `/learn 某主题`：读图、初始化、记录都成功，学习工具不弹批准；没有输入过 `/learn` 的会话运行 `loci learn map_read` 被拒。
5. 在 Antigravity 上重复 1 到 4，并分别在 Supervised、Auto-accept edits 和计划 turn 下确认：读取不问；绘图只在 Supervised 询问；计划 turn 里写入被拒。若读取也弹出批准，说明它的批准请求没有被认出，需要按实际字段调整 `permissionRequestFromAcp`。
6. 在 Claude Code 和 Codex 上各画一次图、各用一次 `/learn`，确认与之前一致。
