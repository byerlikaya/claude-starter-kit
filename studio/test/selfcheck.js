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

import { _internals } from '../server/lib/fleet.js';
import { contextFill } from '../server/lib/transcript.js';
import { encodeCwd } from '../server/lib/projects.js';
import { _internals as graphInternals } from '../server/lib/graph.js';
import { palette } from '../server/lib/palette.js';
import { renderMarkdown } from '../web/md.js';
import { ALLOWED_MODES } from '../server/lib/session.js';
import { parsePeers } from '../server/lib/peers.js';
import { writeAllowed } from '../server/index.js';
import { prepare, decide, pending, cleanup, _internals as permInternals } from '../server/lib/permissions.js';
import { execFileSync } from 'node:child_process';
import os from 'node:os';
import { quickReplies } from '../web/chat.js';
import { installDom } from './dom-stub.js';
import * as pty from '../server/lib/pty.js';
import { plan as terminalPlan } from '../server/lib/terminal.js';
import { gateLog, gateReport, board, sessionStats, _internals as kitInternals } from '../server/lib/kit-telemetry.js';
import { parseRoster, remoteRoster } from '../server/lib/roster.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const STUDIO = path.resolve(HERE, '..');
const REPO = path.resolve(STUDIO, '..');
const WEB_ROOT = path.join(STUDIO, 'web');

let pass = 0;
let fail = 0;
let skipped = 0;
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
 * CSK_VERIFY_STRICT — which CI sets — that is a broken runner, not an honest
 * boundary, so it goes red. Every other class stays a skip.
 */
