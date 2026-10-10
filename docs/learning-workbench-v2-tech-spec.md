# Loci 教学工作台 v2 技术方案

**目标读者**：负责实现的开发者  
**依赖**：本方案以现有 `canvas.rs` / `loci-widget` / `loci-document` 的模式为模板，保持风格一致  

## 实现与使用补充

实现沿用下文的两种课程引擎和独立 Diff 卡片，并按现有项目接口作了以下调整：

- 课程按所属 Agent 或项目会话隔离：数据库主键为 `(agent_id, id)`，进度主键为 `(agent_id, course_id, item_id)`。`course_get` 传 `{ id, agentId }`，进度读取/写入均传 `agentId`；Tauri 输入输出使用 camelCase。
- JSON 在前后端边界都校验。步骤/概念不能为空、ID 唯一、所有概念引用必须存在，`learningPath` 是必填数组。推荐路径未包含的概念仍出现在导航末尾。
- 重开同一课程保留进度；修订保留仍存在的 item 进度，删除项的进度同步清理；切换引擎清空旧进度。课程结构与进度清理在同一 SQLite 事务内完成。
- `canvas-id` 持久化在课程数据中。双击导航使用 Excalidraw 自己的命中结果，并带 `courseId`、`conceptId`、`canvasId`；节点声明可选 `customData.agentId` 时也携带所属标识，仅匹配的已打开课程响应。
- 概念进度保存后，应用通过现有画布写入队列、版本比较与草稿合并更新节点颜色，也支持关闭的画布。画布更新失败不撤销已保存进度，界面提供 **Retry map update**。
- 进度保存或画布更新期间课程发生修订时，按当前课程版本同步画布；仍在加载的修订完成后再同步，已删除的概念不再更新旧节点。
- **Mark as learning / Mark as mastered / Reset progress** 保存进度；**Discuss progress** 将课程进度放入所属会话的可编辑草稿，用户发送后才运行 Agent。
- `simulationHtml` 复用现有 widget 存储、运行时与隔离框架。**Copy command** 只复制命令，保留代码缩进和空行。
- Diff 计算限制输入大小、计算时间和编辑距离，并限制逐行渲染数量。超出限制时显示完整的 Before / After 原文，不做语法高亮。
- 课程 pane 支持聚焦、关闭、拖动、重启恢复和同 ID 修订刷新。创建 Agent 的模板菜单新增 **Builder**、**Navigator**、**Lens** 三个 Soul 模板；已有 Agent 的 Soul 不会自动改写。

下文代码为原始方案示例；实际接口与失败处理以实现补充和代码为准。

验证记录：前端全量 4041 项测试与 TypeScript 检查通过，Rust 格式、Clippy 和 247 项测试通过。浏览器验收使用真实 Course/Markdown/Excalidraw 组件和隔离 IPC 适配，验证打开、步骤切换、命令复制、深浅主题、窄分栏、双击概念导航，以及进度/节点颜色刷新恢复；SQLite 持久化与故障回滚由 Rust 实际数据库测试覆盖。本轮未启动真实 Agent 生成课程，也未验证新功能在原生 WebView 中的完整流程。

---

## 一、变更范围

### 新增文件

| 文件 | 说明 |
|------|------|
| `src-tauri/src/course.rs` | Course 持久化（SQLite，模仿 canvas.rs） |
| `src/features/learning/model/course.ts` | TS 类型定义 + 解析器 |
| `src/features/learning/ui/CourseCard.tsx` | chat 内嵌卡片（摘要 + Open 按钮） |
| `src/features/learning/ui/CoursePane.tsx` | 完整课程浏览器（主体） |
| `src/features/learning/ui/CoursePane.css` | |
| `src/features/learning/ui/DiffCard.tsx` | diff 渲染组件（可独立使用） |
| `src/features/learning/ui/DiffCard.css` | |

### 修改文件

| 文件 | 改动说明 |
|------|---------|
| `src/features/sessions/model/cards.ts` | 新增 `CARD_FENCE.course` + `CARD_FENCE.diff` |
| `src/features/sessions/ui/AgentMarkdown.tsx` | 新增 course/diff 卡片路由 |
| `src/features/workspace/model/layout.ts` | 新增 `"course"` leafKind + `showCourseInTab()` |
| `src/features/workspace/ui/PaneTree.tsx` | 新增 `CoursePane` 渲染 |
| `src/features/canvas/ui/CanvasPane.tsx` | 新增 customData 双击处理器 |
| `src-tauri/src/lib.rs` | 注册 course_* 命令，初始化 courses 表 |

---

## 二、数据层：course.rs

### 2.1 SQLite schema

