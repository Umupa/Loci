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
import { ELEMENT_UPDATES_SCHEMA } from "./element-properties.mjs";

const [major, minor] = process.versions.node.split(".").map(Number);
if (!process.versions.bun && (major < 20 || (major === 20 && minor < 11))) {
  // The official bundle reads import.meta.dirname, added in Node 20.11.
  console.error("Loci's Excalidraw MCP needs Node.js 20.11 or newer.");
  process.exit(1);
}
const { createServer } = await import("./official/server.js");

const HOST_TOOL = {
  name: "read_widget_context",
  title: "Read Loci Canvas",
  description:
    "Reads the Loci canvas behind a checkpoint as it is now, including edits the user made by hand after it was drawn. " +
    "Returns the drawing's Excalidraw elements with their ids and a summary of what the user changed. " +
    "Without checkpointId, lists this project's drawings and their checkpoint ids.",
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
const GET_ELEMENTS = {
  name: "get_elements", title: "Inspect Loci Canvas Elements",
  description: "Read exact native element properties and the current revision of a Loci canvas. Includes image scale/crop and text metrics, never image file data. Without elementIds, returns all existing elements. Its revision is the expectedRevision used by update_elements.",
  inputSchema: { type: "object", required: ["checkpointId"], additionalProperties: false, properties: {
    checkpointId: { type: "string", minLength: 1 },
    elementIds: { type: "array", minItems: 1, maxItems: 500, items: { type: "string" } },
  } },
  annotations: { readOnlyHint: true },
};
const UPDATE_ELEMENTS = {
  name: "update_elements", title: "Edit and Save Loci Canvas Elements",
  description: "Edits and persistently saves the existing Loci canvas. Batch-updates properties of existing elements by ID: position, size, rotation, typography, line spacing, colors and border styles. Unspecified properties, IDs, image resources, groups and binding targets are preserved; derived text metrics and arrow focus/gap follow geometry changes. Bound labels and straight-arrow endpoints follow their shapes; frame members follow translations. No elements are added or deleted. expectedRevision comes from get_elements; a stale read or any invalid change rejects the whole batch. Text height is measured from fontSize/lineHeight. Fixed-width paragraphs use autoResize:false with width. Bound labels use container width and require autoResize:true for reflow. Bound arrows cannot be moved independently; elbowed/rotated bound-arrow routing requires the editor.",
  inputSchema: { type: "object", required: ["checkpointId", "expectedRevision", "updates"], additionalProperties: false, properties: {
    checkpointId: { type: "string", minLength: 1 },
    expectedRevision: { type: "integer", minimum: 0 },
    updates: ELEMENT_UPDATES_SCHEMA,
  } },
  annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
};
const HOST_TOOLS = [GET_ELEMENTS, UPDATE_ELEMENTS, HOST_TOOL];
const LOCI_CANVAS_REFERENCE =
  "These Excalidraw tools draw on Loci canvases. Every create_view call saves a drawing that the user sees and can edit in Loci, " +
  "and each checkpoint id refers to that drawing's latest content, including the user's own edits. " +
  "get_elements returns exact native properties and the revision required by update_elements, which updates the specified fields of existing element IDs. " +
  "read_widget_context returns a compact overview rather than a complete native scene. " +
  "create_view with restoreCheckpoint is for additions/removals, and without restoreCheckpoint it starts a new drawing. " +
  "A remote Excalidraw server is a separate service and does not save a Loci canvas.";

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
const drawingCalls = new Map();

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
    const input = call?.base
      ? { id, baseId: call.base.id, ...patchAgainstBase(call.base.elements, elements) }
      : { id, elements, ...(call?.tool === "save_checkpoint" ? { replace: true } : {}) };
    const receipt = await callLoci("checkpoint.save", input);
    if (call) call.receipt = { ...receipt, checkpointId: id };
  },
};

