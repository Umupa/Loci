import { vi } from "vitest";
import type { Agent } from "../../features/agents/model/agent";
import { newSession, type Session } from "../../features/sessions/model/session";
import type { CommandContext } from "./context";

/** A window for command tests: mentors, their conversations and spies for what commands call. */
export function testContext(agents: Agent[] = [], overrides: Partial<CommandContext> = {}) {
  const chats = new Map<string, Session>();
  const views = new Map<string, ReturnType<CommandContext["reader"]["current"]>>();
  const chatOf = (id: string) => {
    let chat = chats.get(id);
    if (!chat) { chat = { ...newSession("claude", `/agents/${id}`), id: `chat-${id}` }; chats.set(id, chat); }
    return chat;
  };
  const ctx: CommandContext = {
    identifier: vi.fn(async () => "com.loci.desktop.test"),
    agents: () => agents,
    activeAgentId: () => agents[0]?.id ?? null,
    createAgent: vi.fn(async () => "new-agent"),
    removeAgent: vi.fn(async () => true),
    resetAgent: vi.fn(async () => true),
    switchAgent: vi.fn(async () => true),
    agentChat: vi.fn(async (id: string) => chatOf(id)),
    liveSession: (id) => [...chats.values()].find((chat) => chat.id === id),
    submission: {
      submit: vi.fn(async () => true),
      stopSessionWork: vi.fn(async () => undefined),
      changeModel: vi.fn(),
      changeModelSettings: vi.fn(),
      changeRuntimeMode: vi.fn(),
    } as unknown as CommandContext["submission"],
    flushPersistence: vi.fn(async () => undefined),
    reader: {
      show: vi.fn(async (agentId, page) => { views.set(agentId, { page }); }),
      close: vi.fn(async (agentId) => { views.delete(agentId); return true; }),
      current: (agentId) => views.get(agentId) ?? {},
    },
    agentApp: vi.fn(async (_source, _requestId, action) => ({ action })),
    ...overrides,
  };
  return { ctx, chats, chatOf };
}

export function agent(id: string, name?: string): Agent {
  return { id, avatar: "nova", color: "#000", projects: [], ...(name ? { name } : {}) };
}
