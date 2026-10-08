// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invalidateNotes, loadNotes, NOTES_CHANGED_EVENT, type Note, type NoteUpsert } from "../notes";
import { NotesView, type NoteOpenRequest } from "./NotesView";
import { savePinnedProjects, saveProjectRailOrder } from "../../projects/model/recents";

const invoke = vi.hoisted(() => vi.fn());
vi.mock("@tauri-apps/api/core", async (original) => ({
  ...(await original<typeof import("@tauri-apps/api/core")>()),
  invoke,
}));
vi.mock("@tauri-apps/api/webview", () => ({
  getCurrentWebview: () => ({ onDragDropEvent: async () => () => {} }),
}));
vi.mock("@tauri-apps/api/window", () => ({
  getCurrentWindow: () => ({
    isMaximized: async () => false,
    onResized: async () => () => {},
  }),
}));

let root: Root;
let container: HTMLDivElement;
let stored: Note;
let onClose: ReturnType<typeof vi.fn>;
const recents = [
  { path: "/work/Edefyn", openedAt: 2 },
  { path: "/work/portognjeeen", openedAt: 1 },
];

beforeEach(() => {
  invalidateNotes();
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  const storage = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => storage.get(key) ?? null,
    setItem: (key: string, value: string) => storage.set(key, value),
    removeItem: (key: string) => storage.delete(key),
  });
  stored = {
    id: "note-project-test",
    slug: "plan",
    title: "Plan",
    body: "Keep this text.",
    tags: ["ideas"],
    sourceCwd: "/work/Edefyn",
    sourceSessionId: "original-session",
    slugPending: false,
    createdAt: 1,
    updatedAt: 1,
  };
  invoke.mockReset();
  invoke.mockImplementation(
    async (command: string, args?: { note: NoteUpsert }) => {
      if (command === "notes_list") return [{ ...stored }];
      if (command === "notes_upsert") {
        stored = { ...stored, ...args!.note, updatedAt: stored.updatedAt + 1 };
        return { ...stored };
      }
      throw new Error(`Unexpected command: ${command}`);
    },
  );
  onClose = vi.fn();
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

async function render(projects = recents, cwd = "/work/Edefyn", openRequest?: NoteOpenRequest) {
  await act(async () =>
    root.render(
      createElement(NotesView, {
        cwd,
        recents: projects,
        onClose,
        openRequest,
      }),
    ),
  );
}

it("opens the requested note in its own scope and clears existing filters on repeated requests", async () => {
  const target = { ...stored, id: "target", title: "Linked note", sourceCwd: "/work/portognjeeen" };
  invoke.mockImplementation(async (command, args) => {
    if (command === "notes_list") return [stored, target];
    if (command === "notes_get") return args.id === target.id ? target : stored;
    throw new Error(`Unexpected command: ${command}`);
  });
  await render();
  await act(async () => inputText(container.querySelector<HTMLInputElement>('[aria-label="Filter notes"]')!, "Hidden"));
  await render(recents, "/work/Edefyn", { id: "target", sequence: 1 });
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe("Linked note");
  expect(noteRows()).toHaveLength(1);
  expect(container.querySelector<HTMLInputElement>('[aria-label="Filter notes"]')?.value).toBe("");
  await act(async () => container.querySelector<HTMLButtonElement>('[aria-label="Filter by time"]')!.click());
  await act(async () => [...document.querySelectorAll<HTMLElement>('[role="menuitemcheckbox"]')].find((item) => item.textContent?.includes("Today"))!.click());
  expect(container.textContent).toContain("No matching notes");
  await render(recents, "/work/Edefyn", { id: "target", sequence: 2 });
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe("Linked note");
});

it("opens a global note without applying the chat project's scope", async () => {
  const target = { ...stored, id: "global", title: "Global note", sourceCwd: undefined };
  invoke.mockImplementation(async (command) => command === "notes_get" ? target : [stored, target]);
  await render(recents, "/work/Edefyn", { id: "global", sequence: 1 });
  expect(noteRows()).toHaveLength(2);
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe("Global note");
});

it.each(["deleted", "read failure"])("shows a %s error without displaying another note", async (mode) => {
  invoke.mockImplementation(async (command) => {
    if (command === "notes_list") return [stored];
    if (command === "notes_get") {
      if (mode === "read failure") throw new Error("Cannot read note");
      return null;
    }
  });
  await render(recents, "/work/Edefyn", { id: "missing", sequence: 1 });
  expect(container.querySelector('[role="alert"]')?.textContent).toContain(mode === "deleted" ? "no longer exists" : "Cannot read note");
  expect(container.querySelector('[aria-label="Note title"]')).toBeNull();
  expect(container.querySelector("textarea.markdown-source-field")).toBeNull();
});

it("keeps a newer requested note when the older read finishes last", async () => {
  let finish!: (note: Note) => void;
  const slow = new Promise<Note>((resolve) => { finish = resolve; });
  const newer = { ...stored, id: "newer", title: "Newer note" };
  invoke.mockImplementation(async (command, args) => {
    if (command === "notes_list") return [stored, newer];
    if (command === "notes_get") return args.id === "slow" ? slow : newer;
  });
  await render(recents, "/work/Edefyn", { id: "slow", sequence: 1 });
  expect(container.querySelector('[role="status"]')?.textContent).toContain("Loading note");
  expect(container.querySelector('[aria-label="Note title"]')).toBeNull();
  await render(recents, "/work/Edefyn", { id: "newer", sequence: 2 });
  await act(async () => finish({ ...stored, id: "slow", title: "Old response" }));
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe("Newer note");
});

