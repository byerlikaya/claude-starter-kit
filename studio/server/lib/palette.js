// Node colours.
//
// The kit's agents already declare a colour in their frontmatter, and
// packaging/gen-network.py already picked hex values for the README diagrams.
// Reading both means the live panel and the static diagrams are one system
// rather than two palettes that drift apart.
//
// An agent type nobody declared gets a neutral grey and a marked flag. Guessing
// a colour would make an unknown agent look like a known one, which is the
// visual form of the thing this project refuses to do.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const AGENTS_DIR = path.resolve(HERE, '..', '..', '..', 'claude-starter', 'agents');

// The names agents declare, mapped onto gen-network.py's hex values.
const NAMED = {
  green: '#35c874',
  cyan: '#26c6e6',
  blue: '#5b8cff',
  orange: '#f2a65a',
  purple: '#b07cf6',
  red: '#ff8a4d',
  pink: '#ffbc8a',
  yellow: '#db5f1c',
};

// Claude Code's built-in agent types are not kit components and declare
// nothing, so they take the diagram's "core" tones.
const BUILTIN = {
  Explore: '#26c6e6',
  Plan: '#a874f5',
  'general-purpose': '#c79bff',
  claude: '#5b8cff',
  'code-simplifier': '#84e6b0',
  'statusline-setup': '#94a3c8',
  'claude-code-guide': '#8659ee',
};

const UNKNOWN = '#94a3c8';

let cached = null;

function readKitAgents() {
  const out = {};
  let files;
  try { files = fs.readdirSync(AGENTS_DIR); } catch { return out; }

  for (const f of files) {
    if (!f.endsWith('.md')) continue;
    let src;
    try { src = fs.readFileSync(path.join(AGENTS_DIR, f), 'utf8'); } catch { continue; }
    // Frontmatter only: stop at the closing fence so a colon in the body cannot
    // masquerade as a field.
    const fm = src.split(/^---$/m)[1] ?? '';
    const name = fm.match(/^name:\s*(.+)$/m)?.[1]?.trim();
    const color = fm.match(/^color:\s*(.+)$/m)?.[1]?.trim();
    if (name) out[name] = { color: color ?? null, hex: color ? (NAMED[color] ?? null) : null, source: 'kit' };
  }
  return out;
}

export function palette() {
  if (cached) return cached;
  const kit = readKitAgents();
  const map = {};
  for (const [name, v] of Object.entries(kit)) {
    map[name] = { hex: v.hex ?? UNKNOWN, declared: v.color, known: Boolean(v.hex), source: 'kit' };
  }
  for (const [name, hex] of Object.entries(BUILTIN)) {
    if (!map[name]) map[name] = { hex, declared: null, known: true, source: 'builtin' };
  }
  cached = { map, unknown: UNKNOWN, named: NAMED, kitAgents: Object.keys(kit).length };
  return cached;
}

export function colorFor(agentType) {
  const p = palette();
  return p.map[agentType]?.hex ?? p.unknown;
}
