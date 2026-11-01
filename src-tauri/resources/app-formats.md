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
In an agent chat, the document is saved in that agent's library as a
**guide**: the agent's own writing. A complete document with the same ID
replaces the earlier document.

A library holds two kinds, and `documents.list` reports each one's `kind`:

- **source**: text someone else published (docs, a spec, a paper, a README),
  taken in verbatim from a saved file with `documents.write` and its
  `sourceUrl`. A source changes only by taking its file in again.
- **guide**: what the agent wrote itself (a reading guide, a brief, a map of
  the material), saved with `guides.write` (`path` to a Markdown file, or
  `body`) or a `loci-document` block. It has no `sourceUrl` and the user sees
  it labelled "Mentor's guide", listed after the sources.

Never save your own summary as a source. A guide and a source never share an
ID: writing one kind over the other is refused.

## Notes

Use `notes.write` for editable personal notes. A note created in an agent
conversation belongs to that agent and appears under Notes in its library.
Its returned `loci://note/<id>` link opens the note. Documents
can also be saved as notes from their reader.

## Citing what the learner reads

Each turn carries `<reading_now>`: what the reader beside the chat shows and,
in `place`, where the learner is in it: `section` (the headings above the
visible paragraph), `paragraph` (its first words), `page` or `lines`, and
`selection`, the text the learner selected there. "This" and "here" usually
mean the selection, else the paragraph. `"selection":"attached"` means the
selection is already in the message as a source.

Link to an exact place in a source so the learner can jump there: the link
opens the source in the reader, scrolls to the place and flashes it.

```text
[Pod phase](loci://source/k8s-pod-lifecycle#section=Pod%20phase)
[the Pending state](loci://source/k8s-pod-lifecycle#section=Pod%20phase&quote=The%20Pod%20has%20been%20accepted)
[page 7](loci://source/<id>#p7)        [lines 12-40](loci://source/<id>#L12-40)
```

- The id is a document ID from the library (the same one `reader.open` takes
  as `source`), or a source ID from `<loci_learning_context>`.
- `section` is a heading's visible title. `quote` is a short passage of at
  most 200 characters, copied verbatim from the source; it is found even if
  white space or case differ. Percent-encode both (a space is `%20`).
- Join parts with `&`; each appears at most once. A link with any other part
  is not a link.
- If the quote is no longer in the document, the reader shows the section and
  says the passage changed.

File links take the same passage after their lines:
`loci://file/<id>#L12-40&quote=fn%20main`.

A Markdown link to a local path opens the file in the reader, at the place
its fragment names: lines `#L12-40` (or `#L12-L40`), or a PDF page `#p7`.

```text
[worker.rs:571-646](/abs/path/worker.rs#L571-646)
[page 7 of the paper](/abs/path/paper.pdf#p7)
```

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

Courses appear in the owning mentor's library under Courses. They open in its
reader, with the course outline in the library column. Save one with the `courses.write`
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
(an absolute path, or a path in your folder such as `repos/…`). `section` belongs to a document; `pages: [first, last]`
belongs to a file and uses positive, inclusive page numbers. A source or text
file is shown in place, highlighted; `lines: [first, last]` (inclusive) shows
only that range, which suits a code tour through a cloned repository. Name
`pages` or `lines`, not both. Use a Markdown
heading's visible title for `section`: the reader focuses on that heading and
its descendants, stopping before the next heading of the same or higher level.
Omit `section` or leave it blank to
read the whole document; an unmatched title shows the full document.
A course can
link a canvas through optional `canvasId`. Updating the same course ID retains
progress for lesson IDs that remain in the course. A fence that still carries
the JSON body after its front matter is shown as a preview; Open saves it.

### Code-tour lessons

A code-tour lesson reads lines of a file in a cloned repository, pinned to
the commit you read: `"file": "repos/<owner>/<repo>@<sha>:path/in/repo#L40-88"`
(or `file` plus `"commit": "<sha>"` and `lines`). Loci shows the file as it
was at that commit, and tells the learner when the repository has moved past
it and the file changed, with the current file one click away. Always pin
code lessons:

