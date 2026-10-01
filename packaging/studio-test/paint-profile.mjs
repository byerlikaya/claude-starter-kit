#!/usr/bin/env node
// What the graph costs to draw, measured in a browser that is really painting.
//
//   node packaging/studio-test/paint-profile.mjs                 250 synthetic nodes, this checkout's panel
//   node packaging/studio-test/paint-profile.mjs --headed        the same, in a window you can see
//   node packaging/studio-test/paint-profile.mjs --real URL      a panel that is already running, as it is
//   ... --nodes N --running N --secs N --chrome PATH --json FILE
//
// Not a gate, and not wired into verify.sh: it needs a Chrome and a display, and its numbers belong to the
// machine it ran on. It exists so that "the graph is fast enough" is a table and not an impression.
//
// TWO THINGS MAKE A NUMBER FROM HERE WORTH QUOTING, and the script refuses to print a verdict without them:
//
//   1. The calibration twin. requestAnimationFrame ticking is not proof that pixels are produced: in a hidden
//      pane it ran at a healthy 8.3 ms while a deliberately expensive repaint changed the median by nothing.
//      So every run first repaints 400 blurred, shadowed boxes on every frame and compares that with an idle
//      page. If the frame time does not rise, nothing is being painted and the run says INVALID.
//   2. The legal worst case. The motion budget allows 60 strokes in motion; a fixture with 9 moving measures
//      something else. The synthetic graph fills the budget exactly, and reports how many animations ran.
//
// The synthetic mode takes over the panel's own canvas element with a second Canvas instance fed a generated
// graph, so the stylesheet, the tokens and the page around it are the real ones. `--real` touches nothing: it
// measures the page as the viewer has it.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { CDP, httpJson } from '../studio-record/cdp.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');
const arg = (name, fallback) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : fallback; };
const flag = (name) => process.argv.includes(`--${name}`);

const NODES = Number(arg('nodes', 250));
const RUNNING = Number(arg('running', 60));
const SECS = Number(arg('secs', 8));
const REAL = arg('real', null);
const HEADED = flag('headed');
const JSON_OUT = arg('json', null);
const W = Number(arg('width', 1440));
const H = Number(arg('height', 900));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const die = (m) => { console.error(`paint-profile: ${m}`); process.exit(2); };

function findChrome() {
  const given = arg('chrome', process.env.CHROME_PATH ?? null);
  const candidates = given ? [given] : [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
    '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
  ];
  return candidates.find((c) => fs.existsSync(c)) ?? null;
}

/* ---------------------------------------------------------------- server */

const kids = [];
process.on('exit', () => { for (const k of kids) { try { k.kill(); } catch { /* gone */ } } });

async function startPanel() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-paint-'));
  const port = 7900 + Math.floor(Math.random() * 90);
  const token = 'paint-profile';
  // An empty projects root and a CLI that is not there: the panel has nothing of its own to draw or to poll for,
  // so what is measured is the canvas this script feeds.
  const server = spawn(process.execPath, [path.join(REPO, 'kit', 'studio', 'server', 'index.js'), '--port', String(port)], {
    env: {
      ...process.env,
      CREW_STUDIO_TOKEN: token,
      CREW_STUDIO_PROJECTS_ROOT: path.join(tmp, 'projects'),
      CREW_STUDIO_RUNTIME: path.join(tmp, 'runtime'),
      CREW_UPDATE_URL: 'data:application/json,{"latest":"0.0.0"}',
    },
    stdio: 'ignore',
  });
  kids.push(server);
  const url = `http://127.0.0.1:${port}/?token=${token}`;
  for (let i = 0; i < 40; i += 1) {
    await sleep(250);
    try { const r = await fetch(url); if (r.ok) return url; } catch { /* not up yet */ }
  }
  die('the panel did not start');
  return null;
}

/* ------------------------------------------------------- in-page helpers */