it.each(["success", "failure"])("keeps a manual selection after a pending link read ends in %s", async (outcome) => {
  const target = { ...stored, id: "target", title: "Target note" };
  let finish!: (note: Note) => void;
  let fail!: (error: Error) => void;
  const pending = new Promise<Note>((resolve, reject) => { finish = resolve; fail = reject; });
  invoke.mockImplementation(async (command) => command === "notes_get" ? pending : [stored, target]);
  await render();
  await render(recents, "/work/Edefyn", { id: target.id, sequence: 1 });
  expect(container.querySelector('[role="status"]')).not.toBeNull();
  await act(async () => [...container.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.title.startsWith("Plan ·"))!.click());
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe("Plan");
  await act(async () => outcome === "success" ? finish(target) : fail(new Error("Late read failure")));
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe("Plan");
  expect(container.querySelector('[role="alert"]')).toBeNull();
});

it("does not let a previous editor's late save change the new linked note's scope", async () => {
  const target = { ...stored, id: "target", title: "Other project note", sourceCwd: "/work/portognjeeen" };
  let finishSave!: () => void;
  const save = new Promise<void>((resolve) => { finishSave = resolve; });
  invoke.mockImplementation(async (command, args) => {
    if (command === "notes_list") return [{ ...stored }, target];
    if (command === "notes_get") return args.id === target.id ? target : { ...stored };
    if (command === "notes_upsert") { await save; stored = { ...stored, ...args.note, updatedAt: 2 }; return { ...stored }; }
  });
  await render(recents, "/work/Edefyn", { id: stored.id, sequence: 1 });
  const title = container.querySelector<HTMLInputElement>('[aria-label="Note title"]')!;
  await act(async () => { title.focus(); inputText(title, "Saved first note"); title.blur(); });
  await render(recents, "/work/Edefyn", { id: target.id, sequence: 2 });
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe(target.title);
  await act(async () => finishSave());
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe(target.title);
  expect(noteRows()).toHaveLength(1);
});

it("uses the newest target's scope when a move completes during a linked read", async () => {
  let finishRead!: (note: Note) => void;
  const stale = { ...stored };
  const pending = new Promise<Note>((resolve) => { finishRead = resolve; });
  invoke.mockImplementation(async (command) => command === "notes_get" ? pending : [{ ...stored }]);
  await render();
  await render(recents, "/work/Edefyn", { id: stored.id, sequence: 1 });
  // Project-only moves deliberately preserve updatedAt in the SQLite store.
  stored = { ...stored, sourceCwd: "/work/portognjeeen" };
  await act(async () => window.dispatchEvent(new Event(NOTES_CHANGED_EVENT)));
  await act(async () => finishRead(stale));
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe("Plan");
  expect(container.querySelector('[aria-label="Move note to project, current project portognjeeen"]')).not.toBeNull();
});

it("retains an editor save completed after the linked note snapshot was read", async () => {
  const stale = { ...stored };
  let finishRead!: (note: Note) => void;
  const pending = new Promise<Note>((resolve) => { finishRead = resolve; });
  invoke.mockImplementation(async (command, args) => {
    if (command === "notes_list") return [{ ...stored }];
    if (command === "notes_get") return pending;
    if (command === "notes_upsert") { stored = { ...stored, ...args.note, updatedAt: 2 }; return { ...stored }; }
  });
  await render();
  await act(async () => inputText(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')!, "Newest saved title"));
  await render(recents, "/work/Edefyn", { id: stored.id, sequence: 1 });
  expect(stored.title).toBe("Newest saved title");
  await act(async () => finishRead(stale));
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe("Newest saved title");
});

it("shows a preloaded note immediately while refreshing in the background", async () => {
  await loadNotes();
  let finish!: (notes: Note[]) => void;
  const refresh = new Promise<Note[]>((resolve) => { finish = resolve; });
  invoke.mockReturnValue(refresh);
  await render();
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value)
    .toBe("Plan");
  expect(container.textContent).toContain("Keep this text.");
  expect(container.textContent).not.toContain("Select a note");
  expect(container.querySelector(".animate-spin")).toBeNull();

  await act(async () => finish([{ ...stored, title: "Updated plan" }]));
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value)
    .toBe("Updated plan");
});

it("refreshes an open note after an Operator write", async () => {
  await render();
  stored = { ...stored, title: "Updated by Operator", body: "New text", updatedAt: 2 };
  await act(async () => window.dispatchEvent(new Event(NOTES_CHANGED_EVENT)));
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value)
    .toBe("Updated by Operator");
  expect(container.textContent).toContain("New text");
});

// Regression 591:
it("keeps a note's consecutive lines on their own lines", async () => {
  stored = { ...stored, body: "> first line\n> second line\n> third line" };
  await render();

  const preview = container.querySelector<HTMLElement>('[data-streamdown="blockquote"]')!;
  expect(preview.querySelector("p")?.innerHTML).toBe(
    "first line<br>second line<br>third line",
  );
});

