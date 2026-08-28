// Conversations with sessions the panel owns.
//
// Each session gets a pane that keeps its own stream open whether or not it is
// on screen, so a session working in the background is still working when you
// come back to it — its progress is not a replay, it happened.
//
// Two sources describe the same reply: partial `content_block_delta` events
// while it is being written, and the complete `assistant` record once it is
// done. Rendering both would double every message, so deltas only ever feed a
// provisional bubble that the authoritative record replaces.

import { renderMarkdown } from './md.js';
import { Term } from './term.js';

const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
};

/**
 * Options a reply is offering, if it is offering any.
 *
 * Exported so it can be tested without a DOM: the rule for when prose counts
 * as a question is the part worth pinning, and it is easy to get wrong in a
 * direction that puts buttons under every bulleted list.
 */
export function quickReplies(text) {
  if (!text) return [];
  // Only the tail of the message: an option list in the middle is discussion,
  // not the question being asked now.
  const lines = text.trimEnd().split('\n').slice(-14);
  const opts = [];
  for (const raw of lines) {
    const m = raw.match(/^\s*(?:[-*+]|\d+[.)])\s+(.+?)\s*$/);
    if (!m) continue;
    const label = m[1].replace(/\*\*(.+?)\*\*/g, '$1').replace(/`(.+?)`/g, '$1').trim();
    if (label.length >= 2 && label.length <= 80) opts.push(label);
  }
  // Two to five short options reads as a question. One is a statement, a dozen
  // is a report, and without a question mark it is neither.
  return (opts.length >= 2 && opts.length <= 5 && /\?/.test(text)) ? opts : [];
}

/* ========================================================== one session === */

