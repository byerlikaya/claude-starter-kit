#!/usr/bin/env node
// Studio's offline gate. No network, no CLI, no tokens spent — so it can be
// wired into CI and run on every change.
//
// Everything here is hermetic: fixtures and temp directories only, never this
// checkout's own state. An assertion that reads the author's machine is a gate
// that is green for one person and red for everyone else.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { _internals } from '../../kit/studio/server/lib/fleet.js';
import { contextFill } from '../../kit/studio/server/lib/transcript.js';
import { encodeCwd } from '../../kit/studio/server/lib/projects.js';
import { _internals as graphInternals } from '../../kit/studio/server/lib/graph.js';
import { palette, _internals as paletteInternals } from '../../kit/studio/server/lib/palette.js';
import { renderMarkdown } from '../../kit/studio/web/md.js';
import { ALLOWED_MODES } from '../../kit/studio/server/lib/session.js';
import { parsePeers } from '../../kit/studio/server/lib/peers.js';
import { writeAllowed, signature } from '../../kit/studio/server/index.js';
import { prepare, decide, pending, cleanup, _internals as permInternals } from '../../kit/studio/server/lib/permissions.js';
import { execFileSync, spawnSync } from 'node:child_process';
import os from 'node:os';
import { quickReplies } from '../../kit/studio/web/chat.js';
import { installDom } from './dom-stub.mjs';
import { plan as terminalPlan } from '../../kit/studio/server/lib/terminal.js';
import { gateLog, gateReport, board, sessionStats, _internals as kitInternals } from '../../kit/studio/server/lib/kit-telemetry.js';
import { parseRoster, remoteRoster } from '../../kit/studio/server/lib/roster.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
// The suite lives beside the other gates rather than inside the panel, because
// kit/ is shipped whole: a test directory under it would travel to
// every user through all three channels only to be deleted by the installer.
// 104 KB of it, measured. So the panel is named from the repo root, not walked
// up to from here.
const REPO = path.resolve(HERE, '..', '..');
const PAYLOAD = path.join(REPO, 'kit');
const STUDIO = path.join(PAYLOAD, 'studio');
const WEB_ROOT = path.join(STUDIO, 'web');

let pass = 0;
let fail = 0;
let skipped = 0;
let na = 0;
const failures = [];