it("uses the searchable rail project picker when moving a note", async () => {
  const projects = [
    ...recents,
    { path: "/work/Third", openedAt: 3 },
    { path: "/work/Fourth", openedAt: 4 },
    { path: "/work/Fifth", openedAt: 5 },
    { path: "/work/Sixth", openedAt: 6 },
    { path: "/work/Seventh", openedAt: 7 },
    { path: "/work/Active", openedAt: 0 },
  ];
  saveProjectRailOrder([
    "/work/Fourth",
    "/work/Third",
    "/work/Edefyn",
    "/work/portognjeeen",
    "/work/Fifth",
    "/work/Sixth",
    "/work/Seventh",
    "/work/Active",
  ]);
  savePinnedProjects(["/work/Seventh"]);
  await render(projects, "/work/Edefyn");
  await act(async () => projectButton()!.click());
  const menu = document.querySelector('[aria-label="Project picker"]')!;
  const items = [...menu.querySelectorAll<HTMLButtonElement>("button[title]")];
  expect(items.map((item) => item.title)).toEqual([
    "/work/Edefyn",
    "/work/Seventh",
    "/work/Fourth",
    "/work/Third",
    "/work/portognjeeen",
    "/work/Fifth",
    "/work/Sixth",
    "/work/Active",
  ]);
  const search = menu.querySelector<HTMLInputElement>(
    'input[placeholder="Search projects..."]',
  );
  expect(search).not.toBeNull();
  expect(document.activeElement).toBe(search);
  await act(async () => {
    Object.getOwnPropertyDescriptor(
      HTMLInputElement.prototype,
      "value",
    )!.set!.call(search, "active");
    search!.dispatchEvent(new Event("input", { bubbles: true }));
  });
  const filteredItems = [
    ...menu.querySelectorAll<HTMLButtonElement>("button[title]"),
  ];
  expect(filteredItems.map((item) => item.title)).toEqual(["/work/Active"]);
  await act(async () => filteredItems[0]!.click());
  expect(stored.sourceCwd).toBe("/work/Active");
});

function projectButton() {
  return container.querySelector<HTMLButtonElement>(
    'header button[aria-label^="Move note to project"]',
  );
}

async function chooseProject() {
  await render(recents, "~");
  const button = projectButton();
  expect(
    button,
    "The note header should offer a project picker",
  ).not.toBeNull();
  await act(async () => button!.click());
  const item = [
    ...document.querySelectorAll<HTMLButtonElement>(
      '[aria-label="Project picker"] button[title]',
    ),
  ].find((element) => element.title === "/work/portognjeeen");
  expect(item).toBeDefined();
  await act(async () => item!.click());
}

it("moves the existing note and keeps its content when reopened", async () => {
  await render();
  await chooseProject();
  expect(stored).toMatchObject({
    id: "note-project-test",
    slug: "plan",
    title: "Plan",
    body: "Keep this text.",
    tags: ["ideas"],
    sourceCwd: "/work/portognjeeen",
    sourceSessionId: "original-session",
    createdAt: 1,
  });
  expect(projectButton()?.textContent).toContain("portognjeeen");
  expect(
    container.querySelector('li [aria-current="true"]')?.textContent,
  ).toContain("portognjeeen");
  expect(onClose).not.toHaveBeenCalled();
  await act(async () => root.unmount());
  root = createRoot(container);
  await render(recents, stored.sourceCwd);
  expect(projectButton()?.textContent).toContain("portognjeeen");
});

it("closes the project menu with Escape without leaving Notes", async () => {
  await render();
  await act(async () => projectButton()!.click());
  expect(
    document.querySelector('[aria-label="Project picker"]'),
  ).not.toBeNull();
  await act(async () =>
    projectButton()!.dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "Escape",
        bubbles: true,
        cancelable: true,
      }),
    ),
  );
  expect(document.querySelector('[aria-label="Project picker"]')).toBeNull();
  expect(onClose).not.toHaveBeenCalled();
});

