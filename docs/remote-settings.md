# 设置与本地存储的远程化（v0.7 调研）

> 简体中文。2026-11-02，基线 `b2130dc`。只做调研和设计，不含代码改动。上层方案见 [远程访问](remote-access.md)，会话流的接缝见 [会话主控](remote-session.md)。行号以基线为准。

## 结论先行

- `src/` 里 33 个非测试文件直接调用 `localStorage`；另有 `src/features/settings/model/builtinMcp.ts` 经 `src/features/settings/model/storageFlags.ts` 间接读写。共 69 个不同的键（`loci.noteTarget.<scope>`、`loci:path-folded:<agentId>` 这类按作用域拼接的键各算一个）。
- 21 个键属于主机共享；其中 `loci:agent-handed`、`loci:agent-rotations`、`loci.projectLocations` 是主机内部簿记，远程端不需要读。45 个键每台设备各自；3 个待定。
- 导师名单在 `storage_status` 就绪时以 Rust 的导师注册表为权威，localStorage 只是让 `listAgents()` 保持同步的镜像（`src/features/agents/model/mentorStore.ts:5-16`）。远程端直接调现有的 `mentors_load`（`mentorStore.ts:117`）就能拿到名单，不需要为它新建键值通道。
- 推荐做法：主机共享的键继续由主机窗口做唯一写入者；客户端保留一份同键的 localStorage 镜像。连接时取一次 `settings.snapshot`，之后收 `settings.changed`，远程修改走 `settings.set` 意图。所有同步读取方一行不改。
- 会话行为相关的值（`followUpBehavior`、默认模型、权限）在 `session.submit` 等意图里显式带上（见 [会话主控](remote-session.md) 2.2），所以设置通道还没就绪时 P1 仍能跑。

## 1. 清单

统计方式：`rg localStorage src`，排除 `*.test.ts`、`*.test.tsx`。同一个键在多个文件出现时合并为一行。数值型外观键都经 `readNumber`/`writeNumber`（`src/features/settings/model/appearance.ts:142`、`:153`），字体键都经 `readString`/`writeString`（`src/features/settings/model/fonts.ts:82`、`:90`）；表里写调用它们的加载/保存函数。

`src/features/settings/model/workspaceReset.ts` 只做批量清理（`src/platform/tauri/workspaceReset.ts:81` 调用 `clearWorkspaceStorage`），本身不存值，不单列。

### 1.1 主机共享（21）

这些值决定主机做什么：哪个导师和会话存在、用哪个 CLI、哪个模型、什么权限、读哪些文件、写什么内容。远程端看到不同的值，就会驱动主机做出不同的事，或看到不同的世界。