```rust
// src-tauri/src/course.rs
pub fn ensure_courses_table(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS courses (
            id          TEXT PRIMARY KEY,
            agent_id    TEXT NOT NULL,
            engine      TEXT NOT NULL,   -- 'build-your-own' | 'domain-navigation'
            title       TEXT NOT NULL,
            data_json   TEXT NOT NULL,   -- 完整课程 JSON（步骤/概念，不含 status）
            created_at  INTEGER NOT NULL,
            updated_at  INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS course_progress (
            course_id   TEXT NOT NULL,
            item_id     TEXT NOT NULL,   -- step id 或 concept id
            status      TEXT NOT NULL,   -- 'untouched' | 'learning' | 'mastered'
            PRIMARY KEY (course_id, item_id)
        );
        CREATE INDEX IF NOT EXISTS idx_courses_agent ON courses(agent_id);",
    )
}
```

> **设计决策**：`data_json` 存不可变的课程结构；学习进度单独存 `course_progress`，避免状态更新时重写全量 JSON。

### 2.2 Rust structs

```rust
#[derive(serde::Serialize, serde::Deserialize, Clone)]
pub struct Course {
    pub id: String,
    pub agent_id: String,
    pub engine: String,
    pub title: String,
    pub data_json: String,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(serde::Serialize, serde::Deserialize)]
pub struct CourseUpsert {
    pub id: String,
    pub agent_id: String,
    pub engine: String,
    pub title: String,
    pub data_json: String,
}

#[derive(serde::Serialize, serde::Deserialize)]
pub struct CourseProgressItem {
    pub item_id: String,
    pub status: String,
}
```

### 2.3 Tauri commands

```rust
#[tauri::command]
pub fn course_list(store: State<'_, SessionStore>, agent_id: String)
    -> Result<Vec<Course>, String> { ... }

#[tauri::command]
pub fn course_get(store: State<'_, SessionStore>, id: String)
    -> Result<Option<Course>, String> { ... }

#[tauri::command]
pub fn course_upsert(store: State<'_, SessionStore>, course: CourseUpsert)
    -> Result<Course, String> { ... }

// 批量取进度（打开课程时一次性拉取）
#[tauri::command]
pub fn course_progress_get(store: State<'_, SessionStore>, course_id: String)
    -> Result<Vec<CourseProgressItem>, String> { ... }

// 单项状态更新（用户完成某步/概念时调用）
#[tauri::command]
pub fn course_progress_set(
    store: State<'_, SessionStore>,
    course_id: String,
    item_id: String,
    status: String,   // "untouched" | "learning" | "mastered"
) -> Result<(), String> { ... }
```

在 `lib.rs` 的 `invoke_handler` 中注册这 5 个 command，并在数据库初始化时调用 `ensure_courses_table`（与 `ensure_canvases_table` 同位置）。

---

## 三、解析层：course.ts

### 3.1 TypeScript 类型

```typescript
// src/features/learning/model/course.ts

export type CourseEngine = "build-your-own" | "domain-navigation";
export type LearningStatus = "untouched" | "learning" | "mastered";

export type CourseStep = {
  id: string;            // "s01", "s02", ...
  title: string;
  summary: string;       // 一句话说明本步加了什么
  file: string;          // 文件名（用于语法高亮）
  before: string;        // 完整的 before 代码
  after: string;         // 完整的 after 代码
  explanation: string;   // markdown 解释文本
  runCommand?: string;
};

export type CourseConcept = {
  id: string;
  title: string;
  content: string;          // markdown
  prerequisites: string[];
  leadsTo: string[];
  simulationHtml?: string;  // 可选 widget HTML
};

export type CourseData =
  | { engine: "build-your-own"; steps: CourseStep[] }
  | { engine: "domain-navigation"; learningPath: string[]; canvasId?: string; concepts: CourseConcept[] };

// 前端持有的完整课程（data + progress 合并）
export type CourseWithProgress = {
  id: string;
  agentId: string;
  title: string;
  data: CourseData;
  progress: Map<string, LearningStatus>; // itemId → status
};
```

### 3.2 loci-course 格式（Agent 输出格式）

**YAML 前言 + JSON 正文**，与 loci-widget 保持一致的解析风格：

Engine 1:
````
```loci-course
---
id: build-your-own-agent
engine: build-your-own
title: Build Your Own Claude Code Harness
---
{
  "steps": [
    {
      "id": "s01",
      "title": "The Agent Loop",
      "summary": "一个 while True 循环，模型调用工具就继续",
      "file": "main.py",
      "before": "",
      "after": "import anthropic\nclient = anthropic.Anthropic()\n\ndef agent_loop(messages):\n    while True:\n        ...",
      "explanation": "这一步解决了什么问题...",
      "runCommand": "python main.py"
    }
  ]
}
---
```
````

