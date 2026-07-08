#!/usr/bin/env node
'use strict';
// Runner for the Agentic Working Kit. The kit is a set of bash scripts (start.sh / adopt.sh)
// plus the claude-starter/ payload, all bundled in this npm package. This wrapper stages the
// payload in a temp dir and runs the requested script with the user's project as the CWD, so
// start.sh's self-cleanup only ever removes the temp copies — never the package or the CWD.

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const pkgDir = path.join(__dirname, '..');
const argv = process.argv.slice(2);
const sub = argv[0];

if (sub === '--help' || sub === '-h' || sub === 'help') {
  console.log(`Agentic Working Kit

Usage:
  npx @byerlikaya/claude-starter-kit [init] [--backend|--frontend|--mobile|--fullstack] [--dotnet|--generic]
      Set up the kit in a fresh project (start.sh wizard).
  npx @byerlikaya/claude-starter-kit adopt
      Hand the kit over onto an existing project (adopt.sh).

Run either at the root of your target project.`);
  process.exit(0);
}

const isAdopt = sub === 'adopt' || sub === 'update';
const isInit = sub === 'init';
const script = isAdopt ? 'adopt.sh' : 'start.sh';
const passArgs = (isAdopt || isInit) ? argv.slice(1) : argv;

// bash is required (macOS / Linux / on Windows: Git Bash or WSL)
const probe = spawnSync('bash', ['-c', 'exit 0']);
if (probe.error) {
  console.error('This kit needs bash — macOS/Linux have it; on Windows install Git Bash (git-scm.com) or use WSL.');
  process.exit(1);
}

// Stage the bundled payload in a temp dir so the script's self-cleanup is harmless.
const stage = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-starter-kit-'));
try {
  for (const item of [script, 'claude-starter', 'VERSION']) {
    const src = path.join(pkgDir, item);
    if (fs.existsSync(src)) fs.cpSync(src, path.join(stage, item), { recursive: true });
  }
  // Pass the script path with forward slashes: bash (incl. Windows Git Bash) treats '\' as an escape,
  // so a native Windows path like C:\Users\...\start.sh loses its separators. C:/Users/.../start.sh works.
  const scriptPath = path.join(stage, script).replace(/\\/g, '/');
  const res = spawnSync('bash', [scriptPath, ...passArgs], {
    stdio: 'inherit',
    cwd: process.cwd(),
  });
  process.exitCode = res.status == null ? 1 : res.status;
} finally {
  try { fs.rmSync(stage, { recursive: true, force: true }); } catch (_) { /* best effort */ }
}
