// The conversation half of an owned session.
//
// Two sources describe the same reply: partial `content_block_delta` events
// while it is being written, and the complete `assistant` record once it is
// done. Rendering both would double every message, so deltas only ever feed a
// provisional bubble, and the authoritative record replaces it.

import { renderMarkdown } from './md.js';

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
    // Strip the emphasis authors put on the label itself.
    const label = m[1].replace(/\*\*(.+?)\*\*/g, '$1').replace(/`(.+?)`/g, '$1').trim();
    if (label.length >= 2 && label.length <= 80) opts.push(label);
  }
  // Two to five short options reads as a question. One is a statement, a dozen
  // is a report, and without a question mark it is neither.
  return (opts.length >= 2 && opts.length <= 5 && /\?/.test(text)) ? opts : [];
}

export class Chat {
  constructor(root, { api, headers }) {
    this.root = root;
    this.api = api;
    this.headers = headers;
    this.session = null;
    this.source = null;
    this.lastSeq = 0;
    this.messages = [];      // { role, blocks: [] }
    this.streaming = null;   // provisional text while a reply is being written
    this.onSession = () => {};

    this.#build();
    // The countdown has to move on its own; nothing else re-renders it.
    setInterval(() => { if (this.permissions?.length) this.#paintPermissions(); }, 1000);
  }

  #build() {
    this.root.innerHTML = `
      <div class="chat-head">
        <span class="chat-title">Conversation</span>
        <span class="chat-state"></span>
        <span class="chat-cost"></span>
        <button class="ghost chat-stop" type="button" hidden>stop</button>
      </div>
      <div class="chat-log"></div>
      <div class="perm-queue" hidden></div>
      <form class="chat-form">
        <textarea class="chat-input" rows="2" placeholder="Message this session…  (Enter to send, Shift+Enter for a newline)"></textarea>
        <button class="chat-send" type="submit">send</button>
      </form>`;

    this.logEl = this.root.querySelector('.chat-log');
    this.permEl = this.root.querySelector('.perm-queue');
    this.stateEl = this.root.querySelector('.chat-state');
    this.costEl = this.root.querySelector('.chat-cost');
    this.stopEl = this.root.querySelector('.chat-stop');
    this.formEl = this.root.querySelector('.chat-form');
    this.inputEl = this.root.querySelector('.chat-input');

    this.formEl.addEventListener('submit', (e) => { e.preventDefault(); this.#send(); });
    this.inputEl.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); this.#send(); }
    });
    this.stopEl.addEventListener('click', () => this.#stop());
  }

  /* ------------------------------------------------------------ wiring */

  async start({ cwd, model, permissionMode }) {
    const res = await fetch(this.api('/api/owned'), {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...this.headers },
      body: JSON.stringify({ cwd, model, permissionMode }),
    });
    const body = await res.json();
    if (!body.ok) { this.#note(`Could not start: ${body.reason}`); return null; }
    this.attach(body.session);
    return body.session;
  }

  attach(session) {
    this.detach();
    this.session = session;
    this.messages = [];
    this.streaming = null;
    this.lastSeq = 0;
    this.permissions = [];
    this.logEl.replaceChildren();
    this.#paintPermissions();
    this.#paintState();
    this.onSession(session);

    this.source = new EventSource(this.api(`/api/owned/${encodeURIComponent(session.sessionId)}/events`));
    this.source.addEventListener('state', (e) => {
      try { this.session = JSON.parse(e.data); } catch { return; }
      this.#paintState();
    });
    this.source.addEventListener('event', (e) => {
      let ev;
      try { ev = JSON.parse(e.data); } catch { return; }
      this.lastSeq = ev.seq;
      this.#absorb(ev.rec);
    });
    this.source.onerror = () => { this.stateEl.textContent = 'stream dropped'; };
  }

  detach() {
    if (this.source) { this.source.close(); this.source = null; }
    this.session = null;
  }

  /* --------------------------------------------------------- ingestion */

  #absorb(rec) {
    if (!rec) return;

    if (rec.type === 'stream_event') {
      const t = rec.event?.type;
      if (t === 'message_start') { this.streaming = { text: '' }; this.#paintStreaming(); }
      else if (t === 'content_block_delta' && rec.event.delta?.type === 'text_delta') {
        if (!this.streaming) this.streaming = { text: '' };
        this.streaming.text += rec.event.delta.text ?? '';
        this.#paintStreaming();
      }
      return;
    }

    // A subagent's text is forwarded with a parent id. It belongs to the graph,
    // not to this conversation — showing it here would read as the session
    // saying things it never said.
    if (rec.parent_tool_use_id) return;

    if (rec.type === 'user' && rec.message?.content) {
      const text = typeof rec.message.content === 'string'
        ? rec.message.content
        : rec.message.content.filter((c) => c?.type === 'text').map((c) => c.text).join('');
      if (text.trim()) { this.#clearPending(); this.#push({ role: 'user', text }); }
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
      if (blocks.length) this.#push({ role: 'assistant', blocks });
      return;
    }

    if (rec.type === 'result') {
      this.streaming = null;
      this.#paintStreaming();
      return;
    }

    if (rec.type === 'permissions') {
      this.permissions = rec.pending ?? [];
      this.#paintPermissions();
      return;
    }

    if (rec.type === 'fault' || rec.type === 'stderr') {
      this.#note(rec.reason ?? rec.text, 'bad');
    }
  }

  #push(msg) {
    // A question that has been answered no longer offers its options.
    for (const q of this.logEl.querySelectorAll('.quick')) q.remove();
    this.messages.push(msg);
    this.logEl.append(this.#renderMessage(msg));
    this.#paintStreaming();
    this.#scroll();
  }

  /* --------------------------------------------------------- rendering */

  #renderMessage(msg) {
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
      const quick = this.#paintQuickReplies(msg);
      if (quick) wrap.append(el('div', 'msg-spacer'), quick);
    }
    return wrap;
  }

