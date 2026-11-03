// @vitest-environment happy-dom
import { act } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { FsEntry } from "../../platform/tauri/fs";

const host = vi.hoisted(() => ({
  dirs: {} as Record<string, FsEntry[]>,
  existing: new Set<string>(),
  ask: vi.fn(async () => true),
}));
vi.mock("../../platform/tauri/fs", () => ({
  homeDir: async () => "/Users/host",
  listDir: async (path: string) => {
    const entries = host.dirs[path];
    if (!entries) throw new Error(`${path}: No such directory`);
    return entries;
  },
  statFiles: async (paths: string[]) => paths.map((path) => ({ path, mtimeMs: host.existing.has(path) ? 1 : null })),
}));
vi.mock("@tauri-apps/plugin-dialog", () => ({ ask: host.ask, open: vi.fn(), save: vi.fn() }));

import { open, pickFolders, save, setHostPicker } from "../../platform/dialog";
import { pickOnHost, startingPlace } from "./HostFileDialog";

const entry = (path: string, isDir = false, hidden = false): FsEntry => ({ name: path.slice(path.lastIndexOf("/") + 1), path, isDir, hidden });

async function settle() {
  await act(async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); });
}
const dialog = () => document.querySelector("[data-host-file-dialog]")!;
const names = () => [...dialog().querySelectorAll("[role=option]")].map((option) => option.textContent);
async function click(text: string) {
  const button = [...document.querySelectorAll("button")].find((candidate) => candidate.textContent?.includes(text) || candidate.getAttribute("aria-label") === text);
  if (!button) throw new Error(`No button ${text}`);
  await act(async () => button.click());
  await settle();
}

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  host.dirs = {
    "/Users/host": [entry("/Users/host/papers", true), entry("/Users/host/.cache", true, true), entry("/Users/host/notes.md")],
    "/Users/host/papers": [entry("/Users/host/papers/raft.pdf"), entry("/Users/host/papers/paxos.pdf"), entry("/Users/host/papers/todo.txt")],
    "/Users": [entry("/Users/host", true)],
  };
  host.existing = new Set();
  host.ask.mockClear();
  setHostPicker(pickOnHost);
});
afterEach(() => {
  setHostPicker(undefined);
  document.body.innerHTML = "";
  vi.unstubAllGlobals();
});

describe("the host's file browser", () => {
  it("opens the host's home, goes into folders and returns the host paths chosen", async () => {
    const picking = open({ multiple: true, filters: [{ name: "PDF", extensions: ["pdf"] }] });
    await settle();
    expect(names()).toEqual(["▸papers"]);
    await click("papers");
    expect(names()).toEqual(["raft.pdf", "paxos.pdf"]);
    await click("raft.pdf");
    await click("paxos.pdf");
    await click("Open");
    await expect(picking).resolves.toEqual(["/Users/host/papers/raft.pdf", "/Users/host/papers/paxos.pdf"]);
    expect(document.querySelector("[data-host-file-dialog]")).toBeNull();
  });

  it("chooses the folder it shows, after going up one", async () => {
    const picking = pickFolders("Choose folders");
    await settle();
    await click("Up one folder");
    expect(names()).toEqual(["▸host"]);
    await click("Choose this folder");
    await expect(picking).resolves.toEqual(["/Users"]);
  });

  it("asks before saving over a file on the host, and returns nothing when cancelled", async () => {
    host.existing.add("/Users/host/papers/raft.pdf");
    const saving = save({ defaultPath: "/Users/host/papers/raft.pdf" });
    await settle();
    expect((document.querySelector("[aria-label='File name']") as HTMLInputElement).value).toBe("raft.pdf");
    await click("Save");
    expect(host.ask).toHaveBeenCalledOnce();
    await expect(saving).resolves.toBe("/Users/host/papers/raft.pdf");

    const cancelled = open();
    await settle();
    await click("Cancel");
    await expect(cancelled).resolves.toBeNull();
  });

  it("says why a folder could not be read", async () => {
    void open({ defaultPath: "/gone" });
    await settle();
    expect(dialog().querySelector("[role=alert]")?.textContent).toContain("No such directory");
  });

  it("starts where the caller asked", () => {
    expect(startingPlace(undefined, "open", "/home/h")).toEqual({ dir: "/home/h", name: "" });
    expect(startingPlace("/a/b/report.pdf", "save", "/home/h")).toEqual({ dir: "/a/b", name: "report.pdf" });
    expect(startingPlace("/a/b/report.pdf", "open", "/home/h")).toEqual({ dir: "/a/b", name: "" });
    expect(startingPlace("/a/b", "open", "/home/h")).toEqual({ dir: "/a/b", name: "" });
  });
});