| 键 | 读写位置 | 存了什么 | 远程端用法 |
| --- | --- | --- | --- |
| `loci:agent-roster` | 读 `src/features/agents/model/agent.ts:173`、`agent.ts:382`；写 `agent.ts:180`；镜像读 `src/features/agents/model/mentorStore.ts:53`、写 `:95` | `Agent[]`：id、`sessionId`、名字、角色、头像、颜色、学习语言、workdir、projects、folder、`defaults`（provider/model/effort/mode/modelSettings）、侧栏标记 | 用 `mentors_load`（`mentorStore.ts:117`）读取；增删改走意图；客户端不写 |
| `loci:agent-default-access` | 读 `src/features/agents/model/agentAccess.ts:29`；写 `:40` | 新导师对话的默认权限模式：`supervised`、`auto-accept-edits`、`auto`、`full-access` | 下发 + 可改 |
| `loci:agent-handed` | 键 `src/features/agents/model/agentFiles.ts:226`；读 `:230`；写 `:300`、`:319` | 每个会话已经收到过的 Soul/记忆版本（hash）和 provider 会话 id | 仅主机 |
| `loci:agent-rotations` | 键 `src/features/agents/model/agentRotation.ts:219`；读 `:223`；写 `:239`、`:253` | 每个会话的轮换简报和轮换状态 | 仅主机 |
| `loci:agent-previews` | 键 `src/features/agents/model/agentPreview.ts:10`；读 `:59`、`:100`；写 `:85` | 每个导师最后一句话和它的时间，导师栏未打开会话时显示 | 随名单下发，只读 |
| `loci.learningLanguage` | 键 `src/features/agents/model/learningLanguage.ts:16`；读 `:25`；写 `:34-35` | 导师写作用的语言：`auto`、`zh-CN`、`en`，会拼进每一轮 prompt | 下发 + 可改 |
| `loci.defaultModels` | 键 `src/features/sessions/model/models.ts:222`；读 `:750`；写 `:771` | 每个 provider 的默认模型 | 下发 + 可改 |
| `loci.lastModel` | 键 `src/features/sessions/model/models.ts:220`；读 `:824`；写 `:847` | 上一次用的 provider + model，新会话的起点 | 下发 + 可改 |
| `loci.lastModelSettings` | 键 `src/features/sessions/model/models.ts:221`；读 `:572`；写 `:589` | 上一次每个模型的参数（effort 等） | 下发 + 可改 |
| `loci.hiddenPickerProviders` | 键 `src/features/sessions/model/models.ts:219`；读 `:677`；写 `:698` | 模型选择器里隐藏的 provider；也影响新会话能选谁 | 下发 + 可改 |
| `loci.projectProviderSettings.v1` | 键 `src/features/sessions/model/projectProviders.ts:11`；读 `:146`；写 `:211` | 每个项目覆盖的默认 provider/model、模型参数和隐藏的 provider | 下发 + 可改 |
| `loci.providerAccounts.v1` | 键 `src/features/providers/model/providerAccounts.ts:4`；读 `:54`、`:134` | 每个 provider 的账号标签和 id（默认账号 + 额外配置） | 下发；当前只有读 |
| `loci.providerAccountSelections.v1` | 键 `src/features/providers/model/providerAccounts.ts:5`；读 `:97`、`:134` | 每个项目、每个 provider 选中的账号 id | 下发；当前只有读 |
| `loci.providerBinaryPaths.v1` | 键 `src/features/providers/model/providerBinaryPaths.ts:6`；读 `:12`；写 `:65` | 主机上每个 agent CLI 的可执行文件路径 | 下发 + 可改 |
| `loci.followUpBehavior` | 键 `src/features/settings/model/settings.ts:415`；读 `:422`；写 `:433` | 忙时新消息是 steer 还是排队 | 下发 + 可改 |
| `loci.claudeHooks` | 键 `src/features/settings/model/settings.ts:521`；读 `:524`；写 `:527` | 是否给 Claude CLI 装 Loci 的 hooks；`src/integrations/harness/providers/claude/claude.ts:1790` 读它 | 下发 + 可改 |
| `loci.builtinExcalidrawMcpEnabled` | 键 `src/features/settings/model/builtinMcp.ts:4`；读 `:10`；写 `:14`；底层 `src/features/settings/model/storageFlags.ts:3`、`:13` | 内置 Excalidraw MCP 开关；决定主机 CLI 拿不拿画布工具 | 下发 + 可改 |
| `loci.disabledSkillPaths` | 键 `src/features/skills/model/skills.ts:28`；读 `:35`；写 `:48` | 主机上被禁用的 skill 路径 | 下发 + 可改 |
| `loci.recentProjects` | 键 `src/features/projects/model/recents.ts:3`；读 `:35`；写 `:58` | 最近打开的项目路径和 `openedAt`；项目栏的项目集合来自这里 | 下发 + 可改 |
| `loci.archivedProjects` | 键 `src/features/projects/model/recents.ts:6`；读 `:173`；写 `:207` | 已归档的项目路径和时间 | 下发 + 可改 |
| `loci.projectLocations` | 键 `src/features/projects/model/projectLocation.ts:12`；读 `:25`；写 `:54` | 项目路径到目录文件系统 id 的缓存，用于找回被重命名的项目 | 仅主机 |

### 1.2 每台设备各自（45）

这些值只改变本机怎么画、怎么响、怎么排布，或者只是本机的操作记忆。远程端保留自己的一份；主机的那份继续给主机用。

#### 导航与阅读

| 键 | 读写位置 | 存了什么 |
| --- | --- | --- |
| `loci:active-mentor.v1` | 键 `src/app/hooks/useActiveMentor.ts:7`；读 `:11`；写 `:18`、删 `:19` | 本窗口当前打开哪个导师；重启后恢复 |
| `loci:agent-overviews.v1` | 键 `src/app/hooks/useMentorView.ts:31`；读 `:37`；写 `:68`；另见 `src/features/agents/model/mentorStore.ts:64`、`:280`、`:290` | 每个导师的库/对话面板开合、栏宽、上次课程、页面和阅读位置。同时镜像到主机 SQLite 的 `mentor_state`（`mentorStore.ts:273`），那份也是主机自己的视图快照 |
| `loci:path-folded:<agentId>` | 键 `src/features/mentor/ui/LibraryCourses.tsx:41`；读 `:43`；写 `:46` | 课程路径树的折叠状态 |
| `loci.translationView` | 键 `src/features/agents/ui/SourceTranslation.tsx:18`；读 `:23`；写 `:31` | 资料显示译文、原文还是对照 |
| `loci.noteTarget.<scope>` | 键 `src/features/notes/noteTarget.ts:10`；读 `:14`；写 `:23`、`:24` | 上次“加入笔记”的去向（新建或某条笔记），按导师作用域 |
| `loci.readingWide` | 键 `src/shared/lib/readingWidth.ts:9`；读 `:13`；写 `:30` | 阅读区用宽版还是 68ch 版心 |
| `loci.files.showHidden` | 键 `src/features/files/ui/FileTree.tsx:76`；读 `:1457`；写 `:1465` | 文件树是否显示隐藏文件 |

