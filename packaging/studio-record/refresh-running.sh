#!/usr/bin/env bash
# The three "running" nodes are running because their transcripts were written
# less than 120s ago. Touch them again just before a take.
set -euo pipefail
ROOT="${1:?usage: refresh-running.sh <projects-root>}"
S="$ROOT/-Users-Shared-dev-acme-payments-api/7f3c1d20-9a4e-4b6f-8c21-5d0e2a41b9c7/subagents"
for a in f20a7c63 5d93be08 c7e58f14; do touch "$S/agent-$a.jsonl"; done
echo "touched 3 running agents at $(date +%H:%M:%S)"
