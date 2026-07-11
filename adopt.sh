#!/usr/bin/env bash
# kit adopt — hands the kit OVER (handover) to an EXISTING project, brownfield-safe.
# Later becomes the `kit adopt` subcommand. Handover philosophy: don't break the project · don't lose decisions made ·
# don't leave the kit passive (100% hybrid). Kit agents are namespaced with -csk -> no clash with project agents.
#
# >>> STAGE 1: detection + smart suggestion only. CHANGES NOTHING (read-only). <<<
# Later stages: open git branch -> mutation (settings merge · DISCIPLINE.md · coexist) -> install proof
# -> HANDOVER.md / ADR. The SUGGESTION produced here for each decision is applied in the next stage via review/override.
#
# Usage: at the target project root (same directory as claude-starter/):  bash adopt.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/claude-starter"
[ -d "$SRC" ] || { echo "ERROR: claude-starter/ not found (must be in the same directory as adopt.sh)."; exit 1; }

# --- color: only on an interactive TTY (same guard as start.sh) ---
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'; CY=$'\033[36m'; GR=$'\033[32m'; YE=$'\033[33m'; MG=$'\033[35m'
else R=''; B=''; D=''; CY=''; GR=''; YE=''; MG=''; fi
h1()  { printf '\n%s%s%s%s\n' "$B" "$CY" "$1" "$R"; }
sub() { printf '%s%s%s\n' "$D" "$1" "$R"; }
row() { printf '  %s%-20s%s %s\n' "$B" "$1" "$R" "$2"; }
warn(){ printf '  %s!%s %s%s%s\n' "$YE" "$R" "$YE" "$1" "$R"; }
# smart suggestion line:  number+decision · SUGGESTED(green) · rationale(dim)
prop(){ printf '  %s%-18s%s %s%-24s%s %s%s%s\n' "$B" "$1" "$R" "$GR" "$2" "$R" "$D" "$3" "$R"; }
ask_yes(){ local a; printf '%s [yes/no]: ' "$1"; read -r a || a=""; case "$a" in [yY]|[yY][eE][sS]|[eE]|[eE][vV][eE][tT]) return 0;; *) return 1;; esac; }
# never-overwrite copy: does NOT overwrite an EXISTING target file (project file is preserved), skips+counts.
# Result globals: ret_add / ret_skip; conflicts are added to SKIP_LIST. Do NOT call in a subshell (globals are lost).
SKIP_LIST=""
# $4 = space-separated names to SKIP entirely, matched against the first path component of each source file
# ('frontend-expert-csk.md' for agents/, 'a11y' for skills/). We skip rather than copy-then-delete: a project
# may own a directory of the same name, and a refresh must never remove the project's own files.
copy_noclobber(){ local src="$1" dst="$2" force="${3:-0}" excl=" ${4:-} " rel top f; ret_add=0; ret_skip=0; [ -d "$src" ] || return; mkdir -p "$dst"
  while IFS= read -r f; do rel="${f#"$src"/}"; top="${rel%%/*}"
    case "$excl" in *" $top "*) continue ;; esac
    if [ -e "$dst/$rel" ] && [ "$force" != 1 ]; then ret_skip=$((ret_skip+1)); SKIP_LIST="$SKIP_LIST $dst/$rel"
    else mkdir -p "$dst/$(dirname "$rel")"; cp "$f" "$dst/$rel"; ret_add=$((ret_add+1)); fi
  done < <(find "$src" -type f 2>/dev/null); }

# --- CLAUDE.md split (shared contract with start.sh; keep the two in lockstep) ---
IMPORT_LINE='@.claude/DISCIPLINE.md'
# Sentinel matched ANCHORED to line start, so prose that merely names the token is never mistaken for the split
# point. Abort loudly if it is gone: a silent miss ships the ENTIRE template as "discipline" — which is exactly
# what the previous '<PROJE ADI>' marker did once the payload was translated to English.
kit_require_sentinel() { grep -qE '^<!-- KIT:DISCIPLINE-END' "$1" || { echo "ERROR: the '<!-- KIT:DISCIPLINE-END' sentinel line is missing from $1 — refusing to guess the discipline/project split."; exit 1; }; }
kit_discipline_of()    { awk '/^<!-- KIT:DISCIPLINE-END/{exit} {print}' "$1"; }
kit_project_of()       { awk 'f{print} /^<!-- KIT:DISCIPLINE-END/{f=1}' "$1"; }
# Anchored: the import must BE the line, not merely be mentioned in prose (the discipline text names the path).
kit_has_import()       { grep -qE '^[[:space:]]*@\.claude/DISCIPLINE\.md[[:space:]]*$' "$1" 2>/dev/null; }
# A pre-1.1 install pasted the whole discipline inline into CLAUDE.md; adding the @import would load it twice.
# Both markers are required: a project that happens to write its own "Four working principles" heading is NOT a
# legacy kit install, and treating it as one would leave it without the discipline forever.
kit_claude_md_is_legacy() {
  grep -q '^## Four working principles' "$1" 2>/dev/null && grep -qE '^### 4\.[45] ' "$1" 2>/dev/null
}
# Where does the project section of a legacy CLAUDE.md begin? Line 1 is the discipline's own '# CLAUDE.md — Working
# rules' heading, so look from line 2 on. Fallback: the first '# ' heading after the §4.5 block (covers a renamed
# heading). Capture the output — `awk … && return` would return on awk's exit status even when it printed nothing.
kit_legacy_boundary() {
  local n
  n="$(awk 'NR>1 && /^# CLAUDE\.md/{print NR; exit}' "$1" 2>/dev/null)"
  [ -n "$n" ] || n="$(awk '/^### 4\.5 /{f=1;next} f && /^# /{print NR; exit}' "$1" 2>/dev/null)"
  printf '%s' "$n"
}
# A project installed before kit.conf existed carries its shape only in what is on disk. Read it back, so an
# update reshapes it the way it was installed instead of silently re-adding what the profile pruned.
kit_infer_shape() {
  local fe=0 be=0 rn=0
  [ -f .claude/agents/frontend-expert-csk.md ] && fe=1
  [ -f .claude/agents/backend-expert-csk.md ]  && be=1
  [ -d .claude/skills/frontend-rn-expo ]       && rn=1
  if   [ "$be" = 1 ] && [ "$fe" = 1 ]; then KIT_PROFILE=fullstack
  elif [ "$be" = 1 ];                  then KIT_PROFILE=backend
  elif [ "$fe" = 1 ] && [ "$rn" = 1 ]; then KIT_PROFILE=mobile
  elif [ "$fe" = 1 ];                  then KIT_PROFILE=frontend
  else                                      KIT_PROFILE=fullstack; fi   # nothing to go on -> install everything
  # A .NET stack is marked by the devarch-module skill being installed; the generic stack prunes it. (The
  # backend agent itself is pattern-neutral now, so its text is no longer a reliable stack signal.)
  if [ "$be" = 1 ]; then
    if [ -d .claude/skills/devarch-module ]; then KIT_STACK=dotnet; else KIT_STACK=generic; fi
  else KIT_STACK=none; fi
  KIT_INSTALLER="${KIT_INSTALLER:-pre-kit.conf}"
  INFERRED=1
}
# tr -d '\r' on both readers: a CRLF file (Windows checkout, or kit.conf reopened in Notepad) would otherwise
# glue '\r' to every value — 'backend\r' matches no profile row, and the refresh would silently prune nothing.
kit_conf_get()         { [ -f .claude/kit.conf ] && sed -n "s/^$1=//p" .claude/kit.conf | head -1 | tr -d '\r'; }
# Profile -> pruned agents/skills. Same profiles.conf start.sh installs from: the two cannot drift.
kit_profile_field()    { sed -n "s/^$1://p" "$SRC/profiles.conf" 2>/dev/null | head -1 | tr -d '\r' | cut -d: -f"$2"; }
kit_excl_agents_for()  { kit_profile_field "$1" 1; }
kit_excl_skills_for()  { kit_profile_field "$1" 2; }

h1 "kit adopt · Stage 1 — DETECTION (read-only; nothing changes)"
sub "Reads the existing project, produces a smart suggestion for the 7 handover decisions. Approval + mutation in the next stage."

# ========================= [1] ENVIRONMENT =========================
h1 "[1] Environment"
# git context — in a worktree/submodule .git is a FILE (do NOT use [ -d .git ]; red-team hole #6)
IS_GIT=0; GITTOP=""; GITKIND="no git — 'git init' required"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IS_GIT=1; GITTOP="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
  if [ -f "$GITTOP/.git" ]; then GITKIND="worktree/submodule (.git file)"; else GITKIND="normal repo"; fi
fi
row "git" "$GITKIND"

# existing hook system (decision #5 — single-hooksPath clash with husky/lefthook)
HOOKSYS="none"
CURHP="$(git config --get core.hooksPath 2>/dev/null || true)"
case "$CURHP" in
  "") : ;;
  .claude/hooks|.claude/git-shim) HOOKSYS="kit (already armed)"; CURHP="" ;;   # kit's OWN path — not a foreign chain (re-adopt must not shim itself)
  *) HOOKSYS="core.hooksPath=$CURHP" ;;
