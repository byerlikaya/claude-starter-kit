// Fleet: the list of Claude Code sessions alive on this machine.
//
// `claude agents --json` is the only surface that reports interactive sessions
// without a TTY. It spawns a process per call, so every read is cached; the
// cost of that spawn is measured at startup rather than assumed (a 1 s poll is
// free on a fast machine and a tax on a slow one).
//
// Nothing here throws. A missing CLI is a legitimate answer — "not measured" —
// and it is reported as such, never as an empty fleet. Those are different
// facts and the UI draws them differently.

import { execFile } from 'node:child_process';

const CACHE_MS = 1000;
const EXEC_TIMEOUT_MS = 10000;
const MAX_BUFFER = 4 * 1024 * 1024;

let cache = null;          // { at: epochMs, value: FleetResult }
let inflight = null;       // Promise, so N concurrent readers cause 1 spawn

/**
 * @typedef {Object} FleetResult
 * @property {boolean} measured  false means nothing was read, NOT "nothing is running"
 * @property {string}  [reason]  why it could not be measured
 * @property {Array}   sessions  normalised session rows (empty when !measured)
 * @property {number}  at        epoch ms of the underlying read
 * @property {number}  [spawnMs] how long the spawn actually took
 */

function run(cmd, args) {
  return new Promise((resolve) => {
    const started = Date.now();
    execFile(
      cmd,
      args,
      { timeout: EXEC_TIMEOUT_MS, maxBuffer: MAX_BUFFER, windowsHide: true },
      (err, stdout, stderr) => {
        resolve({
          err,
          stdout: stdout ?? '',
          stderr: stderr ?? '',
          ms: Date.now() - started,
        });
      },
    );
  });
}

// A row we do not recognise is still a row. Unknown fields are carried through
// untouched so a CLI upgrade adds information rather than silently dropping it.
function normalise(row) {
  if (!row || typeof row !== 'object') return null;
  const id = row.sessionId ?? row.session_id ?? null;
  if (!id) return null;
  return {
    sessionId: id,
    pid: typeof row.pid === 'number' ? row.pid : null,
    cwd: typeof row.cwd === 'string' ? row.cwd : null,
    kind: typeof row.kind === 'string' ? row.kind : 'unknown',
    name: typeof row.name === 'string' ? row.name : null,
    status: typeof row.status === 'string' ? row.status : 'unknown',
    // Present when the session is blocked on a human. Shown verbatim — the CLI
    // phrases it better than a re-worded guess would.
    waitingFor: typeof row.waitingFor === 'string' ? row.waitingFor : null,
    startedAt: typeof row.startedAt === 'number' ? row.startedAt : null,
    raw: row,
  };
}

async function read() {
  const { err, stdout, stderr, ms } = await run('claude', ['agents', '--json']);

  if (err) {
    // ENOENT is the honest "no CLI here" case; anything else is a broken read.
    const reason =
      err.code === 'ENOENT'
        ? 'claude CLI not found on PATH'
        : `claude agents --json failed (${err.code ?? err.message})${
            stderr.trim() ? `: ${stderr.trim().slice(0, 200)}` : ''
          }`;
    return { measured: false, reason, sessions: [], at: Date.now(), spawnMs: ms };
  }

  let parsed;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    return {
      measured: false,
      reason: 'claude agents --json returned output that is not JSON',
      sessions: [],
      at: Date.now(),
      spawnMs: ms,
    };
  }

  if (!Array.isArray(parsed)) {
    return {
      measured: false,
      reason: `expected a JSON array, got ${typeof parsed}`,
      sessions: [],
      at: Date.now(),
      spawnMs: ms,
    };
  }

  return {
    measured: true,
    sessions: parsed.map(normalise).filter(Boolean),
    at: Date.now(),
    spawnMs: ms,
  };
}

/** Cached fleet read. Concurrent callers share one spawn. */
export async function getFleet({ force = false } = {}) {
  if (!force && cache && Date.now() - cache.at < CACHE_MS) return cache.value;
  if (inflight) return inflight;

  inflight = read()
    .then((value) => {
      cache = { at: Date.now(), value };
      return value;
    })
    .finally(() => {
      inflight = null;
    });

  return inflight;
}

/** Measure what one spawn actually costs here, so the poll interval is a
 *  measurement rather than a guess. Returns null when the CLI is absent. */
export async function measureSpawnCost(samples = 3) {
  const runs = [];
  for (let i = 0; i < samples; i += 1) {
    const r = await getFleet({ force: true });
    if (!r.measured && r.reason?.includes('not found')) return null;
    if (typeof r.spawnMs === 'number') runs.push(r.spawnMs);
  }
  if (!runs.length) return null;
  runs.sort((a, b) => a - b);
  return { samples: runs.length, minMs: runs[0], medianMs: runs[Math.floor(runs.length / 2)], maxMs: runs[runs.length - 1] };
}

export const _internals = { normalise, CACHE_MS };