class Pane {
  constructor(session, { api, headers, onChange }) {
    this.api = api;
    this.headers = headers;
    this.onChange = onChange;
    this.session = session;
    this.id = session.sessionId;
    this.source = null;
    this.messages = [];
    this.streaming = null;
    this.permissions = [];
    this.unread = 0;

    this.root = el('div', 'pane');
    this.root.innerHTML = `
      <div class="chat-log"></div>
      <div class="perm-queue" hidden></div>
      <form class="chat-form">
        <textarea class="chat-input" rows="2"
          placeholder="Message this session…  (Enter to send, Shift+Enter for a newline)"></textarea>
        <button class="chat-send" type="submit">send</button>
      </form>`;

    this.logEl = this.root.querySelector('.chat-log');
    this.permEl = this.root.querySelector('.perm-queue');
    this.formEl = this.root.querySelector('.chat-form');
    this.inputEl = this.root.querySelector('.chat-input');

    this.formEl.addEventListener('submit', (e) => { e.preventDefault(); this.send(); });
    this.inputEl.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); this.send(); }
    });

    this.connect();
  }

  get visible() { return !this.root.hidden; }

  connect() {
    if (this.source) return;
    this.source = new EventSource(this.api(`/api/owned/${encodeURIComponent(this.id)}/events`));
    this.source.addEventListener('state', (e) => {
      try { this.session = JSON.parse(e.data); } catch { return; }
      this.paintState();
      this.onChange(this);
    });
    this.source.addEventListener('event', (e) => {
      let ev;
      try { ev = JSON.parse(e.data); } catch { return; }
      this.absorb(ev.rec);
    });
    this.source.onerror = () => { this.streamBroken = true; this.onChange(this); };
  }

  disconnect() {
    if (this.source) { this.source.close(); this.source = null; }
  }

  /* --------------------------------------------------------- ingestion */

  absorb(rec) {
    if (!rec) return;

    if (rec.type === 'stream_event') {
      const t = rec.event?.type;
      if (t === 'message_start') { this.streaming = { text: '' }; this.paintStreaming(); }
      else if (t === 'content_block_delta' && rec.event.delta?.type === 'text_delta') {
        if (!this.streaming) this.streaming = { text: '' };
        this.streaming.text += rec.event.delta.text ?? '';
        this.paintStreaming();
      }
      return;
    }

    // A subagent's text is forwarded with a parent id. It belongs to the graph,
    // not to this conversation — showing it here would read as the session
    // saying things it never said.
    if (rec.parent_tool_use_id) return;

    if (rec.type === 'permissions') {
      this.permissions = rec.pending ?? [];
      this.paintPermissions();
      this.onChange(this);
      return;
    }

    if (rec.type === 'user' && rec.message?.content) {
      const text = typeof rec.message.content === 'string'
        ? rec.message.content
        : rec.message.content.filter((c) => c?.type === 'text').map((c) => c.text).join('');
      if (text.trim()) { this.clearPending(); this.push({ role: 'user', text }); }
      return;
    }

    if (rec.type === 'assistant' && Array.isArray(rec.message?.content)) {
      this.streaming = null;
      const blocks = [];
      for (const c of rec.message.content) {
        if (c?.type === 'text' && c.text?.trim()) blocks.push({ kind: 'text', text: c.text });
        else if (c?.type === 'tool_use') {
          const i = c.input ?? {};
          blocks.push({
            kind: 'tool',
            name: c.name ?? 'tool',
            label: i.description ?? i.file_path ?? i.command ?? i.pattern ?? i.query ?? null,
          });
        }
      }
      if (blocks.length) {
        this.push({ role: 'assistant', blocks });
        if (!this.visible) { this.unread += 1; this.onChange(this); }
      }
      return;
    }

    if (rec.type === 'result') { this.streaming = null; this.paintStreaming(); return; }
    if (rec.type === 'fault' || rec.type === 'stderr') this.note(rec.reason ?? rec.text, 'bad');
  }

  push(msg) {
    for (const q of this.logEl.querySelectorAll('.quick')) q.remove();
    this.messages.push(msg);
    this.logEl.append(this.renderMessage(msg));
    this.paintStreaming();
    this.scroll();
  }

  /* --------------------------------------------------------- rendering */

  renderMessage(msg) {
    const wrap = el('div', `msg msg-${msg.role}`);
    wrap.append(el('div', 'msg-role', msg.role === 'user' ? 'you' : 'claude'));

    const body = el('div', 'msg-body');
    if (msg.role === 'user') {
      body.append(el('div', 'msg-text', msg.text));
    } else {
      for (const b of msg.blocks) {
        if (b.kind === 'text') {
          const md = el('div', 'md');
          md.innerHTML = renderMarkdown(b.text);
          body.append(md);
        } else {
          const card = el('div', 'tool-card');
          card.append(el('span', 'tool-name', b.name));
          if (b.label) card.append(el('span', 'tool-label', String(b.label).slice(0, 200)));
          body.append(card);
        }
      }
    }
    wrap.append(body);

    if (msg.role === 'assistant') {
      const last = msg.blocks?.filter((b) => b.kind === 'text').pop();
      const opts = quickReplies(last?.text);
      if (opts.length) {
        const row = el('div', 'quick');
        row.append(el('span', 'quick-hint', 'reply with'));
        for (const o of opts) {
          const b = el('button', 'quick-btn', o);
          b.addEventListener('click', () => { row.remove(); this.inputEl.value = o; this.send(); });
          row.append(b);
        }
        wrap.append(row);
      }
    }
    return wrap;
  }

  paintStreaming() {
    let node = this.logEl.querySelector('.msg-streaming');
    if (!this.streaming) { node?.remove(); return; }
    if (!node) {
      node = el('div', 'msg msg-assistant msg-streaming');
      node.append(el('div', 'msg-role', 'claude'));
      node.append(el('div', 'msg-body'));
      this.logEl.append(node);
    }
    const body = node.querySelector('.msg-body');
    if (this.streaming.text) {
      body.textContent = this.streaming.text;
      body.classList.add('msg-text');
    } else {
      body.replaceChildren(el('span', 'thinking', 'thinking…'));
    }
    this.scroll();
  }

  paintPermissions() {
    const list = this.permissions ?? [];
    this.permEl.hidden = list.length === 0;
    if (!list.length) { this.permEl.replaceChildren(); return; }

    const wait = this.session?.gateWaitSeconds ?? null;
    const frag = document.createDocumentFragment();
    for (const r of list) {
      const card = el('div', 'perm');
      const head = el('div', 'perm-head');
      head.append(el('span', 'perm-tool', r.toolName));
      // The clock is part of the decision: silence becomes a denial, and the
      // reader should see that coming rather than discover it.
      if (wait) {
        const left = Math.max(0, wait - Math.round((Date.now() - r.askedAt) / 1000));
        head.append(el('span', 'perm-clock', `${left}s → deny`));
      }
      card.append(head);
      if (r.detail) card.append(el('pre', 'perm-detail', String(r.detail).slice(0, 600)));

      const acts = el('div', 'perm-acts');
      for (const [verdict, label, cls] of [
        ['allow', 'allow once', 'ok'],
        ['always', `always allow ${r.toolName}`, ''],
        ['deny', 'deny', 'bad'],
      ]) {
        const b = el('button', `perm-btn ${cls}`, label);
        b.addEventListener('click', () => this.decide(r.toolUseId, verdict, card));
        acts.append(b);
      }
      card.append(acts);
      frag.append(card);
    }
    this.permEl.replaceChildren(frag);
  }

  paintState() {
    const s = this.session;
    const dead = s.state === 'exited' || s.state === 'failed';
    this.formEl.hidden = false;
    this.inputEl.disabled = dead;
  }

  note(text, kind = '') { this.logEl.append(el('div', `chat-note ${kind}`, text)); this.scroll(); }

  scroll() {
    // Only follow the tail when the reader is already at it, so scrolling back
    // through a long reply is not yanked forward by the next token.
    const near = this.logEl.scrollHeight - this.logEl.scrollTop - this.logEl.clientHeight < 120;
    if (near) this.logEl.scrollTop = this.logEl.scrollHeight;
  }

  pending(text) {
    this.clearPending();
    const wrap = el('div', 'msg msg-user msg-pending');
    wrap.append(el('div', 'msg-role', 'you'));
    wrap.append(el('div', 'msg-body msg-text', text));
    this.logEl.append(wrap);
    this.scroll();
  }

  clearPending() { this.logEl.querySelector('.msg-pending')?.remove(); }

  /* ------------------------------------------------------------ actions */

  async send() {
    const text = this.inputEl.value.trim();
    if (!text) return;
    this.inputEl.value = '';
    // No optimistic bubble. The session is started with --replay-user-messages,
    // so it echoes what it actually received; drawing our own copy as well
    // printed every message twice.
    this.pending(text);

    const res = await fetch(this.api(`/api/owned/${encodeURIComponent(this.id)}/message`), {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...this.headers },
      body: JSON.stringify({ text }),
    }).then((r) => r.json()).catch((e) => ({ ok: false, reason: e.message }));

    if (!res.ok) { this.clearPending(); this.note(`Not sent: ${res.reason}`, 'bad'); }
    else { this.session = res.session; this.paintState(); this.onChange(this); }
  }

  async decide(toolUseId, verdict, card) {
    for (const b of card.querySelectorAll('button')) b.disabled = true;
    const res = await fetch(
      this.api(`/api/owned/${encodeURIComponent(this.id)}/permissions/${encodeURIComponent(toolUseId)}`),
      { method: 'POST', headers: { 'content-type': 'application/json', ...this.headers }, body: JSON.stringify({ verdict }) },
    ).then((r) => r.json()).catch((e) => ({ ok: false, reason: e.message }));
    if (!res.ok) {
      this.note(`Decision not recorded: ${res.reason}`, 'bad');
      for (const b of card.querySelectorAll('button')) b.disabled = false;
    }
  }

  async stop() {
    await fetch(this.api(`/api/owned/${encodeURIComponent(this.id)}/stop`), {
      method: 'POST', headers: this.headers,
    }).catch(() => {});
  }
}

