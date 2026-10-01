// Crewforth Studio — wiring.
//
// One rule runs through the rendering: "not measured" and "nothing running"
// are different facts and never share a screen state. An empty list because
// the CLI is missing would read as a quiet, healthy machine, which is exactly
// the kind of lie this panel exists to stop telling.

import { migrateStorage } from './storage-migrate.js';
import { initTheme } from './theme.js';
import { Canvas } from './canvas.js';
import { renderMarkdown } from './md.js';
import { Chat } from './chat.js';
import {
  summaryChips, sessionStatus, sessionName, sessionSub, ago, matchesSession, highlight, badgeFor,
  liveSessions, machines, seenAgo,
} from './nav.js';
import { liveness } from './liveness.js';

const FLEET_POLL_MS = 2000;
const SESSION_POLL_MS = 5000;

const el = {
  fleet: document.getElementById('fleet'),
  sessions: document.getElementById('sessions'),
  reach: document.getElementById('reach'),
  otherMachines: document.getElementById('other-machines'),
  liveCount: document.getElementById('live-count'),
  filter: document.getElementById('filter'),
  chat: document.getElementById('chat'),
  chatSplit: document.getElementById('chat-split'),
  resizer: document.getElementById('resizer'),
  sideHide: document.getElementById('side-hide'),
  sideShow: document.getElementById('side-show'),
  rail: document.getElementById('side-rail'),
  home: document.getElementById('home'),
  bar: document.querySelector('.bar'),
  crumb: document.getElementById('crumb'),
  fullscreen: document.getElementById('fullscreen'),
  newSession: document.getElementById('new-session'),
  continueSession: document.getElementById('continue-session'),
  summary: document.getElementById('graph-summary'),
  pulse: document.getElementById('pulse'),
  foot: document.getElementById('foot-note'),
  theme: document.getElementById('theme'),
  inspector: document.getElementById('inspector'),
  toast: document.getElementById('toast'),
  menu: document.getElementById('menu'),
};

const token = new URLSearchParams(location.search).get('token');
const api = (p) => (token ? `${p}${p.includes('?') ? '&' : '?'}token=${encodeURIComponent(token)}` : p);

// When the server was last heard from, for the Live indicator. A request that does not complete is the
// connection failing; one that completes with an error status is the server answering, and is neither.
const heard = { okAt: null, failed: false };
const heardNow = () => { heard.okAt = Date.now(); heard.failed = false; };

const getJson = async (p) => {
  let r;
  try {
    r = await fetch(api(p), { cache: 'no-store' });
  } catch (e) {
    heard.failed = true;
    throw e;
  }
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const body = await r.json();
  heardNow();
  return body;
};

/* ---------------------------------------------------------------- theme */

try { migrateStorage(localStorage); } catch { /* blocked storage */ }
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* blocked storage */ } },
};

// Handed the raw storage and not `store`: theme.js guards its own reads and
// writes, and a storage that cannot even be named is replaced by one that
// remembers nothing.
const systemLight = window.matchMedia('(prefers-color-scheme: light)');
let themeStorage = { getItem: () => null, setItem: () => {} };
try { themeStorage = localStorage; } catch { /* blocked storage */ }
const relabelTheme = initTheme(document.documentElement, el.theme, themeStorage, () => systemLight.matches);
systemLight.addEventListener('change', relabelTheme);

/* --------------------------------------------------------------- panels
   Three columns and two dividers. Each width is the user's, remembered, and
   clamped so neither side panel can be dragged to nothing by accident or made
   to swallow the graph. Collapsing is a separate, deliberate act with its own
   control. */

const PANEL = {
  side: { min: 170, max: 620, def: 272, wide: 460, varName: '--side-w', key: 'crewforth-studio-side-w' },
  chat: { min: 280, max: 900, def: 420, wide: 720, varName: '--chat-w', key: 'crewforth-studio-chat-w' },
};

function setPanel(which, px, persist = true) {
  const p = PANEL[which];
  const w = Math.round(Math.min(p.max, Math.max(p.min, px)));
  document.documentElement.style.setProperty(p.varName, `${w}px`);
  if (persist) store.set(p.key, String(w));
  return w;
}

for (const which of ['side', 'chat']) {
  setPanel(which, Number(store.get(PANEL[which].key)) || PANEL[which].def, false);
}

const shell = document.querySelector('.shell');

// `refit` is off for the first call, which restores the remembered state before
// the canvas exists. `typeof canvas` is not a guard here: a const in its
// temporal dead zone throws on typeof too, which is what took the whole page
// down rather than skipping one re-fit.
//
// Below 1024px the navigator is its rail and opens over the canvas. That is the
// window's doing, not the viewer's choice, so nothing done in that band is
// remembered: widening the window brings back whatever was chosen at a width
// where there was a choice to make.
const railBand = window.matchMedia('(max-width: 1023px)');

function setSideHidden(hidden, refit = true, persist = !railBand.matches) {
  shell.classList.toggle('no-side', hidden);
  el.rail.hidden = !hidden;
  if (persist) store.set('crewforth-studio-side-hidden', hidden ? '1' : '0');
  if (refit) canvas.fitIfUntouched();
}
const applyRailBand = (refit) => setSideHidden(
  railBand.matches || store.get('crewforth-studio-side-hidden') === '1', refit, false,
);
applyRailBand(false);
railBand.addEventListener('change', () => applyRailBand(true));

function dragPanel(handle, which, edge) {
  let drag = null;
  handle.addEventListener('pointerdown', (e) => {
    if (e.button !== 0) return;
    drag = { px: e.clientX, w: parseInt(getComputedStyle(document.documentElement).getPropertyValue(PANEL[which].varName), 10) || PANEL[which].def };
    handle.setPointerCapture(e.pointerId);
    handle.classList.add('dragging');
    document.body.classList.add('resizing');
  });
  handle.addEventListener('pointermove', (e) => {
    if (!drag) return;
    // The right-hand panel grows as the pointer moves left, so its delta is
    // inverted. Sharing one handler without this made the conversation shrink
    // when it was dragged open.
    const delta = (e.clientX - drag.px) * (edge === 'right' ? -1 : 1);
    setPanel(which, drag.w + delta);
  });
  const stop = () => {
    if (!drag) return;
    drag = null;
    handle.classList.remove('dragging');
    document.body.classList.remove('resizing');
    canvas.fitIfUntouched();
  };
  handle.addEventListener('pointerup', stop);
  handle.addEventListener('pointercancel', stop);
  handle.addEventListener('dblclick', () => { setPanel(which, PANEL[which].def); canvas.fitIfUntouched(); });
  handle.addEventListener('keydown', (e) => {
    const cur = parseInt(getComputedStyle(document.documentElement).getPropertyValue(PANEL[which].varName), 10) || PANEL[which].def;
    const step = edge === 'right' ? -16 : 16;
    if (e.key === 'ArrowLeft') { setPanel(which, cur + step); e.preventDefault(); }
    if (e.key === 'ArrowRight') { setPanel(which, cur - step); e.preventDefault(); }
  });
}

dragPanel(el.resizer, 'side', 'left');
dragPanel(el.chatSplit, 'chat', 'right');