Engine 2:
````
```loci-course
---
id: kubernetes-deep-dive
engine: domain-navigation
title: Kubernetes Deep Dive
canvas-id: <excalidraw-canvas-id>
---
{
  "learningPath": ["container", "pod", "replicaset", "deployment", "service"],
  "concepts": [
    {
      "id": "pod",
      "title": "Pod",
      "prerequisites": ["container"],
      "leadsTo": ["replicaset", "service"],
      "content": "Pod 是 Kubernetes 的最小调度单元...\n\n..."
    }
  ]
}
---
```
````

### 3.3 parseCourse()

```typescript
export const COURSE_FENCE = "loci-course";

export type CourseParseResult =
  | { course: ParsedCourse; error?: never }
  | { course?: never; error: string };

export type ParsedCourse = {
  id: string;
  title: string;
  engine: CourseEngine;
  canvasId?: string;
  data: CourseData;
};

export function parseCourse(source: string): CourseParseResult {
  const text = source.replace(/^﻿/, "").replace(/\r\n/g, "\n");
  const front = text.match(/^\s*---\n([\s\S]*?)\n---[ \t]*(?:\n|$)/);
  if (!front) return { error: "loci-course requires YAML front matter." };

  const fields: Record<string, string> = {};
  for (const line of front[1].split("\n")) {
    const m = line.match(/^\s*([a-zA-Z-]+)\s*:\s*(.*?)\s*$/);
    if (m) fields[m[1]] = m[2].replace(/^(["'])(.*)\1$/, "$2");
  }

  const id = fields.id?.trim();
  if (!id || !/^[\w-]+$/.test(id)) return { error: "loci-course needs a valid id." };

  const title = fields.title?.trim();
  if (!title) return { error: "loci-course needs a title." };

  const engine = fields.engine as CourseEngine;
  if (engine !== "build-your-own" && engine !== "domain-navigation")
    return { error: `Unknown engine: ${engine}` };

  // JSON 正文在第二个 --- 之后到第三个 --- 之前
  const body = text.slice(front[0].length).replace(/\n---\s*$/, "").trim();
  let parsed: unknown;
  try { parsed = JSON.parse(body); }
  catch { return { error: "loci-course body must be valid JSON." }; }

  if (engine === "build-your-own") {
    const { steps } = parsed as { steps?: unknown };
    if (!Array.isArray(steps) || steps.length === 0)
      return { error: "build-your-own course needs a steps array." };
    return { course: { id, title, engine, data: { engine, steps: steps as CourseStep[] } } };
  } else {
    const { concepts, learningPath } = parsed as { concepts?: unknown; learningPath?: unknown };
    if (!Array.isArray(concepts)) return { error: "domain-navigation course needs a concepts array." };
    return {
      course: {
        id, title, engine,
        canvasId: fields["canvas-id"],
        data: {
          engine,
          learningPath: Array.isArray(learningPath) ? learningPath as string[] : [],
          concepts: concepts as CourseConcept[],
          canvasId: fields["canvas-id"],
        },
      },
    };
  }
}
```

### 3.4 loci-diff 格式与解析

**格式**（YAML 前言 + `=== BEFORE ===` / `=== AFTER ===` 节分隔）：

````
```loci-diff
---
id: s01-agent-loop
title: Step 1 — The Agent Loop
file: main.py
run: python main.py
---
=== BEFORE ===
(empty file)
=== AFTER ===
import anthropic
client = anthropic.Anthropic()

def agent_loop(messages):
    while True:
        response = client.messages.create(...)
```
````

```typescript
export const DIFF_FENCE = "loci-diff";

export type DiffSpec = {
  id: string;
  title: string;
  file: string;
  before: string;
  after: string;
  runCommand?: string;
};

export type DiffParseResult =
  | { diff: DiffSpec; error?: never }
  | { diff?: never; error: string };

export function parseDiff(source: string): DiffParseResult {
  const text = source.replace(/^﻿/, "").replace(/\r\n/g, "\n");
  const front = text.match(/^\s*---\n([\s\S]*?)\n---[ \t]*(?:\n|$)/);
  if (!front) return { error: "loci-diff needs front matter." };

  const fields: Record<string, string> = {};
  for (const line of front[1].split("\n")) {
    const m = line.match(/^\s*([a-zA-Z-]+)\s*:\s*(.*?)\s*$/);
    if (m) fields[m[1]] = m[2].replace(/^(["'])(.*)\1$/, "$2");
  }

  const id = fields.id?.trim();
  if (!id || !/^[\w-]+$/.test(id)) return { error: "loci-diff needs a valid id." };
  const title = fields.title?.trim();
  if (!title) return { error: "loci-diff needs a title." };
  const file = fields.file?.trim() || "file";

  const body = text.slice(front[0].length);
  const beforeMatch = body.match(/=== BEFORE ===\n([\s\S]*?)(?:=== AFTER ===|$)/);
  const afterMatch = body.match(/=== AFTER ===\n([\s\S]*?)$/);

  return {
    diff: {
      id, title, file,
      before: (beforeMatch?.[1] ?? "").trim(),
      after: (afterMatch?.[1] ?? "").trim(),
      runCommand: fields.run?.trim(),
    },
  };
}
```

