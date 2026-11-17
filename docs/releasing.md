# 发布

α1-1 的剩余部分：Loci Dev 怎样签名、公证、打成 dmg，以及 tag 推上去之后流水线做什么。这一版只发 **Loci Dev** 渠道（`com.loci.native.dev`）；正式版 Loci 与自动更新在 β2（见 [design.md](design.md) 的分发一段）。

## 产物

| 文件 | 是什么 |
|---|---|
| `output/Loci Dev.app` | `script/bundle` 组装的应用包，`script/run` 和 `script/release` 共用 |
| `output/Loci-Dev-<version>.dmg` | 发布产物：应用加一个 `/Applications` 链接，Apple silicon 与 Intel 通用 |
| `output/Loci-Dev-<version>.dmg.sha256` | 上面那个文件的校验和 |

签名和公证走 Developer ID：`codesign --options runtime --timestamp` 签应用，`notarytool` 公证，`stapler` 把票据钉在文件上。**两次往返**：先公证应用（装进 zip 提交），再公证 dmg。钉过票据的文件离线也能通过 Gatekeeper 的检查。

没有证书时（本机没有 Developer ID，或 PR 里跑的 CI）不失败：用 ad-hoc 签名，跳过公证，dmg 照样打出来，macOS 第一次打开时会要求确认。这是脚本里的一条分支，不是另一个脚本。PR 的 [ci.yml](../.github/workflows/ci.yml) 里有一个 `Dmg` 作业专门跑这条分支，产物留作 artifact，所以打包坏了在合并前就能看到。

## 打一个 tag

```sh
git tag v1.0.0-alpha.3
git push origin v1.0.0-alpha.3
```

tag 推上去之后，[release.yml](../.github/workflows/release.yml) 依次做：

1. 检查 secrets：tag 构建必须签名并公证，缺一个 secret 就失败，不会把 ad-hoc 签名的包发给别人。
2. 把 `MACOS_SIGNING_IDENTITY` 里的 `.p12` 导入一个临时钥匙串，取出其中的 Developer ID Application 身份。
3. `script/release`：通用构建、签名、公证、写 dmg 和校验和。
4. `script/measure-launch --app "output/Loci Dev.app"`：记录 release 构建的冷启动到 run 的 summary，**只记录，不卡发布**。
5. dmg 和校验和上传到这个 tag 的 release；带 `-` 的 tag 是 pre-release。重跑只替换文件，不会重复建 release。

`gh workflow run release` 是试 secrets 用的：构建、签名、公证都和 tag 一样，但不发版，dmg 留成 workflow artifact。

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

α1-12 的预算：冷启动 0.5 秒内（`docs/roadmap.md` 的验收）。应用自己把「可以打字了」的耗时写进日志（`Sources/Loci/Launch.swift`，subsystem `com.loci.native.dev`，category `launch`），`script/measure-launch` 用 `open` 启动几次、把日志里的数字读出来，并在最后给最差的一次。

```sh
script/measure-launch                            # 量 debug 构建
script/measure-launch --app "output/Loci Dev.app"  # 量已经打好的包
```

每次启动都从开始页起，量的是同一件事；脚本会暂时清掉应用记住的窗口位置，结束时放回去。release 构建的数字在 tag 构建的 run summary 和 `release` artifact 里。

## 还没做

- 自动更新（Sparkle）和正式版 Loci 渠道：β2。
- 应用图标：现在 `script/bundle` 不带 `.icns`，Finder 和 Dock 里是系统默认的样子。
- 公证的 App Store Connect API key 路径：现在只认 Apple ID 加 App 专用密码。
