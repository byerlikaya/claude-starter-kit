// Film the panel by driving our own Chrome over CDP.
//
// Everything the last three takes got wrong is a parameter here rather than a
// guess: the viewport is exact (no browser chrome to subtract, no automation
// banner to crop around), the zoom is pinned so the graph never falls into the
// far reading mid-film and drops its labels, and frames come back at the device
// scale we ask for, so nothing is downscaled into mush afterwards.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { CDP, httpJson } from './cdp.mjs';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i > 0 ? process.argv[i + 1] : d; };

const PORT = Number(arg('cdp', 9333));
const URL_ = arg('url', 'http://127.0.0.1:7802/?token=captureproof');
const W = Number(arg('w', 1512));
const H = Number(arg('h', 760));
const SCALE = Number(arg('scale', 2));      // device pixels per CSS pixel
const FPS = Number(arg('fps', 10));
const SECS = Number(arg('secs', 24));
const ZOOM = Number(arg('zoom', 0.78));
const SESSION = arg('session', '');
const HIDE_SIDE = process.argv.includes('--hide-sidebar');
const NO_PIN = process.argv.includes('--no-pin');
const RECENTRE = Number(arg('recentre', 0));   // frames between recentre passes; 0 = never
const OUT = arg('out', path.join(os.tmpdir(), 'crewforth-studio-record', 'film'));

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PROFILE = arg('profile', path.join(os.tmpdir(), 'crewforth-studio-record', 'chrome-profile'));

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(OUT, { recursive: true });
fs.rmSync(PROFILE, { recursive: true, force: true });

// A throwaway profile: no extensions, so no automation banner, and no other
// tabs whose content could end up in the frame.
const chrome = spawn(CHROME, [
  `--remote-debugging-port=${PORT}`,
  `--user-data-dir=${PROFILE}`,
  '--headless=new',
  `--window-size=${W},${H}`,
  `--force-device-scale-factor=${SCALE}`,
  '--hide-scrollbars',
  '--no-first-run', '--no-default-browser-check', '--disable-extensions',
  'about:blank',
], { stdio: 'ignore', detached: false });

const die = (m) => { console.error('shoot:', m); try { chrome.kill(); } catch { /* already exited */ } process.exit(1); };
process.on('exit', () => { try { chrome.kill(); } catch { /* already exited */ } });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let targets = null;
for (let i = 0; i < 60 && !targets; i++) {
  await sleep(250);
  try { targets = await httpJson(PORT, '/json/list'); } catch { /* not up yet */ }
}
if (!targets) die('chrome never opened its debugging port');

const page = targets.find((t) => t.type === 'page');
if (!page) die('no page target');

const cdp = await new CDP(page.webSocketDebuggerUrl).connect();
await cdp.call('Page.enable');
await cdp.call('Runtime.enable');
await cdp.call('Emulation.setDeviceMetricsOverride',
  { width: W, height: H, deviceScaleFactor: SCALE, mobile: false });

await cdp.call('Page.navigate', { url: URL_ });
await sleep(3500);

const ready = await cdp.eval(`!!document.querySelector('.cv-root')`);
if (!ready) die('the panel did not render — is the server up at ' + URL_ + '?');

// Collapsing the sidebar hands its width to the canvas. It does not change the
// fit of the finished graph — that one is bound by height — but the widest
// moment of a graph that is still growing IS width-bound, and those are exactly
// the frames where cards were spilling out of the picture.
if (HIDE_SIDE) {
  await cdp.eval(`document.getElementById('side-hide')?.click(); 'x'`);
  await sleep(600);
}

// Fold the two sidebar sections that list this machine rather than the fixture.
await cdp.eval(`
  for (const k of ['fleet','reach']) {
    const t = document.querySelector('[data-fold="' + k + '"]');
    if (t && t.getAttribute('aria-expanded') !== 'false') t.click();
  }
  'ok'`);
await sleep(400);

// Pick the session by hand. The panel opens on the largest session it can see,
// and the one we are filming starts empty on purpose — so left alone it opens
// on a different session and films a graph that never changes.
if (SESSION) {
  const picked = await cdp.eval(`
    (() => {
      const rows = [...document.querySelectorAll('.srow, .session, [role="treeitem"]')];
      const hit = rows.find((r) => (r.dataset.session ?? r.getAttribute('data-session') ?? r.textContent ?? '').includes(${JSON.stringify(SESSION.slice(0, 8))}));
      if (!hit) return 'not found among ' + rows.length + ' rows';
      hit.click();
      return 'clicked: ' + hit.textContent.trim().slice(0, 40);
    })()`);
  console.log('shoot: session ->', picked);
  await sleep(1200);
  const shown = await cdp.eval(`document.querySelector('.cv-node .cv-title, .cv-node')?.textContent?.slice(0,60) ?? 'none'`);
  if (String(picked).startsWith('not found')) die('could not select the session to film');
  console.log('shoot: canvas shows', JSON.stringify(shown));
}

