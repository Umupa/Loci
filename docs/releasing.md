# 版本与发布

从一次提交到一个发布出去的 Loci (Beta)：版本号、提交规则、CI、定版本、签名和发布流水线。应用叫 **Loci (Beta)**，bundle id 是 `com.loci.native.dev`，不随名字改，改了 macOS 会当成另一个应用，已给的权限都接不上。数据在 `~/Loci-Beta`。

## 产物

| 文件 | 是什么 |
|---|---|
| `output/Loci (Beta).app` | `script/bundle` 组装的应用包，包含 `script/resources/Loci.icns`；`script/run` 和 `script/release` 共用 |
| `output/Loci-Beta-<version>.dmg` | 发布产物：应用加一个 `/Applications` 链接，Apple silicon 与 Intel 通用 |
| `output/Loci-Beta-<version>.dmg.sha256` | 上面那个文件的校验和 |

## 签名

每个版本都用同一个身份签名。签名不变，macOS 才会保留装好的那一份已经拿到的权限（文件夹、通知、钥匙串）。

| 身份 | 怎么签 | 打开时 |
|---|---|---|
| 自签名的「Loci Signing」（现在用的） | `codesign --options runtime`，不公证 | 第一次打开要在「系统设置 › 隐私与安全性」里点「仍要打开」，发布说明里会写 |
| Developer ID Application（需要 Apple Developer Program 会员） | `codesign --options runtime --timestamp`，`notarytool` 公证应用和 dmg，`stapler` 把票据钉上 | 双击就能打开 |
| 都没有（Dmg 流水线） | ad hoc | 只用来确认打包没坏 |

`script/release` 按这个顺序自己选。以后换成 Developer ID，只需要换 secrets，脚本和流水线都不用改；但签名变了，已经装好的用户要重新授权一次。

[Dmg 流水线](../.github/workflows/dmg.yml) 在包依赖、打包脚本、打包资源或发布流水线变更时验证 ad hoc 打包。也可以用 `gh workflow run dmg.yml` 手动打包。

## 版本号

显示出来是 `1.1.0 (412)`：前面是版本号，括号里是构建号。

- **版本号**是三段数字。默认只加最后一段，新功能也一样；加中间一段或第一段只由用户决定，`script/cut-release` 不带 `--user-chose` 时拒绝。tag 是 `v` 加版本号，CHANGELOG 的段落标题是 `## <版本号> — <日期>`，`script/check` 会检查标题的写法。每个版本都是正式的 GitHub release。
- **构建号**是 main 上到这个提交为止的提交数，只增不减，同一个构建号对应同一份代码。
- 应用包里的 `CFBundleShortVersionString` 和 `CFBundleVersion` 就是这两个。发布时版本号取自 tag；本机构建取 HEAD 之前最近的版本 tag，构建号同样是提交数。设置 › 通用最下面显示它们。

## 从一次改动到一个版本

```
提交（feat/fix 带 CHANGELOG 一行） → 推到 main → CI → script/cut-release → 推 tag → Release 流水线
```

1. **提交。** 提交信息用 Conventional Commits。`feat` 和 `fix` 是用户看得到的，同一个提交里要在 CHANGELOG 的 Unreleased 下加一行或改一行；用户看不到的用 `refactor`、`test`、`build`、`ci`、`chore`、`docs`。`script/check` 会检查还没推送的提交，CI 会检查这次推送带来的提交（`script/check-commits`）。
2. **推到 main。** PR 和推送都会触发 [CI](../.github/workflows/ci.yml)：

   | 作业 | 做什么 |
   |---|---|
   | Commits | 检查这次推送或 PR 的提交信息 |
   | Check | 按改了什么选检查，留下各阶段日志 |

   Check 按这次的提交范围选择检查。纯文档改动使用独立的 Swift 包运行架构和文档规则，跳过应用依赖。普通代码改动先检查 Swift 格式，再由 `script/test --affected <提交范围>` 构建和测试受影响的目标，跳过快照和长对话压测。脚本、包配置和流水线的改动涉及所有目标。PR 的新运行会替代同一 PR 的旧运行，`main` 的每次推送都保留自己的检查。

   每天定时运行和用 `gh workflow run ci.yml` 手动运行时，CI 跑完整 `script/check`，也留下全量快照。

   需要应用依赖的作业通过 `.github/actions/packages` 缓存 SwiftPM 的依赖克隆和 whisper.framework，键是 `Package.resolved`。