esac
[ -d .husky ] && HOOKSYS="husky (.husky/)"
{ [ -f lefthook.yml ] || [ -f .lefthook.yml ]; } && HOOKSYS="lefthook"
[ -f .pre-commit-config.yaml ] && HOOKSYS="pre-commit framework"
row "git hook system" "$HOOKSYS"

# stack hint (context). Look PAST the root: a .NET solution commonly lives in ./backend, ./src, ./server — the
# old root-only `ls ./*.sln` reported "unknown" for exactly those layouts and the install silently fell back to
# generic (dropping the DevArch pattern skill). Search a few levels deep, skipping build/vendor dirs.
STACK="unknown"; IS_DOTNET=0; IS_DEVARCH=0
DOTNET_HIT="$(find . -maxdepth 3 \( -name '*.sln' -o -name '*.csproj' \) 2>/dev/null | grep -vE '/(bin|obj|node_modules|\.git)/' | head -1)"
if [ -n "$DOTNET_HIT" ]; then
  STACK=".NET"; IS_DOTNET=1
  # DevArchitecture signature: the canonical Business/Handlers CQRS layout, or a solution literally named DevArchitecture.
  { find . -maxdepth 4 -type d -path '*/Business/Handlers' 2>/dev/null | grep -q . \
    || find . -maxdepth 3 -iname 'devarchitecture.sln' 2>/dev/null | grep -q .; } && IS_DEVARCH=1
elif [ -f package.json ]; then STACK="Node/JS"
elif [ -f go.mod ]; then STACK="Go"
elif [ -f pyproject.toml ] || [ -f requirements.txt ]; then STACK="Python"; fi
row "stack hint" "$STACK$([ "$IS_DEVARCH" = 1 ] && echo " · DevArchitecture layout detected")"

# ================= [2] EXISTING AGENTIC SETUP =================
h1 "[2] Existing agentic setup (accumulated work to inherit)"
HAS_CLAUDE=0; [ -d .claude ] && HAS_CLAUDE=1
# count only the PROJECT's own agents/skills — exclude the kit's -csk agents and kit skills left by a prior adopt
N_PAGENTS=0; [ -d .claude/agents ] && N_PAGENTS="$(find .claude/agents -name '*.md' ! -name '*-csk.md' 2>/dev/null | wc -l | tr -d ' ')"
N_PSKILLS=0
if [ -d .claude/skills ]; then
  while IFS= read -r f; do d="$(basename "$(dirname "$f")")"; [ -d "$SRC/skills/$d" ] || N_PSKILLS=$((N_PSKILLS+1)); done < <(find .claude/skills -name 'SKILL.md' 2>/dev/null)
