#!/usr/bin/env node
// CSK Studio — the server half.
//
// It binds to loopback and nothing else. The panel reads a developer's live
// sessions, transcripts and, later, drives Claude itself; none of that should
// be reachable from the network, so the host is not configurable.
//
// Zero dependencies, by design: the kit ships no npm packages and this stays
// inside that promise. `node server/index.js` is the whole install step.

import http from 'node:http';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

import { getFleet, measureSpawnCost } from './lib/fleet.js';
import { projectDir, listSessions, findSession, listProjects } from './lib/projects.js';
import { buildGraph, agentDetail } from './lib/graph.js';
import { palette } from './lib/palette.js';
import { latestVersion, kitStatus } from './lib/kit.js';
import { parsePeers, askAll, ask } from './lib/peers.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const WEB_ROOT = path.resolve(HERE, '..', 'web');
const LOOPBACK = '127.0.0.1';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

function parseArgs(argv) {
  const out = { port: 7777, selftest: false, open: false, peers: [], name: null };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--port' || a === '-p') {
      const n = Number(argv[i + 1]);
      if (!Number.isInteger(n) || n < 1 || n > 65535) {
        throw new Error(`--port needs a number between 1 and 65535, got: ${argv[i + 1]}`);
      }
      out.port = n;
      i += 1;
    } else if (a === '--peer') {
      if (!argv[i + 1]) throw new Error('--peer needs a URL');
      out.peers.push(argv[i + 1]);
      i += 1;
    } else if (a === '--name') {
      if (!argv[i + 1]) throw new Error('--name needs a label');
      out.name = argv[i + 1];
      i += 1;
    } else if (a === '--selftest') {
      out.selftest = true;
    } else if (a === '--help' || a === '-h') {
      out.help = true;
    } else {
      throw new Error(`unknown argument: ${a}`);
    }
  }
  return out;
}

function send(res, status, body, headers = {}) {
  res.writeHead(status, {
    'content-type': 'text/plain; charset=utf-8',
    'cache-control': 'no-store',
    ...headers,
  });
  res.end(body);
}

function sendJson(res, status, value) {
  send(res, status, JSON.stringify(value, null, 2), {
    'content-type': 'application/json; charset=utf-8',
  });
}

// Auth is opt-in while every endpoint is read-only and loopback-bound. It
// becomes mandatory in the sprint that adds write endpoints; wiring it now
// means that switch is a default change, not a retrofit.
const TOKEN = process.env.CSK_STUDIO_TOKEN || null;

// Peers are other machines running Studio, reached over a forwarded port. This
// server still listens on loopback only; a peer never widens that.
let PEERS = [];
let SELF_NAME = 'this machine';

function authorised(req, url) {
  if (!TOKEN) return true;
  const header = req.headers['authorization'];
  if (header === `Bearer ${TOKEN}`) return true;
  return url.searchParams.get('token') === TOKEN;
}

async function serveStatic(res, urlPath) {
  const rel = urlPath === '/' ? '/index.html' : urlPath;
  // Resolve, then prove the result is still inside web/. Comparing spellings
  // is not enough; ask the resolver.
  const abs = path.resolve(WEB_ROOT, `.${rel}`);
  if (abs !== WEB_ROOT && !abs.startsWith(WEB_ROOT + path.sep)) {
    return send(res, 403, 'forbidden');
  }
  try {
    const data = await fsp.readFile(abs);
    return send(res, 200, data, {
      'content-type': MIME[path.extname(abs)] ?? 'application/octet-stream',
    });
  } catch {
    return send(res, 404, 'not found');
  }
}

