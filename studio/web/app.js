// CSK Studio — wiring.
//
// One rule runs through the rendering: "not measured" and "nothing running"
// are different facts and never share a screen state. An empty list because
// the CLI is missing would read as a quiet, healthy machine, which is exactly
// the kind of lie this panel exists to stop telling.

import { Canvas } from './canvas.js';
import { renderMarkdown } from './md.js';
import { Chat } from './chat.js';

const FLEET_POLL_MS = 2000;
const SESSION_POLL_MS = 5000;

const el = {
  fleet: document.getElementById('fleet'),
  fleetMeta: document.getElementById('fleet-meta'),
  sessions: document.getElementById('sessions'),
  filter: document.getElementById('filter'),
  kit: document.getElementById('kitline'),
  reach: document.getElementById('reach'),
  reachHead: document.getElementById('reach-head'),
  reachMeta: document.getElementById('reach-meta'),
  chat: document.getElementById('chat'),
  chatSplit: document.getElementById('chat-split'),
  resizer: document.getElementById('resizer'),
  sideWide: document.getElementById('side-wide'),
  sideHide: document.getElementById('side-hide'),
  sideShow: document.getElementById('side-show'),
  fullscreen: document.getElementById('fullscreen'),
  newSession: document.getElementById('new-session'),
  continueSession: document.getElementById('continue-session'),
  newTerm: document.getElementById('new-term'),
  sessionsMeta: document.getElementById('sessions-meta'),
  summary: document.getElementById('graph-summary'),
  pulse: document.getElementById('pulse'),
  foot: document.getElementById('foot-note'),
  theme: document.getElementById('theme'),
  inspector: document.getElementById('inspector'),
};

const token = new URLSearchParams(location.search).get('token');
const api = (p) => (token ? `${p}${p.includes('?') ? '&' : '?'}token=${encodeURIComponent(token)}` : p);
const getJson = async (p) => {
  const r = await fetch(api(p), { cache: 'no-store' });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
};

/* ---------------------------------------------------------------- theme */

const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* blocked storage */ } },
};

const savedTheme = store.get('csk-studio-theme');
if (savedTheme === 'light' || savedTheme === 'dark') document.documentElement.dataset.theme = savedTheme;

el.theme.addEventListener('click', () => {
  const next = document.documentElement.dataset.theme === 'light' ? 'dark' : 'light';
  document.documentElement.dataset.theme = next;
  store.set('csk-studio-theme', next);
});

/* --------------------------------------------------------------- panels
   Three columns and two dividers. Each width is the user's, remembered, and
   clamped so neither side panel can be dragged to nothing by accident or made
   to swallow the graph. Collapsing is a separate, deliberate act with its own
   control. */

const PANEL = {
  side: { min: 170, max: 620, def: 260, wide: 460, varName: '--side-w', key: 'csk-studio-side-w' },
  chat: { min: 280, max: 900, def: 420, wide: 720, varName: '--chat-w', key: 'csk-studio-chat-w' },
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
function setSideHidden(hidden, refit = true) {
  shell.classList.toggle('no-side', hidden);
  el.sideShow.hidden = !hidden;
  store.set('csk-studio-side-hidden', hidden ? '1' : '0');
  if (refit) canvas.fitIfUntouched();
}
setSideHidden(store.get('csk-studio-side-hidden') === '1', false);

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

// Widen toggles between the default and a roomier width rather than growing
// without end: a panel you have to drag back is not a convenience.
function wideToggle(btn, which) {
  btn.addEventListener('click', () => {
    const cur = parseInt(getComputedStyle(document.documentElement).getPropertyValue(PANEL[which].varName), 10) || PANEL[which].def;
    setPanel(which, Math.abs(cur - PANEL[which].wide) < 24 ? PANEL[which].def : PANEL[which].wide);
    canvas.fitIfUntouched();
  });
}
wideToggle(el.sideWide, 'side');

/* ------------------------------------------------------------ full screen
   The browser's own, so it hides the browser too — a panel meant to be watched
   while work runs should be able to take the whole display. Collapsing the side
   panels is a separate control on purpose: the two compose, and folding one
   into the other would make each less predictable. */

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
  el.fullscreen.textContent = on ? '⛶' : '⛶';
  el.fullscreen.classList.toggle('on', on);
  el.fullscreen.title = on ? 'Leave full screen (f or Esc)' : 'Full screen (f)';
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

const writeHeaders = { 'x-csk-studio': '1', ...(token ? { authorization: `Bearer ${token}` } : {}) };
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
  const row = el.sessions.querySelector(`.srow[data-id="${CSS.escape(sessionId)}"] .sname`);
  chat.openReadOnly(sessionId, row?.textContent ?? null);
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
  el.continueSession.textContent = 'continuing…';
  try {
    const r = await chat.start({ cwd: projectsData?.cwd ?? null, permissionMode: 'plan', resume: from });
    if (!r.ok) {
      el.foot.textContent = `could not continue: ${r.reason}`;
    } else {
      ownedIds.add(r.session.sessionId);
      el.foot.textContent = `continued ${from.slice(0, 8)} as a fork — the original transcript is untouched`;
    }
  } finally {
    el.continueSession.disabled = false;
    el.continueSession.textContent = '↩ continue here';
  }
});