// Evaluated in the page. Kept as one string so the same code runs in every scenario.
const IN_PAGE = `
window.__pp = {
  frames(ms) {
    return new Promise((resolve) => {
      const out = []; let last = performance.now(); const t0 = last;
      const tick = (now) => { out.push(now - last); last = now; if (now - t0 < ms) requestAnimationFrame(tick); else resolve(out); };
      requestAnimationFrame(tick);
    });
  },
  stats(a) {
    const s = [...a].sort((x, y) => x - y); const q = (f) => s[Math.min(s.length - 1, Math.floor(f * s.length))];
    const sum = a.reduce((t, v) => t + v, 0);
    // A frame is "late" against THIS display, not against 60 Hz: 1.5x the interval the idle page ran at.
    const late = (window.__pp.base ?? 16.7) * 1.5;
    return { frames: a.length, fps: Math.round(a.length / (sum / 1000)), median: +q(0.5).toFixed(2), p95: +q(0.95).toFixed(2),
      max: +q(1).toFixed(1), late: a.filter((v) => v > late).length };
  },
  twinOn() {
    const host = document.createElement('div'); host.id = '__pp_twin';
    host.style.cssText = 'position:fixed;inset:0;z-index:99999;pointer-events:none;display:grid;grid-template-columns:repeat(25,1fr);gap:2px;opacity:.5';
    for (let i = 0; i < 400; i += 1) { const b = document.createElement('div'); b.style.cssText = 'height:40px;filter:blur(6px);box-shadow:0 0 24px 8px rgba(0,0,0,.5)'; host.append(b); }
    document.body.append(host);
    let n = 0; const paint = () => { if (!host.isConnected) return; n += 1; for (let i = 0; i < host.children.length; i += 1) host.children[i].style.background = 'hsl(' + ((n * 7 + i * 3) % 360) + ' 70% 50%)'; requestAnimationFrame(paint); };
    requestAnimationFrame(paint);
  },
  twinOff() { document.getElementById('__pp_twin')?.remove(); },
  graph(nodes, running) {
    const types = ['Explore', 'general-purpose', 'crew-backend-expert', 'crew-test-expert', 'crew-review-agent', 'Plan'];
    const out = [{ id: 'session', kind: 'session', status: 'session', turns: 41, cwd: '/work/acme-payments-api', gitBranch: 'release/2.4', tokens: 164000, sessionId: 'synthetic' }];
    const edges = [];
    const runs = 5; const perRun = Math.floor(nodes * 0.4 / runs);
    let made = 0; let live = 0;
    const status = (i) => { if (live < running) { live += 1; return 'running'; } return i % 31 === 0 ? 'failed' : i % 17 === 0 ? 'ended' : 'done'; };
    const agent = (id, parentId, depth, i, workflow) => ({ id, kind: 'agent', agentType: types[i % types.length], status: status(i), spawnDepth: depth, parentId,
      workflow: workflow ?? null, description: 'Synthetic task ' + i + ' with a description long enough to be cut', tools: {}, toolCount: 3 + (i % 20), lastTool: 'Bash', tokens: 12000 + i * 37, durationMs: 60000 + i * 900, errors: i % 31 === 0 ? 2 : 0, startedAt: 1000 + i });
    for (let r = 0; r < runs; r += 1) {
      const wf = 'wf:run-' + r;
      const members = [];
      for (let k = 0; k < perRun; k += 1) { const a = agent('w' + r + '-' + k, wf, 2, made, 'run-' + r); members.push(a); made += 1; }
      const byStatus = {}; for (const m of members) byStatus[m.status] = (byStatus[m.status] ?? 0) + 1;
      out.push({ id: wf, kind: 'workflow', workflowId: 'run-' + r, status: byStatus.running ? 'running' : 'done', members: members.length, byStatus, spawnDepth: 1, parentId: 'session', tokens: 99000, durationMs: 300000, startedAt: 500 + r });
      edges.push({ source: 'session', target: wf });
      for (const m of members) { out.push(m); edges.push({ source: wf, target: m.id }); }
    }
    let i = 0;
    while (made < nodes) {
      const top = agent('a' + i, 'session', 1, made); out.push(top); edges.push({ source: 'session', target: top.id }); made += 1; i += 1;
      if (i % 9 === 0 && made < nodes) { const kid = agent('k' + i, top.id, 2, made); out.push(kid); edges.push({ source: top.id, target: kid.id }); made += 1; }
    }
    return { nodes: out, edges, stats: {} };
  },
  async takeOver(nodes, running, token) {
    const { Canvas } = await import('/canvas.js');
    const root = document.getElementById('canvas');
    const c = new Canvas(root, {});
    try { const p = await (await fetch('/api/palette?token=' + token)).json(); c.setPalette?.(p); } catch { /* neutral */ }
    c.setSession('paint-profile-' + nodes);
    const g = this.graph(nodes, running);
    c.render(g);
    this.canvas = c; this.g = g; this.root = root;
    return this.describe();
  },
  describe() {
    const root = this.root ?? document.getElementById('canvas');
    return {
      domNodes: root.querySelectorAll('*').length,
      cards: root.querySelectorAll('.cv-node').length,
      edges: root.querySelectorAll('.cv-edge').length,
      motion: root.dataset.motion ?? null,
      running: document.getAnimations().filter((a) => a.playState === 'running').length,
      zoom: this.canvas ? +this.canvas.view.k.toFixed(3) : null,
    };
  },
  expandAll() {
    const c = this.canvas;
    if (typeof c.expandAll === 'function') c.expandAll(); else this.root.querySelector('[data-act="expand"]')?.click();
    return this.describe();
  },
  async pan(ms) {
    const c = this.canvas; const x0 = c.view.x; const y0 = c.view.y; const t0 = performance.now();
    const move = (now) => { const t = (now - t0) / 1000; c.view.x = x0 + Math.sin(t * 2.2) * 260; c.view.y = y0 + Math.cos(t * 1.7) * 160; c.applyView(); if (now - t0 < ms) requestAnimationFrame(move); else { c.view.x = x0; c.view.y = y0; c.applyView(); } };
    requestAnimationFrame(move);
    return this.frames(ms);
  },
  async zoom(ms) {
    const c = this.canvas; const k0 = c.view.k; const t0 = performance.now();
    const move = (now) => { const t = (now - t0) / 1000; c.view.k = k0 * (1 + 0.45 * Math.sin(t * 2.4)); c.applyView(); if (now - t0 < ms) requestAnimationFrame(move); else { c.view.k = k0; c.applyView(); } };
    requestAnimationFrame(move);
    return this.frames(ms);
  },
  polls(n) {
    const c = this.canvas; const t = [];
    for (let i = 0; i < n; i += 1) { const t0 = performance.now(); c.render(this.g); t.push(performance.now() - t0); }
    const s = [...t].sort((x, y) => x - y);
    return { polls: n, median: +s[Math.floor(n / 2)].toFixed(2), max: +s[n - 1].toFixed(2) };
  },
};
'ready'`;