#### 外观

19 个键都在 `src/features/settings/model/appearance.ts`。`colorScheme`、`themeId`、`themeBoot` 还会被 `index.html` 的首屏脚本读取（`index.html:35`、`:45`、`:44`），那是本机启动画面，保持本地即可。

| 键 | 读写位置 | 存了什么 |
| --- | --- | --- |
| `loci.accentColor` | 键 `src/features/settings/model/appearance.ts:19`；读 `:179`；写 `:188-189` | 用户强调色 |
| `loci.themeHue` | 键 `src/features/settings/model/appearance.ts:20`；`loadThemeHue` `:211`；`saveThemeHue` `:221` | 主题色相 |
| `loci.themeSaturation` | 键 `src/features/settings/model/appearance.ts:21`；`loadThemeSaturation` `:228`；`saveThemeSaturation` `:238` | 主题饱和度 |
| `loci.themeDarkLightness` | 键 `src/features/settings/model/appearance.ts:22`；`loadThemeDarkLightness` `:245`；`saveThemeDarkLightness` `:255` | 暗色背景亮度 |
| `loci.sidebarOpacity` | 键 `src/features/settings/model/appearance.ts:23`；`loadSidebarOpacity` `:633`；`saveSidebarOpacity` `:641` | 侧栏不透明度 |
| `loci.sidebarBlur` | 键 `src/features/settings/model/appearance.ts:24`；`loadSidebarBlur` `:655`；`saveSidebarBlur` `:665` | 侧栏模糊半径 |
| `loci.bodyGlass` | 键 `src/features/settings/model/appearance.ts:25`；读 `:679`；写 `:683` | 正文玻璃效果 |
| `loci.colorScheme` | 键 `src/features/settings/model/appearance.ts:26`；读 `:318`；写 `:327` | 深色、浅色或跟随系统 |
| `loci.transcriptLayout` | 键 `src/features/settings/model/appearance.ts:27`；读 `:950`；写 `:960` | 对话区布局：完整或只聊天 |
| `loci.transcriptAnchor` | 键 `src/features/settings/model/appearance.ts:28`；读 `:973`；写 `:977` | 新内容是否贴底 |
| `loci.chatBackgroundPath` | 键 `src/features/settings/model/appearance.ts:29`；读 `:693`；写 `:704-705` | 对话背景图路径 |
| `loci.chatBackgroundOpacity` | 键 `src/features/settings/model/appearance.ts:30`；读 `:860`（`loadChatBackgroundOpacity` `:836`）；写 `:848`（`saveChatBackgroundOpacity` `:840`） | 背景图基准不透明度，旧键，作为下面两个的兜底 |
| `loci.chatBackgroundEmptyOpacity` | 键 `src/features/settings/model/appearance.ts:31`；读 `:886`；写 `:890` | 空对话时的背景不透明度 |
| `loci.chatBackgroundSessionOpacity` | 键 `src/features/settings/model/appearance.ts:33`；读 `:901`；写 `:905` | 有对话时的背景不透明度 |
| `loci.chatBackgroundScope` | 键 `src/features/settings/model/appearance.ts:34`；读 `:921`；写 `:930` | 背景图用在空对话还是所有对话 |
| `loci.newThreadBackgroundEffect` | 键 `src/features/settings/model/appearance.ts:35`；读 `:787`；写 `:800` | 新对话的背景动效 |
| `loci.themeId` | 键 `src/features/settings/model/appearance.ts:36`；读 `:485`；写 `:493-494` | 选中的命名主题 |
| `loci.themeBoot` | 键 `src/features/settings/model/appearance.ts:37`；写 `:509`、删 `:505`；读 `index.html:44` | 首屏用的主题快照（背景 HSL） |
| `loci.themeWallpaperAuto` | 键 `src/features/settings/model/appearance.ts:38`；读 `:526`；写 `:530` | 选主题时是否自动换壁纸 |

#### 字体与缩放

| 键 | 读写位置 | 存了什么 |
| --- | --- | --- |
| `loci.codeFont` | 键 `src/features/settings/model/fonts.ts:1`；读 `:100`；写 `:104` | 代码字体族 |
| `loci.uiFont` | 键 `src/features/settings/model/fonts.ts:2`；读 `:108`；写 `:112` | 界面字体族；可以是“跟随代码字体” |
| `loci.readingFont` | 键 `src/features/settings/model/fonts.ts:3`；读 `:116`；写 `:120` | 阅读字体：无衬线、衬线或跟随界面 |
| `loci.uiScale` | 键 `src/features/settings/model/uiScale.ts:3`；读 `:33`；写 `:46` | 界面缩放，作用在本机 webview 的 zoom |

