#!/usr/bin/env bash
# Setup wizard: picks profile + backend stack step by step, shows a summary and asks for confirmation;
# if backend .NET is selected, includes the DevArchitecture base behind an approval gate; then installs the kit
# (./.claude + ./CLAUDE.md) pruned by profile; finally deletes claude-starter/ and itself.
# start.sh + claude-starter/ must be in the SAME directory. At the project root:  bash start.sh [flags]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/claude-starter"
DEVARCH_URL="https://github.com/DevArchitecture/DevArchitecture"

if [ ! -d "$SRC" ]; then
  echo "ERROR: 'claude-starter/' folder not found."
  echo "start.sh and claude-starter/ must be in the SAME directory (both come together when you unzip)."
  exit 1
fi

usage() {
  cat <<'USAGE'
Usage: bash start.sh [PROFILE] [BACKEND-STACK]
  Profile:  --backend | --frontend | --mobile | --fullstack   (default: fullstack)
  Stack:    --dotnet  | --generic   (backend/fullstack only; default: dotnet)
If no flag is given, the script asks the relevant step interactively (wizard).
  --dotnet   .NET/DevArchitecture full support (devarch-module + DevArch gate)
  --generic  generic backend (backend/database-expert-csk + db-migration; NO devarch)
             (sonarqube-check is language-agnostic; installed in every profile, not .NET-specific)
USAGE
}

