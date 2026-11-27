# 版本与发布

从一次提交到一个发布出去的 Loci (Beta)：版本号、提交规则、CI、定版本、签名和发布流水线。应用叫 **Loci (Beta)**，bundle id 是 `com.loci.native.dev`，不随名字改，改了 macOS 会当成另一个应用，已给的权限都接不上。数据在 `~/Loci-Beta`。

## 产物

| 文件 | 是什么 |
|---|---|
| `output/Loci (Beta).app` | `script/bundle` 组装的应用包，包含 `script/resources/Loci.icns`；`script/run` 和 `script/release` 共用 |
| `output/Loci-Beta-<version>.dmg` | 第一次下载用：应用加一个 `/Applications` 链接，Apple silicon 与 Intel 通用 |
| `output/Loci-Beta-<version>.zip` | 应用内完整更新用：`ditto -c -k --keepParent` 打的应用包，保留签名，不用挂载 |
| `*.dmg.sha256`、`*.zip.sha256` | 上面两个文件的校验和 |
| `output/patches/Loci-Beta-<version>.files.json` | 清单：新版应用包里每个文件的 SHA-256 和是否可执行、每个符号链接的目标（`script/release-patches`，只在 tag 构建） |
| `output/patches/Loci-Beta-<version>.from-<旧版本>.patch` | 补丁：把 `<旧版本>` 的应用包变成这一版，最近五个版本各一份（同上） |
| `output/notes.json` | 最近十个版本的 CHANGELOG 段落（`script/release-notes`），写进 `latest.json` |

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

- **版本号**是三段数字。默认只加最后一段，新功能也一样；加中间一段或第一段只由用户决定，`script/cut-release` 不带 `--user-chose` 时拒绝。tag 是 `v` 加版本号，CHANGELOG 的段落标题是 `## <版本号> — <日期>`，`script/check` 会检查标题的写法。每个版本都是正式的 GitHub release；仓库是私有的，release 只作存档，用户从 R2 下载。
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

   1. 确认 tag 在 main 上，用 `script/changelog` 取出这一版的 CHANGELOG 段落作为发布说明，没有这一段就失败；`script/release-notes` 取出最近十个版本的段落。
   2. 检查 secrets：tag 构建必须签名，缺签名的 secret 就失败，不会把 ad hoc 签名的包发给别人。
   3. 把 `MACOS_SIGNING_IDENTITY` 里的 `.p12` 导入一个临时钥匙串：有 Developer ID 就用它；否则信任其中的「Loci Signing」并用它。
   4. `script/release`：通用构建、签名并 `codesign --verify --strict`、Developer ID 时公证、写 dmg、zip 和校验和。
   5. `brew install bsdiff`，`script/release-patches` 写清单，并从 `dl.umupa.fun` 取最近五个版本的 dmg，各生成一份补丁（见下面「补丁」）。这一步**不卡发布**：取不到、打不开或补丁不比 zip 小很多的版本跳过，整步失败也只是这一版没有补丁。
   6. `script/measure-launch`：记录 release 构建的冷启动，**只记录，不卡发布**。
   7. 把 dmg、zip、校验和、补丁、清单、发布说明留成 `release` artifact。

   Package 通过后，Publish 先确认上传 R2 的 secrets 都在，再取回 `release` artifact，用校验和核对 dmg 和 zip，写出 `latest.json`，建 GitHub release、附上 dmg、zip、校验和和 `latest.json`，最后按 zip、清单、补丁、dmg、`latest.json` 的顺序传到 R2。Package 失败就不发布。重跑只替换文件，不会重复建 release。

   推送时 CI 也会检查这个发版提交；它只改了 CHANGELOG，所以只跑文档检查。

`gh workflow run release` 是试 secrets 用的：构建和签名都和 tag 一样，但不发版，dmg 留成 workflow artifact。

发出去的版本有问题时不删 tag、不改已发布的 CHANGELOG 段落，修好后发下一个版本。

## 下载与更新源

仓库是私有的，GitHub release 的附件匿名下载不到，所以下载和更新只走 Cloudflare R2：`loci-releases` 桶，自定义域名 `dl.umupa.fun`。应用读 `https://dl.umupa.fun/loci/latest.json`（`Sources/LociMedia/Updates/ReleaseFeed.swift`）。R2 上除 `latest.json` 外都永久缓存；`latest.json` 缓存五分钟，并且最后上传，所以它指向的文件都已经在了。

### `latest.json`