/* ------------------------------------------------------------ full screen
   The browser's own, so it hides the browser too — a panel meant to be watched
   while work runs should be able to take the whole display. The stylesheet
   takes the navigator, the inspector and the conversation off with it, so what
   is left is the canvas; Esc brings everything back. */

async function toggleFullscreen() {
  try {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await document.documentElement.requestFullscreen();
  } catch (e) {
    // Denied by policy, or unsupported. Say so rather than appear inert.
    el.foot.textContent = `full screen refused: ${e?.message ?? e}`;
  }
}

el.fullscreen.addEventListener('click', toggleFullscreen);

document.addEventListener('fullscreenchange', () => {
  const on = Boolean(document.fullscreenElement);
  el.fullscreen.classList.toggle('on', on);
  el.fullscreen.title = on ? 'Leave full screen (f or Esc)' : 'Full screen (f)';
  el.fullscreen.setAttribute('aria-label', on ? 'Leave full screen' : 'Full screen');
  canvas.fitIfUntouched();
});

// `f` toggles it, unless something is being typed into.
document.addEventListener('keydown', (e) => {
  if (e.key !== 'f' || e.metaKey || e.ctrlKey || e.altKey) return;
  const t = e.target;
  if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
  e.preventDefault();
  toggleFullscreen();
});

el.sideHide.addEventListener('click', () => setSideHidden(true));
el.sideShow.addEventListener('click', () => setSideHidden(false));

/* ----------------------------------------------------------------- chat
   Write endpoints need the token and a header that a cross-origin page cannot
   attach without a preflight this server never answers. */

const writeHeaders = { 'x-crew-studio': '1', ...(token ? { authorization: `Bearer ${token}` } : {}) };
const chat = new Chat(el.chat, { api, headers: writeHeaders });

const ownedIds = new Set();

// Switching tabs points the canvas at that session too: the graph and the
// conversation are two views of one thing.
// The conversation's own widen control lives in its header, beside the tabs.
chat.onGrow = () => {
  const cur = parseInt(getComputedStyle(document.documentElement).getPropertyValue('--chat-w'), 10) || PANEL.chat.def;
  setPanel('chat', Math.abs(cur - PANEL.chat.wide) < 24 ? PANEL.chat.def : PANEL.chat.wide);
  canvas.fitIfUntouched();
};

chat.onActivate = (sessionId) => {
  const any = chat.ids.length > 0;
  el.chat.hidden = !any;
  el.chatSplit.hidden = !any; shell.classList.toggle('no-chat', !any);
  // Activating a tab is not a claim of ownership. It used to add the id here,
  // which meant opening a read-only conversation marked that session as one the
  // panel had started — and every later attempt to open it went down the owned
  // path, got a 404, and gave up without saying anything.
  if (sessionId) selectSession(sessionId);
};

/** Bring a session's conversation forward, however the panel can reach it. */
function openConversation(sessionId) {
  if (chat.activeId === sessionId) return;
  if (ownedIds.has(sessionId)) { openOwned(sessionId); return; }
  openReadOnlyPane(sessionId);
}

function openReadOnlyPane(sessionId) {
  const known = findSessionRow(sessionId);
  chat.openReadOnly(sessionId, known ? sessionName(known.session, labels.all()) : null);
  el.chat.hidden = false;
  el.chatSplit.hidden = false;
  shell.classList.remove('no-chat');
}

async function openOwned(sessionId) {
  if (chat.panes.has(sessionId)) { chat.activate(sessionId); return true; }
  try {
    const r = await getJson(`/api/owned/${encodeURIComponent(sessionId)}`);
    if (!r.session) throw new Error('not an owned session');
    chat.open(r.session);
    return true;
  } catch {
    // Reaped, or never ours. Either way the conversation is still readable, and
    // falling through to that beats leaving the panel blank with no reason.
    ownedIds.delete(sessionId);
    openReadOnlyPane(sessionId);
    return false;
  }
}

// Continuing a conversation the panel did not start. It forks rather than
// writing into the original transcript, so a session still open in a terminal
// somewhere is not being written to by two things at once.
el.continueSession.addEventListener('click', async () => {
  const from = current;
  if (!from) return;
  el.continueSession.disabled = true;
  el.continueSession.textContent = 'Continuing…';
  try {
    const r = await chat.start({ cwd: projectsData?.cwd ?? null, permissionMode: 'plan', resume: from });
    if (!r.ok) {
      el.foot.textContent = `could not continue: ${r.reason}`;
    } else {
      ownedIds.add(r.session.sessionId);
      // Two genuinely different outcomes, so say which one happened rather
      // than printing a sentence that is true either way.
      el.foot.textContent = r.session.forked
        ? `${from.slice(0, 8)} is open in another process, so this is a copy — `
          + `messages here do not reach it.`
        : `continued ${from.slice(0, 8)} itself — same session, same transcript.`;
    }
  } finally {
    el.continueSession.disabled = false;
    el.continueSession.textContent = 'Continue here';
  }
});

const newSessionLabel = el.newSession.querySelector('span');
el.newSession.addEventListener('click', async () => {
  const cwd = projectsData?.cwd ?? null;
  el.newSession.disabled = true;
  newSessionLabel.textContent = 'Starting…';
  try {
    // `plan` by default: a panel that can start a session must not also be the
    // reason one got write access nobody asked for.
    const r = await chat.start({ cwd, permissionMode: 'plan' });
    if (!r.ok) el.foot.textContent = `could not start a session: ${r.reason}`;
    else ownedIds.add(r.session.sessionId);
  } finally {
    el.newSession.disabled = false;
    newSessionLabel.textContent = 'New session';
  }
});

/* --------------------------------------------------------------- canvas */

const canvas = new Canvas(document.getElementById('canvas'), { onSelect: showInspector });

getJson('/api/palette')
  .then((p) => {
    canvas.setPalette(p);
    // Twelve unrecognised agents and zero agents read as the same grey. Which
    // one it is has to be said out loud, or the panel is drawing "not measured"
    // as a fact about the agents.
    if (p && p.measured === false) {
      document.body.dataset.paletteMeasured = 'false';
      el.foot.textContent = `agent colours Not measured — ${p.reason}`;
    }
  })
  .catch(() => { /* neutral colours; the canvas already defaults safely */ });

let inspectorTab = 'report';
let inspectorNode = null;
let detailCache = new Map();

function showInspector(node) {
  inspectorNode = node;
  // The session node IS the conversation. Clicking it opened a details panel
  // and nothing else, which asked the reader to go and find the talking
  // elsewhere.
  if (node?.kind === 'session' && current) openConversation(current);
  if (!node) { el.inspector.hidden = true; el.inspector.classList.remove('wide'); return; }
  el.inspector.hidden = false;
  inspectorTab = node.kind === 'session' ? 'meta' : 'report';
  paintInspector();
  if (node.kind === 'agent') loadDetail(node.id, node.status);
  if (node.kind === 'session' && current) loadKit(current);
}

// Keyed by status as well as id: a report fetched while the agent was still
// running says "no report yet", and that answer must not outlive the run.
// Failures are not cached at all — a network blip should not permanently hide
// a report behind a stale error.
async function loadDetail(agentId, status) {
  const key = `${agentId}:${status ?? '?'}`;
  if (detailCache.has(key)) return;
  detailCache.set(key, { loading: true });
  paintInspector();
  try {
    const d = await getJson(`/api/session/${encodeURIComponent(current)}/agent/${encodeURIComponent(agentId)}`);
    detailCache.set(key, d);
  } catch (e) {
    detailCache.delete(key);
    detailCache.set(key, { measured: false, reason: e.message, transient: true });
  }
  if (inspectorNode?.id === agentId) paintInspector();
}