---

## 四、cards.ts 变更

```typescript
// src/features/sessions/model/cards.ts — 修改 CARD_FENCE

export const CARD_FENCE = {
  question: "loci-question",
  document: "loci-document",
  todo:     "loci-todo",
  mindmap:  "loci-mindmap",
  canvas:   "loci-canvas",
  widget:   "loci-widget",
  course:   "loci-course",   // 新增
  diff:     "loci-diff",     // 新增
} as const;
```

同时更新 `KEPT_FENCES`：

```typescript
export const KEPT_FENCES = new Set([
  CARD_FENCE.document,
  CARD_FENCE.todo,
  CARD_FENCE.mindmap,
  CARD_FENCE.canvas,
  CARD_FENCE.widget,
  CARD_FENCE.course,  // 新增：课程卡折叠后保留
  // diff 不保留（步骤内容在课程浏览器中，不需要在 chat 重复显示）
]);
```

---

## 五、AgentMarkdown.tsx 变更

在现有 card 路由块（约 362 行）追加两个 case：

```tsx
import { CourseCard } from "../../learning/ui/CourseCard";
import { DiffCardFromSource } from "../../learning/ui/DiffCard";

// 在现有 if (card === CARD_FENCE.canvas) ... 之后追加：

if (card === CARD_FENCE.course)
  return <CourseCard source={textContent(children)} incomplete={!!incomplete} />;

if (card === CARD_FENCE.diff)
  return incomplete ? null : <DiffCardFromSource source={textContent(children)} />;
```

---

## 六、CourseCard.tsx（chat 内嵌）

功能：流式时显示进度；完成后显示课程摘要 + Open 按钮。

```tsx
// src/features/learning/ui/CourseCard.tsx

import { invoke } from "@tauri-apps/api/core";
import { useMemo } from "react";
import { parseCourse, type ParsedCourse } from "../model/course";
import { useAgentId } from "../../sessions/ui/AgentMarkdown";

export const OPEN_COURSE_EVENT = "loci:open-course";
export type OpenCourseDetail = { courseId: string; agentId: string; title: string };

function openCourse(courseId: string, agentId: string, title: string) {
  window.dispatchEvent(
    new CustomEvent<OpenCourseDetail>(OPEN_COURSE_EVENT, {
      detail: { courseId, agentId, title },
    })
  );
}

export function CourseCard({ source, incomplete }: { source: string; incomplete: boolean }) {
  // 正在流式生成时
  if (incomplete) {
    const stepCount = (source.match(/"id":\s*"s\d+"/g) ?? []).length;
    const conceptCount = (source.match(/"id":\s*"[^"]+"/g) ?? []).length - stepCount;
    const count = Math.max(stepCount, conceptCount);
    return (
      <div className="course-card course-card--generating" aria-busy>
        <span className="course-card__spinner" />
        <span>
          {count > 0
            ? `Generating course… ${count} item${count > 1 ? "s" : ""} so far`
            : "Generating course…"}
        </span>
      </div>
    );
  }

  const result = useMemo(() => parseCourse(source), [source]);

  if (result.error) {
    return <div className="course-card course-card--error">{result.error}</div>;
  }

  const { course } = result;
  const agentId = useAgentId();
  const engine = course.engine === "build-your-own" ? "Build Your Own" : "Domain Navigation";
  const itemCount =
    course.data.engine === "build-your-own"
      ? course.data.steps.length
      : course.data.concepts.length;
  const label = course.data.engine === "build-your-own" ? "steps" : "concepts";

  async function handleOpen() {
    await invoke("course_upsert", {
      course: {
        id: course.id,
        agentId,
        engine: course.engine,
        title: course.title,
        dataJson: JSON.stringify(
          course.data.engine === "build-your-own"
            ? { steps: course.data.steps }
            : { learningPath: course.data.learningPath, concepts: course.data.concepts }
        ),
      },
    });
    openCourse(course.id, agentId, course.title);
  }

  return (
    <div className="course-card">
      <span className="course-card__engine-badge">{engine}</span>
      <p className="course-card__title">{course.title}</p>
      <p className="course-card__meta">{itemCount} {label}</p>
      <button type="button" className="course-card__open-btn" onClick={handleOpen}>
        Open Course
      </button>
    </div>
  );
}
```