async function hostTool(name, args = {}) {
  if (!args || typeof args !== "object" || Array.isArray(args)) throw new Error("Tool arguments must be an object");
  const fields = name === HOST_TOOL.name ? ["checkpointId"] : name === GET_ELEMENTS.name ? ["checkpointId", "elementIds"] : ["checkpointId", "expectedRevision", "updates"];
  if (Object.keys(args).some(key => !fields.includes(key))) throw new Error("Unknown canvas tool argument");
  const { checkpointId, ...input } = args;
  if (checkpointId !== undefined && typeof checkpointId !== "string") throw new Error("checkpointId must be a string");
  if (name !== HOST_TOOL.name && !checkpointId) throw new Error("checkpointId is required");
  const action = name === HOST_TOOL.name ? "context.read" : name === GET_ELEMENTS.name ? "elements.read" : "elements.update";
  const result = await callLoci(action, { ...(checkpointId ? { id: checkpointId } : {}), ...input });
  const content = [{ type: "text", text: result?.text ?? JSON.stringify(result) }];
  if (result?.saved) content.unshift({ type: "text", text: savedLink(result) });
  return { content, structuredContent: result };
}

function savedLink(receipt) {
  const title = receipt.title.replace(/\r?\n/g, " ").replace(/[\\[\]]/g, "\\$&");
  return `Saved to Loci: [${title}](${receipt.url}).`;
}

const write = (message) => process.stdout.write(`${JSON.stringify(message)}\n`);
const awaitingToolList = new Set();
const awaitingCanvasReference = new Set();

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
    if (message?.method === "tools/list" && hasId) awaitingToolList.add(message.id);
    if (message?.method !== "tools/call") return this.onmessage?.(message);
    const name = message.params?.name;
    if (hasId && (name === "read_me" || name === "create_view")) awaitingCanvasReference.add(message.id);
    if (name === UPLOAD_TOOL) {
      if (hasId) write({ jsonrpc: "2.0", id: message.id, result: { content: [{ type: "text", text: "Loci does not upload drawings to excalidraw.com." }], isError: true } });
      return;
    }
    if (!HOST_TOOLS.some(tool => tool.name === name)) {
      const call = { tool: name };
      if (hasId && name === "create_view") drawingCalls.set(message.id, call);
      return toolCalls.run(call, () => this.onmessage?.(message));
    }
    if (!hasId) return;
    hostTool(name, message.params?.arguments).then(
      (result) => write({ jsonrpc: "2.0", id: message.id, result }),
      (error) => write({ jsonrpc: "2.0", id: message.id, result: { content: [{ type: "text", text: String(error?.message ?? error) }], isError: true } }),
    );
  },
  async send(message) {
    if (awaitingToolList.delete(message?.id) && Array.isArray(message.result?.tools)) {
      const tools = message.result.tools.filter((tool) => tool?.name !== UPLOAD_TOOL).map((tool) => {
        if (tool.name === "create_view") return { ...tool, title: "Draw and Save Loci Canvas", description: `${tool.description}\n\n${LOCI_CANVAS_REFERENCE}`, annotations: { ...tool.annotations, readOnlyHint: false } };
        if (tool.name === "read_me") return { ...tool, title: "Read the Loci Canvas Reference", description: `${tool.description}\n\n${LOCI_CANVAS_REFERENCE}` };
        return tool;
      });
      message = { ...message, result: { ...message.result, tools: [...tools, ...HOST_TOOLS] } };
    }
    const call = drawingCalls.get(message?.id);
    drawingCalls.delete(message?.id);
    if (call && message.result && !message.result.isError) {
      if (!call.receipt?.saved) {
        message = { ...message, result: { content: [{ type: "text", text: "Loci did not confirm that the canvas was saved." }], isError: true } };
      } else {
        const content = (message.result.content ?? []).map((block) => block.type === "text"
          ? { ...block, text: block.text.replace(/^Diagram displayed! /, "") } : block);
        message = { ...message, result: { ...message.result, content: [{ type: "text", text: savedLink(call.receipt) }, ...content], structuredContent: { ...message.result.structuredContent, ...call.receipt } } };
      }
    }
    if (awaitingCanvasReference.delete(message?.id) && message.result && !message.result.isError) {
      const note = `Loci canvas capabilities: ${LOCI_CANVAS_REFERENCE}`;
      message = { ...message, result: { ...message.result, content: [...(message.result.content ?? []), { type: "text", text: note }] } };
    }
    write(message);
  },
  async close() { this.onclose?.(); },
};

await createServer(store).connect(transport);
