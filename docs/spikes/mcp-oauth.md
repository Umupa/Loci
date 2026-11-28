# MCP 无服务器授权的验证

2026-11-24，macOS 27.2，Swift 6.4.2。可以不靠任何服务器，在本机用 OAuth 2.1 连远程 MCP。12 家里有 9 家接受本机的动态注册和 `127.0.0.1` 回调，包括 Notion、Linear、Atlassian 和 Sentry。GitHub 没有动态注册，但它的 MCP 接受 `gh` 已登录的 token，实测列出了工具，标注完整。Asana、Figma 需要预先注册的应用，第一批不做。原型只用了 Foundation、Network、CryptoKit 和 AppKit，不需要第三方库。 [MCP 授权规范 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)

## 各家结果

原型做了这些事：发一个不带 token 的 `initialize`，从 401 的 `WWW-Authenticate` 里找元数据地址。找不到就按规范的顺序试 well-known 地址，读 RFC 9728 和 RFC 8414 元数据。然后在 `127.0.0.1` 的随机端口上监听，向注册端点注册一个公开客户端（`token_endpoint_auth_method: none`），拼出带 PKCE S256、`state`、`resource` 的授权地址，最后不跟随跳转去 GET 这个地址。

| 服务 | MCP 地址 | RFC 9728 | 授权服务器（RFC 8414） | 动态注册 | 回环回调 | 换端口 | CIMD |
|---|---|---|---|---|---|---|---|
| Notion | `mcp.notion.com/mcp` | 401 头给出 | 同主机 | 201，`none` | 302 到 Notion 授权页 | 接受 | 支持 |
| Linear | `mcp.linear.app/mcp` | 401 头给出 | 同主机 | 201，`none` | 200 授权页 | 接受 | 支持 |
| Sentry | `mcp.sentry.dev/mcp` | 401 头给出 | 同主机 | 201，`none` | 200 授权页 | 接受 | 支持 |
| Atlassian | `mcp.atlassian.com/v1/mcp` | 没有，401 头里也没有 | 同主机 | 201，`none` | 200 授权页 | 500 | 不支持 |
| Stripe | `mcp.stripe.com` | 401 头给出 | `access.stripe.com/mcp` | 201，`none` | 302 到登录 | 未测 | 不支持 |
| Vercel | `mcp.vercel.com` | 401 头给出 | `vercel.com` | 201，`none` | 200 页面，结果不确定 | 不确定 | 支持 |
| Supabase | `mcp.supabase.com/mcp` | 401 头给出 | `api.supabase.com` | 201，只支持带密钥 | 303 到授权页 | 422 | 不支持 |
| Canva | `mcp.canva.com/mcp` | 401 头给出 | 同主机 | 201，`none` | 302 到 Canva 授权页 | 未测 | 支持 |
| Hugging Face | `huggingface.co/mcp` | 有 | 同主机 | 有端点，只支持带密钥 | 未测 | 未测 | 支持 |
| GitHub | `api.githubcopilot.com/mcp/` | 401 头给出 | `github.com/login/oauth` | **没有** | — | — | 不支持 |
| Asana | `mcp.asana.com/v2/mcp` | 401 头给出 | `app.asana.com` | **没有**，且只支持带密钥 | — | — | 不支持 |
| Figma | `mcp.figma.com/mcp` | 401 头给出 | `api.figma.com` | 403，只放行名单内的客户端 | — | — | 不支持 |

- 所有授权服务器都声明 `S256`。
- 「换端口」指注册时用端口 A，授权时把回调换成端口 A+1。Notion、Linear、Sentry 照常给出授权页，Atlassian 和 Supabase 拒绝。把回调换成没注册过的 `https://example.com`，Notion、Linear 和 Sentry 都返回 400 `Invalid redirect URI`，说明它们只对回环地址放宽了端口。结论是每次连接都新注册一次，回调端口用注册时那个，不要指望能换端口。
- Vercel 的授权页由脚本渲染，GET 拿不到结果。要等登录后才能判断。
- Atlassian 不提供 RFC 9728 元数据，要退回到「MCP 主机就是授权服务器」才能发现。这是 2025-03-26 版规范的做法，新规范已经没有这条。实现时要保留这个退路，否则连不上 Atlassian。
- 授权服务器有的在别的主机上（Stripe、Vercel、Supabase、GitHub、Asana、Figma）。必须按 `authorization_servers` 找，不能假定和 MCP 同主机。Stripe 的 issuer 带路径，要用 RFC 8414 的路径插入格式。

