# 主题、壁纸与字体

## 结论

Settings → Appearance 新增 **Color theme**：22 个来自 [Omarchy](https://github.com/omacom/omarchy) `quattro` 分支的主题（17 深色、5 浅色）。一个主题包括：

- 调色盘，映射到 Loci 现有的颜色变量，并决定 Loci 是深色还是浅色；
- 该主题自带的壁纸，接入已有的 **Chat background**，沿用背景效果、显示范围和透明度设置；
- 代码块配色，用 Omarchy 自己的 palette→语法映射生成 Shiki 主题。

另外新增 **Fonts**（代码字体、界面字体），沿用 Omarchy 的字体方案。**Default** 仍是原来的 Hue / Saturation / Dark-mode lightness 体系，选回 Default 即回到之前的设置，没有任何改动。

## 之前的实现

- 外观是参数化的：深色 / 浅色 / 跟随系统；一个色相和饱和度同时决定背景和文字（`--theme-hue`、`--theme-saturation`），背景明度只有深色可调，浅色固定 97%；强调色是 6 个预设加自选。
- 聊天背景是一张用户图片（拷贝进 app data），配 6 种效果、显示范围（仅空会话 / 全部）和两档透明度；每个项目还可以有自己的背景。
- 字体没有设置，只有 `--font-sans` / `--font-mono` 两个系统字体栈。
- 代码高亮固定为 `github-light` / `github-dark`。
- 设置存在 localStorage 的 `loci.*` 键里，`index.html` 在首次绘制前读取其中一部分，避免启动闪烁。

调色滑块表达不了 Omarchy 的调色盘（背景和文字的色相不同，浅色背景的明度也不是 97%），所以主题需要自己的颜色通道。

## 设计

### 数据来源与导入

`scripts/import-omarchy-themes.mjs <Omarchy 检出>` 读取 `themes/` 和 `default/themed/`，生成：

- `src/features/settings/model/omarchyThemes.generated.ts`：22 份调色盘、壁纸清单、语法规则（含来源 commit）；
- `public/themes/<主题>/<壁纸>.webp` 及 `.thumb.webp`；
- `public/themes/LICENSE`：Omarchy 的 MIT 许可文本。

调色盘按 Omarchy 自己的 `bin/omarchy-theme-color` 补全缺失的色阶（例如 `white` 没有 `orange`，由 `yellow` 代替）。壁纸用 libvips 缩到能盖住 1600×900（不放大），WebP q66，72 张共约 6 MB；缩略图 320px。只有 “OMARCHY” 字样的占位图（`omarchy.webp`）不算壁纸，没有导入。

### 调色盘到 Loci 变量

通过现有的 HSL 通道写入，所以侧栏玻璃、macOS 原生窗口着色、背景效果这些现有逻辑不需要知道主题的存在。`--color-content` 新增了自己的色相和饱和度通道（`--content-hue`、`--content-saturation`），没有主题时它们回退到原来的共用色调。

| Omarchy | Loci |
| --- | --- |
| `background` | `--theme-hue` / `--theme-saturation` / `--background-lightness`（页面背景，同时是原生窗口的底色） |
| `foreground`（必要时见下） | `--content-hue` / `--content-saturation` / `--content-lightness`（所有文字、描边和选中态都由它派生） |
| `accent` | 强调色（`--user-accent-color`）；用户自己选的强调色优先 |
| `blue` | `--link-color`，Markdown 链接 |
| `magenta` | `--color-markdown-heading` |
| `yellow` / `cyan` | `--color-skill` / `--color-mention` |
| `green` / `red` | `--color-diff-add` / `--color-diff-del`；文字用的 `-fg` 是保证可读的版本 |
| 全部 | Shiki 主题，用 Omarchy 的 `vscode-theme.json.tpl` 里的 81 条 TextMate 规则 |

主题的 `mode` 决定 `theme-light` 类，所以原有的浅色样式（含 `dark:` 变体）照常生效。浅色主题下 Mode 行置灰并显示“Set by the … theme.”，色调滑块置灰。

### 可读性

Omarchy 的颜色是为终端配的，暗淡的黄色或灰色在终端里没问题，在这里要承载文字。规则如下，只在不达标时沿同一色相调整明度，并且调得尽量少：

| 对象 | 规则 |
| --- | --- |
| 正文（content 对 background） | ≥ 7:1 |
| 次级文字（content 以 45% 强度，界面里最常用的提示和描述） | 深色 ≥ 3:1，浅色 ≥ 2.5:1（Loci 自带深色是 4.0:1，浅色是 2.5:1） |
| 链接、标题、技能 / 提及标签、diff 文字、语法颜色 | ≥ 4.5:1（语法颜色对的是代码块底色，即页面向文字色混 6%） |
| 强调色 | ≥ 3:1 |

正文色的选择顺序是：调色盘的 `foreground`、`light_foreground`、`bright_foreground`，都不行才自己调。22 个主题里 14 个原样使用；Tokyo Night 和 Osaka Jade 用调色盘自己的更亮的文字色；Catppuccin Latte、Everforest、Gruvbox、Matte Black、Miasma、Rose Pine 沿同色相微调（Matte Black 和 Miasma 只差几个百分点）。`themes.test.ts` 对全部 22 个主题逐一断言以上规则。

没有覆盖的：界面里写死的状态色（`text-sky-*`、`text-amber-*`、`text-red-*` 等）不属于主题变量，沿用原有的深浅两套。Markdown 链接原来写死为 `text-sky-400`，在浅色背景上太淡，所以命名主题下改用 `--link-color`；Default 的外观保持不变。

### 壁纸

壁纸以 `theme:<主题>/<壁纸>` 的形式存进 `loci.chatBackgroundPath`（原来存的是本地文件路径），`chatBackgroundSrc` 把它解析成同源的 `/themes/...webp`。因此背景效果、显示范围、两档透明度、项目背景对话框的预览都不需要改动。

- 选主题时，壁纸只在聊天背景为空或本来就是主题壁纸时才跟着换；用户自己选的图片不会被覆盖。
- 选回 Default，主题壁纸随之撤掉；用户的图片保留。
- 在主题壁纸上点 Remove，会记下 `loci.themeWallpaperAuto = 0`，之后换主题不再自动带壁纸；再手动点一张主题壁纸或自选图片则恢复。
- 找不到的壁纸（比如以后目录里删了）按没有背景处理。

### 字体

Omarchy 的字体方案是一个全局的等宽字体：默认 JetBrainsMono Nerd Font，菜单里可装 Cascadia、Meslo、Fira Code、Victor、Bitstream Vera、Iosevka（名称取自 `bin/omarchy-menu`）。

- **Code font**：系统等宽（默认）、上面 7 种预设，或自己输入字体名（至多 4 个族名，只接受纯名称，不能带 `;`、括号、斜杠等）。
- **Interface font**：系统默认、**Same as code font**（Omarchy 的“到处都是等宽”）、预设或自己输入。
- 字体放在系统栈前面（`--font-mono-user`、`--font-sans-user`），清除后完全回到原样。选了界面字体会加 `has-ui-font`，macOS 上也生效。

代码字体有一道保护：必须实际渲染成等宽才会被使用。原因是 WebKitGTK 经 fontconfig 解析族名时，对没装的字体不会落到 CSS 里的下一个族，而是直接用 fontconfig 的替代字体；实机上 “FiraCode Nerd Font” 没装时被替成了 Liberation Sans（比例字体），代码块会变成比例字体。所以用 canvas 量一下窄字母和宽字母的宽度是否相等，不等就不应用，并在设置里提示 “Not installed, or not a monospace font”。名字里带 “Mono” 的字体没装时 fontconfig 会替成系统等宽字体，量出来仍是等宽，无法区分也无害。

### 持久化

| 键 | 内容 |
| --- | --- |
| `loci.themeId` | 主题 id；缺省为 Default，不认识的值回退为 Default |
| `loci.themeWallpaperAuto` | 选主题时是否带上它的壁纸，默认开 |
| `loci.chatBackgroundPath` | 原有；现在也可以是 `theme:<主题>/<壁纸>` |
| `loci.codeFont` / `loci.uiFont` | 字体族名列表；`loci.uiFont` 可以是 `@code`（跟随代码字体） |
| `loci.themeBoot` | JSON 数组 `[主题 id, 模式, 色相, 饱和度, 明度]`，给 `index.html` 在首次绘制前恢复背景；校验 id、模式、数值范围，坏值或不匹配时忽略 |

“Restore defaults” 一并重置主题、壁纸跟随、两个字体。

## 添加或更新主题

```sh
git clone --depth 1 --branch quattro --filter=blob:none --sparse https://github.com/omacom/omarchy ../omarchy
git -C ../omarchy sparse-checkout set themes default/themed
node scripts/import-omarchy-themes.mjs ../omarchy
npm test
```

需要 libvips（`vips`、`vipsheader`）。生成的文件整体提交，`NOTICE` 里的来源 commit 随之更新。

## 验证

2026-10-08 最终验证：Vitest **291 个文件、3414 项测试通过**；单独执行 `npx tsc --noEmit` 和 `npm run build` 均通过。构建仍提示已有 CSS `::highlight` 兼容性及大 chunk 警告。本次没有修改 Rust 代码，未重跑 Rust 检查。

自动检查覆盖：

- 22 份调色盘、72 张壁纸及缩略图完整性；正文、次级文字、语义色和代码语法色的对比度。
- 主题切换、深浅模式、自定义强调色、默认配色恢复；自选背景不被覆盖、删除壁纸后停止自动跟随。
- 字体名校验、持久化、等宽字体回退、自定义输入及恢复默认。
- 执行 `index.html` 的真实启动脚本，验证所有主题首次绘制前的背景与模式，以及损坏或过期缓存的回退。
- 挂载真实 `AgentMarkdown`，在内容不变的情况下依次切换深色、浅色及 Default，确认代码 token 颜色更新。

Linux 实机验证使用独立应用数据目录，在 Xvfb 中运行 Tauri / WebKitGTK：切换全部 22 个主题，查看设置页及包含链接、标题、TypeScript 和 diff 的笔记；检查字体设置、壁纸及恢复默认；保存 Rose Pine 主题与壁纸后退出，再启动检查持久化。最后一轮主题截图均已检查。启动脚本和自定义字体重置的收尾修复另有上述自动测试覆盖。

次级文字的 3:1 / 2.5:1 是产品基线，并不表示所有小字号文字都达到 WCAG AA。对比度测试基于不透明页面与代码底色，不覆盖任意自选图片、透明度或玻璃背后的内容。macOS 原生玻璃和 Windows 本轮未实机验收；字体只引用系统安装的字体，不下载或打包字体文件。
