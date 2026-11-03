# 远程访问部署指南

> 简体中文。从零开始，让笔记本当主机、Mac mini 连上去。为什么要这样分层、每一层怎么实现，见[远程访问设计稿](remote-access.md)。

## 1. 部署什么，为什么

```text
Mac mini（客户端）                       笔记本（主机）
  Loci ── WSS（端到端加密）──▶ alma-relay ◀── WSS ── Loci
                                    ▲
                                    │ 设备名单
                              device-registry
```

| Worker | 从哪来 | 做什么 | 它看到什么 |
| --- | --- | --- | --- |
| alma-relay | 单独 clone 的仓库 | 隧道。主机主动外连并保持一条 WSS；客户端连到 relay，请求经主机那条连接转过去。它只转发字节，不懂 Loci 的协议。 | 密文、路由令牌和连接元数据；不写盘，也拿不到连接码。 |
| device-registry | 本仓库的 `services/device-registry` | 设备组名单。每个组一个 Durable Object（SQLite），只保存组密钥签名过的设备记录和删除墓碑，不转发流量。 | 明文元数据：设备名、平台、公钥、最后活跃时间和 IP。 |

两个 Worker 部署在同一个 Cloudflare 账号下，互不依赖。**Workers Free 套餐就够**：两个都使用 SQLite 版 Durable Object，空闲时几乎不产生费用。

Loci 的端到端加密在 Worker 之上：连接双方用 X25519 协商，设备密钥参与认证，会话用 AES-256-GCM。relay 只能看到密文。导师、课程、对话、笔记和 agent CLI 都只在主机上，远程端通过隧道读写主机，不做同步；也没有账号服务，设备之间的信任来自设备组。

开始前准备：

- 一个 Cloudflare 账号。
- Node.js 20 或更新版本（`node --version`）。
- 两台 Mac 上装同一个版本的 Loci 桌面版，设置里有“远程访问”一节。
- 两台机器都能访问 `*.workers.dev`。

下面的命令都在终端执行。`<子域>` 是 Cloudflare 分配给你的 workers.dev 子域，Wrangler 部署后会打印完整地址。

## 2. 部署 alma-relay

```sh
git clone https://github.com/yetone/alma-relay && cd alma-relay
npm install
npx wrangler login        # 第一次部署时登录 Cloudflare
npx wrangler deploy
```

最后一行会输出 `https://alma-relay.<子域>.workers.dev`，记下它。

**设置 relay 注册密钥。** 不设的话，任何知道这个地址的人都能在上面开隧道，占用你的连接和额度。他们仍然连不到你的电脑（那需要设备组派生的连接码），但没有必要把 relay 借给别人用。

```sh
npx wrangler secret put RELAY_REGISTRATION_KEY
```

输入一串随机字符串（例如 `openssl rand -base64 32` 的输出）。稍后在 Loci 的“relay 注册密钥”里填同一个值。密钥立即生效，不用重新部署。

可选：`LOCATION_HINT` 指定隧道所在的 Cloudflare 区域，比如 `apac`、`enam`、`weur`。默认建在离主机近的地方；主机走代理、离客户端很远时，可以把它挪到客户端附近。它是普通变量，写进 `wrangler.jsonc` 的 `vars`，再部署一次：

```jsonc
"vars": { "LOCATION_HINT": "apac" }
```

验证：

```sh
curl https://alma-relay.<子域>.workers.dev/healthz
# {"ok":true,"edition":"cloudflare",...}
```

## 3. 部署 device-registry

在 Loci 仓库根目录：

```sh
cd services/device-registry
npm install
npx wrangler deploy
```

输出 `https://loci-device-registry.<子域>.workers.dev`，记下它。

可选：设置 `REGISTRY_KEY` 作为访问门槛。设置后**所有请求**都要带 `Authorization: Bearer <key>`，包括 `/healthz` 和每台设备的注册、心跳；所以每台 Loci 的“注册表密钥”都要填同一个值。

```sh
npx wrangler secret put REGISTRY_KEY
```

验证：

```sh
curl https://loci-device-registry.<子域>.workers.dev/healthz
# {"ok":true}

# 设了 REGISTRY_KEY 时：
curl -H "Authorization: Bearer <key>" \
  https://loci-device-registry.<子域>.workers.dev/healthz
```

## 4. 在笔记本（主机）上

打开 Loci → 设置 → 远程访问。

### 服务地址