3. **定版本。** 在 `docs/roadmap.md` 里把这一版挪进「已完成」，「发布」一列写上版本号，提交并推送。然后在 main 上：

   ```sh
   script/cut-release                       # 下一个补丁号
   script/cut-release 1.8.0 --user-chose    # 用户点名的新版本
   ```

   它检查：版本号的写法，并且比已有的版本都大；在 main 上、工作区干净、和 `origin/main` 一致；tag 还没有；Unreleased 下有内容；roadmap 写了这个版本。然后把 Unreleased 改成 `## 1.1.0 — <今天>`，上面留一个空的 Unreleased，提交 `chore: release 1.1.0`，打带注释的 tag。它不推送。

   发版不跑 `script/check`：完整检查本机要五分钟左右，只在用户明确要求时才跑（本机 `script/check`，或 `gh workflow run ci.yml`）。

4. **发布。** `git push origin main v1.1.0`。推上去的 tag 会触发 [release.yml](../.github/workflows/release.yml)，在 tag 指向的提交上打包、签名，再发布。它不跑检查。

   Package 依次：

   1. 确认 tag 在 main 上，用 `script/changelog` 取出这一版的 CHANGELOG 段落作为发布说明；没有这一段就失败。
   2. 检查 secrets：tag 构建必须签名，缺签名的 secret 就失败，不会把 ad hoc 签名的包发给别人。
   3. 把 `MACOS_SIGNING_IDENTITY` 里的 `.p12` 导入一个临时钥匙串：有 Developer ID 就用它；否则信任其中的「Loci Signing」并用它。
   4. `script/release`：通用构建、签名并 `codesign --verify --strict`、Developer ID 时公证、写 dmg 和校验和。
   5. `script/measure-launch`：记录 release 构建的冷启动，**只记录，不卡发布**。
   6. 把 dmg、校验和、发布说明留成 `release` artifact。

   Package 通过后，Publish 先确认上传 R2 的 secrets 都在，再取回 `release` artifact，用校验和核对 dmg，写出 `latest.json`，建 GitHub release、附上 dmg、校验和和 `latest.json`，最后把这三个文件传到 R2。Package 失败就不发布。重跑只替换文件，不会重复建 release。

   推送时 CI 也会检查这个发版提交；它只改了 CHANGELOG，所以只跑文档检查。

`gh workflow run release` 是试 secrets 用的：构建和签名都和 tag 一样，但不发版，dmg 留成 workflow artifact。

发出去的版本有问题时不删 tag、不改已发布的 CHANGELOG 段落，修好后发下一个版本。

## 下载与更新源

应用按顺序读两份 `latest.json`（`Sources/LociMedia/Updates/ReleaseFeed.swift`），先读到的为准：

| 顺序 | 地址 | 放在哪 |
|---|---|---|
| 1 | `https://dl.umupa.fun/loci/latest.json` | Cloudflare R2 的 `loci-releases` 桶，自定义域名 `dl.umupa.fun` |
| 2 | `https://github.com/Umupa/Loci/releases/latest/download/latest.json` | 最新 GitHub release 的附件 |

两处都不走 `api.github.com`，不受它的匿名限流。`latest.json` 写版本、dmg 的 SHA-256 和下载地址（R2 在前，GitHub 在后）；应用按顺序下载，校验和对不上就换下一个地址，之后照旧核对签名。R2 上 dmg 永久缓存，`latest.json` 缓存五分钟，并且最后上传。

