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

const projectDir = process.argv[2];
if (!projectDir) { console.error('usage: studio-serve-probe.mjs <installed-project-dir>'); process.exit(2); }

const TOKEN = 'probe-token-not-a-secret';
const entry = path.join(projectDir, '.claude', 'studio', 'server', 'index.js');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let pass = 0; const failures = [];
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
  cwd: projectDir,
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
await sleep(400);
check('it shuts down when asked', child.exitCode !== null || child.signalCode !== null,
  `exit ${child.exitCode} signal ${child.signalCode}`);

console.log(`  ${pass}/${pass + failures.length} served checks passed`);
process.exit(failures.length ? 1 : 0);