#### 设置页与其他本机开关

| 键 | 读写位置 | 存了什么 |
| --- | --- | --- |
| `loci.settingsSection` | 键 `src/features/settings/model/settings.ts:5`；读 `:400`；写 `:409` | 设置页上次停在哪一节 |
| `loci.composerEffortVisible` | 键 `src/features/settings/model/settings.ts:416`；读 `:450` | 旧版的 effort 控件开关，只在缺少 `loci.modelControls` 时读一次做迁移；当前没有写入方 |
| `loci.modelControls` | 键 `src/features/settings/model/settings.ts:417`；读 `:445`；写 `:462` | 模型控件放在菜单里还是选择器旁边 |
| `loci.composerRunner` | 键 `src/features/settings/model/settings.ts:479`；读 `:483`；写 `:486` | Composer 里的吉祥物动画开关，纯视觉 |
| `loci.closeToTray` | 键 `src/features/settings/model/settings.ts:510`；读 `:516`；写 `:519` | Windows 上关闭窗口时是否留在托盘 |
| `loci.keybindingOverrides` | 键 `src/features/settings/model/settings.ts:559`；读 `:688`；写 `:714`、删 `:717` | 本机快捷键覆盖；键盘布局因设备而异 |
| `loci.language` | 键 `src/shared/i18n/locale.ts:6`；读 `:23`；写 `:38` | 界面语言：`en`、`zh-CN` 或跟随系统。它只管界面文案，导师写作用的语言是另一个键 `loci.learningLanguage` |

#### 会话与项目栏

| 键 | 读写位置 | 存了什么 |
| --- | --- | --- |
| `loci.modelPickerTab` | 键 `src/features/sessions/model/models.ts:218`；读 `:636`；写 `:648` | 模型选择器上次停在哪一个 tab |
| `loci.pinnedSessionsCollapsed` | 键 `src/features/sessions/model/pinnedSessions.ts:3`；读 `:14`、`:35`、`:55`；写 `:43`、`:62` | 每个项目的置顶会话区是否折叠 |
| `loci.projectRailOrder` | 键 `src/features/projects/model/recents.ts:4`；读 `:239`（`loadProjectRailOrder` `:267`）；写 `:261`（`saveProjectRailOrder` `:271`） | 项目栏的手动排序。项目集合本身来自 `loci.recentProjects`，这个键只决定本机怎么排 |

#### 通知与声音

| 键 | 读写位置 | 存了什么 |
| --- | --- | --- |
| `loci.notifications` | 键 `src/features/notifications/model/notifications.ts:10`；读 `:25`；写 `:35` | 本机是否启用系统通知；启用时要向本机系统申请权限 |
| `loci.notificationProjects.v2` | 键 `src/features/notifications/model/notificationProjects.ts:12`；读 `:64`；写 `:103` | 通知用的项目目录（id、名字、路径），由本机见过的项目累积 |
| `loci.projectNotifications.v1` | 键 `src/features/notifications/model/notificationPreferences.ts:23`；读 `:49`；写 `:131` | 每个项目的通知分类开关、静音截止时间和恢复时间 |
| `loci.sounds` | 键 `src/features/settings/model/sounds.ts:7`；读 `:30`；写 `:41` | 本机提示音开关 |
| `loci.soundsEnabledAt` | 键 `src/features/settings/model/sounds.ts:8`；读 `:76`；写 `:42` | 提示音重新启用的时间；早于它的事件不再响 |

### 1.3 待定（3）

这三个是用户偏好，放在主机还是放在设备上都说得通。它们的共同点是：不影响主机执行什么，但用户可能期望换台设备后还看到同样的选择。

| 键 | 读写位置 | 存了什么 | 倾向与理由 |
| --- | --- | --- | --- |
| `loci.favoriteModels` | 键 `src/features/sessions/model/models.ts:217`；读 `:612`；写 `:624` | 模型选择器里标星的模型 id | 倾向每台设备各自。它只是选择器的快捷方式，真正的默认由 `loci.defaultModels` 和 `loci.lastModel` 决定。如果用户把“收藏”当成跨设备的个人偏好，再移到主机共享 |
| `loci.recentModels` | 键 `src/features/sessions/model/models.ts:223`；读 `:855`；写 `:897` | 最近用过的 6 个 provider + model | 倾向每台设备各自。这是选择器的最近记录；默认模型已经由 `loci.defaultModels` 和 `loci.lastModel` 共享 |
| `loci.projectRailPinned` | 键 `src/features/projects/model/recents.ts:5`；读 `:239`（`loadPinnedProjects` `:275`）；写 `:261`（`savePinnedProjects` `:279`） | 项目栏里钉住的项目路径 | 倾向每台设备各自。钉选是栏位组织，和排序、折叠同类。若产品上希望“钉住的课题到哪都钉住”，把它移到主机共享，改动只在白名单加一行 |

