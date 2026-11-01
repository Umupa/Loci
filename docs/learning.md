# 和导师一起阅读：来源提问、高亮与批注

Loci 的阅读区可以显示资料库文档、课程的课文、Markdown 与源码文件、PDF。所有阅读器共用同一套操作：选中文字后向导师提问、高亮、写笔记；导师知道你读到哪里；导师回复里的链接能跳回原文的具体位置。

![PDF 高亮、批注笔记与关联讨论](images/learning/pdf-annotation.png)

## 选中文字

在任何阅读器里选中一段文字，会出现三个操作：

- **Ask <导师名>**：把选段连同它的位置作为来源放进导师的输入框，并预填 "Explain this passage."。这一步不会发送，可以先改问题再发。
- **Highlight**：保存黄色高亮。点击高亮会打开它：可以写笔记、提问、打开关联讨论或删除。
- **Note**：先高亮，再直接进入笔记输入框。

还有两个快捷键：**⌘L**（Windows/Linux 为 Ctrl+L）把选段作为引用放进输入框；**⌥⌘M**（Ctrl+Alt+M）打开评论框，写好后连同选段放进输入框。

不同阅读器里的位置信息：

| 阅读器 | 记录的位置 |
| --- | --- |
| 资料库文档、课程的文档课 | 选段原文、上下文、所在的小节标题 |
| 源码与文本文件（文件阅读器、课程的代码课） | 选段原文、行号（课程只显示部分行时，仍按文件原行号） |
| Markdown 文件预览 | 选段原文、所在小节 |
| PDF | 页码与选区矩形，新高亮同时保存原文 |

**Highlights & notes** 列出当前内容的全部高亮和笔记：文档在 "…" 菜单里；课程在课的菜单里（只列本课的部分）；文件阅读器和 PDF 在标题栏的笔形按钮。点击条目会滚动到原文并闪一下。

## 读代码

**钉住版本的代码导览课。** 代码课的文件写成 `repos/<owner>/<repo>@<commit>:path#L40-88`：Loci 用 `git show` 读出那个 commit 时的文件，课文标题下显示 `@3f2a9c1`。仓库之后 pull 了新提交、这个文件也改了，标题下会说明，并提供 **Open current**（打开现在的文件，标明 HEAD；改动没碰这几行时自动换算到新行号）和 **Show pinned**（回到钉住的版本）。只是 HEAD 前进而文件没变时，只有一行灰字说明。clone 里没有这个 commit（浅克隆）或文件不在 git 仓库里时，显示现在的文件并说明原因。导师用 `code.pins` 能看到哪些课已经过期。

**代码阅读器。** Go、Rust、C、TypeScript/TSX、JavaScript、Python 文件在阅读区打开时（课文里点 **Open whole file**，或者文件链接），标题栏多一个 **Symbols** 按钮：本文件的定义大纲，可筛选，点一下滚到那一行。

- **⌘ 点击**（Windows/Linux 为 Ctrl 点击）一个名字，跳到它的定义；
- 选中名字后，选段菜单在 Ask / Highlight / Note 之后多了 **Definition** 和 **References**；
- 多个候选或引用列在一个小弹层里，按文件分组；点一项，阅读区换成那个文件并停在那一行。

查找按名字匹配：`git grep -w` 先缩小到同语言的文件，再用 tree-sitter 读出定义或标识符，所以和编译器的解析结果可能不同（例如两个类型都有 `Close`），列表会按"本项目先于 vendor、真正定义先于 C 原型、同文件同目录优先"排序。从钉住的课里跳转时，一直停在那个 commit 上；标题栏的 `@3f2a9c1` 点一下回到现在的文件。不引入 LSP，也不需要预先建索引。

**后退与前进。** 阅读区每换一页都会记下来，像浏览器一样：标题栏出现 ‹ ›，或按 **⌘[** / **⌘]**。回到课程时回到原来那一课；跳到定义后后退，会回到离开时的那一行；关闭阅读区也能后退回来。每位导师各自记最近 50 页，只在本窗口打开期间保留。

高亮、笔记、选中即问在代码上照常可用；在钉住版本上提问时，来源会带上 commit。

## 学习路径

导师可以把一个大目标拆成 **3–5 门短课**（每门 6–12 课），按顺序排成学习路径，存为导师文件夹里的 `courses/_path.yaml`（导师用 `path.write` 写，也可以直接改文件，改动实时生效）：

```yaml
schemaVersion: 1
title: Sandboxes from the source
courses:
  - id: sandbox-foundations
  - id: cube-internals
    after: [sandbox-foundations]
  - id: snapshots-compared
    title: Snapshot and restore, three ways
    after: [cube-internals]
```

左栏 **Courses** 有路径时先列出整条路径：每门课的序号、标题、进度条和已读数；还没写的课显示为 *planned*，点一下会在输入框里请导师写它；前置课还没读完时，课下面一行灰字 "Best after …"——只是提示，**不会锁住任何一门课**。路径之外的课列在 "Other courses"。下面是当前这门课的目录。路径可以折叠成只剩当前这门。没有路径、但有两门以上课程时，课程切换菜单里可以 "Ask <导师> to plan a path"。

