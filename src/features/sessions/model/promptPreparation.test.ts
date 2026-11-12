import { beforeEach,describe,expect,it,vi } from "vitest";

const mocks = vi.hoisted(() => ({
  applyNotesToTurn: vi.fn(),
  events: [] as string[],
  warmNativeSkills: vi.fn(),
}));


vi.mock("../../notes", () => ({
  applyNotesToTurn: mocks.applyNotesToTurn,
}));

vi.mock("../../skills/model/skills", () => ({
  warmNativeSkills: mocks.warmNativeSkills,
  isNativeCommandPrompt: (text: string, harness: string) =>
    harness === "codex" && text.startsWith("/"),
}));

import { preparePrompt } from "./promptPreparation";

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

beforeEach(() => {
  mocks.events.length = 0;
  mocks.applyNotesToTurn.mockReset();
  mocks.applyNotesToTurn.mockImplementation(async (text: string) => text);
  mocks.warmNativeSkills.mockReset();
  mocks.warmNativeSkills.mockImplementation(() => {
    mocks.events.push("warm");
  });
});

describe("preparePrompt", () => {
  it.each([
    "/workflow foo @README.md",
    "/Review_Code a:b",
    "/codex:compact custom instructions",
  ])("preserves native command arguments: %s", async (text) => {
    await expect(
      preparePrompt(text, { harness: "codex", cwd: "/repo" }),
    ).resolves.toBe(text.replace("/codex:compact", "/compact"));
    expect(mocks.applyNotesToTurn).not.toHaveBeenCalled();
  });
  it("starts warmup before awaiting note contents", async () => {
    const notes = deferred<string>();
    mocks.applyNotesToTurn.mockImplementation(() => { mocks.events.push("notes"); return notes.promise; });
    const preparation = preparePrompt("hello", { harness: "codex", cwd: "/repo" });
    expect(mocks.events).toEqual(["warm", "notes"]);
    notes.resolve("with notes");
    // Skill files are not read: the text goes as the notes left it.
    await expect(preparation).resolves.toBe("with notes");
    expect(mocks.applyNotesToTurn).toHaveBeenCalledWith("hello");
  });
});