it("serializes title edits behind an in-flight project change", async () => {
  await render();
  const save = invoke.getMockImplementation()!;
  let finishMove!: () => void;
  const moving = new Promise<void>((resolve) => {
    finishMove = resolve;
  });
  let inFlight = 0;
  let maximumInFlight = 0;
  invoke.mockImplementation(async (command, args) => {
    if (command !== "notes_upsert") return save(command, args);
    inFlight += 1;
    maximumInFlight = Math.max(maximumInFlight, inFlight);
    if (args.note.title === "Plan") await moving;
    const result = await save(command, args);
    inFlight -= 1;
    return result;
  });
  await chooseProject();
  const title = container.querySelector<HTMLInputElement>(
    '[aria-label="Note title"]',
  )!;
  act(() => title.focus());
  act(() => {
    Object.getOwnPropertyDescriptor(
      HTMLInputElement.prototype,
      "value",
    )!.set!.call(title, "Updated plan");
    title.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await act(async () => title.blur());
  await act(async () => finishMove());
  expect(maximumInFlight).toBe(1);
  expect(stored.title).toBe("Updated plan");
  expect(stored.sourceCwd).toBe("/work/portognjeeen");
});

it("keeps newer edits after reopening a note during a project move", async () => {
  const second = {
    ...stored,
    id: "second-note",
    slug: "second",
    title: "Second",
  };
  const save = invoke.getMockImplementation()!;
  let finishMove!: () => void;
  const moving = new Promise<void>((resolve) => {
    finishMove = resolve;
  });
  let inFlight = 0;
  let maximumInFlight = 0;
  invoke.mockImplementation(async (command, args) => {
    if (command === "notes_list") return [{ ...stored }, { ...second }];
    if (command !== "notes_upsert") return save(command, args);
    inFlight += 1;
    maximumInFlight = Math.max(maximumInFlight, inFlight);
    if (args.note.sourceCwd === "/work/portognjeeen") await moving;
    const result = await save(command, args);
    inFlight -= 1;
    return result;
  });
  const selectNote = async (title: string) => {
    const button = [
      ...container.querySelectorAll<HTMLButtonElement>("li button"),
    ].find((item) => item.textContent?.includes(title));
    expect(button).toBeDefined();
    await act(async () => button!.click());
  };

  await render();
  await chooseProject();
  await selectNote("Second");
  await selectNote("Plan");
  const title = container.querySelector<HTMLInputElement>(
    '[aria-label="Note title"]',
  )!;
  act(() => title.focus());
  act(() => {
    Object.getOwnPropertyDescriptor(
      HTMLInputElement.prototype,
      "value",
    )!.set!.call(title, "Updated after reopening");
    title.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await act(async () => title.blur());
  await act(async () => finishMove());

  expect(stored.title).toBe("Updated after reopening");
  expect(stored.sourceCwd).toBe("/work/portognjeeen");
  expect(maximumInFlight).toBe(1);
  await selectNote("Second");
  await selectNote("Updated after reopening");
  expect(
    container.querySelector<HTMLInputElement>('[aria-label="Note title"]')
      ?.value,
  ).toBe("Updated after reopening");
  expect(projectButton()?.textContent).toContain("portognjeeen");
});

it.each(["title", "body", "tags"] as const)(
  "preserves earlier edits when changing %s after reopening during a move",
  async (field) => {
    vi.useFakeTimers();
    const second = { ...stored, id: "second-note", title: "Second" };
    const save = invoke.getMockImplementation()!;
    let finishMove!: () => void;
    const moving = new Promise<void>((resolve) => {
      finishMove = resolve;
    });
    invoke.mockImplementation(async (command, args) => {
      if (command === "notes_list") return [{ ...stored }, { ...second }];
      if (
        command === "notes_upsert" &&
        args.note.sourceCwd === "/work/portognjeeen"
      )
        await moving;
      return save(command, args);
    });
    const selectNote = async (title: string) => {
      const button = [
        ...container.querySelectorAll<HTMLButtonElement>("li button"),
      ].find((item) => item.textContent?.includes(title));
      expect(button).toBeDefined();
      await act(async () => button!.click());
    };
    const editInput = async (label: string, value: string) => {
      const input = container.querySelector<HTMLInputElement>(
        `[aria-label="${label}"]`,
      )!;
      await act(async () => {
        Object.getOwnPropertyDescriptor(
          HTMLInputElement.prototype,
          "value",
        )!.set!.call(input, value);
        input.dispatchEvent(new Event("input", { bubbles: true }));
      });
    };
    const editBody = async (value: string) => {
      const source = [
        ...container.querySelectorAll<HTMLButtonElement>('[role="tab"]'),
      ].find((button) => button.textContent === "Source")!;
      await act(async () => source.click());
      const input = container.querySelector<HTMLTextAreaElement>(
        "textarea.markdown-source-field",
      )!;
      await act(async () => {
        Object.getOwnPropertyDescriptor(
          HTMLTextAreaElement.prototype,
          "value",
        )!.set!.call(input, value);
        input.dispatchEvent(new Event("input", { bubbles: true }));
      });
    };

    await render();
    await selectNote("Plan");
    await editInput("Note title", "Title before moving");
    await editBody("Content before moving");
    await editInput("Add note tag", "before,");
    await chooseProject();
    await selectNote("Second");
    await selectNote("Plan");
    if (field === "title")
      await editInput("Note title", "Title after reopening");
    if (field === "body") await editBody("Content after reopening");
    if (field === "tags") await editInput("Add note tag", "after,");
    await act(async () => vi.advanceTimersByTime(400));
    // Cover both an open editor and saves finishing after it unmounts.
    if (field !== "title") await selectNote("Second");
    await act(async () => finishMove());

    const expected = {
      title:
        field === "title" ? "Title after reopening" : "Title before moving",
      body:
        field === "body" ? "Content after reopening" : "Content before moving",
      tags: field === "tags" ? ["ideas", "after"] : ["ideas", "before"],
      sourceCwd: "/work/portognjeeen",
    };
    expect(stored).toMatchObject(expected);
    await selectNote(expected.title);
    expect(
      container.querySelector<HTMLInputElement>('[aria-label="Note title"]')
        ?.value,
    ).toBe(expected.title);
    expect(
      container.querySelector<HTMLTextAreaElement>(
        "textarea.markdown-source-field",
      )?.value,
    ).toBe(expected.body);
    expect(
      [...container.querySelectorAll('[aria-label="Tags"] span')].map(
        (tag) => tag.textContent,
      ),
    ).toEqual(expect.arrayContaining(expected.tags.map((tag) => `#${tag}`)));
    expect(projectButton()?.textContent).toContain("portognjeeen");
  },
);

it("lets the user retry a project change after saving fails", async () => {
  await render();
  invoke.mockRejectedValueOnce(new Error("Disk full"));
  await chooseProject();
  expect(stored.sourceCwd).toBe("/work/Edefyn");
  expect(container.textContent).toContain("Disk full");
  const retry = [
    ...container.querySelectorAll<HTMLButtonElement>("button"),
  ].find((button) => button.textContent === "Retry");
  expect(retry, "An unsaved project choice needs a retry action").toBeDefined();
  let failRetry!: (error: Error) => void;
  const retrying = new Promise<never>((_, reject) => {
    failRetry = reject;
  });
  invoke.mockImplementationOnce(() => retrying);
  await act(async () => retry!.click());
  expect(container.querySelector('[role="alert"]')).toBeNull();
  expect(stored.sourceCwd).toBe("/work/Edefyn");

  await act(async () => failRetry(new Error("Still no space")));
  expect(container.querySelector('[role="alert"]')?.textContent).toContain(
    "Still no space",
  );
  const nextRetry = [
    ...container.querySelectorAll<HTMLButtonElement>("button"),
  ].find((button) => button.textContent === "Retry");
  expect(nextRetry).toBeDefined();
  await act(async () => nextRetry!.click());
  expect(stored.sourceCwd).toBe("/work/portognjeeen");
  expect(container.querySelector('[role="alert"]')).toBeNull();
});

it("keeps a completed move after returning to the note while it saves", async () => {
  const second = {
    ...stored,
    id: "second-note",
    slug: "second",
    title: "Second",
  };
  const save = invoke.getMockImplementation()!;
  let finishMove!: () => void;
  const moving = new Promise<void>((resolve) => {
    finishMove = resolve;
  });
  invoke.mockImplementation(async (command, args) => {
    if (command === "notes_list") return [{ ...stored }, { ...second }];
    if (
      command === "notes_upsert" &&
      args.note.sourceCwd === "/work/portognjeeen"
    )
      await moving;
    return save(command, args);
  });
  const selectNote = async (title: string) => {
    const button = [
      ...container.querySelectorAll<HTMLButtonElement>("li button"),
    ].find((item) => item.textContent?.includes(title));
    expect(button).toBeDefined();
    await act(async () => button!.click());
  };

  await render();
  await chooseProject();
  await selectNote("Second");
  await selectNote("Plan");
  await act(async () => finishMove());
  expect(stored.sourceCwd).toBe("/work/portognjeeen");
  expect(projectButton()?.textContent).toContain("portognjeeen");
  await selectNote("Second");
  expect(stored.sourceCwd).toBe("/work/portognjeeen");
});

it("clears a failed move error when the saved project is selected again", async () => {
  await render();
  invoke.mockRejectedValueOnce(new Error("Disk full"));
  await chooseProject();
  expect(container.querySelector('[role="alert"]')?.textContent).toContain(
    "Disk full",
  );

  await act(async () => projectButton()!.click());
  const original = [
    ...document.querySelectorAll<HTMLButtonElement>(
      '[aria-label="Project picker"] button[title]',
    ),
  ].find((item) => item.title === "/work/Edefyn");
  expect(original).toBeDefined();
  await act(async () => original!.click());

  expect(stored.sourceCwd).toBe("/work/Edefyn");
  expect(projectButton()?.textContent).toContain("Edefyn");
  expect(container.querySelector('[role="alert"]')).toBeNull();
});

function noteRows() {
  return [...container.querySelectorAll<HTMLButtonElement>("li button")].map((button) => button.textContent);
}

function inputText(input: HTMLInputElement, value: string) {
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, value);
  input.dispatchEvent(new Event("input", { bubbles: true }));
}

async function pickNoteMenu(label: string) {
  const row = container.querySelector<HTMLButtonElement>("li button")!;
  await act(async () => row.dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, clientX: 20, clientY: 20 })));
  const item = [...document.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')].find((el) => el.textContent?.includes(label))!;
  expect(item).toBeDefined();
  await act(async () => item.click());
}

it("deletes from the list without recreating an editor draft", async () => {
  let exists = true;
  const save = invoke.getMockImplementation()!;
  invoke.mockImplementation(async (command, args) => {
    if (command === "notes_list") return exists ? [{ ...stored }] : [];
    if (command === "notes_delete") { exists = false; return; }
    if (command === "notes_upsert") exists = true;
    return save(command, args);
  });
  await render();
  const title = container.querySelector<HTMLInputElement>('[aria-label="Note title"]')!;
  await act(async () => inputText(title, "Unsaved draft"));
  await pickNoteMenu("Delete");
  expect(exists).toBe(false);
  expect(container.querySelector('[aria-label="Note title"]')).toBeNull();
});

it("serializes list rename after an in-flight editor save", async () => {
  const save = invoke.getMockImplementation()!;
  let release!: () => void;
  const saving = new Promise<void>((resolve) => { release = resolve; });
  let writes = 0;
  invoke.mockImplementation(async (command, args) => {
    if (command === "notes_upsert" && ++writes === 1) await saving;
    return save(command, args);
  });
  await render();
  const title = container.querySelector<HTMLInputElement>('[aria-label="Note title"]')!;
  await act(async () => { title.focus(); inputText(title, "Editor title"); title.blur(); });
  await pickNoteMenu("Rename");
  const rename = container.querySelector<HTMLInputElement>('[aria-label="Rename note"]')!;
  await act(async () => { inputText(rename, "List title"); rename.blur(); });
  await act(async () => release());
  expect(stored.title).toBe("List title");
});

function multipleProjects() {
  const notes: Note[] = [
    { ...stored, id: "other-project", title: "Other project note", sourceCwd: "/work/portognjeeen" },
    { ...stored, id: "unassigned", title: "Unassigned note", sourceCwd: undefined },
    { ...stored, sourceCwd: "/work/Edefyn/" },
  ];
  invoke.mockImplementation(async (command: string) => {
    if (command === "notes_list") return notes.map((note) => ({ ...note }));
    throw new Error(`Unexpected command: ${command}`);
  });
}

it("defaults the notes list and detail to the active project", async () => {
  multipleProjects();
  await render();
  expect(noteRows()).toHaveLength(1);
  expect(noteRows()[0]).toContain("Plan");
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe("Plan");
  expect(container.querySelector('[aria-label^="Notes project filter:"]')).toBeNull();
});

it("follows project changes automatically without a filter control", async () => {
  multipleProjects();
  await render(recents, "~");
  expect(noteRows()).toHaveLength(3);
  await render(recents, "/work/portognjeeen");
  expect(noteRows()).toHaveLength(1);
  expect(noteRows()[0]).toContain("Other project note");
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe("Other project note");
  await render();
  expect(noteRows()).toHaveLength(1);
  expect(noteRows()[0]).toContain("Plan");
});

it("searches only the selected project and does not leave an excluded note open", async () => {
  multipleProjects();
  await render();
  const search = container.querySelector<HTMLInputElement>('[aria-label="Filter notes"]')!;
  await act(async () => inputText(search, "Other project"));
  expect(noteRows()).toEqual([]);
  expect(container.querySelector('[aria-label="Note title"]')).toBeNull();
  await render(recents, "~");
  expect(noteRows()).toHaveLength(1);
  expect(container.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe("Other project note");
});

it("shows all notes without an active project, and none from other projects in an empty project", async () => {
  multipleProjects();
  await render(recents, "~");
  expect(noteRows()).toHaveLength(3);
  await render(recents, "/work/Empty");
  expect(noteRows()).toEqual([]);
  expect(container.querySelector('[aria-label="Note title"]')).toBeNull();
});

it("folds the notes list away from a button that stays put, leaving no strip behind", async () => {
  await render();
  const toggle = () => container.querySelector<HTMLButtonElement>('button[aria-label^="Hide notes list"], button[aria-label^="Show notes list"]');
  const resizeHandle = () => container.querySelector('[aria-label="Resize notes list"]');
  expect(resizeHandle()).not.toBeNull();
  expect(toggle()?.getAttribute("aria-label")).toContain("Hide notes list");
  const header = toggle()!.closest("[data-tauri-drag-region]");

  await act(async () => toggle()!.click());
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 300)); });
  expect(resizeHandle()).toBeNull();
  expect(container.querySelector('[aria-label="Filter notes"]')).toBeNull();
  // The same button, in the same header, now offers to bring the list back.
  expect(toggle()?.getAttribute("aria-label")).toContain("Show notes list");
  expect(toggle()!.closest("[data-tauri-drag-region]")).toBe(header);

  await act(async () => toggle()!.click());
  expect(resizeHandle()).not.toBeNull();
  expect(container.querySelector('[aria-label="Filter notes"]')).not.toBeNull();
});

