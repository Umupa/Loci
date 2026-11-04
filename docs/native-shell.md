# 用 Native Shell 替换 Tauri（研究，暂缓）

> 2026-11-04 调研。结论：**方向可行，现在不推进**，等 nsh 成熟后按文末的条件重新评估。调研对象是 [longbridge/nsh](https://github.com/longbridge/nsh) v0.4.0（commit `9cb48de`）。

## 动机

- Tauri 的问题多，总有奇怪的 bug。
- 想要原生的 iPhone、iPad 端。
- 想要更好的性能。

## nsh 是什么

Native Shell 是长桥（gpui-component 的作者团队）做的 Rust 跨平台 UI 框架。

- **原生视图渲染**：iOS 用 UIKit，macOS 用 AppKit，Windows 用 Win32 + Direct2D，Linux 用 GTK 4，Web 用 HTML，另有一个 GPUI 后端。文本、输入法、选区都用平台自己的。没有 WebView。
- **两种写法**：纯 Rust（类型化的构建方法和 Tailwind 同名的样式方法），或 TSX。TSX 编译成字节码跑在 QuickJS 里，用 signal 做响应式，组件只运行一次，类似 SolidJS。**没有 React，也没有 DOM。**
- **现成的组件**：`TextView`（Markdown 流式渲染、公式、跨块选区、可替换代码块渲染）、`RichEditor`（ProseMirror 的 Rust 移植，扩展层仿 Tiptap）、`WebView`、`Canvas`、`DiffView`、`Editor`、虚拟列表、对话框和 sheet。
- **其他**：TSX 热更新、`nsh` CLI 一键打包、签名的 TSX 包可在运行时下发并在沙箱中运行。
- **最低系统**：iOS 15、macOS 14、Windows 10 1809、GTK 4.14。

## 成熟度（2026-11-04）

| 维度 | 现状 |
|---|---|
| 时间 | 2026-10-14 公开，三周内从 v0.1 发到 v0.4，API 变化快，文档和发行版之间有过不一致 |
| 规模 | 约 66 万行 Rust、约 800 个 commit、300+ 个已合并的 PR、文档很全（架构、坑、性能） |
| issue | 64 个打开，只关闭过 32 个；没看到公开的生产案例 |
| 和 Loci 直接相关的未决问题 | iOS 能否上 TestFlight / App Store 还没有答复（#757）；没有文件和文件夹选择器（#162）；输入法未上屏内容在各平台表现不一致（#272）；macOS 不支持窗口半透明（vibrancy）；iOS 15/16 启动失败；内置根证书缺少 ISRG Root YE |
| 缺的组件 | PDF、Mermaid、树视图 |

工程质量高，但作为整个产品的底座还在早期预览阶段。

## 和 Loci 的契合度

Loci（v0.8.10）的规模：前端约 10.5 万行 TS/TSX（不含测试），测试约 6.9 万行，Rust 约 4.2 万行，191 个 Tauri 命令。

| Loci 现在 | 换成 nsh |
|---|---|
| React UI（sessions、settings、agents、files、learning 等，约 7 万行） | 必须重写：没有 React，也没有 DOM |
| `src/integrations/harness`（约 2.9 万行），CLI 协议驱动在 webview 里 | 应下沉到 Rust，各个客户端共用 |
| Rust 后端 | 大部分复用，Tauri 命令层改成 nsh 的 Rust 模块 |
| Streamdown + KaTeX + Shiki | `TextView` 加自定义的代码块渲染 |
| Milkdown 笔记编辑 | `RichEditor` |
| pdf.js 阅读器、⌥ 框选 | 没有现成的组件：Apple 平台用 PDFKit 原生视图，其他平台退回 `WebView` |
| Mermaid、X 的 Feeds | 嵌一个 `WebView` |
| 划线高亮、文本锚点、学习地图、阅读位置 | 要在原生选区上重做，是最大的未知数 |
| 托盘、菜单栏、通知、自动更新 | nsh 的桌面模块覆盖了一部分，自动更新要自己做 |

## 收益和代价

| 期待 | 实际 |
|---|---|
| 性能 | Loci 的慢在 agent 回复和 relay 每次调用约 0.6s，不在 WebView 渲染；体感提升有限 |
| 少些奇怪的 bug | WebView 的滚动、选区、渲染怪癖会消失。但 #43（后台线程碰 AppKit 闪退）、未激活窗口点击只激活这类是原生平台行为，换了也一样，nsh 更贴近原生只会更直接地暴露它们。另外要承担一个新框架的空白，修起来要改 nsh 或等上游 |
| 原生 iPhone、iPad | 真正的收益。但 iOS 不能起子进程，不能跑 agent CLI，移动端只能是远程客户端（见 [remote-access.md](remote-access.md)），面积小 |
| 代价 | 约 7 万行 UI 重写，加上 PDF、Mermaid 等的替代方案；迁移期间功能开发基本停摆 |

## 决定

现在不迁移。理由：框架太新，API 每周在变，和 Loci 相关的几个基础能力（App Store 发布、文件选择、输入法）还没解决；而 Loci 当前的瓶颈不在 UI 渲染。

暂缓期间仍然值得做、且与框架无关的事：

1. **会话驱动下沉到 Rust**（`roadmap.md` 里的“无头主机”）。去掉“主机窗口是唯一驱动者”的限制，远程更稳，以后换任何 UI 框架都只需重写界面。
2. **记录 Tauri 问题**：每次遇到时注明是 WebView 问题还是原生平台问题，作为以后决策的依据。

## 重新评估的条件

满足大部分后再启动：

- nsh 发布 1.0，或明确承诺 API 稳定。
- iOS 应用确认能上 TestFlight 和 App Store。
- 文件和文件夹选择器、输入法一致性问题已解决。
- 有公开的生产应用（长桥自己的也算）。
- 中文长文、跨段落选区、自定义高亮在 macOS 和 iPad 上表现稳定。

## 重启时的方案

### 先做 spike（1～2 天，严格限时）

在 macOS 和 iPad 上用 nsh 做三个页面，结论决定是否继续：

- 流式对话：Markdown、代码块、公式逐段到达。
- 阅读器：霞鹜文楷正文、跨段落选中、划线高亮、文本锚点、阅读位置。
- 一节长课程：滚动、跳转、中文输入法。

### 分阶段迁移

| 阶段 | 内容 | 关口 |
|---|---|---|
| 一 | 会话驱动下沉到 Rust 的 `loci-core`（若暂缓期间还没做） | Tauri 前端成为薄客户端，测试全绿 |
| 二 | nsh 写 iPad / iPhone 远程客户端：配对、导师列表、对话、阅读、高亮、笔记 | 真机验收、TestFlight |
| 三 | nsh 桌面版和 Tauri 版并行，先给 Loci Dev 用，按对齐清单补齐 PDF、RichEditor、设置、通知、菜单栏、托盘、更新 | 功能对齐 |
| 四 | 正式版切到 nsh，删除 Tauri | — |

### 待定的选择

- **UI 用 TSX 还是 Rust。** 倾向核心 Rust、UI 用 TSX：有热更新，写法接近现在的 React，适合 AI 生成。
- **iPad 和 iPhone 的先后**，以及是否保留 Windows、Linux（nsh 的 Linux 需要 GTK 4.14+）。
- **PDF、Mermaid、Feeds 是否接受先用 `WebView` 兜底。**

## 在此之前的 iPad 路线

如果在 nsh 成熟前就想用上 iPad，成本最低的是 `roadmap.md` 里原来的方案：用 Tauri 2 的 iOS 构建打包同一份前端，只保留远程客户端模式。不妨碍以后切到 nsh。