### 1.4 只出现在重置白名单里的历史键

`src/features/settings/model/workspaceReset.ts:9-16` 的 SETTINGS 白名单里还有 `loci.notesEnabled`、`loci.agentsEnabled`、`loci.liveAgentsEnabled`、`loci.tabAnimationsEnabled`、`loci.tabLimit`、`loci.collapsedProjectRailMode`、`loci.diffPalette`、`loci.showExcludedFiles`。当前代码没有读写它们；保留在名单里只是为了让工作区重置不误删旧版本留下的设置。远程化不需要处理。

## 2. 分类依据

- **主机共享**：值会改变主机的行为或主机拥有的数据。典型是导师名单、导师默认权限、默认模型、provider 账号和 CLI 路径、项目集合、被禁用的 skill。两台设备看到不同的值，就会对同一份主机数据做出不同的事。
- **每台设备各自**：值只影响本机怎么显示、怎么响、怎么排布，或者只是本机的操作记忆。主题、字体、缩放、栏宽、折叠状态、上次打开的面板、快捷键、通知和声音都属于这一类。远程端保留自己的 localStorage，主机那份不动。
- **待定**：用户偏好，跨设备一致有道理，但又不是主机执行所必需。第 1.3 节逐条写了倾向。

两个容易混淆的键：`loci.language` 是界面文案语言，放本机；`loci.learningLanguage` 是导师写作用的语言，会拼进 prompt，放主机。`loci.modelPickerTab` 是选择器的 tab，放本机；`loci.defaultModels` 和 `loci.lastModel` 是模型选择本身，放主机。

## 3. 主机共享这一类的远程化方案

### 3.1 约束

1. **读取是同步的。** 这些值在 render 和 `useSyncExternalStore` 的快照里直接读：`agentsSnapshot`（`src/features/agents/model/agent.ts:382`）、`agentPreviewsSnapshot`（`src/features/agents/model/agentPreview.ts:100`）、`loadDefaultModels`（`src/features/sessions/model/models.ts:750` 在 `src/features/settings/ui/SettingsView.tsx:1183` 初始化 state）、`loadFollowUpBehavior`（`src/features/settings/model/settings.ts:422` 在 `src/app/hooks/useSessionSubmission.ts:202` 调用）、`loadCanvasMcpEnabled`（`src/features/settings/model/builtinMcp.ts:10` 在 `useSessionSubmission.ts:197` 调用）、`loadNewAgentAccess`（`src/features/agents/model/agentAccess.ts:29` 在 `src/features/agents/model/agentWorkspace.ts:125` 调用）。把这些调用点改成 async 会波及整棵组件树。
2. **名单已经有权威。** Rust 的导师注册表写 `mentor.json` 并返回名册（`src/features/agents/model/mentorStore.ts:117`、`:165`），窗口里的 localStorage 只是同步副本（`mentorStore.ts:5-16`）。名单不需要新的键值存储。
3. **主机窗口是唯一驱动者。** 远程访问的会话主控要求主机窗口活着（[会话主控](remote-session.md) 2.3）。设置通道可以复用同一个窗口请求机制：Gateway 挂起请求，`emit_to` 主机窗口，窗口执行后回复。
4. **现有的事件是 UI 的更新方式。** `loci:agents-changed`、`loci:agent-default-access-changed`、`loci:skills-change`、`loci:project-paths-changed`、`loci:archived-projects-changed`、`loci:model-controls-change` 等事件驱动 `useSyncExternalStore` 和各个 hook。客户端应用远端值后必须补发同样的事件，否则组件不会重绘。
5. **写入点分散。** 保存函数散布在 settings、models、agentAccess、skills、projects 等模块里，很多不在设置页（切模型、选账号、改项目路径都会写）。只改设置页的保存按钮覆盖不全。

### 3.2 三种做法

**方案 A：主机键值命令。**

A1. 把这些值搬进 Rust 的存储（SQLite 表或应用数据目录下的 JSON），新增 `settings_get`/`settings_set`，本机和远程都走命令。好处是权威独立于窗口，Gateway 在窗口关闭时也能回答，CLI 也能直接用；代价是 21 个键、约 30 个同步读取点要改成异步或加启动缓存，还要迁移现有 localStorage 值，并且和已有的导师注册表重复。