el.newSession.addEventListener('click', async () => {
  const cwd = projectsData?.cwd ?? null;
  el.newSession.disabled = true;
  el.newSession.textContent = 'starting…';
  try {
    // `plan` by default: a panel that can start a session must not also be the
    // reason one got write access nobody asked for.
    const r = await chat.start({ cwd, permissionMode: 'plan' });
    if (!r.ok) el.foot.textContent = `could not start a session: ${r.reason}`;
    else ownedIds.add(r.session.sessionId);
  } finally {
    el.newSession.disabled = false;
    el.newSession.textContent = '+ session';
  }
});

// The shell button only exists where a shell can exist. Offering a control
// that always fails is worse than not offering it.
getJson('/api/pty')
  .then((r) => {
    if (!r.enabled || !r.available) return;
    el.newTerm.hidden = false;
    el.newTerm.title = r.warning;
    el.newTerm.addEventListener('click', async () => {
      el.newTerm.disabled = true;
      try {
        const out = await chat.startTerminal({ cwd: projectsData?.cwd ?? null });
        if (!out.ok) el.foot.textContent = `could not open a shell: ${out.reason}`;
        else { el.chat.hidden = false; el.chatSplit.hidden = false; shell.classList.remove('no-chat'); }
      } finally { el.newTerm.disabled = false; }
    });
  })
  .catch(() => { /* older server, or pty off */ });

/* --------------------------------------------------------------- canvas */

const canvas = new Canvas(document.getElementById('canvas'), { onSelect: showInspector });

getJson('/api/palette')
  .then((p) => canvas.setPalette(p))
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
   What the kit already measures about itself. Nothing here is recomputed —
   each panel shows what the kit's own tool said, including when it said it
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
  if (!kitData) { body.append(node('div', 'ihint', 'Reading the kit…')); return; }

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
    + (log.commandsRecorded ? '' : ' · commands not recorded (CSK_GATE_LOG_CMD=1 records them)')));

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

/* ---------------------------------------------------------------- fleet */

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

// Sessions on other machines. The panel cannot reach them and does not pretend
// to: their transcripts are on those machines' disks, so there is nothing to
// draw but the roster itself, and even that is a snapshot rather than a feed.
function renderReach(roster) {
  if (!roster) { el.reachHead.hidden = true; el.reach.replaceChildren(); return; }

  const remote = (roster.peers ?? []).filter((p) => p.remote);
  if (!roster.measured || !remote.length) {
    // A roster nobody has recorded is not "no peers". Say which it is.
    el.reachHead.hidden = false;
    el.reachMeta.textContent = roster.measured ? '0' : 'not measured';
    el.reachMeta.className = 'meta warn';
    renderNote(el.reach, {
      kind: roster.measured ? '' : 'unmeasured',
      title: roster.measured ? 'None reachable' : 'Not measured',
      body: roster.measured
        ? 'A connected session looked and found no machines besides this one.'
        : 'No session here has recorded a peer list yet.',
      why: roster.measured ? null : roster.reason,
    });
    return;
  }

  el.reachHead.hidden = false;
  const when = new Date(roster.seenAt).toLocaleTimeString();
  el.reachMeta.textContent = `${remote.length} · seen ${when}`;
  el.reachMeta.className = 'meta';
  el.reachMeta.title =
    `Recorded by session ${String(roster.seenBy).slice(0, 8)} at ${when}. `
    + 'Only a session connected to Remote Control can see these, so this is what one last reported — not a live feed.';

  el.reach.replaceChildren(...remote.map((p) => {
    const row = node('div', 'session reach-row');
    const ring = node('span', 'ring');
    ring.dataset.status = p.status === 'running' ? 'busy' : (p.status === 'offline' ? 'unknown' : 'idle');
    ring.title = p.status ?? '';

    const who = node('div', 'who');
    const nm = node('div', 'name');
    nm.append(document.createTextNode(p.name));
    nm.append(node('span', 'origin', 'remote'));
    who.append(nm);
    who.append(node('div', 'path', p.note || p.kind || ''));

    const stat = node('div', 'stat');
    stat.append(node('span', 'status', p.status ?? '?'));
    row.append(ring, who, stat);
    // There is nothing to open: the transcript is on that machine.
    row.title = `${p.name} [${p.ref}] — on another machine. Its transcript lives there, so the panel can list it but not draw it.`;
    return row;
  }));
}