async function handle(req, res) {
  const url = new URL(req.url, `http://${LOOPBACK}`);

  if (!authorised(req, url)) return send(res, 403, 'forbidden: token required');

  if (url.pathname === '/api/health') {
    return sendJson(res, 200, {
      ok: true,
      node: process.version,
      pid: process.pid,
      uptimeMs: Math.round(process.uptime() * 1000),
    });
  }

  if (url.pathname === '/api/fleet') {
    const local = await getFleet();
    const mine = (local.sessions ?? []).map((sn) => ({ ...sn, origin: SELF_NAME, local: true }));

    // Self is always in origins, peers or not: a machine that never names
    // itself cannot be labelled by the one reading it.
    const self = { name: SELF_NAME, local: true, ok: true, sessions: mine.length };
    if (!PEERS.length) return sendJson(res, 200, { ...local, sessions: mine, origins: [self] });

    const answers = await askAll(PEERS, '/api/fleet');
    const sessions = [...mine];
    const origins = [self];
    for (const a of answers) {
      if (!a.ok) {
        // An unreachable machine is reported as unreachable. Dropping it would
        // read as "that machine is quiet".
        origins.push({ name: a.peer.name, ok: false, reason: a.reason });
        continue;
      }
      // A machine knows its own name; the URL we reached it on is only a
      // fallback for one that does not say.
      const label = a.body?.origins?.find((o) => o.local)?.name ?? a.peer.name;
      const rows = (a.body?.sessions ?? []).map((sn) => ({ ...sn, origin: label, local: false }));
      origins.push({ name: label, via: a.peer.name, ok: true, sessions: rows.length, measured: a.body?.measured !== false });
      sessions.push(...rows);
    }
    return sendJson(res, 200, { measured: local.measured, sessions, origins, at: Date.now() });
  }

  if (url.pathname === '/api/projects') {
    const cwd = url.searchParams.get('cwd') || process.cwd();
    const started = Date.now();
    const latest = await latestVersion();
    const projects = listProjects({ currentCwd: cwd, kitOf: (c) => kitStatus(c, latest) });
    for (const p of projects) { p.origin = SELF_NAME; p.local = true; }

    const origins = [{ name: SELF_NAME, local: true, ok: true, projects: projects.length }];
    if (PEERS.length) {
      for (const a of await askAll(PEERS, '/api/projects')) {
        if (!a.ok) { origins.push({ name: a.peer.name, ok: false, reason: a.reason }); continue; }
        const label = a.body?.origins?.find((o) => o.local)?.name ?? a.peer.name;
        const rows = (a.body?.projects ?? []).map((pr) => ({
          ...pr,
          origin: label,
          local: false,
          current: false,              // "the project you are standing in" is a local fact
          key: `${label}|${pr.key}`,
        }));
        origins.push({ name: label, via: a.peer.name, ok: true, projects: rows.length });
        projects.push(...rows);
      }
      projects.sort((a, b) =>
        Number(b.current) - Number(a.current) ||
        Number(b.local) - Number(a.local) ||
        Number(b.exists) - Number(a.exists) ||
        b.modifiedAt - a.modifiedAt);
    }

    const installed = projects.filter((p) => p.kit?.installed);
    return sendJson(res, 200, {
      measured: true,
      cwd,
      latest,
      origins,
      projects,
      totals: {
        projects: projects.length,
        live: projects.filter((p) => p.exists).length,
        sessions: projects.reduce((n, p) => n + p.total, 0),
        agents: projects.reduce((n, p) => n + p.agentTotal, 0),
        kitInstalled: installed.length,
        kitOutdated: installed.filter((p) => p.kit.outdated).length,
        kitUncompared: installed.filter((p) => p.kit.compared === false).length,
      },
      buildMs: Date.now() - started,
    });
  }

  if (url.pathname === '/api/palette') {
    return sendJson(res, 200, palette());
  }

  if (url.pathname === '/api/sessions') {
    const cwd = url.searchParams.get('cwd') || process.cwd();
    const dir = projectDir(cwd);
    if (!dir) {
      // Nothing was read. That is not the same as "this project never ran".
      return sendJson(res, 200, {
        measured: false,
        reason: `no transcript directory for ${cwd}`,
        cwd,
        sessions: [],
      });
    }
    const sessions = listSessions(dir).map((s) => ({
      sessionId: s.sessionId,
      bytes: s.bytes,
      modifiedAt: s.modifiedAt,
      agentCount: s.agentCount,
    }));
    return sendJson(res, 200, { measured: true, cwd, dir, sessions });
  }

  const graphMatch = url.pathname.match(/^\/api\/session\/([^/]+)\/graph$/);
  if (graphMatch) {
    const session = findSession(decodeURIComponent(graphMatch[1]));
    if (!session) {
      const relayed = await relay(url.pathname);
      if (relayed) return sendJson(res, 200, relayed);
      return sendJson(res, 404, { measured: false, reason: 'no such session on this machine or any peer' });
    }
    const started = Date.now();
    const graph = buildGraph(session);
    return sendJson(res, 200, { ...graph, measured: true, buildMs: Date.now() - started });
  }

  const agentMatch = url.pathname.match(/^\/api\/session\/([^/]+)\/agent\/([^/]+)$/);
  if (agentMatch) {
    const session = findSession(decodeURIComponent(agentMatch[1]));
    if (!session) {
      const relayed = await relay(url.pathname);
      if (relayed) return sendJson(res, 200, relayed);
      return sendJson(res, 404, { measured: false, reason: 'no such session' });
    }
    const detail = agentDetail(session, decodeURIComponent(agentMatch[2]));
    if (!detail) return sendJson(res, 404, { measured: false, reason: 'no transcript for that agent' });
    return sendJson(res, 200, { ...detail, measured: true });
  }

  if (url.pathname === '/api/stream') {
    return stream(req, res, url);
  }

  if (url.pathname.startsWith('/api/')) {
    return sendJson(res, 404, { error: `no such endpoint: ${url.pathname}` });
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return send(res, 405, 'method not allowed');
  }

  return serveStatic(res, url.pathname);
}