## 高亮如何跟随修改

高亮按文字定位，不按 DOM 位置：保存选段原文、前后各 32 个字符、所在小节和（文件中的）行号。文档被导师修订、文件被改了几行后，高亮仍落在同一段文字上；原文有多处相同文字时，按上下文选最贴合的一处；空白或大小写变了也能找到。文字已经不在时，高亮不会被删除，列表里会显示 "This passage changed"，可以继续提问或手动删除。

PDF 高亮保存每页的相对矩形，缩放时重新投影。PDF 依赖已有文本层，不做 OCR；没有可选文字的页面无法选段。

## 导师知道你读到哪里

每次发消息时，导师都会收到 `<reading_now>`：当前打开的课、文档或文件，以及 `place`：

- `section`：可见段落上方的小节标题（最多三级）
- `paragraph`：阅读区顶部那一段的开头（最多 280 字符）
- `page` 或 `lines`：PDF 当前页，或文件可见的行
- `selection`：你在阅读区选中的文字（最多 600 字符）。焦点移到输入框后仍然保留；在阅读区点一下或换页会清除。

所以 "这段" "这里" 不需要再解释。整个 `place` 不超过 1.5 KB；如果选段已经作为来源附在消息里，只写 `"selection":"attached"`，不会重复。

## 导师的引用会跳到原文

导师可以用 `loci://source/<id>` 引用来源，并带上位置：

```text
[Pod phase](loci://source/k8s-pod-lifecycle#section=Pod%20phase)
[Pending 的定义](loci://source/k8s-pod-lifecycle#section=Pod%20phase&quote=The%20Pod%20has%20been%20accepted)
[第 7 页](loci://source/<id>#p7)    [第 12–40 行](loci://source/<id>#L12-40)
```

`<id>` 是资料库里的文档 ID，或是消息里附带的来源 ID。点击后来源在阅读区打开（如果当前正读的课就是这篇文档，则留在课里，必要时展开全文），滚动到引用的文字并闪一下。文字已经改动时，显示所在小节并提示 "That passage has changed"。完整格式写在 `loci app --help` 的 "Citing what the learner reads" 一节。

## 课程目录里的数量

左栏课程目录在每一课后面显示这一课的高亮数量；有笔记时数字旁多一个小圆点。课程行显示总数。没有高亮时不显示。

## 网页与会话来源

输入框的附件菜单提供 **Web source**：填入 HTTP 或 HTTPS 地址、可选标题，再粘贴要讨论的原文。这里不自动抓取网页，点击来源会在系统浏览器中打开地址。聊天选段可以记录对应会话和消息。

来源在输入框和已发送消息中单独显示：点击标签右侧箭头（**Show passage**）查看选段，点击标题打开原处，移除标签可将它排除出下一次请求。

各 CLI 接收统一的文本上下文 `<loci_learning_context>`，无需 provider 专用的 UI 工具。只带入被引用的选段与相关上下文，不默认上传整本 PDF 或整篇文档。

## 关联讨论

围绕某个高亮的问题实际发送后，高亮才关联这条会话消息；准备或取消草稿不会创建关联。删除高亮会保留此前消息中的选段快照；会话已删除时，打开对应讨论会提示不可用。

## 命令行

`loci annotations list | counts | add | note | delete` 读写高亮和笔记，详见 [cli.md](cli.md)。`loci code symbols | definition | references | read | pin | pins` 和 `loci path read | write` 是读码和学习路径的命令，导师在自己的对话里也能用。导师在自己的对话里可以 `list` 和 `counts`，看到你标记了什么；新增、改笔记、删除只能从终端做。`loci reader open --source <id> --quote "<原文>"` 打开并闪烁一段原文。

## 存储

高亮、笔记和来源保存在本地 `loci.db`，不写回文件或 PDF。导师文件夹里文件上的高亮以 `mentorFile` `<导师>/<文件夹内路径>` 记录，随文件夹导出、导入或移动；资料库文档的高亮仍是 `<导师>/<文档 id>`，对应 `sources/` 或 `guides/` 里的同名文件。`learning_sources` 保存来源；`reading_documents` 保存 PDF 的规范化路径和 PDF.js 指纹；`pdf_annotations` 保存所有阅读器的高亮（v0.3 原地增加了 `target_kind`、`target_key`、`anchor_json` 三列，旧版本只看到其中的 PDF 高亮）。

PDF 移动后，**Locate file** 通过系统选择器重新定位；指纹不匹配时拒绝迁移，避免把旧高亮套到另一版文档上。

代码在 `src/features/learning`（模型、阅读器共用的界面）、`src/features/mentor/ui/useReadingPlace.ts`（阅读位置）和 `src-tauri/src/learning.rs`。