function renderFleet(data) {
  if (!data.measured) {
    el.fleetMeta.textContent = 'not measured';
    renderNote(el.fleet, {
      kind: 'unmeasured',
      title: 'Not measured',
      body: 'This is not the same as "nothing is running" — nothing was read.',
      why: data.reason || 'no reason reported',
    });
    return;
  }

  const sessions = data.sessions ?? [];
  const origins = data.origins ?? [];
  const down = origins.filter((o) => o.ok === false);
  el.fleetMeta.textContent = origins.length > 1
    ? `${sessions.length} · ${origins.length - down.length}/${origins.length} machines`
    : `${sessions.length}`;
  el.fleetMeta.className = down.length ? 'meta warn' : 'meta';
  el.fleetMeta.title = origins
    .map((o) => `${o.name}${o.local ? ' (this machine)' : ''}: ${o.ok === false ? `unreachable — ${o.reason}` : 'ok'}`)
    .join('\n');

  if (!sessions.length) {
    renderNote(el.fleet, { title: 'No sessions running', body: 'Measured — the machine has none open.' });
    return;
  }

  const order = { busy: 0, waiting: 1, idle: 2 };
  sessions.sort((a, b) => (order[a.status] ?? 3) - (order[b.status] ?? 3));

  el.fleet.replaceChildren(...sessions.map((s) => {
    const row = node('div', 'session fleet-row');
    const ring = node('span', 'ring');
    ring.dataset.status = ['busy', 'waiting', 'idle'].includes(s.status) ? s.status : 'unknown';
    ring.title = s.status;

    const who = node('div', 'who');
    const nm = node('div', 'name');
    nm.append(document.createTextNode(s.name || s.sessionId.slice(0, 8)));
    if (s.origin && s.local === false) nm.append(node('span', 'origin', s.origin));
    who.append(nm);
    who.append(node('div', 'path', shortPath(s.cwd) || '—'));
    if (s.waitingFor) who.append(node('div', 'waiting-for', `⏸ ${s.waitingFor}`));

    const stat = node('div', 'stat');
    stat.append(node('span', 'status', s.status));
    row.append(ring, who, stat);

    // A live session in the fleet is the one most likely to be wanted, so
    // clicking it does what clicking it anywhere else does: opens it.
    if (s.local !== false && s.sessionId) {
      row.classList.add('clickable');
      row.setAttribute('aria-current', String(s.sessionId === current));
      row.title = `Open ${s.name ?? s.sessionId.slice(0, 8)}`;
      row.addEventListener('click', () => selectSession(s.sessionId));
    } else {
      // A session on another machine has no transcript here to open.
      row.title = `${s.name ?? ''} — on ${s.origin}. Its transcript is on that machine.`;
    }
    return row;
  }));
}

/* ------------------------------------------------------------- sessions */

let current = null;
let source = null;

function selectSession(sessionId) {
  // Selecting the session already selected is not a no-op: its conversation may
  // have been closed since, and clicking it is how someone asks for it back.
  if (current === sessionId) { openConversation(sessionId); return; }
  current = sessionId;
  canvas.setSession(sessionId);
  showInspector(null);

  for (const r of el.sessions.querySelectorAll('.srow')) {
    r.setAttribute('aria-current', String(r.dataset.id === sessionId));
  }
  // A new session means the cached agent reports belong to someone else.
  detailCache.clear();

  // Every session gets its conversation shown; only the ones the panel started
  // get a box to write in. Hiding the conversation of a session we can read
  // perfectly well was the wrong half of that rule.
  openConversation(sessionId);
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
    const s = g.stats ?? {};
    // Every status is named, so the parts add up to the total. A summary that
    // reports "250 agents · 7 done" and stops invites the reader to assume the
    // other 243 failed.
    const parts = [`${s.agents ?? 0} agents`];
    if (s.workflows) parts.push(`${s.workflows} workflows`);
    for (const [k, v] of Object.entries(s.byStatus ?? {})) if (v) parts.push(`${v} ${k}`);
    if (g.contextTokens != null) parts.push(`${(g.contextTokens / 1000).toFixed(0)}k ctx`);
    if (s.malformed) parts.push(`${s.malformed} malformed`);
    el.summary.textContent = parts.join(' · ');
    setPulse('on', 'live');
    el.foot.textContent = `graph updated ${new Date().toLocaleTimeString()}`;
  });

  source.addEventListener('idle', () => setPulse('on', 'live'));

  source.addEventListener('waiting', (e) => {
    let reason = '';
    try { reason = JSON.parse(e.data).reason ?? ''; } catch { /* keep default */ }
    setPulse('on', 'waiting');
    el.summary.textContent = 'no agents yet';
    el.foot.textContent = reason;
    canvas.render({ nodes: [], edges: [] });
  });

  // A server-side fault and a dropped connection are different facts. They
  // used to share EventSource's 'error' event, so "no such session" was shown
  // as "reconnecting" and the reason was thrown away.
  source.addEventListener('fault', (e) => {
    let reason = 'unknown';
    try { reason = JSON.parse(e.data).reason ?? reason; } catch { /* keep default */ }
    setPulse('off', 'fault');
    el.foot.textContent = `stream fault: ${reason}`;
    source.close();
    source = null;
  });

  source.onerror = () => {
    if (!source) return;               // already closed by a fault
    setPulse('off', 'reconnecting');
    el.foot.textContent = 'stream dropped — reconnecting';
  };
}

