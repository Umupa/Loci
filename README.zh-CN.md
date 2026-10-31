<div align="center">

<img src="src-tauri/icons/128x128@2x.png" width="112" alt="Loci logo" />

# Loci

**给工程师的 AI 原生学习工作台。**

**一位常驻导师，一个主题。它带来一手材料——文档、规范、论文和源码——陪你一起读。**

[![CI](https://github.com/Umupa/Loci/actions/workflows/ci.yml/badge.svg)](https://github.com/Umupa/Loci/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) · 简体中文

</div>

---

Loci 是一个本地优先的桌面学习工作台，用 agent 学习技术主题。每位导师都是一个长期存在的 agent，对应一个主题：一份 Soul（长期指令）、一份记忆，以及对话旁的资料库，存放课程、文档、笔记和画布。导师采集一手材料，陪你一起读。它通过你已经登录的 agent CLI 运行——Claude Code 或 Codex——不需要另配模型 API key，也没有自己的服务端。数据留在你的机器上，主要是一个本地 SQLite 数据库。

> [!NOTE]
> Loci 还是早期软件（v0.1）。界面、数据模型和内置 MCP 工具都可能变化。各系统上试过什么、没试过什么，见[平台支持](#平台支持)。

## 学习循环

1. **定下目标。** 告诉导师你想学什么。它一次只问一个问题，直到目标和你的基础都清楚。
2. **采集一手材料。** 它查找官方文档、规范、论文和源码，放在课程能指向的地方。
3. **编排课程。** 它把材料排成章节和课时，每一课指向要读的段落、页面或文件。
4. **阅读与提问。** 你在 Loci 里读原文。可以把文档、PDF、网页或对话中的选段附在问题上，回答可以引用这段原文。
5. **沉淀理解。** 在对话旁写笔记、画画布。导师把进度记进记忆，下次从你停下的地方继续。

## 导师

点击导师栏上的 **+**（或按 ⌘T）新建。每位导师负责一个主题。可以从 **Mentor**、**Lens** 或空白 agent 开始。**Mentor** 模板一次一个问题地和你对齐目标，采集一手材料，编排成课程，并在阅读过程中检验你的理解。**Lens** 接收一个仓库，克隆它，写一页速览，并把值得读的文件编成代码导览课。

每位导师都有：

- **Soul。** 长期指令：它怎么教、对你有什么期待、要避开什么。可以在导师设置的 **Soul** 页编辑，也可以让导师在对话里修改。
- **记忆。** 导师通过内置的 `app` CLI 维护的事实和主题笔记。它们是 Loci 数据目录里的文件，换模型也不会丢。
- **资料库。** 对话旁的课程、文档、笔记和画布。课程是你读的内容，文档是课程指向的材料，笔记由你编辑，画布是 Excalidraw 图。导师通过 `app documents.write` 和 `app courses.write` 保存文档与课程。
- **一段持续的对话。** 每位导师只有一段对话。旁边打开的课、文档或笔记会作为上下文一起传给导师，所以“这里”“这段”指的就是你正在读的内容。
- **卡片。** 回复可以带可点选的提问、可打开的文档、清单、思维导图、课程、代码 diff、Mermaid 图，或指向画布的链接。

导师通过 CLI 动手：它可以在你的机器上克隆仓库、运行代码、准备实验，受你选择的权限模式约束。

导师做什么由提示词决定，所以效果取决于它背后的模型。

每位导师有自己的工作台：左边是当前课程的目录和资料库，中间是阅读区，右边是对话。打开任何东西（课文、资料、笔记、画布、文件，或导师发起的会话）都只替换阅读区，不开新标签页或新窗口。切回一位导师时，会回到它上次显示的课文。⌘K 查找导师或资料库里的内容，⌘1–9 切换导师，⌘W 关闭阅读区，⌘B 和 ⇧⌘B 折叠资料库和对话。

## 阅读与来源

问题可以附带选段。在文件里选中代码或文字，选择 **Ask agent** 或 **Add to chat**；在 PDF 或对话中选中段落；或者添加网页来源，填写 URL 并贴上原文（Loci 不会为这个功能抓取网页）。选段会随消息显示，并以文本形式交给 CLI。

PDF 支持高亮。选中文字后可以选择 **Ask agent** 提问，或选择 **Highlight** 保存高亮。点击高亮可以写笔记、提问、打开关联讨论或删除。阅读器工具栏的 **PDF annotations** 列出全部高亮。高亮、笔记和讨论保存在本地 `loci.db`，不会改写 PDF。页面需要已有文本层；目前不做 OCR。详见 [docs/learning.md](docs/learning.md)。

## 安装

### 下载

macOS（Apple 芯片与 Intel）和 Linux（x64）的安装包在 [Releases](https://github.com/Umupa/Loci/releases) 页面，安装后的 Loci 会从那里检查并安装更新（**设置 → 通用 → 关于**）。发布版没有经过 macOS 公证，第一次打开时 macOS 会要求你确认。每个版本的改动见 [CHANGELOG.md](CHANGELOG.md)。

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
npm run app:dev        # 带热更新运行 Loci Dev
npm run tauri build    # 为当前平台构建安装包
```

从源码运行的是 **Loci Dev**：一个独立的应用，数据目录也独立，可以和安装的 Loci 同时运行，不会碰到你的笔记和 agent。`npm run install:local`（macOS）把当前代码构建成正式的 Loci 并安装到 `/Applications`。详见 [docs/releasing.md](docs/releasing.md)。

macOS 上可以用 `./script/build_and_run.sh --verify` 构建并启动 Loci Dev 的 Release 包（它会先停掉从本仓库构建的、正在运行的实例；`--help` 列出调试和日志选项）。

### 开始第一个会话之前

- 安装并登录 Claude Code 或 Codex。这两个是受支持的 CLI。Loci 会在 `PATH` 和常见安装位置里找它们。**Settings → Agent CLIs** 可以指定具体的可执行文件、默认模型，以及隐藏你不用的 CLI。
- 想用内置 MCP 服务（`loci_excalidraw`），需要安装 Node.js 20.11+（或 Bun）。没有它会话照常启动，设置页和画布面板会说明缺什么。

## 支持的 agent CLI

Loci 启动你机器上已安装的 CLI，说它的协议，自己不运行模型。Claude Code 和 Codex 是受支持的两个。其余八个适配保留，属于实验性。

| CLI | 状态 |
| --- | --- |
| Claude Code、Codex | 受支持：对话、工具与权限，以及内置画布 MCP 服务 |
| Antigravity、Pi、Cursor、Grok Build、OpenCode、omp、fx、Hermes Agent | 实验性：可以对话并选择模型和权限。提问、计划、工具详情等还能显示什么，取决于 CLI 上报什么 |

每个 CLI 继续使用自己的登录和设置。每个会话可以选择模型和权限模式：Supervised、Auto-accept edits、Auto 或 Full access。

需要知道的细节：

- Antigravity 使用独立的 ACP server。遇到认证提示时，请点击应用内的 **Sign in to Antigravity**；交互式 `agy` 的登录不能替代它。
- Antigravity 和 Pi 通过运行命令来调用画布工具，所以它们是在对话里被告知这些工具的，而不是通过工具列表。Pi 做任何事之前都不询问，画图也一样；Plan 模式下 Pi 没有 shell，用不了这些工具。
- fx 暂不支持附件。
- 未安装的 CLI 仍会显示在设置里，并附安装提示。

## 斜杠命令

命令只在输入框开头生效。

| 命令 | 作用 |
| --- | --- |
| `/btw` | 就当前 turn 问一个只读的旁问 |
| `/draft` | 保存这条消息，但不启动 agent |
| `/compact` | 总结较早的对话内容，腾出上下文空间 |
| `/mcp` | 为这条消息查找合适的 MCP 服务 |

## 外观与语言

**Settings → Appearance** 提供 22 个 Omarchy 主题、配套代码高亮和 72 张壁纸，也支持系统已安装的字体和自定义强调色。**Settings → 通用 → 设置页语言** 可以跟随系统语言，或选择简体中文、英文，立即生效。工作区保持英文。见 [docs/themes.md](docs/themes.md)。

## 数据与隐私

- **数据在哪。** 会话、笔记、画布、来源引用和 PDF 批注都在应用数据目录 `com.loci.desktop` 下的 `loci.db`（SQLite）里：macOS 是 `~/Library/Application Support/com.loci.desktop`，Linux 是 `~/.local/share/com.loci.desktop`，Windows 是 `%APPDATA%\com.loci.desktop`。粘贴的图片放在它旁边。你的项目文件仍在你自己的文件夹里，批注不会改写原 PDF。
- **Loci 会联网做什么。** Loci 没有统计，也没有崩溃上报。安装版会在启动后不久检查 GitHub Releases 上的更新，之后每六小时一次，安装前会征求你的同意；从源码构建的版本不会自己更新。除了 agent CLI 自己和各自的 provider 通信之外，Loci 会读取对话中公开链接的标题和图标（回环和内网地址会被拒绝）。
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
npm run app:dev       # 带热更新运行 Loci Dev
npm run check         # CI 运行的全部检查：Vitest、tsc、cargo fmt、clippy 和 cargo test
npm run build         # 类型检查并构建 Web 包
```

| 命令 | 作用 |
| --- | --- |
| `npm test` / `npm run test:watch` | Vitest，单次或监听模式 |
| `npm run check:web` | Vitest 和 `tsc --noEmit` |
| `npm run check:rust` | `cargo fmt --check`、`cargo clippy -D warnings`、`cargo test` |
| `npm run set-version -- 0.1.1` | 一次更新所有带版本号的文件 |
| `npm run tauri:stable` | 文件变化时不会重载的 Loci Dev（无热更新，不重编 Rust） |
| `npm run install:local` | 把当前代码构建成安装版 Loci 并放进 `/Applications`（macOS） |
| `npm run release -- 0.2.0` | 从 main 发布一个版本（维护者，见 [docs/releasing.md](docs/releasing.md)） |

目录结构：

```text
src/                      React 前端
  app/                    窗口外壳与工作区组合
  features/               mentor（导师工作台）、sessions、agents、learning、notes、canvas、settings、skills 等
  integrations/harness/   agent CLI 协议核心和十个 CLI 适配器
  platform/tauri/         对 Tauri 命令的薄封装
  shared/                 UI 组件、hooks 和工具函数
src-tauri/                Rust 后端：进程、SQLite 存储、应用控制、MCP 资源
  resources/              内置 MCP 服务（excalidraw-mcp）
docs/                     指南和设计记录
scripts/                  版本号更新、第三方文件引入和真实协议探测
```

各部分如何配合，见 [docs/architecture.md](docs/architecture.md)。欢迎贡献，请先读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 文档

[文档索引](docs/README.md)列出了全部指南。[docs/roadmap.md](docs/roadmap.md) 说明定位和后续阶段。画布 MCP 的设计记录以中文撰写。

## 许可证

Loci 以 [MIT 许可证](LICENSE)发布。它派生自一个更早的 MIT 许可项目，并内置同为 MIT 许可的官方 Excalidraw MCP 服务；来源、版本和商标声明见 [NOTICE](NOTICE)。Loci 与它能运行的各 agent CLI 的厂商相互独立。