ask_yes() {  # $1 = question; returns 0 if the user says 'yes'
  local a
  printf '%s [yes/no]: ' "$1"
  read -r a || a=""
  case "$a" in [yY]|[yY][eE][sS]|[eE]|[eE][vV][eE][tT]) return 0 ;; *) return 1 ;; esac
}
has_devarch() {  # $1 = dir to check (default .); does it have the canonical DevArchitecture structure
  local d="${1:-.}"
  [ -d "$d/Business" ] && [ -d "$d/Core" ] && { [ -d "$d/DataAccess" ] || [ -d "$d/Entities" ] || [ -d "$d/WebAPI" ]; }
}
project_has_source() {  # is there a real source/project file outside the kit
  ls ./*.sln ./*.csproj >/dev/null 2>&1 && return 0
  for m in package.json go.mod pom.xml build.gradle Cargo.toml requirements.txt pyproject.toml src; do
    [ -e "./$m" ] && return 0
  done
  return 1
}
clone_devarch() {  # $1 = target dir; clone verbatim, drop nested .git, rename the .sln to the project name
  local target="${1:-.}"
  command -v git >/dev/null 2>&1 || { echo "  ERROR: git missing; cannot include DevArchitecture."; return 1; }
  local tmp; tmp="$(mktemp -d)"
  echo "  Downloading: $DEVARCH_URL"
  if ! git clone --depth 1 "$DEVARCH_URL" "$tmp/da" >/dev/null 2>&1; then
    echo "  ERROR: clone failed (network/access?). Manually: git clone $DEVARCH_URL"
    rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp/da/.git"     # not a separate repo/submodule, included as verbatim files
  mkdir -p "$target"
  cp -R "$tmp/da/." "$target/"
  rm -rf "$tmp"
  # Rename the solution file to the project name (safe — the .sln name is independent of the projects it references).
  if [ -f "$target/DevArchitecture.sln" ] && [ "$PROJECT_NAME" != "DevArchitecture" ]; then
    mv "$target/DevArchitecture.sln" "$target/${PROJECT_NAME}.sln" && echo "  Renamed the solution to ${PROJECT_NAME}.sln."
  fi
  echo "  DevArchitecture base placed in: $([ "$target" = "." ] && echo 'the project root' || echo "$target/")."
  echo "  NOTE (§4.2): the template name still lives in namespaces / csproj / appsettings — as the FIRST"
  echo "  task, ask an agent to rename DevArchitecture -> ${PROJECT_NAME} throughout."
}

# --- Flag parsing (silent/CI mode) ---
PROFILE=""; STACK=""
for a in "$@"; do
  case "$a" in
    --backend) PROFILE="backend" ;;
    --frontend) PROFILE="frontend" ;;
    --mobile) PROFILE="mobile" ;;
    --fullstack) PROFILE="fullstack" ;;
    --dotnet) STACK="dotnet" ;;
    --generic) STACK="generic" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown parameter: $a"; echo; usage; exit 1 ;;
  esac
done

# ===================== COLOR / STYLE HELPERS =====================
# Color is emitted ONLY on an interactive TTY + TERM!=dumb + NO_COLOR empty.
# Otherwise all codes are '' => raw \033 does NOT leak in CI/pipe/dumb (NO_COLOR is respected).
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
  CY=$'\033[36m'; GR=$'\033[32m'; YE=$'\033[33m'; MG=$'\033[35m'
else
  R=''; B=''; D=''; CY=''; GR=''; YE=''; MG=''
fi
h1()   { printf '\n%s%s%s%s\n' "$B" "$CY" "$1" "$R"; }               # section heading
sub()  { printf '%s%s%s\n' "$D" "$1" "$R"; }                         # dim description
opt()  { # $1=no $2=label $3=is_default $4=right-badge
  local mark=''; [ "${3:-0}" = 1 ] && mark=" ${GR}${B}(default)${R}"
  printf '  %s%s%s)%s %s%-24s%s %s%s%s%s\n' "$B" "$YE" "$1" "$R" "$B" "$2" "$R" "$MG" "${4:-}" "$R" "$mark"
}
add()  { printf '     %s+%s %s\n'      "$GR" "$R" "$1"; }            # INSTALLED
skip() { printf '     %s-%s %s%s%s\n'  "$YE" "$R" "$D" "$1" "$R"; }  # NOT INSTALLED (tradeoff)
gate() { printf '     %s>%s %s\n'      "$CY" "$R" "$1"; }            # gate to be armed
row()  { printf '  %s%-15s%s %s\n'     "$B" "$1" "$R" "$2"; }        # summary row
rule() { printf '  %s------------------------------------------------%s\n' "$D" "$R"; }

h1  "Agentic Working Kit · setup wizard"
sub "3 steps: profile -> backend stack -> summary & confirm."

# ===================== STEP 1 · PROFILE =====================
# If a flag was given ($PROFILE non-empty) this block is SKIPPED entirely (non-interactive path preserved).
if [ -z "$PROFILE" ]; then
  h1  "[1/3] Project profile"
  sub "The choice determines the set of agents + skills to install."
  echo
  opt 1 "backend"   0 "~10 agents · ~24 skills"
  add  "backend-expert-csk · database-expert-csk + db / api / migration skills"
  skip "frontend-expert-csk and all UI skills (frontend/a11y/i18n) NOT INSTALLED"
  echo
  opt 2 "frontend"  0 "~9 agents · ~23 skills"
  add  "frontend-expert-csk + frontend / a11y / i18n skills"
  skip "backend-expert-csk · database-expert-csk and all server skills NOT INSTALLED"
  echo
  opt 3 "fullstack" 1 "~11 agents · ~27 skills"
  add  "everything — all agents + all skills (frontend + backend together)"
  echo
  opt 4 "mobile"    0 "~9 agents · ~24 skills"
  add  "frontend-expert-csk + React Native / Expo layer (frontend-rn-expo)"
  skip "backend-expert-csk · database-expert-csk NOT INSTALLED"
  echo
  printf '  %s->%s Choice %s[1-4, empty=3]%s: ' "$CY" "$R" "$D" "$R"
  read -r s || s=""                 # does not hang on EOF/non-TTY; empty => default (fullstack)
  case "$s" in 1) PROFILE="backend" ;; 2) PROFILE="frontend" ;; 4) PROFILE="mobile" ;; *) PROFILE="fullstack" ;; esac
fi

# ===================== STEP 2 · BACKEND STACK =====================
# Asked only for backend/fullstack; skipped if a flag is given.
HAS_BACKEND=0
case "$PROFILE" in backend|fullstack) HAS_BACKEND=1 ;; esac
if [ "$HAS_BACKEND" = 1 ] && [ -z "$STACK" ]; then
  h1  "[2/3] Backend stack"
  sub "Determines the backend template and whether the .NET-specific skills are included."
  echo
  opt 1 ".NET / DevArchitecture" 1 "full support"
  add  "devarch-module skill (opinionated MediatR CQRS)"
  gate "clones the DevArchitecture base project BEHIND AN APPROVAL GATE (greenfield project)"
  echo
  opt 2 "Generic" 0 "stack-agnostic"
  add  "stack-agnostic backend-expert-csk — adapts to the existing repo's pattern"
  skip "devarch-module and the DevArchitecture base NOT INSTALLED (sonarqube-check still installed)"
  echo
  printf '  %s->%s Choice %s[1-2, empty=1]%s: ' "$CY" "$R" "$D" "$R"
  read -r s || s=""                 # empty => default (dotnet)
  case "$s" in 2) STACK="generic" ;; *) STACK="dotnet" ;; esac
fi
[ "$HAS_BACKEND" = 1 ] || STACK="none"

# Project name (from the directory) + where the backend base lives.
PROJECT_NAME="$(basename "$PWD")"
PROJECT_NAME="$(printf '%s' "$PROJECT_NAME" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^[-._]*//; s/[-._]*$//')"
[ -n "$PROJECT_NAME" ] || PROJECT_NAME="App"
case "$PROFILE" in
  fullstack) BACKEND_DIR="backend" ;;   # keep the root clean; the frontend lives under ./frontend
  *)         BACKEND_DIR="." ;;          # backend-only: the project root IS the backend