/* -------------------------------------------------------------------- run */

const chromePath = findChrome();
if (!chromePath) die('no Chrome or Edge found — pass --chrome PATH');

const url = REAL ?? await startPanel();
const token = new URL(url).searchParams.get('token') ?? '';
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-paint-chrome-'));
const port = 9400 + Math.floor(Math.random() * 90);
const chrome = spawn(chromePath, [
  `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  ...(HEADED ? [] : ['--headless=new']),
  `--window-size=${W},${H}`, '--no-first-run', '--no-default-browser-check', '--disable-extensions',
  // Left on their own, a window that is not in front is throttled, which is the hidden-pane failure again.
  '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding', '--disable-background-timer-throttling',
  'about:blank',
], { stdio: 'ignore' });
kids.push(chrome);

let targets = null;
for (let i = 0; i < 60 && !targets; i += 1) { await sleep(250); try { targets = await httpJson(port, '/json/list'); } catch { /* not up */ } }
if (!targets) die('Chrome never opened its debugging port');
const cdp = await new CDP(targets.find((t) => t.type === 'page').webSocketDebuggerUrl).connect();
await cdp.call('Page.enable');
await cdp.call('Runtime.enable');
if (!HEADED) await cdp.call('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 2, mobile: false });
await cdp.call('Page.navigate', { url });
await sleep(REAL ? 6000 : 3000);
await cdp.eval(IN_PAGE);

const ev = (code) => cdp.eval(`(async () => JSON.stringify(await (${code})))()`).then((s) => JSON.parse(s));

// Frame intervals are locked to the display, so a page that needs 2 ms and one that needs 14 ms both read 16.7.
// The main thread's own clock is not quantised: script, style and layout time per second of wall clock, from the
// browser's counters. Paint and raster run off this thread and show up only in the frames.
await cdp.call('Performance.enable');
const counters = async () => {
  const m = Object.fromEntries((await cdp.call('Performance.getMetrics')).metrics.map((x) => [x.name, x.value]));
  return { t: m.Timestamp, script: m.ScriptDuration, style: m.RecalcStyleDuration, layout: m.LayoutDuration, task: m.TaskDuration };
};
const measure = async (code) => {
  const a = await counters();
  const frames = await ev(`(async () => window.__pp.stats(await ${code}))()`);
  const b = await counters();
  const per = (k) => +(((b[k] - a[k]) / (b.t - a.t)) * 1000).toFixed(1);   // ms of work per second
  return { ...frames, mainMsPerSec: per('task'), scriptMsPerSec: per('script'), styleMsPerSec: per('style'), layoutMsPerSec: per('layout') };
};
const ms = SECS * 1000;

const result = {
  platform: process.platform,
  arch: process.arch,
  cpu: os.cpus()[0]?.model ?? 'unknown',
  node: process.version,
  browser: (await httpJson(port, '/json/version')).Browser,
  mode: REAL ? 'real' : 'synthetic',
  headed: HEADED,
  viewport: await ev(`({ w: innerWidth, h: innerHeight, dpr: devicePixelRatio, visible: document.visibilityState })`),
  commit: (() => { try { return fs.readFileSync(path.join(REPO, '.git', 'HEAD'), 'utf8').trim(); } catch { return 'unknown'; } })(),
};

// The twin first, on the page as it loaded: is anything being painted at all?
result.idle = await measure(`window.__pp.frames(3000)`);
await ev(`(window.__pp.base = ${result.idle.median}, 1)`);
await ev(`(window.__pp.twinOn(), 1)`);
await sleep(300);
result.twin = await measure(`window.__pp.frames(3000)`);
await ev(`(window.__pp.twinOff(), 1)`);
await sleep(300);
result.twinRatio = +(result.twin.median / result.idle.median).toFixed(2);
result.valid = result.twinRatio >= 1.5;

if (REAL) {
  result.page = await ev(`window.__pp.describe()`);
  result.steady = await measure(`window.__pp.frames(${ms})`);
} else {
  result.asOpened = await ev(`window.__pp.takeOver(${NODES}, ${RUNNING}, ${JSON.stringify(token)})`);
  await sleep(900);
  result.settled = await ev(`window.__pp.describe()`);
  result.steady = await measure(`window.__pp.frames(${ms})`);
  result.pan = await measure(`window.__pp.pan(${Math.min(ms, 5000)})`);
  result.zoom = await measure(`window.__pp.zoom(${Math.min(ms, 5000)})`);
  result.poll = await ev(`window.__pp.polls(20)`);
  result.expanded = await ev(`window.__pp.expandAll()`);
  await sleep(800);
  result.expandedDescribe = await ev(`window.__pp.describe()`);
  result.expandedSteady = await measure(`window.__pp.frames(${ms})`);
  result.expandedPan = await measure(`window.__pp.pan(${Math.min(ms, 5000)})`);
  result.expandedPoll = await ev(`window.__pp.polls(20)`);
}

/* ------------------------------------------------------------------ print */

const row = (name, s) => console.log(`${name.padEnd(30)} ${String(s.fps).padStart(4)} fps  median ${String(s.median).padStart(6)} ms  p95 ${String(s.p95).padStart(6)}  max ${String(s.max).padStart(7)}  late ${String(s.late).padStart(3)}/${String(s.frames).padEnd(4)}  main ${String(s.mainMsPerSec).padStart(6)} ms/s (script ${s.scriptMsPerSec}, style ${s.styleMsPerSec}, layout ${s.layoutMsPerSec})`);
console.log(`paint-profile · ${result.mode} · ${result.platform}/${result.arch} · ${result.cpu} · ${result.browser} · ${result.headed ? 'headed' : 'headless'} · ${result.viewport.w}x${result.viewport.h}@${result.viewport.dpr} · ${result.viewport.visible}`);
row('idle page', result.idle);
row('calibration twin (400 boxes)', result.twin);
console.log(`twin / idle median = ${result.twinRatio}  →  ${result.valid ? 'VALID: the page is being painted' : 'INVALID: frames tick but nothing is painted; do not quote the rows below'}`);
if (REAL) {
  console.log(`page: ${JSON.stringify(result.page)}`);
  row('steady, as the viewer has it', result.steady);
} else {
  console.log(`as opened (${NODES} nodes, ${RUNNING} running): ${JSON.stringify(result.settled)}`);
  row('steady', result.steady);
  row('panning', result.pan);
  row('zooming', result.zoom);
  console.log(`poll: render() ${result.poll.median} ms median, ${result.poll.max} ms max over ${result.poll.polls}`);
  console.log(`everything expanded: ${JSON.stringify(result.expandedDescribe)}`);
  row('steady, expanded', result.expandedSteady);
  row('panning, expanded', result.expandedPan);
  console.log(`poll, expanded: render() ${result.expandedPoll.median} ms median, ${result.expandedPoll.max} ms max over ${result.expandedPoll.polls}`);
}
if (JSON_OUT) fs.writeFileSync(JSON_OUT, `${JSON.stringify(result, null, 1)}\n`);
try { chrome.kill(); } catch { /* gone */ }
fs.rmSync(profile, { recursive: true, force: true, maxRetries: 3 });
process.exit(result.valid ? 0 : 1);