---

## 七、CoursePane.tsx（课程浏览器）

### 7.1 数据加载

```tsx
// src/features/learning/ui/CoursePane.tsx（节选）

import { invoke } from "@tauri-apps/api/core";
import { useEffect, useState } from "react";
import type { CourseWithProgress, LearningStatus } from "../model/course";
import { DiffCard } from "./DiffCard";

async function loadCourse(courseId: string): Promise<CourseWithProgress | null> {
  const [raw, progressItems] = await Promise.all([
    invoke<{ id: string; agentId: string; title: string; engine: string; dataJson: string } | null>(
      "course_get", { id: courseId }
    ),
    invoke<{ itemId: string; status: string }[]>("course_progress_get", { courseId }),
  ]);
  if (!raw) return null;

  const progress = new Map<string, LearningStatus>(
    progressItems.map((p) => [p.itemId, p.status as LearningStatus])
  );

  const data = JSON.parse(raw.dataJson);
  return {
    id: raw.id,
    agentId: raw.agentId,
    title: raw.title,
    data: raw.engine === "build-your-own"
      ? { engine: "build-your-own", steps: data.steps }
      : { engine: "domain-navigation", learningPath: data.learningPath ?? [], concepts: data.concepts, canvasId: data.canvasId },
    progress,
  };
}
```

### 7.2 主组件

```tsx
export function CoursePane({ courseId, onClose }: { courseId: string; onClose: () => void }) {
  const [course, setCourse] = useState<CourseWithProgress | null>(null);
  const [activeId, setActiveId] = useState<string | null>(null);

  useEffect(() => {
    loadCourse(courseId).then((c) => {
      setCourse(c);
      if (c) {
        const firstUnmastered = firstUnmasteredId(c);
        setActiveId(firstUnmastered ?? firstItemId(c));
      }
    });
  }, [courseId]);

  // 监听来自 Excalidraw 的概念导航事件（Engine 2）
  useEffect(() => {
    const handler = (e: CustomEvent<{ conceptId: string }>) => {
      setActiveId(e.detail.conceptId);
    };
    window.addEventListener("loci:navigate-concept", handler as EventListener);
    return () => window.removeEventListener("loci:navigate-concept", handler as EventListener);
  }, []);

  if (!course) return <div className="course-pane course-pane--loading">Loading…</div>;

  async function markStatus(itemId: string, status: LearningStatus) {
    await invoke("course_progress_set", { courseId, itemId, status });
    setCourse((c) => {
      if (!c) return c;
      const next = new Map(c.progress);
      next.set(itemId, status);
      return { ...c, progress: next };
    });
  }

  return (
    <div className="course-pane">
      <CourseNav course={course} activeId={activeId} onSelect={setActiveId} />
      <CourseContent course={course} activeId={activeId} onMarkStatus={markStatus} />
    </div>
  );
}
```

### 7.3 导航侧栏

```tsx
function CourseNav({
  course, activeId, onSelect,
}: {
  course: CourseWithProgress;
  activeId: string | null;
  onSelect: (id: string) => void;
}) {
  const items =
    course.data.engine === "build-your-own"
      ? course.data.steps.map((s) => ({ id: s.id, label: s.title }))
      : course.data.learningPath.length > 0
        ? course.data.learningPath.map((id) => {
            const c = course.data.concepts.find((c) => c.id === id);
            return { id, label: c?.title ?? id };
          })
        : course.data.concepts.map((c) => ({ id: c.id, label: c.title }));

  return (
    <nav className="course-pane__nav" aria-label="Course navigation">
      <p className="course-pane__nav-title">{course.title}</p>
      <ol className="course-pane__nav-list">
        {items.map(({ id, label }) => {
          const status = course.progress.get(id) ?? "untouched";
          return (
            <li key={id}>
              <button
                type="button"
                className={`course-pane__nav-item course-pane__nav-item--${status}${activeId === id ? " course-pane__nav-item--active" : ""}`}
                onClick={() => onSelect(id)}
              >
                <StatusDot status={status} />
                <span>{label}</span>
              </button>
            </li>
          );
        })}
      </ol>
    </nav>
  );
}

function StatusDot({ status }: { status: LearningStatus }) {
  // untouched: 空圆；learning: 实心橙；mastered: 勾
  return <span className={`status-dot status-dot--${status}`} aria-hidden />;
}
```

### 7.4 内容区

