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

import { prepare, pending, watch, cleanup } from './permissions.js';

export const ALLOWED_MODES = ['plan', 'acceptEdits', 'default'];
const DEFAULT_MODE = 'plan';
const MAX_EVENTS = 4000;        // ring buffer per session
const MAX_MESSAGE_BYTES = 512 * 1024;

const sessions = new Map();     // sessionId -> OwnedSession

class OwnedSession {
  constructor({ cwd, model, permissionMode, sessionId, resume }) {
    this.id = sessionId;
    this.resumedFrom = resume ?? null;
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

    // The gate is prepared before the child exists, so its very first tool call
    // is already covered. A missing hook is reported, never worked around: a
    // panel that silently ran ungated would be worse than one that cannot run.
    this.gate = prepare(this.id);
    this.pendingPermissions = [];
    this.gateEvents = [];      // hook lifecycle, newest last
    this.unwatch = this.gate
      ? watch(this.id, (reqs) => {
        this.pendingPermissions = reqs;
        this.#emit({ type: 'permissions', pending: reqs });
      })
      : null;

    const args = [
      '-p', '--verbose',
      '--input-format', 'stream-json',
      '--output-format', 'stream-json',
      '--include-partial-messages',
      '--replay-user-messages',
      '--forward-subagent-text',
      // Gate decisions with the moment they happened. gate-log.tsv records the
      // same decisions but carries no timestamp, so for a session we own this
      // is the difference between "this happened at 13:42" and "this was in
      // the log when we looked".
      '--include-hook-events',
      '--session-id', this.id,
      '--permission-mode', this.permissionMode,
    ];
    // Continuing an existing conversation, never overwriting it. --fork-session
    // gives the continuation its own id; measured, the original transcript came
    // back byte-identical, which is the property that makes this safe to offer
    // for a session someone may still have open elsewhere.
    if (this.resumedFrom) args.push('--resume', this.resumedFrom, '--fork-session');
    if (this.model) args.push('--model', this.model);
    // Our own settings file in our own directory. The user's settings are never
    // read, written or merged.
    if (this.gate) args.push('--settings', this.gate.settingsPath);

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
      if (this.unwatch) { this.unwatch(); this.unwatch = null; }
      this.#emit({ type: 'exit', code, signal });
      // A spool outliving its session would leave stale requests behind for a
      // hook that will never run again.
      cleanup(this.id);
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
    if (rec?.type === 'system' && (rec.subtype === 'hook_started' || rec.subtype === 'hook_response')) {
      // The bridge's own hook is noise here: the panel already shows those as
      // permission cards, and listing them again would double every decision.
      const ours = typeof rec.hook_name === 'string' && this.gate;
      const ev = {
        at: Date.now(),
        phase: rec.subtype === 'hook_started' ? 'started' : 'finished',
        hookId: rec.hook_id ?? null,
        name: rec.hook_name ?? null,
        event: rec.hook_event ?? null,
        exitCode: rec.exit_code ?? null,
        outcome: rec.outcome ?? null,
        stderr: (rec.stderr ?? '').slice(0, 300) || null,
        ours,
      };
      this.gateEvents.push(ev);
      if (this.gateEvents.length > 500) this.gateEvents.shift();
    }
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
      resumedFrom: this.resumedFrom,
      state: this.state,
      startedAt: this.startedAt,
      turns: this.turns,
      costUsd: this.costUsd,
      exit: this.exit,
      lastError: this.lastError,
      events: this.seq,
      // Stated rather than implied: a session without a gate must say so.
      gated: Boolean(this.gate),
      gateWaitSeconds: this.gate?.waitSeconds ?? null,
      pendingPermissions: this.pendingPermissions,
      gateEvents: this.gateEvents.slice(-40),
    };
  }
}

export function createSession({ cwd, model, permissionMode, resume } = {}) {
  const dir = cwd || process.cwd();
  if (!fs.existsSync(dir)) return { ok: false, reason: `no such directory: ${dir}` };

  const mode = permissionMode ?? DEFAULT_MODE;
  if (!ALLOWED_MODES.includes(mode)) {
    // Allow-list, not deny-list: unknown modes are refused without this file
    // ever having to write down the dangerous ones.
    return { ok: false, reason: `permission mode not offered here: ${mode}` };
  }

  if (resume != null && !/^[A-Za-z0-9-]+$/.test(String(resume))) {
    return { ok: false, reason: 'the session to resume is not an identifier' };
  }

  const sessionId = randomUUID();
  const s = new OwnedSession({
    cwd: dir, model: model || null, permissionMode: mode, sessionId, resume: resume || null,
  });
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