esac

# --- Mappings: agents/skills to prune + DevArch gate ---
DEVARCH_ON=0
case "$PROFILE" in
  frontend)
    EXCL_AGENTS="backend-expert-csk.md database-expert-csk.md"
    EXCL_SKILLS="db-migration devarch-module frontend-rn-expo api-design" ;;
  mobile)
    EXCL_AGENTS="backend-expert-csk.md database-expert-csk.md"
    EXCL_SKILLS="db-migration devarch-module api-design" ;;
  backend)
    EXCL_AGENTS="frontend-expert-csk.md"
    EXCL_SKILLS="frontend frontend-rn-expo a11y" ;;
  fullstack)
    EXCL_AGENTS=""
    EXCL_SKILLS="" ;;
esac
if [ "$HAS_BACKEND" = 1 ]; then
  if [ "$STACK" = "dotnet" ]; then
    DEVARCH_ON=1
  else
    EXCL_SKILLS="$EXCL_SKILLS devarch-module"   # generic: devarch-module is .NET-specific; sonarqube-check is language-agnostic, kept
  fi
fi

# ===================== STEP 3 · SUMMARY + CONFIRM =====================
# This block comes AFTER the MAPPINGS (EXCL_AGENTS/EXCL_SKILLS/DEVARCH_ON) -> the count is pruned correctly.
# Count the agents/skills to install LIVE FROM SOURCE (not a hardcoded constant; self-corrects if the mappings change).
count_installed() {   # $1=EXCL list  $2=glob  -> count to install
  local excl=" $1 " n=0 base
  for p in $2; do
    [ -e "$p" ] || continue
    base="$(basename "$p")"
    case "$excl" in *" $base "*) ;; *) n=$((n+1)) ;; esac
  done
  printf '%s' "$n"
}
N_AG="$(count_installed "$EXCL_AGENTS" "$SRC/agents/*.md")"
N_SK="$(count_installed "$EXCL_SKILLS" "$SRC/skills/*/")"

