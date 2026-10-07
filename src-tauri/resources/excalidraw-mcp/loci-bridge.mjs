#!/usr/bin/env node
// Runs the official Excalidraw MCP server (./official, unmodified) over stdio
// with Loci canvases as its checkpoint store. The official server already takes
// a store, so its drawing tools, reference text and checkpoint rules stay
// upstream's.
//
// Loci acts as the host around it: it keeps one live drawing per checkpoint
// lineage, it answers `read_widget_context`, the host tool the official
// `create_view` reply tells agents to call before editing, and it withholds
// the widget's upload to excalidraw.com.
import { AsyncLocalStorage } from "node:async_hooks";
import { randomUUID } from "node:crypto";
import net from "node:net";
import { createInterface } from "node:readline";

const [major, minor] = process.versions.node.split(".").map(Number);
if (!process.versions.bun && (major < 20 || (major === 20 && minor < 11))) {
  // The official bundle reads import.meta.dirname, added in Node 20.11.
  console.error("Loci's Excalidraw MCP needs Node.js 20.11 or newer.");
  process.exit(1);
}
const { createServer } = await import("./official/server.js");

const HOST_TOOL = {
  name: "read_widget_context",
  title: "Read Canvas",
  description:
    "Reads the Loci canvas behind a checkpoint as it is now, including edits the user made by hand after it was drawn. " +
    "Returns the drawing's Excalidraw elements with their ids and a summary of what the user changed. " +
    "Call it before changing an existing drawing. Omit checkpointId to list this project's drawings and their checkpoint ids.",
  inputSchema: {
    type: "object",
    properties: {
      checkpointId: {
        type: "string",
        description: "A checkpoint id returned by create_view, or a drawing id from the list.",
      },
    },
    additionalProperties: false,
  },
  annotations: { readOnlyHint: true },
};
const INSTRUCTIONS =
  "These Excalidraw tools draw on Loci canvases. Every create_view call saves a drawing that the user sees and can edit in Loci, " +
  "and each checkpoint id refers to that drawing's latest content, including the user's own edits. " +
  "To change an existing drawing, call read_widget_context for its current elements, then call create_view starting with " +
  '{"type":"restoreCheckpoint","id":"<checkpoint id>"} followed only by new elements and {"type":"delete","ids":"..."} entries. ' +
  "Elements you do not delete are kept exactly, with their images, frames, fonts and bindings. " +
  "A create_view call without restoreCheckpoint starts a new drawing.";

// The official widget's "Open in Excalidraw" uploads a scene to excalidraw.com.
// Loci shows no such button, and an agent must not be able to send a user's
// drawing to a third party, so the tool is neither listed nor run here.
const UPLOAD_TOOL = "export_to_excalidraw";

const REPLY_TIMEOUT_MS = 40_000;
const REPLY_MAX_CHARS = 64 * 1024 * 1024;

/** One request to the Loci window that owns this agent session. */
function callLoci(action, input) {
  const endpoint = process.env.LOCI_APP_ENDPOINT;
  const token = process.env.LOCI_APP_TOKEN;
  if (!endpoint || !token)
    return Promise.reject(new Error("This Excalidraw server is not connected to Loci. Start the agent from a Loci session."));
  const split = endpoint.lastIndexOf(":");
  const host = endpoint.slice(0, split).replace(/^\[|\]$/g, "");
  const port = Number(endpoint.slice(split + 1));
  if (!net.isIP(host) || !(host === "::1" || host.startsWith("127.")) || !Number.isInteger(port))
    return Promise.reject(new Error("Loci canvas access only connects to localhost."));
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host, port });
    let reply = "";
    let settled = false;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      if (error) reject(error);
      else resolve(value);
    };
    socket.setEncoding("utf8");
    socket.setTimeout(REPLY_TIMEOUT_MS, () => finish(new Error("Loci did not answer in time.")));
    socket.on("connect", () => {
      socket.write(`${JSON.stringify({ token, namespace: "canvas", action, input, requestId: randomUUID() })}\n`);
    });
    socket.on("data", (chunk) => {
      reply += chunk;
      if (reply.length > REPLY_MAX_CHARS) finish(new Error("Loci's reply is too large."));
    });
    socket.on("error", (error) =>
      finish(new Error(`Cannot reach Loci (${error.message}). The app may have restarted; send a new message from Loci.`)));
    socket.on("close", () => {
      let response;
      try { response = JSON.parse(reply); }
      catch { return finish(new Error("Loci returned an invalid reply.")); }
      if (response?.ok === true) finish(null, response.result);
      else finish(new Error(typeof response?.error === "string" ? response.error : "Loci rejected the canvas request."));
    });
  });
}

