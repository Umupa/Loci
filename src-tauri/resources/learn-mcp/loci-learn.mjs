#!/usr/bin/env node
// Loci's built-in learning MCP server, over stdio. It holds no state and makes
// no decisions: every call goes to the Loci window that owns the agent session,
// which checks the rules of the learning map (see src/features/learn/bridge.ts).
// The control client below mirrors the one in ../excalidraw-mcp/loci-bridge.mjs.
import { randomUUID } from "node:crypto";
import net from "node:net";
import { createInterface } from "node:readline";

const REPLY_TIMEOUT_MS = 40_000;
const REPLY_MAX_CHARS = 8 * 1024 * 1024;

const text = { type: "string" };
const edge = {
  type: "object", additionalProperties: false, required: ["from", "to"],
  properties: {
    from: { ...text, description: "Node id or label" },
    to: { ...text, description: "Node id or label" },
    label: { ...text, maxLength: 40 },
  },
};
const source = {
  type: "object", additionalProperties: false,
  description: "Either a file inside the project ({path, page} for a PDF or {path, lines:[first,last]}), or a web page ({url, accessedAt:\"YYYY-MM-DD\"}).",
  properties: {
    path: text, page: { type: "integer", minimum: 1 },
    lines: { type: "array", minItems: 2, maxItems: 2, items: { type: "integer", minimum: 1 } },
    url: text, accessedAt: text,
  },
};

const TOOLS = [
  {
    name: "map_read", title: "Read the Learning Map",
    description:
      "Read the learner's learning map for this Loci project: their mission, every node with its state, the connections, anything the learner drew by hand, and the few nodes due for a revisit. " +
      "Call it at the start of every /learn turn and before any other loci_learn tool. " +
      "Pass nodeId for one node's history and the learner's own words about it. While a node is due for a revisit, what the learner said about it earlier, including the wording on its connections, is withheld until the revisit finishes. Pass stats:true for how well explanations have lasted.",
    inputSchema: { type: "object", additionalProperties: false, properties: { nodeId: text, stats: { type: "boolean" } } },
    annotations: { readOnlyHint: true },
  },
  {
    name: "map_init", title: "Start a Learning Map",
    description:
      "Create this project's learning map, once. `why` and every `success` entry must be passages the learner typed in this session, word for word: why they are learning this, and what they want to be able to do. " +
      "Ask the learner first. Loci refuses text the learner did not type.",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["subject", "why"],
      properties: {
        subject: { ...text, maxLength: 80, description: "Short name of the subject; it becomes the map's title" },
        why: text,
        success: { type: "array", maxItems: 5, items: text },
      },
    },
    annotations: { readOnlyHint: false, destructiveHint: false },
  },
  {
    name: "map_sketch", title: "Sketch Unexplored Nodes",
    description:
      "Add up to 3 unexplored (dashed) nodes beside a node the learner already has, to show what lies just past what they know. Loci chooses where they go. " +
      "A map holds at most 9 unexplored nodes: sketch only what is adjacent to the learner's knowledge and serves their mission, never an overview of the field. " +
      "Optional edges are proposals (dashed) until the learner states the connection themselves.",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["nodes"],
      properties: {
        near: { ...text, description: "Id or label of the node to place them beside" },
        nodes: { type: "array", minItems: 1, maxItems: 3, items: { ...text, maxLength: 60 }, description: "Labels: a name only, no explanation" },
        edges: { type: "array", maxItems: 6, items: edge },
      },
    },
    annotations: { readOnlyHint: false, destructiveHint: false },
  },
  {
    name: "map_record", title: "Record What the Learner Said",
    description:
      "Record what the learner said, drew or did. This is the only way a node becomes solid. " +
      "Evidence \"said\" (after you taught it) and \"prior\" (knowledge they brought) need `quote`: a passage the learner typed in this session, copied word for word. Loci checks it and refuses paraphrases, summaries and your own explanations. " +
      "Give an honest `verdict`: right, partly or wrong. A node becomes solid once the learner has explained it in their own words, even if only partly right; solid means explained, not mastered, so say \"recorded\" or \"explained\" and let tomorrow's revisit show whether the correction stuck. A wrong explanation is kept in the node's note and the node stays unexplored. Put what you corrected in `correction`. Cite `sources` for what you taught. " +
      "Edge labels are a few words lifted from the learner's own wording for how two nodes connect (at most 14 CJK characters or 28 letters). " +
      "kind \"judgment\" records a judgment about something real, with `quote`, `wrongIf` (the learner's words for what would prove them wrong) and `lookBackAt`. " +
      "Evidence \"drew\" takes in a shape the learner drew on the map (pass its id); edges may pass the id of an arrow they drew. " +
      "Evidence \"did\" marks an existing node as put to use; `detail` is your statement of what the learner did and how you checked it.",
    inputSchema: {
      type: "object", additionalProperties: false,
      properties: {
        nodes: {
          type: "array", maxItems: 12,
          items: {
            type: "object", additionalProperties: false,
            properties: {
              kind: { type: "string", enum: ["concept", "judgment"] },
              id: { ...text, description: "An existing node, or a shape the learner drew" },
              label: { ...text, maxLength: 60, description: "A name only. An existing node with this label is updated; otherwise a node is created" },
              near: { ...text, description: "Id or label of the node a new one is placed beside" },
              evidence: { type: "string", enum: ["said", "prior", "drew", "did"] },
              quote: text,
              verdict: { type: "string", enum: ["right", "partly", "wrong"] },
              sources: { type: "array", maxItems: 12, items: source },
              correction: text,
              wrongIf: text,
              lookBackAt: { ...text, description: "YYYY-MM-DD, in the future" },
              detail: text,
            },
          },
        },
        edges: {
          type: "array", maxItems: 24,
          items: { type: "object", additionalProperties: false, properties: { id: { ...text, description: "An arrow the learner drew, or one you proposed and they accept" }, ...edge.properties } },
        },
      },
    },
    annotations: { readOnlyHint: false, destructiveHint: false },
  },
  {
    name: "revisit", title: "Revisit a Node",
    description:
      "Revisit a node the learner explained before. phase \"start\" covers the map and returns the node to ask about: name only the node and ask the learner to explain it from memory, with no hints. " +
      "phase \"finish\" takes a passage of their answer, typed after the start, and your verdict: solid, shaky or gone. It reschedules the node and returns the learner's earlier words, to compare. " +
      "For a judgment whose look-back date has come, start returns what the learner wrote then, and finish records what happened in their words, with an optional `principle` they draw from it. " +
      "phase \"cancel\" ends a revisit the learner declined; nothing changes.",
    inputSchema: {
      type: "object", additionalProperties: false, required: ["phase", "nodeId"],
      properties: {
        phase: { type: "string", enum: ["start", "finish", "cancel"] },
        nodeId: text,
        quote: text,
        verdict: { type: "string", enum: ["solid", "shaky", "gone"] },
        principle: { type: "object", additionalProperties: false, required: ["label", "quote"], properties: { label: { ...text, maxLength: 60 }, quote: text } },
      },
    },
    annotations: { readOnlyHint: false, destructiveHint: false },
  },
];