- `code.pin` with `file` (`repos/<owner>/<repo>/path`) and `lines` gives the
  exact string for `file` (HEAD's full commit) and the numbered excerpt;
- `code.read` shows numbered lines at a pin, to check what a lesson shows;
- `code.symbols` lists a file's definitions with their lines, and
  `code.definition` / `code.references` find where a name is defined or
  used (Go, Rust, C, TypeScript, JavaScript, Python; matched by name), so a
  tour can follow the real call path;
- `code.pins` lists pinned lessons whose file changed since their commit,
  with where the lines are now, so you can refresh them.

A short commit is expanded when the course is saved; a commit the clone does
not have is refused (fetch it first). In the reader the learner can open the
whole file, see its symbols, and ⌘-click a name to go to its definition.

### Comparison lessons

When several projects (or a project and its spec) implement the same
mechanism — creating a sandbox, snapshot and restore, a virtqueue — one
lesson can put them side by side. A comparison lesson has no `document` or
`file` of its own; it lists 2–4 parts in `compare`, read one under another on
one page:

```json
{"id":"restore-compared","title":"Restoring a sandbox, three ways","compare":[
  {"label":"CubeSandbox","file":"repos/tencentcloud/cubesandbox@<sha>:cubelet/restore.go#L40-88","note":"Reads the memory file before it starts the VM."},
  {"label":"E2B","file":"repos/e2b-dev/infra@<sha>:packages/orchestrator/internal/sandbox/sandbox.go#L120-170"},
  {"label":"Firecracker spec","document":"firecracker-snapshots","section":"Loading snapshots"}
]}
```

- Each part is a file's `lines` (paste the `ref` from `code.pin` as `file`;
  pinned parts get the same notices as a code-tour lesson) or a source's
  `section`, as a lesson of its own would name them.
- `label` is short (at most 60 characters), unique in the lesson: the
  project's name, or what the part is.
- `note` is optional: one or two sentences of yours on what to look at in this
  part. It is shown as the mentor's note, apart from the source text.
- Compare one mechanism at the same depth in each part: the matching
  function, not a whole file. Pin every code part.
- `<reading_now>` names the comparison's parts, and `place.part` the part the
  learner is reading.

### Learning path

A broad goal is a path of 3–5 short courses (6–12 lessons each), in order.
Write it with `path.write`:

```json
{"title":"Sandboxes from the source","courses":[{"id":"sandbox-foundations"},{"id":"cube-internals","after":["sandbox-foundations"]},{"id":"snapshots-compared","title":"Snapshot and restore, three ways","after":["cube-internals"]}]}
```

`courses` lists course ids in reading order; `after` names earlier courses
the learner may want first. It is a hint shown in the library, never a lock:
every course stays open. A course may be on the path before it is written;
give it a `title` until then. `path.read` returns the path with how far each
course is read. The path is the file `courses/_path.yaml`; `_path` is never a
course id.

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

## Canvas

```loci-canvas
id: existing-canvas-id
title: System overview
```

The block links to an existing canvas. It does not create or change a scene.
Canvas creation and editing are available through the canvas tools and app
CLI actions listed above.

# Your folder

A mentor's library is a folder of files (`<agent>.folder`, such as
`~/Loci/kubernetes-guide/`). Saving through the commands above writes these
files; you may also create or edit them directly, and Loci shows the change.
Run `library check` afterwards to see any file it could not read.

```text
mentor.json               who you are; leave it to Loci
SOUL.md  MEMORY.md  memory/   change only with soul.* and memory.*
sources/<id>.md           first-hand text, verbatim, with front-matter
guides/<id>.md            what you wrote: reading guides, briefs
courses/<id>.yaml         courses
courses/_path.yaml        the learning path (path.write)
notes/<id>.md             notes
canvases/<id>.excalidraw  drawings (Excalidraw files)
repos/  lab/              cloned source and experiments; not indexed
```

An `<id>` uses letters, digits, `-` and `_` (courses, notes and drawings:
ASCII only). A source and a guide never share an id. Files whose names
start with a dot or end in `~`, `.tmp` or `.swp` are ignored.

A source starts with YAML front-matter; the text after it is kept byte for
byte:

```markdown
---
title: Virtio 1.2 — Virtqueues
sourceUrl: https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html
version: "1.2"
fetchedAt: 2026-11-01T09:12:00Z
subject: virtio
---
```

`title` and `sourceUrl` are required for a source; `version` (a release or a
commit), `fetchedAt` and `subject` are optional. A guide has `title` and an
optional `subject`, never `sourceUrl`. Without a title, the first `# Heading`
is used.

A course file is the `courses.write` object as YAML, without its `id` (the
file name is the id). A lesson's `file` may be relative to your folder, and
`document: id#section`, `file: path#L12-40` and `file: path#p7-9` are
shorthands for `section`, `lines` and `pages`:

```yaml
schemaVersion: 1
title: Sandboxes from the kernel up
engine: reading
chapters:
  - title: KVM
    lessons:
      - id: kvm-api
        title: The KVM API
        document: kvm-api#4.1 KVM_CREATE_VM
      - id: vmm-loop
        title: The VMM loop in Firecracker
        file: repos/firecracker-microvm/firecracker@3f2a9c1e5b7d4e6f8a9b0c1d2e3f4a5b6c7d8e9f:src/vmm/src/lib.rs#L120-188
```

`repos/<repo>@<sha>:path` pins a code lesson to a commit (see Code-tour
lessons); Loci writes pinned lessons back in this form.

A note has front-matter `title`, optional `tags: [a, b]`, and its Markdown.

