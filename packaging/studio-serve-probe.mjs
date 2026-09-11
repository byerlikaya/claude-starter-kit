#!/usr/bin/env node
// Does the installed panel actually SERVE?
//
// Everything the suite asserted until now was reachable without the server ever
// listening: files exist, modules parse, the palette resolves. `--selftest` is
// the same shape — it reads the disk and asks the CLI a question. So "the panel
// works" had been measured on exactly one machine, by hand, and carried
// everywhere else as an assumption.
//
// This starts the real server against an installed tree, drives it over HTTP,
// and shuts it down. It is written in node rather than shell on purpose: the
// shell half is where Windows differs — backgrounding, kill semantics, curl's
// flags — and that is precisely the platform the claim was weakest on.
import { spawn } from 'node:child_process';
import http from 'node:http';
import net from 'node:net';
import path from 'node:path';
import fs from 'node:fs';

// Two layouts, one probe. The panel ships in an install at <project>/.claude/studio and in the
// plugin edition at <plugin-root>/studio, and the second one had no way to be driven from here —
// so it was measured by hand on one machine and gated nowhere. The argument is the directory that
// CONTAINS studio/, which is `.claude` in an install and the plugin root in a plugin.
const root = process.argv[2];
if (!root) {
  console.error('usage: studio-serve-probe.mjs <dir-containing-studio | installed-project-dir>');
  process.exit(2);
}