function sameJson(a, b) {
  try { return JSON.stringify(a) === JSON.stringify(b); }
  catch { return false; }
}

/**
 * The official server resolves `restoreCheckpoint` to "loaded elements minus
 * deletions, plus new ones". Send Loci that difference, not the whole scene:
 * the patch then applies to the live canvas even if the user is drawing.
 */
function patchAgainstBase(base, elements) {
  const loaded = new Set(base);
  const byId = new Map(base.map((element) => [element?.id, element]));
  const kept = new Set();
  const added = [];
  for (const element of elements) {
    const original = loaded.has(element) ? element : byId.get(element?.id);
    if (original && !kept.has(original.id) && (original === element || sameJson(original, element))) kept.add(original.id);
    else added.push(element);
  }
  const deletedIds = base.map((element) => element?.id).filter((id) => typeof id === "string" && !kept.has(id));
  return { deletedIds, elements: added };
}

// Which tool call a store access belongs to. The store interface has no
// request argument, and agents may issue several calls at once.
const toolCalls = new AsyncLocalStorage();

const store = {
  async load(id) {
    const found = await callLoci("checkpoint.load", { id });
    if (!found || !Array.isArray(found.elements)) return null;
    const call = toolCalls.getStore();
    if (call?.tool === "create_view") call.base = { id, elements: found.elements };
    return { elements: found.elements };
  },
  async save(id, data) {
    const elements = Array.isArray(data?.elements) ? data.elements : [];
    const call = toolCalls.getStore();
    if (call?.base) {
      await callLoci("checkpoint.save", { id, baseId: call.base.id, ...patchAgainstBase(call.base.elements, elements) });
    } else {
      // `save_checkpoint` stores a widget's whole edited scene under its own id.
      await callLoci("checkpoint.save", { id, elements, ...(call?.tool === "save_checkpoint" ? { replace: true } : {}) });
    }
  },
};

async function readWidgetContext(args) {
  const checkpointId = args?.checkpointId;
  if (checkpointId !== undefined && typeof checkpointId !== "string")
    throw new Error("checkpointId must be a string");
  const result = await callLoci("context.read", checkpointId ? { id: checkpointId } : {});
  return String(result?.text ?? "");
}

const write = (message) => process.stdout.write(`${JSON.stringify(message)}\n`);
const awaitingInitialize = new Set();
const awaitingToolList = new Set();

const transport = {
  onmessage: undefined,
  onclose: undefined,
  onerror: undefined,
  async start() {
    const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
    lines.on("line", (line) => {
      if (!line.trim()) return;
      let message;
      try { message = JSON.parse(line); }
      catch (error) { this.onerror?.(error); return; }
      this.receive(message);
    });
    lines.on("close", () => { this.onclose?.(); process.exit(0); });
  },
  receive(message) {
    const hasId = message?.id !== undefined && message?.id !== null;
    if (message?.method === "initialize" && hasId) awaitingInitialize.add(message.id);
    if (message?.method === "tools/list" && hasId) awaitingToolList.add(message.id);
    if (message?.method !== "tools/call") return this.onmessage?.(message);
    const name = message.params?.name;
    if (name === UPLOAD_TOOL) {
      if (hasId) write({ jsonrpc: "2.0", id: message.id, result: { content: [{ type: "text", text: "Loci does not upload drawings to excalidraw.com." }], isError: true } });
      return;
    }
    if (name !== HOST_TOOL.name) return toolCalls.run({ tool: name }, () => this.onmessage?.(message));
    if (!hasId) return;
    readWidgetContext(message.params?.arguments).then(
      (text) => write({ jsonrpc: "2.0", id: message.id, result: { content: [{ type: "text", text }] } }),
      (error) => write({ jsonrpc: "2.0", id: message.id, result: { content: [{ type: "text", text: String(error?.message ?? error) }], isError: true } }),
    );
  },
  async send(message) {
    if (awaitingInitialize.delete(message?.id) && message.result) {
      const upstream = message.result.instructions;
      message = { ...message, result: { ...message.result, instructions: upstream ? `${upstream}\n\n${INSTRUCTIONS}` : INSTRUCTIONS } };
    } else if (awaitingToolList.delete(message?.id) && Array.isArray(message.result?.tools)) {
      const tools = message.result.tools.filter((tool) => tool?.name !== UPLOAD_TOOL);
      message = { ...message, result: { ...message.result, tools: [...tools, HOST_TOOL] } };
    }
    write(message);
  },
  async close() { this.onclose?.(); },
};

await createServer(store).connect(transport);