fi
# Same-domain agent overlap: a PROJECT agent whose base name matches a kit -csk agent (e.g. backend-expert vs
# backend-expert-csk). The two describe the same job, so the router has to pick between them — plain coexist
# leaves that ambiguous and the project's older agent tends to win, which defeats installing the kit. Collect
# the overlaps so the handover can RESOLVE them, not merely note them.
COLLIDE=""
if [ -d .claude/agents ]; then
  for kf in "$SRC"/agents/*-csk.md; do b="$(basename "$kf" -csk.md)"; [ -f ".claude/agents/$b.md" ] && COLLIDE="$COLLIDE $b"; done
fi
COLLIDE="${COLLIDE# }"; N_COLLIDE=0; [ -n "$COLLIDE" ] && N_COLLIDE="$(printf '%s\n' $COLLIDE | wc -l | tr -d ' ')"
HAS_MD=0; [ -f CLAUDE.md ] && HAS_MD=1
HAS_SETTINGS=0; [ -f .claude/settings.json ] && HAS_SETTINGS=1
# already-adopted fingerprint: did a PRIOR adopt/kit install run here? -> REFRESH semantics, not a fresh handover
KIT_PRESENT=0; KIT_VER=""
{ [ -f .claude/DISCIPLINE.md ] || [ -d .claude/git-shim ] || ls .claude/agents/*-csk.md >/dev/null 2>&1 || [ -f .claude/VERSION ]; } && KIT_PRESENT=1
[ -f .claude/VERSION ] && KIT_VER="$(head -1 .claude/VERSION 2>/dev/null)"
# Shape of the existing install, remembered by whichever installer put it here. An update must refresh the
# project in the SAME shape: a backend-only install must not have frontend agents grafted back on, and a
# .NET install must not have its DevArch backend agent swapped for the generic one.
KIT_PROFILE="$(kit_conf_get profile)"; KIT_STACK="$(kit_conf_get stack)"; KIT_INSTALLER="$(kit_conf_get installer)"
# No kit.conf means the project predates it (v1.0.x). Recover the shape from the files themselves, or the
# refresh would hand a backend-only project the frontend agents and swap its .NET expert for the generic one.
INFERRED=0
{ [ "$KIT_PRESENT" = 1 ] && [ -z "$KIT_PROFILE" ]; } && kit_infer_shape
row ".claude/" "$([ "$HAS_CLAUDE" = 1 ] && echo "present — $N_PAGENTS project agents · $N_PSKILLS project skills" || echo "none")"
row "CLAUDE.md" "$([ "$HAS_MD" = 1 ] && echo "present" || echo "none")"
row "settings.json" "$([ "$HAS_SETTINGS" = 1 ] && echo "present" || echo "none")"
[ "$KIT_PRESENT" = 1 ] && row "kit status" "${YE}already adopted${KIT_VER:+ (v$KIT_VER)} — this run REFRESHES kit files, project untouched${R}"
[ -n "$KIT_PROFILE" ] && row "$([ "$INFERRED" = 1 ] && echo 'inferred shape' || echo 'recorded shape')" \
  "profile=${KIT_PROFILE} · stack=${KIT_STACK:-?}$([ "$INFERRED" = 1 ] && echo " ${YE}(no kit.conf — read back from the installed files)${R}" || echo " · via ${KIT_INSTALLER:-?}") — the refresh keeps it"

# tracked in git? (decision #4 — share/hide)
TRACKED=0
if [ "$IS_GIT" = 1 ]; then
  git ls-files --error-unmatch CLAUDE.md >/dev/null 2>&1 && TRACKED=1
  { [ "$HAS_CLAUDE" = 1 ] && [ -n "$(git ls-files .claude 2>/dev/null | head -1)" ]; } && TRACKED=1
fi
row ".claude/CLAUDE.md in git" "$([ "$TRACKED" = 1 ] && echo "YES — shared with the team" || echo "no/untracked")"

# co-author/sign-off convention (decision #3)
COAUTHOR=0
[ "$IS_GIT" = 1 ] && git log -80 --format='%b' 2>/dev/null | grep -qiE 'Co-Authored[-]By|Signed-off-by' && COAUTHOR=1  # [-] : not a contiguous literal in source (trace hook)

# off-repo hint (decision #7 — decisions may live in chat/on the web)
OFFREPO=0; { [ "$HAS_CLAUDE" = 0 ] && [ "$HAS_MD" = 0 ]; } && OFFREPO=1

# ===================== [3] SMART SUGGESTION ======================
h1 "[3] 7 handover decisions — SMART SUGGESTION"
sub "format:  decision  ->  SUGGESTED  ->  rationale   (you can review and override all of them in the next stage)"
if [ "$N_COLLIDE" != 0 ]; then
  prop "1 Role overlap" "kit takes over" "$N_COLLIDE project agent(s) cover the SAME job as a kit agent ($COLLIDE) — routing is ambiguous; kit wins, yours preserved"
elif [ "$N_PAGENTS" != 0 ]; then
  prop "1 Role clash" "keep (coexist)" "$N_PAGENTS project agents, none overlap a kit role; thanks to -csk they live side by side"
else
  prop "1 Role clash" "none" "no custom agents found in the project"
fi
prop "2 Precedence" "project wins (fixed)" "on conflict the project's rules always win; the kit fills gaps (not overridable)"
if [ "$COAUTHOR" = 1 ]; then
  prop "3 Trace gate" "loosen (.trace-allowlist)" "co-author/sign-off present in git log — may be a convention"
else
  prop "3 Trace gate" "keep" "no co-author/sign-off convention seen"
fi
if [ "$TRACKED" = 1 ]; then
  prop "4 Share/hide" "share" ".claude/CLAUDE.md is tracked — keep sharing with the team"
else
  prop "4 Share/hide" "share" "untracked; kit files are shared by default — pick hide to keep them local"
fi
if [ "$HOOKSYS" = "none" ]; then
  prop "5 Git hooks" "install directly" "no existing hook system"
else
  prop "5 Git hooks" "SHIM (bridge)" "existing $HOOKSYS present — let both run"
fi
prop "6 Brownfield DoD" "baseline+regression" "existing code debt unknown; absolute 0/0/0/0 is risky"
if [ "$OFFREPO" = 1 ]; then
  warn "7 Off-repo: no local .claude/CLAUDE.md — decisions may live in chat/on the web; there is context I CANNOT SEE."
  prop "  -> suggestion" "you transfer" "in the mutation stage 'paste if any' is asked; goes into HANDOVER.md"
else
  prop "7 Off-repo" "local + ask" "some decisions are in files; still may be in-chat (asked during the stage)"
fi

# ============ COMPILE DECISIONS + OVERRIDE (Stage B) ============
DEC1="$([ "$N_PAGENTS" != 0 ] && echo keep || echo none)"
DEC2="project"   # precedence is FIXED to project-wins (not overridable — reflected in the @import comment)
DEC3="$([ "$COAUTHOR" = 1 ] && echo loosen || echo keep)"
DEC4="$([ "$TRACKED" = 1 ] && echo share || echo kit-default)"
DEC6="baseline"
DEC7="$([ "$OFFREPO" = 1 ] && echo transfer || echo local)"
# normalize display defaults to a real, offered token
[ "$DEC1" = none ] && DEC1=keep
[ "$DEC4" = kit-default ] && DEC4=share
if [ -t 0 ]; then
  h1 "Review the decisions"
  # ask_dec: echoes the chosen value to STDOUT; ALL prompts/errors go to STDERR so $(...) captures only the value
  ask_dec(){ local label="$1" a="$2" b="$3" cur="$4" v fa fb; fa="${a:0:1}"; fb="${b:0:1}"
    while :; do
      printf '  %s%s%s [%s/%s] (current: %s%s%s, ENTER=keep): ' "$B" "$label" "$R" "$a" "$b" "$B" "$cur" "$R" >&2
      read -r v || v=""
      case "$v" in
        "")         echo "$cur"; return ;;
        "$a"|"$fa") echo "$a";   return ;;
        "$b"|"$fb") echo "$b";   return ;;
        *) printf '     %s! type "%s" or "%s" (or ENTER to keep "%s")%s\n' "$YE" "$a" "$b" "$cur" "$R" >&2 ;;
      esac
    done; }
  if ask_yes "Accept all smart suggestions?"; then
    sub "All smart suggestions accepted."
  else
    sub "Reviewing each decision. ENTER keeps the current value. (#1 overlap and #2/#5 are handled separately below.)"
    DEC3="$(ask_dec '#3 Trace gate'     loosen   keep     "$DEC3")"
    DEC4="$(ask_dec '#4 Share/hide'     share    hide     "$DEC4")"
    DEC6="$(ask_dec '#6 Brownfield DoD' baseline absolute "$DEC6")"
    DEC7="$(ask_dec '#7 Off-repo'       transfer skip     "$DEC7")"
  fi
  echo "  Final: #3=$DEC3 #4=$DEC4 #6=$DEC6 #7=$DEC7  (#2 project-wins, #5 SHIM — fixed)"
else
  sub "(non-interactive: smart defaults accepted)"
fi

# --- Backend stack (fresh adopt only) --------------------------------------------------------------------
# A REFRESH keeps the recorded stack (kit.conf / inferred). A FRESH adopt used to fall back to generic whenever
# the root had no .sln — wrong for a solution under ./backend. Decide it from the deeper detection, and confirm
# when a TTY is present. Setting KIT_STACK here feeds the existing prune/kit.conf logic below.
if [ -z "${KIT_STACK:-}" ] && [ "$KIT_PRESENT" != 1 ]; then
  if [ "$IS_DOTNET" = 1 ]; then
    KIT_STACK=dotnet
    if [ -t 0 ]; then
      h1 "Backend stack"
      sub "Detected a .NET project$([ "$IS_DEVARCH" = 1 ] && echo ' with a DevArchitecture (Business/Handlers CQRS) layout')."
      ask_yes "Install the .NET/DevArchitecture backend pattern (devarch-module)? (no = stack-agnostic generic)" || KIT_STACK=generic
    fi
  else
    KIT_STACK=generic
  fi
  echo "  backend stack -> ${KIT_STACK}$([ "$IS_DEVARCH" = 1 ] && [ "$KIT_STACK" = dotnet ] && echo ' (DevArchitecture)')"
fi

# --- Refresh: correct a stale/wrong recorded stack -------------------------------------------------------
# Normally a REFRESH trusts the recorded stack over a sniff, so a sniff miss can't flip a dotnet install to
# generic. But a recorded 'generic' on a project that is CLEARLY DevArchitecture (Business/Handlers + a .sln)
# is a stale record from the old root-only sniff — keeping it would prune devarch-module and hold the generic
# backend agent on a .NET/DevArch project. Surface the mismatch and offer to correct it; never flip silently.
if [ "$KIT_PRESENT" = 1 ] && [ "$KIT_STACK" = generic ] && [ "$IS_DEVARCH" = 1 ]; then
  h1 "Recorded backend stack looks wrong"
  warn "kit.conf records stack=generic, but this project has a DevArchitecture layout (Business/Handlers + a .sln)."
  sub "Left as-is, the refresh keeps pruning devarch-module and holds the generic backend agent."
  if [ ! -t 0 ] || ask_yes "Correct it to dotnet? (install the DevArchitecture pattern skill + the .NET backend agent)"; then
    KIT_STACK=dotnet; echo "  stack corrected -> dotnet (DevArchitecture)"
  else
    echo "  kept stack=generic (your choice)"
  fi
fi

# --- Role overlap (#1): resolve same-domain agent collisions ---------------------------------------------
# When a project agent and a kit -csk agent cover the same job, "coexist" leaves routing ambiguous. Offer to
# resolve it. takeover = kit wins (your agent preserved, moved out of the routing pool); keepmine = your agent
# wins (the kit's overlapping -csk is not installed); coexist = keep both (documented). Non-interactive -> takeover
# (you ran adopt to get the kit's agents). The chosen mode is APPLIED on the handover branch in Stage 2.
COLLIDE_MODE=coexist
if [ "$N_COLLIDE" != 0 ]; then
  h1 "Role overlap — project & kit both cover: $COLLIDE"
  sub "Two agents for one job = the router picks one, usually your older agent — so the kit's would sit idle."
  sub "  takeover  kit's -csk agents win; your versions are preserved under .claude/superseded/agents/"
  sub "  keepmine  your agents win; the kit's overlapping -csk agents are not installed"
  sub "  coexist   keep both (routing stays ambiguous; only documented in HANDOVER)"
  COLLIDE_MODE=takeover
  if [ -t 0 ]; then
    while :; do
      printf '  %sowner%s [takeover/keepmine/coexist] (ENTER=takeover): ' "$B" "$R"
      read -r _v || _v=""
      case "$_v" in ""|t|takeover) COLLIDE_MODE=takeover; break ;; k|keepmine) COLLIDE_MODE=keepmine; break ;; c|coexist) COLLIDE_MODE=coexist; break ;;
        *) printf '     %s! type takeover, keepmine or coexist%s\n' "$YE" "$R" >&2 ;; esac
    done
  fi
  echo "  overlap -> $COLLIDE_MODE"
fi
# #1 display/HANDOVER value reflects what actually happens.
case "$COLLIDE_MODE" in
  takeover) DEC1=takeover ;; keepmine) DEC1=keepmine ;;
  *) DEC1="$([ "$N_PAGENTS" != 0 ] && echo keep || echo none)" ;;
esac

# ================= [STAGE 2] HANDOVER BRANCH + COEXIST =================
h1 "Stage 2 — handover branch + coexist"
sub "Installs the kit on a SEPARATE git branch; does NOT touch project files (never-overwrite). Review the diff, roll back with git."
if [ "$IS_GIT" != 1 ]; then
  warn "no git repo — cannot open a handover branch. First:  git init && git add -A && git commit -m init  (then run again)."
  exit 0
fi
if ! ask_yes "Open the handover branch and apply coexist? (mutation; the result can be rolled back with git)"; then
  h1 "Stopped"; sub "Stayed at Stage 1 — NOTHING CHANGED (read-only)."; exit 0
fi

BASE="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
case "$BASE" in kit-adopt-*) warn "HEAD is a prior adopt branch ($BASE) — the review diff will be vs it, not your main line. Consider 'git checkout <main>' first." ;; esac
TS="$(date +%Y%m%d-%H%M%S)"; BR="kit-adopt-$TS"
# The timestamp is only second-resolution, so two adopts in the same repo within one second would collide on the
# branch name and the second `checkout -b` would fail. Append a counter until the name is free (also covers a
# re-run after a discarded attempt left the branch behind).
n=2; while git rev-parse --verify -q "refs/heads/$BR" >/dev/null 2>&1; do BR="kit-adopt-$TS-$n"; n=$((n+1)); done
git checkout -b "$BR" >/dev/null 2>&1 || { echo "ERROR: could not open branch '$BR'."; exit 1; }
echo "  handover branch: ${B}$BR${R}  (${BASE} stays clean)"

mkdir -p .claude
# Honour the shape recorded at install time. A fresh adopt has no kit.conf and installs the full payload
# (adopt = fullstack by definition); a refresh of a start.sh install prunes exactly what that profile pruned,
# so new kit files still land while frontend agents never reappear in a backend-only project.
EXCL_A=""; EXCL_S=""
if [ -n "$KIT_PROFILE" ] && grep -qE "^$KIT_PROFILE:" "$SRC/profiles.conf" 2>/dev/null; then
  EXCL_A="$(kit_excl_agents_for "$KIT_PROFILE")"
  EXCL_S="$(kit_excl_skills_for "$KIT_PROFILE")"
  echo "  refreshing as profile '${KIT_PROFILE}' (stack: ${KIT_STACK:-?}) — pruned agents/skills stay pruned"
fi
# The .NET pattern skill ships only for a dotnet backend. Prune it for generic on a FRESH adopt too (not only a
# recorded refresh) — otherwise a generic project silently carries a DevArch pattern skill it never uses.
[ "$KIT_STACK" = "generic" ] && EXCL_S="$EXCL_S devarch-module"
# #1 keepmine: your overlapping agents own those roles, so the kit's matching -csk agents are NOT installed.
[ "$COLLIDE_MODE" = keepmine ] && for b in $COLLIDE; do EXCL_A="$EXCL_A $b-csk.md"; done
# kit-owned trees: FORCE-refresh on a re-adopt (KIT_PRESENT) so kit updates land; never-overwrite on a fresh adopt
copy_noclobber "$SRC/agents"   .claude/agents   "$KIT_PRESENT" "$EXCL_A"; A_ADD=$ret_add; A_SKIP=$ret_skip
copy_noclobber "$SRC/skills"   .claude/skills   "$KIT_PRESENT" "$EXCL_S"; S_ADD=$ret_add; S_SKIP=$ret_skip
copy_noclobber "$SRC/commands" .claude/commands "$KIT_PRESENT"; C_ADD=$ret_add; C_SKIP=$ret_skip
copy_noclobber "$SRC/hooks"    .claude/hooks    "$KIT_PRESENT"; H_ADD=$ret_add; H_SKIP=$ret_skip
copy_noclobber "$SRC/eval"     .claude/eval     "$KIT_PRESENT"; E_ADD=$ret_add; E_SKIP=$ret_skip
# #1 takeover: move each overlapping PROJECT agent OUT of the routing pool (Claude Code discovers .claude/agents/*.md,
# not subdirs), so the kit's -csk owns the role and the router is no longer ambiguous. Moved, never deleted: your
# agent's domain knowledge is preserved under .claude/superseded/agents/ for you to fold into a project skill.
N_TAKEN=0
if [ "$COLLIDE_MODE" = takeover ] && [ -n "$COLLIDE" ]; then
  mkdir -p .claude/superseded/agents
  for b in $COLLIDE; do
    [ -f ".claude/agents/$b.md" ] && mv ".claude/agents/$b.md" ".claude/superseded/agents/$b.md" 2>/dev/null \
      && { N_TAKEN=$((N_TAKEN+1)); echo "  overlap: $b -> .claude/superseded/agents/ (kit's $b-csk now owns the role)"; }
  done
fi
# Stack-compatible backend: non-.NET projects get the generic backend-expert-csk. A RECORDED stack always beats
# repo sniffing — a refresh of a 'dotnet' install must keep the DevArch-bound agent even when the .sln lives in
# ./backend and the sniffer reports "unknown". And never clobber a preserved project file.
WANT_GENERIC=0
if [ -n "$KIT_STACK" ]; then [ "$KIT_STACK" = "generic" ] && WANT_GENERIC=1
elif [ "$STACK" != ".NET" ]; then WANT_GENERIC=1; fi
if [ "$WANT_GENERIC" = 1 ] && [ -f "$SRC/agents-optional/backend-expert-generic.md" ] && [ -e .claude/agents/backend-expert-csk.md ]; then
  case " $SKIP_LIST " in
    *" .claude/agents/backend-expert-csk.md "*) warn "backend-expert-csk.md pre-existed (preserved) — generic variant NOT applied" ;;
    *) cp "$SRC/agents-optional/backend-expert-generic.md" .claude/agents/backend-expert-csk.md; echo "  backend-expert-csk -> generic variant (${KIT_STACK:-$STACK})" ;;
  esac
elif [ "$KIT_STACK" = "dotnet" ] && [ -e .claude/agents/backend-expert-csk.md ]; then
  echo "  backend-expert-csk kept on the .NET/DevArchitecture variant (recorded stack: dotnet)"
fi
chmod +x .claude/hooks/*.sh .claude/hooks/pre-commit .claude/hooks/commit-msg 2>/dev/null || true
[ -f "$HERE/VERSION" ] && cp "$HERE/VERSION" .claude/VERSION 2>/dev/null || true   # first-class marker so a future adopt detects a REFRESH
# Record (or re-record) the shape so the NEXT update refreshes this project the same way.
{ echo "# Written by the kit installer. The updater reads this to refresh the project in its original shape."
  echo "profile=${KIT_PROFILE:-fullstack}"
  echo "stack=${KIT_STACK:-$([ "$WANT_GENERIC" = 1 ] && echo generic || echo dotnet)}"
  echo "installer=${KIT_INSTALLER:-adopt.sh}"
  echo "version=$( [ -f "$HERE/VERSION" ] && head -1 "$HERE/VERSION" || echo unknown )"
} > .claude/kit.conf

h1 "Coexist summary"
row "kit agents (-csk)" "+$A_ADD added$([ "$A_SKIP" != 0 ] && echo " · $A_SKIP skipped")"
row "skills"            "+$S_ADD$([ "$S_SKIP" != 0 ] && echo " · $S_SKIP skipped")"
row "commands"           "+$C_ADD$([ "$C_SKIP" != 0 ] && echo " · $C_SKIP skipped")"
row "hooks"           "+$H_ADD$([ "$H_SKIP" != 0 ] && echo " · $H_SKIP skipped")"
row "eval"               "+$E_ADD"
row "project agents"     "$N_PAGENTS$([ "${N_TAKEN:-0}" != 0 ] && echo " ($N_TAKEN handed to the kit, preserved under .claude/superseded/agents/)") — the rest UNTOUCHED"
case "$COLLIDE_MODE" in
  keepmine) [ "$N_COLLIDE" != 0 ] && row "overlap" "keepmine — your agents own: $COLLIDE (kit's -csk for these NOT installed)" ;;
  coexist)  [ "$N_COLLIDE" != 0 ] && warn "overlap: $COLLIDE — BOTH kept; routing between your agent and the kit's -csk stays ambiguous" ;;
esac
[ -n "$SKIP_LIST" ] && { warn "conflicting files (the project's was PRESERVED, the kit's skipped):"; for s in $SKIP_LIST; do printf '     %s- %s%s\n' "$D" "$s" "$R"; done; }

# ============ [STAGE 3] DISCIPLINE ACTIVE + SETTINGS MERGE ============
h1 "Stage 3 — activate the kit discipline (without touching the project CLAUDE.md) + settings merge"

# 3a) DISCIPLINE.md: install the discipline half of the payload CLAUDE.md as a separate, FLAT file —
#     everything above the sentinel line. Contains NO @import (leaf) -> no 4-hop trap.
if [ -f "$SRC/CLAUDE.md" ]; then
  kit_require_sentinel "$SRC/CLAUDE.md"
  kit_discipline_of "$SRC/CLAUDE.md" > .claude/DISCIPLINE.md
  echo "  DISCIPLINE.md written (kit discipline only; the project template stays out of it)"
fi

# 3b) single-line @import into the project CLAUDE.md (if present DON'T touch content, only prepend; if absent create).
if [ -f CLAUDE.md ]; then
  if kit_has_import CLAUDE.md; then echo "  CLAUDE.md: @import already present (idempotent)"
  elif kit_claude_md_is_legacy CLAUDE.md; then
    # Pre-1.1: the whole discipline sits inline. Blindly prepending the @import would load it TWICE, and leaving
    # it alone means discipline updates never reach this project. Offer the exact swap, with a backup.
    warn "CLAUDE.md carries the discipline INLINE (pre-1.1 layout) — discipline updates cannot reach it."
    BND="$(kit_legacy_boundary CLAUDE.md | head -1)"
    if [ -n "$BND" ] && [ "$BND" -gt 1 ] 2>/dev/null \
       && head -n "$((BND-1))" CLAUDE.md | grep -q '^## Four working principles' \
       && head -n "$((BND-1))" CLAUDE.md | grep -q '^### 4\.5 '; then
      printf '     %sthe inline block is lines 1-%s; your project section starts at line %s%s\n' "$D" "$((BND-1))" "$BND" "$R"
      if ask_yes "  Replace that inline block with the single @import line? (a backup is written; this branch is reviewable)"; then
        BK=".claude/CLAUDE.md.pre-kit-$TS"
        cp CLAUDE.md "$BK"
        { printf '<!-- kit discipline · on conflict the project rules BELOW win -->\n%s\n\n' "$IMPORT_LINE"
          tail -n +"$BND" CLAUDE.md; } > CLAUDE.md.kit-tmp && mv CLAUDE.md.kit-tmp CLAUDE.md
        echo "  CLAUDE.md migrated -> @import + your project section (backup: $BK)"
      else
        printf '     %sSkipped. Discipline updates will NOT reach this project until you migrate.%s\n' "$D" "$R"
      fi
    else
      printf '     %sProject heading not found — migrate by hand: delete everything above it, leave only:  %s%s\n' "$D" "$IMPORT_LINE" "$R"
    fi
  else
    { printf '<!-- kit discipline · on conflict the project rules BELOW win -->\n%s\n\n' "$IMPORT_LINE"; cat CLAUDE.md; } > CLAUDE.md.kit-tmp && mv CLAUDE.md.kit-tmp CLAUDE.md
    echo "  CLAUDE.md: single-line @import prepended (project content untouched)"
  fi
else
  printf '%s\n\n# CLAUDE.md — <PROJECT NAME>\n\n## Project\n<One sentence: what it does, for whom.>\n' "$IMPORT_LINE" > CLAUDE.md
  echo "  CLAUDE.md was missing -> @import + project template created"
fi

# 3c) settings.json SCHEMA-AWARE merge: project setting is NOT deleted; arrays concat+dedup; ABORT on invalid JSON.
KSET="$SRC/settings.json"; PSET=".claude/settings.json"
JQ_MERGE='
def ddedup: reduce .[] as $x ([]; if any(.[]; .==$x) then . else .+[$x] end);
def dm(a;b): reduce (b|keys_unsorted[]) as $k (a;
  if (.[$k]|type)=="object" and (b[$k]|type)=="object" then .[$k]=dm(.[$k];b[$k])
  elif (.[$k]|type)=="array" and (b[$k]|type)=="array" then .[$k]=((.[$k]+b[$k])|ddedup)
  else .[$k]=b[$k] end);
dm($k[0]; $p[0])'   # base=kit, overlay=project -> project scalars win, arrays merge
if [ ! -f "$PSET" ]; then
  [ -f "$KSET" ] && { cp "$KSET" "$PSET"; echo "  settings.json: was missing in the project -> the kit's was installed"; }
elif ! command -v jq >/dev/null 2>&1; then
  warn "settings.json: no jq -> safe merge not possible. Project setting PRESERVED; add the kit gates by hand."
elif ! jq -e . "$PSET" >/dev/null 2>&1; then
  warn "settings.json: existing file is INVALID JSON -> merge ABORT (no silent overwrite). Fix it by hand first."
else
  MERGED="$(jq -n --slurpfile p "$PSET" --slurpfile k "$KSET" "$JQ_MERGE" 2>/dev/null || true)"
  if [ -n "$MERGED" ] && printf '%s' "$MERGED" | jq -e . >/dev/null 2>&1; then
    printf '%s\n' "$MERGED" > "$PSET"; echo "  settings.json: schema-aware MERGE (project hooks/permissions PRESERVED + kit added)"
  else
    warn "settings.json: merge failed -> project setting PRESERVED (not overwritten)."
  fi
fi

# ============ [STAGE 4] GIT-HOOK ARMING (SHIM) + PROOF ============
h1 "Stage 4 — arm the git gates (SHIM via husky) + PROOF"

# 4a) location of the existing hook chain (the shim calls this too)
ORIG_HOOKS=""
if [ -n "$CURHP" ]; then ORIG_HOOKS="$CURHP"
elif [ -d .husky ]; then ORIG_HOOKS=".husky"
elif [ -x .git/hooks/pre-commit ] || [ -x .git/hooks/commit-msg ]; then ORIG_HOOKS=".git/hooks"; fi
# never shim the kit onto its OWN hooks (re-adopt) — the shim would exec itself and recurse on every commit
case "$ORIG_HOOKS" in .claude/hooks|.claude/git-shim) ORIG_HOOKS="" ;; esac

if [ -z "$ORIG_HOOKS" ]; then
  git config core.hooksPath .claude/hooks
  echo "  core.hooksPath -> .claude/hooks (no existing hook chain)"
else
  mkdir -p .claude/git-shim
  for hk in pre-commit commit-msg; do
    cat > ".claude/git-shim/$hk" <<SHIM
#!/usr/bin/env bash
# kit git-shim: runs the kit hook + the existing project chain IN ORDER (if one fails git stops).
set -e
H="\$(basename "\$0")"
ROOT="\$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
K="\$ROOT/.claude/hooks/\$H"; [ -x "\$K" ] && "\$K" "\$@"
P="\$ROOT/$ORIG_HOOKS/\$H"
if   [ -x "\$P" ]; then "\$P" "\$@"
elif [ -f "\$P" ]; then bash "\$P" "\$@"; fi
exit 0
SHIM
    chmod +x ".claude/git-shim/$hk"
  done
  git config core.hooksPath .claude/git-shim
  echo "  SHIM installed -> core.hooksPath=.claude/git-shim (kit + $ORIG_HOOKS run together)"
fi
[ "$GITKIND" = "worktree/submodule (.git file)" ] && warn "worktree/submodule: core.hooksPath may also affect the main checkout (git design)."

# 4b) PROOF — is the kit actually working? (not a claim)
h1 "Stage 4b — PROOF"
PROOF_OK=1; HP="$(git config --get core.hooksPath 2>/dev/null || echo .claude/hooks)"
# 1) trace-scan git hook: a staged AI trace MUST be BLOCKED (NO real commit; run the hook directly)
# move any allowlist aside so PROOF measures the SCANNER itself, not the project's own exemptions (else a loosened repo fails the proof)
[ -f .trace-allowlist.txt ] && mv .trace-allowlist.txt .trace-allowlist.txt.proofbak 2>/dev/null
printf 'Co-Authored%s: Test <x@y.z>\n' '-By' > .kit-proof.txt   # not contiguous in source (so the trace hook doesn't block itself); full at runtime
git add .kit-proof.txt >/dev/null 2>&1
if bash "$HP/pre-commit" >/tmp/kitproof.$$ 2>&1; then
  warn "PROOF-1 FAILED: the trace scan LET THROUGH the AI trace"; PROOF_OK=0
elif grep -qiE 'TRACE-SCANNER|Commit stopped|forbidden' /tmp/kitproof.$$; then
  echo "  OK · PROOF-1: staged AI trace BLOCKED by the trace scan"
else echo "  ~  PROOF-1: hook blocked ($(head -1 /tmp/kitproof.$$ 2>/dev/null))"; fi
git reset -q .kit-proof.txt 2>/dev/null; rm -f .kit-proof.txt /tmp/kitproof.$$
[ -f .trace-allowlist.txt.proofbak ] && mv .trace-allowlist.txt.proofbak .trace-allowlist.txt 2>/dev/null
# 2) guard-bash git-approval gate: keyless 'git commit' -> block
if printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | bash .claude/hooks/guard-bash.sh >/dev/null 2>&1; then
  warn "PROOF-2 FAILED: guard-bash LET THROUGH the keyless commit"; PROOF_OK=0
else echo "  OK · PROOF-2: guard-bash BLOCKED the keyless 'git commit' (holds in auto/bypass too)"; fi
# 3) can the kit agents + discipline be loaded
NCCK="$(ls .claude/agents/*-csk.md 2>/dev/null | wc -l | tr -d ' ')"
if [ "${NCCK:-0}" -ge 1 ]; then echo "  OK · PROOF-3: $NCCK kit agents (-csk) installed + discoverable"; else warn "PROOF-3: no kit agent"; PROOF_OK=0; fi
if [ -s .claude/DISCIPLINE.md ] && grep -qF '@.claude/DISCIPLINE.md' CLAUDE.md; then echo "  OK · PROOF-4: DISCIPLINE.md loaded + @import-ed from CLAUDE.md"; else warn "PROOF-4: discipline not linked"; PROOF_OK=0; fi
[ "$PROOF_OK" = 1 ] && h1 "PROOF: kit 100% ACTIVE — gates armed, agents + discipline loaded" || warn "PROOF: some gates could not be verified (see above)"

# ============ [STAGE B] APPLY THE DECISIONS ============
h1 "Stage B — apply the decisions"
# #3 loosen trace gate -> repo-root .trace-allowlist.txt (co-author/sign-off exempt from the trace scan)
if [ "$DEC3" = loosen ]; then
  { [ -f .trace-allowlist.txt ] && cat .trace-allowlist.txt; printf 'Co-Authored%s\n' '-By'; } | sort -u > .trace-allowlist.txt.t && mv .trace-allowlist.txt.t .trace-allowlist.txt
  echo "  #3 loosen -> .trace-allowlist.txt (co-author trailer exempt)"
else echo "  #3 keep -> full trace scan"; fi
# #4 share/hide — the payload is ALWAYS committed to the review branch (so the diff is real + rollback stays clean);
# 'hide' becomes a post-merge follow-up in HANDOVER. (Gitignoring .claude BEFORE the commit would drop it from the
# review diff and leave it untracked after a rollback -> 'project untouched' would be a lie.)
HIDE_NOTE=""
if [ "$DEC4" = hide ]; then
  HIDE_NOTE="Keep the kit local after merging:  git rm -r --cached .claude CLAUDE.md  &&  printf '.claude/\nCLAUDE.md\n' >> .gitignore  &&  git commit -m 'kit: keep local'"
  echo "  #4 hide -> recorded; .claude stays TRACKED on the branch (rollback-safe). Post-merge steps in HANDOVER."
else echo "  #4 share -> .claude tracked + shared with the team"; fi
# #1 merge: document (NO automatic risky merge — red-team; merging is a human-approved follow-up)
case "$DEC1" in
  takeover) MERGE_NOTE="takeover: overlapping roles ($COLLIDE) handed to the kit's -csk agents; your versions preserved under .claude/superseded/agents/ (fold their domain into a project skill)" ;;
  keepmine) MERGE_NOTE="keepmine: your agents own the overlapping roles ($COLLIDE); the kit's matching -csk agents were not installed" ;;
  *)        MERGE_NOTE="keep: project + kit agents side by side (no overlaps, or overlaps left to coexist)" ;;
esac
# #7 off-repo transfer: paste from the user (interactive; skipped on non-TTY)
OFFREPO_TEXT=""
if [ "$DEC7" = transfer ] && [ -t 0 ]; then
  h1 "#7 off-repo decisions — paste them here"
  sub "Write the decisions made in chat/on the web but NOT in the repo. When done, an EMPTY line (Enter)."
  while IFS= read -r line; do [ -z "$line" ] && break; OFFREPO_TEXT="$OFFREPO_TEXT
- $line"; done
  [ -n "$OFFREPO_TEXT" ] && echo "  #7 -> $(printf '%s' "$OFFREPO_TEXT" | grep -c .) lines will go into HANDOVER" || echo "  #7 -> empty"
fi

# ============ [STAGE 5] HANDOVER.md + ADR (decisions persist) ============
h1 "Stage 5 — HANDOVER.md + ADR (handover persists; decisions are not lost)"
mkdir -p docs docs/adr
DATE_H="$(date +%Y-%m-%d)"
# compute the decision values first (avoid inner-quote/command-sub tangle in the heredoc)
case "$DEC1" in takeover) D1='takeover (kit -csk owns overlaps; yours preserved)';; keepmine) D1='keepmine (your agents own overlaps)';; none) D1='none';; *) D1='keep (coexist)';; esac
D2='project wins'   # precedence is fixed (DEC2 not overridable) — no false 'kit wins' record
D3="$([ "$DEC3" = loosen ] && echo 'loosen (.trace-allowlist written)' || echo 'keep (full)')"
D4="$([ "$DEC4" = hide ] && echo 'hide (gitignore)' || echo 'keep sharing')"
D5="$([ -n "$ORIG_HOOKS" ] && echo "SHIM ($ORIG_HOOKS)" || echo 'direct')"
D6="$([ "$DEC6" = absolute ] && echo 'absolute 0/0/0/0' || echo 'baseline+regression')"
case "$DEC7" in transfer) D7='transferred (below)';; skip) D7='knowingly missing';; *) D7='local + ask';; esac
HOOKDESC="$([ -n "$ORIG_HOOKS" ] && echo "SHIM (kit + $ORIG_HOOKS together)" || echo '.claude/hooks direct')"
if [ -n "${OFFREPO_TEXT:-}" ]; then OFFSEC="$OFFREPO_TEXT"
elif [ "$OFFREPO" = 1 ]; then OFFSEC="> WARNING: no local .claude/CLAUDE.md -> decisions may also be in chat/on the web; the tool COULD NOT SEE them.
<!-- Write off-repo decisions here; move the important ones under docs/adr/. -->"
else OFFSEC="<!-- Write potentially in-chat decisions here; move the important ones under docs/adr/. -->"; fi

# 5a) HANDOVER.md — mechanical fact (verifiable) + human section (NO LLM signature)
cat > docs/HANDOVER.md <<HAND
# Handover Note (HANDOVER) — $DATE_H

> This document records what the tool did MECHANICALLY (verifiable) + marks the HUMAN
> sections you need to fill in. The tool does NOT SIGN off anything as "done".

## What was handed over (mechanical)
- Kit agents: $NCCK (-csk namespace; no clash with project agents).
- Project agents: $N_PAGENTS — UNTOUCHED, in place + active (recursive discovery).
- Discipline: .claude/DISCIPLINE.md + @import into the project CLAUDE.md (content untouched).
- settings.json: schema-aware merge (project hooks/permissions PRESERVED + kit added).
- Git gates: $HOOKDESC.
- Overlapping roles: $MERGE_NOTE.
- Handover branch: $BR  ($BASE untouched; the change set is STAGED-not-committed — review in your editor / 'git status', then commit).

## Decisions made (smart suggestion; review/override in Stage B)
| # | Decision | Value |
|---|---|---|
| 1 | Role clash | $D1 |
| 2 | Precedence | $D2 (axis-by-axis) |
| 3 | Trace gate | $D3 |
| 4 | Share/hide | $D4 |
| 5 | Git hook | $D5 |
| 6 | Brownfield DoD | $D6 |
| 7 | Off-repo | $D7 |

## CONFIRM (the tool cannot verify — you check)
- [ ] Are the inherited project rules/agents UP TO DATE? (stale rule = regression)
- [ ] Overlapping roles (project + kit same job): which one to use / merge?
- [ ] Has the staged change set been reviewed (editor's Changes panel / git status) before committing?
${HIDE_NOTE:+- [ ] HIDE chosen — after merge run:  $HIDE_NOTE}

## Off-repo / in-chat decisions
$OFFSEC

---
Generated: kit adopt · $DATE_H · branch $BR  (apart from this line there is NO tool SIGNATURE)
HAND
echo "  docs/HANDOVER.md written"

# 5b) ADR-0001 — the handover itself is a persistent decision (never-overwrite)
ADR1="docs/adr/0001-agentic-kit-adoption.md"
if [ ! -e "$ADR1" ]; then
  cat > "$ADR1" <<ADR
# ADR-0001: The Agentic Kit was handed over to this project

- Date: $DATE_H
- Status: accepted (handover branch: $BR)

## Context
The existing project was equipped for agentic work with the standard kit under a "team-to-team handover" logic.
Goal: don't break the project, don't lose decisions made, don't leave the kit passive (hybrid).

## Decision
- Kit agents were installed under the -csk namespace; project agents preserved side by side, untouched.
- Kit discipline active via .claude/DISCIPLINE.md + @import; the project CLAUDE.md untouched.
- On rule conflicts the PROJECT wins (axis-by-axis).
- Git gates: $HOOKDESC.
- Every change is on a reviewable git branch; rollback = git.

## Consequence
From now on decisions are written as ADRs under docs/adr/, NOT in chat (persistence).
Inherited stale rules are subject to "confirm"; not authoritative until verified with code.
ADR
  echo "  $ADR1 written (persistent handover decision)"
else
  echo "  $ADR1 already exists — untouched (never-overwrite)"
fi

git add .claude CLAUDE.md docs >/dev/null 2>&1
[ -e .gitignore ] && git add .gitignore >/dev/null 2>&1
[ -e .trace-allowlist.txt ] && git add .trace-allowlist.txt >/dev/null 2>&1
# NO auto-commit: the change set stays STAGED-but-uncommitted on branch $BR, so every added/changed file shows up
# in your editor's Source Control / Changes panel for review. HEAD is untouched until you commit yourself.

h1 "Review in your editor — nothing committed yet"
row "staged" "$(git diff --cached --stat 2>/dev/null | tail -1 || echo '(none)')"
sub "You are on branch $BR with everything STAGED but NOT committed."
sub "see it:   open the Source Control / Changes panel (every added + changed file is listed)  ·  or: git status"
sub "accept:   git commit -m 'adopt agentic kit'   then:  git checkout $BASE && git merge $BR"
sub "discard:  git reset --hard $BASE && git checkout $BASE && git branch -D $BR"
warn "If Claude Code is running in this project, RESTART it — CLAUDE.md and the discipline load at session start,"
printf '     %sso a session opened before this run keeps quoting the previous version'"'"'s rules.%s\n' "$D" "$R"