// Models the backend: only a note created with a blank title has a pending
// slug, replaced once by a finalizing save with a real title.
const saveRequests = () =>
  invoke.mock.calls
    .filter(([command]) => command === "notes_upsert" || command === "notes_finalize_slug")
    .map(([command, args]): Partial<NoteUpsert> => command === "notes_upsert"
      ? (args as { note: NoteUpsert }).note
      : { ...(args as { id: string; title: string }), finalizeSlug: true });

function useSlugBackend(upsertHook?: () => Promise<void>) {
  const slugify = (title: string) =>
    title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "untitled";
  const placeholder = (title: string) => /^untitled(-\d+)?$/.test(slugify(title));
  invoke.mockImplementation(async (command: string, args?: { note: NoteUpsert; id?: string; title?: string }) => {
    if (command === "notes_list") return [{ ...stored }];
    if (command === "notes_finalize_slug") {
      await upsertHook?.();
      if (stored.slugPending && stored.title === args!.title && !placeholder(stored.title)) {
        stored = { ...stored, slug: slugify(stored.title), slugPending: false };
      }
      return { ...stored };
    }
    if (command !== "notes_upsert") throw new Error(`Unexpected command: ${command}`);
    const { finalizeSlug, ...note } = args!.note;
    await upsertHook?.();
    const title = note.title.trim() || "Untitled";
    if (note.id !== stored.id) {
      stored = {
        ...note,
        title,
        slug: slugify(title),
        slugPending: !note.title.trim(),
        createdAt: 1,
        updatedAt: 1,
      };
      return { ...stored };
    }
    const finalize = finalizeSlug && stored.slugPending && !placeholder(title);
    stored = {
      ...stored,
      ...note,
      title,
      ...(finalize ? { slug: slugify(title), slugPending: false } : {}),
      updatedAt: stored.updatedAt + 1,
    };
    return { ...stored };
  });
}