每改一个字段，失焦时保存；也可以点这一节右上角的“保存”。保存后立即起停隧道，不需要重启 Loci。

| 字段 | 填什么 |
| --- | --- |
| relay 地址 | `wss://alma-relay.<子域>.workers.dev` |
| relay 注册密钥 | 第 2 步设的 `RELAY_REGISTRATION_KEY`；没设就留空 |
| 注册表地址 | `https://loci-device-registry.<子域>.workers.dev` |
| 注册表密钥 | 第 3 步设的 `REGISTRY_KEY`；没设就留空 |
| 设备名 | 其他设备看到的名字，例如 `MacBook`；留空时是 `Loci` |

填完点一次“保存”再往下走。设备名要在创建设备组之前写进设置，否则注册表里记下的是 `Loci`。

relay 地址要写 `wss://`，不能写 `https://`。Loci 把这个字符串直接当作 WebSocket 地址，用来连 relay 的 `/agent` 和 `/c/<token>/__loci__`；`https://` 不是合法的 WebSocket 方案，隧道不会建立，设置页也不会报错。最常见的现象是设备列表里主机在线，却没有“连接”按钮。本地开发的 relay 写 `ws://127.0.0.1:8787`。

两台设备必须填同一个注册表地址：它决定名单从哪里读。建组之后不要随便改；改了等于换一份名单，要改回原地址，或让所有设备退出后重新加入。

### 打开远程访问

打开顶部的“远程访问”开关。状态会变成“已开启。远程访问期间，这台电脑接电源时不会睡眠。”

### 创建设备组

在“设备组”里点“创建设备组”。这一步需要已经填好注册表地址，否则会提示 `Set the device registry first`。

设备名在这一步写进注册表。之后再改“设备名”只会影响以后重新加入时的记录，列表里的旧名字不会跟着变；要改名，先退出设备组再用新名字加入。

### 复制组密钥

创建后，“组密钥”一行默认隐藏，点“显示”查看、“复制”复制。文本形如：

```text
loci-group:BQUF...?registry=https%3A%2F%2Floci-device-registry.<子域>.workers.dev
```

`loci-group:` 后面是 32 字节的组密钥，`?registry=` 带着注册表地址。把整段文本发给其他设备。

开关和建组的先后无所谓：relay 地址和注册表地址填好、并且已经加入设备组之后，relay 隧道才会启动。

### 电源

远程访问开着时，Loci 会启动 `caffeinate -s`，接电源时阻止系统空闲睡眠。用电池时这条断言不生效；合盖后系统仍会睡眠。主机一睡，所有客户端都断开；醒来后客户端会自动重连。

## 5. 在 Mac mini（客户端）上

1. 安装同一个版本的 Loci。
2. 设置 → 远程访问 → 服务地址：填**注册表地址**和**注册表密钥**（如果设了），再填“设备名”（主机在设备列表里看到的名字，留空就是 `Loci`），点“保存”。relay 地址和 relay 注册密钥只有这台电脑也要当主机时才需要填；客户端连主机用的是主机心跳里带回来的 relay 地址。组密钥里通常已经带着注册表地址，粘贴时会自动写入，覆盖这里的值。
3. 设备组 → “加入设备组”，粘贴上一步复制的组密钥，点“加入”。
4. 在“设备”里找到笔记本，应该显示“在线”，下面一行是平台和最后活跃时间。点“连接”。
5. Loci 会打开一个新窗口，顶部状态栏显示 `Connected to <笔记本的设备名>`。首次连接时主机可能还没读到这台新设备，客户端会自动重试一次，通常几秒内连上。

客户端不需要打开“远程访问”开关，除非它也要被别的设备连接。一台设备同一时间只能在一个组里；之前加入过别的组，要先“退出设备组”。

连接窗口里看到的就是笔记本的工作区：导师、课程、对话、笔记、画布、PDF 高亮都在主机上读写。窗口本身不跑 agent CLI，工作区数据不在本地保存。断线时状态栏变成 `Disconnected from <设备名>: <原因>`，旁边有 `Reconnect`；Loci 也会按退避自动重连。

## 6. 日常使用与安全

