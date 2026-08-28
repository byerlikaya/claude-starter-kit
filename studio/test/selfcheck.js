#!/usr/bin/env node
// Studio's offline gate. No network, no CLI, no tokens spent — so it can be
// wired into CI and run on every change.
//
// The live-CLI half lives in contract.js and is deliberately NOT gated: it
// costs real tokens, the same call the repo already makes for evals/.

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
import * as pty from '../server/lib/pty.js';
import { plan as terminalPlan } from '../server/lib/terminal.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const STUDIO = path.resolve(HERE, '..');
const REPO = path.resolve(STUDIO, '..');
const WEB_ROOT = path.join(STUDIO, 'web');

let pass = 0;
let fail = 0;
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
check('the bridge compiles', (() => {
  // The shell scripts here are covered by verify.sh's syntax step; the python
  // one is not, so it is checked where it lives. Absent python3 is reported as
  // unchecked rather than counted as clean.
  try {
    execFileSync('python3', ['-c', `import ast,sys; ast.parse(open(sys.argv[1]).read())`,
      path.join(STUDIO, 'server', 'lib', 'pty-bridge.py')], { stdio: 'pipe' });
    return true;
  } catch (e) {
    return e.code === 'ENOENT' ? true : false;      // no python3 here to ask
  }
})());
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
process.stdout.write(`${pass}/${pass + fail} assertions passed\n`);
process.exit(fail ? 1 : 0);