/* ============================================================== the tabs === */

export class Chat {
  constructor(root, { api, headers }) {
    this.root = root;
    this.api = api;
    this.headers = headers;
    this.panes = new Map();
    this.activeId = null;
    this.onActivate = () => {};

    this.root.innerHTML = `
      <div class="chat-head">
        <div class="tabs"></div>
        <span class="chat-state"></span>
        <span class="chat-cost"></span>
        <button class="ghost chat-stop" type="button" hidden>stop</button>
      </div>
      <div class="panes"></div>`;

    this.tabsEl = this.root.querySelector('.tabs');
    this.panesEl = this.root.querySelector('.panes');
    this.stateEl = this.root.querySelector('.chat-state');
    this.costEl = this.root.querySelector('.chat-cost');
    this.stopEl = this.root.querySelector('.chat-stop');
    this.stopEl.addEventListener('click', () => this.active?.stop?.());

    // Countdowns have to move on their own; nothing else re-renders them.
    setInterval(() => { if (this.active?.permissions?.length) this.active.paintPermissions(); }, 1000);
  }

  get active() { return this.activeId ? this.panes.get(this.activeId) : null; }
  get ids() { return [...this.panes.keys()]; }

  /** A raw shell as a tab. Only reachable when the server was started with
   *  --enable-pty; the view carries its own warning. */
  async startTerminal({ cwd, rows = 30, cols = 110 }) {
    const res = await fetch(this.api('/api/pty'), {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...this.headers },
      body: JSON.stringify({ cwd, rows, cols }),
    });
    const body = await res.json().catch(() => ({ ok: false, reason: 'bad response' }));
    if (!body.ok) return { ok: false, reason: body.reason };

