#!/usr/bin/env bash
# Cases for claude-starter/studio/ensure-node.sh — the script that decides whether this
# machine can run the panel, and goes and gets a runtime when it cannot.
#
# The branches that matter most are the ones a developer machine can never reach: "there is
# no Node anywhere" and "the download did not match its checksum". So the script is sourced
# by small case files and its pieces are driven directly, with the network replaced by
# files on disk. Nothing here touches nodejs.org.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/claude-starter/studio/ensure-node.sh"
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t csk-ensure-node)"
trap 'rm -rf "$WORK"' EXIT INT TERM

pass=0; fail=0; broken=0
ok()    { pass=$((pass+1)); printf 'ok   %s\n' "$1"; }
bad()   { fail=$((fail+1)); printf 'FAIL %s\n     %s\n' "$1" "${2:-}"; }
broke() { broken=$((broken+1)); printf 'BROKEN %s\n       %s\n' "$1" "${2:-}"; }
check() { if [ "${2:-0}" = 1 ]; then ok "$1"; else bad "$1" "${3:-}"; fi; }
has()   { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

[ -f "$SCRIPT" ] || { printf 'BROKEN ensure-node.sh is not at %s\n' "$SCRIPT"; exit 1; }

# A stand-in for a node binary that reports whatever major it is told to.
shim() { # shim <path> <major|silent49>
  mkdir -p "$(dirname "$1")"
  if [ "$2" = silent49 ]; then
    printf '#!/bin/sh\nexit 49\n' > "$1"     # the Windows Store stub: resolves, silent, 49
  else
    printf '#!/bin/sh\nprintf "%%s\\n" %s\n' "$2" > "$1"
  fi
  chmod +x "$1"
}

# A case file sources the real script and then drives one function. `$0` is the case file,
# not the script, so the script's "was I executed?" guard correctly says no.
case_file() { # case_file <name> <body> -> prints the path
  f="$WORK/case-$1.sh"
  { printf '#!/usr/bin/env bash\nset -u\n. "%s"\n' "$SCRIPT"; printf '%s\n' "$2"; } > "$f"
  printf '%s\n' "$f"
}

# PATH with no node on it, but with the tools the script itself needs. /opt/homebrew and
# /usr/local stay out so a Homebrew node is not on PATH; the script still probes them by
# absolute path, which is the behaviour under test elsewhere.
NO_NODE_PATH="$WORK/emptybin:/usr/bin:/bin"
mkdir -p "$WORK/emptybin"

# If the harness's own shim does not run, every case below would report the script's answer
# as a failure of the product. Prove the instrument first.
shim "$WORK/instrument/node" 22
if [ "$("$WORK/instrument/node" -p 'anything' 2>/dev/null)" != 22 ]; then
  broke 'the test shim runs' 'a shell-script shim is not executable here, so nothing below would mean anything'
  printf '\n0 passed, 0 failed, 1 broken — measurement is not trustworthy on this machine\n'
  exit 1
fi
ok 'the test shim runs (instrument check)'

# ---------------------------------------------------------------- probe --------

probe() { bash "$SCRIPT" --probe "$1" >/dev/null 2>&1; }

# The should-pass case. Without it the three refusals below are satisfied by a probe that
# refuses everything.
if probe "$(command -v node 2>/dev/null || printf /nonexistent)"; then
  ok 'a real node is accepted'
else
  broke 'a real node is accepted' 'no working node on PATH to check the positive case against'
fi

shim "$WORK/stub/node" silent49
if probe "$WORK/stub/node"; then bad 'a stub that resolves, prints nothing and exits 49 is refused' 'it was accepted'
else ok 'a stub that resolves, prints nothing and exits 49 is refused'; fi

shim "$WORK/old/node" 16
if probe "$WORK/old/node"; then bad 'a node below the floor is refused' 'major 16 was accepted'
else ok 'a node below the floor is refused'; fi

if probe "$WORK/nothing-here/node"; then bad 'a path with no file is refused' 'it was accepted'
else ok 'a path with no file is refused'; fi

# ------------------------------------------------------------- resolution ------

shim "$WORK/explicit/node" 20
got="$(CSK_STUDIO_NODE="$WORK/explicit/node" bash "$SCRIPT" 2>/dev/null)"
check 'CSK_STUDIO_NODE is used ahead of anything on PATH' \
  "$([ "$got" = "$WORK/explicit/node" ] && echo 1 || echo 0)" "resolved to '$got'"

# A runtime this script fetched earlier must be found on the next run from a shell whose
# PATH has no node — which is every shell, after an install that edits no PATH.
RT="$WORK/runtime"
shim "$RT/node-v99.9.9-linux-x64/bin/node" 99
got="$(PATH="$NO_NODE_PATH" CSK_STUDIO_RUNTIME="$RT" bash "$SCRIPT" 2>/dev/null)"
check 'a previously fetched runtime is found again with no node on PATH' \
  "$([ "$got" = "$RT/node-v99.9.9-linux-x64/bin/node" ] && echo 1 || echo 0)" "resolved to '$got'"

# And the negative twin: when nothing anywhere is usable, the answer is a refusal rather
# than the first thing lying around. Only a machine with no Node reaches this for real, so
# the probe is forced to reject and the search is made to run against nothing.
f="$(case_file resolve-none 'works() { return 1; }
main --explain')"
out="$(CSK_STUDIO_RUNTIME="$WORK/empty-runtime" HOME="$WORK/nohome" bash "$f" 2>&1)"; rc=$?
check 'with no usable node anywhere the answer is a refusal, not a guess' \
  "$([ "$rc" != 0 ] && has "$out" 'nothing usable' && echo 1 || echo 0)" "rc=$rc out='$out'"

# ------------------------------------------------------- release selection -----

TAB="$WORK/index.tab"
{
  printf 'version\tdate\tfiles\tnpm\tv8\tuv\tzlib\topenssl\tmodules\tlts\tsecurity\n'
  printf 'v99.1.0\t2026-08-26\tlinux-x64\t11\t14\t1\t1\t3\t147\t-\t-\n'
  printf 'v98.2.0\t2026-07-01\tlinux-x64\t11\t14\t1\t1\t3\t147\tKrypton\t-\n'
  printf 'v97.0.0\t2026-01-01\tlinux-x64\t11\t14\t1\t1\t3\t147\tJod\t-\n'
} > "$TAB"

OFFLINE_FEED="get() { cat \"$TAB\"; }"

f="$(case_file lts "$OFFLINE_FEED
newest_lts")"
got="$(bash "$f" 2>/dev/null)"
check 'the newest LTS is chosen, not the newest release' \
  "$([ "$got" = v98.2.0 ] && echo 1 || echo 0)" "chose '$got'; v99.1.0 is newer but is not an LTS"

got="$(CSK_STUDIO_NODE_VERSION=v42.0.0 bash "$f" 2>/dev/null)"
check 'a pinned version wins over the feed' "$([ "$got" = v42.0.0 ] && echo 1 || echo 0)" "chose '$got'"

# ------------------------------------------------------------------ plan -------

plan_for() { # plan_for <plat> <arch> -> prints the artifact name it would fetch
  f="$(case_file "plan-$1-$2" "$OFFLINE_FEED
plat_arch() { printf '%s %s\n' '$1' '$2'; }
remote_size() { printf 'unknown\n'; }
plan
printf '%s\n' \"\$ARTIFACT\"")"
  bash "$f" 2>/dev/null | tail -1
}
got="$(plan_for win x64)"
check 'Windows is planned as a zip' "$([ "$got" = node-v98.2.0-win-x64.zip ] && echo 1 || echo 0)" "planned '$got'"
got="$(plan_for darwin arm64)"
check 'macOS is planned as a tarball' "$([ "$got" = node-v98.2.0-darwin-arm64.tar.gz ] && echo 1 || echo 0)" "planned '$got'"