## GitHub

GitHub 的授权服务器是 `github.com/login/oauth`，没有注册端点，所以要先注册一个 GitHub OAuth 应用。注册免费、不用审核，但网页流程换 token 时 `client_secret` 是必填的。本机应用里的密钥谈不上保密。设备流程只要 `client_id`，不用密钥。网页流程的回环回调可以换端口。 [GitHub OAuth 应用授权](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps)

本机 `gh` 已经登录（scope：`gist`、`read:org`、`repo`、`workflow`）。用 `gh auth token` 当 bearer 调 GitHub MCP，`initialize` 和 `tools/list` 都成功了，返回会话 ID，用时约 2 秒。

| 地址 | 工具 | `readOnlyHint: true` | `false` | 没标注 |
|---|---:|---:|---:|---:|
| `/mcp/`（默认工具集） | 46 | 28 | 18 | 0 |
| `/mcp/readonly` | 28 | 28 | 0 | 0 |
| `/mcp/x/all` | 113 | 74 | 39 | 0 |
| `/mcp/x/all/readonly` | 74 | 74 | 0 | 0 |

服务器提供的只读地址和按 `readOnlyHint` 筛出来的结果完全一致。有一条要注意：`run_secret_scanning` 标的是只读。

结论：1.8.1 的 GitHub 连接器用本机 `gh` 的 token 加 `/mcp/x/all/readonly` 地址，同时按 `readOnlyHint` 筛一遍，两道保险。没装 `gh` 时，退回到 Loci 自己注册的 GitHub OAuth 应用走设备流程（只要 `client_id`）。1.8.2 的 `gh` 命令行连接器和这个复用同一个检测。

## 只读标注

Notion、Linear、Sentry、Atlassian 要真实登录后才能列出工具，这次没有测到标注比例（见下面「要你做的」）。规范对没标注的工具没有保证，所以「没标注一律拒绝」（CN-S4）是对的。只有 GitHub 实测到了完整标注。如果某家大多数工具都没标注，那家连上了也读不了什么，伙伴主页上应该能看出来，比如显示「可读的工具 0 个」。

## 规范要点

