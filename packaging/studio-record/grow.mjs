#!/usr/bin/env node
// Replay the hero capture fixture as it would have been written, one step at a
// time, so a screen recording shows a delegation assembling itself.
//
// This does not build a fixture and it does not talk to the server. It takes
// the finished fixture that make-capture-tree.mjs already wrote, snapshots it,
// and then re-lays it down in story order using the same three file shapes the
// panel already parses:
//
//   <sid>.jsonl                          the main transcript, written as prefixes
//   <sid>/subagents/agent-<id>.meta.json a node exists
//   <sid>/subagents/agent-<id>.jsonl     a node has a body, and an mtime
//
// Every status the panel shows is therefore produced the way the server
// derives it in studio/server/lib/graph.js, never asserted:
//
//   meta present, no jsonl ............................. starting
//   jsonl mtime within staleMs (120 s) of now .......... running
//   <task-notification><status>completed</status> ...... done
//   <task-notification><status>failed</status> ......... failed
//   toolUseResult{ status:"completed" } ................ done
//   jsonl mtime older than the transcript's last record  ended
//
// The two mtime-driven states are the ones that decay: "running" is a fact
// about the last two minutes, so held agents get touched on every step and on
// a heartbeat for as long as this process lives.

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

// Defaults live in the temp directory, never beside this script: the fixture and its snapshot are not source.
const WORK_TMP = path.join(os.tmpdir(), 'crewforth-studio-record');

/* -------------------------------------------------------------- arguments */

const DEFAULTS = {
  root: path.join(WORK_TMP, 'projects'),
  session: '7f3c1d20-9a4e-4b6f-8c21-5d0e2a41b9c7',
  delay: 1.2,
  lead: 0,
  hold: Infinity,          // seconds to keep "running" agents alive after the last step
  heartbeat: 15,
  snapshot: path.join(WORK_TMP, 'snapshot'),
  progress: null,
  reset: false,
  resnapshot: false,
};

function parseArgs(argv) {
  const a = { ...DEFAULTS };
  for (let i = 0; i < argv.length; i += 1) {
    const t = argv[i];
    const val = () => {
      const v = argv[i + 1];
      if (v === undefined) throw new Error(`${t} needs a value`);
      i += 1;
      return v;
    };
    if (t === '--reset') a.reset = true;
    else if (t === '--resnapshot') a.resnapshot = true;
    else if (t === '--root') a.root = val();
    else if (t === '--session') a.session = val();
    else if (t === '--snapshot') a.snapshot = val();
    else if (t === '--progress') a.progress = val();
    else if (t === '--heartbeat') a.heartbeat = Number(val());
    else if (t === '--hold') { const v = val(); a.hold = v === 'forever' ? Infinity : Number(v); }
    else if (t === '--delay') a.delay = Number(val());
    else if (t === '--lead') a.lead = Number(val());
    else if (/^-?\d+(\.\d+)?$/.test(t)) a.delay = Number(t);   // bare number: the step delay
    else if (t === '-h' || t === '--help') a.help = true;
    else throw new Error(`unknown argument: ${t}`);
  }
  for (const k of ['delay', 'heartbeat']) {
    if (!Number.isFinite(a[k]) || a[k] <= 0) throw new Error(`--${k} must be a positive number`);
  }
  // Zero is the default and means "no lead-in", so this one is >= 0, not > 0.
  if (!Number.isFinite(a.lead) || a.lead < 0) throw new Error('--lead must be zero or a positive number');
  if (!(a.hold === Infinity || (Number.isFinite(a.hold) && a.hold >= 0))) {
    throw new Error('--hold must be a number of seconds or "forever"');
  }
  return a;
}

/** Every failure here is a setup mistake, so it reads as one line, not a stack. */
function bail(e) {
  process.stderr.write(`grow-capture: ${e.message}\n`);
  process.exit(1);
}
const attempt = (fn) => { try { return fn(); } catch (e) { return bail(e); } };