```tsx
function CourseContent({
  course, activeId, onMarkStatus,
}: {
  course: CourseWithProgress;
  activeId: string | null;
  onMarkStatus: (id: string, status: LearningStatus) => void;
}) {
  if (!activeId) return null;

  if (course.data.engine === "build-your-own") {
    const step = course.data.steps.find((s) => s.id === activeId);
    if (!step) return null;
    const status = course.progress.get(activeId) ?? "untouched";

    return (
      <article className="course-pane__content">
        <header>
          <h2>{step.title}</h2>
          <p className="course-pane__summary">{step.summary}</p>
        </header>
        <DiffCard
          id={`${course.id}-${step.id}`}
          title={step.title}
          file={step.file}
          before={step.before}
          after={step.after}
          runCommand={step.runCommand}
        />
        <MarkdownBody content={step.explanation} />
        <MasteredButton status={status} onMark={() => onMarkStatus(activeId, "mastered")} />
      </article>
    );
  }

  // Engine 2: domain-navigation
  const concept = course.data.concepts.find((c) => c.id === activeId);
  if (!concept) return null;
  const status = course.progress.get(activeId) ?? "untouched";

  return (
    <article className="course-pane__content">
      <header>
        <h2>{concept.title}</h2>
        {concept.prerequisites.length > 0 && (
          <p className="course-pane__prereqs">
            先修：{concept.prerequisites.join("、")}
          </p>
        )}
      </header>
      <MarkdownBody content={concept.content} />
      {concept.simulationHtml && (
        <WidgetFrame html={concept.simulationHtml} title={concept.title} />
      )}
      <MasteredButton status={status} onMark={() => onMarkStatus(activeId, "mastered")} />
    </article>
  );
}
```

---

## 八、DiffCard.tsx

> **npm 依赖**：需确认项目已有 `diff` 包，若无则 `pnpm add diff @types/diff`。

```tsx
// src/features/learning/ui/DiffCard.tsx

import { useMemo } from "react";
import { parseDiff } from "../model/course";

type Line = { kind: "add" | "remove" | "equal"; text: string };

function computeLineDiff(before: string, after: string): Line[] {
  const { diffLines } = require("diff");
  return diffLines(before, after).flatMap(
    (part: { added?: boolean; removed?: boolean; value: string }) =>
      part.value.split("\n").filter(Boolean).map((text) => ({
        kind: part.added ? "add" : part.removed ? "remove" : "equal",
        text,
      }))
  );
}

export type DiffCardProps = {
  id: string;
  title: string;
  file: string;
  before: string;
  after: string;
  runCommand?: string;
};

export function DiffCard({ id, title, file, before, after, runCommand }: DiffCardProps) {
  const lines = useMemo(() => computeLineDiff(before, after), [before, after]);

  const addCount = lines.filter((l) => l.kind === "add").length;
  const removeCount = lines.filter((l) => l.kind === "remove").length;

  return (
    <div className="diff-card" data-file={file}>
      <header className="diff-card__header">
        <span className="diff-card__file">{file}</span>
        <span className="diff-card__stats">
          {addCount > 0 && <span className="diff-card__add">+{addCount}</span>}
          {removeCount > 0 && <span className="diff-card__remove">-{removeCount}</span>}
        </span>
        {runCommand && (
          <button
            type="button"
            className="diff-card__run-btn"
            onClick={() => navigator.clipboard.writeText(runCommand)}
            title="Copy command to clipboard"
          >
            ⎘ Copy command
          </button>
        )}
      </header>
      <pre className="diff-card__body">
        <code>
          {lines.map((line, i) => (
            <span
              key={i}
              className={`diff-card__line diff-card__line--${line.kind}`}
            >
              <span className="diff-card__gutter">
                {line.kind === "add" ? "+" : line.kind === "remove" ? "−" : " "}
              </span>
              {line.text}
              {"\n"}
            </span>
          ))}
        </code>
      </pre>
    </div>
  );
}

// 从 loci-diff fence 直接渲染（在 AgentMarkdown 中使用）
export function DiffCardFromSource({ source }: { source: string }) {
  const result = useMemo(() => parseDiff(source), [source]);
  if (result.error) return <div className="diff-card diff-card--error">{result.error}</div>;
  const { diff } = result;
  return <DiffCard {...diff} />;
}
```

---

## 九、Layout 扩展

### 9.1 layout.ts

```typescript
// src/features/workspace/model/layout.ts

// leafKind 联合类型新增 "course"：
// 原：type LeafKind = "canvas" | "file" | "document" | "widget"
// 改为：
type LeafKind = "canvas" | "file" | "document" | "widget" | "course";

export type CourseLeafData = { courseId: string; agentId: string; title: string };

// 模仿 showDocumentInTab：
export function showCourseInTab(
  tabs: WorkspaceTab[],
  tabId: string,
  course: CourseLeafData
): WorkspaceTab[] {
  return placeLayout(tabs, tabId, {
    id: `course-${course.courseId}`,
    leafKind: "course",
    courseId: course.courseId,
    agentId: course.agentId,
    title: course.title,
  }, "right");
}
```

