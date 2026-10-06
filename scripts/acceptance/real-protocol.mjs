// Explicit live acceptance, separate from the deterministic test suite.
// Node replaces only the native process transport; protocol and provider code
// are imported from production. Every server response comes from the real CLI.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { build } from 'esbuild';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const workspace = process.argv[3] ?? await mkdtemp(path.join(tmpdir(), 'loci-live-'));
const mode = process.argv[2] ?? 'acp';
assert(['acp', 'codex-plan'].includes(mode), 'mode must be acp or codex-plan');
const buildDir = await mkdtemp(path.join(tmpdir(), 'loci-protocol-'));
const children = new Map();
const waiting = new Map();
const buffers = new Map();
const terminate = child => {
  if (!child || child.exitCode !== null) return;
  try {
    if (process.platform === 'win32') child.kill('SIGTERM');
    else process.kill(-child.pid, 'SIGTERM');
  } catch (error) { if (error.code !== 'ESRCH') throw error; }
};
const report = { mode, workspace, transport: 'real CLI pipes via Node; production protocol/provider', checks: [] };
const storage = new Map();
globalThis.localStorage = {
  getItem: key => storage.get(key) ?? null,
  setItem: (key, value) => storage.set(key, String(value)),
  removeItem: key => storage.delete(key),
};
const native = {
  resolveCodexBinary: async () => ({ path: 'codex' }),
  watchChild: (id, onLine, onExit) => {
    waiting.set(id, { onLine, onExit });
    for (const line of buffers.get(id) ?? []) onLine(line);
    buffers.delete(id);
  },
  unwatchChild: id => waiting.delete(id),
  spawnChild: async (id, command, args, cwd) => {
    const child = spawn(command, args, { cwd, detached: process.platform !== 'win32', stdio: ['pipe', 'pipe', 'pipe'] });
    children.set(id, child);
    child.stderr.resume(); // Do not print credentials, MCP URLs, or unrelated diagnostics.
    createInterface({ input: child.stdout }).on('line', line => {
      const listener = waiting.get(id);
      if (listener) listener.onLine(line);
      else buffers.set(id, [...(buffers.get(id) ?? []), line]);
    });
    child.on('exit', code => waiting.get(id)?.onExit?.(code));
    await new Promise((resolve, reject) => {
      child.once('spawn', resolve);
      child.once('error', reject);
    });
  },
  writeChild: (id, line) => new Promise((resolve, reject) => {
    const child = children.get(id);
    if (!child) return reject(new Error('No live child'));
    child.stdin.write(`${line}\n`, error => error ? reject(error) : resolve());
  }),
  killChild: async id => {
    terminate(children.get(id));
    children.delete(id);
    waiting.delete(id);
  },
};
globalThis.__lociAcceptanceNative = native;
await build({
  stdin: {
    contents: `export { AcpClient } from './src/integrations/harness/core/acp.ts';
export { sendCodexTurn, respondCodexQuestion, cancelCodexTurn, stopCodexSession } from './src/integrations/harness/providers/codex/codex.ts';
export { newSession } from './src/features/sessions/model/session.ts';
export { applyHarnessEvent } from './src/integrations/harness/core/apply.ts';`,
    resolveDir: root, loader: 'ts',
  },
  bundle: true, platform: 'node', format: 'esm', outfile: path.join(buildDir, 'live.mjs'),
  plugins: [{
    name: 'real-native-transport',
    setup(plugin) {
      plugin.onResolve({ filter: /(?:core\/child|^\.\/child)$/ }, () => ({ path: 'native', namespace: 'loci-live' }));
      plugin.onLoad({ filter: /.*/, namespace: 'loci-live' }, () => ({
        contents: `const n = globalThis.__lociAcceptanceNative;
export const { resolveCodexBinary, watchChild, unwatchChild, spawnChild, writeChild, killChild } = n;`,
        loader: 'js',
      }));
    },
  }],
});
const api = await import(pathToFileURL(path.join(buildDir, 'live.mjs')).href);
const check = (name, evidence) => {
  report.checks.push({ name, passed: true, evidence });
  console.log(`PASS ${name}: ${JSON.stringify(evidence)}`);
};
let watchdog;
try {
  watchdog = setTimeout(() => {
    console.error('FAIL live acceptance exceeded 6 minutes');
    for (const child of children.values()) terminate(child);
    process.exitCode = 1;
  }, 360_000);
  if (mode === 'acp') {
    let text = '';
    let chunks = 0;
    let updates = 0;
    const updateTypes = [];
    const id = 'loci-live-acp';
    const client = new api.AcpClient(id, {
      onNotification(method, params) {
        if (method !== 'session/update') return;
        updates++;
        const update = params.update;
        updateTypes.push({ kind: update?.sessionUpdate, contentType: update?.content?.type,
          text: update?.content?.type === 'text' ? update.content.text : undefined });
        if (update?.sessionUpdate === 'agent_message_chunk' && update.content?.type === 'text') {
          text += update.content.text;
          chunks++;
        }
      },
      async onRequest(requestId, method) {
        // This smoke performs no filesystem/tool work. Unexpected permission
        // requests must be cancelled, rather than granting broad access.
        if (method === 'session/request_permission')
          await client.respond(requestId, { outcome: { outcome: 'cancelled' } });
        else await client.respondError(requestId, { code: -32601, message: 'Not supported by acceptance client' });
      },
    });
    native.watchChild(id, line => client.pushLine(line), () => client.close());
    await native.spawnChild(id, 'codex-acp', [], workspace);
    const initialize = await client.request('initialize', {
      protocolVersion: 1,
      clientCapabilities: { fs: { readTextFile: false, writeTextFile: false }, terminal: false },
      clientInfo: { name: 'loci-live-acceptance', version: '0.1.0' },
    }, 30_000);
    assert.equal(initialize.protocolVersion, 1);
    check('ACP initialize', { version: initialize.protocolVersion, agent: initialize.agentInfo?.name });
    const session = await client.request('session/new', { cwd: workspace, mcpServers: [] }, 60_000);
    assert.equal(typeof session.sessionId, 'string');
    check('ACP session/new', { sessionId: session.sessionId });
    report.acpModels = session.models;
    report.acpConfigOptions = session.configOptions;
    const offered = session.models?.availableModels ?? [];
    const compatible = offered.find(model => model.modelId === 'gpt-5.4')
      ?? offered.find(model => model.modelId !== 'gpt-6.1-sol');
    if (compatible) {
      await client.request('session/set_model', { sessionId: session.sessionId, modelId: compatible.modelId }, 30_000);
      check('ACP choose advertised model', compatible.modelId);
    }
    const answer = await client.request('session/prompt', {
      sessionId: session.sessionId,
      prompt: [{ type: 'text', text: 'Do not call any tools. Reply exactly LOCI-ACP-LIVE-20261006.' }],
    }, 150_000);
    report.response = { answer, chunks, updates, text, updateTypes };
    assert(text.includes('LOCI-ACP-LIVE-20261006'));
    assert(chunks > 0);
    check('ACP real response and streaming', { stopReason: answer.stopReason, chunks, updates, text });
    await assert.rejects(client.request('loci/unknown-method', {}, 10_000));
    check('ACP remote method error', 'remote error rejected by production client');
    text = '';
    const pending = client.request('session/prompt', {
      sessionId: session.sessionId,
      prompt: [{ type: 'text', text: 'Do not call tools. Output 5000 numbered lines of a long explanation.' }],
    }, 60_000);
    pending.catch(() => undefined);
    await new Promise(resolve => setTimeout(resolve, 1500));
    await client.notify('session/cancel', { sessionId: session.sessionId });
    const cancelled = await pending;
    assert.equal(cancelled.stopReason, 'cancelled');
    check('ACP cancellation', cancelled.stopReason);
    client.close();
  } else {
    const id = 'loci-live-codex-plan';
    const model = process.argv[4] ?? 'codex:gpt-6.1-sol';
    let session = api.newSession('codex', workspace, model, 'supervised', { effort: 'low' });
    session.id = id;
    const events = [];
    await api.sendCodexTurn({
      sessionId: id, cwd: workspace, model, modelSettings: { effort: 'low' },
      runtimeMode: 'supervised', intent: 'plan', attachments: [],
      text: 'This is a read-only protocol acceptance. Do not read files or execute commands. Use request_user_input to ask me to choose Blue or Green, then use update_plan to track three steps (choose color, draft plan, finish) and mark them done. Return a proposed plan headed LOCI-PLAN-LIVE-20261006 containing my selected color. If a tool is unavailable say so; do not pretend to have called it.',
      onEvent(event) {
        events.push(event);
        session = api.applyHarnessEvent(session, event);
        if (event.type === 'question.asked') {
          const answers = Object.fromEntries(event.questions.map(q => [q.id, [q.options.find(o => o.label.includes('Blue'))?.id ?? q.options[0].id]]));
          api.respondCodexQuestion(id, event.requestId, { kind: 'answered', answers });
        }
      },
    });
    const text = events.filter(e => e.type === 'message.delta').map(e => e.text).join('');
    check('Codex Plan real response', { providerSessionId: session.providerSessionId, text });
    report.events = events;
    report.session = session;
    const missing = [];
    for (const type of ['question.asked', 'question.resolved', 'tasks.updated', 'plan']) {
      const count = events.filter(event => event.type === type).length;
      if (count) check(`Codex ${type}`, count);
      else {
        missing.push(type);
        report.checks.push({ name: `Codex ${type}`, passed: false, evidence: 'No real event produced' });
      }
    }
    assert.equal(missing.length, 0, `No real ${missing.join(', ')} event`);
    await api.stopCodexSession(id);
  }
} catch (error) {
  report.failure = error.message;
  console.error(`FAIL ${error.message}`);
  process.exitCode = 1;
} finally {
  clearTimeout(watchdog);
  for (const child of children.values()) terminate(child);
  const reportPath = path.join(workspace, `${mode}-acceptance.json`);
  await writeFile(reportPath, JSON.stringify(report, null, 2));
  console.log(`Report: ${reportPath}`);
}