const ARGS = attempt(() => parseArgs(process.argv.slice(2)));

if (ARGS.help) {
  process.stdout.write(`grow-capture.mjs — reveal an existing capture fixture step by step

  node grow-capture.mjs [seconds]        grow, default ${DEFAULTS.delay}s between steps
  node grow-capture.mjs --reset          put the fixture back to its finished state

  --root <dir>        projects root      (default ${DEFAULTS.root})
  --session <sid>     session to grow    (default ${DEFAULTS.session})
  --delay <sec>       step delay         (default ${DEFAULTS.delay})
  --lead <sec>        hold the emptied graph before the first step, so a recorder
                      that needs a few seconds to warm up still catches the start
  --hold <sec>        keep "running" agents fresh after the last step; "forever" (default)
  --heartbeat <sec>   touch interval while holding (default ${DEFAULTS.heartbeat})
  --progress <file>   write {step,total,note} after each step, for a capture tool to follow
  --snapshot <dir>    where the pristine copy lives (default ${DEFAULTS.snapshot})
  --resnapshot        overwrite the pristine copy from what is on disk now
`);
  process.exit(0);
}

/* ------------------------------------------------------------------ paths */

/** The project directory holding this session, found by asking the filesystem. */
function findSessionDir(root, sid) {
  let entries;
  try { entries = fs.readdirSync(root, { withFileTypes: true }); } catch {
    throw new Error(`projects root not readable: ${root}`);
  }
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    if (fs.existsSync(path.join(root, e.name, `${sid}.jsonl`))) return path.join(root, e.name);
  }
  throw new Error(`no ${sid}.jsonl under ${root}`);
}

const PROJ = attempt(() => findSessionDir(ARGS.root, ARGS.session));
const MAIN = path.join(PROJ, `${ARGS.session}.jsonl`);
const TREE = path.join(PROJ, ARGS.session);            // <sid>/subagents/...
const SUBS = path.join(TREE, 'subagents');
const WF_DIR = path.join(SUBS, 'workflows');

const SNAP = ARGS.snapshot;
const SNAP_MAIN = path.join(SNAP, 'session.jsonl');
const SNAP_TREE = path.join(SNAP, 'tree');
const SNAP_MANIFEST = path.join(SNAP, 'manifest.json');

/* -------------------------------------------------------------- utilities */

const mk = (p) => fs.mkdirSync(p, { recursive: true });
const rm = (p) => fs.rmSync(p, { recursive: true, force: true });

function walk(dir, base = dir, out = []) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, base, out);
    else out.push(path.relative(base, p));
  }
  return out;
}

function copyFile(from, to, mtimeMs) {
  mk(path.dirname(to));
  fs.copyFileSync(from, to);
  if (mtimeMs != null) {
    const s = mtimeMs / 1000;
    fs.utimesSync(to, s, s);
  }
}

const touch = (file) => {
  const s = Date.now() / 1000;
  try { fs.utimesSync(file, s, s); } catch { /* not laid down yet */ }
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/* ------------------------------------------------------------- the snapshot
 *
 * The fixture is the source of truth, so it is copied once and never
 * regenerated. Everything below reads the snapshot; the live tree is only ever
 * written. That is also what makes --reset exact: mtimes are recorded, not
 * recomputed, so a reset fixture is byte- and stat-identical to the one
 * make-capture-tree.mjs left behind.
 */

function takeSnapshot() {
  const records = readRecords(MAIN);
  const metas = walk(TREE).filter((r) => r.endsWith('.meta.json'));
  // A snapshot of a half-grown fixture would bake the growth in permanently.
  if (metas.length < 12 || records.length < 20) {
    throw new Error(
      `refusing to snapshot an incomplete fixture: ${metas.length} agent metas, `
      + `${records.length} main records (expected >=12 and >=20). `
      + 'Rebuild it with make-capture-tree.mjs, or pass --snapshot to point elsewhere.',
    );
  }

  rm(SNAP);
  mk(SNAP_TREE);
  const files = [];
  for (const rel of walk(TREE)) {
    const from = path.join(TREE, rel);
    const st = fs.statSync(from);
    copyFile(from, path.join(SNAP_TREE, rel), st.mtimeMs);
    files.push({ rel, mtimeMs: st.mtimeMs });
  }
  const mainMtime = fs.statSync(MAIN).mtimeMs;
  copyFile(MAIN, SNAP_MAIN, mainMtime);
  fs.writeFileSync(SNAP_MANIFEST, JSON.stringify({
    takenAt: new Date().toISOString(),
    session: ARGS.session,
    projectDir: PROJ,
    mainMtimeMs: mainMtime,
    files,
  }, null, 2) + '\n');
  return { files, count: files.length };
}

function readRecords(file) {
  return fs.readFileSync(file, 'utf8').split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l));
}