### 9.2 PaneTree.tsx

```tsx
import { CoursePane } from "../../learning/ui/CoursePane";

// 在现有 leaf.kind === "widget" / "document" / ... 之后追加：
if (leaf.kind === "course") {
  return (
    <CoursePane
      courseId={leaf.courseId}
      onClose={() => closeLeaf(leaf.id)}
    />
  );
}
```

### 9.3 App.tsx 事件监听

在 App.tsx 的 workspace 事件监听区（与 `"loci:open-document"` 同位置）追加：

```tsx
useEffect(() => {
  const handler = (e: CustomEvent<OpenCourseDetail>) => {
    workspace.showCourse({
      courseId: e.detail.courseId,
      agentId: e.detail.agentId,
      title: e.detail.title,
    });
  };
  window.addEventListener(OPEN_COURSE_EVENT, handler as EventListener);
  return () => window.removeEventListener(OPEN_COURSE_EVENT, handler as EventListener);
}, [workspace]);
```

---

## 十、Excalidraw 双击处理（Engine 2）

**目标**：双击 Excalidraw 中 `customData.type === "concept"` 的形状，触发 CoursePane 导航。

```tsx
// src/features/canvas/ui/CanvasPane.tsx

const lastPointerDown = useRef<{ id: string; time: number } | null>(null);
const lastPointerUp = useRef<{ id: string; time: number } | null>(null);

function handlePointerDown(activeTool: unknown, pointerEvent: PointerEvent) {
  const api = excalidrawApiRef.current;
  if (!api) return;
  const elements = api.getSceneElements();
  const hit = elements.find((el) => isPointerOverElement(el, pointerEvent));
  if (hit) {
    lastPointerDown.current = { id: hit.id, time: Date.now() };
  }
}

function handlePointerUp(activeTool: unknown, pointerEvent: PointerEvent) {
  const down = lastPointerDown.current;
  if (!down) return;
  const elapsed = Date.now() - down.time;
  if (elapsed < 400 && lastPointerUp.current?.id === down.id) {
    // 双击判定成立
    const api = excalidrawApiRef.current;
    const el = api?.getSceneElements().find((e) => e.id === down.id);
    const conceptId = (el as { customData?: { type?: string; conceptId?: string } })
      ?.customData?.conceptId;
    if (conceptId) {
      window.dispatchEvent(
        new CustomEvent("loci:navigate-concept", { detail: { conceptId } })
      );
    }
  }
  lastPointerUp.current = { id: down.id, time: Date.now() };
}

// 在 <Excalidraw> 追加：
<Excalidraw
  {...excalidrawProps}
  onPointerDown={handlePointerDown}
  onPointerUp={handlePointerUp}
/>
```

### Agent 生成概念节点的 customData 约定

Agent 调用 `create_view` 时每个概念矩形包含：

```json
{
  "type": "rectangle",
  "label": { "text": "Pod" },
  "backgroundColor": "#f4f4f5",
  "customData": {
    "type": "concept",
    "conceptId": "pod",
    "courseId": "kubernetes-deep-dive"
  }
}
```

Agent 调用 `update_elements` 更新状态颜色：

| status | backgroundColor |
|--------|----------------|
| untouched | `#f4f4f5` |
| learning | `#fef3c7` |
| mastered | `#dcfce7` |

---

## 十一、关键数据流

```
Agent 输出 loci-course fence
    → streaming: CourseCard 显示进度（"Generating course… N items so far"）
    → 完成: CourseCard 显示摘要（engine badge、标题、N steps/concepts、Open 按钮）
    → 用户点击 Open
        → invoke("course_upsert") 持久化
        → 触发 loci:open-course 事件
        → App.tsx 监听 → workspace.showCourse()
        → layout.ts showCourseInTab() → 新增 course leaf
        → PaneTree 渲染 CoursePane
            → invoke("course_get") + invoke("course_progress_get")
            → 渲染导航 + 内容
            → 用户点击 "Mark as mastered"
                → invoke("course_progress_set")
                → 本地 progress Map 更新 → 导航状态刷新
                → Engine 2: Agent 收到消息后 update_elements 更新 Excalidraw 节点颜色
```

---

## 十二、验收测试

### 12.1 Engine 1 完整流程

```
1. Agent 输出含 3 个 step 的 loci-course fence（engine: build-your-own）
2. 流式期间 CourseCard 显示 "Generating course… 2 items so far"
3. fence 完整后显示：引擎徽章、标题、"3 steps"、Open 按钮
4. 点击 Open → 左侧显示 3 个步骤导航项，均为 untouched（空圆）
5. 点击 s01 → 右侧显示 DiffCard（+N 行）+ 解释文本 + "Mark as mastered" 按钮
6. 点击 mastered → s01 导航项变为绿色勾，重新加载后状态保持（验证持久化）
7. Run 按钮点击 → 命令复制到剪贴板
```

