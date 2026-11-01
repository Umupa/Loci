import { describe, expect, it } from "vitest";
import type { Block, ToolPreview } from "./session";
import { activityEntry, turnActivity } from "./turnProgress";

const app = "/Applications/Loci.app/Contents/MacOS/loci";

function tool(
  id: string,
  options: {
    text?: string;
    kind?: string;
    title?: string;
    status?: string;
    detail?: string;
    preview?: ToolPreview;
  } = {},
): Block {
  const title = options.title ?? options.text ?? id;
  return {
    id,
    role: "tool",
    text: options.text ?? title,
    tool: {
      kind: options.kind ?? "other",
      title,
      status: options.status ?? "completed",
      ...(options.detail ? { detail: options.detail } : {}),
      ...(options.preview ? { preview: options.preview } : {}),
    },
  };
}

function shell(id: string, command: string, status = "completed", detail?: string): Block {
  return tool(id, {
    text: command,
    kind: "execute",
    title: command,
    status,
    ...(detail ? { detail } : {}),
  });
}

const cases: {
  name: string;
  block: Block;
  expect: ReturnType<typeof activityEntry>;
}[] = [
  {
    name: "a saved source names its title",
    block: shell(
      "source",
      `${app} app documents.write --id virtio --title 'Virtio 1.2 — Virtqueues' --path /tmp/virtio.md --source-url https://docs.oasis-open.org/virtio/virtio/v1.2/virtio.html`,
    ),
    expect: {
      id: "source",
      kind: "source",
      status: "done",
      text: "Saved source: Virtio 1.2 — Virtqueues",
      saved: { kind: "source", id: "virtio", title: "Virtio 1.2 — Virtqueues" },
    },
  },
  {
    name: "a source still being saved reads as work in progress",
    block: shell(
      "source",
      `${app} app documents.write --id virtio --title 'Virtio 1.2 — Virtqueues' --path /tmp/virtio.md --source-url https://example.com`,
      "in_progress",
    ),
    expect: {
      id: "source",
      kind: "source",
      status: "running",
      text: "Saving source: Virtio 1.2 — Virtqueues",
    },
  },
  {
    name: "a saved guide comes from its result",
    block: shell(
      "guide",
      `${app} app guides.write --id k8s-guide --path /tmp/guide.md`,
      "completed",
      'Command output:\n{"id":"k8s-guide","title":"How to read the scheduler docs","kind":"guide","saved":true}',
    ),
    expect: {
      id: "guide",
      kind: "guide",
      status: "done",
      text: "Saved guide: How to read the scheduler docs",
      saved: { kind: "guide", id: "k8s-guide", title: "How to read the scheduler docs" },
    },
  },
  {
    name: "a course counts the lessons it has so far",
    block: shell(
      "course",
      `${app} app courses.write --id sandbox --title 'Sandbox runtimes' --chapters '[{"title":"A","lessons":[{},{}]},{"title":"B","lessons":[{},{}]}]'`,
      "in_progress",
    ),
    expect: {
      id: "course",
      kind: "course",
      status: "running",
      text: "Writing course: Sandbox runtimes (4 lessons so far)",
    },
  },
  {
    name: "a completed course counts the lessons it saved",
    block: shell(
      "course",
      `${app} app courses.write --id sandbox --title 'Sandbox runtimes' --input /tmp/course.json`,
      "completed",
      '{"id":"sandbox","title":"Sandbox runtimes","engine":"reading","items":6,"saved":true}',
    ),
    expect: {
      id: "course",
      kind: "course",
      status: "done",
      text: "Wrote course: Sandbox runtimes (6 lessons)",
      saved: { kind: "course", id: "sandbox", title: "Sandbox runtimes" },
    },
  },
  {
    name: "a saved note names its title",
    block: shell(
      "note",
      `${app} app notes.write --title Snapshots --body-file /tmp/note.md`,
      "completed",
      '{"id":"app-a1-r1","title":"Snapshots","saved":true}',
    ),
    expect: {
      id: "note",
      kind: "note",
      status: "done",
      text: "Saved note: Snapshots",
      saved: { kind: "note", id: "app-a1-r1", title: "Snapshots" },
    },
  },
  {
    name: "a clone names the repository, not its checkout path",
    block: shell("clone", "git clone --depth 1 https://github.com/tokio-rs/tokio.git ~/Loci/repos/tokio-rs/tokio", "in_progress"),
    expect: { id: "clone", kind: "clone", status: "running", text: "Cloning tokio-rs/tokio" },
  },
  {
    name: "a finished clone is past tense",
    block: shell("clone", "git clone git@github.com:tokio-rs/tokio.git", "completed"),
    expect: { id: "clone", kind: "clone", status: "done", text: "Cloned tokio-rs/tokio" },
  },
  {
    name: "clones through a provider's shell wrapper",
    block: shell(
      "clone",
      `/bin/zsh -lc "git clone --depth 1 https://github.com/tokio-rs/tokio.git"`,
      "completed",
    ),
    expect: { id: "clone", kind: "clone", status: "done", text: "Cloned tokio-rs/tokio" },
  },
  {
    name: "clones from a chained workdir command and stops before its pipe",
    block: shell(
      "clone",
      "cd /tmp/work && git clone --depth 1 https://github.com/tokio-rs/tokio.git repos/tokio 2>&1 | tail -5",
      "completed",
    ),
    expect: { id: "clone", kind: "clone", status: "done", text: "Cloned tokio-rs/tokio" },
  },
  {
    name: "reads an app action through a provider's shell wrapper",
    block: shell(
      "source",
      `/bin/zsh -lc "${app} app documents.write --id virtio --title 'Virtio 1.2' --path /tmp/v.md --source-url https://example.com"`,
      "completed",
    ),
    expect: {
      id: "source",
      kind: "source",
      status: "done",
      text: "Saved source: Virtio 1.2",
      saved: { kind: "source", id: "virtio", title: "Virtio 1.2" },
    },
  },
  {
    name: "a web fetch names the page",
    block: tool("fetch", {
      text: "WebFetch",
      kind: "fetch",
      title: "Fetch https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/",
      status: "in_progress",
    }),
    expect: {
      id: "fetch",
      kind: "fetch",
      status: "running",
      text: "Fetching kubernetes.io/docs/concepts/workloads/pods/…",
    },
  },
  {
    name: "a shell download names the page it fetches",
    block: shell(
      "curl",
      "cd /tmp/work && rtk curl -sSL https://tokio.rs/tokio/tutorial -o tutorial.html",
      "completed",
    ),
    expect: { id: "curl", kind: "fetch", status: "done", text: "Fetched tokio.rs/tokio/tutorial" },
  },
  {
    name: "a provider's read-shaped preview does not turn a command into a file read",
    block: tool("curl", {
      text: "cd /tmp/work && rtk curl -sSL https://tokio.rs/tokio/tutorial -o tutorial.html",
      kind: "execute",
      title: "cd /tmp/work && rtk curl -sSL https://tokio.rs/tokio/tutorial -o tutorial.html",
      status: "in_progress",
      preview: {
        kind: "read",
        title: "run_terminal_command",
        path: "cd /tmp/work && rtk curl -sSL https://tokio.rs/tokio/tutorial -o tutorial.html",
      },
    }),
    expect: {
      id: "curl",
      kind: "fetch",
      status: "running",
      text: "Fetching tokio.rs/tokio/tutorial",
    },
  },
  {
    name: "reads an app action that Grok hides behind a terminal label",
    block: tool("source", {
      text: "Run Terminal Command",
      kind: "execute",
      title: "Run Terminal Command",
      status: "completed",
      preview: {
        kind: "read",
        title: "run_terminal_command",
        path: `${app} app documents.write --json '{"id":"example-source","title":"Example source","path":"/tmp/example.md","sourceUrl":"https://example.com/example"}'`,
      },
      detail: '{"ok":true,"result":{"id":"example-source","kind":"source","saved":true,"title":"Example source"}}',
    }),
    expect: {
      id: "source",
      kind: "source",
      status: "done",
      text: "Saved source: Example source",
      saved: { kind: "source", id: "example-source", title: "Example source" },
    },
  },
  {
    name: "reads a guide written with one JSON object",
    block: tool("guide", {
      text: "Run Terminal Command",
      kind: "execute",
      title: "Run Terminal Command",
      status: "completed",
      preview: {
        kind: "read",
        title: "run_terminal_command",
        path: `${app} app guides.write --json '{"id":"example-guide","title":"Example guide","body":"# Example guide"}'`,
      },
      detail: '{"ok":true,"result":{"id":"example-guide","kind":"guide","saved":true,"title":"Example guide"}}',
    }),
    expect: {
      id: "guide",
      kind: "guide",
      status: "done",
      text: "Saved guide: Example guide",
      saved: { kind: "guide", id: "example-guide", title: "Example guide" },
    },
  },
  {
    name: "reads an app action after a chained cd, even when its JSON holds separators",
    block: tool("source", {
      text: "Run Terminal Command",
      kind: "execute",
      title: "Run Terminal Command",
      status: "completed",
      preview: {
        kind: "read",
        title: "run_terminal_command",
        path: `cd /tmp/work && '${app}' app documents.write --json '{"id":"example-source-3","title":"A; B && C","path":"/tmp/example.md","sourceUrl":"https://example.com/third"}'`,
      },
    }),
    expect: {
      id: "source",
      kind: "source",
      status: "done",
      text: "Saved source: A; B && C",
      saved: { kind: "source", id: "example-source-3", title: "A; B && C" },
    },
  },
  {
    name: "names a command Grok hides behind a terminal label",
    block: tool("run", {
      text: "Run Terminal Command",
      kind: "execute",
      title: "Run Terminal Command",
      status: "completed",
      preview: {
        kind: "read",
        title: "run_terminal_command",
        path: "cd /tmp/work && cargo test --quiet",
      },
    }),
    expect: {
      id: "run",
      kind: "run",
      status: "done",
      text: "Ran cd /tmp/work && cargo test --quiet",
    },
  },
  {
    name: "a web search says what it looks for",
    block: tool("web", {
      text: "WebSearch",
      kind: "search",
      title: "WebSearch virtio virtqueue split ring",
      status: "completed",
    }),
    expect: {
      id: "web",
      kind: "search",
      status: "done",
      text: "Searched the web for virtio virtqueue split ring",
    },
  },
  {
    name: "a file read names the file",
    block: tool("read", {
      text: "Read src/app/main.rs",
      kind: "read",
      title: "Read src/app/main.rs",
      status: "in_progress",
      preview: { kind: "read", path: "/work/src/app/main.rs", fileName: "main.rs" },
    }),
    expect: { id: "read", kind: "read", status: "running", text: "Reading main.rs" },
  },
  {
    name: "a file write is past tense once it lands",
    block: tool("write", {
      text: "Edit src/flags.rs",
      kind: "edit",
      title: "Edit src/flags.rs",
      status: "completed",
      preview: { kind: "write", path: "/work/src/flags.rs", fileName: "flags.rs" },
    }),
    expect: { id: "write", kind: "write", status: "done", text: "Wrote flags.rs" },
  },
  {
    name: "a project search names its query",
    block: tool("find", {
      text: "Find virtqueue",
      kind: "search",
      title: "Find virtqueue",
      status: "completed",
      preview: { kind: "search", query: "virtqueue" },
    }),
    expect: { id: "find", kind: "search", status: "done", text: "Searched for virtqueue" },
  },
  {
    name: "an unrecognised command still says what ran",
    block: shell("run", "cargo test --quiet", "in_progress"),
    expect: { id: "run", kind: "run", status: "running", text: "Running cargo test --quiet" },
  },
  {
    name: "a failed save says it could not save",
    block: shell(
      "source",
      `${app} app documents.write --id virtio --title 'Virtio 1.2' --path /tmp/virtio.md --source-url https://example.com`,
      "failed",
    ),
    expect: {
      id: "source",
      kind: "source",
      status: "failed",
      text: "Couldn't save source: Virtio 1.2",
    },
  },
];