if (ARGS.resnapshot || !fs.existsSync(SNAP_MANIFEST)) {
  const s = attempt(takeSnapshot);
  process.stdout.write(`snapshot   ${SNAP} (${s.count} agent files + the transcript)\n`);
}

const MANIFEST = attempt(() => JSON.parse(fs.readFileSync(SNAP_MANIFEST, 'utf8')));
const SNAP_RECORDS = attempt(() => readRecords(SNAP_MAIN));
const ORIG_MTIME = new Map(MANIFEST.files.map((f) => [f.rel, f.mtimeMs]));

/* --------------------------------------------------------------- restoring */

function restoreFull() {
  rm(TREE);
  for (const f of MANIFEST.files) copyFile(path.join(SNAP_TREE, f.rel), path.join(TREE, f.rel), f.mtimeMs);
  copyFile(SNAP_MAIN, MAIN, MANIFEST.mainMtimeMs);
}

if (ARGS.reset) {
  attempt(restoreFull);
  const metas = walk(TREE).filter((r) => r.endsWith('.meta.json')).length;
  process.stdout.write(`reset      ${metas} agents, ${SNAP_RECORDS.length} main records restored to ${MAIN}\n`);
  process.stdout.write('           "running" nodes decay after 120 s — refresh-running.sh keeps them alive\n');
  process.exit(0);
}

/* ------------------------------------------------------- the file the panel
 * reads for each agent, resolved from the snapshot rather than guessed. */

function relFor(agentId, ext) {
  const flat = path.join('subagents', `agent-${agentId}${ext}`);
  if (ORIG_MTIME.has(flat)) return flat;
  for (const rel of ORIG_MTIME.keys()) {
    if (path.basename(rel) === `agent-${agentId}${ext}`) return rel;   // workflow member
  }
  return null;
}

function layMeta(agentId) {
  const rel = relFor(agentId, '.meta.json');
  if (!rel) throw new Error(`no meta for agent ${agentId} in the snapshot`);
  copyFile(path.join(SNAP_TREE, rel), path.join(TREE, rel), ORIG_MTIME.get(rel));
}

/** Lay down a transcript with a fresh mtime: that is what "running" is made of. */
function layBody(agentId) {
  layMeta(agentId);
  const rel = relFor(agentId, '.jsonl');
  if (!rel) throw new Error(`no transcript for agent ${agentId} in the snapshot`);
  copyFile(path.join(SNAP_TREE, rel), path.join(TREE, rel), Date.now());
}

/** Put an agent's transcript back on its recorded mtime: it stops looking live. */
function settle(agentId) {
  const rel = relFor(agentId, '.jsonl');
  if (!rel) return;
  const to = path.join(TREE, rel);
  if (!fs.existsSync(to)) return;
  const s = ORIG_MTIME.get(rel) / 1000;
  fs.utimesSync(to, s, s);
}

