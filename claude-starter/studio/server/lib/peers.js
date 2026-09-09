// Other machines.
//
// Transcripts are local files. `claude agents --json` reports only the machine
// it runs on, and no CLI lists another machine's sessions — measured, not
// assumed. So the only way to see a second machine is to run Studio there too
// and have this one read it.
//
// The server still binds to loopback, and that is not negotiable: it serves a
// developer's transcripts. A peer is therefore normally a forwarded port —
//
//     ssh -N -L 7778:127.0.0.1:7777 other-machine
//     node studio/server/index.js --peer http://127.0.0.1:7778
//
// which needs no listening socket on any network and no new credentials. A
// peer that is unreachable is reported as unreachable, never as empty.

const PEER_TIMEOUT_MS = 6000;

export function parsePeers(list) {
  const out = [];
  for (const raw of list) {
    const spec = String(raw).trim();
    if (!spec) continue;
    let url;
    try {
      url = new URL(spec.includes('://') ? spec : `http://${spec}`);
    } catch {
      out.push({ spec, error: 'not a URL' });
      continue;
    }
    // A token may ride along as ?token=… or as the URL's password field.
    const token = url.searchParams.get('token') || url.password || null;
    url.search = '';
    url.username = '';
    url.password = '';
    const name = url.port ? `${url.hostname}:${url.port}` : url.hostname;
    out.push({ spec, base: url.origin, token, name });
  }
  return out;
}

async function ask(peer, path) {
  if (peer.error) return { ok: false, reason: peer.error };
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), PEER_TIMEOUT_MS);
  try {
    const headers = peer.token ? { authorization: `Bearer ${peer.token}` } : {};
    const res = await fetch(`${peer.base}${path}`, { headers, signal: ctl.signal });
    if (!res.ok) return { ok: false, reason: `HTTP ${res.status}` };
    return { ok: true, body: await res.json() };
  } catch (e) {
    return { ok: false, reason: e?.name === 'AbortError' ? 'timed out' : String(e?.message ?? e) };
  } finally {
    clearTimeout(timer);
  }
}

/** Ask every peer the same question, in parallel. Never throws. */
export async function askAll(peers, path) {
  return Promise.all(peers.map(async (p) => ({ peer: p, ...(await ask(p, path)) })));
}

/** Find which peer holds a session, so graph and detail reads can be routed. */
export async function locateSession(peers, sessionId) {
  for (const p of peers) {
    const r = await ask(p, `/api/session/${encodeURIComponent(sessionId)}/graph`);
    if (r.ok && r.body?.measured) return p;
  }
  return null;
}

export { ask };