# --------------------------------------------------------------- install ------

# A real archive shaped the way nodejs.org publishes one, with a node inside that runs.
FIX="$WORK/fixture"
ART=node-v98.2.0-linux-x64.tar.gz
mkdir -p "$FIX/node-v98.2.0-linux-x64/bin"
shim "$FIX/node-v98.2.0-linux-x64/bin/node" 98
( cd "$FIX" && tar -czf "$FIX/$ART" node-v98.2.0-linux-x64 ) 2>/dev/null

sum_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}' || true; }
[ -n "$(sum_of "$FIX/$ART")" ] || sum_of() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

if [ ! -s "$FIX/$ART" ] || [ -z "$(sum_of "$FIX/$ART")" ]; then
  broke 'the fixture archive is built and hashed' 'no tar or no sha256 tool here, so the install cases cannot run'
else
  printf '%s  %s\n' "$(sum_of "$FIX/$ART")" "$ART" > "$FIX/SHASUMS256.txt"
  printf '%s  %s\n' 0000000000000000000000000000000000000000000000000000000000000000 "$ART" > "$FIX/SHASUMS256.bad.txt"

  # `get` is the only door to the network, so replacing it makes the install offline.
  install_case() { # install_case <name> <sums-file>
    case_file "$1" "resolve() { return 1; }
plat_arch() { printf 'linux x64\n'; }
remote_size() { printf 'unknown\n'; }
get() {
  case \"\$1\" in
    *index.tab)      cat '$TAB' ;;
    *SHASUMS256.txt) cp '$2' \"\$2\" ;;
    *)               cp '$FIX/$ART' \"\$2\" ;;
  esac
}
main --install --yes"
  }

  out="$(CSK_STUDIO_RUNTIME="$WORK/rt-good" bash "$(install_case good "$FIX/SHASUMS256.txt")" 2>&1)"; rc=$?
  node_out="$(printf '%s\n' "$out" | tail -1)"
  if [ "$rc" = 0 ] && [ -x "$node_out" ] && [ "$("$node_out" -p x 2>/dev/null)" = 98 ]; then
    ok 'a download whose checksum matches is unpacked and its node runs'
  else
    bad 'a download whose checksum matches is unpacked and its node runs' "rc=$rc out='$out'"
  fi

  out="$(CSK_STUDIO_RUNTIME="$WORK/rt-bad" bash "$(install_case bad "$FIX/SHASUMS256.bad.txt")" 2>&1)"; rc=$?
  left="$(ls -1 "$WORK/rt-bad" 2>/dev/null | grep -cv '^\.tmp' | tr -d ' ')"
  if [ "$rc" != 0 ] && has "$out" 'checksum mismatch' && [ "${left:-0}" = 0 ]; then
    ok 'a checksum mismatch refuses and leaves nothing installed'
  else
    bad 'a checksum mismatch refuses and leaves nothing installed' "rc=$rc left=$left out='$out'"
  fi
