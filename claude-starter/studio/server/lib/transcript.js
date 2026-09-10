// Incremental JSONL reading.
//
// Transcripts are append-only and grow to megabytes, so re-parsing from byte
// zero on every change is not an option. Each reader keeps a byte offset and
// consumes only what was appended.
//
// A single record can itself be enormous (a pasted payload), so lines are
// assembled from a carry buffer rather than assumed to fit in one read.

import fsp from 'node:fs/promises';

export class JsonlReader {
  constructor(file) {
    this.file = file;
    this.offset = 0;
    this.carry = '';
    this.malformed = 0; // counted, never silently swallowed
  }

  /** Read everything appended since the last call. Returns parsed records.
   *
   * Async because a transcript open can take 31 s on a machine whose security
   * layer inspects it, and this sits under the stream tick — see the note at the
   * top of projects.js. The read is no faster; it just no longer stops the loop.
   */
  async read() {
    let st;
    try { st = await fsp.stat(this.file); } catch { return []; }

    // A shrunk file means it was replaced, not appended to. Start over rather
    // than reading from a stale offset into the middle of a record.
    if (st.size < this.offset) {
      this.offset = 0;
      this.carry = '';
    }
    if (st.size === this.offset) return [];

    let chunk;
    let fh;
    try {
      fh = await fsp.open(this.file, 'r');
      const len = st.size - this.offset;
      const buf = Buffer.allocUnsafe(len);
      const { bytesRead } = await fh.read(buf, 0, len, this.offset);
      chunk = buf.subarray(0, bytesRead).toString('utf8');
      this.offset += bytesRead;
    } catch {
      return [];
    } finally {
      if (fh !== undefined) try { await fh.close(); } catch { /* already gone */ }
    }

    const text = this.carry + chunk;
    const lines = text.split('\n');
    // The last element is either '' (clean boundary) or a partial record.
    this.carry = lines.pop() ?? '';

    const out = [];
    for (const line of lines) {
      if (!line) continue;
      try {
        out.push(JSON.parse(line));
      } catch {
        this.malformed += 1;
      }
    }
    return out;
  }
}

/** One-shot full read. Used for files we do not intend to follow. */
export async function readAll(file) {
  const r = new JsonlReader(file);
  const records = await r.read();
  return { records, malformed: r.malformed };
}

/**
 * Session context fill, measured the way the kit measures it.
 *
 * The trap this avoids cost the kit a 92%-full context reported as 0.9%: when
 * a subagent returns, its tool_result lands in the MAIN transcript as a
 * `type:"user"` record carrying `toolUseResult.usage`. That is the SUBAGENT's
 * spend, not the session's. Only `.message.usage` on a non-sidechain assistant
 * record counts.
 */
export function contextFill(records) {
  let total = null;
  for (const r of records) {
    if (r?.isSidechain === true) continue;
    if (r?.type !== 'assistant') continue;
    const u = r?.message?.usage;
    if (!u || u.cache_read_input_tokens == null) continue;
    total =
      (u.input_tokens ?? 0) +
      (u.cache_read_input_tokens ?? 0) +
      (u.cache_creation_input_tokens ?? 0);
  }
  return total;
}