function metaRows(n) {
  const rows = [];
  const row = (k, v) => { if (v != null && v !== '') rows.push([k, String(v)]); };
  if (n.kind === 'session') {
    row('session', n.sessionId); row('cwd', n.cwd); row('branch', n.gitBranch);
    row('model', n.model); row('turns', n.turns);
    row('context', n.tokens?.toLocaleString()); row('cli', n.version);
  } else {
    row('type', n.agentType ?? 'unknown'); row('status', n.status);
    row('depth', n.spawnDepth); row('model', n.model);
    row('turns', n.turns); row('tool calls', n.toolCount); row('last tool', n.lastTool);
    row('tokens', n.tokens?.toLocaleString());
    row('duration', n.durationMs != null ? fmtDur(n.durationMs) : null);
    row('errors', n.errors || null);
    row('agent id', n.id);
  }
  const dl = document.createElement('dl');
  for (const [k, v] of rows) {
    const dt = document.createElement('dt'); dt.textContent = k;
    const dd = document.createElement('dd'); dd.textContent = v;
    dl.append(dt, dd);
  }
  return dl;
}

function fmtDur(ms) {
  const sec = Math.round(ms / 1000);
  return sec < 60 ? `${sec}s` : `${Math.floor(sec / 60)}m ${sec % 60}s`;
}

function paintInspector() {
  const n = inspectorNode;
  if (!n) return;
  const detail = n.kind === 'agent' ? detailCache.get(`${n.id}:${n.status ?? '?'}`) : null;

  const head = document.createElement('div');
  head.className = 'ihead';
  const h3 = document.createElement('h3');
  h3.textContent = n.kind === 'session' ? 'Session' : (n.agentType ?? 'Agent');
  const chip = node('span', 'cv-chip', n.kind === 'session' ? `${n.turns ?? 0} turns` : (n.status ?? '?'));
  chip.dataset.status = n.status ?? 'unknown';
  const wide = node('button', 'ghost iwide', el.inspector.classList.contains('wide') ? '›' : '‹');
  wide.title = 'Widen';
  wide.addEventListener('click', () => { el.inspector.classList.toggle('wide'); paintInspector(); });
  // The inspector floats over the graph, so it needs a way out that is not
  // "click the node again and hope you hit it".
  const close = node('button', 'ghost iwide', '×');
  close.title = 'Close';
  close.addEventListener('click', () => { canvas.clearSelection(); showInspector(null); });
  head.append(h3, chip, wide, close);

  const sub = node('div', 'isub', n.description ?? n.cwd ?? '');

  const tabs = document.createElement('div');
  tabs.className = 'itabs';
  const available = n.kind === 'session'
    ? ['meta', 'gates', 'stats', 'board']
    : ['report', 'activity', 'prompt', 'meta'];
  for (const t of available) {
    const b = node('button', `itab${inspectorTab === t ? ' on' : ''}`, t);
    b.addEventListener('click', () => { inspectorTab = t; paintInspector(); });
    tabs.append(b);
  }

  const body = document.createElement('div');
  body.className = 'ibody';

  if (['gates', 'stats', 'board'].includes(inspectorTab)) {
    paintKit(body, inspectorTab);
  } else if (inspectorTab === 'meta') {
    body.append(metaRows(n));
    const tools = Object.entries(n.tools ?? {});
    if (tools.length) {
      const wrap = node('div', 'tools');
      for (const [name, c] of tools.sort((a, b) => b[1] - a[1])) wrap.append(node('span', 'cv-bit', `${name} ×${c}`));
      body.append(wrap);
    }
  } else if (!detail) {
    body.append(node('div', 'ihint', 'Loading…'));
  } else if (detail.loading) {
    body.append(node('div', 'ihint', 'Reading the agent transcript…'));
  } else if (detail.measured === false) {
    const hint = node('div', 'ihint', `Not measured — ${detail.reason}`);
    if (detail.transient) {
      const retry = node('button', 'ghost', 'retry');
      retry.addEventListener('click', () => {
        detailCache.delete(`${n.id}:${n.status ?? '?'}`);
        loadDetail(n.id, n.status);
      });
      hint.append(' ', retry);
    }
    body.append(hint);
  } else if (inspectorTab === 'report') {
    if (detail.report) {
      const bar = node('div', 'ibar');
      bar.append(node('span', 'meta', `${detail.report.length.toLocaleString()} chars`));
      const copy = node('button', 'ghost', 'copy');
      copy.addEventListener('click', async () => {
        try { await navigator.clipboard.writeText(detail.report); copy.textContent = 'copied'; }
        catch { copy.textContent = 'blocked'; }
        setTimeout(() => { copy.textContent = 'copy'; }, 1400);
      });
      bar.append(copy);
      const md = node('div', 'md');
      md.innerHTML = renderMarkdown(detail.report);
      body.append(bar, md);
    } else {
      // An agent still working has narration but no conclusion. Showing the
      // narration as a report would be inventing a result it never gave.
      body.append(node('div', 'ihint',
        n.status === 'running'
          ? 'Still working — no report yet. What it has said so far is under Activity.'
          : 'This agent produced no closing report.'));
    }
  } else if (inspectorTab === 'activity') {
    const list = node('div', 'itimeline');
    if (!detail.timeline?.length) list.append(node('div', 'ihint', 'No tool calls recorded.'));
    for (const [i, step] of (detail.timeline ?? []).entries()) {
      const r = node('div', 'istep');
      r.append(node('span', 'istep-n', String(i + 1)));
      r.append(node('span', 'istep-tool', step.name));
      r.append(node('span', 'istep-label', step.label ?? ''));
      list.append(r);
    }
    if (detail.narration?.length) {
      list.append(node('div', 'ihint', `${detail.narration.length} progress note(s)`));
      for (const t of detail.narration) {
        const md = node('div', 'md md-narration');
        md.innerHTML = renderMarkdown(t);
        list.append(md);
      }
    }
    body.append(list);
  } else if (inspectorTab === 'prompt') {
    const md = node('div', 'md');
    md.innerHTML = renderMarkdown(detail.prompt ?? '');
    body.append(detail.prompt ? md : node('div', 'ihint', 'No prompt recorded.'));
  }

  el.inspector.replaceChildren(head, sub, tabs, body);
}

/* ------------------------------------------------------------------ kit
   What Crewforth already measures about itself. Nothing here is recomputed —
   each panel shows what Crewforth's own tool said, including when it said it
   could not answer. */

let kitData = null;
let kitFor = null;

async function loadKit(sessionId) {
  if (kitFor === sessionId && kitData) return;
  kitFor = sessionId;
  kitData = null;
  try {
    kitData = await getJson(`/api/kit?session=${encodeURIComponent(sessionId)}`);
  } catch (e) {
    kitData = { measured: false, reason: e.message };
  }
  if (inspectorNode?.kind === 'session') paintInspector();
}

