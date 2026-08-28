// Sessions the panel owns.
//
// An owned session is a `claude -p` child driven over stdin/stdout in
// stream-json. It is given a session id up front, which means it writes its
// transcript to the same place every other session does — so the canvas needs
// no special case: the existing file-watched graph reads it like any other.
// Only the conversation itself comes from the child's stdout, because that is
// the one thing the file does not carry live.
//
// Permission modes are allow-listed, never deny-listed. A list of forbidden
// modes would have to name them, and a panel that names a bypass is one
// grep away from offering it.

import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';

export const ALLOWED_MODES = ['plan', 'acceptEdits', 'default'];
const DEFAULT_MODE = 'plan';
const MAX_EVENTS = 4000;        // ring buffer per session
const MAX_MESSAGE_BYTES = 512 * 1024;

const sessions = new Map();     // sessionId -> OwnedSession

class OwnedSession {
  constructor({ cwd, model, permissionMode, sessionId }) {
    this.id = sessionId;
    this.cwd = cwd;
    this.model = model ?? null;
    this.permissionMode = permissionMode;
    this.startedAt = Date.now();
    this.state = 'starting';    // starting | idle | working | exited | failed
    this.events = [];
    this.seq = 0;
    this.subscribers = new Set();
    this.carry = '';
    this.exit = null;
    this.lastError = null;
    this.turns = 0;
    this.costUsd = 0;

    const args = [
      '-p', '--verbose',
      '--input-format', 'stream-json',
      '--output-format', 'stream-json',
      '--include-partial-messages',
      '--replay-user-messages',
      '--forward-subagent-text',
      '--session-id', this.id,
      '--permission-mode', this.permissionMode,
    ];
    if (this.model) args.push('--model', this.model);

    this.child = spawn('claude', args, {
      cwd: this.cwd,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: process.env,
    });

    this.child.stdout.setEncoding('utf8');
    this.child.stdout.on('data', (chunk) => this.#ingest(chunk));

    this.child.stderr.setEncoding('utf8');
    this.child.stderr.on('data', (t) => {
      this.lastError = String(t).slice(0, 2000);
      this.#emit({ type: 'stderr', text: this.lastError });
    });

    this.child.on('error', (e) => {
      this.state = 'failed';
      this.lastError = String(e?.message ?? e);
      this.#emit({ type: 'fault', reason: this.lastError });
    });

    this.child.on('exit', (code, signal) => {
      this.state = 'exited';
      this.exit = { code, signal };
      this.#emit({ type: 'exit', code, signal });
    });
  }

  #ingest(chunk) {
    const text = this.carry + chunk;
    const lines = text.split('\n');
    this.carry = lines.pop() ?? '';
    for (const line of lines) {
      if (!line.trim()) continue;
      let rec;
      try { rec = JSON.parse(line); } catch { continue; }
      this.#absorb(rec);
      this.#emit(rec);
    }
  }

  // State the UI needs but the raw stream only implies.
  #absorb(rec) {
    if (rec?.type === 'system' && rec.subtype === 'init') this.state = 'idle';
    else if (rec?.type === 'stream_event' && rec.event?.type === 'message_start') this.state = 'working';
    else if (rec?.type === 'result') {
      this.state = 'idle';
      this.turns = rec.num_turns ?? this.turns;
      if (typeof rec.total_cost_usd === 'number') this.costUsd = rec.total_cost_usd;
    }
  }

  #emit(rec) {
    const ev = { seq: (this.seq += 1), at: Date.now(), rec };
    this.events.push(ev);
    if (this.events.length > MAX_EVENTS) this.events.splice(0, this.events.length - MAX_EVENTS);
    for (const fn of this.subscribers) {
      try { fn(ev); } catch { /* a dead subscriber must not stall the stream */ }
    }
  }

  /** Replay from `after`, then follow. Returns an unsubscribe function. */
  subscribe(fn, after = 0) {
    for (const ev of this.events) if (ev.seq > after) fn(ev);
    this.subscribers.add(fn);
    return () => this.subscribers.delete(fn);
  }

  send(text) {
    if (this.state === 'exited' || this.state === 'failed') {
      return { ok: false, reason: `session has ${this.state}` };
    }
    const body = String(text ?? '');
    if (!body.trim()) return { ok: false, reason: 'empty message' };
    if (Buffer.byteLength(body, 'utf8') > MAX_MESSAGE_BYTES) {
      return { ok: false, reason: 'message too large' };
    }
    const line = `${JSON.stringify({ type: 'user', message: { role: 'user', content: body } })}\n`;
    try {
      this.child.stdin.write(line);
    } catch (e) {
      return { ok: false, reason: String(e?.message ?? e) };
    }
    this.state = 'working';
    return { ok: true };
  }

  stop() {
    try { this.child.stdin.end(); } catch { /* already closed */ }
    try { this.child.kill('SIGTERM'); } catch { /* already gone */ }
    // A child that ignores SIGTERM still has to go; the panel promised to stop it.
    setTimeout(() => { try { this.child.kill('SIGKILL'); } catch { /* gone */ } }, 4000).unref();
    return { ok: true };
  }

  summary() {
    return {
      sessionId: this.id,
      cwd: this.cwd,
      model: this.model,
      permissionMode: this.permissionMode,
      state: this.state,
      startedAt: this.startedAt,
      turns: this.turns,
      costUsd: this.costUsd,
      exit: this.exit,
      lastError: this.lastError,
      events: this.seq,
    };
  }
}

export function createSession({ cwd, model, permissionMode } = {}) {
  const dir = cwd || process.cwd();
  if (!fs.existsSync(dir)) return { ok: false, reason: `no such directory: ${dir}` };

  const mode = permissionMode ?? DEFAULT_MODE;
  if (!ALLOWED_MODES.includes(mode)) {
    // Allow-list, not deny-list: unknown modes are refused without this file
    // ever having to write down the dangerous ones.
    return { ok: false, reason: `permission mode not offered here: ${mode}` };
  }

  const sessionId = randomUUID();
  const s = new OwnedSession({ cwd: dir, model: model || null, permissionMode: mode, sessionId });
  sessions.set(sessionId, s);
  return { ok: true, session: s };
}

export function getSession(id) { return sessions.get(id) ?? null; }

export function listSessionsOwned() {
  return [...sessions.values()].map((s) => s.summary());
}

/** Drop finished sessions that nobody is watching, so the map does not grow. */
export function reap(maxAgeMs = 30 * 60 * 1000) {
  const now = Date.now();
  for (const [id, s] of sessions) {
    const dead = s.state === 'exited' || s.state === 'failed';
    if (dead && !s.subscribers.size && now - s.startedAt > maxAgeMs) sessions.delete(id);
  }
}

export function stopAll() {
  for (const s of sessions.values()) {
    if (s.state !== 'exited' && s.state !== 'failed') s.stop();
  }
}