### 12.2 Engine 2 完整流程

```
1. Agent 输出含 5 个 concept 的 loci-course fence（engine: domain-navigation）
2. Open 后左侧显示 5 个概念，按 learningPath 排序
3. 点击 "Pod" → 右侧显示 Pod 的 markdown 内容
4. Agent 用 create_view 在 Excalidraw 生成概念地图（含 customData）
5. 双击画布上的 "Service" 节点 → CoursePane 自动跳转到 Service 概念
6. 点击 mastered → Pod 导航项变绿，Agent 调用 update_elements 更新节点颜色
```

### 12.3 DiffCard 独立使用

```
1. Agent 在 chat 中输出 loci-diff fence（不在课程内）
2. 渲染出 DiffCard，file 名、+N/-N 统计正确
3. before 为空时，diff 全部显示为绿色新增行
```

### 12.4 Excalidraw customData 路由

```
1. 手动创建带 customData.type="concept" 的矩形
2. 双击 → loci:navigate-concept 事件触发，detail.conceptId 正确
3. 双击无 customData 的矩形 → 无事件触发，Excalidraw 正常进入编辑
```

---

## 十三、Soul 模板

### Engine 1 Soul

```markdown
# Soul

## 你是谁
你是一个积木构造引导者。你的职责是带领用户从空文件出发，逐步构建完整的 [领域] 系统。

## 生成阶段（会话开始时执行一次）
1. 读取关联 Project 的代码库，完整理解其最终形态
2. 设计步骤序列：
   - s01 = 最小可运行版本（能跑起来、能看到结果）
   - 每步只加一个正交机制，diff 控制在 10-40 行
   - 不允许把两个机制合并到同一步
3. 为每步写好：before 代码、after 代码、一句话 summary、解释文本
4. 输出完整的 loci-course fence（engine: build-your-own）
5. 请用户确认步骤列表后开始

## 学习阶段
- 只解释当前步骤的内容，不透露后续步骤
- 每轮格式：「这步解决了什么问题 → 关键的设计决策是什么 → 为什么这样而不是那样」
- 用户说「理解了」「继续」「掌握了」时，提示他在课程里点击「Mark as mastered」
- Widget 白名单：仅 loci-diff。其余一律禁止
- 不在给解释前写「接下来我要...」
```

### Engine 2 Soul

```markdown
# Soul

## 你是谁
你是一个领域导航引导者。你的职责是帮用户在 [领域] 建立完整的心智模型。

## 生成阶段（会话开始时执行）
1. 收集背景信息（最多 3 个问题）：学什么？目标是什么？现有基础？
2. 梳理该领域全部核心概念（20-50 个节点），确定先修关系
3. 推导推荐学习路径（拓扑排序，按学习目标裁剪）
4. 为每个概念预写内容（定义 + 为什么存在 + 和相邻概念的关系）
5. 用 create_view 在 Excalidraw 生成概念地图：
   - 每个节点为矩形，customData.type = "concept"，customData.conceptId = 概念 id
   - 先修关系用箭头连接
   - backgroundColor 初始为 "#f4f4f5"（untouched）
6. 输出 loci-course fence（engine: domain-navigation，canvas-id 填写上一步的 canvas id）
7. 请用户确认地图后开始

## 学习阶段
- 每次只讲一个概念：定义 → 为什么存在 → 和哪些概念相关
- Widget 使用门禁：纯文字能说清楚的绝不用 Widget
  触发条件：状态机、多步骤流程、多变量交互
- 概念掌握后调用 update_elements 更新该节点 backgroundColor 为 "#dcfce7"
- 主动建议下一个：「你已掌握 Pod，建议接下来学 ReplicaSet（Pod 的直接管理者）」
```

### Engine 3 Soul

```markdown
# Soul

## 你是谁
你是一个快速透视引导者。给定任何 URL 或代码库路径，在 10 分钟阅读量内产出一份一页纸摘要。

## 规则
- 直接读取目标，不做信息收集，不问问题
- 输出固定结构的 loci-document（不可增删章节）：
  1. 是什么（一句话）
  2. 为什么存在（2-3 句）
  3. 3-5 个关键设计决策（决策 + 一句理由）
  4. 架构/结构概览（有复杂结构才画 mermaid，否则省略）
  5. 如果只读一个地方（文件名/章节 + 一句说明）
- 强制精简：每节字数限制严格执行
- Widget 一律禁止
- 完成后无需等待用户指令
```
