// A terminal view, without a terminal emulator.
//
// xterm.js would be a dependency, and this panel has none. What it renders
// instead is scrollback: lines with colour, carriage returns, backspaces and
// the erase sequences that ordinary command output uses. That covers
// `ls --color`, `git status`, a test run — the things people actually want to
// watch.
//
// It is not a screen. A full-screen program (vim, htop, less) paints by moving
// a cursor around a grid, and that is out of scope by design rather than by
// omission — the view says so when it sees one trying.

const SGR = {
  30: '#5c6472', 31: '#ff8a4d', 32: '#35c874', 33: '#f2a65a',
  34: '#5b8cff', 35: '#b07cf6', 36: '#26c6e6', 37: '#e6e9f0',
  90: '#8d95a3', 91: '#ff9a66', 92: '#5cd694', 93: '#f7bd7e',
  94: '#7ea3ff', 95: '#c39bf8', 96: '#5bd4ee', 97: '#ffffff',
};

const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
};

export class Term {
  constructor(root, { api, headers, terminal, onClose }) {
    this.api = api;
    this.headers = headers;
    this.terminal = terminal;
    this.onClose = onClose ?? (() => {});
    this.id = terminal.id;
    this.source = null;
    this.decoder = new TextDecoder('utf-8', { fatal: false });
    // Cells, not strings. A carriage return moves the cursor to column 0 and
    // what follows OVERWRITES from there — it does not clear the line. Modelling
    // \r as "erase" made every zsh prompt vanish, because the prompt is written
    // after a \r that a real terminal treats as a move.
    this.lines = [[]];           // [[char, color, bold], …] per line
    this.col = 0;
    this.cur = { color: null, bold: false };
    this.fullScreenSeen = false;
    this.outbox = '';
    this.flushing = false;

    this.root = root;
    this.root.className = 'term';
    this.root.innerHTML = `
      <div class="term-warn">
        <strong>No gate here.</strong>
        A command typed in this shell never reaches a PreToolUse hook, so none of the kit's
        guards see it. Work that should be checked belongs in a session, not here.
      </div>
      <pre class="term-screen" tabindex="0"></pre>
      <div class="term-foot">
        <span class="term-meta"></span>
        <button class="ghost term-close" type="button">close</button>
      </div>`;

    this.screen = this.root.querySelector('.term-screen');
    this.metaEl = this.root.querySelector('.term-meta');
    this.root.querySelector('.term-close').addEventListener('click', () => this.close());

    this.screen.addEventListener('keydown', (e) => this.#key(e));
    this.screen.addEventListener('paste', (e) => {
      e.preventDefault();
      this.#send(e.clipboardData?.getData('text') ?? '');
    });

    this.connect();
  }

  connect() {
    this.source = new EventSource(this.api(`/api/pty/${encodeURIComponent(this.id)}/stream`));
    this.source.addEventListener('out', (e) => {
      let b64;
      try { b64 = JSON.parse(e.data); } catch { return; }
      this.#feed(b64);
    });
    this.source.addEventListener('state', (e) => {
      try { this.terminal = JSON.parse(e.data); } catch { return; }
      this.#paintMeta();
    });
    this.source.onerror = () => { this.metaEl.textContent = 'stream dropped'; };
  }

  disconnect() { if (this.source) { this.source.close(); this.source = null; } }

  /* ------------------------------------------------------------ decode */

  #feed(base64) {
    let bin;
    // Malformed input must not take the view down with it: a thrown atob left
    // a blank screen with no hint of why.
    try { bin = atob(base64); } catch { this.metaEl.textContent = 'dropped a malformed frame'; return; }
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i += 1) bytes[i] = bin.charCodeAt(i);
    // stream: true so a multi-byte character split across two reads survives.
    this.#write(this.decoder.decode(bytes, { stream: true }));
  }

  #write(text) {
    for (let i = 0; i < text.length; i += 1) {
      const ch = text[i];

      if (ch === '\x1b') {
        const rest = text.slice(i);
        const csi = rest.match(/^\x1b\[([0-9;?]*)([a-zA-Z])/);
        if (csi) {
          this.#csi(csi[1], csi[2]);
          i += csi[0].length - 1;
          continue;
        }
        // OSC (window title and friends) runs to BEL or ST; drop it whole.
        const osc = rest.match(/^\x1b\][^\x07\x1b]*(\x07|\x1b\\)/);
        if (osc) { i += osc[0].length - 1; continue; }
        i += 1;                              // an escape this view does not model
        continue;
      }

      if (ch === '\n') { this.lines.push([]); this.col = 0; this.#trim(); continue; }
      if (ch === '\r') { this.col = 0; continue; }
      if (ch === '\b') { this.col = Math.max(0, this.col - 1); continue; }
      if (ch === '\x07') continue;           // bell
      if (ch === '\t') { this.#put(' '.repeat(8 - (this.col % 8))); continue; }
      if (ch < ' ') continue;                // other control bytes

      this.#put(ch);
    }
    this.#paint();
  }

  #csi(params, final) {
    if (final === 'm') {
      for (const raw of (params || '0').split(';')) {
        const n = Number(raw || 0);
        if (n === 0) this.cur = { color: null, bold: false };
        else if (n === 1) this.cur.bold = true;
        else if (n === 22) this.cur.bold = false;
        else if (n === 39) this.cur.color = null;
        else if (SGR[n]) this.cur.color = SGR[n];
      }
      return;
    }
    if (final === 'K') {                     // erase in line
      const n = Number(params || 0);
      const row = this.lines[this.lines.length - 1];
      if (n === 0) row.length = Math.min(row.length, this.col);      // to end of line
      else if (n === 1) for (let i = 0; i < this.col && i < row.length; i += 1) row[i] = [' ', null, false];
      else { row.length = 0; this.col = 0; }
      return;
    }
    if (final === 'J' && (params === '2' || params === '3')) {
      this.lines = [[]]; this.col = 0;
      return;
    }
    // Cursor addressing means the program is painting a screen, which this view
    // does not model. Say so once rather than render nonsense.
    if ('ABCDEFGHfd'.includes(final)) this.fullScreenSeen = true;
  }

  #put(s) {
    const row = this.lines[this.lines.length - 1];
    for (const ch of s) {
      while (row.length < this.col) row.push([' ', null, false]);
      row[this.col] = [ch, this.cur.color, this.cur.bold];
      this.col += 1;
    }
  }

  #trim() {
    if (this.lines.length > 4000) this.lines.splice(0, this.lines.length - 4000);
  }

  /* ------------------------------------------------------------ render */

  #paint() {
    const near = this.screen.scrollHeight - this.screen.scrollTop - this.screen.clientHeight < 60;
    const frag = document.createDocumentFragment();

    for (const row of this.lines) {
      let run = '';
      let color = null;
      let bold = false;
      const flush = () => {
        if (!run) return;
        if (!color && !bold) frag.append(document.createTextNode(run));
        else {
          const span = el('span', null, run);
          if (color) span.style.color = color;
          if (bold) span.style.fontWeight = '600';
          frag.append(span);
        }
        run = '';
      };
      for (const cell of row) {
        const [ch, c, b] = cell;
        if (c !== color || b !== bold) { flush(); color = c; bold = b; }
        run += ch;
      }
      flush();
      frag.append(document.createTextNode('\n'));
    }

    this.screen.replaceChildren(frag);
    if (near) this.screen.scrollTop = this.screen.scrollHeight;
    this.#paintMeta();
  }

  #paintMeta() {
    const t = this.terminal ?? {};
    const bits = [t.state ?? '?', `${t.cols ?? '?'}×${t.rows ?? '?'}`];
    if (t.exitCode != null) bits.push(`exit ${t.exitCode}`);
    if (this.fullScreenSeen) bits.push('full-screen program — this view shows scrollback only');
    this.metaEl.textContent = bits.join(' · ');
    this.metaEl.classList.toggle('warn', this.fullScreenSeen);
  }

  /* ------------------------------------------------------------- input */

  #key(e) {
    const map = {
      Enter: '\r', Backspace: '\x7f', Tab: '\t', Escape: '\x1b',
      ArrowUp: '\x1b[A', ArrowDown: '\x1b[B', ArrowRight: '\x1b[C', ArrowLeft: '\x1b[D',
      Home: '\x1b[H', End: '\x1b[F', Delete: '\x1b[3~',
    };
    if (e.ctrlKey && e.key.length === 1 && /[a-z]/i.test(e.key)) {
      e.preventDefault();
      this.#send(String.fromCharCode(e.key.toLowerCase().charCodeAt(0) - 96));
      return;
    }
    if (map[e.key]) { e.preventDefault(); this.#send(map[e.key]); return; }
    if (e.key.length === 1 && !e.metaKey) { e.preventDefault(); this.#send(e.key); }
  }

  // Keystrokes are queued, not fired independently. One request per character
  // with no ordering guarantee is how `ls -G` arrived as `lsG` with the dash
  // landing in the next command: separate fetches can complete out of order,
  // and a terminal is a byte stream where order is the whole meaning.
  #send(text) {
    if (!text) return;
    this.outbox = (this.outbox ?? '') + text;
    this.#flush();
  }

  async #flush() {
    if (this.flushing) return;              // the in-flight send will pick up what arrived
    this.flushing = true;
    try {
      while (this.outbox) {
        const chunk = this.outbox;
        this.outbox = '';
        const bytes = new TextEncoder().encode(chunk);
        let bin = '';
        for (const b of bytes) bin += String.fromCharCode(b);
        // Awaited: the next chunk only leaves once this one has landed.
        await fetch(this.api(`/api/pty/${encodeURIComponent(this.id)}/input`), {
          method: 'POST',
          headers: { 'content-type': 'application/json', ...this.headers },
          body: JSON.stringify({ data: btoa(bin) }),
        }).catch(() => {});
      }
    } finally {
      this.flushing = false;
    }
  }

  resize(rows, cols) {
    fetch(this.api(`/api/pty/${encodeURIComponent(this.id)}/resize`), {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...this.headers },
      body: JSON.stringify({ rows, cols }),
    }).catch(() => {});
  }

  async close() {
    await fetch(this.api(`/api/pty/${encodeURIComponent(this.id)}/close`), {
      method: 'POST', headers: this.headers,
    }).catch(() => {});
    this.disconnect();
    this.onClose(this.id);
  }
}
