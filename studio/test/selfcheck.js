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

const own = gateLog(REPO);
check('the gate log is read where it exists', own.measured === true, own.reason ?? `${own.total} entries`);
check('the log is marked as carrying no timestamps',
  own.measured && own.timestamped === false,
  'the format has no timestamp column, and the panel must not imply one');
check('whether commands were recorded is stated, not assumed',
  own.measured && typeof own.commandsRecorded === 'boolean');
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
