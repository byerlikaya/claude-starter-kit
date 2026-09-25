#!/usr/bin/env bash
# Re-record the three Studio pictures in assets/ from a synthetic fixture:
#   studio-flow.gif    a delegation assembling (README and the home page)
#   studio-panels.gif  the panels in use (the Studio page)
#   studio-graph.png   the finished graph (the Studio page; the home page under reduced motion)
#
# No model session and no real transcript: every project, path, session and sentence is invented, and the
# panel runs with its own projects root, runtime directory and a feed that answers the release version.
# Chrome is launched headless from a throwaway profile, so no banner or other window reaches a frame.
# macOS only (the Chrome path and the ~/… shortening of /Users/Shared); needs node, ffmpeg and Chrome.
#
#   bash packaging/studio-record/record.sh            # all three, written into assets/
#   VERSION_SHOWN=3.1.0 bash packaging/…/record.sh    # a later release
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
VERSION_SHOWN="${VERSION_SHOWN:-$(tr -d '[:space:]' < "$REPO/VERSION")}"
T="${CREW_RECORD_TMP:-${TMPDIR:-/tmp}/crewforth-studio-record}"
ROOT="$T/projects"; SNAP="$T/snapshot"; FILM="$T/film"; TOUR="$T/tour"
PORT="${CREW_RECORD_PORT:-7802}"; TOKEN="studio-record"
URL="http://127.0.0.1:$PORT/?token=$TOKEN"
HERO="7f3c1d20-9a4e-4b6f-8c21-5d0e2a41b9c7"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

for t in node ffmpeg ffprobe; do command -v "$t" >/dev/null || { echo "record: $t is not on PATH" >&2; exit 1; }; done
[ -x "$CHROME" ] || { echo "record: Google Chrome not found at $CHROME" >&2; exit 1; }

PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

mkdir -p "$T"
echo "record: fixture ($VERSION_SHOWN) -> $ROOT"
node "$HERE/fixture.mjs" "$ROOT" "$VERSION_SHOWN" >/dev/null
rm -rf "$SNAP"
node "$HERE/grow.mjs" --root "$ROOT" --snapshot "$SNAP" --resnapshot --reset >/dev/null

# The panel, isolated: its projects root is the fixture, its runtime state lives under $T, and the version feed
# is a data: URL, so nothing is read from the network and no real session on this machine can appear.
rm -rf "$T/runtime" "$T/tmp"; mkdir -p "$T/runtime" "$T/tmp"
TMPDIR="$T/tmp" CREW_STUDIO_TOKEN="$TOKEN" CREW_STUDIO_PROJECTS_ROOT="$ROOT" CREW_STUDIO_RUNTIME="$T/runtime" \
  CREW_UPDATE_URL="data:application/json,{\"latest\":\"$VERSION_SHOWN\"}" \
  node "$REPO/kit/studio/server/index.js" --port "$PORT" >"$T/server.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 40); do curl -fs -o /dev/null "$URL" && break; sleep 0.25; done
curl -fs -o /dev/null "$URL" || { echo "record: the panel did not start — see $T/server.log" >&2; exit 1; }

# Take 1: the delegation grows while Chrome films it.
node "$HERE/grow.mjs" --root "$ROOT" --snapshot "$SNAP" --lead 8 --delay 1.5 --hold forever --heartbeat 8 >"$T/grow.log" 2>&1 &
GROW=$!; PIDS+=($GROW)
sleep 0.4
node "$HERE/shoot.mjs" --url "$URL" --secs 28 --fps 10 --w 1920 --h 1000 --hide-sidebar --no-pin \
  --session "$HERO" --out "$FILM" --profile "$T/chrome-flow"
kill "$GROW" 2>/dev/null || true

# frames-dir first last width out [opening-frame hold]: frames first..last of a take, optionally opened by one
# frame held for `hold` frames. The encoding the original takes used, unchanged.
gif() {
  rm -rf "$T/cut"; mkdir -p "$T/cut"
  local i=0 f n
  if [ -n "${6:-}" ]; then for n in $(seq 1 "$7"); do cp "$6" "$(printf '%s/cut/c%04d.png' "$T" "$i")"; i=$((i + 1)); done; fi
  for f in $(ls "$1"/f*.png | sed -n "$(($2 + 1)),$(($3 + 1))p"); do cp "$f" "$(printf '%s/cut/c%04d.png' "$T" "$i")"; i=$((i + 1)); done
  ffmpeg -y -loglevel error -framerate 10 -i "$T/cut/c%04d.png" \
    -vf "fps=10,scale=$4:-1:flags=lanczos,palettegen=max_colors=128:stats_mode=diff" "$T/pal.png"
  ffmpeg -y -loglevel error -framerate 10 -i "$T/cut/c%04d.png" -i "$T/pal.png" \
    -lavfi "fps=10,scale=$4:-1:flags=lanczos [x]; [x][1:v] paletteuse=dither=none:diff_mode=rectangle" -loop 0 "$5"
}
# The last full frame is the finished graph — twelve agents and the workflow. It is the still, and it OPENS the
# flow GIF for 1.5 s: the first frame is what a link preview and a slow first load show, and the take itself begins
# on an empty canvas (the grower's lead-in, which exists only so the recorder is warm before the first spawn).
LAST="$(ls "$FILM"/f*.png | sed -n 273p)"
gif "$FILM" "${FLOW_FROM:-55}" 274 1600 "$REPO/assets/studio-flow.gif" "$LAST" 15
cp "$LAST" "$REPO/assets/studio-graph.png"

# Take 2: the panels, on the finished fixture with its running agents kept live.
node "$HERE/grow.mjs" --root "$ROOT" --snapshot "$SNAP" --reset >/dev/null
bash "$HERE/refresh-running.sh" "$ROOT" >/dev/null
node "$HERE/tour.mjs" --url "$URL" --session "Duplicate settlements" --out "$TOUR" --profile "$T/chrome-tour"
gif "$TOUR" 0 100000 1600 "$REPO/assets/studio-panels.gif"

for f in studio-flow.gif studio-panels.gif studio-graph.png; do
  printf 'record: assets/%-18s %9s bytes  %s\n' "$f" "$(wc -c < "$REPO/assets/$f" | tr -d ' ')" \
    "$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=width,height,nb_read_frames -of csv=p=0 "$REPO/assets/$f")"
done