/* ---------------------------------------------------------------- stream
   Server-sent events. A WebSocket would need a dependency or a hand-rolled
   frame codec; SSE is one-way, which is all the graph needs, and it reconnects
   on its own.

   Files are polled rather than watched: fs.watch's event semantics differ per
   platform, and a graph rebuild measured 17 ms on a 1.5 MB transcript, so a
   cheap signature check plus a conditional rebuild is both simpler and honest
   about its cost. */

const STREAM_TICK_MS = 700;

/** Ask each peer for a path this machine could not answer. */
async function relay(pathname) {
  for (const p of PEERS) {
    const r = await ask(p, pathname);
    if (r.ok && r.body?.measured !== false) return { ...r.body, origin: p.name, relayed: true };
  }
  return null;
}

function signature(session) {
  const parts = [];
  try { parts.push(String(fs.statSync(session.file).size)); } catch { parts.push('0'); }
  try {
    for (const n of fs.readdirSync(session.subagentsDir).sort()) {
      try { parts.push(`${n}:${fs.statSync(path.join(session.subagentsDir, n)).size}`); } catch { /* raced */ }
    }
  } catch { /* no subagents yet */ }
  return parts.join('|');
}

function stream(req, res, url) {
  const id = url.searchParams.get('session');
  const session = id ? findSession(id) : null;

  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-store',
    connection: 'keep-alive',
    'x-accel-buffering': 'no',
  });

  const send = (event, data) => {
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  };

  if (!session) {
    if (!id) { send('fault', { measured: false, reason: 'no session id given' }); return res.end(); }
    // A remote session is polled through its peer rather than watched: this
    // machine has no file to watch.
    let stopped = false;
    const pull = async () => {
      if (stopped) return;
      const relayed = await relay(`/api/session/${encodeURIComponent(id)}/graph`);
      if (stopped) return;
      if (relayed) send('graph', relayed);
      else { send('fault', { measured: false, reason: 'no such session on this machine or any peer' }); stop(); }
    };
    const timer2 = setInterval(pull, Math.max(STREAM_TICK_MS * 3, 2000));
    const stop = () => { stopped = true; clearInterval(timer2); try { res.end(); } catch { /* gone */ } };
    req.on('close', stop);
    req.on('error', stop);
    pull();
    return undefined;
  }

  let last = null;
  const tick = () => {
    try {
      const sig = signature(session);
      if (sig !== last) {
        last = sig;
        send('graph', buildGraph(session));
      } else {
        send('idle', { at: Date.now() });
      }
    } catch (e) {
      send('fault', { measured: false, reason: String(e?.message ?? e) });
    }
  };

  tick();
  const timer = setInterval(tick, STREAM_TICK_MS);
  const stop = () => { clearInterval(timer); try { res.end(); } catch { /* gone */ } };
  req.on('close', stop);
  req.on('error', stop);
}