function unmeasured(reason) {
  const d = node('div', 'ihint');
  d.append(node('strong', null, 'Not measured'));
  d.append(node('div', null, reason || 'no reason given'));
  d.append(node('div', 'why', 'Which is not the same as nothing having happened.'));
  return d;
}

function paintKit(body, tab) {
  if (!kitData) { body.append(node('div', 'ihint', 'Reading Crewforth…')); return; }

  if (tab === 'stats') {
    const s = kitData.stats;
    if (!s?.measured) { body.append(unmeasured(s?.reason)); return; }
    const dl = document.createElement('dl');
    for (const [k, v] of Object.entries(s.metrics)) {
      const dt = node('dt', null, k.replace(/_/g, ' '));
      const dd = node('dd', null, v.toLocaleString());
      if (v > 0 && /runaway|errors|interrupts/.test(k)) dd.classList.add('bad');
      dl.append(dt, dd);
    }
    body.append(dl);
    body.append(node('div', 'ihint', 'session-stats.sh --raw, over this transcript.'));
    return;
  }

  if (tab === 'board') {
    const b = kitData.board;
    if (!b?.measured) { body.append(unmeasured(b?.reason)); return; }
    if (!b.present) {
      body.append(node('div', 'ihint', b.text));
      return;
    }
    body.append(node('pre', 'md-code', b.text));
    return;
  }

  // gates
  const log = kitData.log;
  const rep = kitData.report;

  if (rep?.measured) {
    const head = node('div', 'kit-sum');
    head.append(node('span', 'cv-bit', `${rep.rules} rules`));
    head.append(node('span', 'cv-bit', `${(rep.decisions ?? 0).toLocaleString()} decisions`));
    body.append(head);
  } else {
    body.append(unmeasured(rep?.reason));
  }

  // Owned sessions carry the moment each gate ran; the log does not.
  const owned = chat.panes.get(current);
  const live = owned?.session?.gateEvents ?? [];
  if (live.length) {
    body.append(node('h4', 'md-h', 'Happened'));
    for (const e of live.slice(-12).reverse()) {
      const row = node('div', 'gate-row');
      row.append(node('span', 'gate-when', new Date(e.at).toLocaleTimeString()));
      row.append(node('span', 'gate-name', e.name ?? e.event ?? 'hook'));
      const v = node('span', 'gate-verdict', e.phase === 'started' ? 'ran' : (e.exitCode === 2 ? 'blocked' : e.outcome ?? 'done'));
      v.dataset.verdict = e.exitCode === 2 ? 'BLOCK' : 'ALLOW';
      row.append(v);
      body.append(row);
    }
  }

  if (!log?.measured) { body.append(unmeasured(log?.reason)); return; }

  const h = node('h4', 'md-h', 'Observed');
  body.append(h);
  // The distinction is the point: this file has no timestamp column, so these
  // are decisions found in the log, not decisions seen happening.
  body.append(node('div', 'ihint',
    `${log.total.toLocaleString()} in the tail of gate-log.tsv${log.truncated ? ' (truncated)' : ''} · `
    + 'no timestamps in this format, so these are what the log holds, not when they ran'
    + (log.commandsRecorded ? '' : ' · commands not recorded (CREW_GATE_LOG_CMD=1 records them)')));

  const counts = node('div', 'kit-sum');
  for (const [k, v] of Object.entries(log.counts ?? {})) {
    const b = node('span', 'cv-bit', `${v.toLocaleString()} ${k}`);
    b.dataset.verdict = k;
    counts.append(b);
  }
  body.append(counts);

  for (const e of (log.entries ?? []).slice(0, 40)) {
    const row = node('div', 'gate-row');
    const v = node('span', 'gate-verdict', e.verdict);
    v.dataset.verdict = e.verdict;
    row.append(v);
    row.append(node('span', 'gate-name', e.rule ?? '—'));
    if (e.section) row.append(node('span', 'gate-sec', e.section));
    body.append(row);
  }
}

/* ------------------------------------------------------------ navigator
   One search box, three tabs. Projects is everything on this machine; Live is
   what is working or waiting right now, whichever project it is in; Machines
   is what is known about the others. The words and the rules are in nav.js —
   this is where they are drawn. */

function node(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
}

function renderNote(host, { kind, title, body, why }) {
  const wrap = node('div', `note${kind ? ` ${kind}` : ''}`);
  wrap.append(node('strong', null, title));
  if (body) wrap.append(node('div', null, body));
  if (why) wrap.append(node('div', 'why', why));
  host.replaceChildren(wrap);
}

function shortPath(p, max = 34) {
  if (!p) return '';
  const home = p.match(/^\/(Users|home)\/[^/]+/);
  const s = home ? `~${p.slice(home[0].length)}` : p;
  if (s.length <= max) return s;
  const keep = Math.floor((max - 1) / 2);
  return `${s.slice(0, keep)}…${s.slice(-keep)}`;
}

const SVG_NS = 'http://www.w3.org/2000/svg';
function icon(d) {
  const svg = document.createElementNS(SVG_NS, 'svg');
  svg.setAttribute('class', 'ic');
  svg.setAttribute('viewBox', '0 0 16 16');
  svg.setAttribute('aria-hidden', 'true');
  const path = document.createElementNS(SVG_NS, 'path');
  path.setAttribute('d', d);
  svg.append(path);
  return svg;
}
const ICON = {
  chevron: 'M6 4l4 4-4 4',
  more: 'M3.5 8h.01M8 8h.01M12.5 8h.01',
  machine: 'M3.5 3h9A1.5 1.5 0 0 1 14 4.5v5a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 9.5v-5A1.5 1.5 0 0 1 3.5 3zM6 14h4M8 11v3',
};

/** A status dot. No tone is the hollow ring: something over, or something nobody has a colour for. */
function dot(tone) {
  const d = node('span', 'dot');
  d.dataset.tone = tone ?? 'none';
  return d;
}

/** `text` with the part that matches the search marked. */
function marked(text, cls) {
  const span = node('span', cls);
  for (const part of highlight(text, filterText)) {
    span.append(part.hit ? node('mark', null, part.text) : document.createTextNode(part.text));
  }
  return span;
}

/* A short line that says something happened and goes away. Not a dialog: it
   takes no focus and needs no answer. */
let toastTimer = null;
function toast(text) {
  el.toast.textContent = text;
  el.toast.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.toast.hidden = true; }, 3200);
}

async function copyText(text, said) {
  try {
    await navigator.clipboard.writeText(text);
    toast(said);
  } catch {
    // A page without clipboard access still has to hand the text over.
    toast(`Could not copy — ${text}`);
  }
}

/* What the viewer changed about the list, kept in this browser. A label is a
   name for a row here; the transcript is not touched. */
function stored(key, fallback) {
  try { return JSON.parse(store.get(key) ?? 'null') ?? fallback; } catch { return fallback; }
}
const labels = {
  map: stored('crewforth-studio-labels', {}),
  all() { return this.map; },
  set(id, text) {
    if (text) this.map[id] = text; else delete this.map[id];
    store.set('crewforth-studio-labels', JSON.stringify(this.map));
  },
};
const hiddenIds = new Set(stored('crewforth-studio-hidden', []));
function setHidden(id, hidden) {
  if (hidden) hiddenIds.add(id); else hiddenIds.delete(id);
  store.set('crewforth-studio-hidden', JSON.stringify([...hiddenIds]));
}

