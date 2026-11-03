# Loci 设备组注册表

远程访问用的设备组注册表。它是一个独立的 Cloudflare Worker，每个设备组对应一个 Durable Object（SQLite 存储），保存组内设备的签名记录和删除墓碑。它和 relay 部署在同一个 Cloudflare 账号下，但互不依赖：注册表只负责验签和存储，不转发流量，不参与连接。

**注册表不可信。** 它保存和转发的都是签名过的数据，客户端拿到 `GET /g/<groupId>/devices` 的结果后必须自己验签。被攻破的 Worker 无法伪造记录，但可以不下发、回滚到旧列表或拒绝服务。

## 协议

所有请求和响应体都是 JSON。时间戳一律是 Unix 毫秒：整数，等于 `Date.now()` 的值，不是秒也不是 ISO 字符串。

### 密钥与 ID

- **组密钥**：用户持有的 32 字节高熵随机数 `groupSecret`。
- **组签名密钥**：Ed25519，种子为 `HKDF-SHA256(ikm=groupSecret, salt="", info="loci-group-sign-v1", 32 字节)`。组私钥只存在于客户端。
- **`groupId`**：组签名公钥 32 字节的 base64url（无填充）编码，43 个字符。
- **设备密钥**：每台设备自己的 Ed25519 密钥对。`devicePubKey` 是设备公钥 32 字节的 base64url 编码。
- **`deviceId`**：对设备公钥的**原始 32 字节**（base64url 解码之后，不是 base64url 文本）做 SHA-256，再对摘要做 base64url（无填充）编码，取前 22 个字符。`src/protocol.mjs` 的 `deviceIdFor` 和 `test/protocol.test.mjs` 的固定向量是准确定义。

签名消息是 UTF-8 的：

```
loci-registry-v1\n<type>\n<canonicalJson(payload)>
```

`type` 为 `device`、`removal` 或 `heartbeat`。`canonicalJson` 把对象的键按字典序排列、递归处理嵌套对象、不输出空白，数组保持原顺序。本仓库的 `src/protocol.mjs` 是参考实现。

### API

| 方法与路径 | 请求体 | 签名者 | 作用 |
| --- | --- | --- | --- |
| `PUT /g/<groupId>/devices/<deviceId>` | `{ record, sig }` | 组私钥，type=`device` | 加入或更新设备，保留已有 `lastSeen`/`route`；该 `deviceId` 被移除过则永久拒绝 |
| `DELETE /g/<groupId>/devices/<deviceId>` | `{ removal, sig }` | 组私钥，type=`removal` | 永久移除设备，留下墓碑 |
| `POST /g/<groupId>/devices/<deviceId>/heartbeat` | `{ beat, sig }` | 设备私钥，type=`heartbeat` | 只更新 `lastSeen` 和 `route` |
| `GET /g/<groupId>/devices` | 无 | — | 列出设备与墓碑 |
| `GET /healthz` | 无 | — | 健康检查 |

`record` 的字段：

```json
{
    "deviceId": "…22 个字符…",
    "name": "Mac mini",
    "devicePubKey": "…base64url…",
    "platform": "macos",
    "addedAt": 1760000000000
}
```

`removal` 是 `{ "deviceId": "…", "removedAt": 1760000000000 }`。`beat` 是 `{ "deviceId": "…", "ts": 1760000000000, "route": "可选字符串" }`；`route` 省略时清空为 `null`，以后可以放 relay 路由信息。

写入成功返回 `{ "ok": true }`；心跳还返回 `{ "lastSeen": 1760000000000, "route": "…" }`。列表返回：

```json
{
    "devices": [{ "record": {}, "sig": "…", "lastSeen": 1760000000000, "route": null }],
    "removals": [{ "removal": {}, "sig": "…" }]
}
```

设备按 `deviceId` 排序，顺序稳定。从未出现过的组返回两个空数组。

### 校验规则

- 签名必须由对应公钥验证通过：`device` 和 `removal` 用 `groupId` 里的组公钥，`heartbeat` 用该设备已存记录的 `devicePubKey`。
- `record.deviceId`、`removal.deviceId`、`beat.deviceId` 都要和路径一致；记录的 `deviceId` 还必须等于由 `devicePubKey` 派生的值。
- `addedAt`、`removedAt`、`ts` 必须是整数毫秒，且与 Worker 当前时间相差不超过 5 分钟。
- **移除是永久的。** 某个 `deviceId` 一旦有墓碑，之后任何 `PUT` 都返回 409，与 `addedAt` 多新无关。被移除的机器只能生成新的设备密钥、以新的 `deviceId` 重新加入。
- 心跳只能改 `lastSeen` 和 `route`，不能改设备名、公钥或加入时间。设备被永久移除后心跳返回 404。
- 删除是幂等的：对不存在或已移除的设备再次 `DELETE` 仍返回 `{ "ok": true }`，并保留第一次删除的墓碑时间。

