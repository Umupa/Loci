# 版本与发布

从一次提交到一个发布出去的 Loci Dev：版本号、提交规则、CI、定版本、签名公证和发布流水线。这一版只发 **Loci Dev** 渠道（`com.loci.native.dev`）；正式版 Loci 与自动更新在 β2（见 [roadmap.md](roadmap.md)）。

## 产物

| 文件 | 是什么 |
|---|---|
| `output/Loci Dev.app` | `script/bundle` 组装的应用包，`script/run` 和 `script/release` 共用 |
| `output/Loci-Dev-<version>.dmg` | 发布产物：应用加一个 `/Applications` 链接，Apple silicon 与 Intel 通用 |
| `output/Loci-Dev-<version>.dmg.sha256` | 上面那个文件的校验和 |

签名和公证走 Developer ID：`codesign --options runtime --timestamp` 签应用，`notarytool` 公证，`stapler` 把票据钉在文件上。**两次往返**：先公证应用（装进 zip 提交），再公证 dmg。钉过票据的文件离线也能通过 Gatekeeper 的检查。

没有证书时（本机没有 Developer ID，或 PR 里跑的 CI）不失败：用 ad-hoc 签名，跳过公证，dmg 照样打出来，macOS 第一次打开时会要求确认。这是脚本里的一条分支，不是另一个脚本；[ci.yml](../.github/workflows/ci.yml) 的 `Dmg` 作业专门跑这条分支。

## 版本号

| 阶段 | 版本号 | 渠道 |
|---|---|---|
| 现在 | `1.0.0-alpha.N` | Loci Dev，GitHub 上的 pre-release |
| 功能齐了、只修问题 | `1.0.0-beta.N`，然后 `1.0.0-rc.N` | Loci Dev |
| 正式版 | `1.0.0`，之后按 semver | Loci（β2 之后才有） |

- tag 是 `v` 加版本号，CHANGELOG 的段落标题是 `## <版本号> — <日期>`。`script/check` 会检查标题的写法。
- 应用包里的 `CFBundleShortVersionString` 取自 tag，`CFBundleVersion` 是流水线的运行次数，只增不减。本机构建是 `1.0.0-alpha` 和 `1`。

## 从一次改动到一个版本

```
提交（feat/fix 带 CHANGELOG 一行） → 推到 main → CI → script/cut-release → 推 tag → Release 流水线
```

1. **提交。** 提交信息用 Conventional Commits。`feat` 和 `fix` 是用户看得到的，同一个提交里要在 CHANGELOG 的 Unreleased 下加一行或改一行；用户看不到的用 `refactor`、`test`、`build`、`ci`、`chore`、`docs`。`script/check` 会检查还没推送的提交，CI 会检查这次推送带来的提交（`script/check-commits`）。
2. **推到 main。** CI 跑三个作业：

   | 作业 | 做什么 |
   |---|---|
   | Commits | 检查这次推送或 PR 的提交信息 |
   | Check | `script/check`，留下日志和快照 |
   | Dmg | 不带证书跑一遍 `script/release`，打包坏了在合并前就能看到 |

3. **定版本。** 在 `docs/roadmap.md` 里把这一版挪进「已完成」，「发布」一列写上版本号，提交并推送。然后在 main 上：

   ```sh
   script/cut-release 1.0.0-alpha.1
   ```

   它检查：版本号的写法；在 main 上、工作区干净、和 `origin/main` 一致；tag 还没有；Unreleased 下有内容；roadmap 写了这个版本。然后把 Unreleased 改成 `## 1.0.0-alpha.1 — <今天>`，上面留一个空的 Unreleased，跑 `script/check`，提交 `chore: release 1.0.0-alpha.1`，打带注释的 tag。它不推送。