case "$PROFILE" in
  backend)   P_TXT="backend ${D}— server / API / DB (no frontend)${R}" ;;
  frontend)  P_TXT="frontend ${D}— web UI (no backend)${R}" ;;
  mobile)    P_TXT="mobile ${D}— React Native / Expo (no backend)${R}" ;;
  fullstack) P_TXT="fullstack ${D}— end to end (widest)${R}" ;;
esac

h1 "[3/3] Summary · see what will be installed before you confirm"
echo
row "Profile" "${B}${P_TXT}${R}"
row "Included"  "${MG}${B}${N_AG}${R} agents · ${MG}${B}${N_SK}${R} skills will be installed"
if [ "$HAS_BACKEND" = 1 ]; then
  if [ "$STACK" = "generic" ]; then
    row "Backend stack" "non-.NET — generic ${D}(devarch-module not installed; sonarqube-check installed)${R}"
  else
    row "Backend stack" ".NET / DevArchitecture ${D}(full support)${R}"
  fi
fi
if [ "$DEVARCH_ON" = 1 ]; then
  row "DevArch base" "${YE}approval gate -> $([ "$BACKEND_DIR" = "." ] && echo 'project root' || echo "./$BACKEND_DIR")${R}"
elif [ "$HAS_BACKEND" = 1 ]; then
  row "DevArch base" "${D}not installed${R}"
fi
echo
printf '  %sSecurity gates armed on every install:%s\n' "$B" "$R"
gate "commit/push approval gate — even in auto/bypass mode (guard-bash)"
gate "trace scan — a git hook blocks AI traces / vendor names"
gate "real context measurement + handoff at 75% (Stop hook)"
gate "destructive command guard (rm -rf / force-push, etc.)"
echo
row "Will write" "${D}./.claude (agents·skills·commands·hooks·eval·settings.json) + ./CLAUDE.md${R}"
rule
echo
# ask_yes reads from stdin => in CI `printf 'yes\n' | bash start.sh` works; 'no' on EOF (no accidental install).
if ! ask_yes "  Install with these settings?"; then
  printf '  %sCancelled — nothing changed.%s\n' "$YE" "$R"
  exit 0
fi
echo

# --- Step 4: Backend base (only .NET/DevArchitecture; APPROVAL GATE) ---
if [ "$DEVARCH_ON" = 1 ]; then
  echo "== Backend base (DevArchitecture) =="
  [ "$BACKEND_DIR" = "." ] || echo "  Target: ./$BACKEND_DIR (the frontend stays separate under ./frontend)."
  if has_devarch "$BACKEND_DIR"; then
    echo "  DevArchitecture detected — base already present, skipping copy."
  elif project_has_source; then
    echo "  !!! WARNING: An existing project is present and the DevArchitecture backend base is MISSING."
    echo "  Adding it may cause file/structure conflicts and BREAK the project."
    echo "  This kit is meant for setting up a project FROM SCRATCH. Confirm if you still want to add it."
    if ask_yes "  Do you want to add DevArchitecture to this EXISTING project (risky)?"; then
      clone_devarch "$BACKEND_DIR" || echo "  Continuing without the backend base."
    else
      echo "  Skipped. The backend flow assumes DevArchitecture; you will need to adapt it manually."
    fi
  else
    echo "  Greenfield project: this kit can install the DevArchitecture backend base."
    if ask_yes "  Should I include the DevArchitecture backend base in the project now?"; then
      clone_devarch "$BACKEND_DIR" || echo "  Could not include the backend base; continuing with kit installation."
    else
      echo "  Skipped. You can add it manually later:  git clone $DEVARCH_URL"
    fi
  fi
  # Fullstack: reserve ./frontend so the layout is explicit (build the frontend here; the backend is in ./backend).
  if [ "$PROFILE" = "fullstack" ] && [ ! -e ./frontend ]; then
    mkdir -p frontend
    printf '# frontend\n\nBuild your frontend here (the `frontend-expert-csk` agent helps). The backend lives in `../backend`.\n' > frontend/README.md
    echo "  Reserved ./frontend for your frontend."
  fi
  echo
