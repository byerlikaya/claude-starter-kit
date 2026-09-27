// The second film: what the panels do when you click them.
//
// The flow film answers "what is running"; this one answers "and then what".
// It is scripted rather than hand-driven so it can be re-shot identically after
// a UI change, and so the timing of each beat is a number in one place.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { CDP, httpJson } from './cdp.mjs';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i > 0 ? process.argv[i + 1] : d; };
const PORT = Number(arg('cdp', 9355));
const URL_ = arg('url', 'http://127.0.0.1:7802/?token=captureproof');
const W = Number(arg('w', 1680)), H = Number(arg('h', 940));
const SCALE = Number(arg('scale', 2));
const FPS = Number(arg('fps', 10));
const OUT = arg('out', path.join(os.tmpdir(), 'crewforth-studio-record', 'tour'));
const SESSION = arg('session', '7f3c1d20');

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(OUT, { recursive: true });
const PROFILE = arg('profile', path.join(os.tmpdir(), 'crewforth-studio-record', 'chrome-tour'));
fs.rmSync(PROFILE, { recursive: true, force: true });

const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  `--remote-debugging-port=${PORT}`, `--user-data-dir=${PROFILE}`, '--headless=new',
  `--window-size=${W},${H}`, `--force-device-scale-factor=${SCALE}`, '--hide-scrollbars',
  '--no-first-run', '--disable-extensions', 'about:blank',
], { stdio: 'ignore' });
process.on('exit', () => { try { chrome.kill(); } catch { /* already exited */ } });
const die = (m) => { console.error('tour:', m); try { chrome.kill(); } catch { /* already exited */ } process.exit(1); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let targets = null;
for (let i = 0; i < 60 && !targets; i++) { await sleep(250); try { targets = await httpJson(PORT, '/json/list'); } catch { /* not listening yet */ } }
if (!targets) die('chrome never opened its debugging port');
const cdp = await new CDP(targets.find((t) => t.type === 'page').webSocketDebuggerUrl).connect();
await cdp.call('Page.enable'); await cdp.call('Runtime.enable');
await cdp.call('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: SCALE, mobile: false });
await cdp.call('Page.navigate', { url: URL_ });
await sleep(3500);
if (!await cdp.eval(`!!document.querySelector('.cv-root')`)) die('panel did not render');

// Headless has no cursor, and a film of things opening by themselves reads as a
// glitch rather than as someone using the panel. This draws one and moves it
// with the synthetic clicks.
await cdp.eval(`
  (() => {
    const c = document.createElement('div');
    c.id = '__cursor';
    c.style.cssText = 'position:fixed;z-index:2147483647;width:22px;height:22px;pointer-events:none;'
      + 'transition:left .28s cubic-bezier(.4,0,.2,1),top .28s cubic-bezier(.4,0,.2,1);left:-40px;top:-40px;';
    c.innerHTML = '<svg viewBox="0 0 22 22" width="22" height="22">'
      + '<path d="M3 2 L3 17 L7.2 13.2 L9.8 19 L12.6 17.7 L10 12 L15.5 12 Z" '
      + 'fill="#fff" stroke="rgba(0,0,0,.55)" stroke-width="1.2"/></svg>';
    document.body.appendChild(c);
    const ring = document.createElement('div');
    ring.id = '__ring';
    ring.style.cssText = 'position:fixed;z-index:2147483646;width:34px;height:34px;border-radius:50%;'
      + 'pointer-events:none;border:2px solid rgba(120,180,255,.9);opacity:0;left:-60px;top:-60px;';
    document.body.appendChild(ring);
    window.__ping = (x, y) => {
      const r = document.getElementById('__ring');
      r.style.left = (x - 17) + 'px'; r.style.top = (y - 17) + 'px';
      r.style.transition = 'none'; r.style.opacity = '1'; r.style.transform = 'scale(.5)';
      requestAnimationFrame(() => {
        r.style.transition = 'opacity .5s, transform .5s';
        r.style.opacity = '0'; r.style.transform = 'scale(1.6)';
      });
    };
    return 'cursor ready';
  })()`);

const moveTo = async (x, y) => {
  await cdp.eval(`(() => { const c=document.getElementById('__cursor'); c.style.left=(${x}-3)+'px'; c.style.top=(${y}-2)+'px'; return 1; })()`);
  await cdp.call('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
};
const clickAt = async (x, y) => {
  await moveTo(x, y);
  await sleep(340);
  await cdp.eval(`window.__ping(${x}, ${y}); 1`);
  await cdp.call('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', buttons: 1, clickCount: 1 });
  await sleep(60);
  await cdp.call('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', buttons: 0, clickCount: 1 });
};
const centreOf = (sel, nth = 0) => cdp.eval(`
  (() => {
    const els = [...document.querySelectorAll(${JSON.stringify(sel)})];
    const e = els[${nth}];
    if (!e) return null;
    const r = e.getBoundingClientRect();
    return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2), text: (e.textContent||'').trim().slice(0,40) };
  })()`);
const findByText = (sel, needle) => cdp.eval(`
  (() => {
    const e = [...document.querySelectorAll(${JSON.stringify(sel)})]
      .find(x => (x.textContent || '').toLowerCase().includes(${JSON.stringify(needle.toLowerCase())}));
    if (!e) return null;
    const r = e.getBoundingClientRect();
    return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2), text: (e.textContent||'').trim().slice(0,40) };
  })()`);

// Fold the two sections that list this machine rather than the fixture.
await cdp.eval(`
  for (const k of ['fleet','reach']) {
    const t = document.querySelector('[data-fold="' + k + '"]');
    if (t && t.getAttribute('aria-expanded') !== 'false') t.click();
  } 'ok'`);
await sleep(500);

let frame = 0;
let filming = true;
const grab = async () => {
  const shot = await cdp.call('Page.captureScreenshot', { format: 'png', fromSurface: true, captureBeyondViewport: false });
  fs.writeFileSync(path.join(OUT, `f${String(frame++).padStart(4, '0')}.png`), Buffer.from(shot.data, 'base64'));
};
(async () => { while (filming) { const t = Date.now(); await grab(); const w = 1000 / FPS - (Date.now() - t); if (w > 0) await sleep(w); } })();

// A beat that clicks nothing looks identical to a beat that worked, until the
// film is assembled and half of it is one still frame. Each one states what it
// expects to be true afterwards.
const beat = async (label, fn, expect, hold = 1400) => {
  process.stdout.write(`tour: ${label}\n`);
  await fn();
  await sleep(hold);
  const got = await cdp.eval(expect.probe);
  const ok = expect.want(got);
  process.stdout.write(`      ${ok ? 'ok' : 'DID NOTHING'} — ${expect.name}: ${JSON.stringify(got).slice(0, 70)}\n`);
  if (!ok) die(`beat "${label}" changed nothing`);
};

await sleep(900);

await beat('open the session from the sidebar', async () => {
  const row = await findByText('.srow, .session, [role="treeitem"]', SESSION);
  if (!row) die('session row not found');
  await clickAt(row.x, row.y);
}, { name: 'nodes on canvas', probe: `document.querySelectorAll('.cv-node').length`, want: (v) => v > 5 }, 2200);

await beat('open an agent and read what it reported', async () => {
  // A finished agent, so the inspector opens on a report worth reading rather
  // than on one that has not written anything yet.
  const node = await findByText('.cv-node', 'Map every retry path');
  if (!node) die('no finished agent node to open');
  await clickAt(node.x, node.y);
}, { name: 'inspector open', probe: `document.getElementById('inspector')?.hidden === false`, want: (v) => v === true }, 2600);

await beat('switch to its tool timeline', async () => {
  const tab = await findByText('#inspector button, #inspector [role="tab"], #inspector .tab', 'activity');
  if (tab) await clickAt(tab.x, tab.y);
}, { name: 'timeline rows', probe: `document.querySelectorAll('#inspector .itimeline > *').length`, want: (v) => v > 3 }, 2400);

await beat('jump to the agent that failed', async () => {
  const alarm = await centreOf('.cv-alarm');
  if (alarm) { await clickAt(alarm.x, alarm.y); await sleep(900); }
  // The button centres the view on the failure and selects it. Clicking the card
  // afterwards is what a person does next anyway, and it makes the beat land
  // whether or not the button did the selecting.
  const bad = await findByText('.cv-node', 'Verify the changelog');
  if (!bad) die('failed agent card not found');
  await clickAt(bad.x, bad.y);
}, { name: 'failed agent selected', probe: `document.querySelector('#inspector')?.textContent?.slice(0,90) ?? ''`, want: (v) => /verif|changelog|fail/i.test(String(v)) }, 2600);

await beat('open the conversation behind the session', async () => {
  const close = await findByText('#inspector button', 'x');
  if (close) await clickAt(close.x, close.y);
  await sleep(600);
  const sn = await findByText('.cv-node', 'acme-payments-api');
  if (!sn) die('session node not found on the canvas');
  await clickAt(sn.x, sn.y);
}, { name: 'conversation messages', probe: `document.querySelectorAll('.chat-log .msg, .chat-log > *').length`, want: (v) => v > 3 }, 3400);

await beat('bring the project list back', async () => {
  const show = await centreOf('#side-show');
  if (show) await clickAt(show.x, show.y);
}, { name: 'still alive', probe: `document.querySelectorAll('.cv-node').length`, want: (v) => v > 5 }, 1800);

filming = false;
await sleep(300);
console.log(`tour: ${frame} frames -> ${OUT}`);
cdp.close(); chrome.kill();