fi

# Windows is the only platform that gets a zip, so the unpack path it uses is the one a
# tarball case can never reach. The archive is built with whatever this machine has; on the
# Windows runner that is a real zip going through a real Windows extractor.
ZFIX="$WORK/zipfix"
ZART=node-v98.2.0-win-x64.zip
mkdir -p "$ZFIX/node-v98.2.0-win-x64"
shim "$ZFIX/node-v98.2.0-win-x64/node.exe" 97
# Three ways to make a zip, because on the machine that matters most only the third exists:
# Git Bash has neither python3's shutil nor the zip command, but PowerShell's Compress-Archive
# is right there. Probing only the first two reported "no way to make a zip here" and skipped
# the Windows unpack cases ON WINDOWS - the one platform they were written for.
zipped=0
if command -v python3 >/dev/null 2>&1 && python3 -c "
import shutil,sys
shutil.make_archive(sys.argv[1], 'zip', sys.argv[2], 'node-v98.2.0-win-x64')" "$ZFIX/node-v98.2.0-win-x64" "$ZFIX" 2>/dev/null \
   && [ -s "$ZFIX/$ZART" ]; then zipped=1
elif command -v zip >/dev/null 2>&1 && ( cd "$ZFIX" && zip -qr "$ZART" node-v98.2.0-win-x64 ) 2>/dev/null \
   && [ -s "$ZFIX/$ZART" ]; then zipped=1
elif command -v powershell >/dev/null 2>&1; then
  zsrc="$ZFIX/node-v98.2.0-win-x64"; zdst="$ZFIX/$ZART"
  if command -v cygpath >/dev/null 2>&1; then
    zsrc="$(cygpath -wa "$zsrc" 2>/dev/null || printf '%s' "$zsrc")"
    zdst="$(cygpath -wa "$zdst" 2>/dev/null || printf '%s' "$zdst")"
  fi
  powershell -NoProfile -Command "Compress-Archive -Path '$zsrc' -DestinationPath '$zdst' -Force" >/dev/null 2>&1
  [ -s "$ZFIX/$ZART" ] && zipped=1
fi

# The stubs below have to actually unpack something, and python3 was the only way they knew
# how — which meant the Windows unpack cases skipped on Git Bash, the one place they matter.
# This helper prefers the machine's real unzip and keeps python3 as the fallback. It is
# calibrated against the fixture before anything is allowed to depend on it.
REAL_UNZIP="$(command -v unzip 2>/dev/null || true)"
XZIP="$WORK/xzip"
cat > "$XZIP" <<EOF
#!/bin/sh
z="\$1"; d="\$2"
[ -n "$REAL_UNZIP" ] && "$REAL_UNZIP" -q -o "\$z" -d "\$d" >/dev/null 2>&1
if [ ! -d "\$d/node-v98.2.0-win-x64" ] && command -v python3 >/dev/null 2>&1; then
  python3 -c "import zipfile,sys
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "\$z" "\$d"
fi
find "\$d" -type f -exec chmod 755 {} + 2>/dev/null
[ -d "\$d/node-v98.2.0-win-x64" ]
EOF
chmod +x "$XZIP"
export XZIP   # the powershell stub is a quoted heredoc, so it reads this at run time

XOK=0
if [ "$zipped" = 1 ]; then
  rm -rf "$WORK/xzip-probe"; mkdir -p "$WORK/xzip-probe"
  "$XZIP" "$ZFIX/$ZART" "$WORK/xzip-probe" >/dev/null 2>&1
  [ "$("$WORK/xzip-probe/node-v98.2.0-win-x64/node.exe" -p x 2>/dev/null)" = 97 ] && XOK=1
fi

if [ "$zipped" != 1 ] || [ -z "$(sum_of "$ZFIX/$ZART" 2>/dev/null)" ]; then
  broke 'the zip fixture is built' 'no way to make a zip here, so the Windows unpack path is not exercised on this machine'
else
  printf '%s  %s\n' "$(sum_of "$ZFIX/$ZART")" "$ZART" > "$ZFIX/SHASUMS256.txt"
  f="$(case_file zip "resolve() { return 1; }
