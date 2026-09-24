// The ONE Node place that still reads the pre-3.0 CSK_* names — the twin of kit/eval/lib/crew-env.sh, same list,
// same rule: when CREW_<X> is not set at all and CSK_<X> is, CREW_<X> takes its value; a CREW_<X> that is set wins.
// Imported first by index.js, so every module after it only ever reads CREW_*. The old names go in 4.0.
const LEGACY = ['LANG', 'NO_STAR', 'NO_UPDATE_CHECK', 'NO_BOARD', 'GATE_LOG', 'GATE_LOG_CMD', 'STUDIO_TOKEN',
  'STUDIO_PEERS', 'STUDIO_RUNTIME', 'MAX_FILE_BYTES', 'ALLOW_SOURCE_INSTALL'];
for (const name of LEGACY) {
  if (process.env[`CREW_${name}`] === undefined && process.env[`CSK_${name}`] !== undefined) {
    process.env[`CREW_${name}`] = process.env[`CSK_${name}`];
  }
}
export const LEGACY_ENV = LEGACY;