const TOKEN = 'probe-token-not-a-secret';
const TIMEOUT_MS = 45000;
const direct = path.join(root, 'studio', 'server', 'index.js');
const viaProject = path.join(root, '.claude', 'studio', 'server', 'index.js');
// Absolute: the child is spawned with cwd set to the root, so a relative entry would be resolved
// against it a second time. It cost one run to see, which is one more than the comment costs.
const entry = path.resolve(fs.existsSync(direct) ? direct : viaProject);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let pass = 0; let na = 0; let known = 0; const failures = [];
// A check the platform cannot answer is not a pass and not a failure. Windows has no way for
// one process to send another a signal — kill() lands as TerminateProcess — so the graceful
// path simply cannot be driven from here, and saying "ok" would be a claim about code that
// never ran.
const notApplicable = (name, why) => { na += 1; console.log(`  N/A  ${name} — ${why}`); };
// A third word, and it is deliberately not a pass. The check ran, it measured what it was written
// to measure, and what it found is a wait the kit neither causes nor can remove. Made green it would
// be a lie; made red it would fire whenever that machine's scanner happens to be busy, which cannot
// be produced on demand, and be silenced within a month, which is how a gate stops being read. KNOWN
// keeps the observation on screen and off the exit code, and it names the cause every time it prints.
const knownIssue = (name, detail, issue) => {
  known += 1;
  console.log(`  KNOWN ${name} — ${detail}\n        the cause: ${issue}`);
};
const check = (name, ok, detail) => {
  if (ok) { pass += 1; console.log(`  ok   ${name}${detail ? ` — ${detail}` : ''}`); }
  else { failures.push(`${name}${detail ? ` — ${detail}` : ''}`); console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`); }
};

/** A port nothing is on right now. Racy by nature, so the caller retries. */
function freePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.on('error', reject);
    s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)); });
  });
}

function get(port, pathname, headers = {}) {
  return new Promise((resolve) => {
    const req = http.request({ host: '127.0.0.1', port, path: pathname, method: headers.__method ?? 'GET', headers },
      (res) => { let b = ''; res.on('data', (d) => { b += d; }); res.on('end', () => resolve({ status: res.statusCode, body: b })); });
    req.on('error', (e) => resolve({ status: 0, body: String(e.code ?? e.message) }));
    // Generous, and it says WHICH it was. Measured on a corporate Windows machine: /api/projects
    // took 12 s, the 15 s limit was marginal, and the failure surfaced as `status 0` — which
    // reads as a broken endpoint rather than as a slow one. A flaky gate that names the wrong
    // cause is worse than a slow one.
    req.setTimeout(TIMEOUT_MS, () => {
      req.destroy();
      resolve({ status: 0, body: `no answer within ${TIMEOUT_MS / 1000}s (timed out, not refused)` });
    });
    req.end();
  });
}

// A registry that accepts the connection and never answers — the shape a proxy or an inspecting
// endpoint takes, and the one an unreachable host does NOT take (a refused connection returns at
// once and hides the defect entirely).
// Every accepted socket needs its own error handler, and so does the server. Killing the panel
// resets these connections; POSIX closes them politely enough that nothing notices, Windows sends
// RST, and an unhandled 'error' takes the whole probe down with `read ECONNRESET`. Measured there:
// 5 runs, 5 crashes — deterministic on that platform and invisible on this one.
const blackHole = net.createServer((sock) => { sock.on('error', () => { /* reset on kill */ }); });
blackHole.on('error', () => { /* the listener itself, same reason */ });
await new Promise((r) => blackHole.listen(0, '127.0.0.1', r));
const feedUrl = `http://127.0.0.1:${blackHole.address().port}/dist-tags`;

const port = await freePort();
const child = spawn(process.execPath, [entry, '--port', String(port)], {
  cwd: root,
  env: { ...process.env, CSK_STUDIO_TOKEN: TOKEN, CSK_UPDATE_URL: feedUrl },
  stdio: ['ignore', 'pipe', 'pipe'],
});

let out = '';
child.stdout.on('data', (d) => { out += d; });
child.stderr.on('data', (d) => { out += d; });

const stop = () => { try { child.kill(); } catch { /* already gone */ } try { blackHole.close(); } catch { /* already closed */ } };
process.on('exit', stop);

// Wait for it to answer, not for a fixed number of seconds: a slow runner is not
// a broken panel, and a fixed sleep is how a green gate starts hiding a hang.
let up = false;
for (let i = 0; i < 60 && !up; i++) {
  await sleep(250);
  if (child.exitCode !== null) break;
  const r = await get(port, `/api/health?token=${TOKEN}`);
  if (r.status === 200) up = true;
}
check('the server listens and answers', up, up ? `port ${port}` : `no answer; output: ${JSON.stringify(out.slice(0, 300))}`);
if (!up) { stop(); process.exit(1); }

check('it prints its URL with the token', /http:\/\/127\.0\.0\.1:\d+\/\?token=/.test(out), out.split('\n')[0]);

const shell = await get(port, `/?token=${TOKEN}`);
check('the panel page is served', shell.status === 200 && /<div id="canvas"|cv-root|CSK Studio/.test(shell.body),
  `status ${shell.status}, ${shell.body.length} bytes`);

const noTok = await get(port, '/api/health');
check('an API call without a token is refused', noTok.status === 403, `status ${noTok.status}`);

// Timed, and it must be the FIRST call to this endpoint: the answer is cached, so a later one
// measures the cache rather than the fetch. A mutation that put the network back on this path
// passed at 22 ms when the timing sat on the second call — the check was reading warm state.
// Both at once: the list itself, and — on a SEPARATE connection, while that one is in flight —
// whether the panel is still answering at all. The distinction is the whole point. A slow endpoint
// is an endpoint; a server that answers nothing is a panel the user calls frozen, and the two look
// identical from a single request. Measured on the machine that has this: during a 29 s stall,
// /api/health on its own connection did not answer for 20 s either.
const t0 = Date.now();
const inFlight = get(port, `/api/projects?token=${TOKEN}`);
await sleep(1500);
const duringStart = Date.now();
const during = await get(port, `/api/health?token=${TOKEN}`);
const duringMs = Date.now() - duringStart;
const projects = await inFlight;
const waited = Date.now() - t0;
let measured = null;
try { measured = JSON.parse(projects.body); } catch { /* reported below */ }
check('projects are read from disk', projects.status === 200 && measured && Array.isArray(measured.projects),
  measured ? `${measured.projects?.length} project(s)` : `status ${projects.status}`);

// The list is local data. It used to await the update feed, so a hanging registry cost the full
// 8 s fetch timeout on the first request — measured at 8.37 s, and reported from a corporate
// network as a 12-second panel that read as hung. CSK_UPDATE_URL points at a socket that accepts
// and never answers, which is exactly that condition; an unreachable host would NOT reproduce it,
// because a refused connection returns at once.
// One measurement, three outcomes — because two independent checks on the same numbers could
// disagree with each other, and because the first version of this got the naming wrong in a way
// worth not repeating: it called every slow first call "waiting on the update feed", which is a
// cause that was later disproven. A run that hits the known block says nothing about the feed at
// all, so it must not be reported as if it did.
const STALL_MS = 25000;          // scanner waits were measured at 28-31 s and at 63-65 s; a feed wait would be 8 s at most
const LIVENESS_MS = 2000;
const timing = `the first /api/projects took ${waited}ms with a feed that never answers; a separate `
  + `/api/health on its own connection answered ${during.status} after ${duringMs}ms while it was in flight`;

// LIVENESS is the graded claim, and the timing is not.
//
// It used to be the other way round, and that was wrong twice over. `waited` says nothing about the
// update feed — a run with the feed disabled entirely still stalled, which is what disproved that
// reading — and it says nothing about the panel either: it is how long ONE file open took, which on a
// machine whose security layer inspects opens is a property of the disk, not of this code. What the
// panel owes its user is that a slow read stays inside the request that hit it. That is gradeable,
// deterministic, and it is exactly what the async conversion bought:
//
//   sync  (main)   /api/projects 33,391 ms · a separate /api/health went unanswered 312 pings of 324
//   async (here)   /api/projects 38,918 ms · the same health endpoint answered 195 of 195
//
// The read did not get faster. Nothing else went dark.
check('the panel answers other requests while a read stalls', duringMs < LIVENESS_MS,
  `${timing}${duringMs < LIVENESS_MS ? '' : ' — the event loop was blocked, so nothing the panel serves responded'}`);

if (waited < 3000) {
  check('the project list is served from local data, not a network round trip', true, timing);
} else if (waited > STALL_MS) {
  // Reported, not graded: the read really did wait that long, and no code here makes a scanner finish
  // sooner. Green would hide it; red would fire whenever that machine's scanner is busy and be muted
  // within a month. The graded half is above, and it stays green through exactly this run.
  knownIssue('one transcript read took the stall shape',
    `${timing} — the read itself took ~${Math.round(waited / 1000)}s`,
    'a security layer that scans files after they are written: a plain tail read of a 25 MB transcript copy '
    + 'waited 63-65 s with no kit code running and 0.044 s after waiting 90 s; it comes in clusters and could '
    + "not be produced on demand. Not the kit's to fix; the kit's part was keeping the rest of the panel "
    + 'answering, which the check above grades');
  notApplicable('the project list is served from local data, not a network round trip',
    'this run hit the stall above, so its timing measures the disk and cannot speak to the request path');
} else {
  // Neither a local read nor the shape of the known stall. Something else, and it should be loud.
  check('the project list is served from local data, not a network round trip', false,
    `${timing} — slower than a local read and faster than the known stall, so this is neither`);
}

const traversal = await get(port, `/../../../../etc/passwd?token=${TOKEN}`);
check('a path outside the web root is refused', traversal.status !== 200, `status ${traversal.status}`);

const write = await get(port, `/api/owned?token=${TOKEN}`, { __method: 'POST' });
check('a write without the same-origin header is refused', write.status === 403, `status ${write.status}`);

// Wait for the exit to be reported, not for a fixed 600 ms. kill() returns once the request is made, and
// the exit reaches this process later, as an event. On Windows CI it once had not arrived after 600 ms,
// and the check read `exit null signal null` for a panel that had been told to stop. A panel that really
// does not stop still fails here, after SHUTDOWN_MS, and says so.
const SHUTDOWN_MS = 10000;
const exitReported = (child.exitCode !== null || child.signalCode !== null)
  ? Promise.resolve(true)
  : new Promise((resolve) => {
    child.once('exit', () => resolve(true));
    setTimeout(() => resolve(false), SHUTDOWN_MS);
  });
const stopAt = Date.now();
stop();
const exited = await exitReported;
const stopMs = Date.now() - stopAt;
check('it shuts down when asked', exited,
  exited ? `exit ${child.exitCode} signal ${child.signalCode} after ${stopMs}ms`
    : `no exit reported within ${SHUTDOWN_MS / 1000}s of kill(); exit ${child.exitCode} signal ${child.signalCode}`);

// Stopping and stopping *cleanly* are different facts, and one check accepting both hid the
// difference: POSIX exits 0 because the SIGTERM handler ran and reaped the panel's children;
// Windows reports signal SIGTERM, which is this process being terminated with no handler run.
if (process.platform === 'win32') {
  notApplicable('it shuts its children down on the way out',
    'Windows cannot deliver a signal to another process, so the handler cannot be driven from a test; '
    + 'the path users are told to use — Ctrl-C in the panel\'s own console — does raise SIGINT and does run it');
} else {
  check('it shuts its children down on the way out', child.exitCode === 0,
    `exit ${child.exitCode} signal ${child.signalCode}; a handler that ran exits 0, a killed process does not`);
}

console.log(`  ${pass}/${pass + failures.length} served checks passed`
  + `${na ? `, ${na} not applicable here` : ''}`
  + `${known ? `, ${known} known open issue${known > 1 ? 's' : ''} observed` : ''}`);
process.exit(failures.length ? 1 : 0);