plat_arch() { printf 'win x64\n'; }
remote_size() { printf 'unknown\n'; }
get() {
  case \"\$1\" in
    *index.tab)      cat '$TAB' ;;
    *SHASUMS256.txt) cp '$ZFIX/SHASUMS256.txt' \"\$2\" ;;
    *)               cp '$ZFIX/$ZART' \"\$2\" ;;
  esac
}
main --install --yes")"
  out="$(CSK_STUDIO_RUNTIME="$WORK/rt-zip" bash "$f" 2>&1)"; rc=$?
  node_out="$(printf '%s\n' "$out" | tail -1)"
  if [ "$rc" = 0 ] && [ -f "$node_out" ] && [ "$("$node_out" -p x 2>/dev/null)" = 97 ]; then
    ok 'a Windows zip is unpacked and the node.exe inside it runs'
  else
    bad 'a Windows zip is unpacked and the node.exe inside it runs' "rc=$rc out='$out'"
  fi
  # Only answerable where unzip is the unpacker. Without it PowerShell runs and the warning is
  # correct, so a failure here would be the suite calling right behaviour wrong.
  if ! command -v unzip >/dev/null 2>&1; then
    broke 'the slow-unpack warning stays quiet when the unpack was not slow' \
      'no unzip here, so the fast path this case is about does not exist on this machine'
  elif has "$out" 'take up to a minute'; then
    bad 'the slow-unpack warning stays quiet when the unpack was not slow' "it warned anyway: '$out'"
  else
    ok 'the slow-unpack warning stays quiet when the unpack was not slow'
  fi
fi

# Measured on Windows 11: Info-ZIP's unzip returns 1 for "extracted, with warnings" — the
# files are there and the status says failure. Trusting that status either skips a successful
# extraction or reports one as failed, so the script judges the directory instead. Forced
# here, because on this machine bsdtar reads the zip and unzip is never reached.
if [ "$zipped" = 1 ] && [ "$XOK" = 1 ]; then
  FB="$WORK/fakebin"; mkdir -p "$FB"
  printf '#!/bin/sh\nexit 1\n' > "$FB/tar"                    # GNU tar's answer to a zip
  { printf '#!/bin/sh\n'
    printf 'for a in "$@"; do case "$a" in *.zip) z="$a" ;; esac; done\n'
    printf 'd=""; p=0; for a in "$@"; do [ "$p" = 1 ] && { d="$a"; p=0; }; [ "$a" = "-d" ] && p=1; done\n'
    # zipfile drops the executable bit; real Info-ZIP keeps it, and on Windows it is moot.
    # Restoring it here keeps the fixture's flaw out of the product's answer.
    printf '%s "$z" "$d"\n' "$XZIP"
    printf 'exit 1\n'                                          # extracted, and still says 1
  } > "$FB/unzip"
  chmod +x "$FB/tar" "$FB/unzip"

  f="$(case_file unzip-rc1 "resolve() { return 1; }
plat_arch() { printf 'win x64\n'; }
remote_size() { printf 'unknown\n'; }
get() {
  case \"\$1\" in
    *index.tab)      cat '$TAB' ;;
    *SHASUMS256.txt) cp '$ZFIX/SHASUMS256.txt' \"\$2\" ;;
    *)               cp '$ZFIX/$ZART' \"\$2\" ;;
  esac
}
main --install --yes")"
  out="$(PATH="$FB:$PATH" CSK_STUDIO_RUNTIME="$WORK/rt-rc1" bash "$f" 2>&1)"; rc=$?
  node_out="$(printf '%s\n' "$out" | tail -1)"
  if [ "$rc" = 0 ] && [ -f "$node_out" ] && [ "$("$node_out" -p x 2>/dev/null)" = 97 ]; then
    ok 'an extractor that succeeds and still reports failure is believed by its result, not its status'
  else
    bad 'an extractor that succeeds and still reports failure is believed by its result, not its status' "rc=$rc out='$out'"
  fi
else
  broke 'the unzip warning-status case runs' 'no way to build a zip here, or nothing on this machine that can unpack one'
fi

# Silence is the failure mode to avoid: with no terminal to ask on, the script must say so
# rather than decide on the user's behalf that a 50 MB download is fine.
f="$(case_file no-tty "resolve() { return 1; }
plat_arch() { printf 'linux x64\n'; }
remote_size() { printf 'unknown\n'; }
$OFFLINE_FEED
main --install")"
out="$(CSK_STUDIO_RUNTIME="$WORK/rt-tty" bash "$f" </dev/null 2>&1)"; rc=$?
check 'with no terminal and no --yes it refuses instead of downloading' \
  "$([ "$rc" != 0 ] && has "$out" '--plan' && echo 1 || echo 0)" "rc=$rc out='$out'"