- **在线。** 设备列表每 30 秒重读一次本机缓存的名单；名单本身在后台约每 60 秒从注册表刷新一次，打开设置页时也会立刻读一次。“在线”指 90 秒内收到过心跳。主机把 relay 地址和连接码派生出的路由令牌登记为路由，其他成员据此连过去，所以设备在线不等于一定能连：没有路由时不会显示“连接”。
- **移除是永久的。** 在任意成员设备的“设备”列表里点“移除”。主机会立即断开它已经建立的连接，注册表留下墓碑，同一个 `deviceId` 之后永远不能再加入。被移除的机器想回来，要先在自己那边“退出设备组”（这会换一把新的设备密钥），再用组密钥加入。
- **组密钥等于这台电脑的完全控制权。** 拿到它的人可以加入一台自己的设备，并以那台设备的身份读写主机上的全部内容，也可以移除组里的其他设备。把它当密码保存，不要发在群里。
- **组密钥泄露时轮换。** 在主机上“退出设备组”，再“创建设备组”，把新的组密钥发给其他设备；每台设备先“退出设备组”，再用新组密钥“加入”。本实现的组 ID 就是组公钥，换组密钥必然换组：旧组里的设备都连不到主机了，要连新组必须重新加入，旧设备不会自动跟过来。各设备的“退出”需要能访问注册表，离线的机器等它下次上线再退出即可。
- **主机离线。** 已经打开的连接窗口保留断线前收到的对话，可以继续翻看，状态栏显示断线原因；发消息和写入要等重新连上。客户端不缓存对话和文档，只留下一份导师名单和主机共享设置；关掉窗口再打开时如果主机仍然离线，名单还在，对话要等连接恢复。重连后以主机为准补齐。
- **两个 Worker 看到什么。** relay 只看到密文、路由令牌和连接元数据，不写盘。注册表看到明文元数据：设备名、平台、公钥、最后活跃时间和 IP。记录本身有组签名，注册表无法伪造，但可以不返回、回滚列表或拒绝服务；吊销的最终执行点是主机在握手时拒绝已移除的设备。
- **密钥存在哪里。** 设备密钥和组密钥存在 macOS 钥匙串里，Loci 只在需要时读取；`remote.json` 里只有开关、地址、密钥门槛和设备名。

## 7. 排查

按这个顺序查，前面的问题会掩盖后面的。

1. **relay 健康检查。** `curl https://alma-relay.<子域>.workers.dev/healthz`。不是 `{"ok":true,...}` 就是地址错或 Worker 没部署成功。relay 的日志用 `npx wrangler tail` 看（在 alma-relay 目录里）。
2. **注册表健康检查。** `curl https://loci-device-registry.<子域>.workers.dev/healthz`。设了 `REGISTRY_KEY` 时，不带 `Authorization: Bearer <key>` 返回 401 是正常的。
3. **设备列表里主机是否在线。** 两台设备都要能看到对方，自己那一行带“本机”。主机不在线：确认它开着、Loci 在运行、开关是开的。刚打开开关时最多等 30 秒心跳。
4. **在线但没有“连接”按钮。** 说明主机的记录里没有路由。检查主机上的 relay 地址是不是 `wss://`、relay 是否可达、relay 注册密钥是否和 Worker 的 `RELAY_REGISTRATION_KEY` 一致。主机只有在 relay 隧道注册成功之后才把路由写进心跳。
5. **两边的密钥是否一致。** relay 注册密钥只影响主机注册隧道；注册表密钥每台设备都要填。组密钥不一致时两台设备根本不在同一个 `groupId`，各自只看到自己。
6. **主机是否睡眠。** 合盖、用电池都会睡。接上电源、打开盖子，等客户端自动重连，或点 `Reconnect`。

注册表和设备组相关的报错会直接显示在设置页，前面通常带有 `Could not …: ` 前缀：

| 现象 | 原因 |
| --- | --- |
| `Set the device registry first` | 还没填注册表地址 |
| `This device is already in a device group. Leave it first.` | 这台设备已经在一个组里，先退出 |
| `That is not a Loci group key` | 组密钥不完整，或多复制了字符 |
| `Could not reach the device registry: …` | 注册表地址错、网络不通，或 Worker 未部署 |
| `The device registry refused: Unauthorized` | 注册表密钥不对 |
| 主机在线，但客户端点不了“连接” | 主机没有 relay 路由：地址不是 `wss://`、relay 注册密钥不对，或 relay 没起来 |
| 连接窗口反复显示 `Connecting to …` 和 `Disconnected from …` | 主机睡眠或已退出、Loci 没在运行，或主机的 relay 注册刚变过（最多等一次心跳） |
