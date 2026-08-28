// The orchestration canvas.
//
// HTML nodes over an SVG edge layer — the same split n8n and React Flow use,
// and for the same reason: cards are far easier to style as DOM, curves are far
// easier to draw as paths. One shared transform keeps them registered.
//
// Layout is automatic until you touch it. The moment a node is dragged its
// position is yours and is remembered per session; new agents still land on the
// auto grid around whatever you have arranged.

// Vertical flow: the session on top, everything it spawned beneath it. Depth
// reads as distance down the page, which is how delegation actually feels —
// work handed downward rather than sideways.
const NODE_W = 236;
const NODE_H = 104;
const SIBLING_GAP = 26;   // between nodes at the same depth
const DEPTH_GAP = 108;    // between one depth and the next
const MIN_K = 0.06;
const MAX_K = 2.5;
// A depth level with 105 siblings is 27,000px of one row. Past this many, the
// level wraps into a grid instead.
const MAX_PER_ROW = 8;
// Folding is driven by whether the graph fits, not by group size. A session
// with one 6-agent workflow should show all six; a session with 250 should
// arrive folded. Below this many nodes nothing is folded at all.
const COMFORTABLE_NODES = 34;

export class Canvas {
  constructor(root, { onSelect } = {}) {
    this.root = root;
    this.onSelect = onSelect ?? (() => {});
    this.view = { x: 80, y: 80, k: 1 };
    this.nodes = new Map();      // id -> data
    this.pos = new Map();        // id -> {x, y}
    this.pinned = new Set();     // ids the user has placed by hand
    this.els = new Map();        // id -> element
    this.edges = [];
    this.palette = { map: {}, unknown: '#94a3c8' };
    this.sessionKey = null;
    this.selected = null;
    this.firstRender = true;
    this.collapsed = new Set();
    // Which way delegation reads. Down is the default because a session
    // handing work to agents feels like work moving downward; sideways suits
    // deep chains better, so it is a preference rather than a decision.
    this.flow = readFlow();

    this.#build();
    this.#wire();
    this.root.dataset.flow = this.flow;
    this.root.querySelector('[data-act="flow"]').textContent = this.flow === 'down' ? '⇅' : '⇄';
  }

  #build() {
    this.root.classList.add('cv-root');
    this.root.innerHTML = `
      <div class="cv-viewport">
        <svg class="cv-edges" aria-hidden="true"><defs></defs><g class="cv-edge-g"></g></svg>
        <div class="cv-nodes"></div>
      </div>
      <div class="cv-hud">
        <button class="cv-btn" data-act="expand" title="Expand every group">⊞</button>
        <button class="cv-btn" data-act="collapse" title="Fold every group">⊟</button>
        <button class="cv-btn" data-act="flow"   title="Switch layout direction">⇅</button>
        <button class="cv-btn" data-act="fit"    title="Fit to view">⤢</button>
        <button class="cv-btn" data-act="relayout" title="Re-run auto layout">⟲</button>
        <span class="cv-zoom">100%</span>
      </div>
      <div class="cv-empty" hidden></div>`;

