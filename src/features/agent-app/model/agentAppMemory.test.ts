// @vitest-environment happy-dom
import { expect, it, vi } from "vitest";
import { newSession } from "../../sessions/model/session";
import {
  AgentFileConflict,
  type AgentFilePath,
} from "../../agents/model/agentFiles";
import { handleAgentApp, type AgentAppHost } from "./agentApp";

/** The agent's folder as a map, with a hash that changes on every write. */
function fixture(agent = true) {
  const source = newSession("codex", "/tmp/project", "codex:test");
  source.id = "agent";
  const files = new Map<string, string>([["MEMORY.md", ""]]);
  const versions = new Map<string, number>();
  const hash = (path: string) => `${path}@${versions.get(path) ?? 0}`;
  const write = vi.fn(
    async (_agentId: string, path: AgentFilePath, text: string, expected: string) => {
      if (expected !== hash(path)) throw new AgentFileConflict();
      files.set(path, text);
      versions.set(path, (versions.get(path) ?? 0) + 1);
      return hash(path);
    },
  );
  const host = {
    agentOf: (id: string) =>
      agent && id === "agent" ? { id: "agent-1", projects: [] } : undefined,
    files: {
    read: async (_agentId: string, path: AgentFilePath) => ({
      text: files.get(path) ?? null,
      hash: hash(path),
    }),
    write,
    load: async () => ({
      id: "a",
      dir: "/data/agents/a",
      soul: "",
      soulHash: "",
      memory: files.get("MEMORY.md") ?? "",
      memoryHash: hash("MEMORY.md"),
      memoryPath: "/data/agents/a/MEMORY.md",
      topics: [...files.keys()]
        .filter((path) => path.startsWith("memory/") && path !== "memory/archive.md")
        .map((path) => path.slice(7, -3)),
    }),
    },
    documents: {
      list: async () => [{ id: "pods", title: "Pods, explained", subject: "Kubernetes", updatedAt: Date.UTC(2026, 9, 9) }],
      read: async (_agentId: string, id: string) =>
        id === "pods" ? { id, title: "Pods, explained", subject: "Kubernetes", body: "# Pods", updatedAt: Date.UTC(2026, 9, 9) } : undefined,
      importSource: async (_agentId: string, input: { id: string; title: string; subject?: string; sourceUrl: string; version?: string }) =>
        ({ id: input.id, title: input.title, subject: input.subject, sourceUrl: input.sourceUrl, sourceVersion: input.version, fetchedAt: Date.UTC(2026, 9, 10), updatedAt: Date.UTC(2026, 9, 10) }),
    },
    now: () => new Date(2026, 9, 4, 12),
  } as unknown as AgentAppHost;
  const run = (action: string, input: Record<string, unknown> = {}) =>
    handleAgentApp(source, `req-${Math.random()}`, action, input, host);
  return { files, write, versions, run };
}

it("adds, supersedes and removes dated entries in MEMORY.md", async () => {
  const { files, run } = fixture();
  await run("memory.add", { fact: "CI runs on Travis" });
  expect(await run("memory.add", { fact: "CI runs on Travis" })).toMatchObject({
    alreadyRemembered: true,
  });
  await run("memory.replace", { find: "Travis", fact: "CI runs on Actions" });
  await run("memory.add", { fact: "wrong fact" });
  await run("memory.remove", { find: "wrong fact" });
  expect(files.get("MEMORY.md")).toBe(
    "- ~~2026-10-04 · CI runs on Travis~~ · superseded 2026-10-04\n- 2026-10-04 · CI runs on Actions\n",
  );
  expect(await run("memory.read")).toMatchObject({ lines: 2, notLoaded: 0 });
});

it("keeps topic notes in their own file and lists them", async () => {
  const { files, run } = fixture();
  await run("memory.add", { fact: "v2.1 shipped", topic: "Releases" });
  expect(files.get("memory/Releases.md")).toContain("- 2026-10-04 · v2.1 shipped");
  expect(await run("memory.read")).toMatchObject({ topics: ["Releases"] });
  expect(await run("memory.read", { topic: "Releases" })).toMatchObject({
    text: expect.stringContaining("v2.1 shipped"),
  });
  await expect(run("memory.add", { fact: "x", topic: "../SOUL" })).rejects.toThrow(
    "topic",
  );
});

it("retries over an edit the user saved in between", async () => {
  const { files, versions, write, run } = fixture();
  const original = write.getMockImplementation()!;
  write.mockImplementationOnce(async (...args) => {
    // The user saves from the details panel just before the agent's write.
    files.set("MEMORY.md", "User note\n");
    versions.set("MEMORY.md", 9);
    return original(...args);
  });
  await run("memory.add", { fact: "uses pnpm" });
  expect(files.get("MEMORY.md")).toBe("User note\n- 2026-10-04 · uses pnpm\n");
});

it("redacts secrets and refuses sessions that are not an agent", async () => {
  const { files, run } = fixture();
  await run("memory.add", { fact: "deploy token=abc123secretvalue" });
  expect(files.get("MEMORY.md")).not.toContain("abc123secretvalue");
  await expect(fixture(false).run("memory.read")).rejects.toThrow(
    "an agent's conversation",
  );
});

it("searches MEMORY.md, topics and the archive", async () => {
  const { files, run } = fixture();
  await run("memory.add", { fact: "deploys go through Fly" });
  await run("memory.add", { fact: "Fly region is ams", topic: "infra" });
  files.set("memory/archive.md", "- 2026-01-01 · deploys went through Heroku · moved 2026-09-01\n");
  const result = (await run("memory.search", { query: "deploys" })) as {
    hits: { file: string }[];
  };
  expect(result.hits.map((hit) => hit.file)).toEqual(["MEMORY.md", "memory/archive.md"]);
  expect(await run("memory.search", { query: "fly" })).toMatchObject({
    hits: [{ file: "MEMORY.md" }, { file: "memory/infra.md" }],
  });
});

it("lets an agent read back the documents it wrote, and nobody else", async () => {
  const { run } = fixture();
  expect(await run("documents.list")).toEqual({
    documents: [{ id: "pods", title: "Pods, explained", subject: "Kubernetes", updatedAt: "2026-10-09T00:00:00.000Z" }],
  });
  expect(await run("documents.read", { id: "pods" })).toMatchObject({ title: "Pods, explained", text: "# Pods" });
  await expect(run("documents.read", { id: "missing" })).rejects.toThrow("No such document");
  await expect(fixture(false).run("documents.list")).rejects.toThrow("Only an agent's own conversation");
});

it("takes a source into the library from the file the agent saved, with where it was published", async () => {
  const { run } = fixture();
  const source = { id: "k8s-pod-lifecycle", title: "Pod Lifecycle", subject: "Kubernetes", path: "/tmp/k8s/pod-lifecycle.md", sourceUrl: "https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/", version: "v1.34" };
  expect(await run("documents.write", source)).toEqual({
    id: "k8s-pod-lifecycle", title: "Pod Lifecycle", subject: "Kubernetes", sourceUrl: source.sourceUrl, version: "v1.34",
    updatedAt: "2026-10-10T00:00:00.000Z", saved: true,
  });
  // The text comes from the file: there is no field to pass it in.
  await expect(run("documents.write", { ...source, body: "# Retyped" })).rejects.toThrow();
  await expect(run("documents.write", { ...source, path: undefined })).rejects.toThrow("path");
  await expect(run("documents.write", { ...source, sourceUrl: "" })).rejects.toThrow("sourceUrl");
  await expect(fixture(false).run("documents.write", source)).rejects.toThrow("Only an agent's own conversation");
});