/* ----------------------------------------------------------------- tabs */

const TABS = { projects: el.sessions, live: el.fleet, machines: el.reach };
let navTab = 'projects';

function setTab(tab) {
  navTab = tab in TABS ? tab : 'projects';
  for (const [name, panel] of Object.entries(TABS)) panel.hidden = name !== navTab;
  for (const b of document.querySelectorAll('[data-tab]')) {
    b.setAttribute('aria-selected', String(b.dataset.tab === navTab));
  }
  for (const b of document.querySelectorAll('[data-rail-tab]')) {
    b.classList.toggle('on', b.dataset.railTab === navTab);
  }
  // The short list of other machines belongs under the projects; on its own
  // tab it would be saying the same thing twice.
  paintOtherMachines();
  store.set('crewforth-studio-nav-tab', navTab);
}

for (const b of document.querySelectorAll('[data-tab]')) b.addEventListener('click', () => setTab(b.dataset.tab));
// On the rail a tab is also the way back in: it opens the navigator on that tab.
for (const b of document.querySelectorAll('[data-rail-tab]')) {
  b.addEventListener('click', () => { setTab(b.dataset.railTab); setSideHidden(false); });
}

/* ----------------------------------------------------------------- menu
   The few things a session row can do besides being opened. A menu, not a
   dialog: it closes on the next click anywhere and on Esc. */

function closeMenu() { el.menu.hidden = true; el.menu.replaceChildren(); }

function openMenu(anchor, items) {
  el.menu.replaceChildren(...items.map((it) => {
    if (it.note) return node('div', 'menu-note', it.note);
    const b = node('button', `menu-item${it.primary ? ' primary' : ''}`);
    b.type = 'button';
    if ('tone' in it) b.append(dot(it.tone));
    b.append(document.createTextNode(it.label));
    if (it.checked !== undefined) {
      b.setAttribute('role', 'menuitemcheckbox');
      b.setAttribute('aria-checked', String(it.checked));
    } else {
      b.setAttribute('role', 'menuitem');
    }
    b.addEventListener('click', (e) => { e.stopPropagation(); closeMenu(); it.run(); });
    return b;
  }));
  const r = anchor.getBoundingClientRect();
  el.menu.hidden = false;
  el.menu.style.left = `${Math.max(8, Math.min(r.left, window.innerWidth - 280))}px`;
  el.menu.style.top = `${Math.min(r.bottom + 4, window.innerHeight - 8 - el.menu.offsetHeight)}px`;
  el.menu.querySelector('button')?.focus();
}

document.addEventListener('click', (e) => { if (!el.menu.hidden && !el.menu.contains(e.target)) closeMenu(); });

/** Hand a session to a real terminal. The command is shown first and runs only on the second click. */
async function offerTerminal(anchor, sessionId) {
  let plan = null;
  try {
    plan = (await getJson(`/api/session/${encodeURIComponent(sessionId)}/terminal`)).plan;
  } catch (e) {
    toast(`Could not read the terminal command — ${e.message}`);
    return;
  }
  if (!plan) { toast('Not measured — this session recorded no working directory to open a terminal in.'); return; }
  openMenu(anchor, [
    { note: `This will run in ${plan.via ?? 'a terminal'}:` },
    { note: plan.line },
    {
      label: 'Open terminal',
      primary: true,
      run: async () => {
        try {
          const r = await fetch(api(`/api/session/${encodeURIComponent(sessionId)}/terminal`), {
            method: 'POST', headers: { ...writeHeaders, 'content-type': 'application/json' }, body: '{}',
          });
          const out = await r.json();
          toast(out.ok ? `Opened in ${plan.via ?? 'a terminal'}` : `Could not open a terminal — ${out.reason ?? 'no reason given'}`);
        } catch (e) {
          toast(`Could not open a terminal — ${e.message}`);
        }
      },
    },
    { label: 'Cancel', run: () => {} },
  ]);
}

/* ------------------------------------------------------------- projects */

let projectsData = null;
let fleetData = null;
let expanded = new Set();
let filterText = '';
let showMissing = false;
let showHidden = false;
let renaming = null;          // the session whose name is being typed

el.filter.addEventListener('input', () => {
  filterText = el.filter.value.trim().toLowerCase();
  paintProjects();
  paintLive();
});

function findSessionRow(sessionId) {
  for (const project of projectsData?.projects ?? []) {
    const session = project.sessions.find((x) => x.sessionId === sessionId);
    if (session) return { project, session };
  }
  return null;
}

function renderSessions(data) {
  if (!data.measured) {
    renderNote(el.sessions, {
      kind: 'unmeasured',
      title: 'No transcripts here',
      body: 'Nothing was read.',
      why: data.reason,
    });
    return;
  }
  projectsData = data;
  // The project you are standing in starts open; the rest stay folded, or a
  // machine with 175 projects buries the one you are working in.
  if (!expanded.size) {
    const cur = data.projects.find((p) => p.current) ?? data.projects[0];
    if (cur) expanded.add(cur.key);
  }
  paintProjects();
  paintCrumb();
}

function versionBadge(kit) {
  const b = badgeFor(kit);
  const tag = node(b.copy ? 'button' : 'span', `badge badge-${b.tone}`, b.text);
  tag.title = b.title;
  if (b.copy) {
    tag.type = 'button';
    tag.addEventListener('click', (e) => { e.stopPropagation(); copyText(b.copy, `Copied: ${b.copy}`); });
  }
  return tag;
}

function sessionRow(project, sn) {
  const status = sessionStatus(sn.sessionId, fleetData);
  const name = sessionName(sn, labels.all());
  const row = node('div', 'srow');
  row.dataset.id = sn.sessionId;
  row.tabIndex = 0;
  row.setAttribute('role', 'treeitem');
  row.setAttribute('aria-current', String(sn.sessionId === current));
  if (ownedIds.has(sn.sessionId)) row.classList.add('owned');

  const top = node('span', 'srow-top');
  const d = dot(status.tone);
  // The word travels with the colour; where there is no status to give, say why.
  d.title = status.key === 'unmeasured' ? 'Status not measured — the session list could not be read' : (status.word ?? '');
  top.append(d);

  if (renaming === sn.sessionId) {
    const input = node('input', 'srow-rename');
    input.value = name;
    input.setAttribute('aria-label', `Rename ${name}`);
    const done = (save) => {
      if (renaming !== sn.sessionId) return;
      renaming = null;
      if (save) labels.set(sn.sessionId, input.value.trim() === (sn.title ?? '') ? '' : input.value.trim());
      paintProjects();
      paintCrumb();
    };
    input.addEventListener('click', (e) => e.stopPropagation());
    input.addEventListener('keydown', (e) => {
      e.stopPropagation();
      if (e.key === 'Enter') done(true);
      if (e.key === 'Escape') done(false);
    });
    input.addEventListener('blur', () => done(true));
    top.append(input);
    queueMicrotask(() => { input.focus(); input.select(); });
  } else {
    top.append(marked(name, 'nm'));
  }
  top.append(node('span', 'row-fill'));
  top.append(node('span', 'sub', ago(sn.modifiedAt, Date.now())));

  const more = node('button', 'row-more');
  more.type = 'button';
  more.setAttribute('aria-label', `More for ${name}`);
  more.setAttribute('aria-haspopup', 'menu');
  more.append(icon(ICON.more));
  more.addEventListener('click', (e) => {
    e.stopPropagation();
    openMenu(more, [
      { label: 'Rename', run: () => { renaming = sn.sessionId; paintProjects(); } },
      { label: 'Copy session id', run: () => copyText(sn.sessionId, 'Copied the session id') },
      { label: 'Open in terminal', run: () => offerTerminal(more, sn.sessionId) },
      hiddenIds.has(sn.sessionId)
        ? { label: 'Show in list', run: () => { setHidden(sn.sessionId, false); paintProjects(); } }
        : { label: 'Hide from list', run: () => { setHidden(sn.sessionId, true); paintProjects(); } },
    ]);
  });
  top.append(more);
  row.append(top);
  // The same menu from a right click, where a menu for a row is expected to be.
  row.addEventListener('contextmenu', (e) => { e.preventDefault(); more.click(); });

  const subText = sessionSub(sn, status) + (ownedIds.has(sn.sessionId) ? ' · started here' : '');
  if (subText) row.append(marked(subText, 'sub srow-sub'));

  row.title = `${sn.sessionId}${sn.title ? `\n${sn.title}` : ''}`;
  const open = () => selectSession(sn.sessionId);
  row.addEventListener('click', open);
  row.addEventListener('keydown', (e) => {
    if (e.target !== row) return;
    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open(); }
  });
  return row;
}