# The PowerShell fallback only runs on Windows, so the property it depends on is pinned with
# stubs that caricature the one thing under test: cygpath -wa promises an absolute path and
# -w does not. Measured on Windows 11 — a relative path reaches a Windows program that is not
# running from the same directory, and it reports the file missing, which would surface here
# as "the download is broken".
if [ "$zipped" = 1 ] && [ "$XOK" = 1 ]; then
  PW="$WORK/pwbin"; mkdir -p "$PW"
  printf '#!/bin/sh\nexit 1\n' > "$PW/tar"
  printf '#!/bin/sh\nexit 1\n' > "$PW/unzip"
  cat > "$PW/cygpath" <<'EOF'
#!/bin/sh
# -wa answers absolutely; -w is allowed to hand back something relative, which is the
# difference the caller has to care about.
case "$1" in
  -wa) printf '/ABS%s\n' "$2" ;;
  *)   printf '%s\n' "${2#/}" ;;
esac
EOF
  cat > "$PW/powershell" <<'EOF'
#!/bin/sh
cmd="$*"
lp=$(printf '%s' "$cmd" | sed -n "s/.*-LiteralPath '\([^']*\)'.*/\1/p")
dp=$(printf '%s' "$cmd" | sed -n "s/.*-DestinationPath '\([^']*\)'.*/\1/p")
# A Windows program given a relative path cannot find the file. Refuse, the way it would.
case "$lp" in /ABS/*) ;; *) exit 1 ;; esac
case "$dp" in /ABS/*) ;; *) exit 1 ;; esac
"$XZIP" "${lp#/ABS}" "${dp#/ABS}"
EOF
  chmod +x "$PW/tar" "$PW/unzip" "$PW/cygpath" "$PW/powershell"

  f="$(case_file powershell-path "resolve() { return 1; }
plat_arch() { printf 'win x64\n'; }
remote_size() { printf 'unknown\n'; }
get() {
  case \"\$1\" in
    *index.tab)      cat '$TAB' ;;
    *SHASUMS256.txt) cp '$ZFIX/SHASUMS256.txt' \"\$2\" ;;
    *)               cp '$ZFIX/$ZART' \"\$2\" ;;
  esac
}
main --install --yes")"
  out="$(PATH="$PW:$PATH" CSK_STUDIO_RUNTIME="$WORK/rt-ps" bash "$f" 2>&1)"; rc=$?
  node_out="$(printf '%s\n' "$out" | tail -1)"
  if [ "$rc" = 0 ] && [ -f "$node_out" ] && [ "$("$node_out" -p x 2>/dev/null)" = 97 ]; then
    ok 'the PowerShell fallback is handed an absolute path, not whatever it was given'
  else
    bad 'the PowerShell fallback is handed an absolute path, not whatever it was given' "rc=$rc out='$out'"
  fi
  # And it says so before it starts, not after: that branch takes 26 s on Node's zip where
  # unzip takes 3 s, and it only runs where there is no unzip to fall back to.
  if has "$out" 'take up to a minute'; then
    ok 'the slow unpack announces itself before the wait, not after'
  else
    bad 'the slow unpack announces itself before the wait, not after' "output was '$out'"
  fi
else
  broke 'the PowerShell path case runs' 'no way to build a zip here, or nothing on this machine that can unpack one'
fi

# ------------------------------------------------------------ MAX_PATH --------

# Expand-Archive enforces Windows' 260-character cap; unzip does not. Measured on Windows 11:
# a 141-character target failed with PathTooLongException after 17 seconds and left nothing,
# while unzip put the same archive in the same place in 3 seconds. So on a machine with no
# unzip the length has to be asked BEFORE 37 MB is fetched, and the refusal has to name the
# path rather than the archive — the archive's checksum passed a line earlier.
#
# CI cannot catch this: the Windows runner's temp is D:\a\_temp, which is short.
# A PATH with everything the script reaches for EXCEPT unzip. Shadowing does not work here —
# `command -v` walks past a non-executable file and finds the real one — so the directory is
# built by name, and unzip is simply not among the names.
NOZIP="$WORK/nounzipbin"; mkdir -p "$NOZIP"
# Shell shims, not links: `ln -s` on Git Bash silently produces a COPY, and a copied bash.exe
# needs msys-2.0.dll from /usr/bin — which this PATH deliberately excludes, so it exits 127 and
# the product never runs at all. A shim's `#!/bin/sh` line is an absolute path and the real
# binary stays where its libraries are.
for t in bash sh mktemp awk sed tr sort ls rm rmdir mkdir mv cp cat uname curl wget \
         sha256sum shasum openssl tar seq grep head tail chmod dirname basename env; do
  w="$(command -v "$t" 2>/dev/null)" || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$w" > "$NOZIP/$t"
  chmod +x "$NOZIP/$t"
done
# Asked by RUNNING it. `-x` answers "is there a file with the bit set", which is the exact
# substitution ensure-node.sh itself exists to refuse — the Windows Store's node stub passes
# `command -v` and then exits 49. The suite had the bug the product defends against.
"$NOZIP/bash" -c 'exit 7' 2>/dev/null
if [ "$?" != 7 ]; then
  broke 'the unzip-free PATH actually runs' 'the shimmed tools do not execute here, so the length cases below would measure nothing'
fi

pathcase() { # pathcase <runtime-dir> -> prints "rc=<n> downloaded=<yes|no> <output>"
  f="$(case_file "maxpath-$2" "resolve() { return 1; }
plat_arch() { printf 'win x64\n'; }
remote_size() { printf 'unknown\n'; }
cygpath() { printf '%s\n' \"C:\\\\\$2\"; }
get() {
  case \"\$1\" in
    *index.tab) cat '$TAB' ;;
    *)          : > '$WORK/downloaded.$2' ; return 1 ;;
  esac
}
main --install --yes")"
  rm -f "$WORK/downloaded.$2"
  out="$(PATH="$NOZIP" CSK_STUDIO_RUNTIME="$1" bash "$f" 2>&1)"; rc=$?
  d=no; [ -f "$WORK/downloaded.$2" ] && d=yes
  printf 'rc=%s downloaded=%s %s\n' "$rc" "$d" "$out"
}

LONGDIR="$WORK/$(printf 'l%.0s' $(seq 1 150))"
got="$(pathcase "$LONGDIR" long)"
if [ "${got%% *}" != "rc=0" ] && has "$got" 'downloaded=no' && has "$got" 'would be expanded into'; then
  ok 'a path too long for Expand-Archive is refused before anything is downloaded'
else
  bad 'a path too long for Expand-Archive is refused before anything is downloaded' "$got"
fi

# The number in the refusal has to be the length of the path the refusal names. It was not:
# the message named $TARGET and reported the length of the unpack directory, so anyone who
# counted the path they were shown got a different answer and went looking for their own
# mistake. The same object mismatch as the arithmetic, surviving in prose.
named="$(printf '%s\n' "$got" | sed -n 's/^  \(.*\)$/\1/p' | head -1)"
claimed="$(printf '%s\n' "$got" | sed -n 's/^which is \([0-9]*\) characters.*/\1/p' | head -1)"
if [ -z "$named" ] || [ -z "$claimed" ]; then
  bad 'the refusal counts the path it names' "could not find both in the message: $got"
