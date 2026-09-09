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
const direct = path.join(root, 'studio', 'server', 'index.js');
const viaProject = path.join(root, '.claude', 'studio', 'server', 'index.js');
// Absolute: the child is spawned with cwd set to the root, so a relative entry would be resolved
// against it a second time. It cost one run to see, which is one more than the comment costs.
const entry = path.resolve(fs.existsSync(direct) ? direct : viaProject);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let pass = 0; let na = 0; const failures = [];
// A check the platform cannot answer is not a pass and not a failure. Windows has no way for
// one process to send another a signal — kill() lands as TerminateProcess — so the graceful
// path simply cannot be driven from here, and saying "ok" would be a claim about code that
// never ran.
const notApplicable = (name, why) => { na += 1; console.log(`  N/A  ${name} — ${why}`); };
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
    req.setTimeout(15000, () => { req.destroy(); resolve({ status: 0, body: 'timeout' }); });
    req.end();
  });
}

const port = await freePort();
const child = spawn(process.execPath, [entry, '--port', String(port)], {
  cwd: root,
  env: { ...process.env, CSK_STUDIO_TOKEN: TOKEN },
  stdio: ['ignore', 'pipe', 'pipe'],
});

let out = '';
child.stdout.on('data', (d) => { out += d; });
child.stderr.on('data', (d) => { out += d; });

const stop = () => { try { child.kill(); } catch { /* already gone */ } };
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

const projects = await get(port, `/api/projects?token=${TOKEN}`);
let measured = null;
try { measured = JSON.parse(projects.body); } catch { /* reported below */ }
check('projects are read from disk', projects.status === 200 && measured && Array.isArray(measured.projects),
  measured ? `${measured.projects?.length} project(s)` : `status ${projects.status}`);

const traversal = await get(port, `/../../../../etc/passwd?token=${TOKEN}`);
check('a path outside the web root is refused', traversal.status !== 200, `status ${traversal.status}`);

const write = await get(port, `/api/owned?token=${TOKEN}`, { __method: 'POST' });
check('a write without the same-origin header is refused', write.status === 403, `status ${write.status}`);

stop();
await sleep(600);
check('it shuts down when asked', child.exitCode !== null || child.signalCode !== null,
  `exit ${child.exitCode} signal ${child.signalCode}`);

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

console.log(`  ${pass}/${pass + failures.length} served checks passed${na ? `, ${na} not applicable here` : ''}`);
process.exit(failures.length ? 1 : 0);
