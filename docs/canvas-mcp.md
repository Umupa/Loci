# Excalidraw 画布与官方 MCP

## 结论

每个 Claude Code / Codex 会话自动带上内置的 `excalidraw` MCP。它运行**未经修改的官方 Excalidraw MCP 服务**（v0.3.2 `.mcpb` 里的 `dist/server.js`），只把官方的 checkpoint 存储换成 Loci 画布。agent 用官方的 `read_me`、`create_view` 在本地画布上创建和续画；人工修改被保留，已打开的面板立即更新，结果写入 SQLite，重启后旧 checkpoint 仍可续画。

之前的结论“官方 MCP 只做预览，落盘走 `/operator` CLI”已作废。`/operator` 的 `canvas.*` 动作保留，用于列出、改名、删除和整幅替换。

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
  └─ stdio MCP “excalidraw”：node resources/excalidraw-mcp/loci-bridge.mjs
       ├─ official/server.js      官方服务，逐字节等于发布包（SOURCE 记录哈希）
       └─ Loci store ── 本机回环 + 会话令牌，命名空间 canvas ──▶ control.rs
                                                                └─ 会话所在窗口
                                                                     checkpoints.ts
                                                                       load：先让面板落盘，再返回当前元素
                                                                       save：把差异应用到当前场景 → SQLite → 面板
```

- `loci-bridge.mjs` 只做三件事：实现 store；补上 `read_widget_context`；屏蔽 `export_to_excalidraw`（它会把图上传到 excalidraw.com）。
- 官方服务把 `restoreCheckpoint` 解析为“加载的元素 − 删除 + 新增”。bridge 只把删除的 ID 和新增元素发给 Loci，Loci 在保存队列里对**当时的**场景应用，所以用户正在画的内容不会被旧读数覆盖。
- 场景和 checkpoint 在同一个 SQLite 事务里保存：不会出现已告诉 agent 却找不到的 checkpoint。
- `canvas` 命名空间比 `/operator` 的 `app` 窄：只需会话有进行中的 turn，只能读写本项目的画布。

## 语义

- 不带 `restoreCheckpoint` 的 `create_view` 新建画布，标题取最大的独立文字。
- 画布的每个 checkpoint ID，以及画布 ID 本身，都指向画布**当前**内容。手工创建的画布也能续画。与官方的差别：旧 checkpoint 不会回到旧快照；回退用面板的撤销。
- `read_widget_context` 不带参数列出本项目画布；带 ID 返回精简后的当前元素，以及按官方 widget 措辞写的人工修改摘要（新增、删除、移动、改字）。
- 同一 ID 重画即替换，保留原来的层次位置；删除形状会一并删除它的标签，并释放指向它的箭头和框架成员。
- 删除写成 Excalidraw 的墓碑元素。面板打开时，agent 的一次调用是一步撤销；面板未打开时直接落盘，没有撤销。
- 画布会出现在正在作画的会话旁边且不抢焦点；已在别的标签页打开时，只有用户正看着该会话才会移过来。面板跟随 agent 最后一个 `cameraUpdate`，首次打开时缩放到看全，不放大。
- 批准：读取类工具从不询问；`create_view` 在 Supervised 询问，其余模式直接执行，计划 turn 拒绝。官方把 `create_view` 标成只读，Codex 默认不会问，所以为它设置了 `approval_mode="prompt"`，再由 Loci 按模式作答。

## 存储：继续用 SQLite

画布是有两个写入方（人和 agent）的实时状态，需要串行写入、读前落盘和撤销集成；这些都在应用内完成。改成项目里的 `.excalidraw` 文件会多出一条绕过校验的写入路径（agent 直接改 JSON），并需要文件监听和冲突处理。会话、笔记、布局也都在同一个库里。

SQLite 方案的真实代价是不可移植、不随项目进版本库。需要时应增加显式的 `.excalidraw` 导出和导入，而不是更换存储。另一个已知弱点是图片以 base64 存在场景 JSON 里，每次保存都重写整幅；图片多时应把 `files` 拆表。两者本次都没有做。

新增表 `canvas_checkpoints(checkpoint_id, canvas_id, baseline_json, created_at)`，随画布删除。

## 限制

- 需要本机有 Node.js 20.11+ 或 Bun。没有时会话照常启动但没有绘图工具，Excalidraw 页面会显示原因。应用包没有自带运行时。
- agent 不能新增图片：官方格式没有图片数据通道。已有图片只要不删除就保留。
- 同一画布在另一个窗口打开时不会实时刷新。
- 用户自己配置的同名 `excalidraw` 服务或远端官方连接器不会接到本地画布；两者并存时模型可能选错。

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

未验证：macOS（主要目标平台）与 Windows；打包后应用的资源路径（只验证了开发构建的 `target/debug/resources`）；Claude Desktop；Bun 只做了协议冒烟，没有接到 Loci 实测；多窗口。