function paintProjects() {
  const data = projectsData;
  if (!data || renaming && document.activeElement?.classList?.contains('srow-rename')) return;

  // Typing a search is an explicit request, so it looks everywhere — including
  // the projects whose directories are gone. Hiding a result someone asked for
  // by name is worse than showing a dead path.
  const pool = (showMissing || filterText) ? data.projects : data.projects.filter((p) => p.exists);
  const missing = data.projects.length - pool.length;

  const frag = document.createDocumentFragment();
  let shown = 0;
  let hiddenCount = 0;

  for (const p of pool) {
    const projectHit = filterText && p.label.toLowerCase().includes(filterText);
    const sessions = p.sessions.filter((sn) => {
      if (hiddenIds.has(sn.sessionId) && !showHidden) { hiddenCount += 1; return false; }
      return !filterText || projectHit || matchesSession(filterText, p, sn, labels.all());
    });
    if (filterText && !projectHit && !sessions.length) continue;
    shown += 1;

    const open = expanded.has(p.key) || Boolean(filterText);
    const group = node('div', 'proj');
    const head = node('div', `proj-head${p.current ? ' current' : ''}${p.exists ? '' : ' gone'}`);
    head.tabIndex = 0;
    head.setAttribute('role', 'treeitem');
    head.setAttribute('aria-expanded', String(open));
    head.dataset.project = p.key;
    const caret = icon(ICON.chevron);
    caret.classList.add('proj-caret');
    head.append(caret, marked(p.label, 'proj-name'));
    // Where a project lives is part of its identity once more than one machine
    // is in view.
    if (p.origin && p.local === false) head.append(node('span', 'origin', p.origin));
    head.append(node('span', 'row-fill'), versionBadge(p.kit));
    head.title = (p.cwd ?? p.dir) + (p.exists ? '' : ' — directory no longer exists');
    const toggle = () => {
      if (expanded.has(p.key)) expanded.delete(p.key); else expanded.add(p.key);
      paintProjects();
    };
    head.addEventListener('click', toggle);
    head.addEventListener('keydown', (e) => {
      if (e.target !== head) return;
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggle(); }
    });
    group.append(head);

    if (open) {
      for (const sn of sessions) group.append(sessionRow(p, sn));
      if (p.total > p.sessions.length) {
        group.append(node('div', 'nav-line', `${p.total - p.sessions.length} older session(s) not listed`));
      }
    }
    frag.append(group);
  }

  if (!shown) {
    renderNote(el.sessions, filterText
      ? { title: 'No match', body: `Nothing here is called “${filterText}”.` }
      : { title: 'No projects', body: 'Measured — no transcript was found on this machine.' });
    return;
  }

  for (const o of (data.origins ?? []).filter((x) => x.ok === false)) {
    frag.append(node('div', 'nav-line bad', `${o.name} unreachable — ${o.reason}`));
  }
  const lineWith = (text, label, run) => {
    const line = node('div', 'nav-line');
    line.append(node('span', null, text));
    const b = node('button', 'link', label);
    b.type = 'button';
    b.addEventListener('click', run);
    line.append(b);
    return line;
  };
  if (hiddenIds.size && !filterText) {
    frag.append(lineWith(
      showHidden ? `${hiddenIds.size} hidden session(s) shown` : `${hiddenCount} session(s) hidden from this list`,
      showHidden ? 'hide' : 'show',
      () => { showHidden = !showHidden; paintProjects(); },
    ));
  }
  if (missing > 0 && !filterText) {
    frag.append(lineWith(
      `${missing} project(s) hidden — their directories no longer exist`, 'show',
      () => { showMissing = true; paintProjects(); },
    ));
  } else if (showMissing && !filterText) {
    frag.append(lineWith('Showing projects whose directories no longer exist', 'hide',
      () => { showMissing = false; paintProjects(); }));
  }
  el.sessions.replaceChildren(frag);

  if (!current) {
    const cur = data.projects.find((x) => x.current) ?? data.projects[0];
    const best = cur?.sessions.find((x) => x.agentCount > 0) ?? cur?.sessions[0];
    if (best) selectSession(best.sessionId);
  }
}

/* ------------------------------------------------------- live and machines */

function renderFleet(data) {
  fleetData = data;
  paintLive();
  paintMachines();
  // A session's dot comes from this answer, so the project list follows it.
  paintProjects();
}

