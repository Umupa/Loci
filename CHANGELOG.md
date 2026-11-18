# Changelog

User-visible changes to the native app. The Tauri app's history is on `main`.

## Unreleased

- 导师对话：`$$…$$` 和 `\[…\]` 公式排成居中的块；连续工具调用折叠成一行按动作计数，展开后命令不带 shell 外壳，读取、修改、创建、删除文件都显示文件名，搜索显示查询词；悬停回复或代码块可以复制；往上翻时输入框上方出现「回到最新」；Shift+Return 换行，⌘Return 发送；`/new` 重新开始，留一条「新对话」分隔线，之前的消息都保留；窗口窄于 1000 时课文页的侧边栏自动让位给对话。
- 导师对话修正：长对话里接连提问后消息区不再变成一片空白；流式输出时文字不再变淡、重影，占用的 CPU 大幅下降；agent 起不来时用界面语言说明是没安装还是无法启动；资料页的陪读对话也能用 `/new` 重新开始。
- 资料库修正：在资料库或开始页，焦点在侧栏或列表时按 ⌘V 也能导入剪贴板里的链接，编辑菜单新增「粘贴链接」；从别的应用拖入网页链接（或含一个链接的文字）到资料库任意位置或开始页都能导入，拖入时显示琥珀色描边。
- 取回失败改说人话：视频不可用、连不上网站、yt-dlp 太旧、读不到浏览器登录信息等分别说明，并给对应按钮（不可用给「打开原网页」而不是「重试」）；列表行只放短说法，完整原因在详情里，yt-dlp 原文可展开查看。书架大卡片上也显示失败或进行中的状态和按钮。
- 取回的视频封面随标题一起出现，不用重启；Martin Fowler 等把正文插图也设为分享图的文章，插图不再丢失。
- 小窗口里视频页右栏自动收起（点按钮浮在视频上打开），视频不再画到侧栏上，窄时控制栏只留播放、时间、字幕和全屏。
- 浏览器「下载视频 · n」挑选框加「全选 / 全不选」；播放列表页不再把「全部播放」「随机播放」算成视频。
- 资料库界面：上面一排大封面放正在看的，下面是列表，每行右侧显示下载、识别进度或「下载组件」「下载模型」「更新 yt-dlp」「重试」等按钮；空资料库中央就是输入框。在资料库或开始页按 ⌘V 粘链接、或把链接拖进来，立刻建资料并打开。
- 视频与播客页：大播放器（播客是大封面），进度条上标出章节和重点，速度、字幕（原文、对照、译文、不显示）、全屏；右栏「文稿 · 对话 · 划线」，文稿跟着播放高亮滚动，手动滚动后出现「回到播放处」，点一句从那里播放，拖选几句可以划线或问导师；识别中显示进度，句子陆续出现。空格播放暂停，← → 跳五秒，< > 调速。
- 文章标题下一行显示作者、站点、日期和原文链接，正文用衬线并显示图片；论文用 PDF 阅读。资料的对话页顶部选一位导师陪读，中途可以换，每条回答标着是谁答的。
- 内置浏览器（侧边栏「浏览器」）：单个视频页是「下载视频」，频道和列表页是「下载视频 · n」可挑选，播客单集、论文、有正文的文章是「加入资料库」，已加过的是「在资料库中查看」；在里面登录过的网站，取回时带上登录状态。
- 打开的资料、课文等页面不再在窗口顶部多出一条带大返回按钮的栏：返回改为侧边栏旁的小箭头，⌘[ 也能返回。侧边栏的资料库下总列出视频、播客、文章，有论文时再加「论文」。
- 设置 › 媒体：yt-dlp、FFmpeg、QuickJS 的版本和来源，可更新、重新检测；七个 Whisper 模型的速度、准确、大小，可下载、删除、选默认；是否使用浏览器登录信息。
- 资料库取回：粘 YouTube、B 站、播客链接立即建资料，几秒内可在线播放（不能直接放画面的先放声音），后台下载 1080p 兼容 mp4 或播客 m4a；有平台字幕直接成文稿，没有就在本机用 Whisper 识别，句子陆续出现，智能断句每句一到两行；之后由 agent 写译文和章节重点。文章、论文链接与本地音视频导入也走同一套任务。缺组件、缺语音模型、需要登录时任务停在等待，满足后自己继续；失败时说明原因并给出更新 yt-dlp、选浏览器登录信息或重试；退出再开接着做。yt-dlp、FFmpeg、QuickJS 和七个 Whisper 模型可在设置里下载、更新、删除。

- 界面改版：窗口没有工具栏，侧边栏是悬浮的玻璃面板，依次是开始、课程、资料库、导师、设置；课程可以展开，看到每课读过、当前、未读、未写，点一门课直接打开它当前的课。
- 课文标题和小节标题改用衬线，去掉目录页和上一课 / 下一课；右栏顶部切换对话和划线，可以收起。
- 选中文字后弹出「划线 / 问导师」：划线立刻生效，可以顺手写一句想法；问导师在右栏对话里回答，有思考和工具步骤，答完这条问答自动存进那条划线。点划线或对话里的引文，正文定位并闪一下。界面里的「笔记」改叫「划线」。
- 输入框下方可以切换 agent、模型和思考程度（Claude Code、Codex、Pi），并能看到上下文用量。
- 导师一律以完全权限运行，不再弹权限卡，也没有权限设置。
- 导师页改版：头像与名字、agent 与模型、正在做什么、书架式课程封面，以及原样显示的 Memory 和 Soul，导师改了文件页面跟着变。
- 设置移进主窗口的侧边栏，⌘, 打开：通用（外观、界面语言、课文语言、数据文件夹）和 Agent（各家版本、默认 agent、各家默认模型）。
- 左右两栏都能拖动调宽，双击边缘恢复默认；右栏可以一直拖宽到只给正文留 320 点；左侧边栏可以收起（侧边栏右上角按钮或 ⌃⌘S）；「通用 → 阅读 → 正文宽度」可以选适中或全宽。
- 侧边栏换成设计稿的暖色磨砂底，选中行跟着变成琥珀色；设置页的按钮和栏宽对齐设计稿。
- 正文里选中的文字用中性的淡底，和划线分得开；松手后选区不再变灰，工具条放在选区上方，不挡后面的字；工具条图标换成笔尖和对话气泡。
- 导师和课程用内置图标代替首字母，新导师随机获得一个图标和一种暖色；旧导师的颜色显示为最接近的暖色。
- Agent 菜单和设置里显示各家官方图标（来自 LobeHub，MIT）。

- 课末「下一课」按钮能打开下一课了；正文里术语的别名也会标虚线、悬停看释义。
- 设置窗口新增「Agent」页：列出本机装了哪些 agent CLI、路径、版本、登录状态，可重新检测；可选新导师默认用的 agent 和模型。导师右键菜单和导师页工具栏可进入导师设置，改 agent、模型和权限（每次询问 / Full access）。
- 段落提问失败时关闭对应的 agent 会话，避免后台进程遗留。

- 评测的一手来源计分按仓库路径边界匹配，不再把相似仓库名算作一手来源。

- 同一笔记同时提出多个问题时，各条待答记录分别更新，完成一个回答不会移除另一个问题。

- 新增 Grok（ACP）驱动，支持流式回复、工具调用、权限询问、中断和会话恢复；其余 ACP 系 agent 只需提供启动参数。
- 新建的导师会立刻开始工作：先写目录，再写第一课；目录里未写的课可以请导师写。
- 和导师对话：回复流式出现，可以停止、回答权限询问；对话记录只追加，重开应用后都在。
- 对一段话提问：问题和定位符一起发给导师，回答流式出现，完成后存进这条笔记。
- 新增 LociEval：经命令层在 Pi 上建导师、等第一课、计时并按 0.11 的评分表打分。
- 停止对话统一在 30 秒内返回；Claude Code 拒绝未知控制请求后继续对话，ACP 自动批准优先只允许一次。

- 新增 Antigravity 原生会话驱动，复用本机 ACP 服务端，支持工具审批、停止和恢复对话。
- Cursor 的 ACP 驱动支持流式回复、工具调用、权限回答、中断和恢复会话。
- 增加 Hermes ACP 驱动，支持模型与权限设置、流式对话、工具审批、中断和会话恢复。
- OpenCode 驱动支持流式回复、工具调用、权限询问、中断和恢复会话。
- omp 接入共享的 Pi RPC 驱动，支持流式回复、工具调用、权限询问、中断和恢复会话。
- 新增 Claude Code 驱动，支持流式回复、工具调用、权限询问、中断和恢复会话。
- 原生版接入 Codex app-server，支持流式回复、工具调用、权限询问、停止与会话恢复。

- The native app opens to a start page: type a sentence to make a mentor, or drop a text file to add it to the library; browse mentors, lessons and items, with each lesson's sources and each item's citing lessons beside them. Warm-night look in light and dark, English and Chinese.
- Lessons and items open in a real reader: headings, lists, quotes, code blocks and tables, set in one column. It reopens where you stopped, keeps your place when the window is resized or the text is revised, and marks a lesson read once you reach its end.
- A mentor's page is a catalog tree that marks each lesson read, revised or not yet written, and shows what the mentor is doing while it works. Lessons the mentor revised highlight what changed since you last saw them; glossary terms are underlined where first used, with their definition on hover; at a lesson's end you can go on to the next one or ask the mentor to write it.
- Select a passage to highlight it, write a thought on it, or ask the lesson's mentor about it. Notes are kept in `notes/` files and survive restarts; the text keeps only the underline and a small mark, and the panel beside it lists the contents and every note in reading order, with answers streaming in. Notes whose passage is gone are listed as lost instead of pointing elsewhere.
- Talk with a mentor on its page: replies stream in, tool calls show what they ran and how it went, permission requests wait for your answer, and a running turn can be stopped.
- Mentor replies and answers render full Markdown with Textual; code in lessons is syntax-highlighted and formulas are typeset. Inputs, the floating next-lesson button and the panel header use macOS 26 glass.