- 2025-11-25 版规范把客户端注册的优先级定为：预注册、CIMD（Client ID Metadata Document）、动态注册。动态注册从 SHOULD 降为 MAY，「为了向后兼容」。CIMD 要求客户端把元数据放在一个 HTTPS 地址上，这需要一个静态网页（比如 GitHub Pages），不需要能运行代码的服务器。Notion、Linear、Sentry、Vercel、Canva 已经声明支持。 [规范：客户端注册](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization#client-registration-approaches)
- 规范对 CIMD 加回环回调这种组合明确提出了风险：任何人都能拿着 Loci 的 `client_id` 冒充 Loci。动态注册每次签发一个新的 `client_id`，没有这个问题。所以第一批先用动态注册，CIMD 以后再说。
- `resource` 参数在授权请求和 token 请求里都必须带（RFC 8707）。缺少 `code_challenge_methods_supported` 时必须拒绝继续。授权服务器必须轮换公开客户端的 refresh token。 [2025-06-18 版](https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization)
- scope 优先用 401 头里的 `scope`（Notion 给的是 `default`，Linear 给的是 `read write`），没有时才用 `scopes_supported`。Linear 有只读的 `read` scope，可以只申请 `read`，多一层保护。

## 原型

`spike/mcp-oauth/main.swift`，一个文件，约 250 行。

- `URLSession`：发现、注册、换 token、MCP 请求。用一个返回 `nil` 的跳转代理来观察 302。
- `NWListener`：`requiredLocalEndpoint` 绑在 `127.0.0.1`，端口填 `.any`，系统分配端口后立刻可以读到。只监听回环地址，不会弹防火墙提示。
- `CryptoKit` 的 SHA256 做 PKCE，`SecRandomCopyBytes` 生成 verifier 和 state。
- Streamable HTTP：返回的 `Content-Type` 可能是 `application/json`，也可能是 `text/event-stream`，两种都要能解析。要带上 `Mcp-Session-Id` 和 `MCP-Protocol-Version`，`initialize` 之后发 `notifications/initialized`，`tools/list` 要按 `nextCursor` 翻页。

## 对 1.8.1 的建议

**第一批**：Notion、Linear、GitHub（`gh` token），以及「添加 MCP 地址」。粘贴任意地址的连接走同一条通用流程：401 头、well-known 回退、动态注册。Sentry、Atlassian、Canva、Stripe 和 Notion、Linear 走的是同一条路，不用单独写代码，可以放进「可连接」列表，但要等真实登录验收过才放。Asana、Figma 不进列表，粘贴它们的地址时提示「这家需要预先注册的应用」。

**实现要点**
- `LociConnect` 只做发现、注册、PKCE、回环接收、换 token、刷新和 Streamable HTTP 客户端。不需要依赖。
- 每个连接保存这些：MCP 地址、`resource`、issuer、`client_id`、注册时的回调地址、access token、refresh token、到期时间。token 和 `client_id` 都存钥匙串。
- 刷新失败（`invalid_grant`）就把这个连接标成需要「重新连接」（CN-S7）。重新连接时重新注册一次，不复用旧的回调端口。
- 授权页用 `NSWorkspace.open` 在默认浏览器里打开，不用内置 WebView：用户的登录状态在默认浏览器里，而且 RFC 8252 不建议在应用内嵌网页做授权。回环接收到回调后，回一个简短页面，让用户回到 Loci。等待加超时，用户关掉浏览器也能取消。
- 只读放行：`tools/list` 的结果按连接缓存，`call` 时检查 `readOnlyHint == true`。没标注、标 `false`、或者不在缓存里的工具一律拒绝（CN-S4）。服务器有只读地址的（比如 GitHub）就用只读地址。
- 远程打开时不能连接（CN-S8）：回环回调只能在 Host 那台 Mac 上收到，这和设计一致。

**风险**
- token 有效期、refresh token 是否轮换、Notion 和 Linear 的只读标注比例，这次都没有拿到证据，要等真实登录。
- 动态注册每连一次就在对方那里多一个客户端，有的服务器可能限流或清理。重新连接本来也会重新注册，问题不大。
- 规范正在从动态注册转向 CIMD。以后某家只支持 CIMD 时，Loci 要在静态 HTTPS 地址上放一份元数据文件。
- Hugging Face 不带 token 访问时，`initialize` 返回 200，但后续请求返回 401。可选授权的服务器要按「有 401 才授权」处理。

## 要你做的

在这个 worktree 里跑一次，每家会弹出浏览器授权页，登录并同意：

```sh
swiftc -O -enable-bare-slash-regex spike/mcp-oauth/main.swift -o /tmp/mcp-spike
/tmp/mcp-spike login https://mcp.notion.com/mcp -v
/tmp/mcp-spike login https://mcp.linear.app/mcp -v
/tmp/mcp-spike login https://mcp.sentry.dev/mcp -v      # 可选
/tmp/mcp-spike login https://mcp.atlassian.com/v1/mcp -v # 可选
```

每次会打印回调是否收到、`expires_in`、有没有 refresh token、刷新是否成功和 refresh token 是否轮换，以及工具数量和 R、W、? 三类的明细。token 不会落盘，进程退出就没了。把输出补进上面的表格，就能确定第一批。