function paintLive() {
  const data = fleetData;
  if (!data) return;

  if (!data.measured) {
    el.liveCount.hidden = false;
    el.liveCount.textContent = '?';
    el.liveCount.title = 'Not measured';
    renderNote(el.fleet, {
      kind: 'unmeasured',
      title: 'Not measured',
      body: 'This is not the same as "nothing is running" — nothing was read.',
      why: data.reason || 'no reason reported',
    });
    return;
  }

  const live = liveSessions(data);
  el.liveCount.hidden = live.length === 0;
  el.liveCount.textContent = String(live.length);
  el.liveCount.title = `${live.length} working or waiting`;

  const rows = live.filter((s) => !filterText
    || [s.name, s.cwd, s.sessionId, s.origin].some((v) => typeof v === 'string' && v.toLowerCase().includes(filterText)));

  if (!live.length) {
    const open = (data.sessions ?? []).length;
    renderNote(el.fleet, {
      title: 'No sessions running',
      body: open
        ? `Measured — ${open} open on this machine, none of them working or waiting.`
        : 'Measured — the machine has none open.',
    });
    return;
  }
  if (!rows.length) {
    renderNote(el.fleet, { title: 'No match', body: `No live session is called “${filterText}”.` });
    return;
  }

  el.fleet.replaceChildren(...rows.map((s) => {
    const status = sessionStatus(s.sessionId, { measured: true, sessions: [{ ...s, local: true }] });
    const known = findSessionRow(s.sessionId);
    const name = known ? sessionName(known.session, labels.all()) : (s.name || s.sessionId.slice(0, 8));
    const row = node('div', 'srow');
    const top = node('span', 'srow-top');
    top.append(dot(status.tone), marked(name, 'nm'));
    if (s.origin && s.local === false) top.append(node('span', 'origin', s.origin));
    top.append(node('span', 'row-fill'), node('span', 'sub', ago(s.startedAt, Date.now())));
    row.append(top);
    const where = known?.project.label ?? shortPath(s.cwd);
    const said = status.key === 'waiting' && s.waitingFor ? `Needs you · ${s.waitingFor}` : (status.word ?? s.status);
    row.append(marked([where, said].filter(Boolean).join(' · '), 'sub srow-sub'));

    if (s.local !== false && s.sessionId) {
      row.tabIndex = 0;
      row.dataset.id = s.sessionId;
      row.setAttribute('aria-current', String(s.sessionId === current));
      row.title = `Open ${name}`;
      const open = () => selectSession(s.sessionId);
      row.addEventListener('click', open);
      row.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open(); } });
    } else {
      // A session on another machine has no transcript here to open.
      row.classList.add('remote');
      row.title = `${name} — on ${s.origin}. Its transcript is on that machine.`;
    }
    return row;
  }));
}

function machineRow(m) {
  const row = node('div', 'srow remote');
  const top = node('span', 'srow-top');
  top.append(icon(ICON.machine), node('span', 'mname', m.name), node('span', 'row-fill'));
  if (m.kind === 'snapshot') {
    // Recorded by a session, not asked just now: the label says which.
    top.append(node('span', 'badge', 'snapshot'));
    row.append(top);
    const seen = seenAgo(m.seenAt, Date.now());
    row.append(node('div', 'sub srow-sub', [m.status, m.note, seen].filter(Boolean).join(' · ')));
    row.title = `${m.name} — on another machine. Its transcript lives there, so the panel can list it but not draw it.`;
  } else {
    top.append(node('span', 'badge', 'peer'));
    row.append(top);
    const sub = node('div', `sub srow-sub${m.ok ? '' : ' bad'}`,
      m.ok ? `${m.sessions ?? 0} session(s) · asked just now` : `unreachable — ${m.reason ?? 'no reason given'}`);
    row.append(sub);
  }
  return row;
}

function paintMachines() {
  const m = machines(fleetData);
  const self = (fleetData?.origins ?? []).find((o) => o.local);
  const frag = document.createDocumentFragment();

  if (self) {
    const row = node('div', 'srow remote');
    const top = node('span', 'srow-top');
    top.append(icon(ICON.machine), node('span', 'mname', self.name), node('span', 'row-fill'), node('span', 'badge', 'this machine'));
    row.append(top);
    frag.append(row);
  }
  for (const p of m.peers) frag.append(machineRow(p));
  for (const r of m.remote) frag.append(machineRow(r));

  if (!m.remote.length) {
    // A roster nobody has recorded is not "no other machines". Say which it is.
    const note = node('div', 'nav-note');
    renderNote(note, {
      kind: m.rosterMeasured ? '' : 'unmeasured',
      title: m.rosterMeasured ? 'None reachable' : 'Not measured',
      body: m.rosterMeasured
        ? 'A connected session looked and found no machines besides this one.'
        : 'No session here has recorded a list of other machines yet.',
      why: m.rosterMeasured ? null : m.rosterReason,
    });
    frag.append(note);
  }
  el.reach.replaceChildren(frag);
  paintOtherMachines();
}

/** The short form under the project list: the first two, and the way to the rest. */
function paintOtherMachines() {
  const m = machines(fleetData);
  const others = [...m.peers, ...m.remote];
  el.otherMachines.hidden = navTab !== 'projects' || others.length === 0;
  if (el.otherMachines.hidden) return;
  const label = node('button', 'nav-foot-label', 'Other machines');
  label.type = 'button';
  label.addEventListener('click', () => setTab('machines'));
  const rows = others.slice(0, 2).map(machineRow);
  const more = others.length > 2 ? [node('div', 'nav-line', `${others.length - 2} more in Machines`)] : [];
  el.otherMachines.replaceChildren(label, ...rows, ...more);
}

/* ------------------------------------------------------------- sessions */

let current = null;
let source = null;
let statusFilter = null;
let lastStats = null;

/** The breadcrumb: which project, which session. The project is the way back to its list. */
function paintCrumb() {
  const found = current ? findSessionRow(current) : null;
  if (!found) { el.crumb.replaceChildren(); return; }
  const proj = node('button', 'crumb-project', found.project.label);
  proj.type = 'button';
  proj.title = `Show ${found.project.label} in the navigator`;
  proj.addEventListener('click', () => showProject(found.project.key));
  const sep = icon(ICON.chevron);
  sep.classList.add('crumb-sep');
  const name = node('span', 'crumb-session', sessionName(found.session, labels.all()));
  // The branch is on the session's row and on its card; here it is one hover away.
  name.title = found.session.branch ? `on ${found.session.branch}` : '';
  el.crumb.replaceChildren(proj, sep, name);
  fitBar();
}

function showProject(key) {
  el.filter.value = '';
  filterText = '';
  expanded.add(key);
  setTab('projects');
  setSideHidden(false);
  paintProjects();
  el.sessions.querySelector(`[data-project="${CSS.escape(key)}"]`)?.scrollIntoView({ block: 'nearest' });
}

/** The summary: one chip per status, each a filter on the canvas. Clicking the lit one puts everything back. */
function paintSummary(stats, extra = []) {
  lastStats = stats;
  const chips = summaryChips(stats?.byStatus);
  // A filter on a status nothing has any more would hide every agent with no chip left to undo it.
  if (statusFilter && !chips.some((c) => c.status === statusFilter)) setStatusFilter(null, false);
  const toggle = (c) => setStatusFilter(statusFilter === c.status ? null : c.status);
  const full = chips.map((c) => {
    const b = node('button', 'pill chip');
    b.type = 'button';
    b.setAttribute('aria-pressed', String(statusFilter === c.status));
    b.title = statusFilter === c.status ? 'Show every agent' : `Show only ${c.text.replace(/^\d+ /, '')}`;
    b.append(dot(c.tone), document.createTextNode(c.text));
    b.addEventListener('click', () => toggle(c));
    return b;
  });

  // The same chips as one: dots and counts, for a bar too narrow to spell them
  // out. The words are in its label and in the menu it opens, where each line
  // is the same filter the full chip is.
  const compact = [];
  if (chips.length) {
    const words = [...chips.map((c) => c.text), ...extra].join(', ');
    const b = node('button', 'pill chip chip-compact');
    b.type = 'button';
    b.setAttribute('aria-label', `Session summary: ${words}. Open details`);
    b.setAttribute('aria-haspopup', 'menu');
    b.setAttribute('aria-pressed', String(Boolean(statusFilter)));
    b.title = words;
    for (const c of chips) b.append(dot(c.tone), document.createTextNode(String(c.count)));
    b.append(icon('M4 6l4 4 4-4'));
    b.addEventListener('click', (e) => {
      e.stopPropagation();
      openMenu(b, [
        ...chips.map((c) => ({ label: c.text, tone: c.tone, checked: statusFilter === c.status, run: () => toggle(c) })),
        ...extra.map((t) => ({ note: t })),
      ]);
    });
    compact.push(b);
  }
  el.summary.replaceChildren(...full, ...extra.map((t) => node('span', 'pill note-pill', t)), ...compact);
  fitBar();
}