async function selftest() {
  const checks = [];
  const check = (name, ok, detail) => checks.push({ name, ok, detail });

  check('web root exists', fs.existsSync(WEB_ROOT), WEB_ROOT);
  check('index.html present', fs.existsSync(path.join(WEB_ROOT, 'index.html')), null);

  const fleet = await getFleet({ force: true });
  check(
    'fleet read returned a verdict',
    typeof fleet.measured === 'boolean',
    fleet.measured ? `${fleet.sessions.length} session(s)` : `not measured: ${fleet.reason}`,
  );

  const cost = await measureSpawnCost(3);
  check(
    'spawn cost measured',
    cost !== null,
    cost ? `min ${cost.minMs}ms · median ${cost.medianMs}ms · max ${cost.maxMs}ms` : 'claude CLI absent — skipped honestly',
  );

  for (const c of checks) {
    process.stdout.write(`${c.ok ? 'PASS' : 'FAIL'} ${c.name}${c.detail ? ` — ${c.detail}` : ''}\n`);
  }
  // An empty run is a broken harness, not a clean bill of health.
  if (!checks.length) {
    process.stdout.write('FAIL selftest ran zero checks — the measurement is broken, not the server\n');
    return 1;
  }
  const failed = checks.filter((c) => !c.ok).length;
  process.stdout.write(`\n${checks.length - failed}/${checks.length} passed\n`);
  return failed ? 1 : 0;
}

async function main() {
  let args;
  try {
    args = parseArgs(process.argv.slice(2));
  } catch (e) {
    process.stderr.write(`csk-studio: ${e.message}\n`);
    process.exit(64);
  }

  if (args.help) {
    process.stdout.write(
      'csk-studio — visual orchestration panel for Claude Code\n\n' +
        '  --port <n>   port to listen on (default 7777, loopback only)\n' +
        '  --peer <url> another machine running Studio (repeatable)\n' +
        '  --name <s>   label for this machine (default: hostname)\n' +
        '  --selftest   run offline checks and exit\n' +
        '  --help       this text\n\n' +
        'Set CSK_STUDIO_TOKEN to require a bearer token, CSK_STUDIO_PEERS for a\n' +
        'comma-separated peer list.\n\n' +
        'Peers are normally reached over a forwarded port, which keeps every\n' +
        'Studio on loopback:\n' +
        '  ssh -N -L 7778:127.0.0.1:7777 other-machine\n' +
        '  csk-studio --peer http://127.0.0.1:7778\n',
    );
    return;
  }

  if (args.selftest) {
    process.exit(await selftest());
  }

  const server = http.createServer((req, res) => {
    handle(req, res).catch((e) => {
      process.stderr.write(`csk-studio: unhandled: ${e?.stack ?? e}\n`);
      if (!res.headersSent) send(res, 500, 'internal error');
    });
  });

  server.on('error', (e) => {
    if (e.code === 'EADDRINUSE') {
      process.stderr.write(`csk-studio: port ${args.port} is already in use — try --port ${args.port + 1}\n`);
      process.exit(1);
    }
    throw e;
  });

  PEERS = parsePeers([
    ...args.peers,
    ...(process.env.CSK_STUDIO_PEERS ?? '').split(',').map((x) => x.trim()).filter(Boolean),
  ]);
  SELF_NAME = args.name || os.hostname().replace(/\.local$/, '');

  server.listen(args.port, LOOPBACK, () => {
    const q = TOKEN ? `?token=${TOKEN}` : '';
    process.stdout.write(`csk-studio  http://${LOOPBACK}:${args.port}/${q}\n`);
    process.stdout.write(`            machine: ${SELF_NAME}\n`);
    if (PEERS.length) {
      for (const p of PEERS) {
        process.stdout.write(`            peer: ${p.error ? `${p.spec} — ${p.error}` : p.base}\n`);
      }
    }
    if (!TOKEN) process.stdout.write('            (loopback only, no token set)\n');
  });

  for (const sig of ['SIGINT', 'SIGTERM']) {
    process.on(sig, () => {
      server.close(() => process.exit(0));
      setTimeout(() => process.exit(0), 2000).unref();
    });
  }
}

main();
