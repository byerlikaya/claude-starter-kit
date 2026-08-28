// Sessions reachable elsewhere.
//
// A peer on another machine is visible only to a session connected to Remote
// Control — measured: a headless session's ListAgents returns three local peers
// where a connected one returns eight, and passing --remote-control to a
// headless session does not change that, because the flag starts an
// INTERACTIVE session.
//
// So the panel does not try to be that session. It reads what one already
// wrote: an interactive session's ListAgents result lands in its transcript as
// a tool_result, which is structured text on disk rather than a screen to
// scrape. That makes this a SNAPSHOT — the roster as it stood when some
// connected session last asked — and it is labelled that way everywhere,
// because a stale list drawn as a live one is the kind of lie this panel is
// built to avoid.

import fs from 'node:fs';
import path from 'node:path';

import { allProjectDirs } from './projects.js';

const SCAN_FILES = 40;          // most recently written transcripts
const TAIL_BYTES = 2 * 1024 * 1024;

/** Parse the block ListAgents prints. */
export function parseRoster(text) {
  if (!text || !text.includes('Peer sessions')) return null;

  const self = text.match(/This session is (\S+) \[([0-9a-f]+)\]/);
  const peers = [];
  // "  name [hash]  ·  kind  ·  status  ·  started 3h ago"
  const re = /^\s{2,}(\S+)\s+\[([0-9a-f]+)\]\s+·\s+(.+)$/gm;
  let m;
  while ((m = re.exec(text)) !== null) {
    const parts = m[3].split('·').map((x) => x.trim()).filter(Boolean);
    peers.push({
      name: m[1],
      ref: m[2],
      kind: parts[0] ?? null,
      status: parts[1] ?? null,
      // Everything after is free text ("started 3h ago"); kept, not parsed into
      // a time it might not be.
      note: parts.slice(2).join(' · ') || null,
      remote: /remote control/i.test(parts[0] ?? ''),
    });
  }
  if (!peers.length) return null;
  return { self: self ? { name: self[1], ref: self[2] } : null, peers };
}

function readTail(file, size) {
  let fd;
  try {
    fd = fs.openSync(file, 'r');
    const len = Math.min(size, TAIL_BYTES);
    const buf = Buffer.allocUnsafe(len);
    fs.readSync(fd, buf, 0, len, Math.max(0, size - len));
    return buf.toString('utf8');
  } catch {
    return '';
  } finally {
    if (fd !== undefined) try { fs.closeSync(fd); } catch { /* gone */ }
  }
}

/**
 * The most recent roster any session recorded.
 *
 * Returns not-measured rather than an empty list when nothing has asked yet:
 * "no session has run ListAgents" and "you have no peers" are different facts.
 */
export function remoteRoster() {
  const files = [];
  for (const dir of allProjectDirs()) {
    let entries;
    try { entries = fs.readdirSync(dir); } catch { continue; }
    for (const e of entries) {
      if (!e.endsWith('.jsonl')) continue;
      const p = path.join(dir, e);
      try {
        const st = fs.statSync(p);
        files.push({ path: p, mtime: st.mtimeMs, size: st.size, sessionId: e.slice(0, -6) });
      } catch { /* raced */ }
    }
  }
  files.sort((a, b) => b.mtime - a.mtime);

  let best = null;
  for (const f of files.slice(0, SCAN_FILES)) {
    const text = readTail(f.path, f.size);
    if (!text.includes('Peer sessions')) continue;

    // The block lives INSIDE a JSON string, so its line breaks are the two
    // characters \\n rather than real ones. Reading the raw tail with a
    // line-anchored regex found nothing at all, which is how this was caught:
    // the records have to be parsed, not grepped.
    for (const line of text.split('\n')) {
      if (!line.includes('Peer sessions') || !line.startsWith('{')) continue;
      let rec;
      try { rec = JSON.parse(line); } catch { continue; }

      const chunks = [];
      const content = rec?.message?.content;
      if (typeof content === 'string') chunks.push(content);
      else if (Array.isArray(content)) {
        for (const c of content) {
          if (typeof c?.text === 'string') chunks.push(c.text);
          const inner = c?.content;
          if (typeof inner === 'string') chunks.push(inner);
          else if (Array.isArray(inner)) for (const x of inner) if (typeof x?.text === 'string') chunks.push(x.text);
        }
      }

      for (const chunk of chunks) {
        const parsed = parseRoster(chunk);
        if (!parsed) continue;
        // Prefer the roster that actually saw remote machines: a local-only one
        // is a session that was not connected, and reporting it as the answer
        // would say the peers had gone away.
        const remotes = parsed.peers.filter((p) => p.remote).length;
        const cand = { ...parsed, sessionId: f.sessionId, at: f.mtime, remotes };
        if (!best || remotes > best.remotes || (remotes === best.remotes && cand.at > best.at)) best = cand;
      }
    }
  }

  if (!best) {
    return {
      measured: false,
      reason: 'no session on this machine has recorded a peer list yet — run /list-agents in a session connected to Remote Control',
      peers: [],
    };
  }

  return {
    measured: true,
    // Said plainly: this is when a session last looked, not now.
    seenAt: best.at,
    seenBy: best.sessionId,
    self: best.self,
    peers: best.peers,
    remotes: best.remotes,
    live: false,
  };
}