  #paintStreaming() {
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
    this.#scroll();
  }

  // A message in flight, shown until the session echoes it back.
  #pending(text) {
    this.#clearPending();
    const wrap = el('div', 'msg msg-user msg-pending');
    wrap.append(el('div', 'msg-role', 'you'));
    const body = el('div', 'msg-body msg-text', text);
    wrap.append(body);
    this.logEl.append(wrap);
    this.#scroll();
  }

  #clearPending() {
    this.logEl.querySelector('.msg-pending')?.remove();
  }

  /* ------------------------------------------------------ quick replies
     Headless sessions are not given AskUserQuestion — measured: it is absent
     from the 78-tool list in both permission modes, while an interactive
     session has it. So there is no structured choice to render, and inventing
     one would be dressing prose up as a protocol.

     What is real: when a reply ends by offering options, those lines can be
     made clickable. The button sends that text as the next message, which is
     exactly what typing it would do — a shortcut, not a channel. */

  #quickReplies(text) { return quickReplies(text); }

  #paintQuickReplies(msg) {
    const last = msg.blocks?.filter((b) => b.kind === 'text').pop();
    const opts = this.#quickReplies(last?.text);
    if (!opts.length) return null;

    const wrap = el('div', 'quick');
    wrap.append(el('span', 'quick-hint', 'reply with'));
    for (const o of opts) {
      const b = el('button', 'quick-btn', o);
      b.addEventListener('click', () => {
        // Remove the row first: these belong to a question already answered.
        wrap.remove();
        this.inputEl.value = o;
        this.#send();
      });
      wrap.append(b);
    }
    return wrap;
  }

  /* ------------------------------------------------------- permissions */

  #paintPermissions() {
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
        b.addEventListener('click', () => this.#decide(r.toolUseId, verdict, card));
        acts.append(b);
      }
      card.append(acts);
      frag.append(card);
    }
    this.permEl.replaceChildren(frag);
  }

  async #decide(toolUseId, verdict, card) {
    for (const b of card.querySelectorAll('button')) b.disabled = true;
    const res = await fetch(
      this.api(`/api/owned/${encodeURIComponent(this.session.sessionId)}/permissions/${encodeURIComponent(toolUseId)}`),
      {
        method: 'POST',
        headers: { 'content-type': 'application/json', ...this.headers },
        body: JSON.stringify({ verdict }),
      },
    ).then((r) => r.json()).catch((e) => ({ ok: false, reason: e.message }));

    if (!res.ok) {
      this.#note(`Decision not recorded: ${res.reason}`, 'bad');
      for (const b of card.querySelectorAll('button')) b.disabled = false;
    }
  }

  #note(text, kind = '') {
    this.logEl.append(el('div', `chat-note ${kind}`, text));
    this.#scroll();
  }

  #paintState() {
    const s = this.session;
    const has = Boolean(s);
    this.formEl.hidden = !has;
    this.stopEl.hidden = !has || s.state === 'exited' || s.state === 'failed';
    // A session without a gate says so plainly. Showing only the permission
    // mode would let an ungated session look like a guarded one.
    this.stateEl.textContent = has
      ? `${s.state} · ${s.permissionMode}${s.gated ? '' : ' · NO GATE'}`
      : 'no session';
    this.stateEl.classList.toggle('ungated', has && !s.gated);
    this.stateEl.dataset.state = has ? s.state : 'none';
    this.costEl.textContent = has && s.costUsd ? `$${s.costUsd.toFixed(4)}` : '';
    this.inputEl.disabled = !has || s.state === 'exited' || s.state === 'failed';
  }

  #scroll() {
    // Only follow the tail when the reader is already at it, so scrolling back
    // through a long reply is not yanked forward by the next token.
    const nearBottom = this.logEl.scrollHeight - this.logEl.scrollTop - this.logEl.clientHeight < 120;
    if (nearBottom) this.logEl.scrollTop = this.logEl.scrollHeight;
  }

  /* ------------------------------------------------------------ actions */

  async #send() {
    const text = this.inputEl.value.trim();
    if (!text || !this.session) return;
    this.inputEl.value = '';

    // No optimistic bubble. The session is started with --replay-user-messages,
    // so it echoes what it actually received; drawing our own copy as well
    // printed every message twice. Waiting for the echo also means the log
    // shows what the session got, not what we hoped it got.
    this.#pending(text);

    const res = await fetch(this.api(`/api/owned/${encodeURIComponent(this.session.sessionId)}/message`), {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...this.headers },
      body: JSON.stringify({ text }),
    }).then((r) => r.json()).catch((e) => ({ ok: false, reason: e.message }));

    if (!res.ok) {
      this.#clearPending();
      this.#note(`Not sent: ${res.reason}`, 'bad');
    } else {
      this.session = res.session;
      this.#paintState();
    }
  }

  async #stop() {
    if (!this.session) return;
    await fetch(this.api(`/api/owned/${encodeURIComponent(this.session.sessionId)}/stop`), {
      method: 'POST',
      headers: this.headers,
    }).catch(() => {});
  }
}