describe("activityEntry", () => {
  for (const entry of cases) {
    it(entry.name, () => {
      expect(activityEntry(entry.block)).toEqual(entry.expect);
    });
  }

  it("ignores provider todo calls", () => {
    expect(
      activityEntry(
        tool("todo", { text: "Update TODOs", kind: "tasks", status: "completed" }),
      ),
    ).toBeUndefined();
  });
});

describe("turnActivity", () => {
  it("lists the running turn newest first and leaves earlier turns alone", () => {
    const blocks: Block[] = [
      { id: "u1", role: "user", text: "first" },
      shell("old", "git clone https://github.com/old/repo.git"),
      { id: "u2", role: "user", text: "second" },
      shell(
        "source",
        `${app} app documents.write --id virtio --title 'Virtio 1.2' --path /tmp/v.md --source-url https://example.com`,
      ),
      tool("read", {
        text: "Read src/lib.rs",
        kind: "read",
        title: "Read src/lib.rs",
        status: "in_progress",
        preview: { kind: "read", path: "/work/src/lib.rs" },
      }),
    ];
    expect(turnActivity(blocks).map((entry) => entry.text)).toEqual([
      "Reading lib.rs",
      "Saved source: Virtio 1.2",
    ]);
  });

  it("keeps the newest update of one call and drops older copies", () => {
    const running = shell("call", "cargo build", "in_progress");
    running.tool!.callId = "call-1";
    const done = shell("call", "cargo build", "completed");
    done.tool!.callId = "call-1";
    expect(turnActivity([running, done]).map((entry) => entry.text)).toEqual([
      "Ran cargo build",
    ]);
  });
});
