// instance.js — let a second session find the panel that is already running.
//
// WHY THIS EXISTS. The panel printed its tokenised URL once, to the stdout of whoever started it, and kept the
// token nowhere else. So a second session that wanted the SAME panel had no way in: it could see the port was
// taken, but not that the holder was our own panel, and not what URL would open it. Measured in the field —
// port 7777 was held by another session's csk-studio, the user asked for the panel, and the answer was a dead
// end. The server said "try --port 7778", 7778 was held by something unrelated, and the command's own rule is
// to retry once. Two ports, no panel, and a running instance nobody could reach.
//
// WHAT IT WRITES. One small JSON file per listening port, 0600, under the same runtime directory ensure-node.sh
// already owns. It holds the token, which is the part that matters and the part that decides the mode: this is
// a credential, so it is written to $HOME and never into the repo, where a stray `git add -A` would publish it.
//
// A STATE FILE IS A CLAIM, NOT A FACT. Processes are killed, machines lose power, and a file outlives both, so
// nothing here trusts what it reads. A record is believed only when the port answers /api/health with the token
// it names AND reports the pid it names. Anything else is treated as stale and removed, which also means a
// crashed panel cleans itself up the next time anyone looks.
import fs from 'node:fs';
import http from 'node:http';
import fsp from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';

// Deliberately the same directory ensure-node.sh uses, and overridden by the same variable: one place under
// $HOME that the panel owns, that a user can delete wholesale, and that no installer has to know about.
export function runtimeDir() {
  return process.env.CSK_STUDIO_RUNTIME || path.join(os.homedir(), '.claude', 'studio-runtime');
}

export function statePath(port) {
  return path.join(runtimeDir(), `instance-${port}.json`);
}

// 0600 twice: in the open flags, and again with chmod. The flag alone loses to a permissive umask on some
// systems, and chmod alone leaves a window where the token sits world-readable.
//
// ON WINDOWS THIS IS NOT 0600 AND SHOULD NOT BE CALLED IT. POSIX mode bits are advisory there; what actually
// protects the file is the ACL it inherits from the user's profile directory. Measured with icacls on Windows
// 11: the record carries SYSTEM, Administrators and the owning user, all inherited, and no Everyone or Users
// entry — so another standard user cannot read it, and a local administrator can. That is weaker than 0600,
// which is why it is written down rather than rounded off, and why it is not the only defence: the panel
// listens on loopback and the token is regenerated every run.
export async function writeState(port, { token, name, pid = process.pid } = {}) {
  const dir = runtimeDir();
  await fsp.mkdir(dir, { recursive: true, mode: 0o700 });
  const body = JSON.stringify({ pid, port, token, name, startedAt: new Date().toISOString() }, null, 2);
  const file = statePath(port);
  await fsp.writeFile(file, body, { mode: 0o600, flag: 'w' });
  await fsp.chmod(file, 0o600).catch(() => {});
  return file;
}

export async function readState(port) {
  try {
    const raw = await fsp.readFile(statePath(port), 'utf8');
    const s = JSON.parse(raw);
    if (!s || typeof s.token !== 'string' || !s.token) return null;
    if (Number(s.port) !== Number(port)) return null;   // a file renamed by hand is not a record of this port
    return s;
  } catch {
    return null;
  }
}

export async function clearState(port) {
  await fsp.rm(statePath(port), { force: true }).catch(() => {});
}

// Synchronous twin, for process exit. `process.on('exit')` runs no promises — an async unlink there is queued
// and then dropped when the event loop stops, which would leave exactly the stale file this module refuses to
// trust. Learned by leaving one behind.
export function clearStateSync(port) {
  try { fs.rmSync(statePath(port), { force: true }); } catch { /* exiting anyway */ }
}

// Ask the port whether it is ours. A short timeout because this sits between the user and an error message:
// the interesting answers (a live local server, or nothing at all) both arrive in milliseconds, and anything
// slower is not something to wait on while someone is watching a prompt.
//
// node:http rather than fetch, and that is not style. fetch is a GLOBAL, and a global can be replaced: the
// panel's own offline suite installs a DOM stub so the browser modules can be exercised under Node, and that
// stub owns `fetch`. The first version of this function used it and the suite reported a live panel as
// unreachable -- the harness was wrong, not the code, which is the failure this repo has been bitten by
// before. A module that reaches for a global is a module whose behaviour depends on who else is loaded.
export function probe(port, token, { timeoutMs = 1500, host = '127.0.0.1' } = {}) {
  return new Promise((resolve) => {
    let settled = false;
    const done = (v) => { if (!settled) { settled = true; resolve(v); } };
    const req = http.request(
      { host, port, path: `/api/health?token=${encodeURIComponent(token)}`, method: 'GET', timeout: timeoutMs },
      (res) => {
        if (res.statusCode !== 200) { res.resume(); return done(null); }
        let body = '';
        res.setEncoding('utf8');
        res.on('data', (c) => { body += c; if (body.length > 64 * 1024) req.destroy(); });
        res.on('end', () => {
          try {
            const j = JSON.parse(body);
            done(j && j.ok ? j : null);
          } catch { done(null); }
        });
      },
    );
    req.on('timeout', () => { req.destroy(); done(null); });
    req.on('error', () => done(null));
    req.end();
  });
}

// The whole point, in one call: "port N is busy — is it us?"
//
// Returns { url, pid, name } when a panel we recorded is genuinely answering there, and null otherwise. Null
// covers both shapes the caller has to tell the user apart from success, and they are NOT the same thing:
// no record at all means something else owns the port, while a record that fails to answer means our own panel
// died without cleaning up. The second case removes the file, so the next start is not misled by it.
export async function findRunning(port) {
  const s = await readState(port);
  if (!s) return null;
  const health = await probe(port, s.token);
  if (!health) {
    await clearState(port);
    return null;
  }
  // The pid is the last check rather than the first: a port can be recycled to a different process quickly
  // enough that a health answer alone is not proof of identity, and /api/health reports its own pid precisely
  // so this comparison is possible. A mismatch means the record describes a process that no longer owns this
  // port, so the record is stale even though something answered.
  if (Number(health.pid) !== Number(s.pid)) {
    await clearState(port);
    return null;
  }
  return { url: `http://127.0.0.1:${port}/?token=${s.token}`, pid: s.pid, name: s.name, startedAt: s.startedAt };
}

export const _internals = { runtimeDir, statePath };
