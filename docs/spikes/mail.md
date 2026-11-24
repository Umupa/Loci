# 读 Mail.app 邮件的验证

2026-11-24，macOS 27.2。**结论：直接读 `~/Library/Mail` 的本机数据**，用 AppleScript 问 Mail.app 只作退路。不走 Gmail 的 Google OAuth：`gmail.readonly` 是受限权限，必须通过受限权限审核，存储或传输这类数据时还要过安全评估。这条判断成立。这次只验证到「没有授权时读不到」为止。真实的计数和耗时需要先给完全磁盘访问权限再跑原型（见末尾）。

## 两条路的对比

| | 读本机数据（Envelope Index + `.emlx`） | 用脚本问 Mail.app（AppleScript / JXA / ScriptingBridge） |
|---|---|---|
| 系统授权 | 完全磁盘访问（`kTCCServiceSystemPolicyAllFiles`） | 自动化：Loci → Mail（`kTCCServiceAppleEvents`）。加固运行时下签名还要带 `com.apple.security.automation.apple-events` 权利，`Info.plist` 要写 `NSAppleEventsUsageDescription` |
| 首次授权体验 | 应用不能弹窗请求。只能把用户带到「系统设置 › 隐私与安全性 › 完全磁盘访问权限」，让用户自己打开开关，通常还要重开应用 | 第一次发 Apple Event 时系统弹窗，点「好」就行，体验最好 |
| 覆盖账户 | Mail.app 里所有账户（IMAP、iCloud、Gmail、Exchange）都在同一个库里。只有已经同步下来的才有 | 同左，只能看到 Mail.app 看得到的 |
| Mail.app 没开 | 能读。库是 SQLite（WAL），以只读方式打开 | 会把 Mail.app 启动起来（出现窗口、开始同步）。后台 run 不能接受这一点 |
| 改变已读状态 | 不会。只读打开 SQLite 和读文件都不会写 | 读 `content` 的设计上不会标已读，原型里做了前后对比，待实测 |
| 速度 | 信封查询是一次 SQL（毫秒级，待实测）。正文是读文件 | 每个属性都是一次 Apple Event 往返。逐封读取的开销随数量线性增长，大收件箱很慢（待实测） |
| 格式稳定性 | **没有公开文档**。目录有版本号（`V10` 之类），表结构随系统更新可能变化。二手资料说从 Ventura 到 Tahoe 一直是 `V10`，也有说法不一致 | 有字典（`Mail.sdef`），多年稳定 |
| 风险 | 完全磁盘访问的权限太大，用户会犹豫。表结构变了就要适配 | 驱动一个有界面的应用；脚本超时；Mail 正忙时会卡住 |

关于没有授权时的情况，这次实测：当前终端没有完全磁盘访问权限，`ls ~/Library/Mail`、`~/Library/Containers/com.apple.mail` 和 `~/Library/Accounts` 都返回 `Operation not permitted`，原型的 `opendir` 也失败了。这说明这些路径受 TCC 保护，Loci 必须单独拿到这个授权。Mail.app 当时没有运行，上次使用是 2026-11-03。

## 为什么选读本机数据

- 后台 run 发生在关窗或者用户不在的时候。脚本那条路会把 Mail.app 拉起来，在用户面前打开一个窗口，这和「不打扰」矛盾。
- 只读由机制保证：SQLite 用 `SQLITE_OPEN_READONLY` 打开，`.emlx` 只读文件，代码里根本不存在写的路径。脚本那条路上，Mail 的字典本来就有 `move`、`delete`、`set read status`，只读只能靠我们不去调用。
- 一次授权覆盖所有账户。只要 Mail.app 配好了 Gmail、Exchange、iCloud，就不用再接各家的 OAuth。

代价是授权的门槛，以及格式没有文档。应对办法：表结构在启动时探测，按列名查询，查不到所需的列就把这个连接器标成「不可用」，并且明确告诉伙伴。CN-S14 的验收要在当时最新的系统上实跑一次。

## Gmail 的 Google OAuth

成立，不走。

- Gmail API 的权限分级里，`gmail.readonly`（"View your email messages and settings"）和 `gmail.metadata` 都属于 **Restricted**。 [Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes)
- 受限权限要走受限权限的应用审核：限定用途、提供演示视频、对每个权限说明理由。存储或传输受限数据的应用要「submitting to an annual security assessment from a Google empanelled group of security assessors」，每年复审一次。 [Restricted scope verification](https://support.google.com/cloud/answer/13464321) · [Security assessment](https://support.google.com/cloud/answer/13465431)
- 豁免只适用于个人模式（只有开发者自己能用）、少于 100 个用户（会显示未验证提示）和组织内部应用，都不适合公开发布的 Loci。 [When verification is not needed](https://support.google.com/cloud/answer/13464323)

Gmail 用户在 Mail.app 里加上 Gmail 账户，就由上面这条路覆盖。

## 原型

- `spike/mail/envelope.swift`：只读打开最新版本目录下的 `MailData/Envelope Index`，输出这些内容：表和主要列名、邮件总数、按账户（协议加账户哈希，不打印地址）的计数、最近 N 封信封的查询耗时、遍历找 `.emlx` 和读正文的耗时与字节数、读之前和之后已读状态变化的数量。不打印任何主题、地址或正文。
- `spike/mail/script.js`（JXA）：账户数和类型、统一收件箱的邮件数、逐封和批量取最近 N 封信封的耗时、读 N 封正文的耗时和字符数、已读状态前后对比。只调用读取的属性。

## 对 1.8.2 的建议

**进第一批**：本机读取。连接时打开「完全磁盘访问权限」设置页，提示用户把 Loci 拖进去或打开开关，然后探测能不能读，读到了就移到已连接。

**实现要点**
- 放在 `LociConnect` 的本机来源里。路径从外面传进来，测试里用一个假的 `Envelope Index` 和 `.emlx` 目录。
- 版本目录取最大的 `V*`。列名在打开时用 `pragma table_info` 探测。主要用到的表是 `messages`、`mailboxes`、`subjects`、`addresses`，以 `messages.mailbox → mailboxes.url` 区分账户。
- 正文按需读 `.emlx`（前面是字节数，后面是 RFC 822 原文），解析成纯文本后加上外部内容标记（CN-S6）。只有信封、正文还没下载的（`.partial.emlx` 或者文件不存在），就照实说只有信封。
- 签名要稳定：TCC 按代码签名的指定要求记住授权。Loci 用的是固定的自签名证书，更新后授权应该还在，要在一次升级里验证。
- 退路：如果某个系统版本的格式变了，再考虑 JXA。前提是只在 Mail.app 已经运行时调用，不主动启动它。

**风险**
- 完全磁盘访问的权限太大，要有用户愿意给。拒绝的比例未知。
- 格式没有文档，跨大版本要回归。
- 原型的实测数字（计数、耗时、已读状态不变）这次都没有拿到。

## 要你做的

1. 系统设置 › 隐私与安全性 › 完全磁盘访问权限，给运行下面命令的终端打开开关（之后可以关掉）。
2. 在这个 worktree 里：
   ```sh
   swiftc -O spike/mail/envelope.swift -o /tmp/mail-envelope && /tmp/mail-envelope 50
   ```
   先退出 Mail.app 跑一次，再打开 Mail.app 跑一次。
3. 可选，比较脚本那条路（会弹「终端想控制 Mail」的授权，Mail 没开时会被启动）：
   ```sh
   osascript -l JavaScript spike/mail/script.js 50
   ```
4. 把两次输出贴回来。只有计数和耗时，不含正文和地址。