// Pin the zoom. fit() re-runs on every poll and, while the graph is growing,
// it dips below the detail threshold and the cards shed their text — correct
// behaviour in the product, but in a recording it reads as the labels breaking.
// Nudging one node marks the view as touched, which is the panel's own signal
// to stop auto-fitting.
// Drag one card a few pixels. The panel treats a hand-placed node as "the user
// has arranged this" and stops auto-fitting, which is what keeps the zoom — and
// therefore the level of detail — steady while the graph grows underneath.
//
// This has to go through Input.dispatchMouseEvent rather than a synthetic
// MouseEvent: the drag handler listens for POINTER events and calls
// setPointerCapture, and neither fires for a hand-made MouseEvent. A whole take
// was filmed before that was noticed, with the cards dropping their text
// halfway through because the view was still free to re-fit.
if (!NO_PIN) {
  const box = await cdp.eval(`
    (() => {
      const n = document.querySelector('.cv-node');
      if (!n) return null;
      const r = n.getBoundingClientRect();
      return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + 12) };
    })()`);
  if (!box) die('no node to pin');
  const mouse = (type, x, y) => cdp.call('Input.dispatchMouseEvent',
    { type, x, y, button: 'left', buttons: type === 'mouseReleased' ? 0 : 1, clickCount: 1 });
  await mouse('mousePressed', box.x, box.y);
  for (let d = 1; d <= 6; d++) { await mouse('mouseMoved', box.x + d, box.y); await sleep(16); }
  await mouse('mouseReleased', box.x + 6, box.y);
  await sleep(300);
  const pinned = await cdp.eval(`document.querySelectorAll('.cv-node[data-pinned], .cv-node.pinned').length`);
  console.log('shoot: pin drag sent; nodes marked pinned =', pinned);
}

const setZoom = async (k) => cdp.eval(`
  (() => {
    const vp = document.querySelector('.cv-viewport').parentElement;
    const r = vp.getBoundingClientRect();
    const cx = r.x + r.width / 2, cy = r.y + r.height / 2;
    let guard = 0;
    const cur = () => parseFloat(document.querySelector('.cv-zoom').textContent) / 100;
    while (cur() < ${k} - 0.01 && guard++ < 40) {
      vp.dispatchEvent(new WheelEvent('wheel', {deltaY:-100, clientX:cx, clientY:cy, bubbles:true, cancelable:true}));
    }
    while (cur() > ${k} + 0.01 && guard++ < 80) {
      vp.dispatchEvent(new WheelEvent('wheel', {deltaY:100, clientX:cx, clientY:cy, bubbles:true, cancelable:true}));
    }
    return document.querySelector('.cv-zoom').textContent;
  })()`);

if (!NO_PIN) console.log('shoot: zoom ->', await setZoom(ZOOM));
else console.log('shoot: zoom left free — the panel fits the graph on every poll');

const total = FPS * SECS;
const delay = 1000 / FPS;
const t0 = Date.now();
let corrections = 0;
let recentres = 0;
for (let i = 0; i < total; i++) {
  // Re-assert the zoom rather than trusting it to stay put. Nudging a node is
  // supposed to stop the panel auto-fitting, but it did not hold across a
  // growing graph: the view drifted below the detail threshold partway through
  // and the cards shed their text mid-film. Checking is cheap; assuming was the
  // reason a whole take had to be thrown away.
  if (!NO_PIN && i % 8 === 0) {
    const k = await cdp.eval(`parseFloat(document.querySelector('.cv-zoom').textContent) / 100`);
    if (Math.abs(k - ZOOM) > 0.02) { await setZoom(ZOOM); corrections += 1; }
  }
  // Keep the camera over the graph. A pinned zoom holds the level of detail but
  // not the framing, and a graph that is still growing walks out of a fixed
  // one. Fit centres and scales; zooming back to the pinned value afterwards
  // scales about the viewport centre, so the centring survives and the reading
  // does not change.
  if (RECENTRE && i > 0 && i % RECENTRE === 0) {
    await cdp.eval(`document.querySelector('[data-act="fit"]').click(); 'x'`);
    await sleep(60);
    await setZoom(ZOOM);
    recentres += 1;
  }
  const shot = await cdp.call('Page.captureScreenshot', { format: 'png', fromSurface: true, captureBeyondViewport: false });
  fs.writeFileSync(path.join(OUT, `f${String(i).padStart(4, '0')}.png`), Buffer.from(shot.data, 'base64'));
  const target = t0 + (i + 1) * delay;
  const wait = target - Date.now();
  if (wait > 0) await sleep(wait);
}
const el = ((Date.now() - t0) / 1000).toFixed(1);
console.log(`shoot: ${total} frames in ${el}s (${(total / el).toFixed(1)} fps) -> ${OUT}`);

const zoomEnd = await cdp.eval(`document.querySelector('.cv-zoom').textContent`);
const lod = await cdp.eval(`document.querySelector('.cv-root').dataset.lod`);
console.log('shoot: ended at', zoomEnd, '· reading', lod, `· ${corrections} zoom corrections · ${recentres} recentres`);
cdp.close();
chrome.kill();
