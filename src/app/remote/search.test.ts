import { readFileSync } from "node:fs";
import { expect, it, vi } from "vitest";

// A window connected to a host: the real remote transport over a bridge that answers as the host would.
const host = vi.hoisted(() => ({ asked: [] as { cmd: string; args: unknown }[] }));
vi.mock("../../platform/transport", async () => {
  const { createRemoteTransport } = await vi.importActual<typeof import("../../platform/remoteTransport")>("../../platform/remoteTransport");
  const bridge = {
    call: vi.fn(async (command: string, input: { cmd: string; args: unknown }) => {
      if (command !== "remote_client_call") throw new Error(`unexpected ${command}`);
      host.asked.push({ cmd: input.cmd, args: input.args });
      if (input.cmd === "agent_documents_list") return [{ id: "raft", title: "Raft, explained", agentId: "ada", body: "", updatedAt: 1 }];
      return [];
    }),
    listen: vi.fn(async () => () => undefined),
    fileUrl: vi.fn(),
  };
  return { transport: createRemoteTransport(bridge), REMOTE_CLIENT: true };
});

import { loadMentorSearchSources } from "../../features/mentor/ui/MentorSearch";
import { mentorSearchItems, searchMentorItems } from "../../features/mentor/model/mentorSearch";

it("searches what the host keeps, reading it from the host", async () => {
  const sources = await loadMentorSearchSources([{ id: "ada", name: "Ada", avatar: "ember", color: "#f28c28" }]);
  const found = searchMentorItems(mentorSearchItems(sources), "raft");
  expect(found.map((item) => item.title)).toContain("Raft, explained");

  const catalog = readFileSync(new URL("../../../src-tauri/src/remote_catalog.rs", import.meta.url), "utf8");
  const reads = new Set([...catalog.matchAll(/\("([a-z_]+)", Read\)/g)].map((match) => match[1]));
  expect(host.asked.length).toBeGreaterThan(0);
  for (const { cmd } of host.asked) expect(reads.has(cmd), `${cmd} is a Read command`).toBe(true);
});