```json
{"version": "1.9.0", "sha256": "<dmg>", "downloads": ["https://dl.umupa.fun/loci/Loci-Beta-1.9.0.dmg"],
 "archive": {"sha256": "…", "size": 66046324, "downloads": ["…/Loci-Beta-1.9.0.zip"]},
 "manifest": {"sha256": "…", "size": 82011, "downloads": ["…/Loci-Beta-1.9.0.files.json"]},
 "patches": [{"from": "1.8.8", "sha256": "…", "size": 15061390, "downloads": ["…/Loci-Beta-1.9.0.from-1.8.8.patch"]}],
 "notes": [{"version": "1.9.0", "changes": "- …"}, {"version": "1.8.8", "changes": "- …"}]}
```

| 字段 | 谁读 | 是什么 |
|---|---|---|
| `version`、`sha256`、`downloads` | 所有版本 | 新版本号和 dmg。1.8.8 及更早的应用只认这三个，所以它们一直指 dmg，含义不变 |
| `archive` | 1.8.8 之后的版本 | zip 的校验和、大小和地址；有它就不再挂载 dmg，没有（旧格式）就照旧用 dmg |
| `manifest`、`patches` | 1.8.8 之后的版本 | 清单和各个补丁；有 `from` 等于当前版本的补丁才走补丁，没有补丁时这两项都不写 |
| `notes` | 1.8.8 之后的版本 | 最近十个版本的 CHANGELOG 段落，检查更新窗口列出当前版本之后的那些 |

### 更新文件放在哪

每个副本的更新文件都在 `~/Library/Application Support/Loci/updates/<包标识>/` 下（`UpdateFiles`，包标识由 `UpdateEnvironment.system` 从 Bundle 读）：半截下载 `<校验和>.partial`、解压和打补丁用的临时文件夹 `scratch/`、暂存的新版 `<版本>/`、旧副本 `previous/`、没起来的新版 `failed/`、回滚记录 `rolled-back.json`。所以包标识不同的测试副本（比如 `fun.loci.bbtest.update`）和发布的 `com.loci.native.dev` 互不看见对方的暂存和记录。

1.8.8 及更早把这些直接放在 `updates/` 下。正常装完只剩空目录，但下载失败留下的半截 dmg（最多七十多 MB）和暂存了却没换上的应用包（两三百 MB）会留在那里，新版本不再看那个位置。所以发布的副本（包标识是 `com.loci.native.dev`）每次开始检查更新时删掉 `updates/` 下以版本号命名的文件夹和 `.partial` 文件；测试副本不删，免得删掉正在运行的发布版的暂存。

### 补丁

补丁是 `ditto -c -k` 打的 zip，里面是 `patch.json`、每个变了的文件一份 bsdiff（`diffs/<n>`）、每个新文件整份（`files/<路径>`）。`patch.json` 写 `from`、`to`、`changed`（路径和它的 bsdiff）、`added`、`removed`（先删）、`links`（新的或目标变了的符号链接）。格式由 `script/release-patches` 写、`Sources/LociStore/AppPatchFiles.swift` 读。

应用拿到补丁后：在 Application Support 里复制一份当前应用包（APFS 上是克隆，几乎不占地方），用系统自带的 `/usr/bin/bspatch` 逐个重建变了的文件，删、加、建链接、按清单设可执行位，然后按清单逐个核对：多一个、少一个、校验和或可执行位不对都不行，最后照旧 `codesign --verify --deep --strict` 并核对签名要求。任何一步不过就下 zip。1.8.6/1.8.7 → 1.8.8 的补丁约 14.5 MB，zip 66 MB。

签名一变，每个可执行文件都变，所以按文件整份替换省不下来；二进制差分后主程序约 12 MB，其余可执行文件只有几 KB。bsdiff 只装在发布机上，应用不带它。

### 换上后打不开

换上新版之前，应用把旧的应用包复制到 `updates/<包标识>/previous/`，旁边写上换上的版本。换上后起一个独立的 shell 盯着新版（`AppImage.watchStart`）：重新打开时它负责打开，退出时换上的等你下次打开，最多等十二小时。新版的窗口出来（主对话或启动问题页）时写 `previous/started`，守护进程看到就删掉旧副本；新版在写出标记之前退出（重新打开时三十秒内没起来也算），守护进程把它挪到 `updates/<包标识>/failed/`，把旧副本挪回原位并打开，再把版本记到 `updates/<包标识>/rolled-back.json`。新版起得慢、还在跑，就一直等，不会杀掉它。守护进程中途没了（比如注销），旧副本留着，新版下次启动成功时删。

回滚只换应用包，不动数据：新版已经改过数据格式时，换回的旧版能不能读，现在不保证。

### 位置

应用在只读卷上（直接从 dmg 运行）或在 macOS 的 App Translocation 位置运行时，不检查也不下载（`AppPlacement`），更新按钮让人先把 Loci 移到「应用程序」。

环境变量 `LOCI_UPDATE_FEED` 给测试副本换成本地的 `latest.json` 地址（`UpdateEnvironment.system`），签名照样核对。

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