## 在本机

```sh
script/release                                   # 用本机的 Developer ID 或「Loci Signing」签名；Developer ID 加公证凭据时公证
LOCI_ARCHS="arm64 x86_64" script/release         # 通用包（默认只打本机架构）
LOCI_VERSION=1.1.0 LOCI_BUILD=412 script/release
```

脚本把 dmg 的路径打印到 stdout（其余进度都在 stderr），所以 `dmg="$(script/release)"` 可以直接拿到路径。

| 环境变量 | 作用 |
|---|---|
| `LOCI_SIGN_IDENTITY` | 用哪个 codesign 身份；默认取本机第一个 `Developer ID Application`，没有就用「Loci Signing」 |
| `LOCI_NOTARY_PROFILE` | `xcrun notarytool store-credentials` 存的钥匙串 profile |
| `APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_PASSWORD` | 或者直接给 Apple ID 的公证凭据 |
| `LOCI_VERSION`、`LOCI_BUILD` | 包里的 `CFBundleShortVersionString`、`CFBundleVersion`（默认 HEAD 之前最近的版本 tag 和提交数） |
| `LOCI_ARCHS` | 空格分隔的架构；默认是本机的 |

本机可以把公证凭据存一次，之后不再给密码：

```sh
xcrun notarytool store-credentials loci-notary
LOCI_NOTARY_PROFILE=loci-notary script/release
```

## secrets

| secret | 是什么 | 必须 |
|---|---|---|
| `MACOS_SIGNING_IDENTITY` | 签名身份的 `.p12`，base64 | tag 必须 |
| `MACOS_SIGNING_PASSWORD` | `.p12` 的密码 | tag 必须 |
| `LOCI_RELAY_URL`、`LOCI_RELAY_KEY` | 远程访问用的中继和注册密钥；没有就没有远程访问 | 应该有 |
| `MACOS_NOTARY_APPLE_ID`、`MACOS_NOTARY_TEAM_ID`、`MACOS_NOTARY_PASSWORD` | Apple ID、Team ID、App 专用密码 | 只在用 Developer ID 时 |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare 账号 ID，拼出 R2 的 S3 接口地址 | tag 必须 |
| `R2_ACCESS_KEY_ID`、`R2_SECRET_ACCESS_KEY` | R2 API 令牌（只对 `loci-releases` 读写）的 S3 凭据 | tag 必须 |

签名的两个沿用 Tauri 版：「Loci Signing」由 Tauri 版的 `scripts/setup-release.sh` 生成（`git show tauri:scripts/setup-release.sh`），本机钥匙串里也有一份。换成 Developer ID 时，从钥匙串访问把证书连同私钥导出成 `.p12`（`openssl pkcs12` 生成的要用 `-legacy`），`base64 -i id.p12 | gh secret set MACOS_SIGNING_IDENTITY`，再设密码和三个公证 secret。

## 冷启动

冷启动的预算是 0.5 秒内（[design.md](design.md) 的流畅度预算）。应用自己把「可以打字了」的耗时写进日志（`Sources/Loci/Launch.swift`，subsystem `com.loci.native.dev`，category `launch`），`script/measure-launch` 用 `open` 启动几次、把日志里的数字读出来，并在最后给最差的一次。

```sh
script/measure-launch                            # 量 debug 构建
script/measure-launch --app "output/Loci (Beta).app"  # 量已经打好的包
```

每次启动都从主对话起，量的是同一件事；脚本会暂时清掉应用记住的窗口位置，结束时放回去。release 构建的数字在 tag 构建的 run summary 和 `release` artifact 里。

## 还没做

- 正式版 Loci 渠道：β2。
- 公证的 App Store Connect API key 路径：现在只认 Apple ID 加 App 专用密码。