fi

# --- Step 5: Kit installation (./.claude + ./CLAUDE.md) — pruned by profile ---
echo "== Installing: ./.claude + ./CLAUDE.md =="
mkdir -p .claude/agents .claude/skills .claude/commands .claude/hooks .claude/eval
cp -R "$SRC/agents/."   .claude/agents/
cp -R "$SRC/skills/."   .claude/skills/
cp -R "$SRC/commands/." .claude/commands/
cp -R "$SRC/hooks/."    .claude/hooks/ 2>/dev/null || true
cp -R "$SRC/eval/."     .claude/eval/ 2>/dev/null || true
for f in $EXCL_AGENTS; do rm -f  ".claude/agents/$f"; done
for d in $EXCL_SKILLS; do rm -rf ".claude/skills/$d"; done
# Generic backend: install the stack-agnostic variant instead of the DevArchitecture-bound backend-expert-csk.
if [ "$HAS_BACKEND" = 1 ] && [ "$STACK" = "generic" ] && [ -f "$SRC/agents-optional/backend-expert-generic.md" ]; then
  cp "$SRC/agents-optional/backend-expert-generic.md" .claude/agents/backend-expert-csk.md
fi
echo "  Profile '$PROFILE' (stack: $STACK): $(ls .claude/agents/*.md 2>/dev/null | wc -l | tr -d ' ') agents, $(ls -d .claude/skills/*/ 2>/dev/null | wc -l | tr -d ' ') skills installed."
[ -f "$SRC/settings.json" ] && cp "$SRC/settings.json" .claude/settings.json
[ -f "$HERE/VERSION" ] && cp "$HERE/VERSION" .claude/VERSION   # make the kit version trackable in the installed project
chmod +x .claude/hooks/pre-commit .claude/hooks/commit-msg .claude/hooks/guard-bash.sh .claude/hooks/context-usage.sh .claude/hooks/session-guard.sh .claude/eval/smoke-test.sh .claude/eval/routing-eval.sh 2>/dev/null || true
cp "$SRC/AGENT_TEMPLATE.md" .claude/ 2>/dev/null || true
cp "$SRC/FIRST_PROMPT.md"   .claude/ 2>/dev/null || true
cp "$SRC/README.md"         .claude/ 2>/dev/null || true
if [ -f ./CLAUDE.md ]; then
  echo "  ./CLAUDE.md exists — merge manually (left untouched)."
else
  cp "$SRC/CLAUDE.md" ./CLAUDE.md
  echo "  ./CLAUDE.md created — EDIT the project section."
fi
touch .gitignore
for e in 'docs/' '.claude/' 'CLAUDE.md'; do grep -qxF "$e" .gitignore || echo "$e" >> .gitignore; done
if [ -d .git ]; then
  git config core.hooksPath .claude/hooks
  echo "  trace scan: core.hooksPath -> .claude/hooks (§4.1/§4.2 commit gate active)"
else
  echo "  NOTE: no git repository; after 'git init' run:  git config core.hooksPath .claude/hooks"
fi
rm -rf "$SRC"
echo
echo "== Done. ./.claude + ./CLAUDE.md ready ($PROFILE/$STACK); claude-starter/ deleted. =="
echo "Next: 1) fill in the CLAUDE.md project section  2) open Claude Code at the repo root"
echo "Tip:  paste .claude/FIRST_PROMPT.md as your first Claude Code message — an optional kickoff (verifies the agents/skills, plans the first sprint). CLAUDE.md loads the discipline every session either way."
[ "$PROFILE" = "fullstack" ] && [ "$STACK" = "dotnet" ] && echo "Layout: backend in ./backend · build your frontend in ./frontend · first agent task: rename DevArchitecture -> $PROJECT_NAME."
rm -f -- "$0"