async function renderUntitled(id: string) {
  vi.useFakeTimers();
  stored = { ...stored, id, slug: "untitled", title: "Untitled", body: "", slugPending: true };
  useSlugBackend();
  await render();
  return container.querySelector<HTMLInputElement>('[aria-label="Note title"]')!;
}

it("keeps the placeholder slug while typing with pauses, then finalizes on blur", async () => {
  const title = await renderUntitled("note-slug-typing");
  act(() => {
    title.focus();
    inputText(title, "This i");
  });
  await act(async () => vi.advanceTimersByTime(400));
  act(() => inputText(title, "This is my first note"));
  await act(async () => vi.advanceTimersByTime(400));
  expect(stored.title).toBe("This is my first note");
  expect(stored.slug).toBe("untitled");
  expect(saveRequests().every((note) => !note.finalizeSlug)).toBe(true);

  await act(async () => title.blur());
  expect(saveRequests().at(-1)).toMatchObject({ finalizeSlug: true });
  expect(stored.slug).toBe("this-is-my-first-note");

  act(() => {
    title.focus();
    inputText(title, "Renamed");
  });
  await act(async () => title.blur());
  expect(stored.title).toBe("Renamed");
  expect(stored.slug).toBe("this-is-my-first-note");
  expect(saveRequests().at(-1)?.finalizeSlug).toBeUndefined();
});