A2. Rust 命令只做转发：收到 `settings_get` 后按 `control.rs` 的模式挂起请求，让主机窗口读自己的 localStorage，再把结果回给调用方。好处是不搬存储；代价是每次读都是一次窗口往返，同步读取点仍然要加缓存。加上变更推送后，它和下面的方案 C 基本重合，只是多了一层命令外壳。

**方案 B：随会话 feed 下发。**

快照里带一个 `settings: Record<key, string | null>`，变化作为 feed 的一部分推给客户端，写入走意图。[会话主控](remote-session.md) 已经计划在快照里带 `roster`（2.1 节），再加一个 `settings` 字段看起来顺路。好处是复用 feed 的 `epoch`/`seq`、断线补齐和快照机制。代价是设置和会话的生命周期不同：设置要在第一个会话之前就可用；改一个主题开关不应该让会话 epoch 变化；客户端的会话镜像 store 会因此拥有非会话状态；feed 的 diff 和性质测试也要多维护一张表。

**方案 C：专用 settings 通道 + 客户端 localStorage 镜像（推荐）。**

主机窗口仍然是唯一写入者；客户端保留一份同键的 localStorage 镜像，读取方完全不变。连接时取一次快照，之后收变更事件，写入走意图。它和方案 A2 的区别是不把读做成命令往返，而是把值推到客户端；和方案 B 的区别是走独立的消息，不混进会话 patch。

| | A1 Rust 存储 | A2 窗口键值命令 | B 随会话 feed | C 专用通道 + 镜像 |
| --- | --- | --- | --- | --- |
| 同步读取方改动 | 大 | 大（仍要缓存） | 无 | 无 |
| 每次读的延迟 | 本机无，远程一次往返 | 本机无，远程一次往返 | 镜像，无 | 镜像，无 |
| 主机窗口必须活着 | 否 | 是 | 是 | 是 |
| 新增存储或迁移 | 有 | 无 | 无 | 无 |
| 与会话 feed 的耦合 | 无 | 无 | 高 | 低 |
| 设置先于会话可用 | 是 | 是 | 要额外处理 | 是 |
| 实现量 | 大 | 中 | 中 | 小 |

### 3.3 推荐方案：主机窗口做权威，客户端做镜像

#### 消息

复用 Gateway 的 `call`/`result` 和 `subscribe`/`event` 帧，新增三条消息。名字只是建议，落地时按 Gateway 的命名习惯调整。

| 消息 | 方向 | 参数 | 返回 / 载荷 |
| --- | --- | --- | --- |
| `settings.snapshot` | 客户端 → 主机 | 无 | `{ revision, values: Record<string, string \| null> }`，只含白名单里的键 |
| `settings.set` | 客户端 → 主机 | `{ key, value: string \| null }` | `{ revision, key, value }`；主机校验并应用后的值 |
| `settings.changed` | 主机 → 已订阅客户端 | 无 | `{ revision, key, value, origin?: "host" \| "remote" }` |

`revision` 是主机窗口这次加载内单调递增的整数。客户端只应用 `revision` 更大的消息；重连或主机窗口重载后重新取快照。它不替代会话 feed 的 `epoch`/`seq`，两者互不依赖。

`settings.set` 走和 `session.intent` 相同的窗口请求机制：Gateway 校验身份和白名单，选主机窗口（没有就显示或重开），挂 `Pending`，`emit_to(window, "loci-settings-set", …)`，窗口执行后 `invoke("remote_settings_reply", …)`。可以复用 `control.rs` 的模式，但用独立的事件名和 Pending 表，避免和 CLI 控制通道的权限模型混在一起。

#### 主机侧

新增一个模块，建议 `src/app/remote/hostSettings.ts`：

- `HOST_SHARED_KEYS`：第 1.1 节里走设置通道的 16 个键。`loci:agent-roster` 走 `mentors_load`，`loci:agent-previews` 随名单下发，`loci:agent-handed`、`loci:agent-rotations`、`loci.projectLocations` 是主机内部簿记，这五个都不进白名单。
- `snapshot()`：按白名单读 localStorage，返回字符串值。没存过的键返回 `null`，让客户端知道用默认值。
- `apply(key, value)`：校验键在白名单里；调用该键对应的现有保存函数，复用它的规范化逻辑和事件，返回应用后的值。远程来源的 `apply` 要让保存函数跳过 `publish`（例如传一个模块级标记），最后由 `apply` 统一广播一次，避免同一写入广播两次。
- `publish(key)`：从 localStorage 读当前值，`revision += 1`，向已订阅的客户端广播 `settings.changed`。
- 在主机窗口监听 `storage` 事件：同一个应用的其他窗口写入 localStorage 时，主控窗口会收到 `storage`，按白名单补一次 `publish`。同一个窗口自己的写入不会触发 `storage`，所以每个保存函数在写完后调一次 `publish(key)`。

