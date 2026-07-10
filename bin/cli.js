#!/usr/bin/env node
'use strict';
// Runner for the Claude Starter Kit. The kit is a set of bash scripts (start.sh / adopt.sh)
// plus the claude-starter/ payload, all bundled in this npm package. This wrapper stages the
// payload in a temp dir and runs the requested script with the user's project as the CWD, so
// the script's self-cleanup only ever removes the temp copies — never the package or the CWD.

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const pkgDir = path.join(__dirname, '..');
const argv = process.argv.slice(2);
const sub = argv[0];

if (sub === '--help' || sub === '-h' || sub === 'help') {
  console.log(`Claude Starter Kit

Usage:
  npx @byerlikaya/claude-starter-kit [init] [--backend|--frontend|--mobile|--fullstack] [--dotnet|--generic]
      Set up the kit in a fresh project (start.sh wizard).
  npx @byerlikaya/claude-starter-kit adopt
      Hand the kit over onto an existing project (adopt.sh).
  npx @byerlikaya/claude-starter-kit@latest update
      Refresh a project that already has the kit. Alias of 'adopt': it reads .claude/kit.conf and
      refreshes the project in the shape it was installed in. Your CLAUDE.md is never touched.

Run any of them at the root of your target project.
On Windows, run inside Git Bash for the smoothest experience (WSL works as a fallback).`);
  process.exit(0);
}

const isAdopt = sub === 'adopt' || sub === 'update';
const isInit = sub === 'init';
const script = isAdopt ? 'adopt.sh' : 'start.sh';
const passArgs = (isAdopt || isInit) ? argv.slice(1) : argv;

// On Windows, prefer Git Bash (MINGW: shares the Win32 namespace, accepts C:/... natively) over WSL's
// System32 bash.exe (its drvfs / 8.3 / /mnt/c handling is the fragile path). Fall back to 'bash' on PATH.
function findBash() {
  if (process.platform !== 'win32') return 'bash';
  const roots = [
    process.env['ProgramFiles'],
    process.env['ProgramW6432'],
    process.env['ProgramFiles(x86)'],
    process.env['LOCALAPPDATA'] && path.join(process.env['LOCALAPPDATA'], 'Programs'),
  ].filter(Boolean);
  for (const r of roots) {
    for (const rel of ['Git\\bin\\bash.exe', 'Git\\usr\\bin\\bash.exe']) {
      const p = path.join(r, rel);
      try { if (fs.existsSync(p)) return p; } catch (_) { /* ignore */ }
    }
  }
  return 'bash'; // likely WSL; the runner below converts C:/... -> /mnt/c/... for that case
}
const BASH = findBash();

// bash is required (macOS / Linux have it; on Windows: Git Bash or WSL)
const probe = spawnSync(BASH, ['-c', 'exit 0']);
if (probe.error) {
  console.error('This kit needs bash — macOS/Linux have it; on Windows install Git Bash (git-scm.com) or use WSL.');
  process.exit(1);
}

// Expand 8.3 short names (e.g. C:\Users\BB358~1.YER) to their real long form before staging — WSL's drvfs
// exposes only long names, so an unexpanded short path yields a "correct-looking" /mnt/c/... that still ENOENTs.
// No-op / safe on macOS & Linux.
const realpath = (p) => { try { return fs.realpathSync.native(p); } catch (_) { return p; } };

// Stage the bundled payload in a temp dir so the script's self-cleanup is harmless.
const stage = fs.mkdtempSync(path.join(realpath(os.tmpdir()), 'claude-starter-kit-'));
try {
  for (const item of [script, 'claude-starter', 'VERSION']) {
    const src = path.join(pkgDir, item);
    if (fs.existsSync(src)) fs.cpSync(src, path.join(stage, item), { recursive: true });
  }

  let res;
  if (process.platform !== 'win32') {
    // macOS / Linux: run the staged script directly. cwd = the user's project so it installs there;
    // $0 resolves to the stage so the payload (claude-starter/) is found next to it. No path munging —
    // a backslash is a legal Unix filename char, and rewriting it would corrupt real paths.
    res = spawnSync(BASH, [path.join(stage, script), ...passArgs], {
      stdio: 'inherit',
      cwd: process.cwd(),
    });
  } else {
    // Windows: forward-slash so bash's argv parsing doesn't eat '\'; then translate the Windows paths to
    // the running shell's convention INSIDE bash, dispatched deterministically by shell flavour:
    //   Git Bash / MSYS / Cygwin -> cygpath -u (C:/... also works as-is);  WSL -> wslpath -u -> /mnt/c/...
    const fwd = (p) => p.replace(/\\/g, '/');
    const stageFwd = fwd(realpath(stage));
    const projFwd = fwd(realpath(process.cwd()));
    const runner = [
      'conv(){',
      '  case "$(uname -s)" in',
      '    MINGW*|MSYS*|CYGWIN*) command -v cygpath >/dev/null 2>&1 && { cygpath -u "$1"; return; } ;;',
      '    *)                    command -v wslpath >/dev/null 2>&1 && { wslpath -u "$1"; return; } ;;',
      '  esac',
      '  printf %s "$1"',
      '}',
      'S=$(conv "$1"); C=$(conv "$2"); shift 2',
      '[ -r "$S/' + script + '" ] || { echo "kit: bash cannot read the staged script at $S/' + script +
        ' — run inside Git Bash, or set TEMP to a long (non-8.3, ASCII) path." >&2; exit 127; }',
      'cd "$C" || { echo "kit: cannot enter the project directory $C" >&2; exit 1; }',
      'exec bash "$S/' + script + '" "$@"',
    ].join('\n');
    res = spawnSync(BASH, ['-c', runner, 'kit', stageFwd, projFwd, ...passArgs], {
      stdio: 'inherit',
    });
  }

  process.exitCode = res.status == null ? 1 : res.status;
} finally {
  try { fs.rmSync(stage, { recursive: true, force: true }); } catch (_) { /* best effort */ }
}
