// A minimal Chrome DevTools Protocol client.
//
// The browser extension proved the wrong tool for filming: it attaches to
// whichever Chrome the account has connected — twice that was a window on
// another display, once it was another machine entirely — and it paints an
// automation banner over the page, which then lands in the recording. Driving
// a Chrome we launch ourselves removes all three, and makes the viewport an
// exact number instead of a browser-chrome subtraction.
//
// Node has no WebSocket client, and this file is not allowed a dependency, so
// the framing is here: a handshake, masked client frames, and reassembly of
// the fragmented server frames a screenshot arrives in.
import net from 'node:net';
import http from 'node:http';
import crypto from 'node:crypto';

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

export function httpJson(port, path) {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port, path }, (res) => {
      let b = '';
      res.on('data', (d) => { b += d; });
      res.on('end', () => { try { resolve(JSON.parse(b)); } catch (e) { reject(e); } });
    }).on('error', reject);
  });
}

export class CDP {
  constructor(wsUrl) {
    this.url = new URL(wsUrl);
    this.id = 0;
    this.pending = new Map();
    this.events = new Map();
    this.buf = Buffer.alloc(0);
    this.frag = null;
  }

  connect() {
    return new Promise((resolve, reject) => {
      const key = crypto.randomBytes(16).toString('base64');
      const sock = net.connect(Number(this.url.port), this.url.hostname, () => {
        sock.write(
          `GET ${this.url.pathname}${this.url.search} HTTP/1.1\r\n`
          + `Host: ${this.url.host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n`
          + `Sec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`);
      });
      sock.setNoDelay(true);
      this.sock = sock;
      const expect = crypto.createHash('sha1').update(key + GUID).digest('base64');
      let handshook = false;
      sock.on('data', (chunk) => {
        if (!handshook) {
          this.buf = Buffer.concat([this.buf, chunk]);
          const end = this.buf.indexOf('\r\n\r\n');
          if (end < 0) return;
          const head = this.buf.subarray(0, end).toString();
          if (!head.includes(expect)) { reject(new Error('bad websocket handshake')); return; }
          this.buf = this.buf.subarray(end + 4);
          handshook = true;
          resolve(this);
          this.#drain();
          return;
        }
        this.buf = Buffer.concat([this.buf, chunk]);
        this.#drain();
      });
      sock.on('error', reject);
    });
  }

  #drain() {
    for (;;) {
      if (this.buf.length < 2) return;
      const b0 = this.buf[0], b1 = this.buf[1];
      const fin = (b0 & 0x80) !== 0;
      const op = b0 & 0x0f;
      let len = b1 & 0x7f;
      let off = 2;
      if (len === 126) { if (this.buf.length < 4) return; len = this.buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (this.buf.length < 10) return; len = Number(this.buf.readBigUInt64BE(2)); off = 10; }
      if (this.buf.length < off + len) return;
      const payload = this.buf.subarray(off, off + len);
      this.buf = this.buf.subarray(off + len);
      if (op === 0x8) { this.sock.end(); return; }
      if (op === 0x9) { this.#send(0xa, payload); continue; }
      if (op === 0x0) this.frag = this.frag ? Buffer.concat([this.frag, payload]) : payload;
      else this.frag = payload;
      if (!fin) continue;
      const text = this.frag.toString('utf8');
      this.frag = null;
      let msg; try { msg = JSON.parse(text); } catch { continue; }
      if (msg.id !== undefined && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
      } else if (msg.method) {
        (this.events.get(msg.method) ?? []).forEach((fn) => fn(msg.params));
      }
    }
  }

  #send(op, payload) {
    const len = payload.length;
    const head = len < 126 ? Buffer.alloc(6) : len < 65536 ? Buffer.alloc(8) : Buffer.alloc(14);
    head[0] = 0x80 | op;
    const mask = crypto.randomBytes(4);
    if (len < 126) { head[1] = 0x80 | len; mask.copy(head, 2); }
    else if (len < 65536) { head[1] = 0x80 | 126; head.writeUInt16BE(len, 2); mask.copy(head, 4); }
    else { head[1] = 0x80 | 127; head.writeBigUInt64BE(BigInt(len), 2); mask.copy(head, 10); }
    const masked = Buffer.from(payload);
    for (let i = 0; i < masked.length; i++) masked[i] ^= mask[i & 3];
    this.sock.write(Buffer.concat([head, masked]));
  }

  on(method, fn) {
    if (!this.events.has(method)) this.events.set(method, []);
    this.events.get(method).push(fn);
  }

  call(method, params = {}) {
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.#send(0x1, Buffer.from(JSON.stringify({ id, method, params })));
    });
  }

  async eval(expression) {
    const r = await this.call('Runtime.evaluate', {
      expression, awaitPromise: true, returnByValue: true,
    });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description ?? ''));
    return r.result?.value;
  }

  close() { try { this.sock.end(); } catch { /* already gone */ } }
}