elif [ "${#named}" = "$claimed" ]; then
  ok 'the refusal counts the path it names'
else
  bad 'the refusal counts the path it names' "it names a path of ${#named} characters and calls it $claimed"
fi

# The should-pass twin. Without it, a check that refuses every Windows install would satisfy
# the case above — and the default path is well inside the budget, so refusing it would break
# every machine this feature exists for.
got="$(pathcase "$WORK/short" short)"
if has "$got" 'downloaded=yes'; then
  ok 'a path within the budget is not refused, and the download is attempted'
else
  bad 'a path within the budget is not refused, and the download is attempted' "$got"
fi

# And the check must not fire where unzip exists, because unzip is not bound by the cap.
f="$(case_file maxpath-unzip "resolve() { return 1; }
plat_arch() { printf 'win x64\n'; }
remote_size() { printf 'unknown\n'; }
cygpath() { printf '%s\n' \"C:\\\\\$2\"; }
get() {
  case \"\$1\" in
    *index.tab) cat '$TAB' ;;
    *)          : > '$WORK/downloaded.withunzip' ; return 1 ;;
  esac
}
main --install --yes")"
rm -f "$WORK/downloaded.withunzip"
out="$(CSK_STUDIO_RUNTIME="$LONGDIR" bash "$f" 2>&1)"
if ! command -v unzip >/dev/null 2>&1; then
  broke 'the length check stays out of the way when unzip is present' \
    'there is no unzip on this machine, so the condition this case is named after cannot be set up'
elif [ -f "$WORK/downloaded.withunzip" ]; then
  ok 'the length check stays out of the way when unzip is present'
else
  bad 'the length check stays out of the way when unzip is present' "$out"
fi

# The boundary itself, to the character. windows-csk pins the CONSTANT against a real
# Expand-Archive on a real zip; this pins the ARITHMETIC against the constant, so a future
# edit cannot quietly measure one object against another one's budget. That mismatch happened
# twice in one round, in both directions.
#
# Nothing is assumed about the pid: each run reports the tail plan() actually appended, and
# the assertion is the invariant — accepted exactly when runtime + tail fits the budget.
BUD="$(bash "$(case_file budget 'printf "%s\n" "$WIN_DIR_BUDGET"')" 2>/dev/null)"