### 状态码

| 状态码 | 情况 |
| --- | --- |
| 400 | 路径或请求体格式错误（包括缺少 `record`/`removal`/`beat` 或 `sig`）、ID 对不上、时间戳不是整数毫秒 |
| 401 | 签名验证失败；设置了 `REGISTRY_KEY` 但 Bearer 缺失或不对 |
| 404 | 路由不存在；心跳的设备未注册 |
| 405 | 路径存在但方法不对 |
| 409 | 时间戳在 5 分钟窗口外；该 `deviceId` 已有墓碑，永久拒绝加入 |

设置了环境变量 `REGISTRY_KEY` 后，所有请求（包括 `/healthz`）都要带 `Authorization: Bearer <key>`。它只是部署门槛，不是设备身份，不能替代签名。

## 部署

需要 Node.js 20+ 和 Cloudflare 账号：

```sh
cd services/device-registry
npm install
npx wrangler login
npx wrangler deploy
```

部署后 Wrangler 会输出 `https://loci-device-registry.<account>.workers.dev`。可选：

```sh
npx wrangler secret put REGISTRY_KEY          # 设置访问门槛
# 或在 wrangler.jsonc 里添加 routes，用自定义域名
```

本地开发：

```sh
npm run dev                                   # http://127.0.0.1:8787
curl http://127.0.0.1:8787/healthz
```

`wrangler dev` 在本地跑 workerd 和 SQLite DO，不需要登录。DO 使用 `new_sqlite_classes`，Free 套餐即可运行。

## 安全性说明

- **客户端必须验签。** 注册表可以少返回设备、返回旧列表或隐藏墓碑。客户端应验证每条 `record`/`removal` 的签名和 `deviceId` 派生关系。列表只是提示，吊销的最终执行点是主机在握手时拒绝已移除的设备。
- **移除是永久的。** 墓碑没有撤销接口；同一个 `deviceId` 永远不能再出现。要重新接入那台机器，只能换一把新的设备密钥，以新设备身份加入。怀疑某台设备已泄露时，先 `DELETE` 它，再确认它不再出现在列表里。
- **注册表看到的是明文元数据。** 设备名、平台、公钥、在线时间和 IP 对 Cloudflare 可见。这里不做端到端加密。
- **`lastSeen` 和 `route` 没有签名。** 列表里的这两个字段由注册表直接维护，没有任何签名回执，注册表可以任意篡改。客户端只能把它们当作展示或选路提示，不能据此判断设备可信；连接安全由主机握手和 SecureChannel 保证。
- **组密钥泄露意味着组被接管。** 拿到 `groupSecret` 的人可以签发新设备记录、删除设备、替换墓碑；它不能冒充已有设备发心跳（没有设备私钥），但可以加入一台自己的设备后以该设备身份活动。这时唯一的补救是**轮换组密钥**：重新生成 `groupSecret` 会得到新的 `groupId`，旧组里的所有设备（包括攻击者的设备）都失效，所有成员需要用新组密钥重新加入。组密钥只用于签名，不要发给注册表。
- **轮换组密钥会换组。** 本实现的 `groupId` 就是组公钥，换 `groupSecret` 会得到新的 `groupId`，已有设备需要重新加入。设计稿里“轮换只影响以后的加入”需要独立于公钥的组 ID 才能做到，当前协议没有这一层。
- **5 分钟窗口限制重放**，客户端和服务器的时钟要大致准确。墓碑永久保留，目前没有删除整组的接口。
- **没有速率限制。** 公开部署时由 Cloudflare 的默认防护兜底；`REGISTRY_KEY` 可以挡住扫描，但会分发给每个客户端，不应视为秘密。

## 测试

```sh
npm test
```

用 `node:crypto` 生成 Ed25519 密钥并签名，覆盖：加入与列表、错签/换签名人/改记录、`deviceId` 与公钥不一致、时间窗、删除后永久拒绝重加、换新密钥可以加入、心跳的各种拒绝情况、`canonicalJson` 的键序。

## 文件

- `src/protocol.mjs`：规范化 JSON、base64url、ID 派生、Ed25519 验签、字段校验。只依赖标准全局对象和 WebCrypto，可在 Node 里直接跑。
- `src/group.mjs`：`DeviceGroup` 状态机。存储通过 `get`/`put`/`delete`/`list` 注入，测试用内存 Map。
- `src/worker.mjs`：Worker 路由、`REGISTRY_KEY` 门槛、Durable Object 和 SQLite 存储适配。
- `test/`、`test-support/`：协议和状态机测试。