function setPulse(cls, text) {
  el.pulse.className = `pulse ${cls}`;
  el.pulse.textContent = text;
}

let projectsData = null;
let expanded = new Set();
let filterText = '';
let showMissing = false;

el.filter.addEventListener('input', () => {
  filterText = el.filter.value.trim().toLowerCase();
  paintProjects();
});

function fmtSize(bytes) {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)}KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)}MB`;
}

function renderSessions(data) {
  if (!data.measured) {
    el.sessionsMeta.textContent = 'not measured';
    renderNote(el.sessions, {
      kind: 'unmeasured',
      title: 'No transcripts here',
      body: 'Nothing was read.',
      why: data.reason,
    });
    return;
  }
  projectsData = data;
  const t0 = data.totals ?? {};
  if (t0.kitInstalled) {
    const bits = [`kit in ${t0.kitInstalled}`];
    if (t0.kitOutdated) bits.push(`${t0.kitOutdated} behind ${data.latest?.version ?? '?'}`);
    if (t0.kitUncompared) bits.push(`${t0.kitUncompared} not compared`);
    el.kit.textContent = bits.join(' · ');
    el.kit.className = `kitline${t0.kitOutdated ? ' warn' : ''}`;
  } else {
    el.kit.textContent = '';
  }
  // The project you are standing in starts open; the rest stay folded, or a
  // machine with 175 projects buries the one you are working in.
  if (!expanded.size) {
    const cur = data.projects.find((p) => p.current) ?? data.projects[0];
    if (cur) expanded.add(cur.key);
  }
  paintProjects();
}

function paintProjects() {
  const data = projectsData;
  if (!data) return;

  // Typing a filter is an explicit request, so it searches everything —
  // including the projects whose directories are gone. Hiding a result someone
  // asked for by name is worse than showing a dead path.
  let projects = (showMissing || filterText) ? data.projects : data.projects.filter((p) => p.exists);
  const hidden = data.projects.length - projects.length;

  if (filterText) {
    projects = projects.filter((p) =>
      p.label.toLowerCase().includes(filterText) ||
      (p.cwd ?? '').toLowerCase().includes(filterText) ||
      (p.origin ?? '').toLowerCase().includes(filterText) ||
      p.sessions.some((x) => (x.title ?? '').toLowerCase().includes(filterText)));
  }

  const t = data.totals ?? {};
  el.sessionsMeta.textContent = filterText
    ? `${projects.length}/${t.live ?? 0}`
    : `${t.live ?? 0} · ${t.sessions ?? 0} sessions`;

  if (!projects.length) {
    renderNote(el.sessions, { title: 'Nothing matches', body: `No project matches “${filterText}”.` });
    return;
  }

  const frag = document.createDocumentFragment();
  for (const p of projects) {
    const open = expanded.has(p.key) || Boolean(filterText);

    const head = node('div', `pgroup${p.current ? ' current' : ''}`);
    head.setAttribute('role', 'treeitem');
    head.setAttribute('aria-expanded', String(open));
    head.append(node('span', 'pcaret', open ? '▾' : '▸'));
    const lbl = node('span', 'plabel');
    lbl.append(document.createTextNode(p.label));
    // Where a project lives is part of its identity once more than one machine
    // is in view.
    if (p.origin && p.local === false) lbl.append(node('span', 'origin', p.origin));
    head.append(lbl);
    const counts = node('span', 'pcount');
    counts.append(node('span', null, String(p.total)));
    if (p.agentTotal) counts.append(node('span', 'sbadge', `${p.agentTotal} ▸`));
    head.append(counts);
    // Kit version sits with the project, because that is the thing that is or
    // is not up to date.
    if (p.kit?.installed) {
      const k = node('span', 'kitbadge');
      if (p.kit.compared === false) {
        k.classList.add('unknown');
        k.textContent = `${p.kit.version} ?`;
        k.title = `kit ${p.kit.version} — not compared: ${p.kit.reason}`;
      } else if (p.kit.outdated) {
        k.classList.add('old');
        k.textContent = `${p.kit.version} → ${p.kit.latest}`;
        k.title = `kit ${p.kit.version} is behind ${p.kit.latest} — run /update-csk in this project`;
      } else if (p.kit.ahead) {
        k.classList.add('ahead');
        k.textContent = p.kit.version;
        k.title = `kit ${p.kit.version} is ahead of the published ${p.kit.latest}`;
      } else {
        k.classList.add('ok');
        k.textContent = p.kit.version;
        k.title = `kit ${p.kit.version} — current`;
      }
      counts.prepend(k);
    }
    if (!p.exists) head.classList.add('gone');
    head.title = (p.cwd ?? p.dir) + (p.exists ? '' : ' — directory no longer exists');
    head.addEventListener('click', () => {
      if (expanded.has(p.key)) expanded.delete(p.key); else expanded.add(p.key);
      paintProjects();
    });
    frag.append(head);

    if (!open) continue;

    for (const sn of p.sessions) {
      const row = node('div', 'srow');
      row.dataset.id = sn.sessionId;
      row.setAttribute('role', 'treeitem');
      row.setAttribute('aria-current', String(sn.sessionId === current));
      // The name people actually gave the session, with the id as the fallback
      // it always was.
      row.append(node('span', 'sname', sn.title || sn.sessionId.slice(0, 8)));
      const right = node('span', 'sright');
      if (sn.agentCount) right.append(node('span', 'sbadge', `${sn.agentCount} ▸`));
      right.append(node('span', 'sagents', fmtSize(sn.bytes)));
      row.append(right);
      if (ownedIds.has(sn.sessionId)) row.classList.add('owned');
      row.title = `${sn.sessionId}\n${sn.title ?? ''}`;
      row.addEventListener('click', () => selectSession(sn.sessionId));
      frag.append(row);
    }

    if (p.total > p.sessions.length) {
      frag.append(node('div', 'ptrunc', `${p.total - p.sessions.length} older session(s) not listed`));
    }
  }
  for (const o of (data.origins ?? []).filter((x) => x.ok === false)) {
    const w = node('div', 'ptrunc pdown');
    w.textContent = `${o.name} unreachable — ${o.reason}`;
    frag.append(w);
  }

  if (hidden > 0 && !filterText) {
    const t2 = node('div', 'ptrunc pmissing');
    t2.textContent = showMissing
      ? `hiding nothing — ${hidden} directory(ies) no longer exist`
      : `${hidden} project(s) hidden — their directories no longer exist`;
    const b = node('button', 'ghost', showMissing ? 'hide' : 'show');
    b.addEventListener('click', () => { showMissing = !showMissing; paintProjects(); });
    t2.append(b);
    frag.append(t2);
  }
  el.sessions.replaceChildren(frag);

  if (!current) {
    const cur = data.projects.find((x) => x.current) ?? data.projects[0];
    const best = cur?.sessions.find((x) => x.agentCount > 0) ?? cur?.sessions[0];
    if (best) selectSession(best.sessionId);
  }
}

/* --------------------------------------------------------------- polling */

async function pollFleet() {
  try {
    const fleet = await getJson('/api/fleet');
    renderFleet(fleet);
    renderReach(fleet.roster);
  } catch (e) {
    el.fleetMeta.textContent = 'offline';
    renderNote(el.fleet, { kind: 'unmeasured', title: 'Server unreachable', why: e.message });
  }
}

async function pollSessions() {
  try {
    renderSessions(await getJson('/api/projects'));
  } catch (e) {
    el.sessionsMeta.textContent = 'offline';
  }
}

// Sessions this panel owns survive a page reload as long as the server does.
getJson('/api/owned')
  .then((r) => { for (const sn of r.sessions ?? []) ownedIds.add(sn.sessionId); })
  .catch(() => { /* none yet */ });

pollFleet(); pollSessions();
setInterval(pollFleet, FLEET_POLL_MS);
setInterval(pollSessions, SESSION_POLL_MS);