function writeMainPrefix(upto) {
  const slice = SNAP_RECORDS.slice(0, upto + 1);
  fs.writeFileSync(MAIN, slice.map((r) => JSON.stringify(r)).join('\n') + '\n');
  return slice.length;
}

/* ------------------------------------------------------- the record markers
 *
 * Cut points are found by what the record contains, not by counting: a fixture
 * that gains a turn should move the cuts with it or fail loudly, never silently
 * cut in the wrong place.
 */

function cutAfter(marker, offset = 0) {
  const i = SNAP_RECORDS.findIndex((r) => JSON.stringify(r).includes(marker));
  if (i < 0) throw new Error(`marker not found in the snapshot transcript: ${marker}`);
  return i + offset;
}

const CUT = attempt(() => ({
  opening: cutAfter('toolu_agent_9c1f4a72', -1),      // the ask, before any delegation
  spawnExplorer: cutAfter('toolu_agent_9c1f4a72'),
  explorerBack: cutAfter('toolu_grep_unique', 1),     // result, notice, and the turn that reads it
  spawnBackend: cutAfter('toolu_agent_3e7b10d5'),
  backendBack: cutAfter('<task-id>b48d29e1</task-id>'),
  spawnThree: cutAfter('toolu_agent_f20a7c63'),
  spawnDocs: cutAfter('toolu_agent_1a6c3d95'),
  workflowStart: cutAfter('toolu_wf_start', 1),       // the run, and the line that says it started
  auditClean: cutAfter('<task-id>4f81ca20</task-id>'),
  auditFailed: cutAfter('<status>failed</status>', 1),
  spawnLate: cutAfter('toolu_agent_7b2e94af', 1),     // and the title the session finally earned
}));

/* ------------------------------------------------------------- the 14 steps */

const STEPS = [
  { note: 'session spawns Explore 9c1f4a72 — meta only, so it reads "starting"',
    main: CUT.spawnExplorer, meta: ['9c1f4a72'] },

  { note: 'Explore starts writing — transcript appears, "running"',
    body: ['9c1f4a72'], hold: ['9c1f4a72'] },

  { note: 'Explore reports; the completion notice lands — "done"',
    main: CUT.explorerBack, settle: ['9c1f4a72'] },

  { note: 'session spawns crew-backend-expert 3e7b10d5 — "running"',
    main: CUT.spawnBackend, body: ['3e7b10d5'], hold: ['3e7b10d5'] },

  { note: 'crew-backend-expert spawns its own crew-test-expert b48d29e1 — depth 2, hanging off its parent',
    body: ['b48d29e1'], hold: ['b48d29e1'] },

  { note: 'both come back — result record for the parent, notice for the child',
    main: CUT.backendBack, settle: ['3e7b10d5', 'b48d29e1'] },

  { note: 'three in parallel: crew-frontend-expert, crew-database-expert, crew-performance-expert',
    main: CUT.spawnThree, body: ['f20a7c63', '5d93be08', 'c7e58f14'], hold: ['f20a7c63', '5d93be08', 'c7e58f14'] },

  { note: 'general-purpose 1a6c3d95 joins them',
    main: CUT.spawnDocs, body: ['1a6c3d95'], hold: ['1a6c3d95'] },

  { note: 'release-audit workflow starts — first two members fill the container',
    main: CUT.workflowStart, body: ['4f81ca20', 'e6390d7b'], hold: ['4f81ca20', 'e6390d7b'] },

  { note: 'the other two workflow members arrive — container now holds four',
    body: ['2c74a9f6', 'af5b1e38'], hold: ['2c74a9f6', 'af5b1e38'] },

  { note: 'three of the four audit checks report clean',
    main: CUT.auditClean, settle: ['4f81ca20', 'e6390d7b', '2c74a9f6'] },

  { note: 'the claude-code-guide stops on disagreeing version carriers — "failed"',
    main: CUT.auditFailed, settle: ['af5b1e38'] },

  { note: 'general-purpose goes quiet behind the transcript — "ended", not stale',
    settle: ['1a6c3d95'] },

  { note: 'one more is queued: Explore 7b2e94af, meta only — "starting"',
    main: CUT.spawnLate, meta: ['7b2e94af'] },
];

