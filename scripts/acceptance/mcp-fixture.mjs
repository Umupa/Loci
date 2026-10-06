// Disposable local stdio MCP service. No file/network access is exposed.
import { appendFileSync } from 'node:fs';
import { createInterface } from 'node:readline';

const marker = process.argv[2];
const logPath = process.argv[3];
if (!marker?.startsWith('LOCI-MCP-') || !logPath)
  throw new Error('Expected an acceptance marker and log path');

const send = object => process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', ...object })}\n`);
createInterface({ input: process.stdin }).on('line', line => {
  let request;
  try { request = JSON.parse(line); } catch { return; }
  const { id, method, params } = request;
  if (id == null) return;
  if (method === 'initialize') {
    send({ id, result: {
      protocolVersion: params.protocolVersion,
      capabilities: { tools: {} },
      serverInfo: { name: 'loci-qa', version: '1.0.0' },
    } });
  } else if (method === 'ping') send({ id, result: {} });
  else if (method === 'tools/list') {
    send({ id, result: { tools: [{
      name: 'acceptance_marker',
      description: 'Return the marker proving this local acceptance service was called.',
      inputSchema: { type: 'object', properties: {}, additionalProperties: false },
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    }] } });
  } else if (method === 'tools/call' && params.name === 'acceptance_marker') {
    appendFileSync(logPath, `${JSON.stringify({ method, tool: params.name, marker, at: Date.now() })}\n`);
    send({ id, result: { content: [{ type: 'text', text: marker }], isError: false } });
  } else send({ id, error: { code: -32601, message: 'Unknown acceptance method' } });
});