4. **发布。** `git push origin main v1.0.0-alpha.1`。推上去的 tag 会触发 [release.yml](../.github/workflows/release.yml)：

   1. 确认 tag 在 main 上，用 `script/changelog` 取出这一版的 CHANGELOG 段落作为发布说明；没有这一段就失败。
   2. `script/check`。
   3. 检查 secrets：tag 构建必须签名并公证，缺一个 secret 就失败，不会把 ad-hoc 签名的包发给别人。
   4. 把 `MACOS_SIGNING_IDENTITY` 里的 `.p12` 导入一个临时钥匙串，取出其中的 Developer ID Application 身份。
   5. `script/release`：通用构建、签名、公证、写 dmg 和校验和。
   6. `script/measure-launch`：记录 release 构建的冷启动，**只记录，不卡发布**。
   7. 建 GitHub release，附上 dmg 和校验和；带 `-` 的版本是 pre-release。重跑只替换文件，不会重复建 release。

`gh workflow run release` 是试 secrets 用的：构建、签名、公证都和 tag 一样，但不发版，dmg 留成 workflow artifact。

发出去的版本有问题时不删 tag、不改已发布的 CHANGELOG 段落，修好后发下一个版本。

## 在本机

```sh
script/release                                   # 有 Developer ID 和公证凭据就签名并公证
LOCI_ARCHS="arm64 x86_64" script/release         # 通用包（默认只打本机架构）
LOCI_VERSION=1.0.0-alpha.3 LOCI_BUILD=42 script/release
```

脚本把 dmg 的路径打印到 stdout（其余进度都在 stderr），所以 `dmg="$(script/release)"` 可以直接拿到路径。

| 环境变量 | 作用 |
|---|---|
| `LOCI_SIGN_IDENTITY` | 用哪个 codesign 身份；默认取本机第一个 `Developer ID Application` |
| `LOCI_NOTARY_PROFILE` | `xcrun notarytool store-credentials` 存的钥匙串 profile |
| `APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_PASSWORD` | 或者直接给 Apple ID 的公证凭据 |
| `LOCI_VERSION`、`LOCI_BUILD` | 包里的 `CFBundleShortVersionString`、`CFBundleVersion`（默认 `1.0.0-alpha` 和 `1`） |
| `LOCI_ARCHS` | 空格分隔的架构；默认是本机的 |

本机可以把公证凭据存一次，之后不再给密码：

```sh
xcrun notarytool store-credentials loci-notary
LOCI_NOTARY_PROFILE=loci-notary script/release
```

## secrets 怎么准备

一次性的，在有证书的 Mac 上：

1. 从 Apple Developer 导出 **Developer ID Application** 证书，连同私钥和证书链，存成 `.p12`（用钥匙串访问导出；`openssl pkcs12` 生成的要用 `-legacy`，不然 `security import` 读不了）。
2. `base64 -i DeveloperID.p12 | pbcopy`，然后 `gh secret set MACOS_SIGNING_IDENTITY`。
3. `.p12` 的密码：`gh secret set MACOS_SIGNING_PASSWORD`。
4. 公证凭据是 Apple ID、Team ID 和 App 专用密码（在 appleid.apple.com 生成）：
   `gh secret set MACOS_NOTARY_APPLE_ID`、`gh secret set MACOS_NOTARY_TEAM_ID`、`gh secret set MACOS_NOTARY_PASSWORD`。

`MACOS_SIGNING_IDENTITY` 和 `MACOS_SIGNING_PASSWORD` 沿用 Tauri 版的名字；公证的三个是这个版本新加的。

## 冷启动

冷启动的预算是 0.5 秒内（[design.md](design.md) 的流畅度预算）。应用自己把「可以打字了」的耗时写进日志（`Sources/Loci/Launch.swift`，subsystem `com.loci.native.dev`，category `launch`），`script/measure-launch` 用 `open` 启动几次、把日志里的数字读出来，并在最后给最差的一次。

```sh
script/measure-launch                            # 量 debug 构建
script/measure-launch --app "output/Loci Dev.app"  # 量已经打好的包
```

每次启动都从主对话起，量的是同一件事；脚本会暂时清掉应用记住的窗口位置，结束时放回去。release 构建的数字在 tag 构建的 run summary 和 `release` artifact 里。

## 还没做

- 自动更新（Sparkle）和正式版 Loci 渠道：β2。
- 应用图标：现在 `script/bundle` 不带 `.icns`，Finder 和 Dock 里是系统默认的样子。
- 公证的 App Store Connect API key 路径：现在只认 Apple ID 加 App 专用密码。