    const host = document.createElement('div');
    const term = new Term(host, {
      api: this.api,
      headers: this.headers,
      terminal: body.terminal,
      onClose: (id) => this.close(id),
    });
    const pane = {
      kind: 'term', id: term.id, root: host, term,
      session: { state: 'running', permissionMode: 'raw shell', gated: false },
      disconnect: () => term.disconnect(),
      permissions: [], unread: 0,
    };
    host.hidden = true;
    this.panesEl.append(host);
    this.panes.set(term.id, pane);
    this.activate(term.id);
    return { ok: true, terminal: body.terminal };
  }

  async start({ cwd, model, permissionMode, resume }) {
    const res = await fetch(this.api('/api/owned'), {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...this.headers },
      body: JSON.stringify({ cwd, model, permissionMode, resume }),
    });
    const body = await res.json().catch(() => ({ ok: false, reason: 'bad response' }));
    if (!body.ok) return { ok: false, reason: body.reason };
    this.open(body.session);
    return { ok: true, session: body.session };
  }

  open(session) {
    let pane = this.panes.get(session.sessionId);
    if (!pane) {
      pane = new Pane(session, { api: this.api, headers: this.headers, onChange: () => this.paintTabs() });
      this.panesEl.append(pane.root);
      this.panes.set(session.sessionId, pane);
    }
    this.activate(session.sessionId);
    return pane;
  }

  activate(id) {
    if (!this.panes.has(id)) return;
    this.activeId = id;
    for (const [pid, p] of this.panes) {
      p.root.hidden = pid !== id;
      if (pid === id) p.unread = 0;
    }
    this.paintTabs();
    const a = this.active;
    if (a?.kind === 'term') a.term.screen.focus();
    else a?.inputEl?.focus();
    // A terminal is not a session, so the canvas is left where it is rather
    // than pointed at a session id that does not exist.
    this.onActivate(a?.kind === 'term' ? null : id);
  }

  close(id) {
    const pane = this.panes.get(id);
    if (!pane) return;
    // Closing a tab closes the view, not the session: it keeps running and can
    // be reopened from the sidebar. Stopping is a separate, explicit act.
    pane.disconnect();
    pane.root.remove();
    this.panes.delete(id);
    if (this.activeId === id) {
      const next = this.ids[0] ?? null;
      this.activeId = null;
      if (next) this.activate(next); else { this.paintTabs(); this.onActivate(null); }
    } else {
      this.paintTabs();
    }
  }

  paintTabs() {
    const frag = document.createDocumentFragment();
    for (const [id, p] of this.panes) {
      const tab = el('button', `tab${id === this.activeId ? ' on' : ''}`);
      tab.type = 'button';
      const dot = el('span', 'tab-dot');
      dot.dataset.state = p.session?.state ?? 'unknown';
      tab.append(dot);
      const label = p.kind === 'term' ? `shell ${shortId(id)}`
        : (p.session?.resumedFrom ? `↩ ${shortId(p.session.resumedFrom)}` : shortId(id));
      tab.append(el('span', 'tab-name', label));
      if (p.kind === 'term') tab.classList.add('tab-term');
      if (p.permissions?.length) tab.append(el('span', 'tab-badge warn', String(p.permissions.length)));
      else if (p.unread) tab.append(el('span', 'tab-badge', String(p.unread)));
      tab.title = `${id}\n${p.session?.state ?? ''} · ${p.session?.permissionMode ?? ''}`;
      tab.addEventListener('click', () => this.activate(id));

      const x = el('span', 'tab-x', '×');
      x.title = 'Close this tab — the session keeps running';
      x.addEventListener('click', (e) => { e.stopPropagation(); this.close(id); });
      tab.append(x);
      frag.append(tab);
    }
    this.tabsEl.replaceChildren(frag);

    const a = this.active;
    const s = a?.session;
    if (a?.kind === 'term') {
      this.stateEl.textContent = `${s.state} · raw shell · NO GATE`;
      this.stateEl.dataset.state = s.state;
      this.stateEl.classList.add('ungated');
      this.costEl.textContent = '';
      this.stopEl.hidden = true;
      return;
    }
    this.stateEl.textContent = s
      ? `${s.state} · ${s.permissionMode}${s.gated ? '' : ' · NO GATE'}`
      : 'no session';
    this.stateEl.dataset.state = s?.state ?? 'none';
    this.stateEl.classList.toggle('ungated', Boolean(s) && !s.gated);
    this.costEl.textContent = s?.costUsd ? `$${s.costUsd.toFixed(4)}` : '';
    this.stopEl.hidden = !s || s.state === 'exited' || s.state === 'failed';
  }
}

function shortId(id) { return id.slice(0, 8); }
