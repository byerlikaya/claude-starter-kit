// Raw shells, off by default.
//
// This is the one thing in the panel that steps outside the kit's own gates.
// A command typed here does not pass guard-bash.sh, because nothing in a raw
// pty passes a PreToolUse hook — there is no tool call to intercept. The kit's
// whole argument is that discipline is held at the tool boundary, so a shell
// with no boundary is a deliberate exception and is treated as one: it needs
// --enable-pty, it is never the default, and the UI says so on the screen.
//
// Everything else the panel offers routes shell work through a session's Bash
// tool, where the gates do apply.

import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BRIDGE = path.join(HERE, 'pty-bridge.py');
const MAX_BUFFER = 256 * 1024;   // replay window per terminal
const MAX_TERMINALS = 8;

const terminals = new Map();
let enabled = false;

export function enable(v) { enabled = Boolean(v); }
export function isEnabled() { return enabled; }

/** Whether a pty could be started here at all, and why not when it could not. */
export function capability() {
  if (process.platform === 'win32') {
    // Python's pty module is Unix-only. Saying so is better than a terminal
    // that opens and never speaks.
    return { available: false, reason: 'the pty module is Unix-only; Windows needs ConPTY' };
  }
  if (!fs.existsSync(BRIDGE)) return { available: false, reason: 'the bridge script is missing' };
  return { available: true };
}

class Terminal {
  constructor({ cwd, rows, cols, shell }) {
    this.id = randomUUID();
    this.cwd = cwd;
    this.rows = rows;
    this.cols = cols;
    // Bytes, not base64 text. Concatenating two base64 strings produces
    // something that is not base64 at all once either carries padding — the
    // replay arrived with '==' in the middle and atob threw on it, leaving the
    // screen blank. Decode on arrival, encode once on replay.
    this.buffer = Buffer.alloc(0);
    this.subscribers = new Set();
    this.state = 'running';
    this.exitCode = null;
    this.startedAt = Date.now();
    this.carry = '';

    this.child = spawn('python3', [BRIDGE, cwd, shell, String(rows), String(cols)], {
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    this.child.stdout.setEncoding('utf8');
    this.child.stdout.on('data', (c) => this.#ingest(c));
    this.child.stderr.setEncoding('utf8');
    this.child.stderr.on('data', (t) => { this.lastError = String(t).slice(0, 1000); });
    this.child.on('exit', () => { this.state = 'exited'; this.#push({ t: 'exit', code: this.exitCode ?? -1 }); });
    this.child.on('error', (e) => { this.state = 'failed'; this.lastError = String(e?.message ?? e); });
  }

  #ingest(chunk) {
    const text = this.carry + chunk;
    const lines = text.split('\n');
    this.carry = lines.pop() ?? '';
    for (const line of lines) {
      if (!line.trim()) continue;
      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      if (msg.t === 'out') {
        this.buffer = Buffer.concat([this.buffer, Buffer.from(msg.d, 'base64')]);
        if (this.buffer.length > MAX_BUFFER) this.buffer = this.buffer.subarray(-MAX_BUFFER);
      }
      if (msg.t === 'exit') { this.state = 'exited'; this.exitCode = msg.code; }
      this.#push(msg);
    }
  }

  #push(msg) {
    for (const fn of this.subscribers) {
      try { fn(msg); } catch { /* a dead subscriber must not stall the stream */ }
    }
  }

  subscribe(fn, { replay = true } = {}) {
    if (replay && this.buffer.length) fn({ t: 'out', d: this.buffer.toString('base64') });
    this.subscribers.add(fn);
    return () => this.subscribers.delete(fn);
  }

  write(base64) {
    if (this.state !== 'running') return { ok: false, reason: `terminal has ${this.state}` };
    try { this.child.stdin.write(`${JSON.stringify({ t: 'in', d: base64 })}\n`); } catch (e) {
      return { ok: false, reason: String(e?.message ?? e) };
    }
    return { ok: true };
  }

  resize(rows, cols) {
    this.rows = rows; this.cols = cols;
    try { this.child.stdin.write(`${JSON.stringify({ t: 'size', rows, cols })}\n`); } catch { /* gone */ }
    return { ok: true };
  }

  close() {
    try { this.child.stdin.write(`${JSON.stringify({ t: 'kill' })}\n`); } catch { /* gone */ }
    setTimeout(() => { try { this.child.kill('SIGKILL'); } catch { /* gone */ } }, 2000).unref();
    this.state = 'exited';
    return { ok: true };
  }

  summary() {
    return {
      id: this.id, cwd: this.cwd, rows: this.rows, cols: this.cols,
      state: this.state, exitCode: this.exitCode, startedAt: this.startedAt,
      lastError: this.lastError ?? null,
    };
  }
}

export function create({ cwd, rows = 30, cols = 100, shell } = {}) {
  if (!enabled) return { ok: false, reason: 'raw terminals are off — start the server with --enable-pty' };
  const cap = capability();
  if (!cap.available) return { ok: false, reason: cap.reason };
  if (!cwd || !fs.existsSync(cwd)) return { ok: false, reason: `no such directory: ${cwd}` };
  if (terminals.size >= MAX_TERMINALS) return { ok: false, reason: `at most ${MAX_TERMINALS} terminals` };

  const t = new Terminal({
    cwd,
    rows: clampInt(rows, 4, 200, 30),
    cols: clampInt(cols, 20, 500, 100),
    shell: shell || process.env.SHELL || '/bin/sh',
  });
  terminals.set(t.id, t);
  return { ok: true, terminal: t };
}

function clampInt(v, lo, hi, dflt) {
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : dflt;
}

export function get(id) { return terminals.get(id) ?? null; }
export function list() { return [...terminals.values()].map((t) => t.summary()); }
export function closeAll() { for (const t of terminals.values()) t.close(); }
export const _internals = { BRIDGE, MAX_TERMINALS };
