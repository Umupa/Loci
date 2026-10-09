// @vitest-environment happy-dom
// One turn of a real /learn conversation: a signed-in agent CLI is given the
// production prompt and the real loci_learn MCP server, whose calls reach the
// production bridge over the control socket's line protocol. Only the Tauri
// window and SQLite are replaced, by a store kept in a file between turns, so
// that the next turn can be written after reading what the agent said.
//
//   LEARN_PROBE_DIR=/scratch/k8s LEARN_PROBE_HARNESS=codex \
//   LEARN_PROBE_MESSAGE='/learn kubernetes' \
//   npx vitest run --config scripts/acceptance/learn/vitest.config.ts
//
// LEARN_PROBE_MODEL picks the model, LEARN_PROBE_MESSAGE_FILE reads the message
// from a file, and LEARN_PROBE_LANGUAGES ("zh-CN,en") stands in for the system
// languages the app reports to the agent.
// The folder gets `project/` (the subject's folder, where the agent works),
// `state.json`, `transcript.md` and `map.md`. See ../README.md.
import { spawn } from "node:child_process";
import fs from "node:fs";
import { createServer, type AddressInfo } from "node:net";
import path from "node:path";
import { createInterface } from "node:readline";
import { expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { invalidateCanvases, type Canvas, type CanvasUpsert } from "../../../src/features/canvas/canvas";
import { handleLearnBridge } from "../../../src/features/learn/bridge";
import { LEARN_MCP_NAME } from "../../../src/features/learn/mcpServer";
import { isLearnMap, readMap } from "../../../src/features/learn/model/learnMap";
import type { Note, NoteUpsert } from "../../../src/features/notes";
import type { Block, Session } from "../../../src/features/sessions/model/session";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

type Harness = "claude" | "codex";
type State = { harness: Harness; model?: string; cliSession?: string; blocks: Block[]; canvases: Canvas[]; notes: Note[]; clock: number };
type Step = { kind: "text" | "tool"; text: string };

const dir = process.env.LEARN_PROBE_DIR;
const message = process.env.LEARN_PROBE_MESSAGE_FILE ? fs.readFileSync(process.env.LEARN_PROBE_MESSAGE_FILE, "utf8").trim() : process.env.LEARN_PROBE_MESSAGE;
const server = path.resolve(__dirname, "../../../src-tauri/resources/learn-mcp/loci-learn.mjs");
const TOKEN = "probe-token";

const short = (value: unknown, max = 220) => {
  const text = typeof value === "string" ? value : JSON.stringify(value) ?? "";
  return text.length > max ? `${text.slice(0, max)}…` : text;
};

/** The commands the bridge uses. Canvases and notes live in the state file; source files are checked on disk. */
function appStore(state: State) {
  const canvases = new Map(state.canvases.map((canvas) => [canvas.id, canvas]));
  const notes = new Map(state.notes.map((note) => [note.id, note]));
  const commands: Record<string, (args: any) => unknown> = {
    canvas_list: () => [...canvases.values()],
    canvas_get: ({ id }) => canvases.get(id) ?? null,
    canvas_upsert: ({ canvas }: { canvas: CanvasUpsert }) => {
      const { checkpoint: _checkpoint, expectedUpdatedAt, ...fields } = canvas;
      const previous = canvases.get(fields.id);
      if (expectedUpdatedAt !== undefined && (!previous || previous.updatedAt !== expectedUpdatedAt)) throw new Error("Canvas changed since it was read; retry the update.");
      const saved: Canvas = { ...fields, createdAt: previous?.createdAt ?? ++state.clock, updatedAt: ++state.clock };
      canvases.set(saved.id, saved);
      return saved;
    },
    canvas_checkpoint_canvas: ({ checkpointId }) => canvases.has(checkpointId) ? checkpointId : null,
    canvas_checkpoint_latest: () => null,
    notes_get: ({ id }) => notes.get(id) ?? null,
    notes_upsert: ({ note }: { note: NoteUpsert }) => {
      const previous = notes.get(note.id);
      const saved = { ...previous, ...note, slug: note.id, createdAt: previous?.createdAt ?? ++state.clock, updatedAt: ++state.clock } as Note;
      notes.set(saved.id, saved);
      return saved;
    },
    stat_files: ({ paths }: { paths: string[] }) => paths.map((file) => ({ path: file, mtimeMs: fs.existsSync(file) ? fs.statSync(file).mtimeMs : null })),
  };
  return {
    run: async (command: string, args: unknown) => {
      if (!commands[command]) throw new Error(`Unexpected command ${command}`);
      return structuredClone(commands[command](args));
    },
    save: () => { state.canvases = [...canvases.values()]; state.notes = [...notes.values()]; },
  };
}

/** What a learner would see in the pane: the mission, the roadmap by stage, and what grew beside it. */
function mapText(state: State): string {
  const canvas = state.canvases.find((entry) => isLearnMap(entry));
  if (!canvas) return "No learning map yet.\n";
  const view = readMap(canvas.dataJson, Date.now());
  const mark = (node: { state: string }) => node.state === "ghost" ? "[ ]" : node.state === "solid" ? "[x]" : `[${node.state}]`;
  const lines = [`# ${view.title}`, "", view.mission, ""];
  for (const stage of view.stages) lines.push(`## ${stage}`, ...view.nodes.filter((node) => node.stage === stage).map((node) => `- ${mark(node)} ${node.label}`), "");
  const beside = view.nodes.filter((node) => !node.stage);
  if (beside.length) lines.push("## Beside the roadmap", ...beside.map((node) => `- ${mark(node)} ${node.label}${node.kind === "judgment" ? " (judgment)" : ""}`), "");
  if (view.edges.length) lines.push("## Connections", ...view.edges.map((edge) => {
    const name = (id: string | null) => view.nodes.find((node) => node.id === id)?.label ?? id;
    return `- ${name(edge.from)} → ${name(edge.to)}${edge.label ? `: ${edge.label}` : ""}${edge.by === "proposed" ? " (proposed)" : ""}`;
  }), "");
  return lines.join("\n");
}

/** Run one prompt through the CLI and collect what it said and did, in order. */
function runCli(state: State, project: string, prompt: string, endpoint: string, raw: string): Promise<{ steps: Step[]; cliSession?: string; usage?: unknown; exit: number | null; stderr: string }> {
  // The probe is often started from inside another agent session; the CLI under test must not inherit that session.
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !/^CLAUDE/.test(name)));
  Object.assign(env, { LOCI_APP_ENDPOINT: endpoint, LOCI_APP_TOKEN: TOKEN });
  const model = state.model ? [state.harness === "claude" ? "--model" : "-m", state.model] : [];
  const [command, args] = state.harness === "claude"
    ? ["claude", ["-p", "--output-format", "stream-json", "--verbose", "--dangerously-skip-permissions", "--strict-mcp-config",
        // Without a window there is nothing to show a question card in; the skill then asks in text.
        "--disallowedTools", "AskUserQuestion",
        "--mcp-config", JSON.stringify({ mcpServers: { [LEARN_MCP_NAME]: { type: "stdio", command: process.execPath, args: [server] } } }),
        ...model, ...(state.cliSession ? ["--resume", state.cliSession] : [])]] as const
    : ["codex", ["exec", ...(state.cliSession ? ["resume"] : []), "--json", "--skip-git-repo-check", "--dangerously-bypass-approvals-and-sandbox",
        "-c", `mcp_servers.${LEARN_MCP_NAME}.command=${JSON.stringify(process.execPath)}`,
        "-c", `mcp_servers.${LEARN_MCP_NAME}.args=${JSON.stringify([server])}`,
        "-c", `mcp_servers.${LEARN_MCP_NAME}.env_vars=${JSON.stringify(["LOCI_APP_ENDPOINT", "LOCI_APP_TOKEN"])}`,
        ...model, ...(state.cliSession ? [state.cliSession] : []), "-"]] as const;
  return new Promise((resolve, reject) => {
    const child = spawn(command, [...args], { cwd: project, env: env as NodeJS.ProcessEnv });
    const steps: Step[] = [];
    let cliSession: string | undefined;
    let usage: unknown;
    let stderr = "";
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    createInterface({ input: child.stdout }).on("line", (line) => {
      fs.appendFileSync(raw, `${line}\n`);
      let event: any;
      try { event = JSON.parse(line); } catch { return; }
      if (state.harness === "claude") {
        if (event.session_id) cliSession = event.session_id;
        if (event.type === "assistant") for (const part of event.message?.content ?? []) {
          if (part.type === "text" && part.text.trim()) steps.push({ kind: "text", text: part.text });
          if (part.type === "tool_use") steps.push({ kind: "tool", text: `${part.name} ${short(part.input)}` });
        }
        if (event.type === "user") for (const part of event.message?.content ?? [])
          if (part.type === "tool_result" && part.is_error) steps.push({ kind: "tool", text: `  ↳ error: ${short(Array.isArray(part.content) ? part.content.map((entry: any) => entry.text).join(" ") : part.content, 400)}` });
        if (event.type === "result") usage = { costUsd: event.total_cost_usd, turns: event.num_turns, durationMs: event.duration_ms, usage: event.usage };
        return;
      }
      if (event.type === "thread.started") cliSession = event.thread_id;
      if (event.type === "turn.completed") usage = event.usage;
      if (event.type === "error" || event.type === "turn.failed") steps.push({ kind: "tool", text: `error: ${short(event, 600)}` });
      const item = event.type === "item.completed" ? event.item : undefined;
      if (!item) return;
      if (item.type === "agent_message" && item.text?.trim()) steps.push({ kind: "text", text: item.text });
      else if (item.type === "mcp_tool_call") steps.push({ kind: "tool", text: `${item.server}:${item.tool} ${short(item.arguments)}${item.error ? `\n  ↳ error: ${short(item.error, 400)}` : item.result?.is_error || item.result?.isError ? `\n  ↳ refused: ${short(item.result, 400)}` : ""}` });
      else if (item.type === "command_execution") steps.push({ kind: "tool", text: `$ ${short(item.command, 300)}${item.exit_code ? ` (exit ${item.exit_code})` : ""}` });
      else if (item.type !== "reasoning") steps.push({ kind: "tool", text: `${item.type} ${short({ ...item, id: undefined, type: undefined })}` });
    });
    child.on("close", (exit) => resolve({ steps, cliSession, usage, exit, stderr }));
    child.stdin.end(prompt);
  });
}

