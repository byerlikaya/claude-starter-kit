#!/usr/bin/env bash
# Graded on files. FIXED DENOMINATOR: every check emits a line on every run.
set -uo pipefail
say() { printf '%s %s\n' "$1" "$2"; }
code_files() { find . \( -path ./.claude -o -path ./.git -o -path ./node_modules \) -prune -o -type f \( "$@" \) -print 2>/dev/null; }
JS="--include=*.js --include=*.ts --include=*.mjs"

# 1. The endpoint exists, in the repo's own runtime.
# shellcheck disable=SC2086
if grep -rqsE "['\"]/time['\"]" $JS --exclude-dir=.claude --exclude-dir=node_modules . 2>/dev/null; then say PASS "a /time route was added in JS/TS"
else say FAIL "no /time route in the Node code"; fi

# 2. No other runtime appeared.
OTHER="$(code_files -name go.mod -o -name pyproject.toml -o -name requirements.txt -o -name '*.csproj' -o -name pom.xml -o -name 'build.gradle*' -o -name Cargo.toml -o -name '*.go' -o -name '*.py' | head -3)"
if [ -z "$OTHER" ]; then say PASS "no other runtime's files were created"
else say FAIL "another runtime was started: $(printf '%s' "$OTHER" | tr '\n' ' ')"; fi

# 3. The detected framework was kept — no second web framework added to package.json.
if grep -qsE '"(express|koa|hapi|@hapi/hapi|@nestjs/core|hono)"' package.json; then say FAIL "a second web framework was added to package.json"
else say PASS "package.json carries no second web framework"; fi

# 4. The route is registered on a Fastify instance (app.get / app.route), not on a hand-rolled http server.
# shellcheck disable=SC2086
if grep -rqsE "\.(get|route)\( *['\"]/time|url: *['\"]/time" $JS --exclude-dir=.claude --exclude-dir=node_modules . 2>/dev/null \
   && ! grep -rqsE "from ['\"](node:)?http['\"]|require\(['\"](node:)?http['\"]\)" $JS --exclude-dir=.claude --exclude-dir=node_modules . 2>/dev/null; then
  say PASS "the route is registered through Fastify"
else say FAIL "the /time route is not registered through the existing Fastify app"; fi