boundary() { # boundary <runtime-length> <tag> -> "<tail> <downloaded=yes|no>", or "skip"
  need=$(( $1 - ${#WORK} - 1 ))
  [ "$need" -lt 1 ] && { printf 'skip\n'; return; }
  d="$WORK/$(printf 'b%.0s' $(seq 1 "$need"))"
  f="$(case_file "bound-$2" "resolve() { return 1; }
plat_arch() { printf 'win x64\n'; }
remote_size() { printf 'unknown\n'; }
cygpath() { printf '%s\n' \"\$2\"; }
get() {
  case \"\$1\" in
    *index.tab) cat '$TAB' ;;
    *)          : > '$WORK/dl.$2' ; return 1 ;;
  esac
}
plan
printf 'tail=%s pid=%s\n' \"\$(( \${#probe} - \${#RUNTIME} ))\" \"\$\$\"
main --install --yes")"
  rm -f "$WORK/dl.$2"
  o="$(PATH="$NOZIP" CSK_STUDIO_RUNTIME="$d" bash "$f" 2>&1)"
  t="$(printf '%s\n' "$o" | sed -n 's/^tail=\([0-9]*\) .*/\1/p' | head -1)"
  q="$(printf '%s\n' "$o" | sed -n 's/^tail=[0-9]* pid=//p' | head -1)"
  if [ -f "$WORK/dl.$2" ]; then printf '%s %s yes\n' "$t" "$q"; else printf '%s %s no\n' "$t" "$q"; fi
}

case "$BUD" in
  ''|*[!0-9]*) broke 'the length boundary is exact' "could not read WIN_DIR_BUDGET (got '$BUD')" ;;
  *)
    # A first run only to learn the tail this machine produces; the two that matter bracket it.
    probe0="$(boundary $(( ${#WORK} + 20 )) probe)"
    tail0="${probe0%% *}"
    pid0="$(printf '%s\n' "$probe0" | awk '{print $2}')"
    case "$tail0" in
      ''|*[!0-9]*) broke 'the length boundary is exact' "plan() reported no tail (got '$probe0')" ;;
      *)
        # "/.tmp." plus seven digits. Two things at once: the object is the unpack directory
        # rather than some other path, and the width is FIXED rather than the running pid.
        # A real pid gives 9 to 11 here, so this also catches a regression to `$$` — which
        # would make the accepted length drift with uptime and let --plan and --install
        # disagree about the same path.
        want_tail=13
        if [ "$tail0" != "$want_tail" ]; then
          bad 'the length boundary is exact' \
            "plan() measures $tail0 characters past \$RUNTIME; a fixed \$RUNTIME/.tmp.0000000 is $want_tail (the running pid here is $pid0)"
        else
        at="$(boundary $((BUD - tail0)) at)"
        over="$(boundary $((BUD - tail0 + 1)) over)"
        ta="${at%% *}"; va="${at##* }"
        to="${over%% *}"; vo="${over##* }"
        if [ "$at" = skip ] || [ "$over" = skip ]; then
          broke 'the length boundary is exact' "this working directory is already longer than the budget ($BUD)"
        elif [ "$ta" != "$tail0" ] || [ "$to" != "$tail0" ]; then
          # The pid changed width between runs; the lengths chosen no longer bracket anything.
          broke 'the length boundary is exact' "the tail moved between runs ($tail0 -> $ta/$to)"
        elif [ "$va" = yes ] && [ "$vo" = no ]; then
          ok "the length boundary is exact — the longest accepted runtime is $((BUD - tail0)) characters (budget $BUD, tail $tail0)"
        else
          bad 'the length boundary is exact' "at=$va over=$vo (budget $BUD, tail $tail0)"
        fi
        fi ;;
    esac ;;
esac

# The constant, pinned to what was measured rather than to what the arithmetic produces. The
# case above reads WIN_DIR_BUDGET out of the script, so it moves with any edit to it and cannot
# catch a wrong constant. These two numbers came off a real Windows 11 machine — an unpack
# directory of 133 characters works and 134 fails, and 125 is the longest path inside
# v24.21.0's zip counted from the archive root. Changing either should require measuring again,
# which is what this case is for.
CONSTS="$(bash "$(case_file consts 'printf "%s %s\n" "$WIN_DIR_BUDGET" "$NODE_DEEPEST_ENTRY"')" 2>/dev/null)"
if [ "$CONSTS" = "133 125" ]; then
  ok 'the budget and the deepest entry are the numbers that were measured'
else
  bad 'the budget and the deepest entry are the numbers that were measured' \
    "got '$CONSTS', expected '133 125' — if a newer Node changed the archive, re-measure on Windows and update both"
fi

# ------------------------------------------------------ hash calibration ------

# The step that makes a download trustworthy is only as good as the tool doing it, and a tool
# that resolves is not a tool that works. A stub that answers confidently and wrongly is the
# shape that would turn verification into theatre, so it is put in front of the script.
SB="$WORK/shabin"; mkdir -p "$SB"
liar() { printf '#!/bin/sh\nprintf "%%s  -\\n" deadbeef\n' > "$SB/$1"; chmod +x "$SB/$1"; }
liar sha256sum

f="$(case_file sha-liar 'sha256_calibrate && printf "picked %s\n" "$SHA_TOOL" || printf "refused\n"')"

