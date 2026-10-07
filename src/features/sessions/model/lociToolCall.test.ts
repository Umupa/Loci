import { describe,expect,it } from "vitest";
import { lociToolCall,lociWorkSummary } from "./lociToolCall";
import type { Block } from "./session";

function shell(text: string): Block {
  return { id: text, role: "tool", text, tool: { kind: "shell" } };
}

describe("Loci CLI tool calls", () => {
  it.each([
    ["canvas.list", "List canvases"],
    ["canvas.get", "Get a canvas"],
    ["canvas.create", "Create a canvas"],
    ["canvas.rename", "Rename a canvas"],
    ["canvas.delete", "Delete a canvas"],
    ["canvas.read-data", "Read canvas scene data"],
    ["canvas.write-data", "Write canvas scene data"],
  ])("labels %s as an app operation", (action, label) => {
    expect(lociToolCall(shell(`loci app ${action} --json '{}'`))?.label).toBe(label);
  });
  it("recognizes app actions with absolute, quoted, or bare executables", () => {
    expect(
      lociToolCall(
        shell(
          "/repo/target/debug/Loci.app/Contents/MacOS/loci app notes.list --json '{}'",
        ),
      )?.label,
    ).toBe("List notes");
    expect(
      lociToolCall(
        shell(
          "'/Applications/Loci App/loci' app folders.move --input -",
        ),
      )?.label,
    ).toBe("Move a session");
    expect(
      lociToolCall(
        shell('"C:\\Program Files\\Loci\\loci.exe" app notes.list'),
      )?.label,
    ).toBe("List notes");
    expect(lociToolCall(shell("loci app --help"))?.label).toBe(
      "View CLI commands",
    );
    expect(
      lociToolCall(shell("loci app sessions.read --json '{}'"))?.label,
    ).toBe("Read a session");
    expect(
      lociToolCall(shell("loci app sessions.send --json '{}'"))?.label,
    ).toBe("Continue a session");
    expect(
      lociToolCall(shell("loci app sessions.draft --json '{}'"))?.label,
    ).toBe("Save a draft");
    expect(
      lociToolCall(shell("loci app notes.write --input -"))?.label,
    ).toBe("Write a note");
    expect(
      lociToolCall({
        id: "generic",
        role: "tool",
        text: "Run command:",
        tool: { kind: "other", title: "loci app sessions.start" },
      })?.label,
    ).toBe("Start a session");
    expect(
      lociToolCall({
        id: "codex-action",
        role: "tool",
        text: "List",
        tool: {
          kind: "execute",
          preview: { kind: "shell", title: "loci app notes.list" },
        },
      })?.label,
    ).toBe("List notes");
  });

  it("does not restyle unrelated commands or text mentioning the CLI", () => {
    expect(
      lociToolCall(shell("echo loci app notes.list")),
    ).toBeUndefined();
    expect(lociToolCall(shell("loci control list"))).toBeUndefined();
    expect(
      lociToolCall({
        id: "prose",
        role: "assistant",
        text: "loci app notes.list",
      }),
    ).toBeUndefined();
  });

  it("does not compact compound shell commands or hide a longer shell preview", () => {
    for (const command of [
      "loci app notes.list && echo extra",
      "loci app notes.list; echo extra",
      "loci app notes.list | cat",
      "loci app notes.list\necho extra",
      "loci app notes.list --json \"$(echo extra)\"",
    ]) {
      expect(lociToolCall(shell(command))).toBeUndefined();
    }
    expect(
      lociToolCall({
        id: "short-title",
        role: "tool",
        text: "loci app notes.list",
        tool: {
          kind: "shell",
          title: "loci app notes.list",
          preview: {
            kind: "shell",
            title: "loci app notes.list && echo extra",
          },
        },
      }),
    ).toBeUndefined();
    expect(
      lociToolCall(
        shell("loci app sessions.send --json '{\"prompt\":\"a; b\"}'"),
      )?.command,
    ).toBe("loci app sessions.send --json '{\"prompt\":\"a; b\"}'");
  });

  it("names a group only when all its tool calls use Loci", () => {
    const calls = [
      shell("loci app --help"),
      shell("loci app notes.list"),
    ];
    expect(lociWorkSummary(calls, true)).toBe("Using Loci");
    expect(lociWorkSummary(calls, false)).toBe("Used Loci");
    expect(
      lociWorkSummary([...calls, shell("git status")], true),
    ).toBeUndefined();
  });
});