保存函数的改动是一行：

```ts
export function saveFollowUpBehavior(value: FollowUpBehavior) {
  localStorage.setItem(FOLLOW_UP_BEHAVIOR_KEY, value);
  publishHostSetting(FOLLOW_UP_BEHAVIOR_KEY); // 新增
}
```

需要加的保存函数集中在 `settings.ts`、`models.ts`、`agentAccess.ts`、`learningLanguage.ts`、`skills.ts`、`builtinMcp.ts`、`providerBinaryPaths.ts`、`projectProviders.ts`、`recents.ts`。大约 15 处。`providerAccounts.ts` 当前只有读，没有写；以后加写入时同样接 `publish`。

#### 客户端侧

新增一个模块，建议 `src/app/remote/hostSettingsCache.ts`：

- 连接后 `transport.call("settings.snapshot")`，把每个值写进客户端同名的 localStorage 键，然后按值补发对应的现有事件（`loci:agents-changed` 不在这里，名单单独处理）。
- 收到 `settings.changed` 时，若 `revision` 更大，写 localStorage，补发事件，更新内存快照。
- 暴露 `writeHostSetting(key, value)`：远程模式下 `transport.call("settings.set", …)`，不直接写本地；主机的回声会走同一条应用路径。主机模式下返回 `false`，让调用方继续走本地保存。
- 启动时等一次 `ready`（快照已应用）再渲染工作区，避免首帧读到默认值。之前启动缓存在 localStorage 里的值仍然可用，所以离线打开也能显示上次的内容。

保存函数在远程模式下先问 `writeHostSetting`：

```ts
export function saveFollowUpBehavior(value: FollowUpBehavior) {
  if (writeHostSetting(FOLLOW_UP_BEHAVIOR_KEY, value)) return; // 远程：交给主机
  localStorage.setItem(FOLLOW_UP_BEHAVIOR_KEY, value);
  publishHostSetting(FOLLOW_UP_BEHAVIOR_KEY);
}
```

这个 guard 只加在允许远程修改的键上。客户端的读取函数、组件、`useSyncExternalStore` 快照都不用改。`settings.set` 失败时保留原值并提示；主机离线时设置页只读，沿用 [远程访问](remote-access.md) 第 7 节。

#### 写入顺序与冲突

- 设置是低频、整值覆盖的。主机按收到的顺序应用，后到的赢；回声带回主机实际应用的值，客户端以回声为准。不做合并，也不做乐观更新。局域网和 relay 下往返通常小于 300 ms，设置页的开关可以接受；如果觉得慢，再对布尔开关做乐观应用和失败回滚。
- 同一台主机的多个窗口共享同一份 localStorage 和 `storage` 事件，主控窗口的 `publish` 能覆盖其他窗口的写入。
- 主机窗口重载时 `revision` 从 0 开始。客户端发现 `revision` 回退或连接重建，重新取快照。

#### 名单和预览

名单不走设置通道：

- 客户端连接后调 `mentors_load`（`src/features/agents/model/mentorStore.ts:117`），拿到和主机一致的 `Agent[]`，写进客户端自己的 `loci:agent-roster` 副本（只写本地），`listAgents()` 照旧同步读。`hydrateMentors` 已经在启动时做迁移和加载（`mentorStore.ts:126`），客户端变体只需要加载，不跑 `storage_migrate`、`mentors_sync` 这些写路径。
- 主机窗口收到 `loci:mentors-changed`（`mentorStore.ts:21`）时，把事件转发给已订阅的客户端；客户端重新调 `mentors_load`。名单变化频率低，整份重取比做增量简单。
- 导师的增删改继续走 `agent.create`、`agent.reset`、`agent.remove` 意图（[会话主控](remote-session.md) 2.2），由主机写 localStorage 和 Rust。
- `loci:agent-previews` 是名单的派生数据，由主机的 `useAgents` 在会话结束后写（`src/app/hooks/useAgents.ts:205`）。它随名单快照的附加字段下发，或者另发一条 `agent.previews` 读命令；名单变化频率低，整份重取即可。客户端把它写进自己的 `loci:agent-previews` 副本供 `agentPreviewsSnapshot` 同步读，但不向主机写。
- 客户端的 `useAgents` 换成只读镜像（[会话主控](remote-session.md) 2.5），不挂会写库、归档、收文档的 effect。

#### 白名单和校验