    this.viewport = this.root.querySelector('.cv-viewport');
    this.svg = this.root.querySelector('.cv-edges');
    this.edgeG = this.root.querySelector('.cv-edge-g');
    this.nodeLayer = this.root.querySelector('.cv-nodes');
    this.zoomLabel = this.root.querySelector('.cv-zoom');
    this.emptyEl = this.root.querySelector('.cv-empty');
  }

  /* ------------------------------------------------------------ input */

  #wire() {
    let panning = null;

    this.root.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;                 // right/middle must not pan
      if (e.target.closest('.cv-node') || e.target.closest('.cv-hud')) return;
      panning = { px: e.clientX, py: e.clientY, x: this.view.x, y: this.view.y };
      this.root.setPointerCapture(e.pointerId);
      this.root.classList.add('cv-panning');
    });

    this.root.addEventListener('pointermove', (e) => {
      if (!panning) return;
      this.view.x = panning.x + (e.clientX - panning.px);
      this.view.y = panning.y + (e.clientY - panning.py);
      this.#applyView();
    });

    const endPan = () => { panning = null; this.root.classList.remove('cv-panning'); };
    this.root.addEventListener('pointerup', endPan);
    this.root.addEventListener('pointercancel', endPan);

    this.root.addEventListener('wheel', (e) => {
      e.preventDefault();
      const r = this.root.getBoundingClientRect();
      const mx = e.clientX - r.left;
      const my = e.clientY - r.top;

      // deltaMode 1 is lines and 2 is pages; Firefox reports ~3 where Chrome
      // reports ~100, which made zoom imperceptible and pan crawl.
      const unit = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? r.height : 1;
      const dY = e.deltaY * unit;
      const dX = e.deltaX * unit;

      if (e.ctrlKey || e.metaKey || Math.abs(dY) > Math.abs(dX)) {
        const k = clamp(this.view.k * Math.exp(-dY * 0.0016), MIN_K, MAX_K);
        // Zoom about the cursor: the world point under it must not move.
        this.view.x = mx - (mx - this.view.x) * (k / this.view.k);
        this.view.y = my - (my - this.view.y) * (k / this.view.k);
        this.view.k = k;
      } else {
        this.view.x -= dX;
        this.view.y -= dY;
      }
      this.#applyView();
    }, { passive: false });

    this.root.querySelector('.cv-hud').addEventListener('click', (e) => {
      const act = e.target.closest('[data-act]')?.dataset.act;
      if (act === 'fit') this.fit();
      if (act === 'relayout') { this.pinned.clear(); this.#persist(); this.layout(true); this.fit(); }
      if (act === 'flow') this.setFlow(this.flow === 'down' ? 'right' : 'down');
      if (act === 'expand') { this.collapsed.clear(); this.#redraw(); }
      if (act === 'collapse') {
        for (const n of this.nodes.values()) if (this.hiddenCount(n.id) > 0) this.collapsed.add(n.id);
        this.#redraw();
      }
    });
  }

  #applyView() {
    const { x, y, k } = this.view;
    this.viewport.style.transform = `translate(${x}px, ${y}px) scale(${k})`;
    this.zoomLabel.textContent = `${Math.round(k * 100)}%`;
  }

  /* ----------------------------------------------------------- layout */

  /**
   * Fold the fewest, largest groups needed to make the graph readable.
   *
   * Runs once when a session opens. Small sessions are left fully open — the
   * point is to rescue the ones that do not fit, not to hide work by default.
   * Everything folded stays one click away and says how much it is holding.
   */
  #autoFold() {
    const total = this.nodes.size;
    if (total <= COMFORTABLE_NODES) return;

    const groups = [...this.nodes.values()]
      .filter((n) => n.kind === 'workflow' || (n.kind === 'agent' && this.hiddenCount(n.id) > 0))
      .map((n) => ({ id: n.id, size: this.hiddenCount(n.id) }))
      .filter((g) => g.size > 1)
      .sort((a, b) => b.size - a.size);

    let visible = total;
    for (const g of groups) {
      if (visible <= COMFORTABLE_NODES) break;
      this.collapsed.add(g.id);
      visible -= g.size;
    }
  }

  /** Nodes that are actually drawn: everything except what a folded ancestor
   *  is hiding. Hidden nodes keep their data — they are folded, not dropped. */
  visible() {
    const hiddenBy = (id) => {
      let cur = this.nodes.get(id);
      let guard = 0;
      while (cur && cur.parentId && guard++ < 24) {
        if (this.collapsed.has(cur.parentId)) return true;
        cur = this.nodes.get(cur.parentId);
      }
      return false;
    };
    return [...this.nodes.values()].filter((n) => !hiddenBy(n.id));
  }

  /** How many nodes a folded node is holding back, transitively. */
  hiddenCount(id) {
    let n = 0;
    const walk = (pid) => {
      for (const c of this.nodes.values()) {
        if (c.parentId !== pid) continue;
        n += 1;
        walk(c.id);
      }
    };
    walk(id);
    return n;
  }

  // Rows by spawn depth, columns by arrival, wrapping into a grid once a level
  // grows past a row. Deterministic, so the picture is stable across refreshes
  // instead of reshuffling on every poll.
  layout(force = false) {
    const byDepth = new Map();
    for (const n of this.visible()) {
      const d = n.kind === 'session' ? 0 : (n.spawnDepth ?? 1);
      if (!byDepth.has(d)) byDepth.set(d, []);
      byDepth.get(d).push(n);
    }

    const down = this.flow === 'down';
    let cursor = 0;   // running position along the flow axis

    for (const [, list] of [...byDepth.entries()].sort((a, b) => a[0] - b[0])) {
      // Siblings of one parent stay together, so a workflow's children do not
      // interleave with another's.
      list.sort((a, b) =>
        String(a.parentId ?? '').localeCompare(String(b.parentId ?? '')) ||
        (a.startedAt ?? 0) - (b.startedAt ?? 0) ||
        a.id.localeCompare(b.id));

      const cols = Math.min(list.length, MAX_PER_ROW);
      const rows = Math.ceil(list.length / cols);
      const rowSpan = down
        ? cols * NODE_W + (cols - 1) * SIBLING_GAP
        : cols * NODE_H + (cols - 1) * SIBLING_GAP;

      list.forEach((n, i) => {
        const col = i % cols;
        const row = Math.floor(i / cols);
        // Only a hand-placed node keeps its position. Freezing auto-placed
        // ones too was the bug: the row is re-centred as siblings arrive, so
        // nodes laid out against an older, shorter row overlapped the new
        // ones by half a card.
        if (!force && this.pinned.has(n.id)) return;
        this.pos.set(n.id, down
          ? {
            x: col * (NODE_W + SIBLING_GAP) - rowSpan / 2 + NODE_W / 2,
            y: cursor + row * (NODE_H + SIBLING_GAP),
          }
          : {
            x: cursor + row * (NODE_W + SIBLING_GAP),
            y: col * (NODE_H + SIBLING_GAP) - rowSpan / 2 + NODE_H / 2,
          });
      });

      cursor += rows * ((down ? NODE_H : NODE_W) + SIBLING_GAP) - SIBLING_GAP + DEPTH_GAP;
    }
  }

  /** Re-fit only while the layout is still automatic. Once nodes have been
   *  placed by hand, moving the view under them is not helpful. */
  fitIfUntouched() {
    if (!this.pinned.size) this.fit();
  }

  fit() {
    if (!this.pos.size) return;
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const p of this.pos.values()) {
      minX = Math.min(minX, p.x); minY = Math.min(minY, p.y);
      maxX = Math.max(maxX, p.x + NODE_W); maxY = Math.max(maxY, p.y + NODE_H);
    }
    const r = this.root.getBoundingClientRect();
    const pad = 60;
    const k = clamp(Math.min((r.width - pad * 2) / (maxX - minX), (r.height - pad * 2) / (maxY - minY), 1.2), MIN_K, MAX_K);
    this.view.k = k;
    this.view.x = (r.width - (maxX - minX) * k) / 2 - minX * k;
    this.view.y = (r.height - (maxY - minY) * k) / 2 - minY * k;
    this.#applyView();
  }

  /* -------------------------------------------------------- rendering */

  setPalette(p) { if (p?.map) this.palette = p; }

  /** Switch between top-down and left-to-right. Hand-placed nodes are cleared:
   *  positions arranged for one direction are meaningless in the other. */
  setFlow(flow) {
    if (flow !== 'down' && flow !== 'right') return;
    this.flow = flow;
    writeFlow(flow);
    this.root.dataset.flow = flow;
    this.root.querySelector('[data-act="flow"]').textContent = flow === 'down' ? '⇅' : '⇄';
    this.pinned.clear();
    this.#persist();
    this.layout(true);
    const vis = new Set(this.visible().map((n) => n.id));
    for (const [id, el] of this.els) {
      if (!vis.has(id)) { el.remove(); this.els.delete(id); }
    }
    for (const n of this.visible()) this.#renderNode(n);
    this.#renderEdges();
    this.fit();
  }

  setSession(sessionId) {
    if (this.sessionKey === sessionId) return;
    this.sessionKey = sessionId;
    this.nodes.clear(); this.pos.clear(); this.pinned.clear(); this.collapsed.clear();
    this.els.clear(); this.nodeLayer.replaceChildren(); this.edgeG.replaceChildren();
    this.selected = null;
    this.firstRender = true;
    this.#restore();
  }

  render(graph) {
    if (!graph?.nodes?.length) {
      this.emptyEl.hidden = false;
      this.emptyEl.innerHTML =
        '<strong>No agents yet</strong><div>This session has not delegated to a subagent. ' +
        'The moment it does, a node appears here.</div>';
      // els must go with the DOM. Leaving stale elements behind made
      // #renderNode believe they were still mounted, so nodes never returned.
      this.nodeLayer.replaceChildren(); this.edgeG.replaceChildren();
      this.nodes.clear(); this.els.clear(); this.pos.clear();
      this.selected = null;
      this.onSelect(null);
      return;
    }
    this.emptyEl.hidden = true;

    const seen = new Set();
    let born = false;

    for (const n of graph.nodes) {
      seen.add(n.id);
      const isNew = !this.nodes.has(n.id);
      this.nodes.set(n.id, n);
      if (isNew) born = true;
    }

    for (const id of [...this.nodes.keys()]) {
      if (!seen.has(id)) {
        this.nodes.delete(id);
        this.els.get(id)?.remove();
        this.els.delete(id);
        this.pos.delete(id);
        this.pinned.delete(id);
        // The inspector must not keep describing a node that is gone.
        if (this.selected === id) { this.selected = null; this.onSelect(null); }
      }
    }

    if (this.firstRender) this.#autoFold();
    this.layout();
    this.edges = graph.edges ?? [];

    const vis = new Set(this.visible().map((n) => n.id));
    for (const [id, el] of this.els) {
      if (!vis.has(id)) { el.remove(); this.els.delete(id); }
    }
    for (const n of this.visible()) this.#renderNode(n);
    this.#renderEdges();

    // Fit once when a session opens, so the graph is never half off-screen.
    // After that the view is the user's: re-fitting under them as agents
    // appear would yank the canvas mid-drag.
    if (this.firstRender) {
      this.firstRender = false;
      this.fit();
    } else if (born && !this.pinned.size) {
      this.fit();
    }
  }

  #renderNode(n) {
    let el = this.els.get(n.id);
    const fresh = !el;

    if (fresh) {
      el = document.createElement('div');
      el.className = 'cv-node';
      el.dataset.id = n.id;
      el.innerHTML = `
        <span class="cv-port cv-in"></span>
        <span class="cv-port cv-out"></span>
        <div class="cv-accent"></div>
        <div class="cv-head">
          <button class="cv-fold" type="button" hidden></button>
          <span class="cv-type"></span>
          <span class="cv-chip"></span>
        </div>
        <div class="cv-desc"></div>
        <div class="cv-foot"></div>`;
      this.nodeLayer.append(el);
      this.els.set(n.id, el);
      this.#makeDraggable(el, n.id);
      el.querySelector('.cv-fold').addEventListener('click', (ev) => {
        ev.stopPropagation();
        if (this.collapsed.has(n.id)) this.collapsed.delete(n.id); else this.collapsed.add(n.id);
        this.#redraw();
      });
      // A drag ends with a click on the same element. Without this guard every
      // reposition also toggled selection and fired a report fetch.
      el.addEventListener('click', () => {
        if (el.dataset.suppressClick === '1') { el.dataset.suppressClick = '0'; return; }
        // A container opens on click — the fold control is a 20px target and
        // the card is the obvious one, so a folded workflow used to look like a
        // dead end with its agents nowhere to be found.
        //
        // The session node is NOT one of those, even though it has children.
        // It is the conversation, and clicking it should open that; folding it
        // is what its caret is for. Treating every parent alike meant a click
        // on the session hid the whole graph.
        const node = this.nodes.get(n.id);
        if (node && node.kind !== 'session' && this.hiddenCount(n.id) > 0) {
          if (this.collapsed.has(n.id)) this.collapsed.delete(n.id); else this.collapsed.add(n.id);
          this.#redraw();
          return;
        }
        this.#select(n.id);
      });
      // Birth animation, only for nodes that actually just appeared.
      el.classList.add('cv-born');
      requestAnimationFrame(() => requestAnimationFrame(() => el.classList.remove('cv-born')));
    }

    const p = this.pos.get(n.id) ?? { x: 0, y: 0 };
    el.style.transform = `translate(${p.x}px, ${p.y}px)`;
    el.dataset.kind = n.kind;
    el.dataset.status = n.status ?? 'unknown';
    el.classList.toggle('cv-selected', this.selected === n.id);

    const known = n.kind !== 'agent' || Boolean(this.palette.map[n.agentType]);
    const color = n.kind === 'session' ? '#5b8cff'
      : n.kind === 'workflow' ? '#a874f5'
        : (this.palette.map[n.agentType]?.hex ?? this.palette.unknown);
    el.style.setProperty('--node-color', color);

    el.querySelector('.cv-type').textContent =
      n.kind === 'session' ? 'SESSION'
        : n.kind === 'workflow' ? 'WORKFLOW'
          : (n.agentType ?? 'unknown agent');
    // An agent type the kit never declared is marked, not quietly coloured in.
    el.querySelector('.cv-type').classList.toggle('cv-unknown', !known);

    // Fold control, shown only where there is something to fold.
    const kids = [...this.nodes.values()].filter((c) => c.parentId === n.id).length;
    const fold = el.querySelector('.cv-fold');
    if (kids) {
      fold.hidden = false;
      const folded = this.collapsed.has(n.id);
      const hidden = folded ? this.hiddenCount(n.id) : 0;
      fold.textContent = folded ? `▸ ${hidden}` : '▾';
      fold.title = folded ? `Show ${hidden} hidden node(s)` : `Fold ${kids} child node(s)`;
      el.classList.toggle('cv-folded', folded);
      // Say what a click does, since for these nodes it is not selection.
      if (n.kind === 'session') {
        el.title = 'Click to open this conversation';
        el.classList.remove('cv-container');
      } else {
        el.title = folded ? `Click to show ${hidden} node(s) inside` : 'Click to fold';
        el.classList.add('cv-container');
      }
    } else {
      fold.hidden = true;
      el.classList.remove('cv-folded', 'cv-container');
      el.title = '';
    }

    const chip = el.querySelector('.cv-chip');
    chip.textContent = n.kind === 'session' ? `${n.turns ?? 0} turns`
      : n.kind === 'workflow' ? `${n.members ?? 0} agents`
        : (n.status ?? '?');
    chip.dataset.status = n.status ?? 'unknown';

    el.querySelector('.cv-desc').textContent =
      n.kind === 'session' ? (shortPath(n.cwd) || n.sessionId)
        : n.kind === 'workflow' ? (n.workflowId ?? 'workflow run')
          : (n.description ?? '—');

    el.querySelector('.cv-foot').replaceChildren(...this.#footBits(n));
  }

  #footBits(n) {
    const bits = [];
    const add = (text, cls) => {
      const s = document.createElement('span');
      s.className = `cv-bit${cls ? ` ${cls}` : ''}`;
      s.textContent = text;
      bits.push(s);
    };

    if (n.kind === 'workflow') {
      // The breakdown is the point of a folded group: how it went, not just
      // how big it was.
      for (const [st, c] of Object.entries(n.byStatus ?? {})) add(`${c} ${st}`, st === 'running' ? 'cv-live' : null);
      if (n.tokens) add(fmtTokens(n.tokens));
      if (n.durationMs != null) add(fmtDuration(n.durationMs));
      return bits;
    }

    if (n.kind === 'session') {
      if (n.model) add(n.model);
      if (n.tokens != null) add(`${fmtTokens(n.tokens)} ctx`);
      if (n.gitBranch) add(n.gitBranch, 'cv-branch');
      return bits;
    }

    if (n.status === 'running' && n.lastTool) add(`▸ ${n.lastTool}`, 'cv-live');
    else if (n.lastTool) add(n.lastTool);
    if (n.toolCount) add(`${n.toolCount} calls`);
    if (n.tokens != null) add(fmtTokens(n.tokens));
    if (n.durationMs != null) add(fmtDuration(n.durationMs));
    if (n.errors) add(`${n.errors} err`, 'cv-err');
    return bits;
  }

  #renderEdges() {
    const paths = [];
    const vis = new Set(this.visible().map((n) => n.id));
    for (const e of this.edges) {
      if (!vis.has(e.source) || !vis.has(e.target)) continue;
      const a = this.pos.get(e.source);
      const b = this.pos.get(e.target);
      if (!a || !b) continue;

      // Out of the parent's outgoing port, into the child's incoming one.
      // Control points are pushed along the flow axis so siblings fan out
      // instead of stacking on one line.
      const down = this.flow === 'down';
      const x1 = down ? a.x + NODE_W / 2 : a.x + NODE_W;
      const y1 = down ? a.y + NODE_H      : a.y + NODE_H / 2;
      const x2 = down ? b.x + NODE_W / 2 : b.x;
      const y2 = down ? b.y               : b.y + NODE_H / 2;
      const d = Math.max(46, Math.abs((down ? y2 - y1 : x2 - x1)) * 0.55);

      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('d', down
        ? `M ${x1} ${y1} C ${x1} ${y1 + d}, ${x2} ${y2 - d}, ${x2} ${y2}`
        : `M ${x1} ${y1} C ${x1 + d} ${y1}, ${x2 - d} ${y2}, ${x2} ${y2}`);
      path.setAttribute('class', 'cv-edge');
      const target = this.nodes.get(e.target);
      path.dataset.status = target?.status ?? 'unknown';
      path.style.stroke = this.palette.map[target?.agentType]?.hex ?? this.palette.unknown;
      paths.push(path);
    }
    this.edgeG.replaceChildren(...paths);

    // The SVG plane must cover every node, including negative coordinates.
    let minX = 0, minY = 0, maxX = 0, maxY = 0;
    for (const p of this.pos.values()) {
      minX = Math.min(minX, p.x - 100); minY = Math.min(minY, p.y - 100);
      maxX = Math.max(maxX, p.x + NODE_W + 100); maxY = Math.max(maxY, p.y + NODE_H + 100);
    }
    this.svg.setAttribute('viewBox', `${minX} ${minY} ${maxX - minX} ${maxY - minY}`);
    this.svg.style.left = `${minX}px`;
    this.svg.style.top = `${minY}px`;
    this.svg.style.width = `${maxX - minX}px`;
    this.svg.style.height = `${maxY - minY}px`;
  }

  /** Re-lay out and repaint after folding changed what is visible. */
  #redraw() {
    this.layout(true);
    const vis = new Set(this.visible().map((x) => x.id));
    for (const [id, el] of this.els) if (!vis.has(id)) { el.remove(); this.els.delete(id); }
    for (const v of this.visible()) this.#renderNode(v);
    this.#renderEdges();
    // Unfolding 105 agents puts most of them off-screen; pull the view back to
    // what was just revealed, unless the user has arranged things by hand.
    this.fitIfUntouched();
  }

  /** Drop the selection without pretending a node was clicked. */
  clearSelection() {
    this.selected = null;
    for (const el of this.els.values()) el.classList.remove('cv-selected');
  }

  #select(id) {
    this.selected = this.selected === id ? null : id;
    for (const [nid, el] of this.els) el.classList.toggle('cv-selected', nid === this.selected);
    this.onSelect(this.selected ? this.nodes.get(this.selected) : null);
  }

  /* ---------------------------------------------------------- dragging */

  #makeDraggable(el, id) {
    let drag = null;

    el.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      e.stopPropagation();                       // do not pan the canvas too
      const p = this.pos.get(id) ?? { x: 0, y: 0 };
      drag = { px: e.clientX, py: e.clientY, x: p.x, y: p.y, moved: false };
      el.setPointerCapture(e.pointerId);
      el.classList.add('cv-dragging');
    });

    el.addEventListener('pointermove', (e) => {
      if (!drag) return;
      const dx = (e.clientX - drag.px) / this.view.k;
      const dy = (e.clientY - drag.py) / this.view.k;
      if (Math.abs(dx) > 2 || Math.abs(dy) > 2) drag.moved = true;
      this.pos.set(id, { x: drag.x + dx, y: drag.y + dy });
      el.style.transform = `translate(${drag.x + dx}px, ${drag.y + dy}px)`;
      this.#renderEdges();
    });

    const stop = () => {
      if (!drag) return;
      if (drag.moved) { this.pinned.add(id); this.#persist(); el.dataset.suppressClick = '1'; }
      drag = null;
      el.classList.remove('cv-dragging');
    };
    el.addEventListener('pointerup', stop);
    el.addEventListener('pointercancel', stop);
  }

  /* -------------------------------------------------------- persistence
     Hand-placed positions are the user's work and outlive a refresh. Storage
     can be unavailable (private windows, blocked site data), so every access
     is guarded and the canvas falls back to auto layout. */

  #key() { return `csk-studio-layout:${this.flow}:${this.sessionKey}`; }

  #persist() {
    if (!this.sessionKey) return;   // no session, nothing to key the layout to
    try {
      const out = {};
      for (const id of this.pinned) {
        const p = this.pos.get(id);
        if (p) out[id] = [Math.round(p.x), Math.round(p.y)];
      }
      localStorage.setItem(this.#key(), JSON.stringify(out));
    } catch { /* positions stay for this page view only */ }
  }

  #restore() {
    if (!this.sessionKey) return;
    try {
      const raw = localStorage.getItem(this.#key());
      if (!raw) return;
      for (const [id, [x, y]] of Object.entries(JSON.parse(raw))) {
        this.pos.set(id, { x, y });
        this.pinned.add(id);
      }
    } catch { /* start from auto layout */ }
  }
}

/* -------------------------------------------------------------- helpers */

function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }

function readFlow() {
  try {
    const v = localStorage.getItem('csk-studio-flow');
    return v === 'right' ? 'right' : 'down';
  } catch { return 'down'; }
}

function writeFlow(v) {
  try { localStorage.setItem('csk-studio-flow', v); } catch { /* blocked storage */ }
}

function fmtTokens(t) {
  if (t == null) return '';
  if (t < 1000) return `${t}`;
  if (t < 1_000_000) return `${(t / 1000).toFixed(t < 10_000 ? 1 : 0)}k`;
  return `${(t / 1_000_000).toFixed(2)}M`;
}

function fmtDuration(ms) {
  const s = Math.round(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  return m < 60 ? `${m}m ${s % 60}s` : `${Math.floor(m / 60)}h ${m % 60}m`;
}

function shortPath(p, max = 40) {
  if (!p) return '';
  const home = p.match(/^\/(Users|home)\/[^/]+/);
  const s = home ? `~${p.slice(home[0].length)}` : p;
  if (s.length <= max) return s;
  const keep = Math.floor((max - 1) / 2);
  return `${s.slice(0, keep)}…${s.slice(-keep)}`;
}