got="$(PATH="$SB:$PATH" bash "$f" 2>/dev/null)"
if [ -n "$got" ] && [ "$got" != "picked sha256sum" ] && [ "$got" != refused ]; then
  ok 'a hash tool that answers wrongly is passed over for one that does not'
else
  bad 'a hash tool that answers wrongly is passed over for one that does not' "calibration said '$got'"
fi

# The should-pass twin. Without it, a calibration that rejected everything would satisfy the
# case above and the one below.
got="$(bash "$f" 2>/dev/null)"
if [ "$got" != refused ] && [ -n "$got" ]; then
  ok 'with a working hash tool present, one is picked'
else
  bad 'with a working hash tool present, one is picked' "calibration said '$got'"
fi

# And when every candidate lies, the answer is a refusal rather than a wrong hash.
liar shasum; liar openssl; liar certutil
got="$(PATH="$SB:$PATH" bash "$f" 2>/dev/null)"
if [ "$got" = refused ]; then
  ok 'when every hash tool lies it refuses rather than verify with one'
else
  bad 'when every hash tool lies it refuses rather than verify with one' "calibration said '$got'"
fi

# Each of the four tools prints the digest in a different place, the Windows builds append CR,
# and three of them echo the path they were given. These stubs are the real shapes, captured
# on Windows 11, INCLUDING that echo — a fixture that leaves the path out cannot show what a
# path does to the parser.
V=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
printf abc > "$WORK/plain.txt"
SHAPES="$WORK/shapebin"; mkdir -p "$SHAPES"

cat > "$SHAPES/sha256sum" <<EOF
#!/bin/sh
if [ \$# -eq 0 ]; then printf '%s  -\n' "$V"; else printf '%s *%s\n' "$V" "\$1"; fi
EOF
cat > "$SHAPES/shasum" <<EOF
#!/bin/sh
f=""
while [ \$# -gt 0 ]; do case "\$1" in -a|256) ;; *) f="\$1" ;; esac; shift; done
if [ -z "\$f" ]; then printf '%s  -\n' "$V"; else printf '%s *%s\n' "$V" "\$f"; fi
EOF
cat > "$SHAPES/openssl" <<EOF
#!/bin/sh
f=""
for a in "\$@"; do case "\$a" in dgst|-sha256) ;; *) f="\$a" ;; esac; done
if [ -z "\$f" ]; then printf 'SHA2-256(stdin)= %s\r\n' "$V"
else printf 'SHA2-256(%s)= %s\r\n' "\$f" "$V"; fi
EOF
cat > "$SHAPES/certutil" <<EOF
#!/bin/sh
printf 'SHA256 hash of %s:\r\n%s\r\nCertUtil: -hashfile command completed successfully.\r\n' "\$2" "$V"
EOF
chmod +x "$SHAPES"/sha256sum "$SHAPES"/shasum "$SHAPES"/openssl "$SHAPES"/certutil

read_with() { # read_with <tool> <file>
  f="$(case_file "shape-$1" "printf '%s\n' \"\$(sha256_with $1 '$2')\"")"
  PATH="$SHAPES:$PATH" bash "$f" 2>/dev/null
}

for t in sha256sum shasum openssl certutil; do
  got="$(read_with "$t" "$WORK/plain.txt")"
  check "the digest is read out of $t's own output shape" \
    "$([ "$got" = "$V" ] && echo 1 || echo 0)" "read '$got'"
done

# The input the four shape cases never asked about. A path can itself be 64 hex characters —
# a content-addressed cache directory is exactly that — and the tools that echo the path put
# it where a first-match rule finds it. Not reachable with the default runtime directory, but
# CSK_STUDIO_RUNTIME is the user's to set, and a verifier comparing the wrong value is the
# class of defect this round exists to catch.
HEXDIR="$WORK/deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
mkdir -p "$HEXDIR"; printf 'abc' > "$HEXDIR/f.txt"
for t in sha256sum shasum openssl certutil; do
  got="$(read_with "$t" "$HEXDIR/f.txt")"
  check "$t: a 64-hex path is not mistaken for the digest" \
    "$([ "$got" = "$V" ] && echo 1 || echo 0)" "read '$got'"
done

# ------------------------------------------------------------------ pin --------

# The floor is written in two files because preflight ships in editions that carry no
# panel. Two copies are fine; two different numbers are not.
a="$(sed -n 's/^FLOOR=\([0-9][0-9]*\).*/\1/p' "$SCRIPT" | head -1)"
b="$(grep -o 'node [0-9][0-9]*+' "$ROOT/claude-starter/eval/preflight.sh" | head -1 | tr -cd '0-9')"
check 'preflight and ensure-node state the same Node floor' \
  "$([ -n "$a" ] && [ "$a" = "$b" ] && echo 1 || echo 0)" "ensure-node=$a preflight=$b"

printf '\n%s passed, %s failed, %s broken\n' "$pass" "$fail" "$broken"
[ "$fail" = 0 ] && [ "$broken" = 0 ]
