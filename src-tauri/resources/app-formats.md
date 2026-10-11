# Loci reply formats

These fenced Markdown blocks render as cards in Loci. They describe supported
formats, without prescribing when to use them. Questions use the three-backtick
fence shown below. Other formats accept three or more backticks; their closing
fence has at least as many backticks as the opening fence. Four backticks allow
a document to contain ordinary code fences.

## Question

```loci-question
{"questions":[{"id":"path","header":"Reading path","question":"Which path?","multiSelect":false,"allowCustom":true,"options":[{"id":"core","label":"Core path","description":"Read the core topics"},{"id":"panorama","label":"Panorama","description":"Read across the field"}]}]}
```

The body is JSON. A question has `question`, optional `id` and `header`,
`multiSelect`, `allowCustom`, and an `options` array of `label` plus optional
`id` and `description`. Question and option IDs are generated when omitted.
`multiSelect` defaults to false. With the `question` field, custom answers are
allowed by default. Choices arrive as the user's next message.

## Document

````loci-document
---
id: reading-plan
title: Reading plan
subject: Kubernetes
---
# Reading plan

Markdown content, including code, tables, and links.
````

`id`, `title`, and `subject` are front matter fields. Without front matter,
the first heading supplies the title and a document ID is derived from it.
In an agent chat, the document is saved in that agent's library. A complete
document with the same ID replaces the earlier document. Imported source
documents are updated through `documents.write`, not reply blocks.

## Checklist

```loci-todo
# Reading steps
- [x] Read the introduction
- [ ] Read the design document
```

The body is a Markdown task list with an optional heading. Ticking a task
submits `Done: <task>` as the user's next message. Checklist state belongs
to the message and is not stored as a course.

## Mind map

```loci-mindmap
# Workloads
- Pods
  - Lifecycle
  - Scheduling
```

The body is a Markdown outline. Its heading names the root and indented
bullets become child nodes in a collapsible tree.

## Reading course

Courses belong to an agent's library. Save one with the `courses.write`
action, then point at it from a reply with a fence that has front matter and
no body:

```loci-course
---
id: kubernetes-reading
title: Kubernetes reading
---
```

The `courses.write` input is one object:

```json
{"id":"kubernetes-reading","title":"Kubernetes reading","engine":"reading","chapters":[{"title":"Workloads","lessons":[{"id":"pod-lifecycle","title":"Pod Lifecycle","document":"k8s-pod-lifecycle","section":"Pod phase"},{"id":"borg","title":"Borg","file":"/absolute/path/borg.pdf","pages":[1,12]}]}]}
```

`id` and `title` are required; `engine` defaults to `reading`.
Chapters and lessons are non-empty arrays. Each lesson has a unique `id`,
`title`, and exactly one of `document` (an imported document ID) or `file`
(an absolute path). `section` belongs to a document; `pages: [first, last]`
belongs to a file and uses positive, inclusive page numbers. A course can
link a canvas through optional `canvasId`. Updating the same course ID retains
progress for lesson IDs that remain in the course. A fence that still carries
the JSON body after its front matter is shown as a preview; Open saves it.

The `build-your-own` engine uses `{"steps":[...]}`. Each step has a unique
`id`, `title`, `summary`, `file`, `before`, `after`, `explanation`, and optional
`runCommand`; `before`, `after`, and `explanation` may be empty strings.

## Diff

```loci-diff
---
id: example-change
title: Example change
file: src/example.ts
---
=== BEFORE ===
export const answer = 41;
=== AFTER ===
export const answer = 42;
```

`id` and `title` are required; `file` and `run` are optional. Exactly one
`=== BEFORE ===` delimiter precedes exactly one `=== AFTER ===` delimiter.
Section content is preserved verbatim. `(empty file)` as the entire BEFORE
section represents an empty file. This block displays a change; it does not
apply it to disk.

## Widget

````loci-widget
---
id: counter
title: Counter
subject: Examples
---
<button id="increment">Increment</button>
<output id="value"></output>
<script>
const output = document.getElementById("value");
const render = () => { output.textContent = window.loci.getState().count ?? 0; };
document.getElementById("increment").onclick = () => {
  window.loci.setState({ count: (window.loci.getState().count ?? 0) + 1 });
};
window.loci.onState(render);
render();
</script>
````

`id` and `title` are required. `subject` is optional. Optional `sources` is a
JSON array or comma-separated list of existing learning source IDs. The body
is HTML with optional inline CSS, SVG, and JavaScript, limited to 1 MiB. It
runs in an isolated iframe; network access, external scripts, and external
stylesheets are unavailable. Images can use data URLs.

The runtime provides `window.loci.getState()`, `setState(value)`,
`onState(listener)`, `theme`, `onTheme(listener)`, `ask(text)`,
`openSource(id)`, and `resize(height)`. State is JSON, limited to 64 KiB;
`openSource` accepts the widget's declared source IDs. `ask` prefills a chat
message with current widget context; it does not submit a message. Widgets
remain in their conversation; Keep saves the widget and its interaction state.

## Canvas

```loci-canvas
id: existing-canvas-id
title: System overview
```

The block links to an existing canvas. It does not create or change a scene.
Canvas creation and editing are available through the canvas tools and app
CLI actions listed above.