it("finalizes the slug when Notes closes without blurring the title", async () => {
  const title = await renderUntitled("note-slug-unmount");
  act(() => {
    title.focus();
    inputText(title, "Closing note");
  });
  await act(async () => vi.advanceTimersByTime(400));
  expect(stored.slug).toBe("untitled");
  await act(async () => root.unmount());
  expect(saveRequests().at(-1)).toMatchObject({ finalizeSlug: true });
  expect(stored.slug).toBe("closing-note");
  root = createRoot(container);
});

it("keeps the finalization request when it fails so Retry still finalizes", async () => {
  const title = await renderUntitled("note-slug-retry");
  act(() => {
    title.focus();
    inputText(title, "Retry note");
  });
  await act(async () => vi.advanceTimersByTime(400));
  expect(stored.title).toBe("Retry note");
  expect(stored.slug).toBe("untitled");

  const ok = invoke.getMockImplementation()!;
  invoke.mockImplementation(async (command: string, args?: { note: NoteUpsert }) => {
    if (command === "notes_upsert" || command === "notes_finalize_slug") throw new Error("Disk full");
    return ok(command, args);
  });
  await act(async () => title.blur());
  expect(container.querySelector('[role="alert"]')?.textContent).toContain("Disk full");
  expect(stored.slug).toBe("untitled");

  invoke.mockImplementation(ok);
  const retry = [...container.querySelectorAll<HTMLButtonElement>("button")]
    .find((button) => button.textContent === "Retry")!;
  await act(async () => retry.click());
  expect(saveRequests().at(-1)).toMatchObject({ title: "Retry note", finalizeSlug: true });
  expect(stored.slug).toBe("retry-note");
  expect(container.querySelector('[role="alert"]')).toBeNull();
});

it("does not let a queued blur finalize a newer partial title", async () => {
  vi.useFakeTimers();
  stored = {
    ...stored,
    id: "note-slug-queued",
    slug: "untitled",
    title: "Untitled",
    body: "",
    slugPending: true,
  };
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  let hold = false;
  useSlugBackend(async () => {
    if (hold) {
      hold = false;
      await gate;
    }
  });
  await render();
  const title = container.querySelector<HTMLInputElement>('[aria-label="Note title"]')!;
  act(() => {
    title.focus();
    inputText(title, "Full title");
  });
  hold = true;
  await act(async () => vi.advanceTimersByTime(400)); // in-flight save
  await act(async () => title.blur()); // queued, finalizing "Full title"
  act(() => {
    title.focus();
    inputText(title, "Full title ext");
  });
  await act(async () => release());

  expect(stored.slug).toBe("untitled");
  expect(saveRequests().some((note) => note.finalizeSlug && note.title !== "Full title")).toBe(false);

  await act(async () => title.blur());
  expect(stored.slug).toBe("full-title-ext");
});

