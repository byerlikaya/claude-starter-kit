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
const SIBLING_GAP = 26;   // between nodes of the same kind
const GROUP_GAP = 64;     // between one kind and the next
const DEPTH_GAP = 128;    // between one depth and the next
const MAX_PER_GROUP_ROW = 4;

// Kinds that are not agents still need a colour, and the card and the edge into
// it have to agree — a branch you can trace by colour stops working the moment
// the two are computed in different places. This is that one place.
const KIND_COLOR = { session: '#5b8cff', workflow: '#a874f5' };

// Raw status strings, folded into the handful of things motion has to say.
// `killed` and `stopped` come straight off the transcript and mean the same
// thing to a reader as `failed`: this branch did not finish on its own terms.
const FLOW_STATE = {
  running: 'live',
  starting: 'waking',
  done: 'done',
  failed: 'failed',
  killed: 'failed',
  stopped: 'failed',
  ended: 'quiet',
  stale: 'quiet',
  session: 'root',
};

// How long an arriving edge takes to draw itself toward its new node. Short on
// purpose: this is a status panel, and anything a viewer has to wait through
// is a cost they pay on every spawn.
const DRAW_MS = 300;

// Above this many edges in motion at once the canvas stops moving them and
// shows the same states standing still.
//
// Two reasons, and the second is the one that decided the number. A dash
// travelling along a stroke is a paint-driven animation, not a composited one,
// so its cost scales with how many strokes are in motion rather than with how
// many exist. And 200 flowing lines carry less than 20 do — past a certain
// density motion stops reading as direction and starts reading as noise, which
// is the same reason the pulse is restrained rather than loud.
const MOTION_BUDGET = 60;
// Marks, so a card says what kind of thing it is before it is read.
//
// The kit's own is the three-bar mark from assets/icon.svg, redrawn here rather
// than fetched — one <img> per node would be a request per node, and the shape
// is four rectangles.
//
// Claude's built-in agents get a neutral burst, NOT Anthropic's logo. Shipping
// a vendor's trademark inside an MIT repo, on cards the panel draws itself,
// claims a relationship this project does not have. The shape reads as "not
// ours" without borrowing anyone's mark.
const MARKS = {
  // The kit's own mark, from assets/icon.svg: three rotated bars, redrawn as
  // rectangles rather than fetched — one image request per node, for a shape
  // that is three rectangles, is a poor trade. Its own palette, not the node's,
  // so it looks like the mark rather than like the card.
  kit: '<g transform="rotate(20 8 8)">'
    + '<rect x="3.4" y="2.3" width="2.2" height="11.4" rx="1.1" fill="#E5E7FB"/>'
    + '<rect x="6.8" y="2.3" width="2.2" height="11.4" rx="1.1" fill="#B9BEF9"/>'
    + '<rect x="10.2" y="1.9" width="2.5" height="12.2" rx="1.25" fill="#A78BFA"/></g>',
  // Claude's mark, in Claude's colour. Rays of uneven length and spacing —
  // the irregularity is what makes it read as the mark rather than as a star.
  builtin: '<g stroke="#D97757" stroke-width="1.45" stroke-linecap="round" fill="none"><path d="M8.00 6.50L8.00 1.10"/><path d="M7.21 6.73L5.03 3.25"/><path d="M6.65 7.34L2.07 5.11"/><path d="M6.51 8.16L2.83 8.54"/><path d="M6.82 8.92L2.56 12.25"/><path d="M7.49 9.41L6.15 13.07"/><path d="M8.31 9.47L9.37 14.46"/><path d="M9.04 9.08L11.61 11.74"/><path d="M9.46 8.36L14.70 9.67"/><path d="M9.43 7.54L13.33 6.27"/><path d="M8.88 6.79L11.76 2.82"/></g>',
  workflow: '<g fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round">'
    + '<path d="M3 4.5h10M3 8h10M3 11.5h10"/></g>',
  session: '<g fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">'
    + '<path d="M3.5 4.5l3 3-3 3M8.5 11.5h4"/></g>',
};