/** One request to the Loci window that owns this agent session. */
function callLoci(action, input) {
  const endpoint = process.env.LOCI_APP_ENDPOINT;
  const token = process.env.LOCI_APP_TOKEN;
  if (!endpoint || !token)
    return Promise.reject(new Error("This learning server is not connected to Loci. Start the agent from a Loci session."));
  const split = endpoint.lastIndexOf(":");
  const host = endpoint.slice(0, split).replace(/^\[|\]$/g, "");
  const port = Number(endpoint.slice(split + 1));
  if (!net.isIP(host) || !(host === "::1" || host.startsWith("127.")) || !Number.isInteger(port))
    return Promise.reject(new Error("Loci learning access only connects to localhost."));
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
      socket.write(`${JSON.stringify({ token, namespace: "learn", action, input, requestId: randomUUID() })}\n`);
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
      else finish(new Error(typeof response?.error === "string" ? response.error : "Loci rejected the learning request."));
    });
  });
}

async function callTool(name, args = {}) {
  if (!args || typeof args !== "object" || Array.isArray(args)) throw new Error("Tool arguments must be an object");
  if (!TOOLS.some((tool) => tool.name === name)) throw new Error(`Unknown tool: ${name}`);
  let action = name.replace("_", ".");
  let input = args;
  if (name === "revisit") {
    const { phase, ...rest } = args;
    if (!["start", "finish", "cancel"].includes(phase)) throw new Error("phase must be start, finish or cancel");
    action = `revisit.${phase}`;
    input = rest;
  }
  const result = await callLoci(action, input);
  const content = [{ type: "text", text: typeof result?.text === "string" ? result.text : JSON.stringify(result) }];
  if (result?.saved && typeof result.url === "string") {
    const title = String(result.title ?? "Learning map").replace(/\r?\n/g, " ").replace(/[\\[\]]/g, "\\$&");
    content.unshift({ type: "text", text: `Saved to the learning map: [${title}](${result.url}). Include this link in your reply so the learner can open it.` });
  }
  return { content, ...(result && typeof result === "object" ? { structuredContent: result } : {}) };
}

const write = (message) => process.stdout.write(`${JSON.stringify(message)}\n`);

function receive(message) {
  const { id, method, params } = message ?? {};
  const answers = id !== undefined && id !== null;
  if (typeof method !== "string") return;
  if (method === "initialize") {
    const requested = typeof params?.protocolVersion === "string" ? params.protocolVersion : "2025-03-26";
    return write({ jsonrpc: "2.0", id, result: { protocolVersion: requested, capabilities: { tools: {} }, serverInfo: { name: "loci_learn", version: "1" } } });
  }
  if (!answers) return;
  if (method === "ping") return write({ jsonrpc: "2.0", id, result: {} });
  if (method === "tools/list") return write({ jsonrpc: "2.0", id, result: { tools: TOOLS } });
  if (method === "tools/call") {
    callTool(params?.name, params?.arguments).then(
      (result) => write({ jsonrpc: "2.0", id, result }),
      (error) => write({ jsonrpc: "2.0", id, result: { content: [{ type: "text", text: String(error?.message ?? error) }], isError: true } }),
    );
    return;
  }
  write({ jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } });
}

const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
lines.on("line", (line) => {
  if (!line.trim()) return;
  let message;
  try { message = JSON.parse(line); }
  catch { return write({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } }); }
  receive(message);
});
lines.on("close", () => process.exit(0));
