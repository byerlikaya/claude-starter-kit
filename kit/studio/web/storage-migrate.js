// 3.0 renamed the panel's saved-layout keys: csk-studio-* → crewforth-studio-*. They are moved once, on the first
// open after the update: the old value is copied unless the new key already holds one, then the old key is removed.
// So the user's theme, widths, folds and canvas layout survive the rename. Remove in 4.0.
const OLD = 'csk-studio-';
export const PREFIX = 'crewforth-studio-';

export function migrateStorage(ls) {
  let moved = 0;
  try {
    const keys = [];
    for (let i = 0; i < ls.length; i++) {
      const k = ls.key(i);
      if (k && k.startsWith(OLD)) keys.push(k);
    }
    for (const k of keys) {
      const nk = PREFIX + k.slice(OLD.length);
      if (ls.getItem(nk) === null) ls.setItem(nk, ls.getItem(k));
      ls.removeItem(k);
      moved += 1;
    }
  } catch { /* blocked storage: nothing to move, nothing lost */ }
  return moved;
}
