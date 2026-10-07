// Refreshes the pinned official Excalidraw MCP server that Loci ships.
// The server is used exactly as released; only its checkpoint store is Loci's.
//
//   node scripts/vendor-excalidraw-mcp.mjs           re-extract the pinned release
//   node scripts/vendor-excalidraw-mcp.mjs --check   verify the committed files
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// To upgrade: change the version and bundle hash, run this script, then run
// the bridge tests. A release that changes `createServer(store)` needs review.
const RELEASE = {
  version: '0.3.2',
  url: 'https://github.com/excalidraw/excalidraw-mcp/releases/download/v0.3.2/excalidraw-mcp-app.mcpb',
  sha256: '2b494012b5fee5937f9f7b86f04a76cc4a91ec843ee3339b93e4e15e415274ff',
};
// `server.js` reads `mcp-app.html` from its own directory.
const FILES = { 'dist/server.js': 'server.js', 'dist/mcp-app.html': 'mcp-app.html', 'manifest.json': 'manifest.json' };

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const target = path.join(root, 'src-tauri/resources/excalidraw-mcp');
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

function recorded() {
  const source = readFileSync(path.join(target, 'SOURCE'), 'utf8');
  return new Map([...source.matchAll(/^sha256 ([0-9a-f]{64}) {2}(\S+)$/gm)].map(match => [match[2], match[1]]));
}

if (process.argv.includes('--check')) {
  const hashes = recorded();
  for (const name of Object.values(FILES)) {
    const file = `official/${name}`;
    if (sha256(readFileSync(path.join(target, file))) !== hashes.get(file))
      throw new Error(`${file} does not match the hash recorded in SOURCE`);
  }
  console.log(`Excalidraw MCP ${RELEASE.version}: vendored files match SOURCE`);
} else {
  const response = await fetch(RELEASE.url);
  if (!response.ok) throw new Error(`Download failed: ${response.status} ${RELEASE.url}`);
  const bundle = Buffer.from(await response.arrayBuffer());
  if (sha256(bundle) !== RELEASE.sha256) throw new Error('Bundle hash does not match the pinned release');
  const work = mkdtempSync(path.join(tmpdir(), 'excalidraw-mcp-'));
  try {
    const archive = path.join(work, 'bundle.zip');
    writeFileSync(archive, bundle);
    // An .mcpb is a zip; bsdtar (macOS, Windows) reads it, GNU tar does not.
    try { execFileSync('unzip', ['-q', archive, '-d', work]); }
    catch { execFileSync('tar', ['-xf', archive, '-C', work]); }
    mkdirSync(path.join(target, 'official'), { recursive: true });
    const lines = [];
    for (const [from, name] of Object.entries(FILES)) {
      const bytes = readFileSync(path.join(work, from));
      writeFileSync(path.join(target, 'official', name), bytes);
      lines.push(`sha256 ${sha256(bytes)}  official/${name}`);
    }
    writeFileSync(path.join(target, 'SOURCE'), [
      'official/: the Excalidraw MCP server, copied unmodified from its release bundle.',
      `Source: ${RELEASE.url}`,
      `Version: ${RELEASE.version}`,
      `sha256 ${RELEASE.sha256}  excalidraw-mcp-app.mcpb`,
      ...lines,
      'License: MIT, as declared in official/manifest.json. The bundle inlines its',
      'npm dependencies, which carry their own notices inside server.js.',
      'Refresh with: node scripts/vendor-excalidraw-mcp.mjs',
      '',
    ].join('\n'));
    console.log(`Vendored Excalidraw MCP ${RELEASE.version} into ${path.relative(root, target)}`);
  } finally { rmSync(work, { recursive: true, force: true }); }
}
