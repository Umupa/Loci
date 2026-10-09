<div align="center">

<img src="src-tauri/icons/128x128@2x.png" width="112" alt="Loci logo" />

# Loci

**一个桌面应用，容纳你已经在用的所有 agent CLI。**

项目就是普通文件夹，会话通过本机已安装的 agent CLI 运行。<br />
笔记、画布和常驻 agent 就放在对话旁边。

[![CI](https://github.com/Umupa/Loci/actions/workflows/ci.yml/badge.svg)](https://github.com/Umupa/Loci/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) · 简体中文

</div>

---

Loci 是一个本地优先的 agent CLI 桌面外壳，使用 Tauri 2、Rust、React 19 和 Tailwind 4 构建。它自己不运行模型，也没有服务端：它启动你已安装的 CLI，说它们的协议，并给它们一个共同的工作场所，包括标签与分栏、项目侧栏、笔记、Excalidraw 画布和提醒。数据都留在你的机器上，主要存放在一个本地 SQLite 数据库里。

> [!NOTE]
> Loci 还是早期软件（v0.1）。界面、数据模型和内置 MCP 工具都可能变化。各系统上试过什么、没试过什么，见[平台支持](#平台支持)。

## 功能

- **十个 agent CLI，一个界面。** Claude Code、Codex、Cursor、Grok Build、OpenCode、Pi、omp、fx、Hermes Agent 和 Antigravity。每个 CLI 继续使用它自己的登录和设置。每个会话可以单独选择模型和权限模式（Supervised、Auto-accept edits、Auto、Full access）。
- **为长时间运行的 agent 准备的工作区。** 标签和拖拽分栏、agent 提问、计划与任务显示、带文件夹的会话列表、⌘K 跨会话搜索、图片和文档附件、手动提醒及桌面通知。
- **笔记和画布是一等对象。** 可以在输入框里用 `@` 引用的 Markdown 笔记，以及 Excalidraw 画布。回复里可以用 `loci://note/<id>`、`loci://canvas/<id>` 链接它们，点击后在当前窗口打开。
- **会画图的 agent。** Claude Code 和 Codex 会话自带内置的 `loci_excalidraw` MCP：未经修改的官方 Excalidraw MCP 服务，写入 Loci 自己的画布存储。Antigravity 和 Pi 会话通过 Loci 自带的 CLI 使用同一组工具，不需要安装或配置。你的手动修改会被保留，面板实时更新。见 [docs/canvas-mcp.md](docs/canvas-mcp.md)。
- **`/operator`。** 让 agent 操作 Loci 本身：读取模型、启动和发送会话、调整分栏、整理文件夹、读写笔记和画布。它走一条带认证的本机回环通道，只在你启用它的那一个 turn 内有效。
- **常驻 agent。** 不属于任何项目、长期存在的 agent：一段你会反复回来的对话、常驻指令、记忆、按计划自己运行的习惯，以及它在你的项目里启动并跟进的会话。它用可点选的选项提问，用卡片回复。见 [Agents](#agents)。
- **主题、壁纸与字体。** Settings → Appearance 提供 22 个 Omarchy 主题、配套代码高亮和 72 张壁纸，也支持自选背景与系统已安装的字体。沿用背景效果、显示范围和透明度，自定义强调色优先。见 [docs/themes.md](docs/themes.md)。
- **中文设置页。** 设置页默认跟随系统语言，也可在“Settings → 通用 → 设置页语言”切换简体中文或英文，立即生效。工作区保持英文。
- **本地优先。** 本地 SQLite 数据库，不需要账号，没有统计，没有自动更新。见[数据与隐私](#数据与隐私)。

## 安装

### 下载

第一个版本打上标签后，macOS（Apple Silicon）和 Linux（x64）的安装包会附在 [Releases](https://github.com/Umupa/Loci/releases) 页面。目前还没有发布，所以暂时请从源码构建。发布版没有经过 macOS 公证，第一次打开时 macOS 会要求你确认。

### 从源码构建

需要：

| 工具 | 版本 | 说明 |
| --- | --- | --- |
| Node.js | 20.19+ 或 22.12+（推荐 24，`.nvmrc` 已固定） | 下限由 Vite 7 决定 |
| Rust | stable，带 `rustfmt` 和 `clippy` | `rustup component add rustfmt clippy` |
| 平台依赖 | 见 [Tauri 前置条件](https://v2.tauri.app/start/prerequisites/) | macOS 需要 Xcode 命令行工具；Linux 需要 WebKitGTK 4.1 等；Windows 需要 MSVC 和 WebView2 |

```sh
git clone https://github.com/Umupa/Loci.git
cd Loci
npm ci
npm run tauri dev      # 带热更新运行
npm run tauri build    # 为当前平台构建安装包
```

macOS 上可以用 `./script/build_and_run.sh --verify` 构建并启动 Release 包（它会先停掉从本仓库构建的、正在运行的实例；`--help` 列出调试和日志选项）。

### 开始第一个会话之前

- 至少安装并登录一个受支持的 agent CLI。Loci 会在 `PATH` 和常见安装位置里找每个 CLI。**Settings → Agent CLIs** 可以指定具体的可执行文件、默认模型，以及隐藏你不用的 CLI。
- 想用内置 MCP 服务（`loci_excalidraw`），需要安装 Node.js 20.11+（或 Bun）。没有它会话照常启动，设置页和画布面板会说明缺什么。

## 支持的 agent CLI

| CLI | 说明 |
| --- | --- |
| Claude Code、Codex | 完整功能：账号管理与额度查询、内置 MCP 服务 |
| Antigravity、Pi | 对话、模型和权限选择，并通过 Loci 的 CLI 使用画布工具 |
| Cursor、Grok Build、OpenCode、omp、fx、Hermes Agent | 通过 CLI 自己的协议聊天，并选择模型和权限。除此之外能显示多少（提问、计划、工具详情）取决于 CLI 上报什么 |

需要知道的细节：

- 账号管理和额度查询目前只支持 Claude Code 和 Codex。
- Antigravity 使用独立的 ACP server。遇到认证提示时，请点击应用内的 **Sign in to Antigravity**；交互式 `agy` 的登录不能替代它。
- Antigravity 和 Pi 通过运行命令来调用画布工具，所以它们是在对话里被告知这些工具的，而不是通过工具列表。Pi 做任何事之前都不询问，画图也一样；Plan 模式下 Pi 没有 shell，用不了这些工具。
- fx 暂不支持附件。
- 未安装的 CLI 仍会显示在设置里，并附安装提示。

## 斜杠命令

命令只在输入框开头生效。

| 命令 | 作用 |
| --- | --- |
| `/operator` | 让当前会话能访问 Loci 的会话、文件夹、笔记和画布 |
| `/btw` | 就当前 turn 问一个只读的旁问 |
| `/draft` | 保存这条消息，但不启动 agent |
| `/compact` | 总结较早的对话内容，腾出上下文空间 |
| `/mcp` | 为这条消息查找合适的 MCP 服务 |
| `/add-to-folder` | 把这个会话放进已有或新建的侧栏文件夹 |


## Agents

点击侧栏 *Agents* 旁边的 **+**。**New agent** 创建一个空白 agent，它会先问你它的主要工作是什么，然后给自己起名，并根据你的回答写下自己的常驻指令。也可以从内置模板开始（Tutor、Lead、Watch、Reviewer、Scout、Chief）：工作已经定好，它的工作方法直接写进 soul 里可以查看，agent 只问这份工作需要知道的事。模板的措辞可以在 **Settings → Your agents → Agent templates** 里修改。这些之后都可以在 **Details** 里修改。

- **它一直在。** 一个 agent 有一段不会结束的对话、一份 soul（常驻指令）和一份边学边记的记忆。两者都是 Loci 数据目录里的文件，不在你的仓库里，换模型也不会丢。
- **它在你的项目里干活。** 在 Details 里把项目交给它。它可以在其中启动会话、跟进，并在完成后回来汇报。
- **习惯。** Loci 开着的时候按计划自己做的事，只有值得说时才给你发消息。
- **卡片。** 回复不只是文字：可点选的提问、在对话旁打开的文档、可以勾选的清单、可折叠的思维导图、Mermaid 图、指向画布的链接。卡片自己不保存任何状态；你对它做的操作会作为下一条消息发给 agent。
- **文档库。** agent 写的文档保存在 Details → Library，按主题分组。同一篇再写一次就是修订，任何一篇都可以存为笔记。
- **比如做导师。** 选 Tutor 模板。它会访谈你，把你的水平和进度记在记忆里，把路线图和讲解写成文档，你说换主题就换。

agent 做什么由提示词决定，所以效果取决于它背后的模型。

## 数据与隐私

- **数据在哪。** 会话、笔记、画布、布局和提醒都在应用数据目录 `com.loci.desktop` 下的 `loci.db`（SQLite）里：macOS 是 `~/Library/Application Support/com.loci.desktop`，Linux 是 `~/.local/share/com.loci.desktop`，Windows 是 `%APPDATA%\com.loci.desktop`。粘贴的图片和隔离的 provider 账号放在它旁边。你的项目文件仍在你自己的文件夹里。
- **Loci 会联网做什么。** Loci 没有统计、崩溃上报和更新检查。除了 agent CLI 自己和各自的 provider 通信之外，Loci 会读取对话中公开链接的标题和图标（回环和内网地址会被拒绝）；对 Claude Code，它会用 Claude Code 已保存在本机的登录令牌，向 Anthropic 的用量接口查询你的用量。该令牌不会保存到别处。
- **agent 能做什么。** agent 以你的用户权限运行。权限模式只决定 Loci 在 CLI 行动之前是否询问你，所以选它要像在 CLI 里一样谨慎。**Full access** 会让命令、编辑和受支持的 MCP 确认都不再询问。

报告安全漏洞请见 [SECURITY.md](SECURITY.md)。

## 平台支持

| 平台 | 状态 |
| --- | --- |
| macOS（Apple Silicon） | 主要的开发和手动测试平台 |
| Linux | 能构建、通过测试套件并运行；开发中在 Arch Linux ARM 上检查过，使用得比 macOS 少 |
| Windows | 有平台代码和安装包配置，但维护者没有构建或试过 |

CI 在 Linux 和 macOS 上构建并测试 Rust 与 Web 代码，见 [.github/workflows/ci.yml](.github/workflows/ci.yml)。

## 开发

```sh
npm ci
npm run tauri dev     # 带热更新运行
npm run check         # CI 运行的全部检查：Vitest、tsc、cargo fmt、clippy 和 cargo test
npm run build         # 类型检查并构建 Web 包
```

| 命令 | 作用 |
| --- | --- |
| `npm test` / `npm run test:watch` | Vitest，单次或监听模式 |
| `npm run check:web` | Vitest 和 `tsc --noEmit` |
| `npm run check:rust` | `cargo fmt --check`、`cargo clippy -D warnings`、`cargo test` |
| `npm run set-version -- 0.1.1` | 一次更新所有带版本号的文件 |
| `npm run tauri:stable` | 文件变化时不会重载的开发实例（无热更新，不重编 Rust） |

目录结构：

```text
src/                      React 前端
  app/                    窗口外壳与工作区组合
  features/               sessions、agents、notes、canvas、projects、search、settings、skills 等
  integrations/harness/   agent CLI 协议核心和十个 provider
  platform/tauri/         对 Tauri 命令的薄封装
  shared/                 UI 组件、hooks 和工具函数
src-tauri/                Rust 后端：进程、SQLite 存储、应用控制、MCP 资源
  resources/              内置 MCP 服务（excalidraw-mcp）
docs/                     指南和设计记录
scripts/                  版本号更新、第三方文件引入和真实协议探测
```

各部分如何配合，见 [docs/architecture.md](docs/architecture.md)。欢迎贡献，请先读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 文档

[文档索引](docs/README.md)列出了全部指南。画布 MCP 的设计记录以中文撰写。

## 许可证

Loci 以 [MIT 许可证](LICENSE)发布。它派生自一个更早的 MIT 许可项目，并内置同为 MIT 许可的官方 Excalidraw MCP 服务；来源、版本和商标声明见 [NOTICE](NOTICE)。Loci 与它能驱动的各 agent CLI 的厂商没有任何关联。
