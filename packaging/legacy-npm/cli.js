#!/usr/bin/env node
// The 2.x package name, kept alive so installs that still call it reach 3.0. Every 2.x entry point — the
// update check's `npx @byerlikaya/claude-starter-kit@latest update`, `init`, `adopt`, `--version` — is answered by
// the 3.0 CLI as it stands, so nothing is translated: the arguments go through unchanged, and so does the exit code.
'use strict';
const { spawnSync } = require('node:child_process');

// crewforth@^3 by default. A test (or a rehearsal against `crewforth@next`, which ^3 does not match) may point it
// elsewhere; CREWFORTH_SPEC is the rehearsal spelling, CREW_FORWARD_SPEC the test one.
const spec = process.env.CREW_FORWARD_SPEC || process.env.CREWFORTH_SPEC || 'crewforth@^3';
const args = process.argv.slice(2);

process.stderr.write('@byerlikaya/claude-starter-kit is now crewforth — forwarding to npx crewforth@3 …\n');

// Run npm's own entry point with this node: no shell, so every argument arrives as one argv entry on every
// platform (a shell joins them unescaped, and Node 24 warns about exactly that — DEP0190). npx and npm set
// npm_execpath to npm-cli.js; without it (a global install run directly) the shell is the last resort.
const npmCli = process.env.npm_execpath;
const npmArgs = ['exec', '--yes', '--', spec, ...args];
const r = npmCli && /npm-cli\.[cm]?js$/.test(npmCli)
  ? spawnSync(process.execPath, [npmCli, ...npmArgs], { stdio: 'inherit' })
  : spawnSync('npm', npmArgs, { stdio: 'inherit', shell: true });

if (r.error) {
  process.stderr.write(`claude-starter-kit: could not start npm (${r.error.message}). Run: npx crewforth ${args.join(' ')}\n`);
  process.exit(1);
}
process.exit(r.status === null ? 1 : r.status);