it("does not let a queued blur finalize a title edited away and back", async () => {
  vi.useFakeTimers();
  stored = {
    ...stored,
    id: "note-slug-same-text",
    slug: "untitled",
    title: "Untitled",
    body: "",
    slugPending: true,
  };
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  let hold = false;
  useSlugBackend(async () => {
    if (hold) {
      hold = false;
      await gate;
    }
  });
  await render();
  const title = container.querySelector<HTMLInputElement>('[aria-label="Note title"]')!;
  act(() => {
    title.focus();
    inputText(title, "Plan");
  });
  hold = true;
  await act(async () => vi.advanceTimersByTime(400)); // in-flight save
  await act(async () => title.blur()); // queued, finalizing "Plan"
  act(() => {
    title.focus();
    inputText(title, "Plan extended");
    inputText(title, "Plan");
  });
  await act(async () => release());
  await act(async () => vi.advanceTimersByTime(400));

  expect(stored.slug).toBe("untitled");
  expect(saveRequests().some((note) => note.finalizeSlug)).toBe(false);

  await act(async () => title.blur());
  expect(saveRequests().at(-1)).toMatchObject({ title: "Plan", finalizeSlug: true });
  expect(stored.slug).toBe("plan");
});

it("keeps a newer finalization request when an older finalizing save completes", async () => {
  vi.useFakeTimers();
  stored = {
    ...stored,
    id: "note-slug-stale",
    slug: "untitled",
    title: "Untitled",
    body: "",
    slugPending: true,
  };
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  let hold = true;
  useSlugBackend(async () => {
    if (hold) {
      hold = false;
      await gate;
    }
  });
  await render();
  const title = container.querySelector<HTMLInputElement>('[aria-label="Note title"]')!;
  await act(async () => {
    title.focus();
    title.blur(); // finalizing save for "Untitled" held in flight
  });
  act(() => {
    title.focus();
    inputText(title, "Real title");
  });
  await act(async () => title.blur()); // queued, finalizing "Real title"
  await act(async () => release());

  expect(saveRequests().at(-1)).toMatchObject({ title: "Real title", finalizeSlug: true });
  expect(stored.slug).toBe("real-title");
});

it("does not save or request finalization when blurring an unchanged established note", async () => {
  vi.useFakeTimers();
  stored = { ...stored, id: "note-real-slug", slug: "untitled", title: "Untitled", body: "" };
  useSlugBackend();
  await render();
  const title = container.querySelector<HTMLInputElement>('[aria-label="Note title"]')!;
  const before = saveRequests().length;

  await act(async () => {
    title.focus();
    title.blur();
  });

  expect(saveRequests().length).toBe(before);
  expect(saveRequests().some((note) => note.finalizeSlug)).toBe(false);
});

it("creates a new note with a blank title so its slug starts pending", async () => {
  vi.useFakeTimers();
  useSlugBackend();
  await render();
  const create = container.querySelector<HTMLButtonElement>('[aria-label="New note"]')!;
  await act(async () => create.click());

  expect(saveRequests().at(-1)).toMatchObject({ title: "", body: "" });
  expect(stored).toMatchObject({ title: "Untitled", slug: "untitled", slugPending: true });
  const title = container.querySelector<HTMLInputElement>('[aria-label="Note title"]')!;
  expect(title.value).toBe("Untitled");
});

it.each([
  ["untitled", "Untitled"],
  ["untitled-3", "Untitled 3"],
  ["plan", "Plan"],
])("never requests finalization for an established %s slug", async (slug, oldTitle) => {
  vi.useFakeTimers();
  stored = { ...stored, id: `note-established-${slug}`, slug, title: oldTitle, body: "" };
  useSlugBackend();
  await render();
  const title = container.querySelector<HTMLInputElement>('[aria-label="Note title"]')!;
  act(() => {
    title.focus();
    inputText(title, "Release notes");
  });
  await act(async () => vi.advanceTimersByTime(400));
  await act(async () => title.blur());
  await act(async () => root.unmount());
  root = createRoot(container);

  expect(stored).toMatchObject({ title: "Release notes", slug, slugPending: false });
  expect(saveRequests().some((note) => note.finalizeSlug)).toBe(false);
});


it("finalizes a pending slug when a list rename is committed", async () => {
  await renderUntitled("note-slug-list-rename");
  await pickNoteMenu("Rename");
  const rename = container.querySelector<HTMLInputElement>('[aria-label="Rename note"]')!;
  await act(async () => { inputText(rename, "Release plan"); rename.blur(); });
  expect(saveRequests().at(-1)).toMatchObject({ title: "Release plan", finalizeSlug: true });
  expect(stored).toMatchObject({ slug: "release-plan", slugPending: false });
});


it("does not overwrite another window's edits when an unchanged pending editor closes", async () => {
  await renderUntitled("note-slug-external-edit");
  stored = { ...stored, title: "Other window", body: "Keep the newer body", tags: ["new"], updatedAt: 42 };
  await act(async () => root.unmount());
  root = createRoot(container);
  expect(invoke.mock.calls.filter(([command]) => command === "notes_upsert")).toHaveLength(0);
  expect(stored).toMatchObject({ title: "Other window", body: "Keep the newer body", tags: ["new"], updatedAt: 42, slugPending: true });
});

it("does not recreate a note deleted by another window when its unchanged editor closes", async () => {
  await renderUntitled("note-slug-external-delete");
  let exists = false;
  const backend = invoke.getMockImplementation()!;
  invoke.mockImplementation(async (command, args) => {
    if (command === "notes_finalize_slug") return null;
    if (command === "notes_upsert") exists = true;
    return backend(command, args);
  });
  await act(async () => root.unmount());
  root = createRoot(container);
  expect(exists).toBe(false);
  expect(invoke.mock.calls.filter(([command]) => command === "notes_upsert")).toHaveLength(0);
});