it.skipIf(!dir || !message)("runs one turn of /learn with a real agent CLI", async () => {
  const project = path.join(dir!, "project");
  const stateFile = path.join(dir!, "state.json");
  fs.mkdirSync(project, { recursive: true });
  const state: State = fs.existsSync(stateFile) ? JSON.parse(fs.readFileSync(stateFile, "utf8"))
    : { harness: (process.env.LEARN_PROBE_HARNESS as Harness) || "codex", model: process.env.LEARN_PROBE_MODEL || undefined, blocks: [], canvases: [], notes: [], clock: 0 };
  expect(["claude", "codex"]).toContain(state.harness);

  // The prompt names the system's languages, which it reads when the module loads.
  if (process.env.LEARN_PROBE_LANGUAGES) Object.defineProperty(navigator, "languages", { value: process.env.LEARN_PROBE_LANGUAGES.split(","), configurable: true });
  const { consumeLearnCommand, LEARN_CONTINUE_PROMPT, LEARN_PROMPT } = await import("../../../src/features/learn/learnCommand");
  // What useSessionSubmission does with the learner's text: the command is consumed, the prompt follows the first /learn turn.
  const learning = consumeLearnCommand(message!);
  const visible = learning.matched ? learning.text.trim() || LEARN_CONTINUE_PROMPT : message!;
  const prompt = learning.matched ? visible + LEARN_PROMPT : visible;
  if (!learning.matched && !state.blocks.some((block) => block.role === "user" && block.learn)) throw new Error("The first message of a probe conversation starts with /learn");
  state.blocks.push({ id: crypto.randomUUID(), role: "user", text: visible, ...(learning.matched ? { learn: true } : {}) } as Block);

  vi.stubGlobal("FontFace", class { constructor(family: string, _source: string, descriptors: object) { Object.assign(this, { family }, descriptors); } });
  // happy-dom has no text rasterizer; the actual Excalidraw conversion runs.
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({ filter: "none", font: "20px sans-serif",
    measureText(text: string) { return { width: text.length * (parseFloat((this as { font: string }).font) || 20) * 0.5 }; } } as never);
  const store = appStore(state);
  invalidateCanvases();
  vi.mocked(invoke).mockImplementation((command, args) => store.run(command, args) as never);

  const source = { id: "probe-session", cwd: project, harness: state.harness, title: `${state.harness} · learn`, blocks: state.blocks } as unknown as Session;
  const calls: string[] = [];
  // What `control.rs` does for the `learn` namespace: one JSON line in, one out.
  const control = createServer((socket) => {
    createInterface({ input: socket }).once("line", (line) => {
      const request = JSON.parse(line);
      const reply = (response: object) => socket.end(`${JSON.stringify(response)}\n`);
      if (request.token !== TOKEN || request.namespace !== "learn") return reply({ ok: false, error: "Connection revoked or unauthorized" });
      void handleLearnBridge(source, request.action, request.input, { reveal: () => undefined }).then(
        (result) => { calls.push(`${request.action} ok`); reply({ ok: true, result }); },
        (error: Error) => { calls.push(`${request.action} REFUSED: ${error.message}`); reply({ ok: false, error: error.message }); });
    });
  });
  await new Promise<void>((resolve) => control.listen(0, "127.0.0.1", resolve));
  const started = Date.now();
  const turn = state.blocks.filter((block) => block.role === "user").length;
  fs.mkdirSync(path.join(dir!, "events"), { recursive: true });
  const result = await runCli(state, project, prompt, `127.0.0.1:${(control.address() as AddressInfo).port}`, path.join(dir!, "events", `turn-${turn}.jsonl`));
  control.close();
  store.save();

  const reply = result.steps.filter((step) => step.kind === "text").map((step) => step.text).join("\n\n");
  state.blocks.push({ id: crypto.randomUUID(), role: "assistant", text: reply } as Block);
  if (result.cliSession) state.cliSession = result.cliSession;
  fs.writeFileSync(stateFile, JSON.stringify(state, null, 1));
  fs.writeFileSync(path.join(dir!, "map.md"), mapText(state));
  fs.appendFileSync(path.join(dir!, "transcript.md"), [
    `\n\n# Turn ${turn} · ${state.harness}${state.model ? ` ${state.model}` : ""} · ${Math.round((Date.now() - started) / 1000)}s`,
    "## Learner", message!,
    "## Agent", ...result.steps.map((step) => step.kind === "text" ? step.text : `    ⚙ ${step.text}`),
    "## Learning tools, as the app answered them", ...(calls.length ? calls.map((call) => `- ${call}`) : ["- none"]),
    `## Usage\n${JSON.stringify(result.usage)}`,
    ...(result.exit ? [`## CLI exited with ${result.exit}\n${result.stderr.slice(-2000)}`] : []),
  ].join("\n\n"));
  expect(result.exit, result.stderr.slice(-2000)).toBe(0);
  expect(reply.trim(), "the agent said nothing").not.toBe("");
});
