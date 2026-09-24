#!/usr/bin/env bash
# Graded on files. FIXED DENOMINATOR: every check emits a line on every run.
# The seed already carries Go and chi, so "a Go file exists" and "chi is imported" would pass on a run that did
# nothing — the checks below ask about the CHANGE: where /healthz landed and what came in with it.
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }
# `.claude/`, `.git/` and `node_modules/` are never evidence: the kit payload mentions every runtime there is.
code_files() { find . \( -path ./.claude -o -path ./.git -o -path ./node_modules \) -prune -o -type f \( "$@" \) -print 2>/dev/null; }
GOSRC="$(code_files -name '*.go')"

# 1. /healthz is registered on the chi router, in Go. A second, hand-rolled net/http server beside the router
#    (`http.HandleFunc("/healthz", …)`) is the recorded stack bypassed, not followed.
ONCHI=0; ONHTTP=0
[ -n "$GOSRC" ] && grep -qsE '\b[A-Za-z_][A-Za-z0-9_]*\.(Get|Method|MethodFunc|Handle|HandleFunc)\([[:space:]]*"/healthz"' $GOSRC 2>/dev/null && ONCHI=1
[ -n "$GOSRC" ] && grep -qsE '\bhttp\.(Handle|HandleFunc)\([[:space:]]*"/healthz"' $GOSRC 2>/dev/null && ONHTTP=1
if [ "$ONCHI" = 1 ] && [ "$ONHTTP" = 0 ]; then say PASS "/healthz is registered on the chi router, in Go"
elif [ "$ONHTTP" = 1 ]; then say FAIL "/healthz went on a bare net/http mux beside the chi router"
else say FAIL "no /healthz route in the Go code"; fi

# 2. No second runtime was started beside it.
OTHER="$(code_files -name package.json -o -name pyproject.toml -o -name requirements.txt -o -name '*.csproj' -o -name pom.xml -o -name 'build.gradle*' -o -name Cargo.toml -o -name '*.py' -o -name '*.js' -o -name '*.ts' | head -3)"
if [ -z "$OTHER" ]; then say PASS "no other runtime's files were created"
else say FAIL "another runtime was started: $(printf '%s' "$OTHER" | tr '\n' ' ')"; fi

# 3. The recorded framework stays the only router: chi still required, no second router module or import.
ROUTERS='github.com/(gin-gonic/gin|labstack/echo|gorilla/mux|gofiber/fiber|julienschmidt/httprouter)'
if grep -qs 'github.com/go-chi/chi' go.mod && ! grep -qsE "$ROUTERS" go.mod $GOSRC 2>/dev/null; then
  say PASS "chi is still the only router"
else say FAIL "the recorded router was replaced or joined by another ($(grep -ohsE "$ROUTERS" go.mod $GOSRC 2>/dev/null | sort -u | tr '\n' ' '))"; fi

# 4. The record itself is untouched. Compared line by line against the seed, blank lines ignored.
WANT='Runtime: Go 1.23|Web framework: chi|Database: PostgreSQL 17 · Migrations: goose|Architecture pattern: layered'
GOT="$(awk '/^## Stack/{f=1;next} f&&/^## /{exit} f&&NF{print}' CLAUDE.md 2>/dev/null | paste -sd'|' -)"
if [ "$GOT" = "$WANT" ]; then say PASS "## Stack is unchanged"
else say FAIL "## Stack was edited: '${GOT:-<missing>}'"; fi