function check(name, ok, detail) {
  if (ok) {
    pass += 1;
  } else {
    fail += 1;
    failures.push(`${name}${detail ? ` — ${detail}` : ''}`);
  }
  process.stdout.write(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ` — ${detail}` : ''}\n`);
}

/**
 * A check that could not run, said out loud.
 *
 * `tool` means the machine is missing something the check needs. Under
 * CREW_VERIFY_STRICT — which CI sets — that is a broken runner, not an honest
 * boundary, so it goes red. Every other class stays a skip.
 */
/**
 * An assertion that does not apply on this platform, and is measured on another.
 *
 * Distinct from skip() on purpose. `tool` skips mean "this could have been
 * measured and was not", so CREW_VERIFY_STRICT turns them red — a runner missing
 * a tool is a broken runner. A capability the platform does not have is a
 * different statement: it stays green here because it is red-or-green somewhere
 * else, and saying so is the only way the strict rule keeps its meaning.
 *
 * Use it only where another assertion covers the same ground on the platform
 * that has the feature. Never as a way to make a failing check quiet.
 */
function notApplicable(name, why, coveredBy) {
  na += 1;
  process.stdout.write(`N/A  ${name} — ${why}; covered by: ${coveredBy}\n`);
}

function skip(name, kind, why) {
  const strict = process.env.CREW_VERIFY_STRICT === '1' && kind === 'tool';
  if (strict) {
    fail += 1;
    failures.push(`${name} — required ${kind} missing: ${why}`);
  } else {
    skipped += 1;
  }
  process.stdout.write(`${strict ? 'FAIL' : 'SKIP'} ${name} — ${kind}: ${why}\n`);
}

function read(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return null; }
}

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name === '.git' || e.name === 'recordings') continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

/* ---------------------------------------------------------------- §1 pins
   Five assertions that keep Studio on its side of the fence. Each one is a
   boundary that, once crossed, is expensive to walk back. */

process.stdout.write('\n== §1 boundary pins ==\n');

const rootPkg = JSON.parse(read(path.join(REPO, 'package.json')) ?? '{}');

// Inverted, not deleted. The old pin held the panel OUT of every channel; a
// real project then updated, ran the documented command and got ENOENT, because
// nothing had ever installed it. The claim now runs the other way and has to
// fail the moment the panel stops shipping: `kit/` is the one string
// every channel already carries (npm files[], make-release.sh's whitelist,
// bin/cli.js's staging list, the Homebrew formula), so living under it is what
// makes "installed" true rather than a fourth place to remember.
const shipsPayload = Array.isArray(rootPkg.files) && rootPkg.files.some((f) => String(f).replace(/\/$/, '') === 'kit');
const insidePayload = path.basename(PAYLOAD) === 'kit';
const carried = ['server/index.js', 'web/index.html', 'package.json', 'ensure-node.sh']
  .filter((f) => fs.existsSync(path.join(STUDIO, f)));
check(
  'pin: studio ships inside the payload every channel installs',
  shipsPayload && insidePayload && carried.length === 4,
  `payload dir = ${path.basename(PAYLOAD)}, files[] = ${JSON.stringify(rootPkg.files)}, carried = ${carried.join(' ')}`,
);

// Silently load-bearing: every server file is ESM. Without this manifest beside
// them node reads them as CommonJS and the panel installs cleanly, then dies on
// its first import — a failure the user meets, not the build.
const typeField = JSON.parse(read(path.join(STUDIO, 'package.json')) ?? '{}').type;
check(
  'pin: the installed tree declares "type": "module"',
  typeField === 'module',
  `type = ${JSON.stringify(typeField)}`,
);

const rootDeps = Object.keys(rootPkg.dependencies ?? {}).length;
const rootDevDeps = Object.keys(rootPkg.devDependencies ?? {}).length;
check(
  'pin: the root package still carries zero dependencies',
  rootDeps === 0 && rootDevDeps === 0,
  `${rootDeps} deps, ${rootDevDeps} devDeps`,
);

const studioPkg = JSON.parse(read(path.join(STUDIO, 'package.json')) ?? '{}');
const sDeps = Object.keys(studioPkg.dependencies ?? {}).length;
check(
  'pin: studio itself carries zero dependencies',
  sDeps === 0 && !fs.existsSync(path.join(STUDIO, 'node_modules')),
  `${sDeps} deps, node_modules ${fs.existsSync(path.join(STUDIO, 'node_modules')) ? 'PRESENT' : 'absent'}`,
);

const studioFiles = walk(STUDIO).filter((f) => /\.(js|mjs|sh|py|html|css|json|md)$/.test(f));
const bypassHits = studioFiles.filter((f) => {
  const src = read(f) ?? '';
  return /bypassPermissions|dangerously-skip-permissions/.test(src);
});
check(
  'pin: studio never names a permission bypass',
  bypassHits.length === 0,
  bypassHits.length ? bypassHits.map((f) => path.relative(REPO, f)).join(', ') : `${studioFiles.length} files scanned`,
);

const serverSrc = read(path.join(STUDIO, 'server', 'index.js')) ?? '';
check(
  'pin: the server binds loopback and nothing else',
  serverSrc.includes("const LOOPBACK = '127.0.0.1'") &&
    !/0\.0\.0\.0|::\s*'|listen\([^)]*,\s*['"]0/.test(serverSrc),
  null,
);

/* ------------------------------------------------------- §2 static guard
   Proved directly, because a live HTTP probe cannot reach this branch: the
   URL parser collapses "/../" before the handler sees it. A gate that only
   ever passes through a second gate has not been measured. */

process.stdout.write('\n== §2 static path guard ==\n');

function guard(urlPath) {
  const rel = urlPath === '/' ? '/index.html' : urlPath;
  const abs = path.resolve(WEB_ROOT, `.${rel}`);
  return abs === WEB_ROOT || abs.startsWith(WEB_ROOT + path.sep);
}

for (const [p, want] of [
  ['/', true],
  ['/index.html', true],
  ['/app.js', true],
  ['/style.css', true],
  ['/../package.json', false],
  ['/../../VERSION', false],
  ['/../../../etc/passwd', false],
  ['/a/b/../../../../secrets', false],
]) {
  check(`guard ${want ? 'allows' : 'blocks'} ${p}`, guard(p) === want, null);
}

/* ------------------------------------------------- §3 fleet normalisation
   "Not measured" and "nothing running" must never collapse into each other,
   and an unknown field must survive rather than be dropped. */

process.stdout.write('\n== §3 fleet normalisation ==\n');

const { normalise } = _internals;

const real = normalise({
  pid: 71288, cwd: '/tmp/x', kind: 'interactive',
  startedAt: 1787667229756, sessionId: 'abc-123', name: 'mac-session', status: 'busy',
});
check('normalise keeps the identifying fields', real?.sessionId === 'abc-123' && real.name === 'mac-session' && real.status === 'busy');
check('normalise surfaces waitingFor when present',
  normalise({ sessionId: 'w', status: 'waiting', waitingFor: 'input needed' })?.waitingFor === 'input needed');
check('normalise keeps waitingFor null when absent', real?.waitingFor === null);
check('normalise drops rows with no session id', normalise({ pid: 1 }) === null);
check('normalise survives junk', normalise(null) === null && normalise('x') === null && normalise(42) === null);
check('normalise labels an unknown status rather than guessing',
  normalise({ sessionId: 'u', status: 'teleporting' })?.status === 'teleporting');
check('normalise defaults a missing status to "unknown"',
  normalise({ sessionId: 'u' })?.status === 'unknown');
check('normalise carries unknown fields through untouched',
  normalise({ sessionId: 'u', futureField: 7 })?.raw?.futureField === 7);

/* ------------------------------------------------------ §4 honest states
   The UI must have a distinct rendering for "nothing was read". Pin the
   strings, because this is the one lie the panel exists to prevent. */

process.stdout.write('\n== §4 honest empty states ==\n');

const appSrc = read(path.join(WEB_ROOT, 'app.js')) ?? '';
check('ui: renders a distinct "Not measured" state', /Not measured/.test(appSrc));
check('ui: says outright that unmeasured is not the same as empty',
  /not the same as "nothing is running"/i.test(appSrc));
check('ui: has a separate state for a measured but empty fleet',
  /No sessions running/.test(appSrc));
check('ui: reports the reason a read failed', /data\.reason/.test(appSrc));

/* ------------------------------------------------------- §5 the poison
   The kit paid for this lesson once: a 92%-full context reported as 0.9%.
   When a subagent returns, its tool_result lands in the MAIN transcript as a
   `type:"user"` record carrying `toolUseResult.usage`. That is the subagent's
   spend, not the session's. Same fixture as smoke-test.sh:980. */

process.stdout.write('\n== §5 context fill, the poisoned record ==\n');

const A_REC = { type: 'assistant', isSidechain: false, message: { usage: { input_tokens: 1000, cache_creation_input_tokens: 0, cache_read_input_tokens: 800000, output_tokens: 5 } } };
const SIDE_REC = { type: 'assistant', isSidechain: true, message: { usage: { input_tokens: 5, cache_creation_input_tokens: 0, cache_read_input_tokens: 30000, output_tokens: 1 } } };
const POISON_REC = { type: 'user', isSidechain: false, message: { role: 'user', content: 'x' }, toolUseResult: { usage: { input_tokens: 25, cache_creation_input_tokens: 1344, cache_read_input_tokens: 8000, output_tokens: 9 } } };

const fill = contextFill([A_REC, SIDE_REC, POISON_REC]);
check("a returning subagent's toolUseResult.usage is NOT the session's fill", fill === 801000, `expected 801000, measured ${fill}`);
check('a sidechain record does not count toward the session', fill !== 831005);
check('an empty transcript yields null, not zero', contextFill([]) === null);

/* -------------------------------------------------- §6 transcript paths */

process.stdout.write('\n== §6 transcript path encoding ==\n');

check('cwd folds : \\ / . _ down to -',
  encodeCwd('/Users/x/Projects/my.app_v2') === '-Users-x-Projects-my-app-v2',
  encodeCwd('/Users/x/Projects/my.app_v2'));
// C: contributes two dashes (the colon and the following separator); each
// remaining backslash contributes one. Verified against the encoder, not guessed.
check('a windows path folds too',
  encodeCwd('C:\\Users\\x\\proj') === 'C--Users-x-proj',
  encodeCwd('C:\\Users\\x\\proj'));

/* --------------------------------------------- §7 completion harvesting */

process.stdout.write('\n== §7 completion notices ==\n');

const seen = new Map();
graphInternals.harvestCompletions(
  '<task-notification><task-id>abc123</task-id><status>completed</status></task-notification>', seen);
check('a completion notice is read out of prose', seen.get('abc123') === 'completed');

const multi = new Map();
graphInternals.harvestCompletions(
  '<task-id>one</task-id><status>completed</status> ... <task-id>two</task-id><status>failed</status>', multi);
check('two notices in one blob are both read', multi.get('one') === 'completed' && multi.get('two') === 'failed');
check('a status other than completed is carried, not normalised', multi.get('two') === 'failed');

const none = new Map();
graphInternals.harvestCompletions('no notice here', none);
check('prose without a notice yields nothing', none.size === 0);

/* --------------------------------------------------------- §8 palette */

process.stdout.write('\n== §8 palette ==\n');

const pal = palette();
// Counted off disk in this same run rather than pinned to a constant: an agent
// added to the payload must not turn this red, and a resolver that finds the
// wrong directory must not stay green because it happened to find twelve of
// something. `>= 12` would have passed on a partial read.
const agentsOnDisk = fs.readdirSync(path.join(PAYLOAD, 'agents')).filter((f) => f.endsWith('.md')).length;
check('every kit agent in the payload is in the palette',
  pal.measured === true && pal.kitAgents === agentsOnDisk,
  `${pal.kitAgents} in the palette, ${agentsOnDisk} .md files in ${path.relative(REPO, path.join(PAYLOAD, 'agents'))}`);
check('a declared colour resolves to a hex value', /^#[0-9a-f]{6}$/i.test(pal.map['crew-security-expert']?.hex ?? ''));
check('an undeclared agent type falls back to neutral, never a borrowed colour',
  !pal.map['no-such-agent-type'] && /^#[0-9a-f]{6}$/i.test(pal.unknown));

// The resolver against synthetic trees, because the claim is "one rule, every
// layout" and this checkout can only ever demonstrate one of them. Install and
// repo differ in depth and in the parent's name; the rule may read neither.
const palHome = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-studio-palette-'));
try {
  const shapes = {
    install: path.join(palHome, 'install', '.claude'),
    repo: path.join(palHome, 'repo', 'kit'),
    // The third layout, and the one the comment above claimed in prose while nothing measured it: a
    // plugin root has no `.claude` or `kit` segment at all — agents/ and studio/ sit
    // directly in it. Now that the plugin edition ships the panel, this is a real deployment.
    plugin: path.join(palHome, 'plugin', 'crewforth'),
  };
  for (const base of Object.values(shapes)) {
    fs.mkdirSync(path.join(base, 'agents'), { recursive: true });
    fs.mkdirSync(path.join(base, 'studio', 'server', 'lib'), { recursive: true });
  }
  for (const [name, base] of Object.entries(shapes)) {
    const got = paletteInternals.agentsDirFor(path.join(base, 'studio', 'server', 'lib'));
    check(`palette resolves the agents dir in the ${name} layout`,
      got === path.join(base, 'agents'), `got ${got}`);
  }
  const orphan = path.join(palHome, 'orphan', 'studio', 'server', 'lib');
  fs.mkdirSync(orphan, { recursive: true });
  check('palette returns null where no agents dir sits beside the panel',
    paletteInternals.agentsDirFor(orphan) === null,
    `got ${paletteInternals.agentsDirFor(orphan)}`);
} finally {
  fs.rmSync(palHome, { recursive: true, force: true });
}
// …and the unresolved case must be reported, not drawn. `palette()` caches, so
// the shape is asserted on the module's own contract: measured false carries a
// reason, and the UI reads that flag rather than an empty map.
check('an unresolved palette is reported as not measured, with the directory it looked in',
  pal.measured === true ? typeof pal.agentsDir === 'string' && pal.reason === null
    : pal.reason?.includes(pal.agentsDir) === true,
  `measured=${pal.measured} dir=${pal.agentsDir}`);
check('ui: an unresolved palette is labelled, not drawn as neutral rings',
  /p\.measured === false/.test(read(path.join(WEB_ROOT, 'app.js')) ?? ''));

/* ---------------------------------------------- §9 report rendering ---
   Agent reports are untrusted text: an agent can quote anything it read from
   the repo, including markup. Only known constructs are re-introduced after
   escaping, so nothing in a report can become an element. */

process.stdout.write('\n== §9 markdown is escaped before it is rendered ==\n');

const ALLOWED = /^(\/?)(p|h[1-6]|ul|ol|li|code|pre|strong|em|hr|blockquote|div|table|thead|tbody|tr|th|td|span)\b/;
const attacks = [
  '<script>alert(1)</script>',
  '**bold** <img src=x onerror=alert(1)>',
  '> quote with <svg onload=alert(1)>',
  '`<iframe src=evil>`',
  '| a | <b>x</b> |\n|---|---|\n| y | z |',
];
for (const a of attacks) {
  const tags = [...renderMarkdown(a).matchAll(/<([^>]*)>/g)].map((m) => m[1]);
  const bad = tags.filter((t) => !ALLOWED.test(t));
  check(`report text cannot inject markup: ${JSON.stringify(a.slice(0, 30))}`, bad.length === 0, bad.join(', ') || null);
}
check('a link never becomes an href', !/href/i.test(renderMarkdown('[x](javascript:alert(1))')));
check('headings and tables still render', /<h\d/.test(renderMarkdown('## h')) && /<table/.test(renderMarkdown('| a |\n|---|\n| 1 |')));

/* ------------------------------------------- §10 the write surface ---
   The panel can now start a session and send it messages, which makes it
   worth attacking. These pin the shape of that surface. */

process.stdout.write('\n== §10 owned sessions ==\n');

check('permission modes are an allow-list, not a deny-list',
  Array.isArray(ALLOWED_MODES) && ALLOWED_MODES.length > 0 && ALLOWED_MODES.every((m) => typeof m === 'string'),
  ALLOWED_MODES.join(', '));
check('the default mode is the least permissive one offered',
  ALLOWED_MODES[0] === 'plan',
  `first is ${ALLOWED_MODES[0]}`);

const idxSrc = read(path.join(STUDIO, 'server', 'index.js')) ?? '';
// Exercised, not grepped. An earlier version of this pin only looked for the
// header's name in the source, and survived the check being replaced with
// `if (false)` — a gate that cannot fail is not a gate.
const req = (headers) => ({ headers });
check('a request without the header is refused',
  writeAllowed(req({})).ok === false);
check('a request with the wrong header value is refused',
  writeAllowed(req({ 'x-crew-studio': '0' })).ok === false);
check('a same-origin request with the header is allowed',
  writeAllowed(req({ 'x-crew-studio': '1', origin: 'http://127.0.0.1:7777' })).ok === true);
check('localhost counts as same-origin',
  writeAllowed(req({ 'x-crew-studio': '1', origin: 'http://localhost:7777' })).ok === true);
check('a cross-origin request is refused even with the header',
  writeAllowed(req({ 'x-crew-studio': '1', origin: 'https://evil.example' })).ok === false);
check('an unparseable Origin is refused rather than ignored',
  writeAllowed(req({ 'x-crew-studio': '1', origin: 'not a url' })).ok === false);
check('a request with no Origin at all still needs the header',
  writeAllowed(req({ 'x-crew-studio': '1' })).ok === true &&
  writeAllowed(req({ origin: 'http://127.0.0.1:7777' })).ok === false);
check('a token always exists, generated when none was supplied',
  /CREW_STUDIO_TOKEN \|\| randomUUID\(\)/.test(idxSrc));
check('the token gate covers every /api/ path',
  /url\.pathname\.startsWith\('\/api\/'\) && !authorised/.test(idxSrc));

const sessSrc = read(path.join(STUDIO, 'server', 'lib', 'session.js')) ?? '';
check('owned sessions are spawned with an id we chose, so the transcript lands where the graph reads it',
  /'--session-id', this\.id/.test(sessSrc));
check('children are stopped when the server is', /stopAll/.test(idxSrc) && /export function stopAll/.test(sessSrc));

/* ------------------------------------------------------- §11 peers ---
   A peer is another machine. Reaching one must never widen this one. */

process.stdout.write('\n== §11 peers ==\n');

const [p1] = parsePeers(['http://127.0.0.1:7778']);
check('a bare peer URL parses', p1.base === 'http://127.0.0.1:7778' && !p1.token);
const [p2] = parsePeers(['http://:tok@127.0.0.1:7780']);
check('a peer token is taken off the URL, not left in it', p2.token === 'tok' && !p2.base.includes('tok'));
const [p3] = parsePeers([']]not a url']);
check('an unparseable peer is reported, not silently dropped', p3.error === 'not a URL');
check('the server binds loopback whatever the peer list says',
  /server\.listen\(args\.port, LOOPBACK/.test(idxSrc));

/* ------------------------------------------- §12 the permission gate ---
   Measured on this machine: a PreToolUse hook killed at its configured timeout
   emits nothing and the tool PROCEEDS — permission_denials came back 0 and the
   command ran. So the hook must decide for itself first, and these pin the
   invariant that makes that true. */

process.stdout.write('\n== §12 permission bridge ==\n');

const { HOOK, HOOK_WAIT_S, HARNESS_TIMEOUT_S } = permInternals;

check('the hook exists and is executable', (() => {
  try { fs.accessSync(HOOK, fs.constants.X_OK); return true; } catch { return false; }
})(), HOOK);

check('the hook answers well before the harness would kill it',
  HOOK_WAIT_S < HARNESS_TIMEOUT_S,
  `hook ${HOOK_WAIT_S}s vs harness ${HARNESS_TIMEOUT_S}s`);

const probeId = `selfcheck-${process.pid}`;
const gate = prepare(probeId);
check('prepare writes a settings file', Boolean(gate) && fs.existsSync(gate.settingsPath));

if (gate) {
  const cfg = JSON.parse(fs.readFileSync(gate.settingsPath, 'utf8'));
  const entry = cfg.hooks?.PreToolUse?.[0];
  check('the gate covers every tool, not a chosen few', entry?.matcher === '*', `matcher ${entry?.matcher}`);
  check('the settings file is ours, not the user\'s',
    gate.settingsPath.startsWith(os.tmpdir()), gate.settingsPath);
  check('the configured timeout leaves the hook room to answer',
    entry?.hooks?.[0]?.timeout > HOOK_WAIT_S);
  // Left to the default, Claude Code runs the hook through PowerShell on Windows when it does not detect Git Bash; the
  // VAR=… prefix is not PowerShell and the gate fails open.
  check('the gate names its shell (bash), so PowerShell never runs it',
    entry?.hooks?.[0]?.shell === 'bash', `shell ${entry?.hooks?.[0]?.shell}`);

  // Behaviour, not text. Each case runs the real hook.
  const payload = JSON.stringify({
    session_id: probeId, tool_name: 'Bash', tool_use_id: 'toolu_probe',
    tool_input: { command: 'echo probe' },
  });
  const runHook = (env = {}) => {
    try {
      execFileSync('bash', [HOOK, gate.spool], {
        input: payload,
        env: { ...process.env, CREW_GATE_WAIT: '1', ...env },
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      return 0;
    } catch (e) {
      return e.status ?? -1;
    }
  };

  check('silence is a denial, not an opening', runHook() === 2);

  fs.writeFileSync(path.join(gate.spool, 'ans', 'toolu_probe'), 'deny\n');
  check('a deny blocks', runHook() === 2);

  fs.writeFileSync(path.join(gate.spool, 'ans', 'toolu_probe'), 'allow\n');
  check('an allow lets the tool through', runHook() === 0);

  // The discriminating control: without the answer file the same call is
  // refused, so the allow above measured the answer rather than the harness.
  check('the allow was the answer, not the absence of a gate', runHook() === 2);

  fs.writeFileSync(path.join(gate.spool, 'always', 'Bash'), '');
  check('an always-allowed tool skips the round trip', runHook() === 0);
  fs.rmSync(path.join(gate.spool, 'always', 'Bash'));

  check('a request is visible to the panel while the hook waits', (() => {
    fs.writeFileSync(path.join(gate.spool, 'req', 'toolu_seen.json'), payload);
    const seen = pending(probeId).find((r) => r.toolUseId === 'toolu_seen');
    // The command itself, not just the tool's name: nobody can approve what
    // they cannot read.
    return seen?.toolName === 'Bash' && seen?.detail === 'echo probe';
  })());

  check('an unknown verdict is refused', decide(probeId, 'toolu_probe', 'maybe').ok === false);
  check('a tool use id that is not an identifier is refused',
    decide(probeId, '../escape', 'allow').ok === false);

  cleanup(probeId);
  check('cleanup removes the spool', !fs.existsSync(gate.spool));
}

/* -------------------------------------------- §13 quick replies ------
   A headless session is not given AskUserQuestion — measured: absent from the
   78-tool list in both permission modes, present in an interactive session. So
   options arrive as prose, and the panel only makes them clickable. The rule
   for when prose counts as a question is what these pin: too loose and every
   bulleted list grows buttons. */

process.stdout.write('\n== §13 quick replies ==\n');

const qr = [
  ['two options under a question', 'Which do you prefer?\n\n1. **Tabs**\n2. **Spaces**', 2],
  ['three options', 'How should I proceed?\n- Rebase\n- Merge\n- Leave it', 3],
  ['a list that answers rather than asks', 'Here is what I found:\n- one\n- two\n- three', 0],
  ['a single option is not a choice', 'Shall I?\n1. Yes', 0],
  ['a long list is a report', 'Which?\n1. a\n2. b\n3. c\n4. d\n5. e\n6. f', 0],
  ['a paragraph-length item is not a button', `Which?\n1. ${'x'.repeat(90)}\n2. short`, 0],
  ['nothing at all', '', 0],
  ['prose with no list', 'Do you want me to continue?', 0],
];
for (const [name, text, want] of qr) {
  const got = quickReplies(text).length;
  check(`quick replies: ${name}`, got === want, `${got} offered, expected ${want}`);
}
check('emphasis is stripped from the label',
  quickReplies('Which?\n1. **Tabs**\n2. `Spaces`')[0] === 'Tabs');

/* ------------------------------------------ §14 no raw shell, no python ---
   The panel once offered raw shells behind a flag. They were the one surface the
   kit's gates could not see — a command typed there never becomes a tool call —
   and the only reason the panel needed python3. Shell work goes through a
   session's Bash tool, where the gates apply. These pin that it stays that way:
   one bash path, no python3, on every OS. They read this checkout's files and
   run its server entry point, nothing about the machine. */

process.stdout.write('\n== §14 no raw shell, no python ==\n');
{
  const RAW_SHELL = /python3|pty-bridge|\/api\/pty|enable-pty/;
  const files = walk(STUDIO);
  const hits = files.filter((f) => RAW_SHELL.test(read(f) ?? ''))
    .map((f) => path.relative(REPO, f));
  // A scan that saw nothing proves nothing, so the count is part of the verdict.
  check(`no studio file names python3, the pty bridge, /api/pty or --enable-pty (${files.length} files read)`,
    files.length > 0 && hits.length === 0,
    files.length === 0 ? 'the walk found no files — the scan is broken, not clean' : hits.join(', '));

  // Behaviour, not text: the server's own parser has to turn the flag away. An
  // unknown argument is rejected with exit 64 and says which one, so a flag that
  // was quietly re-accepted, or quietly ignored, both show here.
  const r = spawnSync(process.execPath, [path.join(STUDIO, 'server', 'index.js'), '--enable-pty'],
    { encoding: 'utf8', timeout: 20000 });
  check('the server rejects --enable-pty as an unknown argument',
    r.status === 64 && /unknown argument: --enable-pty/.test(r.stderr ?? ''),
    `rc=${r.status} stderr=${JSON.stringify((r.stderr ?? '').trim().slice(0, 200))}`);
}

// Behaviour: the plan a terminal launch would run, quoted.
process.stdout.write('\n== §15 handing a session to a real terminal ==\n');

const tp = terminalPlan({ cwd: "/tmp/it's here", sessionId: 'abc-123' });
check('a path with a quote in it cannot break out of the command',
  tp.line.includes("/tmp/it'\\''s here") || tp.line.includes(String.raw`it'\''s here`),
  tp.line);
check('the session id is quoted too', tp.line.includes("'abc-123'"));
check('the plan is inspectable before anything launches', typeof tp.line === 'string' && tp.line.length > 0);

/* ------------------------------------------- §16 the kit's own numbers ---
   The panel reports what the kit's tools said, including when they said they
   could not answer. The distinction these pin is the one that would be easiest
   to lose: a decision found in a log is not a decision seen happening. */

process.stdout.write('\n== §16 kit telemetry ==\n');

// A fixture, not this checkout. These read a gate log, and a gate log only
// exists on a machine that has actually run the guard hooks — it is gitignored.
// Pointed at REPO these four passed here and failed 4/4 on a fresh clone, which
// is the worst kind of gate: green for the author, red for everyone else, and
// silent about the difference.
const logHome = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-studio-gatelog-'));
fs.mkdirSync(path.join(logHome, '.claude'), { recursive: true });
fs.writeFileSync(path.join(logHome, '.claude', 'gate-log.tsv'),
  ['BLOCK\t§4.1\tdestructive\tgit reset --hard',
    'BLOCK\t§4.1\tdestructive\trm -rf /',
    'ASK\t§2.3\tcommit-approval\tgit commit -m x',
    'ALLOW\t§2.3\tcommit-approval\tgit status',
    ''].join('\n'));

let own;
try {
  own = gateLog(logHome);
} finally {
  fs.rmSync(logHome, { recursive: true, force: true });
}
check('the gate log is read where it exists', own.measured === true, own.reason ?? `${own.total} entries`);
check('every record in the fixture is read back, and no more',
  own.total === 4 && own.counts.BLOCK === 2 && own.counts.ASK === 1 && own.counts.ALLOW === 1,
  `a parser that drops or invents records would still satisfy a "> 0 entries" check (got ${JSON.stringify(own.counts)})`);
check('the log is marked as carrying no timestamps',
  own.measured && own.timestamped === false,
  'the format has no timestamp column, and the panel must not imply one');
check('whether commands were recorded is stated, not assumed',
  own.measured && own.commandsRecorded === true);
check('verdicts are counted', own.measured && typeof own.counts?.BLOCK === 'number', JSON.stringify(own.counts));

const noLog = gateLog(os.tmpdir());
check('a project with no gate log says so rather than showing an empty list',
  noLog.measured === false && /no .claude\/gate-log/.test(noLog.reason ?? ''),
  noLog.reason);
check('"not measured" never carries entries', (noLog.entries ?? []).length === 0);

check('the kit is found in an installed layout and in this source checkout',
  kitInternals.kitPaths(REPO)?.kind === 'source' && kitInternals.kitPaths(os.tmpdir()) === null);

const rep = await gateReport(os.tmpdir());
check('a directory without the kit is told so', rep.measured === false, rep.reason);

const brd = await board(REPO);
check('a repo with no board reports a state, not a failure',
  brd.measured === true && brd.present === false,
  brd.text ?? brd.reason);

const st = await sessionStats(REPO, path.join(os.tmpdir(), 'definitely-not-a-transcript.jsonl'));
check('missing transcript is reported rather than guessed at', st.measured === false, st.reason);

/* ------------------------------------------ §17 reach and continuity ---
   Two things a reader tried and could not do. */

process.stdout.write('\n== §17 opening and continuing ==\n');

const canvasSrc = read(path.join(STUDIO, 'web', 'canvas.js')) ?? '';
check('a node that hides others opens when the card is clicked, not only its 20px control',
  /hiddenCount\(n\.id\) > 0/.test(canvasSrc) && /cv-container/.test(canvasSrc));
check('the card says what a click will do', /Click to show/.test(canvasSrc));
// The session node has children too, so treating every parent as a container
// made a click on it fold the entire graph instead of opening its conversation.
check('the session node opens rather than folds when its card is clicked',
  /node\.kind !== 'session' && this\.hiddenCount/.test(canvasSrc));

const sessSrc2 = read(path.join(STUDIO, 'server', 'lib', 'session.js')) ?? '';
check('an existing conversation can be continued rather than started over',
  /--resume/.test(sessSrc2));
check('continuing forks, so the original transcript is never the one being written',
  /--fork-session/.test(sessSrc2));
check('the session to resume must be an identifier',
  /is not an identifier/.test(sessSrc2));

/* ---------------------------------------- §18 sessions on other machines ---
   Only a session connected to Remote Control can see them — measured: a
   headless session's ListAgents returns the local peers where a connected one
   returns those plus five remote, and passing --remote-control to a headless
   session does not change it. So the panel reads what a connected session
   already recorded, and says when. */

process.stdout.write('\n== §18 remote roster ==\n');

// Synthetic throughout. Real session names are machine-private, and a fixture
// is exactly where one would slip into the repo unnoticed.
const sample = [
  'This session is alpha [aaa111] — the name other sessions use to message it.',
  '',
  'Peer sessions (3):',
  '  bravo [bbb222]  ·  interactive  ·  idle  ·  started 3h ago',
  '  charlie [ccc333]  ·  Remote Control  ·  running',
  '  delta [ddd444]  ·  Remote Control  ·  offline',
].join('\n');

const parsed = parseRoster(sample);
check('the roster block is parsed', parsed !== null && parsed.peers.length === 3);
check('the session names itself', parsed?.self?.name === 'alpha');
check('a machine elsewhere is told apart from one here',
  parsed?.peers.filter((p) => p.remote).length === 2);
check('status survives', parsed?.peers.find((p) => p.name === 'charlie')?.status === 'running');
check('free text after the status is carried, not parsed into a time it may not be',
  parsed?.peers.find((p) => p.name === 'bravo')?.note === 'started 3h ago');
check('prose without a roster yields nothing', parseRoster('there are no peers here') === null);
check('an empty block yields nothing, not an empty roster', parseRoster('Peer sessions (0):') === null);

const live = await remoteRoster();
check('the roster is either measured or says why not',
  live.measured === true || typeof live.reason === 'string',
  live.measured ? `${live.remotes} remote, seen ${new Date(live.seenAt).toISOString()}` : live.reason);
check('a measured roster says when it was seen, never implying now',
  live.measured !== true || (typeof live.seenAt === 'number' && live.live === false));

const rosterSrc = read(path.join(STUDIO, 'server', 'lib', 'roster.js')) ?? '';
check('records are parsed rather than grepped, because the block is JSON-escaped',
  /JSON\.parse\(line\)/.test(rosterSrc),
  'a line-anchored regex over the raw tail matched nothing: the newlines in it are two characters, not one');

/* ------------------------------------------------------- §19 history ---
   A resumed session remembers what was said; the panel did not draw it, so
   continuing a conversation looked exactly like starting one. And a session
   the panel cannot write to is still one it can read. */

process.stdout.write('\n== §19 conversation history ==\n');

const chatSrc2 = read(path.join(STUDIO, 'web', 'chat.js')) ?? '';
check('a resumed pane loads what was said before it',
  /loadHistory/.test(chatSrc2) && /resumedFrom/.test(chatSrc2));
check('the seam between history and this run is drawn, not implied',
  /chat-seam/.test(chatSrc2) && /forked from \$\{from/.test(chatSrc2));
check('an observed session is shown but not writable',
  /openReadOnly/.test(chatSrc2) && /readOnly/.test(chatSrc2));
check('the read-only pane says why it cannot be written to, and what to do instead',
  /has no way in/.test(chatSrc2) && /fork &amp; continue/.test(chatSrc2));
// A fork reads as "I am now typing into that session" unless the UI says
// otherwise, and the user then wonders why their terminal stays silent. Both
// the seam and the read-only notice must say the two are separate.
check('the panel never lets a fork pass for the session it copied',
  /the original does not see this/.test(chatSrc2)
  && /never reach your terminal/.test(chatSrc2),
  'calling it "continued" made a copy look like a live channel into the terminal');

// The fix that made this worth distinguishing: a terminal continues a session
// by resuming it, and so does the panel now — but only when nothing else holds
// it open. Forking unconditionally was the bug; forking never would be worse.
{
  const sess = read(path.join(STUDIO, 'server', 'lib', 'session.js')) ?? '';
  check('a resume is only forked when the session is still held open',
    /const forked = resume \? await isHeldOpen/.test(sess),
    'forking every resume moved the user to a stranger; forking none would let two processes write one transcript');
  check('a true continuation keeps the id it is continuing',
    /const sessionId = resume && !forked \? String\(resume\) : randomUUID\(\)/.test(sess));
  check('--session-id is not sent alongside a bare resume',
    /args\.push\('--resume', this\.resumedFrom\);/.test(sess)
    && /\} else \{\s*\n\s*args\.push\('--session-id', this\.id\);/.test(sess),
    'asking for a new id while resuming an old one is a contradiction the CLI has to resolve');
  check('an unreadable fleet forks rather than risking two writers',
    /if \(fleet && fleet\.measured === false\) return true;/.test(sess),
    'treating "not measured" as "not running" is the kit\'s oldest mistake, in a new place');
  check('the panel refuses to run one session twice',
    /the panel is already running that session/.test(sess));
}

const graphSrc = read(path.join(STUDIO, 'server', 'lib', 'graph.js')) ?? '';
check('a subagent exchange is left out of the conversation it was not part of',
  /isSidechain === true\) continue/.test(graphSrc) && /parent_tool_use_id\) continue/.test(graphSrc));
check('command envelopes are not shown as things someone said',
  /command-name\|command-message/.test(graphSrc));
check('a truncated history says how much was left out',
  /truncated/.test(graphSrc) && /total - conv\.messages\.length|conv\.total/.test(chatSrc2));

/* -------------------------------------------- §20 the modules evaluate ---
   A syntax check parses; it does not run. Both of today's page-killing bugs
   parsed cleanly — a const read inside its temporal dead zone, and an
   identifier whose declaration had been deleted out from under it. Each module
   is loaded against a stub DOM so that class of failure is caught here rather
   than by a blank page. */

process.stdout.write('\n== §20 browser modules load ==\n');

{
  const cleanup = installDom();
  for (const mod of ['md.js', 'canvas.js', 'chat.js', 'app.js']) {
    let err = null;
    try {
      // Cache-busted so a module is really evaluated on every run.
      await import(`../../kit/studio/web/${mod}?t=${Date.now()}`);
    } catch (e) {
      err = e;
    }
    check(`${mod} evaluates`, err === null, err ? `${err.name}: ${err.message}` : null);
  }
  // Loading a module runs what runs at load. Rendering is where the rest of it
  // lives — and a method calling a helper this file never had threw there,
  // silently, leaving the group labels missing with no error anyone saw.
  {
    let err = null;
    try {
      const { Canvas } = await import(`../../kit/studio/web/canvas.js?render=${Date.now()}`);
      const host = document.createElement('div');
      const c = new Canvas(host, {});
      c.setPalette({ map: { Explore: { hex: '#26c6e6', source: 'builtin' } }, unknown: '#94a3c8' });
      c.setSession('fixture');
      c.render({
        nodes: [
          { id: 'session', kind: 'session', label: 's', turns: 1, cwd: '/x' },
          { id: 'a1', kind: 'agent', agentType: 'Explore', status: 'done', spawnDepth: 1, parentId: 'session', tools: { Bash: 2 }, toolCount: 2 },
          { id: 'a2', kind: 'agent', agentType: 'Explore', status: 'running', spawnDepth: 1, parentId: 'session', tools: {}, toolCount: 0 },
          { id: 'w1', kind: 'workflow', members: 3, byStatus: { done: 3 }, spawnDepth: 1, parentId: 'session' },
        ],
        edges: [
          { id: 'e1', source: 'session', target: 'a1', kind: 'spawn' },
          { id: 'e2', source: 'session', target: 'a2', kind: 'spawn' },
          { id: 'e3', source: 'session', target: 'w1', kind: 'spawn' },
        ],
        stats: {},
      });
    } catch (e) {
      err = e;
    }
    check('the canvas renders a graph without throwing', err === null,
      err ? `${err.name}: ${err.message}` : null);
  }

  cleanup();
}

/* --------------------------------- §21 nothing is used undeclared ------
   Loading a module proves what runs at load. It says nothing about a handler
   that only runs on a click — which is where the second of today's bugs lived:
   a Set used in three places whose declaration had been deleted, so the module
   evaluated fine and the page broke the moment anyone clicked.
 
   This looks for the shape that bug had: a name used as a collection, but
   declared nowhere in its file. Narrow on purpose — a general scope checker is
   a linter, and this is the failure that actually happened. */

process.stdout.write('\n== §21 collections are declared ==\n');

// Not preceded by a dot: `this.collapsed.has(...)` is a property, not a name
// this file has to declare.
const COLLECTION_USE = /(?<![.\w$])([a-z][A-Za-z0-9_]*)\.(?:has|add|delete|clear)\(/g;
const GLOBALS = new Set(['localStorage', 'sessionStorage', 'classList', 'dataset', 'document', 'window', 'store', 'headers', 'params', 'searchParams']);

for (const mod of ['app.js', 'chat.js', 'canvas.js']) {
  const src = read(path.join(STUDIO, 'web', mod)) ?? '';
  const used = new Set();
  let m;
  while ((m = COLLECTION_USE.exec(src)) !== null) used.add(m[1]);

  const missing = [];
  for (const name of used) {
    if (GLOBALS.has(name)) continue;
    // Declared here, imported here, or bound as a parameter of a function in
    // this file. Anything else is a name nothing in the file creates.
    const declared = new RegExp(
      String.raw`(?:const|let|var|function|class)\s+${name}\b`
      + String.raw`|import[^;]*\b${name}\b`
      + String.raw`|\(\s*(?:[^)]*,\s*)?${name}\s*[,)]`
      + String.raw`|\{[^}]*\b${name}\b[^}]*\}\s*=`,
    ).test(src);
    if (!declared) missing.push(name);
  }
  check(`${mod}: every collection it uses is declared in it`, missing.length === 0,
    missing.length ? `used but never declared: ${missing.join(', ')}` : `${used.size} checked`);
}

/* ------------------------------------------------------ §22 the layout ---
   Three columns, two dividers, and a conversation that reads like one. */

process.stdout.write('\n== §22 layout ==\n');

const cssSrc = read(path.join(STUDIO, 'web', 'style.css')) ?? '';
// Six columns since the redesign: the inspector has one of its own between the
// stage and the conversation. The claim is unchanged — the conversation is the
// last column of the same row as the stage.
check('the conversation is a column beside the graph, not a drawer under it',
  /\.shell\s*\{[^}]*grid-template-columns:\s*var\(--side-w,\s*var\(--nav-w\)\)\s+5px\s+minmax\(0,\s*1fr\)\s+auto\s+5px\s+var\(--chat-w/.test(cssSrc.replace(/\/\*[\s\S]*?\*\//g, '')));
check('who spoke is read from which side it sits on',
  /\.msg-user\s*\{\s*align-items:\s*flex-end/.test(cssSrc)
  && /\.msg-assistant\s*\{\s*align-items:\s*flex-start/.test(cssSrc));
check('either panel can be collapsed without leaving a gap where it was',
  /\.shell\.no-side/.test(cssSrc) && /\.shell\.no-chat/.test(cssSrc));
// A hidden grid child occupies no cell, so auto-flow slides everything after it
// one column left: hiding the sidebar handed the graph the rail's 22px and gave
// the conversation the rest of the window.
check('every column is placed explicitly rather than by auto-flow',
  /\.shell > \.stage\s*\{\s*grid-column:\s*3/.test(cssSrc)
  && /\.shell > \.chat\s*\{\s*grid-column:\s*6/.test(cssSrc)
  && /\.shell\.no-chat > \.inspector\s*\{[^}]*grid-column:\s*4/.test(cssSrc),
  'stage 3, docked inspector 4, conversation 6');
check('the control that reopens the sidebar is on the edge it acts on',
  /\.side-rail\s*\{[^}]*left:\s*0/.test(cssSrc),
  'it started in the header, in the opposite corner from the panel it opens');

const appSrc2 = read(path.join(STUDIO, 'web', 'app.js')) ?? '';
check('the right-hand divider grows its panel when dragged left',
  /edge === 'right' \? -1 : 1/.test(appSrc2),
  'sharing one handler without inverting the delta shrank the panel being opened');
check('both widths are remembered', /crewforth-studio-side-w/.test(appSrc2) && /crewforth-studio-chat-w/.test(appSrc2));

// 3.0 renamed the saved-layout keys. The move is run against a Map-backed storage, so what is asserted is the
// behaviour — the layout survives, the old key is gone, a value already under the new name is not overwritten —
// and not the source text. And the panel must call it before it reads any key.
{
  const { migrateStorage } = await import(`../../kit/studio/web/storage-migrate.js?t=${Date.now()}`);
  const m = new Map([['csk-studio-theme', 'dark'], ['csk-studio-layout:down:s1', '{"a":1}'],
    ['csk-studio-side-w', '300'], ['crewforth-studio-side-w', '410'], ['unrelated', 'x']]);
  const ls = { get length() { return m.size; }, key: (i) => [...m.keys()][i] ?? null,
    getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: (k) => m.delete(k) };
  const moved = migrateStorage(ls);
  check('a 2.x saved layout survives the key rename (moved, old key removed, newer value kept)',
    moved === 3 && m.get('crewforth-studio-theme') === 'dark' && m.get('crewforth-studio-layout:down:s1') === '{"a":1}'
      && m.get('crewforth-studio-side-w') === '410' && m.get('unrelated') === 'x'
      && ![...m.keys()].some((k) => k.startsWith('csk-studio-')),
    JSON.stringify([...m.entries()]));
  check('a second open moves nothing', migrateStorage(ls) === 0);
  const firstRead = appSrc2.search(/store\.get\(|localStorage\.getItem\(/);
  // The theme is read inside theme.js now, so the call that starts it is a read too.
  const themeRead = appSrc2.indexOf('initTheme(');
  check('the panel migrates the keys before it reads any', /migrateStorage\(localStorage\)/.test(appSrc2)
    && appSrc2.indexOf('migrateStorage(localStorage)') < firstRead
    && themeRead !== -1 && appSrc2.indexOf('migrateStorage(localStorage)') < themeRead,
  `first read at ${firstRead}, theme read at ${themeRead}`);
}


/* ------------------------------------------- §23 launching from a symlink */

// Every global install path puts a symlink on PATH: `npm link`, `npm i -g`,
// Homebrew. The direct-run guard compares import.meta.url against argv[1], and
// argv[1] is then the symlink while import.meta.url is the real file. Getting
// this wrong is invisible — the command exits 0 having printed nothing.
//
// Grepping for `realpathSync` would pass on a guard wrapped in `if (false)`.
// So run it: a symlink into a temp dir, invoked with --help, must produce the
// usage text. A regressed guard prints nothing and still exits 0.
{
  const entry = path.join(STUDIO, 'server', 'index.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-studio-link-'));
  const link = path.join(dir, 'crewforth-studio');
  let viaLink = '';
  let viaReal = '';
  try {
    fs.symlinkSync(entry, link);
    const run = (target) => execFileSync(process.execPath, [target, '--help'], {
      encoding: 'utf8', timeout: 20000, stdio: ['ignore', 'pipe', 'pipe'],
    });
    viaLink = run(link);
    viaReal = run(entry);
  } catch (e) {
    viaLink = `ERROR ${e?.message ?? e}`;
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }

  check('the entry point runs when invoked through a symlink',
    /--port/.test(viaLink),
    `a symlinked bin printed nothing — comparing raw argv[1] to import.meta.url `
    + `makes every global install a silent no-op. got: ${JSON.stringify(viaLink.slice(0, 120))}`);
  check('the symlinked invocation matches the direct one',
    viaLink === viaReal && viaReal.length > 0,
    'the two paths diverged, so the guard is doing something path-dependent');
}


/* --------------------------------- §26 delegation reads as motion ------
   The graph was correct and inert. A viewer could see that two cards were
   connected and could not see which way the work went or which branch was
   alive, which is the one thing the panel exists to show.

   Grepping the stylesheet for "animation" would pass on a sheet that animates
   nothing, and grepping for a keyframe name would pass on one whose rule never
   matches any element. So this section does two things instead. It renders
   real fixtures through the canvas and reads what the canvas produced. And it
   resolves the stylesheet the way a browser would — parse, match, sort by
   specificity then source order — and asserts the values that come out. The
   second half caught a real bug on its first run: the reduced-motion rules
   were a hundred points of specificity short of the rules they had to beat,
   so asking for less motion changed nothing. */

process.stdout.write('\n== §26 delegation reads as motion ==\n');

/* A cascade small enough to trust — enough CSS to answer "what would the
   browser compute here", which is the only question this section asks. */

function cssRules(src) {
  const clean = src.replace(/\/\*[\s\S]*?\*\//g, '');
  const out = [];
  let order = 0;
  const walk = (text, media) => {
    let i = 0;
    while (i < text.length) {
      const open = text.indexOf('{', i);
      if (open === -1) break;
      const prelude = text.slice(i, open).trim();
      let depth = 1;
      let j = open + 1;
      while (j < text.length && depth > 0) {
        if (text[j] === '{') depth += 1;
        else if (text[j] === '}') depth -= 1;
        j += 1;
      }
      const body = text.slice(open + 1, j - 1);
      if (/^@media\b/.test(prelude)) {
        walk(body, media.concat(prelude.replace(/^@media\s*/, '').trim()));
      } else if (!prelude.startsWith('@')) {
        // Keyframe blocks are not cascade rules and drop out here with every
        // other at-rule; they are read separately, by name, below.
        const decls = new Map();
        for (const part of body.split(';')) {
          const k = part.indexOf(':');
          if (k === -1) continue;
          const prop = part.slice(0, k).trim();
          if (prop) decls.set(prop, part.slice(k + 1).trim());
        }
        for (const sel of prelude.split(',')) {
          const s = sel.trim();
          if (s) out.push({ sel: s, decls, media, order: (order += 1) });
        }
      }
      i = j;
    }
  };
  walk(clean, []);
  return out;
}

/** The body of a named at-rule, brace-balanced. */
function atRule(src, name) {
  const i = src.indexOf(name);
  if (i === -1) return '';
  const open = src.indexOf('{', i);
  if (open === -1) return '';
  let depth = 1;
  let j = open + 1;
  while (j < src.length && depth > 0) {
    if (src[j] === '{') depth += 1;
    else if (src[j] === '}') depth -= 1;
    j += 1;
  }
  return src.slice(open + 1, j - 1);
}

/** Which properties a keyframe block actually animates. */
function animates(body) {
  return new Set([...body.matchAll(/([a-z-]+)\s*:/g)].map((m) => m[1]));
}

const CSS_TOKEN = /^[a-zA-Z][\w-]*|\.[\w-]+|#[\w-]+|\[[^\]]*\]|::?[\w-]+(?:\([^)]*\))?|\*/g;

function compound(s) {
  const out = { tag: null, id: null, classes: [], attrs: [], pseudos: [], bad: false };
  for (const t of s.match(CSS_TOKEN) ?? []) {
    if (t === '*') continue;
    else if (t.startsWith(':')) out.pseudos.push(t);
    else if (t.startsWith('.')) out.classes.push(t.slice(1));
    else if (t.startsWith('#')) out.id = t.slice(1);
    else if (t.startsWith('[')) {
      const m = /^\[([\w-]+)(?:=["']?([^\]"']*)["']?)?\]$/.exec(t);
      if (m) out.attrs.push([m[1], m[2] ?? null]); else out.bad = true;
    } else out.tag = t.toLowerCase();
  }
  return out;
}

/** An element is `{ tag, classes:Set, attrs:{}, pseudo }`. A pseudo-class the
 *  probes do not model — `:hover`, `:not(…)` — never matches, which is the
 *  right answer here: none of these probes is hovered or is the root. */
function hits(c, el) {
  if (c.bad || c.id) return false;
  if (c.tag && c.tag !== el.tag) return false;
  for (const k of c.classes) if (!el.classes.has(k)) return false;
  for (const [name, val] of c.attrs) {
    const have = el.attrs[name];
    if (have === undefined) return false;
    if (val !== null && String(have) !== val) return false;
  }
  const want = c.pseudos.map((p) => (p.startsWith('::') ? p : `:${p}`));
  if (want.length === 0) return el.pseudo == null;
  return want.length === 1 && want[0] === el.pseudo;
}

function selMatches(sel, el, ancestors) {
  const toks = sel.trim().split(/\s+/).filter(Boolean);
  const last = toks.pop();
  if (!hits(compound(last), el)) return false;
  let ai = ancestors.length - 1;                 // ancestors run outermost first
  for (let i = toks.length - 1; i >= 0; i -= 1) {
    const t = toks[i];
    if (t === '+' || t === '~') return false;    // siblings are not modelled
    if (t === '>') {
      i -= 1;
      if (ai < 0 || !hits(compound(toks[i]), ancestors[ai])) return false;
      ai -= 1;
      continue;
    }
    const c = compound(t);
    let found = false;
    while (ai >= 0) {
      const anc = ancestors[ai];
      ai -= 1;
      if (hits(c, anc)) { found = true; break; }
    }
    if (!found) return false;
  }
  return true;
}

function specificity(sel) {
  let b = 0;
  let c = 0;
  for (const t of sel.split(/\s+|>|\+|~/).filter(Boolean)) {
    const p = compound(t);
    b += p.classes.length + p.attrs.length + p.pseudos.filter((x) => !x.startsWith('::')).length;
    c += (p.tag ? 1 : 0) + p.pseudos.filter((x) => x.startsWith('::')).length;
  }
  return b * 100 + c;
}

function computed(rules, el, ancestors, media = []) {
  const on = new Set(media);
  const won = rules
    .filter((r) => r.media.every((m) => on.has(m)) && selMatches(r.sel, el, ancestors))
    .sort((x, y) => specificity(x.sel) - specificity(y.sel) || x.order - y.order);
  const out = new Map();
  for (const r of won) for (const [k, v] of r.decls) out.set(k, v);
  return out;
}

{
  const dom = installDom();
  const cssText = read(path.join(STUDIO, 'web', 'style.css')) ?? '';
  const rules = cssRules(cssText);
  const REDUCE = ['(prefers-reduced-motion: reduce)'];

  const { Canvas } = await import(`../../kit/studio/web/canvas.js?motion=${Date.now()}`);
  const PAL = {
    map: {
      Explore: { hex: '#26c6e6', source: 'builtin' },
      Plan: { hex: '#a874f5', source: 'builtin' },
      reviewer: { hex: '#35c874', source: 'kit' },
      tester: { hex: '#f2a65a', source: 'kit' },
    },
    unknown: '#94a3c8',
  };

  const kid = (id, status, type = 'Explore', parentId = 'session') =>
    ({ id, kind: 'agent', agentType: type, status, spawnDepth: 1, parentId, tools: {}, toolCount: 0 });
  const root = (turns = 1) => ({ id: 'session', kind: 'session', status: 'session', turns, cwd: '/x' });

  const FIXTURE = {
    nodes: [
      root(3),
      // One status each, and all of one type on purpose: the distinguishability
      // check below reads the whole painted signature, and if these carried
      // different agent colours they would come out "different" on identity
      // rather than on status. `alt` is the one that varies, for the identity
      // check that does want two colours.
      kid('live', 'running'),
      kid('wake', 'starting'),
      kid('fin', 'done'),
      kid('bad', 'failed'),
      kid('over', 'ended'),
      kid('old', 'stale'),
      kid('alt', 'done', 'reviewer'),
      { id: 'w1', kind: 'workflow', status: 'running', members: 3, byStatus: { running: 3 }, spawnDepth: 1, parentId: 'session' },
      kid('m1', 'running', 'Explore', 'w1'),
      kid('m2', 'running', 'reviewer', 'w1'),
      kid('m3', 'running', 'tester', 'w1'),
    ],
    edges: [
      { source: 'session', target: 'live' }, { source: 'session', target: 'wake' },
      { source: 'session', target: 'fin' }, { source: 'session', target: 'bad' },
      { source: 'session', target: 'over' }, { source: 'session', target: 'old' },
      { source: 'session', target: 'alt' },
      { source: 'session', target: 'w1' },
      { source: 'w1', target: 'm1' }, { source: 'w1', target: 'm2' }, { source: 'w1', target: 'm3' },
    ],
  };

  const canvas = new Canvas(document.createElement('div'), {});
  canvas.setPalette(PAL);
  canvas.setSession('motion-fixture');
  canvas.render(FIXTURE);
  // Every edge in a first render is an arrival, so all of them are drawing
  // themselves right now. Wait the arrival out before reading steady state —
  // and the wait is itself the assertion below that the class comes off again.
  await new Promise((r) => { setTimeout(r, 500); });

  // The canvas keys an edge by its endpoints joined on NUL, the one character
  // a node id cannot contain. Built here rather than pasted, so a literal
  // control byte stays out of this file.
  const SEP = String.fromCharCode(0);
  const edgeIn = (cv, from, to) => cv.edgeEls.get([from, to].join(SEP));
  const edge = (from, to) => edgeIn(canvas, from, to);
  const dataAttrs = (el) => Object.fromEntries(
    Object.entries(el.dataset).map(([k, v]) => [`data-${k.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`)}`, v]),
  );
  // The stub keeps setAttribute('class') and classList apart; a browser does
  // not, and the canvas legitimately uses both on one path.
  const classesOf = (el) => new Set([
    ...String(el.getAttribute('class') ?? '').split(/\s+/).filter(Boolean),
    ...el.classList._s,
  ]);
  // The chain a path really hangs in, carrying the root's own attributes — the
  // motion budget is expressed there, so a probe that invented the chain would
  // never see it.
  const chainFor = (cv) => [
    { tag: 'div', classes: new Set(['cv-root']), attrs: dataAttrs(cv.root), pseudo: null },
    { tag: 'div', classes: new Set(['cv-viewport']), attrs: {}, pseudo: null },
    { tag: 'svg', classes: new Set(['cv-edges']), attrs: {}, pseudo: null },
    { tag: 'g', classes: new Set(['cv-edge-g']), attrs: {}, pseudo: null },
  ];
  const pathStyle = (cv, el, media) => computed(
    rules, { tag: 'path', classes: classesOf(el), attrs: dataAttrs(el), pseudo: null }, chainFor(cv), media,
  );
  const styleOf = (el, media) => pathStyle(canvas, el, media);
  const asDrawing = (state, media) => computed(rules, {
    tag: 'path', classes: new Set(['cv-edge', 'cv-drawing']), attrs: { 'data-state': state }, pseudo: null,
  }, chainFor(canvas), media);

  const moving = (m) => {
    const a = m.get('animation');
    return Boolean(a) && a !== 'none' && !/(^|\s)0s(\s|$)/.test(a);
  };

  // A probe that matched nothing would make every assertion below vacuously
  // true, so it is asked for a value that is known to be there first.
  check('the cascade probe resolves a rule that is known to exist',
    styleOf(edge('session', 'live')).get('fill') === 'none',
    'the selector matcher found no .cv-edge rule at all — every result below would be empty');
  // An arrival that never ends is a graph where every edge animates the
  // draw-in forever and no edge ever shows its status.
  check('the draw-in takes itself off again',
    [...canvas.edgeEls.values()].every((p) => !p.classList.contains('cv-drawing')),
    `${[...canvas.edgeEls.values()].filter((p) => p.classList.contains('cv-drawing')).length}`
    + ' edges were still drawing half a second after they arrived');

  /* -- 1. motion, and which way it points ------------------------------- */

  const live = styleOf(edge('session', 'live'));
  const fin = styleOf(edge('session', 'fin'));
  check('an edge into a working agent is in motion', moving(live),
    `resolved animation: ${JSON.stringify(live.get('animation') ?? null)}`);
  check('an edge into a finished agent is not', !moving(fin),
    `resolved animation: ${JSON.stringify(fin.get('animation') ?? null)}`);

  // Direction is two facts together: the curve is drawn starting at the
  // parent, and the offset animates negative, which walks the pattern toward
  // the far end. Either one alone says nothing about which way work flows.
  const start = /^M\s*([-\d.]+)\s+([-\d.]+)/.exec(edge('session', 'live').getAttribute('d') ?? '');
  const parentPos = canvas.pos.get('session');
  check('the curve starts at the parent, so "along the path" means "toward the child"',
    Boolean(start) && Number(start[2]) > parentPos.y && Number(start[2]) <= parentPos.y + 105,
    `d starts at ${start ? `${start[1]},${start[2]}` : '?'} and the parent sits at ${parentPos.x},${parentPos.y}`);
  check('the dash travels parent to child rather than back up the wire',
    /stroke-dashoffset:\s*calc\(\s*-1\s*\*/.test(atRule(cssText, '@keyframes cv-flow')),
    `a positive offset runs the dashes the wrong way. keyframe: ${JSON.stringify(atRule(cssText, '@keyframes cv-flow').trim())}`);

  // A dash pattern and a travel distance that disagree put a seam in every
  // loop, and the two moving states do not share a pattern.
  for (const [id, want] of [['live', '6px 7px'], ['wake', '2px 7px']]) {
    const m = styleOf(edge('session', id));
    const period = Number(String(m.get('--dash-period') ?? '').replace('px', ''));
    const sum = String(m.get('stroke-dasharray') ?? '').split(/\s+/)
      .reduce((t, v) => t + Number(String(v).replace('px', '')), 0);
    check(`the ${id} edge advances exactly one dash period per loop`,
      m.get('stroke-dasharray') === want && period === sum && period > 0,
      `dasharray ${m.get('stroke-dasharray')} sums to ${sum}, period is ${period}`);
  }

  /* -- 2. the edge carries the child's identity ------------------------- */

  check('an edge is stroked with the colour of the card it feeds',
    edge('session', 'live').style.stroke === PAL.map.Explore.hex
    && edge('session', 'alt').style.stroke === PAL.map.reviewer.hex,
    `got ${edge('session', 'live').style.stroke} and ${edge('session', 'alt').style.stroke}`);
  check('the edge colour comes from the same call the card colour does',
    edge('session', 'fin').style.stroke === canvas.nodeColor(canvas.nodes.get('fin')));
  // The old edge code read the agent palette only, so an edge into a container
  // fell through to the unknown grey while the card itself was purple — the
  // one branch a viewer most needs to follow was the one that did not match.
  check('an edge into a workflow container is not painted as an unknown agent',
    edge('session', 'w1').style.stroke === canvas.nodeColor(canvas.nodes.get('w1'))
    && edge('session', 'w1').style.stroke !== PAL.unknown,
    `got ${edge('session', 'w1').style.stroke}, unknown is ${PAL.unknown}`);

  /* -- 3. a workflow's members read as one system ----------------------- */

  const chan = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  const apart = (a, b) => Math.hypot(...chan(a).map((v, i) => v - chan(b)[i]));
  const wf = canvas.nodeColor(canvas.nodes.get('w1'));
  const members = ['m1', 'm2', 'm3'].map((id) => ({
    id,
    stroke: edge('w1', id).style.stroke,
    own: canvas.nodeColor(canvas.nodes.get(id)),
    group: edge('w1', id).dataset.group,
  }));
  check('every member edge is pulled toward the container it belongs to',
    members.every((m) => apart(m.stroke, wf) < apart(m.own, wf)),
    members.map((m) => `${m.id} ${m.own}->${m.stroke} (${apart(m.own, wf).toFixed(0)} -> ${apart(m.stroke, wf).toFixed(0)} from ${wf})`).join('; '));
  check('a member is still traceable back to its own card',
    new Set(members.map((m) => m.stroke)).size === 3,
    'blending all the way to the container would turn twelve members into one line');
  check('member edges are marked as members and spawn edges are not',
    members.every((m) => m.group === 'member') && edge('session', 'w1').dataset.group === 'spawn');
  check('the member bundle is drawn at one weight',
    new Set(members.map((m) => styleOf(edge('w1', m.id)).get('stroke-width'))).size === 1);

  /* -- 4. arrival ------------------------------------------------------- */

  {
    const c2 = new Canvas(document.createElement('div'), {});
    c2.setPalette(PAL);
    c2.setSession('arrival');
    c2.render({ nodes: [root(1), kid('a1', 'running')], edges: [{ source: 'session', target: 'a1' }] });
    const first = edgeIn(c2, 'session', 'a1');
    check('an edge to a node that just arrived draws itself',
      first.classList.contains('cv-drawing'));

    c2.render({
      nodes: [root(2), kid('a1', 'running'), kid('a2', 'starting', 'Plan')],
      edges: [{ source: 'session', target: 'a1' }, { source: 'session', target: 'a2' }],
    });
    check('only the new arrival draws; the edge that was already there does not',
      edgeIn(c2, 'session', 'a2').classList.contains('cv-drawing')
      && edgeIn(c2, 'session', 'a1') === first,
      'replaying a settled edge would perform the whole graph on every poll');

    // Unfolding is not arriving. An edge revealed by opening a group is new to
    // the DOM but its node is not new to the session, and treating the two the
    // same makes opening a 105-agent workflow perform itself.
    {
      const c4 = new Canvas(document.createElement('div'), {});
      c4.setPalette(PAL);
      c4.setSession('unfold');
      const grouped = {
        nodes: [
          root(1),
          { id: 'w', kind: 'workflow', status: 'running', members: 3, byStatus: { running: 3 }, spawnDepth: 1, parentId: 'session' },
          kid('u1', 'running', 'Explore', 'w'), kid('u2', 'running', 'Plan', 'w'), kid('u3', 'done', 'tester', 'w'),
        ],
        edges: [
          { source: 'session', target: 'w' },
          { source: 'w', target: 'u1' }, { source: 'w', target: 'u2' }, { source: 'w', target: 'u3' },
        ],
      };
      c4.render(grouped);
      c4.collapsed.add('w');
      c4.render(grouped);
      const hidden = ['u1', 'u2', 'u3'].every((id) => !edgeIn(c4, 'w', id));
      c4.collapsed.delete('w');
      c4.render(grouped);
      check('unfolding a group reveals its edges rather than performing them',
        hidden && ['u1', 'u2', 'u3'].every((id) => edgeIn(c4, 'w', id)
          && !edgeIn(c4, 'w', id).classList.contains('cv-drawing')),
        hidden
          ? `${['u1', 'u2', 'u3'].filter((id) => edgeIn(c4, 'w', id)?.classList.contains('cv-drawing')).length}`
            + ' of 3 revealed edges started drawing themselves'
          : 'folding did not take the member edges out of the layer, so the test proves nothing');
    }

    // The draw and the flow both drive stroke-dashoffset, so if the draw did
    // not win outright the two would fight and the arrival would stutter.
    check('the draw-in outranks the flow it briefly replaces',
      /cv-draw/.test(String(asDrawing('live').get('animation') ?? '')),
      `resolved to ${JSON.stringify(asDrawing('live').get('animation') ?? null)}`);
    // With the animation gone, the pattern has to go with it — a dasharray on
    // the class itself would survive animation:none and freeze a live edge
    // solid, or half drawn, for as long as the class is on.
    const drawKf = animates(atRule(cssText, '@keyframes cv-draw'));
    const drawnStill = asDrawing('live', REDUCE);
    check('an arriving edge with motion off shows its own status dash, not a stuck one',
      drawKf.has('stroke-dasharray') && drawKf.has('stroke-dashoffset')
      && drawnStill.get('animation') === 'none'
      && drawnStill.get('stroke-dasharray') === '6px 7px',
      `keyframe animates ${[...drawKf].join('+')}; still resolves to `
      + `${JSON.stringify(drawnStill.get('stroke-dasharray') ?? null)}`);
  }

  /* -- 5. a live card is legibly alive ---------------------------------- */

  const cardRing = (state, media) => computed(rules, {
    tag: 'div',
    classes: new Set(['cv-node']),
    attrs: { 'data-kind': 'agent', 'data-state': state },
    pseudo: '::after',
  }, [chainFor(canvas)[0]], media);

  check('a running card carries a pulse', moving(cardRing('live')),
    `resolved animation: ${JSON.stringify(cardRing('live').get('animation') ?? null)}`);
  check('a finished card does not', !moving(cardRing('done')));
  const pulseKf = animates(atRule(cssText, '@keyframes cv-pulse'));
  check('the pulse animates opacity and nothing that has to be repainted',
    pulseKf.size === 1 && pulseKf.has('opacity'),
    `it animates ${[...pulseKf].join(', ')} — box-shadow or filter here rasterises every live card, every frame`);
  check('the ring the pulse fades is drawn whether or not it fades',
    Boolean(cardRing('live').get('box-shadow')),
    'a ring that lived only inside the keyframes would mean motion off is status gone');
  check('a card carries its state where CSS can reach it',
    canvas.els.get('live').dataset.state === 'live'
    && canvas.els.get('bad').dataset.state === 'failed');

  /* -- 6. motion off, status still readable ----------------------------- */

  const still = (id) => styleOf(edge('session', id), REDUCE);

  check('reduced motion stops the flowing edge', !moving(still('live')),
    `resolved animation: ${JSON.stringify(still('live').get('animation') ?? null)}`
    + ' — a media query adds no specificity, so this rule has to out-rank the one it cancels');
  check('reduced motion stops the arriving edge',
    asDrawing('live', REDUCE).get('animation') === 'none');
  check('reduced motion stops the card pulse', !moving(cardRing('live', REDUCE)));
  check('a card born under reduced motion arrives placed rather than invisible',
    computed(rules, {
      tag: 'div', classes: new Set(['cv-node', 'cv-born']), attrs: { 'data-state': 'live' }, pseudo: null,
    }, [], REDUCE).get('opacity') === '1',
    'with the transition gone, opacity:0 is a card that never appears');

  // The point of the whole section. With every animation off, the states the
  // brief names have to remain five different pictures. Ended and stale are
  // deliberately one of those five — both mean "still and quiet" — and that is
  // asserted rather than assumed.
  const IDS = ['live', 'wake', 'fin', 'bad', 'over'];
  const signature = (id) => {
    const m = still(id);
    return JSON.stringify([
      m.get('stroke-width'), m.get('stroke-dasharray'), m.get('opacity'), edge('session', id).style.stroke,
    ]);
  };
  const sigs = new Map(IDS.map((id) => [id, signature(id)]));
  const clashes = [];
  for (let i = 0; i < IDS.length; i += 1) {
    for (let j = i + 1; j < IDS.length; j += 1) {
      if (sigs.get(IDS[i]) === sigs.get(IDS[j])) clashes.push(`${IDS[i]}=${IDS[j]}`);
    }
  }
  check('with motion off every status is still a different picture',
    clashes.length === 0,
    clashes.length
      ? `indistinguishable: ${clashes.join(', ')} — motion was the only channel carrying them`
      : [...sigs].map(([k, v]) => `${k} ${v}`).join(' | '));
  check('ended and stale are one quiet state on purpose',
    edge('session', 'over').dataset.state === 'quiet' && edge('session', 'old').dataset.state === 'quiet');

  check('a failed branch is wrong in colour, not only in a word',
    edge('session', 'bad').style.stroke === 'var(--cv-fail)'
    && Object.values(PAL.map).every((p) => p.hex !== 'var(--cv-fail)'),
    `got ${edge('session', 'bad').style.stroke}`);
  check('killed and stopped read as the failure they are',
    ['failed', 'killed', 'stopped'].every((s) => {
      const c3 = new Canvas(document.createElement('div'), {});
      c3.setPalette(PAL);
      c3.setSession(`s-${s}`);
      c3.render({ nodes: [root(1), kid('x', s)], edges: [{ source: 'session', target: 'x' }] });
      return edgeIn(c3, 'session', 'x').dataset.state === 'failed';
    }),
    'they come off the transcript verbatim and mean the same thing to a reader');

  /* -- 7. both themes --------------------------------------------------- */

  // The three blocks are the ones tokens.css is generated with: dark on a bare
  // :root, light when the system asks and the viewer has not chosen dark, light
  // when the viewer chose it. A token defined in two of them is a stroke that
  // keeps its dark weight on a light ground for one of the two ways to get there.
  const bareRoot = rules.filter((r) => r.sel === ':root' && r.media.length === 0);
  const lightSystem = rules.filter((r) => r.sel === ':root:not([data-theme="dark"])'
    && r.media.length === 1 && r.media[0] === '(prefers-color-scheme: light)');
  const lightChosen = rules.filter((r) => r.sel === ':root[data-theme="light"]' && r.media.length === 0);
  const used = new Set();
  const collect = (v) => { for (const m of String(v).matchAll(/var\((--[\w-]+)\)/g)) used.add(m[1]); };
  for (const id of IDS) { for (const v of still(id).values()) collect(v); collect(edge('session', id).style.stroke); }
  for (const v of cardRing('live').values()) collect(v);
  // --cv-fail is an alias of the status-fail token, which tokens.css themes; the
  // weights are the ones this file has to theme itself.
  const themed = [...used].filter((t) => t.startsWith('--cv-edge-'));
  check('a failed edge takes its colour from the status token',
    bareRoot.some((r) => r.decls.get('--cv-fail') === 'var(--status-fail)') && used.has('--cv-fail'),
    'an alias with a literal behind it would not follow the theme');
  check('the edge states are expressed as tokens rather than literals',
    themed.length >= 4, `tokens in play: ${themed.join(', ') || 'none'}`);
  const orphan = themed.filter((t) => !bareRoot.some((r) => r.decls.has(t))
    || !lightSystem.some((r) => r.decls.has(t))
    || !lightChosen.some((r) => r.decls.has(t)));
  check('every edge token is defined on bare :root and redefined in both light blocks',
    orphan.length === 0,
    orphan.length ? `only partly defined: ${orphan.join(', ')}` : `${themed.length} tokens, three blocks each`);

  /* -- 8. the cost, measured -------------------------------------------- */

  // 250 nodes is a session size this project has reached. Two numbers decide
  // whether motion is affordable there: how much of the edge layer the canvas
  // rebuilds per poll, and how many strokes are moving at once.
  {
    const N = 250;
    const TYPES = ['Explore', 'Plan', 'reviewer', 'tester'];
    const big = { nodes: [root(1)], edges: [] };
    for (let i = 0; i < N; i += 1) {
      big.nodes.push(kid(`n${i}`, 'running', TYPES[i % TYPES.length]));
      big.edges.push({ source: 'session', target: `n${i}` });
    }

    let made = 0;
    const realNS = document.createElementNS;
    document.createElementNS = (...a) => { made += 1; return realNS(...a); };

    const cBig = new Canvas(document.createElement('div'), {});
    cBig.setPalette(PAL);
    cBig.setSession('big');
    cBig.render(big);
    const firstPass = made;

    made = 0;
    const POLLS = 20;
    const t0 = process.hrtime.bigint();
    for (let i = 0; i < POLLS; i += 1) cBig.render(big);
    const perPoll = Number(process.hrtime.bigint() - t0) / 1e6 / POLLS;
    const churn = made;
    document.createElementNS = realNS;

    // This is the fix that made CSS-only motion possible at all. An element
    // that leaves the document restarts its animations, so rebuilding the edge
    // layer each poll reset every travelling dash twice a second — and every
    // frame of a drag, which calls the same code.
    check(`re-polling ${N} nodes rebuilds no edge elements`,
      churn === 0 && firstPass === N,
      `first pass built ${firstPass} paths (expected ${N}); ${POLLS} further polls built ${churn} more`);
    check(`the edge layer stays at ${N} elements across polls`,
      cBig.edgeEls.size === N, `${cBig.edgeEls.size} paths held`);

    // A dash travelling along a stroke is paint work, not compositor work, so
    // the honest limit is on how many strokes travel at once rather than on
    // how many exist.
    check('past the motion budget the canvas stops moving and keeps saying the same things',
      cBig.root.dataset.motion === 'still',
      `${N} running agents left data-motion at ${JSON.stringify(cBig.root.dataset.motion)}`);
    const bigEdge = edgeIn(cBig, 'session', 'n0');
    const stillBig = pathStyle(cBig, bigEdge);
    check('the budget actually reaches the stroke, not just the root element',
      stillBig.get('animation') === 'none',
      `resolved to ${JSON.stringify(stillBig.get('animation') ?? null)}`);
    check('a live edge under the budget still moves',
      moving(styleOf(edge('session', 'live'))) && canvas.root.dataset.motion === 'flow',
      `the small fixture is at ${JSON.stringify(canvas.root.dataset.motion)}`);
    check('the budget is a ceiling on motion, not on the graph',
      stillBig.get('stroke-dasharray') === '6px 7px'
      && stillBig.get('opacity') === 'var(--cv-edge-live)',
      'dropping the live styling along with the animation would hide which branches are alive');

    // The budget is only a real gate if it has an edge. Found by walking to it
    // rather than by naming the constant a second time — a threshold written
    // down twice is a threshold that drifts.
    const motionAt = (n) => {
      const c = new Canvas(document.createElement('div'), {});
      c.setPalette(PAL);
      c.setSession(`edge-${n}`);
      c.render({
        nodes: [root(1), ...Array.from({ length: n }, (_, i) => kid(`k${i}`, 'running'))],
        edges: Array.from({ length: n }, (_, i) => ({ source: 'session', target: `k${i}` })),
      });
      return c.root.dataset.motion;
    };
    let last = 0;
    for (let n = 1; n <= 200 && motionAt(n) === 'flow'; n += 1) last = n;
    check('the budget has a sharp edge, and it is not at one or two agents',
      last >= 20 && last <= 160 && motionAt(last) === 'flow' && motionAt(last + 1) === 'still',
      `motion holds up to ${last} flowing edges and stops at ${last + 1}`);

    process.stdout.write(`     ${N} nodes: ${cBig.edgeEls.size} paths held, ${churn} rebuilt`
      + ` over ${POLLS} polls, ${perPoll.toFixed(1)} ms of JS per poll\n`);
  }

  /* -- 9. the method six call sites depend on --------------------------- */

  // Deleted by accident in an earlier layout change while app.js kept calling
  // it in six places and #redraw in a seventh, so every fold and every panel
  // resize threw. Call it rather than grep for it.
  {
    let err = null;
    try { canvas.fitIfUntouched(); } catch (e) { err = e; }
    check('the canvas still answers the fit call the rest of the page makes',
      err === null && typeof canvas.fitIfUntouched === 'function',
      err ? `${err.name}: ${err.message}` : null);
  }

  dom();
}