function skip(name, kind, why) {
  const strict = process.env.CSK_VERIFY_STRICT === '1' && kind === 'tool';
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

check(
  'pin: studio is absent from the root package files[]',
  Array.isArray(rootPkg.files) && !rootPkg.files.some((f) => String(f).includes('studio')),
  `files[] = ${JSON.stringify(rootPkg.files)}`,
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
  if (f.endsWith(path.join('test', 'selfcheck.js'))) return false; // the pin names the literal it forbids
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
  startedAt: 1787667229756, sessionId: 'abc-123', name: 'mac-csk', status: 'busy',
});
check('normalise keeps the identifying fields', real?.sessionId === 'abc-123' && real.name === 'mac-csk' && real.status === 'busy');
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
check('kit agent colours are read from frontmatter', pal.kitAgents >= 12, `${pal.kitAgents} kit agents`);
check('a declared colour resolves to a hex value', /^#[0-9a-f]{6}$/i.test(pal.map['security-expert-csk']?.hex ?? ''));
check('an undeclared agent type falls back to neutral, never a borrowed colour',
  !pal.map['no-such-agent-type'] && /^#[0-9a-f]{6}$/i.test(pal.unknown));

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
  writeAllowed(req({ 'x-csk-studio': '0' })).ok === false);
check('a same-origin request with the header is allowed',
  writeAllowed(req({ 'x-csk-studio': '1', origin: 'http://127.0.0.1:7777' })).ok === true);
check('localhost counts as same-origin',
  writeAllowed(req({ 'x-csk-studio': '1', origin: 'http://localhost:7777' })).ok === true);
check('a cross-origin request is refused even with the header',
  writeAllowed(req({ 'x-csk-studio': '1', origin: 'https://evil.example' })).ok === false);
check('an unparseable Origin is refused rather than ignored',
  writeAllowed(req({ 'x-csk-studio': '1', origin: 'not a url' })).ok === false);
check('a request with no Origin at all still needs the header',
  writeAllowed(req({ 'x-csk-studio': '1' })).ok === true &&
  writeAllowed(req({ origin: 'http://127.0.0.1:7777' })).ok === false);
check('a token always exists, generated when none was supplied',
  /CSK_STUDIO_TOKEN \|\| randomUUID\(\)/.test(idxSrc));
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

  // Behaviour, not text. Each case runs the real hook.
  const payload = JSON.stringify({
    session_id: probeId, tool_name: 'Bash', tool_use_id: 'toolu_probe',
    tool_input: { command: 'echo probe' },
  });
  const runHook = (env = {}) => {
    try {
      execFileSync('bash', [HOOK, gate.spool], {
        input: payload,
        env: { ...process.env, CSK_GATE_WAIT: '1', ...env },
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

/* --------------------------------------------- §14 raw terminals ------
   The one surface here the kit's gates cannot see. A command typed in a raw
   shell never reaches a PreToolUse hook, because there is no tool call to
   intercept. That makes "off unless asked for" a property worth pinning. */

process.stdout.write('\n== §14 raw terminals ==\n');

check('a raw shell is refused until it is asked for',
  pty.create({ cwd: process.cwd() }).ok === false && pty.isEnabled() === false);
check('the refusal names the flag rather than failing vaguely',
  /--enable-pty/.test(pty.create({ cwd: process.cwd() }).reason ?? ''));

const ptySrc = read(path.join(STUDIO, 'server', 'lib', 'pty.js')) ?? '';
check('Windows is told it cannot, rather than left to fail',
  /Unix-only/.test(ptySrc) && /win32/.test(ptySrc));
check('the bridge is not named pty.py, which would shadow the module it imports',
  fs.existsSync(path.join(STUDIO, 'server', 'lib', 'pty-bridge.py')) &&
  !fs.existsSync(path.join(STUDIO, 'server', 'lib', 'pty.py')));
// The shell scripts here are covered by verify.sh's syntax step; the python one
// is not, so it is checked where it lives.
//
// A resolvable name is not a working interpreter. Windows ships a python3 stub
// that passes `command -v`, prints "Python was not found" and exits 49 — so the
// candidates are tried in order and the first one that actually runs is used.
// ENOENT was the only miss handled before, which turned that stub into a loud
// FAIL claiming the bridge does not compile, when nothing had compiled it.
{
  const bridgePath = path.join(STUDIO, 'server', 'lib', 'pty-bridge.py');
  let compiled = null;
  for (const c of ['python3', 'python']) {
    try {
      execFileSync(c, ['-c', 'import ast,sys; ast.parse(open(sys.argv[1]).read())', bridgePath],
        { stdio: 'pipe', timeout: 20000 });
      compiled = true; break;
    } catch (e) {
      // Only a real parse failure is an answer; a missing or stubbed
      // interpreter means we still have not asked anyone.
      if (e.status === 1 && String(e.stderr ?? '').includes('SyntaxError')) { compiled = false; break; }
    }
  }
  if (compiled === null) skip('the bridge compiles', 'tool', 'no working python found to parse it');
  else check('the bridge compiles', compiled, 'pty-bridge.py has a syntax error');
}
check('the scrollback buffer holds bytes, not concatenated base64',
  /Buffer\.concat/.test(ptySrc) && !/this\.buffer \+= msg\.d/.test(ptySrc));

const termSrc = read(path.join(STUDIO, 'web', 'term.js')) ?? '';
check('the terminal view says on screen that nothing guards it',
  /No gate here/.test(termSrc));
check('keystrokes are queued so their order survives the network',
  /outbox/.test(termSrc) && /await fetch/.test(termSrc));

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
const logHome = fs.mkdtempSync(path.join(os.tmpdir(), 'csk-studio-gatelog-'));
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

const live = remoteRoster();
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
  const sess = read(path.join(HERE, '..', 'server', 'lib', 'session.js')) ?? '';
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
  for (const mod of ['md.js', 'canvas.js', 'chat.js', 'term.js', 'app.js']) {
    let err = null;
    try {
      // Cache-busted so a module is really evaluated on every run.
      await import(`../web/${mod}?t=${Date.now()}`);
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
      const { Canvas } = await import(`../web/canvas.js?render=${Date.now()}`);
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

for (const mod of ['app.js', 'chat.js', 'canvas.js', 'term.js']) {
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
check('the conversation is a column beside the graph, not a drawer under it',
  /grid-template-columns:\s*var\(--side-w[^)]*\)\s+5px\s+1fr\s+5px\s+var\(--chat-w/.test(cssSrc));
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
  && /\.shell > \.chat\s*\{\s*grid-column:\s*5/.test(cssSrc));
check('the control that reopens the sidebar is on the edge it acts on',
  /\.side-rail\s*\{[^}]*left:\s*0/.test(cssSrc),
  'it started in the header, in the opposite corner from the panel it opens');

const appSrc2 = read(path.join(STUDIO, 'web', 'app.js')) ?? '';
check('the right-hand divider grows its panel when dragged left',
  /edge === 'right' \? -1 : 1/.test(appSrc2),
  'sharing one handler without inverting the delta shrank the panel being opened');
check('both widths are remembered', /csk-studio-side-w/.test(appSrc2) && /csk-studio-chat-w/.test(appSrc2));


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
  const entry = path.join(HERE, '..', 'server', 'index.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'csk-studio-link-'));
  const link = path.join(dir, 'csk-studio');
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


/* ------------------------------------------- §24 foldable side sections */

// The kit has been bitten twice by a hide rule losing to a display rule:
// `[hidden]` lost to `display: grid`, and a `display: none` grid child stopped
// occupying its cell. So assert the cascade, not the intent.
{
  const html = read(path.join(HERE, '..', 'web', 'index.html')) ?? '';
  const css = read(path.join(HERE, '..', 'web', 'style.css')) ?? '';
  const app = read(path.join(HERE, '..', 'web', 'app.js')) ?? '';

  for (const key of ['fleet', 'reach', 'sessions']) {
    check(`the ${key} section has a fold control and a body to fold`,
      html.includes(`data-fold="${key}"`) && html.includes(`data-fold-body="${key}"`),
      'a twisty with nothing wired to it folds nothing');
  }
  check('every project-list body folds, filter box included',
    (html.match(/data-fold-body="sessions"/g) ?? []).length === 2,
    'folding the tree while leaving the search box behind looks like a rendering bug');

  check('the fold rule outranks the display it has to beat',
    /\[data-fold-body\]\.is-folded\s*\{\s*display:\s*none/.test(css),
    'a bare .is-folded ties with .fleet/.sessions and loses on source order');
  check('a folded section stops claiming leftover height',
    /\.side-block\.folded\s*\{\s*flex:\s*none/.test(css),
    'without this the sidebar keeps a tall empty gap where the tree was');

  check('the fold choice is remembered per browser',
    /csk-studio-fold-/.test(app));
  check('a browser that refuses localStorage still folds',
    /localStorage\.setItem\(`csk-studio-fold-[\s\S]{0,120}?\} catch/.test(app),
    'private mode throws on setItem; an unguarded write kills the click handler');
}


/* ------------------------------------- §25 the pty bridge survives garbage */

// One frame that would not base64-decode killed the whole terminal, and it
// surfaced as an exit with no code — which reads as "the shell died on its
// own" rather than "we sent it something bad". Assert the behaviour, because
// the fix is an except clause and a grep for one proves nothing about reach.
{
  const bridge = path.join(HERE, '..', 'server', 'lib', 'pty-bridge.py');
  let python = null;
  for (const c of ['python3', 'python']) {
    try {
      execFileSync(c, ['-c', 'import pty'], { stdio: 'ignore', timeout: 10000 });
      python = c; break;
    } catch { /* try the next one; a resolvable name is not a working one */ }
  }
  if (!python) {
    skip('the pty bridge survives an undecodable frame', 'tool', 'no python3 with the pty module');
  } else {
    const probe = [
      'import json,subprocess,sys,time',
      `p=subprocess.Popen([${JSON.stringify(python)},${JSON.stringify(bridge)},"/tmp","/bin/sh","30","100"],`,
      ' stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,text=True,bufsize=1)',
      'time.sleep(0.5)',
      'assert p.poll() is None, "bridge exited before the test began"',
      'p.stdin.write(json.dumps({"t":"in","d":"!!!not-base64!!!"})+chr(10)); p.stdin.flush()',
      'p.stdin.write(json.dumps({"t":"size","rows":"abc","cols":None})+chr(10)); p.stdin.flush()',
      'time.sleep(0.8)',
      'alive = p.poll() is None',
      'p.terminate()',
      'print("ALIVE" if alive else "DEAD")',
    ].join('\n');
    let verdict = '';
    try {
      verdict = execFileSync(python, ['-c', probe], { encoding: 'utf8', timeout: 30000 }).trim();
    } catch (e) {
      verdict = `ERROR ${e?.message ?? e}`;
    }
    check('the pty bridge survives an undecodable frame',
      verdict === 'ALIVE',
      `a bad frame took the terminal down instead of being dropped (got ${JSON.stringify(verdict)})`);
  }
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

  const { Canvas } = await import(`../web/canvas.js?motion=${Date.now()}`);
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

  const bareRoot = rules.filter((r) => r.sel === ':root' && r.media.length === 0);
  const darkRoot = rules.filter((r) => r.sel === ':root:not([data-theme="light"])' && r.media.length === 0);
  const lightBack = rules.filter((r) => r.sel === ':root:not([data-theme="dark"])' && r.media.length === 1);
  const used = new Set();
  const collect = (v) => { for (const m of String(v).matchAll(/var\((--[\w-]+)\)/g)) used.add(m[1]); };
  for (const id of IDS) { for (const v of still(id).values()) collect(v); collect(edge('session', id).style.stroke); }
  for (const v of cardRing('live').values()) collect(v);
  const themed = [...used].filter((t) => t.startsWith('--cv-'));
  check('the edge states are expressed as tokens rather than literals',
    themed.length >= 5, `tokens in play: ${themed.join(', ') || 'none'}`);
  const orphan = themed.filter((t) => !bareRoot.some((r) => r.decls.has(t))
    || !darkRoot.some((r) => r.decls.has(t))
    || !lightBack.some((r) => r.decls.has(t)));
  check('every edge token is defined on bare :root and redefined in both theme blocks',
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
  const { Canvas } = await import(`../web/canvas.js?lod=${Date.now()}`);

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

  const TYPES = ['Explore', 'Plan', 'reviewer', 'tester', 'planner-csk',
    'backend-expert-csk', 'docs-agent', 'security'];
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
    const live = byType('backend-expert-csk');
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
      `backend-expert-csk -> ${JSON.stringify(live.parts.type.dataset.short)},`
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
process.stdout.write(`${pass}/${pass + fail} assertions passed`
  + (skipped ? `, ${skipped} skipped` : '') + '\n');
process.exit(fail ? 1 : 0);
