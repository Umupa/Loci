// @vitest-environment happy-dom
import { beforeEach, expect, it, vi } from "vitest";

const stored = new Map<string, string>();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(async (command: string, args: { folder: string; id: string; language: string; content?: string }) => {
    const key = `${args.folder}/translations/${args.language}/${args.id}.md`;
    if (command === "source_translation_read") return stored.get(key) ?? null;
    if (command === "source_translation_write") { stored.set(key, args.content!); return null; }
    throw new Error(command);
  }),
}));

import { newSession } from "../../sessions/model/session";
import { handleAgentApp, type AgentAppHost } from "./agentApp";

const BODY = "# Pods\n\nPods are the smallest unit.\n\n## Pod phase\n\nA summary.\n\n```yaml\nphase: Pending\n```\n";

function run(action: string, input: Record<string, unknown>) {
  const source = newSession("codex", "/tmp/project", "codex:test");
  source.id = "agent";
  const host = {
    agentOf: (id: string) => (id === "agent" ? { id: "agent-1", projects: [] } : undefined),
    documents: {
      read: async (_agentId: string, id: string) => id === "pods"
        ? { id, title: "Pods", kind: "source", sourceUrl: "https://kubernetes.io/pods", body: BODY, updatedAt: 0 }
        : id === "guide" ? { id, title: "Guide", kind: "guide", body: "# Mine", updatedAt: 0 } : undefined,
    },
  } as unknown as AgentAppHost;
  return handleAgentApp(source, `req-${Math.random()}`, action, input, host);
}

beforeEach(() => {
  stored.clear();
  localStorage.clear();
  localStorage.setItem("loci:agent-roster", JSON.stringify([{ id: "agent-1", folder: "/m/kern" }]));
  localStorage.setItem("loci.learningLanguage", "zh-CN");
});

it("keeps a section's translation beside the source and reports what is left", async () => {
  expect(await run("documents.translate", { id: "pods", section: "Pod phase", body: "## Pod 阶段\n\n一个概要。\n\n```yaml\nphase: Pending\n```\n" }))
    .toEqual({ id: "pods", language: "zh-CN", section: "Pod phase", saved: true, translated: 1, of: 2 });
  expect(stored.get("/m/kern/translations/zh-CN/pods.md")).toContain("一个概要。");
  expect(await run("documents.read", { id: "pods" })).toMatchObject({
    text: BODY,
    translation: { language: "zh-CN", sections: 2, translated: ["Pod phase"], untranslated: ["Pods"], outOfDate: [] },
  });
});

it("refuses what it cannot keep side by side, and what is not a source", async () => {
  await expect(run("documents.translate", { id: "pods", section: "Pod phase", body: "一个概要。" })).rejects.toThrow("same headings");
  await expect(run("documents.translate", { id: "pods", section: "Nowhere", body: "x" })).rejects.toThrow('No heading "Nowhere"');
  await expect(run("documents.translate", { id: "guide", body: "# 我的" })).rejects.toThrow("Only a source");
  localStorage.removeItem("loci.learningLanguage");
  await expect(run("documents.translate", { id: "pods", body: "# Pods" })).rejects.toThrow("learning language");
});