- Gateway 和主机窗口各查一次白名单：不在名单里的键直接拒绝，避免远程读写任意 localStorage（比如 `loci:agent-handed`）。
- 值的长度设上限（建议 64 KiB）。名单本身可能有几十 KB，但它走 `mentors_load`，不占这个上限。
- `providerAccounts.v1` 只存账号标签和 id（`src/features/providers/model/providerAccounts.ts:43-49`），没有 token；落地前再确认一次。设置通道仍然在 E2E 里面。
- 值按字符串传输，保持 localStorage 的原始格式。客户端和主机用同一套规范化函数解析，不引入第二套 schema。

#### 逐键处理

| 键 | 处理 |
| --- | --- |
| `loci:agent-roster` | `mentors_load` + 转发的 `loci:mentors-changed`；增删改走意图 |
| `loci:agent-default-access`、`loci.learningLanguage`、`loci.followUpBehavior` | 设置通道；同时在相关意图里显式带上值，保证 P1 不依赖通道 |
| `loci.defaultModels`、`loci.lastModel`、`loci.lastModelSettings`、`loci.hiddenPickerProviders`、`loci.projectProviderSettings.v1` | 设置通道 |
| `loci.providerAccounts.v1`、`loci.providerAccountSelections.v1`、`loci.providerBinaryPaths.v1` | 设置通道；前两个当前只有读，写入随账号管理一起接；主机 CLI 登录仍在主机做 |
| `loci.claudeHooks`、`loci.builtinExcalidrawMcpEnabled`、`loci.disabledSkillPaths` | 设置通道；它们改变主机 CLI 的启动参数和工具 |
| `loci.recentProjects`、`loci.archivedProjects` | 设置通道；应用后补发 `loci:project-paths-changed`、`loci:archived-projects-changed` |
| `loci:agent-previews` | 随名单下发，只读 |
| `loci:agent-handed`、`loci:agent-rotations`、`loci.projectLocations` | 仅主机，不进白名单，客户端不读不写 |

### 3.4 实施顺序

1. 主机侧白名单、`snapshot`、`publish`；客户端 `settingsCache` 的读取和应用；先只做读，验证远程端能看到主机的默认模型、权限、项目和 provider 设置。
2. `settings.set` 意图和主机 `apply`；先接设置页的写入，再接模型选择器、项目路径这些散落的写入点。
3. 名单：客户端 `mentors_load`，主机转发 `loci:mentors-changed`，导师增删改走意图。
4. 预览和项目事件补齐；断线重连、主机窗口重载的测试。

### 3.5 验收

- 在客户端改主题、字体、缩放、栏宽、折叠状态，主机的外观不变；反过来也一样。
- 在主机改默认模型，客户端的模型选择器在一次事件内更新；在客户端改默认模型，主机下一次新会话用它。
- 在客户端改新导师的默认权限，主机 `agents.create` 用的是新值（`src/features/agents/model/agentWorkspace.ts:125`）。
- 在主机改导师名或新建导师，客户端导师栏在一次 `loci:mentors-changed` 后更新；客户端的导师操作落在主机，主机窗口的视图不被切走。
- 断开再连，客户端的设置和主机一致；主机窗口重载后也能重新对齐。
- `settings.set` 收到白名单外的键（例如 `loci:agent-handed`）时被拒绝；客户端没有写 `loci:agent-roster`、`loci:agent-handed`、`loci:agent-rotations`、`loci.projectLocations`。
- 客户端模式没有任何 `harness_*` 调用；这条沿用会话主控的测试。

### 3.6 风险

- **漏发。** 某个保存函数忘了 `publish`，客户端会静默漂移。用一张“白名单键 → 保存函数”的表和一条测试兜底：每个白名单键至少有一个会 `publish` 的写入函数。
- **首帧默认值。** 快照到达前，客户端组件可能先渲染默认值。用 `ready` 闸门挡住工作区；设置页可以显示骨架。
- **主机窗口不可用。** 窗口关到托盘是隐藏，不影响；窗口被销毁时按 `pick_window` 的规则重开（`src-tauri/src/control.rs:201`、`:314`）。如果以后要把设置做到窗口关闭也能读，再考虑 A1 的 Rust 存储。
- **敏感值。** 当前名单里的键都不含凭证；新增键进白名单前要单独审一次。
- **体积。** 快照预计在 100 KB 以内（名单另走 `mentors_load`），没有实测；`recentProjects` 和 `disabledSkillPaths` 是主要变量。

## 未覆盖

- 没有实测快照体积和 `settings` 往返延迟；第 3.6 节的数字是估计。
- 没有逐一验证 `providerAccounts.v1` 的所有写入方；当前代码只有读。
- 客户端设置页的离线编辑、冲突提示不在本文范围。主机离线时客户端只读，沿用 [远程访问](remote-access.md) 第 7 节。
- 没有把新文档加进 `docs/README.md` 的索引；本次任务只允许改三个文件。