/* ---------------------------------------------------------------- the run */

const keepFresh = new Set();

function refresh() {
  for (const id of keepFresh) {
    const rel = relFor(id, '.jsonl');
    if (rel) touch(path.join(TREE, rel));
  }
  return keepFresh.size;
}

function emptyOut() {
  rm(TREE);
  mk(SUBS);
  mk(WF_DIR);                       // the workflow container's home, still empty
  return writeMainPrefix(CUT.opening);
}

function writeProgress(step, note) {
  if (!ARGS.progress) return;
  fs.writeFileSync(ARGS.progress, JSON.stringify({
    step, total: STEPS.length, note, at: new Date().toISOString(),
  }) + '\n');
}

let heartbeat = null;
process.on('SIGINT', () => {
  if (heartbeat) clearInterval(heartbeat);
  process.stdout.write('\nstopped    fixture is mid-growth; `--reset` puts it back\n');
  process.exit(0);
});

async function main() {
  const opening = emptyOut();
  process.stdout.write(`fixture    ${MAIN}\n`);
  process.stdout.write(`emptied    session transcript kept (${opening} record), 0 agents on disk\n`);
  writeProgress(0, 'emptied');

  // A recorder needs a moment to launch a browser and settle. Without a lead-in
  // it starts filming after the graph has already been emptied AND partly
  // rebuilt — or worse, while the finished fixture is still on disk, so the film
  // opens on the full graph, blinks empty, and starts over.
  if (ARGS.lead > 0) {
    process.stdout.write(`lead       holding the empty graph for ${ARGS.lead}s before step 1\n`);
    await sleep(ARGS.lead * 1000);
  }

  const t0 = Date.now();
  for (let i = 0; i < STEPS.length; i += 1) {
    const s = STEPS[i];
    await sleep(ARGS.delay * 1000);

    let records = null;
    if (s.main != null) records = writeMainPrefix(s.main);
    for (const id of s.meta ?? []) layMeta(id);
    for (const id of s.body ?? []) layBody(id);
    for (const id of s.hold ?? []) keepFresh.add(id);
    for (const id of s.settle ?? []) { keepFresh.delete(id); settle(id); }
    refresh();

    const n = String(i + 1).padStart(2, '0');
    const at = ((Date.now() - t0) / 1000).toFixed(1).padStart(5, ' ');
    const detail = [
      records != null ? `${records} records` : null,
      keepFresh.size ? `${keepFresh.size} held live` : null,
    ].filter(Boolean).join(', ');
    process.stdout.write(`[${n}/${STEPS.length}] ${at}s  ${s.note}${detail ? `  (${detail})` : ''}\n`);
    writeProgress(i + 1, s.note);
  }

  if (ARGS.hold === 0) {
    process.stdout.write('done       not holding; the 3 "running" nodes decay in 120 s\n');
    return;
  }

  const forever = ARGS.hold === Infinity;
  process.stdout.write(`holding    ${keepFresh.size} agents kept "running", touched every ${ARGS.heartbeat}s`
    + `${forever ? ' — Ctrl-C to stop' : ` for ${ARGS.hold}s`}\n`);

  await new Promise((resolve) => {
    heartbeat = setInterval(() => {
      process.stdout.write(`heartbeat  ${refresh()} agents kept "running" at ${new Date().toTimeString().slice(0, 8)}\n`);
    }, ARGS.heartbeat * 1000);
    if (!forever) setTimeout(() => { clearInterval(heartbeat); resolve(); }, ARGS.hold * 1000);
  });

  process.stdout.write('done       hold expired; `--reset` puts the fixture back\n');
}

main().catch((e) => {
  process.stderr.write(`grow-capture: ${e.message}\n`);
  process.exit(1);
});