/* ------------------------------------------------- §24 navigator tabs ---
   The three folding blocks became three tabs. What this section guards is the
   same class of defect it always did: a rule that hides something losing to a
   rule that displays it, and a choice that is lost because storage refused.
   It sits after §26 because it resolves the cascade with §26's resolver. */

// The kit has been bitten twice by a hide rule losing to a display rule:
// `[hidden]` lost to `display: grid`, and a `display: none` grid child stopped
// occupying its cell. So assert the cascade, not the intent.
{
  const html = read(path.join(STUDIO, 'web', 'index.html')) ?? '';
  const css = read(path.join(STUDIO, 'web', 'style.css')) ?? '';
  const app = read(path.join(STUDIO, 'web', 'app.js')) ?? '';

  for (const [tab, panel] of [['projects', 'sessions'], ['live', 'fleet'], ['machines', 'reach']]) {
    check(`the ${tab} tab has a control and the panel it shows`,
      new RegExp(`role="tab"[^>]*data-tab="${tab}"[^>]*aria-controls="${panel}"`).test(html)
      && new RegExp(`<div id="${panel}" class="nav-list" role="tabpanel"`).test(html)
      && new RegExp(`data-rail-tab="${tab}"`).test(html),
      'a tab with no panel wired to it switches nothing; the collapsed rail carries the same three');
  }
  check('the search box sits above the tabs and searches whichever one is showing',
    (html.match(/id="filter"/g) ?? []).length === 1
    && html.indexOf('id="filter"') < html.indexOf('role="tablist"')
    && /el\.filter\.addEventListener\('input', \(\) => \{[^}]*paintProjects\(\);[^}]*paintLive\(\);/.test(app),
    'a search that only reaches the first tab looks like a broken search on the second');

  // Every element the page ships hidden has to resolve to display:none against
  // the class that gives it a display.
  const tabRules = cssRules(css);
  // `hidden` the attribute, not the tail of `aria-hidden`.
  const hiddenOnes = [...html.matchAll(/<(\w+)\b([^>]*\s)hidden(?=[\s>])([^>]*)>/g)].map(([m, tag, pre, post]) => [m, tag, pre + post]).map(([, tag, attrs]) => ({
    tag,
    id: /\bid="([^"]+)"/.exec(attrs)?.[1] ?? tag,
    classes: (/\bclass="([^"]+)"/.exec(attrs)?.[1] ?? '').split(/\s+/).filter(Boolean),
  }));
  const stillShown = hiddenOnes.filter((h) => {
    const shown = computed(tabRules, { tag: h.tag, classes: new Set(h.classes), attrs: {}, pseudo: null }, []).get('display');
    const hidden = computed(tabRules, { tag: h.tag, classes: new Set(h.classes), attrs: { hidden: '' }, pseudo: null }, []).get('display');
    return shown !== undefined && hidden !== 'none';
  });
  const mustBeAmong = ['side-rail', 'fleet', 'reach', 'other-machines', 'inspector', 'chat', 'toast', 'menu', 'live-count'];
  const notSeen = mustBeAmong.filter((id) => !hiddenOnes.some((h) => h.id === id));
  check('a hidden panel stays hidden against the rule that lays it out',
    notSeen.length === 0 && !hiddenOnes.some((h) => h.tag === 'svg') && stillShown.length === 0,
    notSeen.length ? `the scan did not see: ${notSeen.join(', ')}`
      : stillShown.length ? `still displayed: ${stillShown.map((h) => h.id).join(', ')}`
      : `${hiddenOnes.length} elements ship hidden: ${hiddenOnes.map((h) => h.id).join(', ')}`);
  check('twin: a class that sets display with no [hidden] rule is caught', (() => {
    const rules = cssRules('.nav-list { display: flex; }');
    return computed(rules, { tag: 'div', classes: new Set(['nav-list']), attrs: { hidden: '' }, pseudo: null }, []).get('display') === 'flex';
  })(), 'this is the defect: the attribute alone does not win');

  check('the tab choice is remembered per browser',
    /store\.set\('crewforth-studio-nav-tab', navTab\)/.test(app)
    && /setTab\(store\.get\('crewforth-studio-nav-tab'\)/.test(app));
  check('a browser that refuses localStorage still switches tabs',
    /set\(k, v\) \{ try \{ localStorage\.setItem\(k, v\); \} catch/.test(app)
    && !/localStorage\.setItem\(/.test(app.replace(/set\(k, v\) \{ try \{ localStorage\.setItem\(k, v\); \} catch/, '')),
    'private mode throws on setItem; every write in app.js goes through the one guarded wrapper');
}

process.stdout.write('\n== §27 the picture at 250 nodes ==\n');

/* The owner's complaint was that a big graph "looks low quality and
   meaningless". Two things answer it and both are measured here rather than
   grepped for: a depth level now wraps into bands, so fit() stops being
   width-bound against a ribbon; and what survives a zoom-out is redrawn at a
   constant SCREEN size instead of shrinking into grey.

   Every assertion below renders a real fixture through the DOM stub and reads
   what came out, or resolves the stylesheet the way a browser would and reads
   the value. Nothing here asks whether a class name appears in a file. */

{
  const dom = installDom();
  const cssText = read(path.join(STUDIO, 'web', 'style.css')) ?? '';
  const canvasSrc = read(path.join(STUDIO, 'web', 'canvas.js')) ?? '';
  const rules = cssRules(cssText);
  const REDUCE = ['(prefers-reduced-motion: reduce)'];
  const { Canvas } = await import(`../../kit/studio/web/canvas.js?lod=${Date.now()}`);

  // Thresholds are read out of the module rather than restated here. A
  // threshold written down twice is a threshold that drifts.
  const constOf = (name) => Number(new RegExp(`^const ${name} = ([\\d.]+);`, 'm').exec(canvasSrc)?.[1]);
  const LOD_NEAR = constOf('LOD_NEAR');
  const LOD_FAR = constOf('LOD_FAR');
  const LOD_HYST = constOf('LOD_HYST');
  const LABEL_BUDGET = constOf('LABEL_BUDGET');

  // If the constants did not parse, every threshold assertion below would be
  // comparing against NaN and quietly passing or quietly failing.
  check('the reading thresholds are read from canvas.js rather than restated here',
    [LOD_NEAR, LOD_FAR, LOD_HYST, LABEL_BUDGET].every((v) => Number.isFinite(v) && v > 0)
    && LOD_NEAR > LOD_FAR,
    `near=${LOD_NEAR} far=${LOD_FAR} hyst=${LOD_HYST} budget=${LABEL_BUDGET}`);

  const TYPES = ['Explore', 'Plan', 'reviewer', 'tester', 'crew-planner',
    'crew-backend-expert', 'docs-agent', 'security'];
  const PAL = {
    map: Object.fromEntries(TYPES.map((t, i) => [t, {
      hex: ['#26c6e6', '#a874f5', '#35c874', '#f2a65a'][i % 4],
      source: i % 2 ? 'kit' : 'builtin',
    }])),
    unknown: '#94a3c8',
  };

  /** A root whose pane is a real size. The stub answers 800x600 for every
   *  element, and the whole point of the band wrap is that it is chosen
   *  against the pane it will be drawn in. */
  const pane = (w, h) => {
    const el = document.createElement('div');
    el.getBoundingClientRect = () => ({ x: 0, y: 0, top: 0, left: 0, right: w, bottom: h, width: w, height: h });
    return el;
  };

  // Three failures and a handful of running agents, the rest finished — the
  // shape of a real session late in a run.
  const statusOf = (i) => (i < 3 ? 'failed' : i < 9 ? 'running' : 'done');
  const graph = (n) => {
    const nodes = [{ id: 'session', kind: 'session', status: 'session', turns: 4, cwd: '/x/y' }];
    const edges = [];
    for (let i = 0; i < n; i += 1) {
      nodes.push({
        id: `n${i}`,
        kind: 'agent',
        agentType: TYPES[i % TYPES.length],
        status: statusOf(i),
        description: 'a sentence of description that fills the lower half of the card',
        lastTool: statusOf(i) === 'running' ? 'Grep' : null,
        spawnDepth: 1,
        parentId: 'session',
        tools: {},
        toolCount: 3,
      });
      edges.push({ source: 'session', target: `n${i}` });
    }
    return { nodes, edges };
  };
  const made = (n, w = 1280, h = 800) => {
    const c = new Canvas(pane(w, h), {});
    c.setPalette(PAL);
    c.setSession(`lod-${n}-${w}x${h}`);
    c.render(graph(n));
    return c;
  };

  const span = (c) => {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const p of c.pos.values()) {
      minX = Math.min(minX, p.x); minY = Math.min(minY, p.y);
      maxX = Math.max(maxX, p.x + 236); maxY = Math.max(maxY, p.y + 104);
    }
    return { w: maxX - minX, h: maxY - minY };
  };

  const small = made(6);
  const dozen = made(12);
  const mid = made(60);
  const big = made(250);

  for (const [label, c] of [['6', small], ['60', mid], ['250', big]]) {
    const s = span(c);
    process.stdout.write(`     ${label.padStart(3)} nodes @1280x800: world ${Math.round(s.w)}x${Math.round(s.h)}`
      + ` (${(s.w / s.h).toFixed(2)}:1), fit ${(c.view.k * 100).toFixed(1)}%,`
      + ` reading ${c.root.dataset.lod}, 11px type draws at ${(11 * c.view.k).toFixed(2)}px\n`);
  }

  /* -- 1. the wrap is real --------------------------------------------- */

  {
    const s = span(big);
    check('a 250-node depth level wraps into bands instead of one row',
      s.w / s.h < 4 && big.view.k >= LOD_FAR,
      `world ${Math.round(s.w)}x${Math.round(s.h)} (${(s.w / s.h).toFixed(2)}:1) fits at`
      + ` ${(big.view.k * 100).toFixed(1)}% — one unbounded row was 8624x1246 (6.92:1) at 7.9%`);
  }

  /* -- 2. the small case did not pay for it ---------------------------- */

  check('a six-agent session still gets full cards, at full size',
    small.view.k >= 1 && small.root.dataset.lod === 'near',
    `fits at ${(small.view.k * 100).toFixed(1)}% reading ${small.root.dataset.lod}`
    + ' — one row put the same six at 66.8%');
  check('twelve agents get full cards too, which is the complaint that started this',
    dozen.view.k >= LOD_NEAR && dozen.root.dataset.lod === 'near',
    `fits at ${(dozen.view.k * 100).toFixed(1)}% reading ${dozen.root.dataset.lod}`
    + ` — needs >= ${LOD_NEAR * 100}% to keep the description`);

  /* -- 3. zoom never moves a node -------------------------------------- */

  {
    const before = JSON.stringify([...dozen.pos].sort());
    let relaid = 0;
    dozen.layout = () => { relaid += 1; };          // shadows the prototype
    const startK = dozen.view.k;
    for (const k of [1.2, 0.9, LOD_NEAR + 0.05, LOD_NEAR - 0.05, 0.4,
      LOD_FAR + 0.05, LOD_FAR - 0.05, 0.08, 0.5, 1.0]) {
      dozen.view.k = k;
      dozen.applyView();
    }
    const after = JSON.stringify([...dozen.pos].sort());
    delete dozen.layout;
    dozen.view.k = startK;
    dozen.applyView();
    check('crossing every reading boundary moves nothing and re-lays out nothing',
      after === before && relaid === 0,
      `${dozen.pos.size} positions, ${after === before ? 'byte-identical' : 'CHANGED'} across ten`
      + ` zoom steps spanning both boundaries; layout() ran ${relaid} times`);
  }

  /* -- 4. the band is hysteretic --------------------------------------- */

  {
    const sweep = (from, to, step) => {
      const seen = [];
      for (let i = 0; i <= Math.round(Math.abs(to - from) / Math.abs(step)); i += 1) {
        dozen.view.k = Number((from + i * step).toFixed(4));
        dozen.applyView();
        const b = dozen.root.dataset.lod;
        if (seen[seen.length - 1] !== b) seen.push(b);
      }
      return seen;
    };
    // A tremor is the case the hysteresis exists for: a finger resting on a
    // trackpad at a boundary must not reband 250 cards twice a second.
    const tremor = (at) => {
      dozen.view.k = at - 0.01;
      dozen.applyView();
      const settled = dozen.root.dataset.lod;
      let flips = 0;
      for (let i = 0; i < 40; i += 1) {
        dozen.view.k = at + (i % 2 ? 0.001 : -0.001);
        dozen.applyView();
        if (dozen.root.dataset.lod !== settled) flips += 1;
      }
      return flips;
    };

    for (const [name, at] of [['detail', LOD_NEAR], ['marks', LOD_FAR]]) {
      const up = sweep(at - 0.06, at + 0.06, 0.001);
      const down = sweep(at + 0.06, at - 0.06, -0.001);
      const flips = tremor(at);
      check(`the ${name} boundary changes the reading once per direction and never on a tremor`,
        up.length === 2 && down.length === 2 && flips === 0,
        `up ${up.join('->')}, down ${down.join('->')}, ${flips} flips over 40 jitters of`
        + ` +-0.001 at k=${at} (hysteresis ${LOD_HYST})`);
    }
    dozen.view.k = 1;
    dozen.applyView();
  }

  /* -- 5. the crowd forces the far reading, not only the zoom ---------- */

  {
    big.view.k = 0.5;
    big.applyView();
    dozen.view.k = 0.5;
    dozen.applyView();
    check('too many cards is the same complaint as cards too small, and gets the same remedy',
      big.root.dataset.lod === 'far' && dozen.root.dataset.lod === 'mid',
      `at k=0.5, ${big.drawn} nodes read as ${big.root.dataset.lod} and ${dozen.drawn} read as`
      + ` ${dozen.root.dataset.lod} (budget ${LABEL_BUDGET}) — equal here means the rule is zoom-only`);
    big.view.k = 0.27;
    big.applyView();
  }

  /* -- 6. a running node is never anonymous ---------------------------- */

  const classesOf = (el) => new Set([
    ...String(el.getAttribute('class') ?? '').split(/\s+/).filter(Boolean),
    ...el.classList._s,
  ]);
  const dataAttrs = (el) => Object.fromEntries(
    Object.entries(el.dataset).map(([k, v]) => [`data-${k.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`)}`, v]),
  );
  const rootOf = (c) => ({ tag: 'div', classes: new Set(['cv-root']), attrs: dataAttrs(c.root), pseudo: null });
  const cardOf = (c, id) => ({
    tag: 'div', classes: classesOf(c.els.get(id)), attrs: dataAttrs(c.els.get(id)), pseudo: null,
  });
  const partStyle = (c, id, cls, pseudo, media) => computed(
    rules, { tag: 'span', classes: new Set([cls]), attrs: {}, pseudo: pseudo ?? null },
    [rootOf(c), cardOf(c, id)], media,
  );

  {
    check('the canvas really is in the far reading for the assertions below',
      big.root.dataset.lod === 'far',
      `250 nodes at ${(big.view.k * 100).toFixed(0)}% read as ${big.root.dataset.lod}`);

    const promoted = [...big.nodes.values()]
      .filter((n) => ['failed', 'running'].includes(n.status) || n.kind === 'session');
    const mute = promoted.filter((n) => {
      const c = partStyle(big, n.id, 'cv-type', '::before').get('content');
      return !c || c === 'none';
    });
    check('every running, failed and session node keeps a label at the far reading',
      promoted.length >= 10 && mute.length === 0,
      mute.length
        ? `${mute.length} of ${promoted.length} resolved no content: ${mute.slice(0, 4).map((n) => `${n.id}/${n.status}`).join(', ')}`
        : `${promoted.length} promoted nodes, all labelled`);

    // The control. If the four promotion selectors had been written with
    // :not(), the matcher would treat them as non-matches and the assertion
    // above would go green on a rule the browser is running and this test
    // never saw — so a node that must NOT be labelled is checked too.
    const quiet = partStyle(big, 'n100', 'cv-type', '::before').get('content');
    check('an ordinary finished node gets no label out there, which is what makes the labels mean something',
      big.nodes.get('n100').status === 'done' && (!quiet || quiet === 'none'),
      `a done node resolved content ${JSON.stringify(quiet ?? null)} — every card labelled is the grey wall again`);

    const midType = computed(rules,
      { tag: 'span', classes: new Set(['cv-type']), attrs: {}, pseudo: '::before' },
      [{ tag: 'div', classes: new Set(['cv-root']), attrs: { 'data-lod': 'mid' }, pseudo: null },
        { tag: 'div', classes: new Set(['cv-node']), attrs: { 'data-kind': 'agent', 'data-state': 'done' }, pseudo: null }]);
    check('the middle reading draws a short type at a constant screen size',
      midType.get('content') === 'attr(data-short)'
      && /calc\(\s*11px\s*\/\s*var\(--k\)\s*\)/.test(String(midType.get('font-size') ?? '')),
      `content ${JSON.stringify(midType.get('content') ?? null)},`
      + ` font-size ${JSON.stringify(midType.get('font-size') ?? null)}`);

    // The attribute the pseudo-element reads has to actually carry something,
    // and for a running agent it has to carry what the agent is doing.
    // Found by type rather than by index, so the fixture's type cycle can be
    // reordered without turning this into a puzzle.
    const byType = (t) => big.els.get([...big.nodes.values()].find((n) => n.agentType === t).id);
    const live = byType('crew-backend-expert');
    const done = big.els.get('n100');
    check('the label a running node keeps says what it is doing, not just what it is',
      big.nodes.get(live.dataset.id).status === 'running'
      && live.parts.type.dataset.far === 'backend ▸ Grep'
      && done.parts.type.dataset.far === done.parts.type.dataset.short,
      `running: ${JSON.stringify(live.parts.type.dataset.far)},`
      + ` done: ${JSON.stringify(done.parts.type.dataset.far)}`);
    check('short names are derived the way the README diagram derives them',
      live.parts.type.dataset.short === 'backend'
      && byType('docs-agent').parts.type.dataset.short === 'docs'
      && byType('Explore').parts.type.dataset.short === 'Explore',
      `crew-backend-expert -> ${JSON.stringify(live.parts.type.dataset.short)},`
      + ` docs-agent -> ${JSON.stringify(byType('docs-agent').parts.type.dataset.short)},`
      + ` Explore -> ${JSON.stringify(byType('Explore').parts.type.dataset.short)}`);

    // font-size:0 removes the accessible name and a pseudo-element's content
    // is not reliably exposed, so the card has to carry it as an attribute at
    // every reading or this ships as an accessibility regression.
    const named = [...big.els.entries()].filter(([, el]) => {
      const a = String(el.getAttribute('aria-label') ?? '');
      return a.includes(',') && a.length > 6;
    });
    check('every card names itself for a screen reader at every reading',
      named.length === big.els.size,
      `${named.length} of ${big.els.size} cards carried an aria-label;`
      + ` n3 reads ${JSON.stringify(big.els.get('n3').getAttribute('aria-label'))}`);
  }

  /* -- 7. what the middle reading gives up ----------------------------- */

  {
    const at = (lod, cls) => computed(rules,
      { tag: 'div', classes: new Set([cls]), attrs: {}, pseudo: null },
      [{ tag: 'div', classes: new Set(['cv-root']), attrs: { 'data-lod': lod }, pseudo: null },
        { tag: 'div', classes: new Set(['cv-node']), attrs: { 'data-kind': 'agent', 'data-state': 'done' }, pseudo: null }]);
    check('the middle reading drops the grey half of the card and keeps the chip',
      at('mid', 'cv-desc').get('opacity') === '0' && at('mid', 'cv-foot').get('opacity') === '0'
      && at('mid', 'cv-chip').get('opacity') !== '0'
      && at('near', 'cv-desc').get('opacity') !== '0',
      `mid desc ${at('mid', 'cv-desc').get('opacity')}, mid foot ${at('mid', 'cv-foot').get('opacity')},`
      + ` mid chip ${at('mid', 'cv-chip').get('opacity')}, near desc ${at('near', 'cv-desc').get('opacity')}`);
    check('the far reading stops drawing the rectangle that is the wall',
      at('far', 'cv-node').get('background') === 'transparent'
      && at('far', 'cv-node').get('box-shadow') === 'none'
      && at('near', 'cv-node').get('background') !== 'transparent',
      `far background ${at('far', 'cv-node').get('background')},`
      + ` near background ${at('near', 'cv-node').get('background')}`);
  }

  /* -- 8. stillness reaches the substitution --------------------------- */

  {
    const under = (motion, media) => computed(rules,
      { tag: 'svg', classes: new Set(['cv-mark']), attrs: {}, pseudo: null },
      [{ tag: 'div', classes: new Set(['cv-root']), attrs: { 'data-lod': 'far', 'data-motion': motion }, pseudo: null },
        { tag: 'div', classes: new Set(['cv-node']), attrs: { 'data-state': 'live' }, pseudo: null }], media);
    const label = (motion, media) => computed(rules,
      { tag: 'span', classes: new Set(['cv-type']), attrs: {}, pseudo: '::before' },
      [{ tag: 'div', classes: new Set(['cv-root']), attrs: { 'data-lod': 'mid', 'data-motion': motion }, pseudo: null },
        { tag: 'div', classes: new Set(['cv-node']), attrs: { 'data-state': 'live' }, pseudo: null }], media);

    // The control: there has to be a transition here for switching it off to
    // mean anything.
    check('the mark travels to its new place rather than jumping there',
      /transform/.test(String(under('flow').get('transition') ?? '')),
      `resolved transition: ${JSON.stringify(under('flow').get('transition') ?? null)}`);
    check('a reader who asked for stillness gets it on the new motion too',
      under('flow', REDUCE).get('transition') === 'none'
      && label('flow', REDUCE).get('transition') === 'none',
      `mark ${JSON.stringify(under('flow', REDUCE).get('transition') ?? null)},`
      + ` label ${JSON.stringify(label('flow', REDUCE).get('transition') ?? null)}`);
    check('past the motion budget the substitution stands still as well',
      under('still').get('transition') === 'none' && label('still').get('transition') === 'none',
      `mark ${JSON.stringify(under('still').get('transition') ?? null)},`
      + ` label ${JSON.stringify(label('still').get('transition') ?? null)}`);
  }

  /* -- 9. the disc survives the tightest pitch ------------------------- */

  {
    const farRoot = computed(rules,
      { tag: 'div', classes: new Set(['cv-root']), attrs: { 'data-lod': 'far' }, pseudo: null }, []);
    const decl = String(farRoot.get('--dot-screen') ?? '');
    const m = /clamp\(\s*([\d.]+)px\s*,\s*calc\(\s*([\d.]+)\s*\*\s*var\(--k\)[^)]*\)\s*,\s*([\d.]+)px\s*\)/.exec(decl);
    if (!m) {
      skip('the disc never collides with its neighbour', 'fixture',
        `--dot-screen did not parse as a clamp: ${JSON.stringify(decl || null)}`);
    } else {
      const k = big.view.k;
      const dot = Math.min(Math.max(Number(m[1]), Number(m[2]) * k), Number(m[3]));
      // Measured against the pitch the layout actually produced, so a later
      // change to SIBLING_GAP or the per-group column count turns this red
      // instead of quietly overlapping 250 dots.
      const centres = [...big.pos.values()].map((p) => [(p.x + 118) * k, (p.y + 52) * k]);
      let pitch = Infinity;
      for (let i = 0; i < centres.length; i += 1) {
        for (let j = i + 1; j < centres.length; j += 1) {
          pitch = Math.min(pitch, Math.hypot(centres[i][0] - centres[j][0], centres[i][1] - centres[j][1]));
        }
      }
      // Both bounds are expressed against the measured pitch rather than
      // against the constants in the clamp: `dot >= floor` would be true of
      // any clamp, since the clamp puts it there. A disc has to fill enough of
      // its cell to read as a mark and not enough to touch the next one.
      check('the disc fills its cell at the tightest pitch without touching its neighbour',
        dot <= pitch && dot >= pitch * 0.2,
        `disc is ${dot.toFixed(1)} screen px at k=${k.toFixed(3)}, closest two nodes are`
        + ` ${pitch.toFixed(1)} px apart (floor ${m[1]}px, cap ${m[3]}px)`);
    }
  }

  /* -- 10. the failed branches are reachable --------------------------- */

  {
    const clean = made(12);
    // n0..n2 are the failures, so a twelve-node fixture has them too; a graph
    // with none is built here to prove the button hides itself.
    const none = new Canvas(pane(1280, 800), {});
    none.setPalette(PAL);
    none.setSession('lod-nofail');
    none.render({
      nodes: [{ id: 'session', kind: 'session', status: 'session', turns: 1, cwd: '/x' },
        { id: 'ok', kind: 'agent', agentType: 'Explore', status: 'done', spawnDepth: 1, parentId: 'session' }],
      edges: [{ source: 'session', target: 'ok' }],
    });
    check('the alarm is absent when nothing went wrong and counts what did',
      none.alarmBtn.hidden === true && clean.alarmBtn.hidden === false
      && clean.alarmBtn.textContent === '⚠ 3',
      `no-failure canvas: hidden=${none.alarmBtn.hidden};`
      + ` three-failure canvas: hidden=${clean.alarmBtn.hidden} label ${JSON.stringify(clean.alarmBtn.textContent)}`);

    const k0 = big.view.k;
    const visited = [];
    for (let i = 0; i < 4; i += 1) { big.gotoFailed(); visited.push(big.selected); }
    const r = big.root.getBoundingClientRect();
    const p = big.pos.get(big.selected);
    const cx = big.view.x + (p.x + 118) * big.view.k;
    const cy = big.view.y + (p.y + 52) * big.view.k;
    check('the alarm walks the failures in order, wraps, and does not zoom to do it',
      visited.join(',') === 'n0,n1,n2,n0'
      && visited.every((id) => big.nodes.get(id).status === 'failed')
      && big.view.k === k0
      && Math.abs(cx - r.width / 2) < 0.5 && Math.abs(cy - r.height / 2) < 0.5,
      `visited ${visited.join(' -> ')}; k ${k0.toFixed(3)} -> ${big.view.k.toFixed(3)};`
      + ` last node centred at ${cx.toFixed(1)},${cy.toFixed(1)} in a ${r.width}x${r.height} pane`);
  }

  /* -- 11. the HUD says which reading you are in ----------------------- */

  {
    const label = (c) => String(c.zoomLabel.textContent ?? '');
    dozen.view.k = 1;
    dozen.applyView();
    const near = label(dozen);
    dozen.view.k = 0.5;
    dozen.applyView();
    const midL = label(dozen);
    dozen.view.k = 0.1;
    dozen.applyView();
    const farL = label(dozen);
    check('the HUD names the reading beside the percentage, so detail reads as traded not lost',
      /^100% . detail$/.test(near) && /^50% . titles$/.test(midL) && /^10% . marks$/.test(farL),
      `${JSON.stringify(near)} / ${JSON.stringify(midL)} / ${JSON.stringify(farL)}`);
    check('and says when it was the crowd rather than the zoom that traded them',
      new RegExp(`^\\d+% . marks \\(${big.drawn}\\)$`).test(label(big))
      && !/\(/.test(farL),
      `250-node canvas reads ${JSON.stringify(label(big))}, zoomed-out small one reads ${JSON.stringify(farL)}`);
  }

  dom();
}


/* --------------------------------------------------------------- verdict */


process.stdout.write('\n== §28 the instance record — finding a panel that is already running ==\n');

/* The panel used to print its tokenised URL once, to one session's stdout, and
   keep the token nowhere else. A second session could see the port was taken but
   not that the holder was our own panel, and had no way to reach it — measured in
   the field, two sessions and one live panel that nobody could open.

   A state file answers that, and every assertion below is about NOT trusting it.
   Files outlive processes: a killed panel, a recycled port and a hand-edited
   record all produce a file that says a panel is there when none is. So the
   record is believed only when the port answers /api/health with the token it
   names AND reports the pid it names, and a record that fails is deleted rather
   than kept. The must-NOT-find cases are the point of the section; the one
   happy path is easy and would be green on its own with no checking at all. */

{
  const rtDir = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-inst-'));
  const prevRt = process.env.CREW_STUDIO_RUNTIME;
  process.env.CREW_STUDIO_RUNTIME = rtDir;
  const inst = await import('../../kit/studio/server/lib/instance.js');

  check('the record lives under the runtime directory the env var names',
    inst.statePath(7777) === path.join(rtDir, 'instance-7777.json'),
    inst.statePath(7777));

  // A fake panel: /api/health is all findRunning consults, and answering it here
  // keeps the section hermetic — no real server, no fixed port, nothing to leak.
  const http = await import('node:http');
  const fakePanel = (pid) => new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true, pid }));
    });
    srv.listen(0, '127.0.0.1', () => resolve({ srv, port: srv.address().port }));
  });

  const live = await fakePanel(4242);
  await inst.writeState(live.port, { token: 'tok-abc', name: 'testbox', pid: 4242 });

  const found = await inst.findRunning(live.port);
  check('a live panel is found and its URL carries the recorded token',
    found?.url === `http://127.0.0.1:${live.port}/?token=tok-abc`, found?.url);
  check('the record survives being found (finding is not consuming)',
    fs.existsSync(inst.statePath(live.port)));

  // Same port, same file, a DIFFERENT process answering. A health response alone
  // is not identity: ports get recycled, and /api/health reports its own pid so
  // this comparison is possible at all.
  const mismatch = await inst.findRunning(live.port + 0) && null;
  await inst.writeState(live.port, { token: 'tok-abc', name: 'testbox', pid: 999999 });
  check('a record whose pid does not match the answering process is refused',
    (await inst.findRunning(live.port)) === null, String(mismatch));
  check('...and that stale record is removed rather than left to mislead the next start',
    !fs.existsSync(inst.statePath(live.port)));

  live.srv.close();

  // Nothing listening at all: the ordinary aftermath of a crash or a kill -9.
  const deadPort = live.port;
  await inst.writeState(deadPort, { token: 'tok-dead', name: 'ghost', pid: 4242 });
  check('a record with nothing listening behind it is refused',
    (await inst.findRunning(deadPort)) === null);
  check('...and it is removed too, so a crashed panel cleans up the next time anyone looks',
    !fs.existsSync(inst.statePath(deadPort)));

  check('no record at all reads as "not ours", not as an error',
    (await inst.findRunning(deadPort)) === null);

  // The token is a credential, so the mode is part of the contract and not a
  // detail. Windows has no POSIX mode bits — the file's protection there is that
  // it sits under the user's own profile — so the check states that rather than
  // pretending to pass.
  await inst.writeState(deadPort, { token: 'tok-mode', name: 'm', pid: 1 });
  if (process.platform === 'win32') {
    // This said "covered by: the Windows session" before anyone had asked whether it was, and it was not -- that
    // machine had no node and could not start the panel at all. It now names the coverer only for what was
    // actually measured there: icacls on the written record, and two panels handing back the same token. What
    // is STILL uncovered is the third question, whether a gentle stop clears the record: MSYS `kill -TERM`
    // cannot reach a Windows process at all ("No such process", separate pid spaces) and `taskkill` without
    // /F is refused by Windows, so a real console Ctrl-C could not be produced from that harness. A hard
    // `taskkill /F` does leave the record behind, which is expected -- no handler runs -- and the next panel
    // discards the stale pid and starts fresh, which was measured.
    notApplicable('the record holding the token is written 0600', 'POSIX mode bits are advisory on win32; the file inherits the user profile ACL instead — measured: SYSTEM, Administrators and the owner, no Everyone or Users, so weaker than 0600 and written down as such', 'windows-crew for the ACL and the shared-token path; NOBODY YET for whether a gentle stop clears the record');
  } else {
    const mode = fs.statSync(inst.statePath(deadPort)).mode & 0o777;
    check('the record holding the token is written 0600', mode === 0o600, mode.toString(8));
  }
  await inst.clearState(deadPort);
  check('clearState removes the record', !fs.existsSync(inst.statePath(deadPort)));

  fs.rmSync(rtDir, { recursive: true, force: true });
  if (prevRt === undefined) delete process.env.CREW_STUDIO_RUNTIME;
  else process.env.CREW_STUDIO_RUNTIME = prevRt;
}

process.stdout.write('\n');
if (pass + fail === 0) {
  // The branch that audits the harness itself. An empty run is a broken
  // measurement, not a clean bill of health.
  process.stdout.write('FAIL selfcheck ran zero assertions — the measurement is broken, not the code\n');
  process.exit(1);
}
if (fail) {
  process.stdout.write(`${failures.length} failure(s):\n`);
  for (const f of failures) process.stdout.write(`  - ${f}\n`);
}
// ---- the stream signature: what decides whether a status change ever reaches the panel ----
// Both of these were measured over a 45-second SSE capture against the previous version, with a synthetic
// session built on disk: an agent that goes quiet held `running` FOREVER (1 graph frame in 150 s), and three
// writes to a workflow agent's transcript produced NO frame at all. Those captures proved the defects; these
// assertions are what stops them coming back, because a two-minute timing test is one nobody runs twice.
{
  const sigHome = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-studio-sig-'));
  const sess = { file: path.join(sigHome, 's.jsonl'), subagentsDir: path.join(sigHome, 'subagents') };
  fs.writeFileSync(sess.file, '{}\n');
  const wfDir = path.join(sess.subagentsDir, 'workflows', 'wf_1');
  fs.mkdirSync(wfDir, { recursive: true });
  const flat = path.join(sess.subagentsDir, 'agent-aflat.jsonl');
  const nested = path.join(wfDir, 'agent-anested.jsonl');
  fs.writeFileSync(flat, 'x\n');
  fs.writeFileSync(nested, 'x\n');

  // A workflow agent lives one level down. A flat readdir sees only the `workflows` DIRECTORY, whose size does
  // not move when a transcript inside it grows, so its updates were invisible to the stream.
  const beforeGrow = await signature(sess);
  fs.appendFileSync(nested, 'yy\n');
  const afterGrow = await signature(sess);
  check('stream signature notices a NESTED (workflow) agent growing',
    beforeGrow !== afterGrow, `${beforeGrow} vs ${afterGrow}`);
  check('stream signature names the nested file, not just its directory',
    afterGrow.includes('wf_1/agent-anested.jsonl'), afterGrow);

  // A STATUS CHANGES ON THE CLOCK ALONE: `running` becomes `stale` with nothing written. The signature must
  // therefore carry a coarse clock component while something is recent enough to still be called running, and
  // must NOT carry one otherwise — an idle session's signature has to stay as stable as it was before.
  const fresh = await signature(sess);
  check('a recent agent puts a clock bucket in the signature', /\|t:\d+$/.test(fresh), fresh);
  const old = Date.now() / 1000 - 600;
  fs.utimesSync(flat, old, old);
  fs.utimesSync(nested, old, old);
  const quiet = await signature(sess);
  check('an agent quiet for longer than the stale window does NOT', !/\|t:\d+/.test(quiet), quiet);

  // The bucket is derived from the clock rather than from a counter, so it is the same for two calls inside one
  // bucket. Pinned because a per-tick value would rebuild the graph 85 times a bucket for no new information.
  fs.utimesSync(flat, Date.now() / 1000, Date.now() / 1000);
  const a = await signature(sess);
  const b = await signature(sess);
  check('two calls inside one bucket agree', a === b, `${a} vs ${b}`);
  fs.rmSync(sigHome, { recursive: true, force: true });
}

/* --------------------------------------- §29 design tokens and the frame ---
   The redesign's first step. Every claim below is about one of three things:
   the colours come from the design system and from nowhere else, the frame has
   the spec's measures, and the theme the viewer picked is the one drawn.

   Each gate is run three ways where three ways exist. The real tree must pass.
   A twin with the defect planted must fail, and it is planted in memory, never
   in the checkout — a gate that edits the tree it guards is green for whoever
   ran it last. And on a machine without node this whole file does not run:
   verify.sh reports the step as SKIPPED, which CREW_VERIFY_STRICT turns red. */

process.stdout.write('\n== §29 design tokens and the frame ==\n');

{
  const gen = await import(`../gen-studio-tokens.mjs?t=${Date.now()}`);
  const tokenSrc = read(gen.SOURCE);
  const tokensCss = read(path.join(WEB_ROOT, 'tokens.css'));
  const styleCss = read(path.join(WEB_ROOT, 'style.css')) ?? '';
  const indexHtml = read(path.join(WEB_ROOT, 'index.html')) ?? '';
  const appJs = read(path.join(WEB_ROOT, 'app.js')) ?? '';
  const tokens = JSON.parse(tokenSrc ?? '{}');
  const clone = () => JSON.parse(tokenSrc);
  const noComments = (css) => css.replace(/\/\*[\s\S]*?\*\//g, '');

  /* -- 1. freshness ------------------------------------------------------ */

  const rendered = gen.render(tokens);
  check('tokens.css is byte for byte what the generator writes',
    tokensCss !== null && tokensCss === rendered,
    tokensCss === null ? 'kit/studio/web/tokens.css is missing'
      : `${Buffer.byteLength(tokensCss)} bytes on disk, ${Buffer.byteLength(rendered)} generated`
        + (tokensCss === rendered ? '' : ' — run: node packaging/gen-studio-tokens.mjs'));
  {
    // The twin: one colour changed in the source and nothing regenerated.
    const stale = clone();
    stale.color.tokens.find((t) => t.name === 'line').value.dark = '#262c3a';
    check('a token changed in the JSON and not regenerated is caught',
      gen.render(stale) !== tokensCss, 'the comparison would pass on anything if this were equal');
  }
  check('the generated file ends every line with LF and carries no CR',
    !/\r/.test(rendered) && rendered.endsWith('}\n'),
    'a CRLF checkout would otherwise differ from the generator on Windows alone');

  // A token the generator cannot place must stop the build, not be written as it came.
  const refuses = (mutate) => { const t = clone(); mutate(t); try { gen.render(t); return false; } catch { return true; } };
  check('a colour with no light value stops the generator',
    refuses((t) => { delete t.color.tokens.find((x) => x.name === 'ink').value.light; }));
  check('a reference to a colour that does not exist stops the generator',
    refuses((t) => { t.color.tokens.find((x) => x.name === 'chevron-3').value.dark = '{acent}'; }));
  check('a value that is neither #rrggbb nor a reference stops the generator',
    refuses((t) => { t.color.tokens.find((x) => x.name === 'ink').value.dark = 'red; } body { display: none'; }));
  check('the source as it stands does not', !refuses(() => {}));

  /* -- 2. both ways to light carry every colour -------------------------- */

  const themeGaps = (css) => {
    const rules = cssRules(css);
    const pick = (sel, media) => rules.find((r) => r.sel === sel
      && r.media.length === (media ? 1 : 0) && (!media || r.media[0] === media));
    const dark = pick(gen.DARK);
    const sys = pick(gen.LIGHT_SYSTEM, gen.LIGHT_SYSTEM_MEDIA);
    const chosen = pick(gen.LIGHT_CHOSEN);
    if (!dark || !sys || !chosen) return { colours: 0, gaps: ['a theme block is missing'] };
    const colours = tokens.color.tokens.map((t) => `--${t.name}`);
    const gaps = colours.filter((c) => !dark.decls.has(c) || !sys.decls.has(c) || !chosen.decls.has(c));
    const differ = colours.filter((c) => sys.decls.get(c) !== chosen.decls.get(c));
    return { colours: colours.length, gaps: gaps.concat(differ.map((c) => `${c} differs between the two light blocks`)) };
  };
  const real = themeGaps(tokensCss ?? '');
  check('every colour token is defined for dark and for both ways to light',
    real.colours === tokens.color.tokens.length && real.colours > 0 && real.gaps.length === 0,
    real.gaps.length ? real.gaps.join(', ') : `${real.colours} colours, three blocks each`);
  {
    // The twin: one colour dropped from the block the theme button selects.
    const cut = (tokensCss ?? '').replace(/(:root\[data-theme="light"\] \{[\s\S]*?)\n {2}--ink: [^;]+;/, '$1');
    const holed = themeGaps(cut);
    check('a colour missing from one light block is caught',
      cut !== tokensCss && holed.gaps.includes('--ink'), `reported: ${holed.gaps.join(', ') || 'nothing'}`);
  }

  /* -- 3. no colour literal outside tokens.css --------------------------- */

  // What counts as a colour literal: a hex of a colour's length, or a functional
  // notation with a number in it. In a stylesheet only declarations are read —
  // comments are prose, and `#fade` in a selector is an id. NOT seen: a named
  // colour (`white`), which no rule here can tell from a word.
  const HEX_RE = /(?<![&\w])#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})(?![\w-])/g;
  const FN_RE = /\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch)\(\s*[\d.]/g;
  const literals = (name, text) => {
    const out = [];
    if (name.endsWith('.css')) {
      const css = noComments(text);
      for (const m of css.matchAll(HEX_RE)) {
        // A value sits after the `:` of its declaration; a selector sits after `}` or `{`'s end.
        const before = css.slice(0, m.index);
        const at = Math.max(before.lastIndexOf('{'), before.lastIndexOf('}'), before.lastIndexOf(';'));
        if (before.slice(at + 1).includes(':') && before.lastIndexOf('{') > before.lastIndexOf('}')) out.push(m[0]);
      }
      for (const m of css.matchAll(FN_RE)) out.push(m[0]);
    } else {
      for (const m of text.matchAll(HEX_RE)) out.push(m[0]);
      for (const m of text.matchAll(FN_RE)) out.push(m[0]);
    }
    return out;
  };

  // The exceptions, by name. Each is an agent-IDENTITY colour, which the graph
  // step of the redesign removes: colour will say status only, and identity moves
  // to an icon. Until then canvas.js blends these as hex (mixHex), which var()
  // cannot feed. A fifth literal in that file is not covered by this list.
  const ALLOWED = {
    'canvas.js': {
      '#5b8cff': 'KIND_COLOR.session — the session node\'s identity colour',
      '#a874f5': 'KIND_COLOR.workflow — the workflow node\'s identity colour',
      '#D97757': 'MARKS.builtin — the built-in agent mark, replaced by web/icons/builtin.svg',
      '#94a3c8': 'the palette\'s unknown colour before the server sends one',
    },
  };

  const webFiles = walk(WEB_ROOT).map((f) => path.relative(WEB_ROOT, f).split(path.sep).join('/')).sort();
  const scanned = webFiles.filter((f) => f !== 'tokens.css');
  /** entries: [name, text]. An excepted literal is excepted once per file, not per occurrence. */
  const scan = (entries) => {
    const found = [];
    const allowedSeen = [];
    for (const [f, text] of entries) {
      const seen = new Map();
      for (const lit of literals(f, text)) seen.set(lit, (seen.get(lit) ?? 0) + 1);
      for (const [lit, n] of seen) {
        if (ALLOWED[f]?.[lit] && n === 1) allowedSeen.push(`${f} ${lit}`);
        else found.push(`${f} ${lit}${n > 1 ? ` ×${n}` : ''}`);
      }
    }
    return { found, allowedSeen };
  };
  const { found, allowedSeen } = scan(scanned.map((f) => [f, read(path.join(WEB_ROOT, f)) ?? '']));
  // The scanned set against the set that has to be scanned: every file the panel
  // serves except the generated one. "N files, 0 findings" says nothing if the
  // file that carries the colours is not among the N.
  const mustScan = ['app.js', 'canvas.js', 'chat.js', 'index.html', 'liveness.js', 'md.js', 'nav.js', 'style.css', 'theme.js'];
  const unscanned = mustScan.filter((f) => !scanned.includes(f));
  check('the colour scan reads every file the panel serves except tokens.css',
    unscanned.length === 0 && webFiles.includes('tokens.css') && scanned.length === webFiles.length - 1,
    unscanned.length ? `not scanned: ${unscanned.join(', ')}` : `${scanned.length} of ${webFiles.length} files: ${scanned.join(', ')}`);
  check('no colour literal in web/ outside tokens.css',
    found.length === 0,
    found.length ? found.join(' · ') : `0 literals in ${scanned.length} files; ${allowedSeen.length} named exceptions`);
  const allowedCount = Object.values(ALLOWED).reduce((n, o) => n + Object.keys(o).length, 0);
  check('every named exception is still there to be excepted',
    allowedSeen.length === allowedCount,
    `${allowedSeen.length} of ${allowedCount} seen — an exception for a literal that is gone is a hole left open`);

  // Calibration, on inputs whose answer is known before the scan runs.
  const count = (name, text) => literals(name, text).length;
  check('twin: a hex added to style.css is caught',
    count('style.css', `${styleCss}\n.x { color: #ff00aa; }\n`) === count('style.css', styleCss) + 1
    && count('style.css', styleCss) === 0);
  check('twin: a short hex and an rgb() literal are caught too',
    count('style.css', '.x { border: 1px solid #abc; background: rgb(91 140 255 / 0.4); }') === 2);
  check('twin: a hex in a script is caught',
    count('app.js', `${appJs}\nel.style.color = '#1a2b3c';\n`) === count('app.js', appJs) + 1);
  {
    const canvasJs = read(path.join(WEB_ROOT, 'canvas.js')) ?? '';
    const twice = scan([['canvas.js', `${canvasJs}\nconst again = '#5b8cff';\n`]]);
    check('twin: a second copy of an excepted literal is not excepted',
      twice.found.join() === 'canvas.js #5b8cff ×2' && twice.allowedSeen.length === 3,
      `reported: ${twice.found.join(', ') || 'nothing'}`);
    const elsewhere = scan([['app.js', "const c = '#5b8cff';"]]);
    check('twin: an excepted literal in another file is not excepted', elsewhere.found.join() === 'app.js #5b8cff');
  }
  check('calibration: what only looks like a colour is not counted',
    count('style.css', '/* was #0d1017 */ #fade { color: var(--ink); } #add:hover { top: 0; } .a { background: url(#abc123-grad); }') === 0
    && count('index.html', '<a href="#">x</a> &#9662; <use href="#icon-add"/>') === 0
    && count('app.js', 'const rgb = (h) => h; rgb(a); location.hash = "#top";') === 0,
    'a comment, an id selector, a url fragment, an entity, a function called rgb');

  /* -- 4. every var() resolves ------------------------------------------- */

  // A renamed token leaves `var(--old-name)` behind, which is not an error: the
  // declaration is dropped and the element is drawn with whatever it inherits.
  const defined = new Set();
  for (const css of [tokensCss ?? '', styleCss]) {
    for (const m of noComments(css).matchAll(/(?:^|[{;\s])(--[\w-]+)\s*:/g)) defined.add(m[1]);
  }
  // Set from script, per element or on the root, never in a stylesheet. --k is
  // also registered with @property, which is an at-rule and not a declaration.
  const FROM_SCRIPT = ['--side-w', '--chat-w', '--node-color', '--edge-len', '--k'];
  const scriptText = scanned.filter((f) => f.endsWith('.js')).map((f) => read(path.join(WEB_ROOT, f)) ?? '').join('\n');
  const notSet = FROM_SCRIPT.filter((v) => !scriptText.includes(`'${v}'`));
  check('every property expected from script is set by one', notSet.length === 0,
    notSet.length ? `never set: ${notSet.join(', ')}` : `${FROM_SCRIPT.join(', ')}`);
  const unresolved = (css) => [...new Set([...noComments(css).matchAll(/var\(\s*(--[\w-]+)/g)].map((m) => m[1]))]
    .filter((v) => !defined.has(v) && !FROM_SCRIPT.includes(v));
  const dangling = unresolved(styleCss);
  const usedVars = new Set([...noComments(styleCss).matchAll(/var\(\s*(--[\w-]+)/g)].map((m) => m[1]));
  check('every var() in style.css names a property that exists',
    dangling.length === 0 && usedVars.size > 20,
    dangling.length ? `undefined: ${dangling.join(', ')}` : `${usedVars.size} distinct properties`);
  check('twin: a var() left behind by a rename is caught',
    unresolved(`${styleCss}\n.x { color: var(--surface-2); }`).join() === '--surface-2');
  check('index.html loads the tokens before the stylesheet that reads them',
    indexHtml.indexOf('href="/tokens.css"') !== -1
    && indexHtml.indexOf('href="/tokens.css"') < indexHtml.indexOf('href="/style.css"'));

  /* -- 5. the frame's measures ------------------------------------------- */

  const frameOf = (css) => {
    const rules = cssRules(css);
    const root = rules.filter((r) => r.sel === ':root' && r.media.length === 0);
    const prop = (name) => root.map((r) => r.decls.get(name)).find(Boolean) ?? null;
    const decl = (sel, name) => rules.filter((r) => r.sel === sel && r.media.length === 0)
      .map((r) => r.decls.get(name)).find(Boolean) ?? null;
    return {
      bar: [prop('--bar-h'), decl('.bar', 'height')],
      navigator: [prop('--nav-w'), decl('.shell', 'grid-template-columns')],
      toolbar: [prop('--toolbar-h'), decl('.toolbar', 'height')],
      inspector: [prop('--inspector-w'), decl('.inspector', 'width')],
      rail: [prop('--rail-w'), decl('.side-rail', 'width')],
    };
  };
  const WANT = {
    bar: ['56px', 'var(--bar-h)'],
    navigator: ['272px', /^var\(--side-w, var\(--nav-w\)\) /],
    toolbar: ['48px', 'var(--toolbar-h)'],
    inspector: ['344px', 'var(--inspector-w)'],
    rail: ['56px', 'var(--rail-w)'],
  };
  const frameMisses = (css) => {
    const got = frameOf(css);
    return Object.keys(WANT).filter((k) => got[k][0] !== WANT[k][0]
      || !(WANT[k][1] instanceof RegExp ? WANT[k][1].test(got[k][1] ?? '') : got[k][1] === WANT[k][1]));
  };
  const misses = frameMisses(styleCss);
  check('the frame has the spec\'s measures: bar 56, navigator 272, toolbar 48, inspector 344, rail 56',
    misses.length === 0,
    misses.length ? `off: ${misses.map((k) => `${k} ${JSON.stringify(frameOf(styleCss)[k])}`).join(', ')}`
      : 'each is a property on :root AND the declaration that uses it');
  check('twin: a measure that exists only in a comment is not the frame',
    frameMisses(styleCss.replace(/--toolbar-h: 48px;/, '/* --toolbar-h: 48px; */ --toolbar-h: 52px;')).join() === 'toolbar');
  check('twin: a measure nothing uses is not the frame',
    frameMisses(styleCss.replace(/height: var\(--toolbar-h\);/, 'height: 40px;')).join() === 'toolbar');
  check('the navigator opens at the same width without a remembered one',
    /side:\s*\{[^}]*\bdef:\s*272\b/.test(appJs), 'app.js sets --side-w from this before the stylesheet\'s fallback is ever used');
  check('the toolbar and the inspector are in the page', /class="toolbar"/.test(indexHtml)
    && /<main class="stage">\s*<div class="toolbar"[\s\S]*?<div id="canvas"/.test(indexHtml)
    && /<\/main>\s*<aside id="inspector"/.test(indexHtml),
  'toolbar above the canvas inside the stage; inspector a column of the shell, not a child of the stage');

  /* -- 6. four widths ----------------------------------------------------- */

  const widthQueries = (css) => [...new Set([...noComments(css).matchAll(/@media\s*([^{]+)\{/g)]
    .map((m) => m[1].trim()).filter((q) => /width/.test(q)))].sort();
  const BANDS = ['(max-width: 1023px)', '(max-width: 1279px)', '(max-width: 639px)', '(min-width: 1280px)'];
  check('the stylesheet breaks at the spec\'s widths and at no other',
    widthQueries(styleCss).join() === BANDS.join(), `queries: ${widthQueries(styleCss).join(' ')}`);
  check('twin: a query at any other width is caught',
    widthQueries(`${styleCss}\n@media (max-width: 900px) { .side { display: none; } }`).join() !== BANDS.join());

  // What each band does, resolved through the cascade rather than read off the text.
  const rules = cssRules(styleCss);
  const node = (classes, attrs = {}) => ({ tag: 'div', classes: new Set(classes), attrs, pseudo: null });
  const WIDE = ['(min-width: 1280px)'];
  const MID = ['(max-width: 1279px)'];
  const NARROW = ['(max-width: 1279px)', '(max-width: 1023px)'];
  const PHONE = ['(max-width: 1279px)', '(max-width: 1023px)', '(max-width: 639px)'];
  const inspectorIn = (shell, media) => computed(rules, node(['inspector']), [node(shell)], media);
  check('at 1280 and up the inspector is docked in its own column',
    inspectorIn(['shell', 'no-chat'], WIDE).get('position') === 'static'
    && inspectorIn(['shell', 'no-chat'], WIDE).get('grid-column') === '4');
  check('with a conversation open it floats instead, at any width',
    inspectorIn(['shell'], WIDE).get('position') === 'absolute'
    && inspectorIn(['shell'], WIDE).get('grid-column') === undefined,
    'navigator, inspector and conversation side by side leave no graph');
  check('between 1024 and 1279 the inspector floats and the canvas keeps its width',
    inspectorIn(['shell', 'no-chat'], MID).get('position') === 'absolute'
    && inspectorIn(['shell', 'no-chat'], MID).get('top') === 'var(--toolbar-h)');
  const shellIn = (classes, media) => computed(rules, node(classes), [], media).get('grid-template-columns') ?? '';
  check('at 1024 and up an open navigator is a column of its own width',
    shellIn(['shell', 'no-chat'], MID).startsWith('var(--side-w, var(--nav-w)) 5px '));
  check('below 1024 the navigator\'s column is the rail whether it is open or not',
    shellIn(['shell', 'no-chat'], NARROW).startsWith('var(--rail-w) 0 ')
    && shellIn(['shell', 'no-side', 'no-chat'], NARROW).startsWith('var(--rail-w) 0 ')
    && computed(rules, node(['side']), [node(['shell'])], NARROW).get('position') === 'absolute',
    'opened there, it floats over the canvas');
  check('below 640 the stage is the only column',
    ['shell', 'no-chat', 'no-side'].every((c) => shellIn(['shell', c], PHONE).startsWith('0 0 minmax(0, 1fr) '))
    && computed(rules, node(['side-rail']), [node(['shell'])], PHONE).get('display') === 'none');
  check('the narrow band collapses the navigator without overwriting the viewer\'s choice',
    /matchMedia\('\(max-width: 1023px\)'\)/.test(appJs)
    && /persist = !railBand\.matches/.test(appJs)
    && /if \(persist\) store\.set\('crewforth-studio-side-hidden'/.test(appJs));

  /* -- 7. the theme button ------------------------------------------------ */

  const { initTheme, effectiveTheme, THEME_KEY } = await import(`../../kit/studio/web/theme.js?t=${Date.now()}`);
  const rig = (saved, systemLight, broken = false) => {
    const m = new Map(saved ? [[THEME_KEY, saved]] : []);
    const ls = broken
      ? { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); } }
      : { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)) };
    const root = { dataset: {} };
    const button = { attrs: {}, setAttribute(k, v) { this.attrs[k] = v; }, addEventListener(_e, fn) { this.click = fn; } };
    initTheme(root, button, ls, () => systemLight);
    return { root, button, m };
  };
  check('with nothing chosen the theme is the system\'s, and dark unless it asks for light',
    effectiveTheme(undefined, false) === 'dark' && effectiveTheme(undefined, true) === 'light'
    && effectiveTheme('dark', true) === 'dark' && effectiveTheme('light', false) === 'light'
    && effectiveTheme('sepia', false) === 'dark');
  {
    const t = rig('light', false);
    check('a remembered theme is applied before anything is drawn', t.root.dataset.theme === 'light'
      && t.button.attrs['aria-label'] === 'Switch to dark theme');
    t.button.click();
    check('the button switches the theme and remembers it',
      t.root.dataset.theme === 'dark' && t.m.get(THEME_KEY) === 'dark'
      && t.button.attrs['aria-label'] === 'Switch to light theme');
  }
  {
    // The case the old button got wrong: no choice yet, and the system is light.
    const t = rig(null, true);
    const before = t.root.dataset.theme;
    t.button.click();
    check('on a light system the first click goes to dark, not to the theme already showing',
      before === undefined && t.root.dataset.theme === 'dark',
      `first click set ${t.root.dataset.theme}`);
  }
  {
    const t = rig(null, false, true);
    t.button.click();
    check('a browser that refuses storage still switches the theme', t.root.dataset.theme === 'light');
  }
  check('a remembered value that is not a theme is ignored', rig('sepia', false).root.dataset.theme === undefined);

  /* -- 8. controls that are only an icon say what they are ---------------- */

  // The static page only. A control app.js builds at run time is not in this
  // file and is not seen here.
  const unlabelled = (html) => [...html.matchAll(/<button\b([^>]*)>([\s\S]*?)<\/button>/g)]
    .filter(([, attrs, body]) => !/[A-Za-z]{2}/.test(body.replace(/<[^>]+>/g, '').replace(/&\w+;/g, ''))
      && !/\baria-label="[^"]+"/.test(attrs))
    .map(([, attrs]) => (/\bid="([^"]+)"/.exec(attrs)?.[1] ?? attrs.trim()));
  const buttons = [...indexHtml.matchAll(/<button\b/g)].length;
  check('every icon-only button in index.html has an aria-label',
    buttons > 0 && unlabelled(indexHtml).length === 0,
    unlabelled(indexHtml).length ? `no label: ${unlabelled(indexHtml).join(', ')}` : `${buttons} buttons read`);
  check('twin: an icon-only button with a title and no aria-label is caught',
    unlabelled('<button id="x" title="Widen">⇥</button><button id="y">+ session</button>').join() === 'x');
  check('the focus ring is 2px of the accent, 2px off the control',
    cssRules(styleCss).some((r) => r.sel === ':focus-visible' && r.media.length === 0
      && r.decls.get('outline') === '2px solid var(--accent)' && r.decls.get('outline-offset') === '2px')
    && !/outline:\s*(none|0)\b/.test(noComments(styleCss)),
    'and nothing in the stylesheet switches an outline off');
}

/* ------------------------------------- §30 the top bar and the navigator ---
   What the bar and the navigator SAY is in web/nav.js and web/liveness.js as
   functions of the server's data, so it is asserted here by calling them. What
   the server adds for them — a session's branch, a project's update command —
   is asserted against real files in a temp directory. */

process.stdout.write('\n== §30 the top bar and the navigator ==\n');

{
  const nav = await import(`../../kit/studio/web/nav.js?t=${Date.now()}`);
  const live = await import(`../../kit/studio/web/liveness.js?t=${Date.now()}`);
  const { kitStatus, _internals: kitInt } = await import(`../../kit/studio/server/lib/kit.js?t=${Date.now()}`);
  const { sessionTail, listSessions } = await import(`../../kit/studio/server/lib/projects.js?t=${Date.now()}`);
  const appJs = read(path.join(WEB_ROOT, 'app.js')) ?? '';
  const indexHtml = read(path.join(WEB_ROOT, 'index.html')) ?? '';
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-studio-nav-'));

  try {
    /* -- 1. the update command comes from the server, per install type ------ */

    const fileInstall = path.join(tmp, 'file-install');
    fs.mkdirSync(path.join(fileInstall, '.claude'), { recursive: true });
    fs.writeFileSync(path.join(fileInstall, '.claude', 'VERSION'), '2.12.0\n');
    // What a plugin install looks like from a project: a directory with no Crewforth file in it.
    const pluginShape = path.join(tmp, 'plugin-shape');
    fs.mkdirSync(path.join(pluginShape, '.claude'), { recursive: true });
    fs.writeFileSync(path.join(pluginShape, '.claude', 'settings.json'), '{}\n');
    const latest = { measured: true, version: '3.0.1' };

    const behind = await kitStatus(fileInstall, latest);
    check('a file install that is behind is told how to update, by the server',
      behind.installed && behind.outdated && behind.updateCommand === kitInt.FILE_INSTALL_UPDATE
      && behind.updateCommand === 'npx crewforth@latest update --here',
      `updateCommand: ${JSON.stringify(behind.updateCommand)}`);
    const badgeBehind = nav.badgeFor(behind);
    check('its badge copies exactly that command and says so',
      badgeBehind.copy === behind.updateCommand && badgeBehind.text === '2.12.0 · update'
      && badgeBehind.title.includes(behind.updateCommand), JSON.stringify(badgeBehind));

    const plugin = await kitStatus(pluginShape, latest);
    check('a project with no Crewforth files gets no command: a plugin install cannot be told apart from here',
      plugin.installed === false && plugin.updateCommand === null,
      `updateCommand: ${JSON.stringify(plugin.updateCommand)}`);
    const badgePlugin = nav.badgeFor(plugin);
    check('its badge copies nothing and points at /crew-update instead of inventing a command',
      badgePlugin.copy === null && /\/crew-update/.test(badgePlugin.title) && badgePlugin.text === 'no Crewforth'
      && !/npx/.test(JSON.stringify(badgePlugin)), JSON.stringify(badgePlugin));

    const current = nav.badgeFor(await kitStatus(fileInstall, { measured: true, version: '2.12.0' }));
    const uncompared = nav.badgeFor(await kitStatus(fileInstall, { measured: false, reason: 'offline' }));
    check('a current project and an uncompared one offer nothing to copy',
      current.copy === null && current.tone === 'current'
      && uncompared.copy === null && uncompared.tone === 'unknown' && /not compared: offline/.test(uncompared.title),
      'not compared is not "current", and neither is a reason to run an update');
    check('a badge never copies a command the server did not send',
      nav.badgeFor({ installed: true, version: '2.0.0', compared: true, outdated: true, latest: '3.0.1' }).copy === null
      && /\/crew-update/.test(nav.badgeFor({ installed: true, version: '2.0.0', compared: true, outdated: true, latest: '3.0.1' }).title),
      'an older server sends no updateCommand; the badge falls back to the hint');

    // The command text has one home. Nothing the browser loads may carry a copy of it.
    const typed = (text) => /npx\s+(--yes\s+)?crewforth|crewforth@latest/.test(text);
    const webFiles = walk(WEB_ROOT);
    const carriers = webFiles.filter((f) => typed(read(f) ?? '')).map((f) => path.basename(f));
    check('no file under web/ types the update command itself',
      webFiles.length >= 9 && carriers.length === 0,
      carriers.length ? `typed in: ${carriers.join(', ')}` : `${webFiles.length} files read`);
    check('twin: a command typed into a script is caught',
      typed("copyText('npx crewforth@latest update --here')") && typed('npx --yes crewforth@latest update')
      && !typed('run /crew-update in this project'));

    /* -- 2. a session's branch, read from its transcript --------------------- */

    const tDir = path.join(tmp, 'transcripts');
    fs.mkdirSync(tDir);
    const writeT = (name, lines) => {
      const f = path.join(tDir, name);
      fs.writeFileSync(f, lines.map((l) => (typeof l === 'string' ? l : JSON.stringify(l))).join('\n') + '\n');
      const st = fs.statSync(f);
      return [f, st.size, st.mtimeMs];
    };
    const moved = await sessionTail(...writeT('moved.jsonl', [
      { type: 'user', cwd: '/x', gitBranch: 'main', message: { content: 'start' } },
      { type: 'ai-title', aiTitle: 'Refund rounding' },
      { type: 'user', cwd: '/x', gitBranch: 'fix/refund-rounding', message: { content: 'go on' } },
    ]));
    check('the branch is the one the session is on now, and the title still comes from the same read',
      moved.branch === 'fix/refund-rounding' && moved.title === 'Refund rounding', JSON.stringify(moved));
    const none = await sessionTail(...writeT('none.jsonl', [{ type: 'user', cwd: '/x', message: { content: 'hi' } }]));
    const empty = await sessionTail(...writeT('empty.jsonl', [{ type: 'user', cwd: '/x', gitBranch: '', message: { content: 'hi' } }]));
    check('a transcript with no branch, or an empty one, yields null and not a guess',
      none.branch === null && empty.branch === null, `${JSON.stringify(none.branch)} / ${JSON.stringify(empty.branch)}`);
    const quoted = await sessionTail(...writeT('quoted.jsonl', [
      { type: 'user', cwd: '/x', gitBranch: 'real', message: { content: 'the record says "gitBranch":"fake" somewhere' } },
    ]));
    check('text that merely mentions the field is not read as the branch', quoted.branch === 'real', JSON.stringify(quoted.branch));
    const odd = await sessionTail(...writeT('odd.jsonl', [{ type: 'user', cwd: '/x', gitBranch: 'feat/"q"\\ü' }]));
    check('a branch with escaped characters comes back as it was written', odd.branch === 'feat/"q"\\ü', JSON.stringify(odd.branch));
    const listed = (await listSessions(tDir)).find((s) => s.sessionId === 'moved');
    check('the session list carries the branch beside the title', listed?.branch === 'fix/refund-rounding' && listed?.title === 'Refund rounding');

    /* -- 3. what a row is called, and what is under it ----------------------- */

    const sn = { sessionId: '7f3c1d20-9a4e', title: 'Refund rounding', branch: 'fix/refund-rounding', agentCount: 3 };
    check('a row is called by its label, then its title, then its id — never by a branch',
      nav.sessionName(sn, { '7f3c1d20-9a4e': 'mine' }) === 'mine'
      && nav.sessionName(sn, {}) === 'Refund rounding'
      && nav.sessionName({ ...sn, title: null }, {}) === '7f3c1d20'
      && nav.sessionName({ ...sn, title: null }, { '7f3c1d20-9a4e': '   ' }) === '7f3c1d20');
    const running = { key: 'busy', word: 'Running', tone: 'busy', known: true };
    check('the line under it is branch, state and agents',
      nav.sessionSub(sn, running) === 'fix/refund-rounding · Running · 3 agents'
      && nav.sessionSub({ ...sn, agentCount: 1 }, running) === 'fix/refund-rounding · Running · 1 agent');
    const bare = nav.sessionSub({ sessionId: 'x', title: null, branch: null, agentCount: 0 }, { key: 'unmeasured', word: null, tone: null });
    const noBranch = nav.sessionSub({ ...sn, branch: null }, running);
    check('a part that was not read is left out, not filled in',
      bare === '' && noBranch === 'Running · 3 agents' && !/null|undefined|—|unknown/.test(bare + noBranch),
      `${JSON.stringify(bare)} / ${JSON.stringify(noBranch)}`);

    /* -- 4. status: a word with every colour, and no colour for the unknown -- */

    const fleet = { measured: true, sessions: [
      { sessionId: 'a', status: 'busy' }, { sessionId: 'b', status: 'waiting', waitingFor: 'approve Bash' },
      { sessionId: 'c', status: 'idle' }, { sessionId: 'd', status: 'hibernating' },
      { sessionId: 'e', status: 'busy', local: false },
    ] };
    const st = (id, f = fleet) => nav.sessionStatus(id, f);
    check('every session state the machine reports has a word beside its colour',
      st('a').word === 'Running' && st('a').tone === 'busy'
      && st('b').word === 'Needs you' && st('b').tone === 'waiting' && st('b').waitingFor === 'approve Bash'
      && st('c').word === 'Idle' && st('c').tone === 'idle');
    check('a session the machine does not list has ended', st('zz').key === 'ended' && st('zz').word === 'Ended' && st('zz').tone === null);
    check('a state nobody recognises keeps its own word and gets no colour',
      st('d').word === 'hibernating' && st('d').tone === null && st('d').known === false);
    check('a fleet that was not read is "unmeasured", never "ended"',
      st('a', { measured: false, reason: 'no CLI' }).key === 'unmeasured' && st('a', null).key === 'unmeasured'
      && st('a', { measured: false }).word === null,
      'an unread list would otherwise draw every session as finished');
    check('a session on another machine does not lend its state to a local row', st('e').key === 'ended');

    const chips = nav.summaryChips({ done: 6, running: 3, failed: 1, zombie: 2, ended: 0, starting: 1 });
    check('the summary has one chip per status in play, and they add up',
      chips.map((c) => c.text).join(' | ') === '3 running | 1 starting | 6 done | 1 failed | 2 zombie'
      && chips.reduce((n, c) => n + c.count, 0) === 13, chips.map((c) => c.text).join(' | '));
    check('every chip carries a word, and an unknown status its own with no colour',
      chips.every((c) => /^\d+ \S+/.test(c.text))
      && chips.find((c) => c.status === 'zombie').tone === null && chips.find((c) => c.status === 'zombie').known === false
      && chips.find((c) => c.status === 'failed').tone === 'fail' && chips.find((c) => c.status === 'done').tone === 'good');
    check('no agents is no chips, not a row of zeros', nav.summaryChips({}).length === 0 && nav.summaryChips(null).length === 0
      && nav.summaryChips({ done: 0 }).length === 0);

    /* -- 5. search ------------------------------------------------------------ */

    const proj = { label: 'acme-payments-api' };
    check('search reaches the project name, the branch, the session id and the row\'s name',
      nav.matchesSession('PAYMENTS', proj, sn, {}) && nav.matchesSession('refund-round', proj, sn, {})
      && nav.matchesSession('7f3c', proj, sn, {}) && nav.matchesSession('rounding', proj, sn, {})
      && nav.matchesSession('mine', proj, sn, { '7f3c1d20-9a4e': 'mine' })
      && !nav.matchesSession('ledger', proj, sn, {}) && nav.matchesSession('  ', proj, sn, {}));
    const parts = nav.highlight('feat/Payment-retries · payments', 'payment');
    check('the match is marked where it is, in the case it was written in',
      parts.filter((p) => p.hit).map((p) => p.text).join('|') === 'Payment|payment'
      && parts.map((p) => p.text).join('') === 'feat/Payment-retries · payments'
      && nav.highlight('abc', '').length === 1 && nav.highlight('abc', 'zz')[0].hit === false);

    /* -- 6. live and machines ------------------------------------------------- */

    const liveRows = nav.liveSessions({ measured: true, sessions: [
      { sessionId: 'i', status: 'idle' }, { sessionId: 'r', status: 'busy', startedAt: 5 },
      { sessionId: 'w', status: 'waiting', startedAt: 1 }, { sessionId: 'r2', status: 'busy', startedAt: 9 },
    ] });
    check('Live is what is working or waiting, the waiting ones first',
      liveRows.map((s) => s.sessionId).join() === 'w,r2,r');
    check('an unread fleet has no live list to show', nav.liveSessions({ measured: false }).length === 0 && nav.liveSessions(null).length === 0);
    check('and the panel says so instead of "none running"',
      /Not measured/.test(appJs) && /not the same as "nothing is running"/.test(appJs) && /No sessions running/.test(appJs));

    const mach = nav.machines({
      origins: [{ name: 'here', local: true, ok: true }, { name: 'mini', ok: true, sessions: 2 }, { name: 'box', ok: false, reason: 'ECONNREFUSED' }],
      roster: { measured: true, seenAt: 1000, peers: [{ name: 'laptop', remote: true, status: 'idle' }, { name: 'self', remote: false }] },
    });
    check('a peer asked just now and a session recorded earlier are different kinds of row',
      mach.peers.map((p) => `${p.name}:${p.kind}:${p.ok}`).join() === 'mini:peer:true,box:peer:false'
      && mach.peers[1].reason === 'ECONNREFUSED'
      && mach.remote.length === 1 && mach.remote[0].kind === 'snapshot' && mach.remote[0].seenAt === 1000);
    check('a roster nobody recorded is not "no other machines"',
      nav.machines({ origins: [], roster: { measured: false, reason: 'never recorded' } }).rosterMeasured === false
      && nav.machines({ origins: [], roster: { measured: false, reason: 'never recorded' } }).rosterReason === 'never recorded'
      && nav.machines(null).rosterMeasured === false);
    check('a snapshot says how old it is', nav.seenAgo(0, 185000) === 'seen 3 min ago' && nav.seenAgo(0, 20000) === 'seen just now'
      && nav.seenAgo(null, 5) === 'seen at an unrecorded time' && nav.ago(0, 7200000) === '2h' && nav.ago(0, 30000) === 'now');

    /* -- 7. Live, Stale, Offline ---------------------------------------------- */

    const T = 1_000_000;
    check('heard from a moment ago is Live, with how long ago',
      live.liveness(T, T - 2000, false).state === 'live' && live.liveness(T, T - 2000, false).detail === '2s ago');
    check('the threshold is where Live becomes Stale, and not a millisecond before',
      live.liveness(T, T - live.STALE_AFTER_MS, false).state === 'live'
      && live.liveness(T, T - live.STALE_AFTER_MS - 1, false).state === 'stale');
    check('a failed request is Offline whatever the clock says, and keeps the time of the last answer',
      live.liveness(T, T - 500, true).state === 'offline' && /^last update \d\d:\d\d$/.test(live.liveness(T, T - 500, true).detail)
      && live.liveness(T, null, true).detail === 'the server has not answered');
    check('before the first answer it is Connecting, not Live', live.liveness(T, null, false).state === 'connecting');
    check('every state has a word, so none of them is told by colour alone',
      [[T - 1, false], [T - 99999, false], [T, true], [null, false]].every(([ok, failed]) => live.liveness(T, ok, failed).word.length > 3));

    // The threshold was chosen against the slowest healthy silence, which is one
    // project poll (the fleet poll can be slower than that, and then it is the
    // project poll that keeps the panel fed). Slowing that poll without moving
    // the threshold would make a healthy panel read Stale.
    const pollMs = (name) => Number(new RegExp(`const ${name} = (\\d+);`).exec(appJs)?.[1]);
    const roomFor = (staleMs, slowestPollMs) => staleMs >= 2 * slowestPollMs;
    check('the Stale threshold leaves room for two project polls',
      pollMs('SESSION_POLL_MS') > 0 && pollMs('FLEET_POLL_MS') > 0
      && roomFor(live.STALE_AFTER_MS, Math.max(pollMs('SESSION_POLL_MS'), 0)),
      `stale after ${live.STALE_AFTER_MS} ms; polls every ${pollMs('FLEET_POLL_MS')} and ${pollMs('SESSION_POLL_MS')} ms`);
    check('twin: a slower project poll with the same threshold is caught', !roomFor(live.STALE_AFTER_MS, 6000));
    check('any answer on any channel counts as heard from',
      (appJs.match(/heardNow\(\)|heardNow\)/g) ?? []).length >= 4
      && /addEventListener\('graph', \(e\) => \{\s*heardNow\(\);/.test(appJs)
      && /addEventListener\('idle', heardNow\)/.test(appJs),
      'the fleet poll alone waits on a CLI spawn; the project poll and the stream do not');
    check('only a request that did not complete is Offline; an error status is still an answer',
      /catch \(e\) \{\s*heard\.failed = true;\s*throw e;\s*\}\s*if \(!r\.ok\) throw/.test(appJs));

    /* -- 8. the summary chips filter the canvas ------------------------------- */

    const dom = installDom();
    try {
      const { Canvas } = await import(`../../kit/studio/web/canvas.js?filter=${Date.now()}`);
      const c = new Canvas(document.createElement('div'), {});
      c.setPalette({ map: { Explore: { hex: '#26c6e6', source: 'builtin' } }, unknown: '#94a3c8' });
      c.setSession('s-filter');
      const agent = (id, status) => ({ id, kind: 'agent', agentType: 'Explore', status, spawnDepth: 1, parentId: 'session', tools: {}, toolCount: 0 });
      c.render({
        nodes: [{ id: 'session', kind: 'session', status: 'session', turns: 1, cwd: '/x' }, agent('r', 'running'), agent('d', 'done'), agent('f', 'failed')],
        edges: [{ source: 'session', target: 'r' }, { source: 'session', target: 'd' }, { source: 'session', target: 'f' }],
      });
      const dim = (id) => c.els.get(id).classList.contains('cv-dim');
      check('with no filter nothing is stepped back', !dim('r') && !dim('d') && !dim('f') && !dim('session'));
      c.setFilter('running');
      check('a status filter steps back the agents in every other status and leaves the session lit',
        !dim('r') && dim('d') && dim('f') && !dim('session'));
      check('the cards stay where they were: a filter is not a new layout',
        c.els.size === 4 && c.nodes.size === 4);
      c.setFilter(null);
      check('taking the filter off brings everything back', !dim('r') && !dim('d') && !dim('f'));
    } finally {
      dom();
    }
    check('the chip that is filtering says so, and clicking it again undoes it',
      /setAttribute\('aria-pressed', String\(statusFilter === c\.status\)\)/.test(appJs)
      && /setStatusFilter\(statusFilter === c\.status \? null : c\.status\)/.test(appJs));
    check('a filter cannot outlive the status it filters on',
      /if \(statusFilter && !chips\.some\(\(c\) => c\.status === statusFilter\)\) setStatusFilter\(null, false\)/.test(appJs),
      'when the last running agent finishes, a "running" filter would hide every card with no chip left to undo it');

    /* -- 9. the page ----------------------------------------------------------- */

    check('the bar has the breadcrumb, the summary, the Live indicator and one primary button',
      /id="crumb"[^>]*aria-label="Breadcrumb"/.test(indexHtml) && /id="graph-summary"[^>]*aria-label="Session summary"/.test(indexHtml)
      && /id="pulse"[^>]*role="status"/.test(indexHtml) && (indexHtml.match(/class="btn primary"/g) ?? []).length === 1);
    check('the old three folding blocks are gone', !/data-fold/.test(indexHtml) && !/side-block/.test(indexHtml));
    check('the footer line is gone; its reasons moved into the toolbar',
      !/<footer/.test(indexHtml) && /<span id="foot-note" class="toolbar-note" role="status">/.test(indexHtml));
    check('the navigator answers to / [ and ]',
      /e\.key === '\/'/.test(appJs) && /e\.key === '\['/.test(appJs) && /e\.key === '\]'/.test(appJs)
      && /tagName === 'INPUT'/.test(appJs), 'and not while something is being typed into');
    check('a terminal is only opened after its command has been shown',
      /note: plan\.line/.test(appJs) && appJs.indexOf('note: plan.line') < appJs.indexOf("method: 'POST'"),
      'the command is in the menu before the button that runs it');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

process.stdout.write(`${pass}/${pass + fail} assertions passed`
  + (skipped ? `, ${skipped} skipped` : '')
  + (na ? `, ${na} n/a on ${process.platform}` : '') + '\n');
process.exit(fail ? 1 : 0);