/** Element helper. `el` is used as a local name for a node all over this file,
 *  so the helper is named for what it does instead. */
function mk(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
}

const MIN_K = 0.06;
const MAX_K = 2.5;
// Padding fit() leaves around the graph, on each side. Named because the band
// search below has to score candidates with the same arithmetic fit() uses; two
// copies of the number is two numbers that drift.
const FIT_PAD = 60;
// The largest fit() will scale up to. Same reason.
const FIT_MAX = 1.2;

/* --------------------------------------------------------------- reading
   Three readings of the same picture, chosen by how much of a card would
   actually survive on screen.

   The idea is not "hide things when zoomed out" — hiding alone still leaves an
   unreadable title. What survives is redrawn at a constant *screen* size: its
   world font-size grows as the canvas shrinks. That costs one custom property
   and no per-node JS, which is why a band change is O(1) in node count. */

// 13px .cv-desc clears 9px on screen at 9/13 = 0.692.
const LOD_NEAR = 0.70;
// A screen-constant 11px mono line stops fitting the card: the content box is
// 204x80 world px (236-18-14, 104-12-12); six mono chars at a 6.6px advance
// need 40 screen px, so 204*k >= 40 => k >= 0.196. The horizontal bound binds.
const LOD_FAR = 0.20;
// A trackpad tremor must not reband 250 cards.
const LOD_HYST = 0.025;
// Past this many drawn nodes, words are the noise floor. Count is the axis that
// says "there are too many words on this canvas"; zoom is the axis that says
// "the words are too small". Both have the same remedy, so both pick `far`.
const LABEL_BUDGET = 40;
// What the HUD calls each reading, so a viewer knows detail was traded rather
// than lost and that one wheel notch brings it back.
const LOD_WORD = { near: 'detail', mid: 'titles', far: 'marks' };
const LOD_RANK = { far: 0, mid: 1, near: 2 };

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
    this.edgeEls = new Map();    // edge key -> <path>
    this.edges = [];
    // Ids that arrived on the last poll. An edge into one of these draws
    // itself; every other edge is left alone, so unfolding a group of 105 does
    // not set 105 animations running at once.
    this.newborn = new Set();
    this.palette = { map: {}, unknown: '#94a3c8' };
    this.sessionKey = null;
    this.selected = null;
    this.firstRender = true;
    this.collapsed = new Set();
    // How many nodes the last layout actually placed. The reading band is a
    // function of this as well as of zoom, and it is cached rather than
    // recounted because applyView() runs on every frame of a pan.
    this.drawn = 0;
    // Which way delegation reads. Down is the default because a session
    // handing work to agents feels like work moving downward; sideways suits
    // deep chains better, so it is a preference rather than a decision.
    this.flow = readFlow();

    this.#build();
    this.#wire();
    // #renderNode runs before the first fit() inside render(), so without this
    // there is one paint with --k unset, and every calc() that reads it drops.
    this.applyView();
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
        <button class="cv-btn cv-alarm" data-act="failed" title="Go to the next failed branch" hidden>⚠</button>
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
    this.alarmBtn = this.root.querySelector('.cv-alarm');
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
      this.applyView();
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
      this.applyView();
    }, { passive: false });

    this.root.querySelector('.cv-hud').addEventListener('click', (e) => {
      const act = e.target.closest('[data-act]')?.dataset.act;
      if (act === 'fit') this.fit();
      if (act === 'relayout') { this.pinned.clear(); this.#persist(); this.layout(true); this.fit(); }
      if (act === 'flow') this.setFlow(this.flow === 'down' ? 'right' : 'down');
      if (act === 'failed') this.gotoFailed();
      if (act === 'expand') { this.collapsed.clear(); this.#redraw(); }
      if (act === 'collapse') {
        for (const n of this.nodes.values()) if (this.hiddenCount(n.id) > 0) this.collapsed.add(n.id);
        this.#redraw();
      }
    });
  }

  /**
   * Turn `view` into pixels. Public because it is the single place that does
   * so — the wheel, the pan, fit() and the constructor all come through here,
   * and so does anything that wants to drive the view without a pointer.
   *
   * It publishes two things the stylesheet reads: the scale, so a surviving
   * label can be drawn at a constant *screen* size, and the reading band. A
   * band change never re-lays out, re-fits or re-renders a node — every card
   * responds through the cascade, which is what keeps this O(1) in node count
   * and makes it impossible for a band to move the world that decides it.
   */
  applyView() {
    const { x, y, k } = this.view;
    this.viewport.style.transform = `translate(${x}px, ${y}px) scale(${k})`;
    this.root.style.setProperty('--k', String(k));
    const band = this.#band(k);
    this.root.dataset.lod = band;
    // Say when it was the crowd rather than the zoom that traded the words
    // away, because the remedy for that one is folding, not scrolling.
    const crowded = band === 'far' && k >= LOD_FAR;
    this.zoomLabel.textContent = `${Math.round(k * 100)}% · ${LOD_WORD[band]}`
      + (crowded ? ` (${this.drawn})` : '');
  }

  /** Which reading the canvas is in. Hysteresis is applied only on the way
   *  *up*, so a jitter sitting on a boundary cannot reband 250 cards twice a
   *  second; dropping detail is always immediate. */
  #band(k) {
    if (this.drawn > LABEL_BUDGET) return 'far';
    const now = LOD_RANK[this.root.dataset.lod] ?? LOD_RANK.near;
    const near = LOD_NEAR + (now < LOD_RANK.near ? LOD_HYST : 0);
    const mid = LOD_FAR + (now < LOD_RANK.mid ? LOD_HYST : 0);
    return k >= near ? 'near' : k >= mid ? 'mid' : 'far';
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

  // Depth downward, kind across. Eight agents in one undifferentiated fan told
  // the reader nothing about which were alike; grouped by type, with the type
  // named above its group, the same eight read as three Explores, a Plan, and
  // so on. Groups keep their own small grid so one large kind does not push
  // every other kind off the screen.
  //
  // A depth level then WRAPS. Laying every group of a depth in one unbounded
  // row made the world a ribbon — 8624x1246 at 250 nodes — and fit() is
  // width-bound at every size against a ribbon, so twelve agents already
  // arrived at 34% and the type line was 3.7px on screen. The level is packed
  // into bands instead, and how many groups go in a band is chosen by the same
  // arithmetic fit() uses, so the layout optimises the number the reader
  // actually feels.
  //
  // Nothing here reads this.view. Positions are never a function of zoom —
  // that invariant is what makes the reading bands oscillation-proof.
  layout(force = false) {
    const byDepth = new Map();
    let drawn = 0;
    for (const n of this.visible()) {
      const d = n.kind === 'session' ? 0 : (n.spawnDepth ?? 1);
      if (!byDepth.has(d)) byDepth.set(d, []);
      byDepth.get(d).push(n);
      drawn += 1;
    }
    this.drawn = drawn;

    const down = this.flow === 'down';
    const NODE_A = down ? NODE_W : NODE_H;            // size across a band
    const NODE_B = down ? NODE_H : NODE_W;            // size along the depth axis

    // Read once per call. The band search needs the pane, and asking for it per
    // group would be one forced layout per group on a 250-node graph.
    const r = this.root.getBoundingClientRect();
    const paneW = Math.max(2 * FIT_PAD + NODE_A, r.width || 800);
    const paneH = Math.max(2 * FIT_PAD + NODE_B, r.height || 600);

    const levels = [...byDepth.entries()].sort((a, b) => a[0] - b[0]).map(([, list]) => {
      // One group per kind. Workflows are their own kind; the session is alone
      // at its depth and needs no label.
      const groups = new Map();
      for (const n of list) {
        const key = n.kind === 'session' ? '\u0000session'
          : n.kind === 'workflow' ? 'workflow'
            : (n.agentType ?? 'unknown');
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(n);
      }

      // Biggest kinds first, then alphabetically, so the picture is stable
      // across refreshes rather than following arrival order.
      const ordered = [...groups.entries()].sort(
        (a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0]),
      );

      // Measure first: every band is centred on its own width, so each group's
      // span has to be known before any node is placed.
      const measured = ordered.map(([key, members]) => {
        const cols = groupCols(members.length, NODE_A, NODE_B);
        const rows = Math.ceil(members.length / cols);
        return { key, members, cols, rows, span: cols * NODE_A + (cols - 1) * SIBLING_GAP };
      });
      return { measured, plans: bandPlans(measured, NODE_B) };
    });

    // Pick a packing per level against the fit of the WHOLE graph, not of the
    // level alone. Scored alone, a tall single-column level always wins — it is
    // narrow, and it is only the other levels stacked under it that make that a
    // bad trade. Levels are few and each has a handful of candidates, so a few
    // rounds of coordinate descent over the real objective is cheap and lands
    // on the same answer every time.
    const fitOf = (choice) => {
      let w = 0;
      let h = 0;
      for (let i = 0; i < levels.length; i += 1) {
        const p = levels[i].plans[choice[i]];
        w = Math.max(w, p.w);
        h += p.h;
      }
      h += Math.max(0, levels.length - 1) * DEPTH_GAP;
      return clamp(Math.min((paneW - 2 * FIT_PAD) / w, (paneH - 2 * FIT_PAD) / h, FIT_MAX), MIN_K, MAX_K);
    };
    const choice = levels.map((L) => {
      let best = 0;
      for (let i = 1; i < L.plans.length; i += 1) {
        if (soloFit(L.plans[i], paneW, paneH) > soloFit(L.plans[best], paneW, paneH) + 1e-9) best = i;
      }
      return best;
    });
    for (let round = 0; round < 4; round += 1) {
      let moved = false;
      for (let i = 0; i < levels.length; i += 1) {
        let bestJ = choice[i];
        let bestK = fitOf(choice);
        for (let j = 0; j < levels[i].plans.length; j += 1) {
          if (j === choice[i]) continue;
          const trial = choice.slice();
          trial[i] = j;
          const k = fitOf(trial);
          if (k > bestK + 1e-9) { bestK = k; bestJ = j; }
        }
        if (bestJ !== choice[i]) { choice[i] = bestJ; moved = true; }
      }
      if (!moved) break;
    }

    let cursor = 0;                                   // position along the depth axis
    levels.forEach((L, li) => {
      const { per } = L.plans[choice[li]];
      let bandTop = cursor;
      for (let i = 0; i < L.measured.length; i += per) {
        const band = L.measured.slice(i, i + per);
        // Each band is centred on its own width rather than on the widest one,
        // so a level does not look ragged.
        let across = -(band.reduce((t, g) => t + g.span, 0) + (band.length - 1) * GROUP_GAP) / 2;
        let rows = 0;
        for (const g of band) {
          g.members.sort((a, b) => (a.startedAt ?? 0) - (b.startedAt ?? 0) || a.id.localeCompare(b.id));
          g.members.forEach((n, idx) => {
            const col = idx % g.cols;
            const row = Math.floor(idx / g.cols);
            const a = across + col * (NODE_A + SIBLING_GAP);
            const b = bandTop + row * (NODE_B + SIBLING_GAP);
            // Only a hand-placed node keeps its position. Freezing auto-placed
            // ones too was the bug: the row is re-centred as siblings arrive, so
            // nodes laid out against an older, shorter row overlapped the new
            // ones by half a card.
            if (!force && this.pinned.has(n.id)) return;
            this.pos.set(n.id, down ? { x: a, y: b } : { x: b, y: a });
          });
          across += g.span + GROUP_GAP;
          rows = Math.max(rows, g.rows);
        }
        bandTop += rows * (NODE_B + SIBLING_GAP) - SIBLING_GAP + GROUP_GAP;
      }
      // The next depth clears the whole stack of bands, not one row of it.
      cursor = bandTop - GROUP_GAP + DEPTH_GAP;
    });
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
    const pad = FIT_PAD;
    const k = clamp(Math.min((r.width - pad * 2) / (maxX - minX), (r.height - pad * 2) / (maxY - minY), FIT_MAX), MIN_K, MAX_K);
    this.view.k = k;
    this.view.x = (r.width - (maxX - minX) * k) / 2 - minX * k;
    this.view.y = (r.height - (maxY - minY) * k) / 2 - minY * k;
    this.applyView();
  }

  /* -------------------------------------------------------- rendering */

  setPalette(p) { if (p?.map) this.palette = p; }

  /** The one colour a node answers to. The card paints itself with it and the
   *  edge into the card is stroked with it, which is what makes a branch
   *  traceable by colour alone. */
  nodeColor(n) {
    if (!n) return this.palette.unknown;
    return KIND_COLOR[n.kind] ?? this.palette.map[n.agentType]?.hex ?? this.palette.unknown;
  }

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
    this.#syncHud();
  }

  setSession(sessionId) {
    if (this.sessionKey === sessionId) return;
    this.sessionKey = sessionId;
    this.nodes.clear(); this.pos.clear(); this.pinned.clear(); this.collapsed.clear();
    this.els.clear(); this.nodeLayer.replaceChildren(); this.edgeG.replaceChildren();
    this.edgeEls.clear(); this.newborn.clear();
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
      this.edgeEls.clear(); this.newborn.clear();
      this.selected = null;
      this.drawn = 0;
      this.onSelect(null);
      this.applyView();
      this.#syncHud();
      return;
    }
    this.emptyEl.hidden = true;

    const seen = new Set();
    let born = false;

    for (const n of graph.nodes) {
      seen.add(n.id);
      const isNew = !this.nodes.has(n.id);
      this.nodes.set(n.id, n);
      if (isNew) { born = true; this.newborn.add(n.id); }
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
    // Neither branch above is guaranteed to run, and both the drawn count and
    // the failure count can have changed on any poll.
    this.applyView();
    this.#syncHud();
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
          <svg class="cv-mark" viewBox="0 0 16 16" aria-hidden="true"></svg>
          <span class="cv-type"></span>
          <span class="cv-chip"></span>
        </div>
        <div class="cv-desc"></div>
        <div class="cv-foot"></div>`;
      // The card's children never change identity, so they are found once per
      // element instead of six times per element per poll — at 250 nodes on a
      // 2s poll that is 45,000 selector runs a minute for a fixed answer.
      el.parts = {
        fold: el.querySelector('.cv-fold'),
        mark: el.querySelector('.cv-mark'),
        type: el.querySelector('.cv-type'),
        chip: el.querySelector('.cv-chip'),
        desc: el.querySelector('.cv-desc'),
        foot: el.querySelector('.cv-foot'),
      };
      this.nodeLayer.append(el);
      this.els.set(n.id, el);
      this.#makeDraggable(el, n.id);
      el.parts.fold.addEventListener('click', (ev) => {
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
    el.style.setProperty('--node-color', this.nodeColor(n));
    // What motion says about this node, separated from the raw status so that
    // `killed` and `stopped` read like the failures they are instead of like
    // two more words nothing has a rule for.
    el.dataset.state = FLOW_STATE[n.status] ?? 'unknown';

    const typeText = n.kind === 'session' ? 'SESSION'
      : n.kind === 'workflow' ? 'WORKFLOW'
        : (n.agentType ?? 'unknown agent');
    const typeEl = el.parts.type;
    typeEl.textContent = typeText;
    // Two names the stylesheet draws counter-scaled, so that what survives a
    // zoom-out is drawn at a constant size on the reader's screen rather than
    // shrunk into grey. The far one carries the running tool, because "what is
    // it doing" is exactly that string.
    typeEl.dataset.short = n.kind === 'agent' ? shortType(n.agentType ?? 'unknown') : typeText;
    typeEl.dataset.far = typeEl.dataset.short
      + (n.status === 'running' && n.lastTool ? ` \u25b8 ${n.lastTool}` : '');

    // Whose agent this is, at a glance. The palette says where a type was
    // declared; anything it does not know is drawn as unknown rather than
    // guessed into one camp or the other.
    const source = n.kind === 'session' ? 'session'
      : n.kind === 'workflow' ? 'workflow'
        : (this.palette.map[n.agentType]?.source ?? null);
    const markEl = el.parts.mark;
    markEl.innerHTML = MARKS[source === 'kit' ? 'kit' : source === 'builtin' ? 'builtin' : source] ?? MARKS.builtin;
    markEl.classList.toggle('cv-mark-unknown', n.kind === 'agent' && !source);
    markEl.setAttribute('aria-label', source === 'kit' ? 'kit agent' : 'built-in agent');
    el.dataset.source = source ?? 'unknown';
    // An agent type the kit never declared is marked, not quietly coloured in.
    typeEl.classList.toggle('cv-unknown', !known);

    // Fold control, shown only where there is something to fold.
    const kids = [...this.nodes.values()].filter((c) => c.parentId === n.id).length;
    const fold = el.parts.fold;
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

    const chip = el.parts.chip;
    chip.textContent = n.kind === 'session' ? `${n.turns ?? 0} turns`
      : n.kind === 'workflow' ? `${n.members ?? 0} agents`
        : (n.status ?? '?');
    chip.dataset.status = n.status ?? 'unknown';

    const desc = n.kind === 'session' ? (shortPath(n.cwd) || n.sessionId)
      : n.kind === 'workflow' ? (n.workflowId ?? 'workflow run')
        : (n.description ?? '—');
    el.parts.desc.textContent = desc;

    el.parts.foot.replaceChildren(...this.#footBits(n));

    // The card's whole name, at every reading. The two smaller readings drop
    // the type line to font-size:0 and redraw it from a pseudo-element, and
    // neither of those is reliably exposed to a screen reader — so without this
    // the far band would ship as an accessibility regression rather than as a
    // rendering change.
    el.setAttribute('aria-label', `${typeText}, ${n.status ?? 'unknown'}${desc ? `, ${desc}` : ''}`);
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

  // Edges are kept and updated, never rebuilt.
  //
  // Replacing the whole layer each pass was the reason motion could not live
  // here: a CSS animation restarts when its element leaves the document, so a
  // travelling dash jumped back to its start on every 2s poll and on every
  // frame of a drag. Reusing the path element is what lets the stylesheet own
  // the animation and JS own nothing but geometry.
  #renderEdges() {
    const vis = new Set(this.visible().map((n) => n.id));
    const alive = new Set();
    let moving = 0;

    for (const e of this.edges) {
      if (!vis.has(e.source) || !vis.has(e.target)) continue;
      const a = this.pos.get(e.source);
      const b = this.pos.get(e.target);
      if (!a || !b) continue;

      const key = `${e.source}\u0000${e.target}`;
      alive.add(key);

      // Out of the parent's outgoing port, into the child's incoming one.
      // Control points are pushed along the flow axis so siblings fan out
      // instead of stacking on one line.
      const down = this.flow === 'down';
      const x1 = down ? a.x + NODE_W / 2 : a.x + NODE_W;
      const y1 = down ? a.y + NODE_H      : a.y + NODE_H / 2;
      const x2 = down ? b.x + NODE_W / 2 : b.x;
      const y2 = down ? b.y               : b.y + NODE_H / 2;
      const d = Math.max(46, Math.abs((down ? y2 - y1 : x2 - x1)) * 0.55);

      let path = this.edgeEls.get(key);
      const fresh = !path;
      if (fresh) {
        path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        path.setAttribute('class', 'cv-edge');
        this.edgeEls.set(key, path);
        this.edgeG.append(path);
      }

      path.setAttribute('d', down
        ? `M ${x1} ${y1} C ${x1} ${y1 + d}, ${x2} ${y2 - d}, ${x2} ${y2}`
        : `M ${x1} ${y1} C ${x1 + d} ${y1}, ${x2 - d} ${y2}, ${x2} ${y2}`);

      // The draw-in has to cover the whole curve without measuring it —
      // getTotalLength() forces a synchronous layout, once per edge. A cubic is
      // never longer than its control polygon, so that bound is computed from
      // the numbers already in hand and handed to CSS as a length.
      path.style.setProperty('--edge-len', `${Math.ceil(Math.hypot(x2 - x1, y2 - y1) + 2 * d)}px`);

      const target = this.nodes.get(e.target);
      const parent = this.nodes.get(e.source);
      const state = FLOW_STATE[target?.status] ?? 'unknown';
      path.dataset.status = target?.status ?? 'unknown';
      path.dataset.state = state;

      // A workflow's twelve members are one dispatch, not twelve unrelated
      // decisions. Blending each member's own colour toward the container's
      // pulls the whole bundle into one hue family while still leaving every
      // line traceable back to the card it feeds.
      const member = parent?.kind === 'workflow';
      path.dataset.group = member ? 'member' : 'spawn';
      const own = this.nodeColor(target);
      path.style.stroke = state === 'failed' ? 'var(--cv-fail)'
        : member ? mixHex(own, this.nodeColor(parent), 0.45)
          : own;

      if (state === 'live' || state === 'waking') moving += 1;

      // Only an edge into a node that just arrived draws itself. Unfolding a
      // group is not an arrival, so opening a 105-agent workflow reveals it
      // rather than performing it.
      if (fresh && this.newborn.has(e.target)) {
        path.classList.add('cv-drawing');
        setTimeout(() => path.classList.remove('cv-drawing'), DRAW_MS);
      }
    }

    for (const [key, path] of this.edgeEls) {
      if (alive.has(key)) continue;
      path.remove();
      this.edgeEls.delete(key);
    }
    this.newborn.clear();

    // Only travelling strokes are counted. The card pulse rides the same flag,
    // but it animates opacity on a pseudo-element and costs the compositor
    // almost nothing, so charging a running agent twice — once for its edge and
    // once for its card — would halve the budget for no reason anyone measured.
    this.root.dataset.motion = moving > MOTION_BUDGET ? 'still' : 'flow';

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
    // fitIfUntouched() is a no-op once a node has been dragged, and folding is
    // exactly the thing that changes the drawn count the reading band is a
    // function of. Republish it either way.
    this.applyView();
    this.#syncHud();
  }

  /** What the HUD can say only after a render: how many branches went wrong.
   *  With three red marks among 250 you can still be panned away from them. */
  #syncHud() {
    const bad = this.#failedIds();
    this.alarmBtn.hidden = bad.length === 0;
    this.alarmBtn.textContent = `\u26a0 ${bad.length}`;
    this.alarmBtn.title = bad.length === 1
      ? 'Go to the failed branch'
      : `Go to the next of ${bad.length} failed branches`;
  }

  /** Drawn nodes that did not finish on their own terms, in a stable order so
   *  that stepping through them twice visits them in the same sequence. */
  #failedIds() {
    return this.visible()
      .filter((n) => FLOW_STATE[n.status] === 'failed')
      .map((n) => n.id)
      .sort((a, b) => a.localeCompare(b));
  }

  /**
   * Step to the next failed branch, wrapping. Public for the same reason
   * applyView() is: the HUD button is its only caller in the page, and it has
   * to be drivable without a pointer.
   *
   * Selection is set rather than toggled — #select() flips a node that is
   * already chosen, which would make the button a no-op the second time it is
   * pressed on a lone failure.
   */
  gotoFailed() {
    const bad = this.#failedIds();
    if (!bad.length) return;
    const at = bad.indexOf(this.selected);
    const id = bad[(at + 1) % bad.length];
    this.#centreOn(id);
    this.selected = id;
    for (const [nid, el] of this.els) el.classList.toggle('cv-selected', nid === id);
    this.onSelect(this.nodes.get(id) ?? null);
  }

  /** Put one node in the middle of the pane without changing the zoom — the
   *  reading band must not move because the view panned. */
  #centreOn(id) {
    const p = this.pos.get(id);
    if (!p) return;
    const r = this.root.getBoundingClientRect();
    this.view.x = r.width / 2 - (p.x + NODE_W / 2) * this.view.k;
    this.view.y = r.height / 2 - (p.y + NODE_H / 2) * this.view.k;
    this.applyView();
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

/**
 * How many columns one kind's own grid gets.
 *
 * Four until the group is big enough that four columns would make a tower —
 * a session that spawned 250 agents of a single type is 63 rows deep at four
 * across, and no amount of band packing rescues one group. Past ~36 members the
 * count goes square-ish in the flow's own aspect instead. Below that this
 * returns exactly what MAX_PER_GROUP_ROW always returned.
 */
function groupCols(count, nodeA, nodeB) {
  const square = Math.ceil(Math.sqrt(Math.max(1, count) * (nodeB / nodeA)));
  return Math.min(count, Math.max(MAX_PER_GROUP_ROW, square));
}

/**
 * Every way a depth level's groups can be packed into bands, and the box each
 * packing needs. `per` is groups per band; bands stack along the depth axis.
 */
function bandPlans(measured, nodeB) {
  const plans = [];
  for (let per = 1; per <= Math.max(1, measured.length); per += 1) {
    let w = 0;
    let h = 0;
    let bands = 0;
    for (let i = 0; i < measured.length; i += per) {
      const band = measured.slice(i, i + per);
      w = Math.max(w, band.reduce((t, g) => t + g.span, 0) + (band.length - 1) * GROUP_GAP);
      h += Math.max(...band.map((g) => g.rows)) * (nodeB + SIBLING_GAP) - SIBLING_GAP;
      bands += 1;
    }
    plans.push({ per, w: Math.max(1, w), h: Math.max(1, h + (bands - 1) * GROUP_GAP) });
  }
  return plans;
}

/** What a level would fit at with the pane to itself. Only a starting guess —
 *  the real objective is the whole graph, which layout() optimises. */
function soloFit(plan, paneW, paneH) {
  return clamp(
    Math.min((paneW - 2 * FIT_PAD) / plan.w, (paneH - 2 * FIT_PAD) / plan.h, FIT_MAX),
    MIN_K, MAX_K,
  );
}

/** The name gen-network.py prints on the README diagram, derived the same way,
 *  so the diagram and the live panel call an agent by the same short name. */
function shortType(t) {
  return String(t ?? '').replace(/-csk$/, '').replace(/-(expert|agent)$/, '');
}

/** `#rgb` and `#rrggbb` to three channels, or null for anything else — a
 *  palette entry that is not a plain hex is left alone rather than mangled. */
function rgb(h) {
  const s = String(h ?? '').trim();
  const m = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(s);
  if (!m) return null;
  const x = m[1].length === 3 ? m[1].replace(/./g, (c) => c + c) : m[1];
  return [0, 2, 4].map((i) => parseInt(x.slice(i, i + 2), 16));
}

/** `t` of the way from `a` toward `b`. Done here rather than with color-mix()
 *  because the result is also what the edge reports to anything reading it. */
function mixHex(a, b, t) {
  const pa = rgb(a);
  const pb = rgb(b);
  if (!pa || !pb) return a;
  const hex = pa.map((v, i) => Math.round(v + (pb[i] - v) * t).toString(16).padStart(2, '0'));
  return `#${hex.join('')}`;
}

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