/** Spell the summary out while it fits; fold it into one chip the moment the bar would overflow. Measured, not
 *  guessed from the window's width: how much room the chips need depends on how many statuses are in play. */
function fitBar() {
  delete el.bar.dataset.compact;
  if (el.bar.scrollWidth > el.bar.clientWidth) el.bar.dataset.compact = 'true';
}
window.addEventListener('resize', fitBar);

function setStatusFilter(status, repaint = true) {
  statusFilter = status;
  canvas.setFilter(status);
  if (repaint) paintSummary(lastStats, lastStats?.malformed ? [`${lastStats.malformed} malformed`] : []);
}

// Selecting a session points the graph at it. It does NOT open the
// conversation: the navigator is for choosing what to look at, and having a
// reading panel appear on every click there made choosing expensive. The
// conversation is opened from the session node on the canvas, which is the
// thing that represents it.
function selectSession(sessionId) {
  if (current === sessionId) return;
  current = sessionId;
  canvas.setSession(sessionId);
  statusFilter = null;
  canvas.setFilter(null);
  showInspector(null);

  // The session being looked at is never inside a folded project: the row that
  // says "you are here" has to be on screen.
  const home = findSessionRow(sessionId);
  if (home && !expanded.has(home.project.key)) { expanded.add(home.project.key); paintProjects(); }
  for (const r of document.querySelectorAll('.srow[data-id]')) {
    r.setAttribute('aria-current', String(r.dataset.id === sessionId));
  }
  paintCrumb();
  paintSummary(null);
  // A new session means the cached agent reports belong to someone else.
  detailCache.clear();

  const any = chat.ids.length > 0;
  el.chat.hidden = !any;
  el.chatSplit.hidden = !any;
  shell.classList.toggle('no-chat', !any);
  // Offered only where it means something: a session the panel already owns is
  // already here, and there is nothing to continue.
  el.continueSession.hidden = ownedIds.has(sessionId);
  el.continueSession.title = `Continue ${sessionId.slice(0, 8)} in the panel — forks it, so the original transcript is not written to`;

  if (source) source.close();
  source = new EventSource(api(`/api/stream?session=${encodeURIComponent(sessionId)}`));

  source.addEventListener('graph', (e) => {
    heardNow();
    const g = JSON.parse(e.data);
    canvas.render(g);
    // The inspector holds a node object from an earlier frame; refresh it so
    // status, tokens and tool counts keep moving while it is open.
    if (inspectorNode) {
      const fresh = g.nodes.find((n) => n.id === inspectorNode.id);
      if (fresh) {
        const changed = fresh.status !== inspectorNode.status;
        inspectorNode = fresh;
        paintInspector();
        if (changed && fresh.kind === 'agent') loadDetail(fresh.id, fresh.status);
      }
    }
    // Every status is named, so the chips add up to the total. A summary that
    // reports "250 agents · 7 done" and stops invites the reader to assume the
    // other 243 failed. A count of records that could not be read stays beside
    // them: it is not a status, and it is not nothing.
    const s = g.stats ?? {};
    paintSummary(s, s.malformed ? [`${s.malformed} malformed`] : []);
    el.foot.textContent = '';
  });

  source.addEventListener('idle', heardNow);

  source.addEventListener('waiting', (e) => {
    heardNow();
    let reason = '';
    try { reason = JSON.parse(e.data).reason ?? ''; } catch { /* keep default */ }
    paintSummary(null);
    el.foot.textContent = reason;
    canvas.render({ nodes: [], edges: [] });
  });

  // A server-side fault and a dropped connection are different facts. They
  // used to share EventSource's 'error' event, so "no such session" was shown
  // as "reconnecting" and the reason was thrown away.
  source.addEventListener('fault', (e) => {
    let reason = 'unknown';
    try { reason = JSON.parse(e.data).reason ?? reason; } catch { /* keep default */ }
    el.foot.textContent = `stream fault: ${reason}`;
    source.close();
    source = null;
  });

  // A dropped stream reconnects by itself, and the two polls say within two
  // seconds whether the server is gone. So this only names what happened; it
  // does not decide Offline.
  source.onerror = () => {
    if (!source) return;               // already closed by a fault
    el.foot.textContent = 'stream dropped — reconnecting';
  };
}

/* ------------------------------------------------------- live indicator */

const pulse = {
  dot: el.pulse.querySelector('.dot'),
  word: el.pulse.querySelector('strong'),
  detail: el.pulse.querySelector('.live-detail'),
};
function paintPulse() {
  const l = liveness(Date.now(), heard.okAt, heard.failed);
  el.pulse.dataset.state = l.state;
  pulse.dot.dataset.tone = l.tone ?? 'none';
  pulse.word.textContent = l.word;
  pulse.detail.textContent = l.detail ? `· ${l.detail}` : '';
}
paintPulse();
setInterval(paintPulse, 1000);

/* -------------------------------------------------------------- home, keys */

// The mark goes back to where the panel opens: the session that moved last.
el.home.addEventListener('click', (e) => {
  e.preventDefault();
  let latest = null;
  for (const p of projectsData?.projects ?? []) {
    for (const sn of p.sessions) if (!latest || sn.modifiedAt > latest.sn.modifiedAt) latest = { p, sn };
  }
  setTab('projects');
  if (!latest) return;
  expanded.add(latest.p.key);
  paintProjects();
  selectSession(latest.sn.sessionId);
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    if (!el.menu.hidden) { closeMenu(); return; }
    if (document.activeElement === el.filter && el.filter.value) {
      el.filter.value = ''; filterText = ''; paintProjects(); paintLive();
    }
    return;
  }
  if (e.metaKey || e.ctrlKey) return;
  const t = e.target;
  if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
  if (e.key === '/') {
    e.preventDefault();
    setSideHidden(false);
    el.filter.focus();
  } else if (e.key === '[') {
    setSideHidden(true);
  } else if (e.key === ']') {
    setSideHidden(false);
  }
});

/* --------------------------------------------------------------- polling */

async function pollFleet() {
  try {
    renderFleet(await getJson('/api/fleet'));
  } catch (e) {
    renderNote(el.fleet, { kind: 'unmeasured', title: 'Server unreachable', why: e.message });
  }
}

async function pollSessions() {
  try {
    renderSessions(await getJson('/api/projects'));
  } catch { /* the Live indicator says so; the list keeps what it last showed */ }
}

// Sessions this panel owns survive a page reload as long as the server does.
getJson('/api/owned')
  .then((r) => { for (const sn of r.sessions ?? []) ownedIds.add(sn.sessionId); })
  .catch(() => { /* none yet */ });

setTab(store.get('crewforth-studio-nav-tab') ?? 'projects');
pollFleet(); pollSessions();
setInterval(pollFleet, FLEET_POLL_MS);
setInterval(pollSessions, SESSION_POLL_MS);
