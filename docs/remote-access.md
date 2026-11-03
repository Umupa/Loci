# 远程访问（v0.7 已实现）

> 2026-11-02 脑暴定稿，已在 v0.7 实现；细节以 [architecture.md](architecture.md#remote-access) 和代码为准。本文保留当时的方案与取舍。iPad 端暂不考虑。

## 目标

在笔记本上建的导师和课程，回家后在 Mac mini 上接着学，体验和在笔记本上一样。

- **不做同步。** 数据、agent CLI 和模型配置只在一台设备上（主机，目前是笔记本）。其他设备通过隧道连到主机，像 Claude Code / Codex 的 remote control。
- **远程端和本机同级。** 功能一致：对话、阅读、笔记、画布、PDF 高亮、设置、导师权限（包括 Full access）都能用，都能改。
- **没有账号服务。** “登录后看到所有设备”靠设备组实现，信任来自设备密钥，不是服务端密码。

## 关键约束

1. **CLI 驱动在前端。** 解析 CLI 协议、组装对话块、写会话（`session_upsert`、`agent_transcript_append`）的逻辑在 webview 里（`src/integrations/harness/core/apply.ts`、`jsonRpc.ts`、`acp.ts`），Rust 只是管道（`harness_spawn`/`harness_write`/`harness-stdout`）。外部 `loci` CLI 的请求也是转给窗口回答的（`control.rs` → `loci-control-request`）。
   所以**主机窗口是会话的唯一驱动者**。远程端不能各自驱动 CLI，只能发意图（发消息、停止、回答卡片），收状态（对话块快照和增量）。
2. **alma-relay 只是通用隧道。** 它转发 HTTP、SSE、WebSocket，不懂上层协议。E2E 要 Loci 自己实现（Alma 的 E2E 在 Alma 端点里，不在 relay 里）。限制：单条客户端 WS 消息 ≤ 24 MiB，响应头 120 s 内必须返回，主机掉线时客户端 socket 以 1012 关闭。
3. **主机会睡眠。** 笔记本合盖、用电池时睡眠无法阻止，此时所有客户端都连不上。开启远程访问后，Loci 在接电源时阻止系统空闲睡眠；设置页写明这一点，合盖或用电池时仍会睡。

## 分层

```
客户端 Loci（Mac mini，桌面版，连接远程设备模式）
  React 前端 ── RemoteTransport
                   │  一条连接：call/result、subscribe/event、blob 分块、upload
                   │  SecureChannel（X25519 + 设备密钥 → AES-256-GCM）
  ─────────────── Tunnel ───────────────
     AlmaRelayTunnel │ TailscaleTunnel（后续） │ LoopbackTunnel（开发）
  ──────────────────────────────────────
主机 Loci（笔记本）
  Remote Gateway（Rust）：鉴权、命令白名单、blob、事件扇出
  会话主控（主窗口）：唯一驱动 CLI，广播会话快照和增量
  loci.db + ~/Loci + CLI 登录与模型配置
```

每个 Loci 都既能当主机也能当客户端；连接一台设备会打开一个新窗口，类似 VS Code Remote。客户端用的是本机安装的 Loci 桌面版，前端代码在本地、可信，不经 relay 下发。

### 1. Transport（前端）

- 所有直接 import `@tauri-apps` 的地方都已收进 `src/platform`。
- 定义 `Transport` 接口：`call(cmd, args)`、`listen(event, handler)`、`fileUrl(path)`；字节读写直接走命令（`read_binary_file`、`write_attachment`、`remote_client_upload`），没有单独的 blob 方法。实现有两种：`TauriTransport`（本机）和 `RemoteTransport`（连主机）。
- `convertFileSrc`/`asset://` 改用 `fileUrl`：本机返回 asset URL，远程整份取回字节后返回 blob URL，没有按 range 读取。

### 2. 命令清单与白名单

Rust 端共注册 194 个命令，每个都要标一类。白名单由这份清单生成，未标注的命令默认不对外。

| 类别 | 远程端行为 | 例子（模块） |
| --- | --- | --- |
| 读 | 转发到主机 | `mentor_store`（load/search/state）、`course`、`agent_documents`、`notes`、`canvas`、`learning`、`code`、`skills`、`source_translations`、`session_store`（get/list/search）、`fs` 的读（`read_*`、`list_dir`、`stat_files`、`inspect_paths`） |
| 写 | 转发到主机 | 上面各模块的 upsert/delete/set，`fs` 的写（`write_text_file`、`create_path`、`rename_path`、`trash_path`、`copy_path`、`move_path`、`write_attachment`），`mentors_import/export`，`mcp_add`，`claude_mcp_*`，`cli_access_*` |
| 会话动作 | 不直接执行，交给主机窗口 | `session_upsert`、`session_delete`、`session_set_archived`、`agent_transcript_append` 等会话存储命令 |
| 在主机执行 | 转发，作用在主机上 | `reveal_path`、`open_path_with_default_app`、`show_notification`（主机提示）、`mcp_provider_login`（在主机浏览器里完成） |
| 客户端本地 | 不转发，在客户端执行 | `window`、`menu`、`set_traffic_lights_visible`、`set_window_*`、`set_trackpad_zoom_enabled`、`set_dock_badge`、`open_new_window`、`pasteboard`、`notifications` 的权限、`chat_background`（外观）、`fetch_link_preview`、`keybindings_set_overrides` |
| 永不对外 | 拒绝 | `harness_*`（spawn/write/kill/exec/http/sse/resolve）、`control_*`、`workspace_reset*`、`canvas_mcp_server` |

需要专门处理的：

- **系统文件选择器**（`tauri-plugin-dialog`）：远程端换成主机文件浏览器（基于 `list_dir`、`stat_files`）；从客户端拖入或选择本机文件时，走上传，写到主机。
- **剪贴板图片、拖入图片**：截图或没有路径的字节经 `write_attachment` 写到主机；按路径拖入或粘贴的文件先经 `remote_client_upload` 上传，再以主机路径进入附件或笔记。
- **链接预览**（`fetch_link_preview`）：在客户端本地执行，只取公开网页，不涉及主机数据。
- **工作区重置**：只能在主机上做。

### 3. 会话主控

- 主机窗口里的会话 store 是唯一的权威。所有设备的输入进同一个队列；两台设备同时打开同一个导师，看到的是同一条对话流。
- 广播：会话块增量带递增序号；客户端断线重连后，按序号补齐，差太多时取快照。
- 视图状态（打开的课程、阅读位置以外的面板状态）按设备各自记录；阅读进度、高亮只存在主机，一份。
- **实施时先摸清了** `useSessionStore`、`useSessionRuntime`、`useSessionSubmission` 的状态流：唯一的写入口是 `useSessionRuntime` 的 `updateSessions`，块和会话都不可变，按引用比较就能产出增量。这是整个方案风险最大的一块。
- 长期可以把会话驱动下沉到 Rust，做成不依赖窗口的无头主机；第一版不做。

### 4. Gateway（Rust，主机）

- 一条连接上四种帧：`call`/`result`、`subscribe`/`event`、`blob`（分块，单块 ≤ 1 MiB，远低于 relay 的 24 MiB 上限）和 `upload`（设备上传，单文件 ≤ 100 MiB）。
- 每个请求先经 SecureChannel 解密、验证设备身份，再查白名单，然后转发：要么调 Rust 命令，要么交给主窗口（会话动作、`loci-control-request` 那类窗口回答的请求）。
- 事件扇出：已订阅的客户端收到会话 feed（快照、patch，以及夹在其中的共享设置）；主机发给本机窗口的其他事件不转发。

### 5. Tunnel

```rust
trait Tunnel {
    /// 开始监听，把每条进入的客户端连接交给上层；drop 即停止。
    fn listen(&self) -> Listener;
    /// 作为客户端连到主机。
    fn dial(&self) -> impl Future<Output = Result<Connection, String>> + Send;
}
```

`Connection` 两端交换不透明的字节消息，断开任一端两个方向都结束；状态是 `Connecting`、`Online`、`Retrying { attempt }` 或 `Stopped { reason }`。

- `AlmaRelayTunnel`：外连 `wss://<relay>/agent?th=<tokenHash>`，发 `register`（带 `RELAY_REGISTRATION_KEY`），协商协议 2；把 `wopen`/`wmsg`/`wclose` 映射成 Gateway 的连接；收到 close `4000`（同一 hash 被别人注册）时不要循环重连。客户端访问 `wss://<relay>/c/<token>/__loci__`。
- `TailscaleTunnel`：在 tailnet 地址上监听，后续再做。
- `LoopbackTunnel`：本机两个窗口模拟主机和客户端，开发和测试用。

E2E 不管走哪条隧道都开着，安全模型只有一套。

### 6. 身份：设备组

和隧道层并列的抽象：

```rust
trait Identity {
    fn devices(&self) -> Vec<Device>;                 // 组里的所有设备、是否在线
    fn join(&self, name: &str) -> Result<(), String>;
    fn remove(&self, device_id: &str) -> Result<(), String>;
}
```

实现：`DeviceGroup`（v0.7 实现）、`Tailnet`（换 Tailscale 时一起换）、`OAuth`（以后开放给他人时再考虑）。

`DeviceGroup`：

- **建组**：第一次用到远程访问时生成设备密钥对（私钥存 Keychain）；在设置里显式“创建设备组”，生成 32 字节组密钥。
- **加入**：新设备粘贴组密钥文本（`loci-group:<组密钥>?registry=<注册表地址>`，可从任一成员设备复制，也可以存进密码管理器），即可加入，**不需要在已有设备上批准**。加入后以本机设备密钥登记；主机在下一次名单刷新时接受它，第一次连接可能被拒，客户端约 3 秒后自动重试。没有“新设备加入”的全组通知，新设备出现在设备列表里。
- **设备列表**：放在本仓库的 `services/device-registry`，一个独立的 Cloudflare Worker（每个组一个 Durable Object，自带 SQLite），记录设备名、平台、公钥、最后活跃时间和路由。设备记录由组密钥签名，心跳由设备密钥签名。它和 relay 部署在同一个 Cloudflare 账号下，但互不依赖。
- **连接码**：每台主机的连接码由组密钥和它的 `deviceId` 派生（HKDF-SHA256），成员各自算出，注册表和 relay 都不知道组密钥；心跳里只有连接码派生出的路由令牌。
- **吊销**：在任意成员设备上移除某台设备，注册表留下签名墓碑，**移除是永久的**：同一个 `deviceId` 之后不能再加入。主机在名单刷新后拒绝它的握手，并断掉它已建立的连接；被别的设备移除的主机最多 60 秒后才知道。**轮换组密钥等于换一个组**：`groupId` 就是组公钥，旧组成员连不到新组，必须重新加入。
- **风险**：远程端等同 Full access，组密钥泄露就等于主机被接管。组密钥只保存在成员设备上，用于加入、签名设备记录和派生连接码，不发给 relay 或注册表。缓解：可以随时移除设备；轮换组密钥需要所有设备重新加入。

### 7. 客户端缓存

- 客户端缓存最近看过的主机内容：导师列表、课程大纲、打开过的文档和 PDF、笔记、对话记录。
- 主机离线时，客户端只读：显示缓存内容和“主机离线”提示，所有写操作和发消息禁用。不排队写入，所以不产生同步冲突。
- 主机恢复后，以主机为准刷新缓存。
- 缓存放在客户端的应用数据目录 `remote-cache/`，按主机设备 id 分开存放，每台主机上限 256 MiB；断线时保留（离线读的就是它），移除设备或退出设备组时清除。

## 阶段

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| P0 | 命令清单与分类；`Transport` 接口；收拢 Tauri import | 行为不变，现有测试全过 |
| P1 | Gateway、会话主控广播、`LoopbackTunnel` | 本机两个窗口：同一导师对话同步显示，断线补齐，客户端能读写笔记和打开 PDF |
| P2 | `DeviceGroup`、SecureChannel、`AlmaRelayTunnel`、Worker 设备注册表 | 笔记本和 Mac mini 经 Cloudflare Worker 连通，relay 只看到密文 |
| P3 | 客户端“连接到设备”界面、主机文件浏览器和上传、客户端缓存、电源管理 | Mac mini 上把一节课从读到问到记笔记完整走一遍 |
| P4 | `TailscaleTunnel` 加 `Tailnet` 身份 | 切换隧道不改上层代码 |

P0–P3 的代码已在 v0.7 完成；P2、P3 的两台 Mac 实机验收还没做。P4 未做。

## 对路线图的影响

路线图里写着“本地优先。数据留在本机，没有账号”。这个方案仍然本地优先，也没有账号服务，但多了一个自建的 relay 和一个设备注册表 Worker。远程访问默认关闭，不开就和现在完全一样。
