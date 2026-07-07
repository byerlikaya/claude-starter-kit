# Distribution / publishing

The kit ships through several channels. These files support the ones that do **not** depend on a GitHub clone. Each channel bundles the same payload (`start.sh`, `update.sh`, `claude-starter/`, `VERSION`).

## npm (npx) — primary

`package.json` + `bin/cli.js` at the repo root make this an npm package that bundles the whole payload.

```bash
npm login
npm publish --access public
```

Users then need nothing but Node:

```bash
npx claude-code-starter-kit            # fresh project (start.sh wizard)
npx claude-code-starter-kit adopt      # existing project (update.sh handover)
```

`bin/cli.js` stages the payload in a temp dir and runs it with the user's project as the CWD, so `start.sh`'s self-cleanup never touches the package or the project.

> Published as `claude-code-starter-kit` (the bare `claude-starter-kit` was already taken on npm). To rename, edit `name` (and the matching `bin` key) in `package.json`.

## Homebrew (tap)

`homebrew/claude-kit.rb` is the formula.

1. Create a repo named `homebrew-tap` (e.g. `github.com/byerlikaya/homebrew-tap`).
2. Add the formula at `Formula/claude-kit.rb`.
3. Users install:

```bash
brew install byerlikaya/tap/claude-kit
claude-kit            # fresh project    ·    claude-kit adopt    # existing project
```

The formula's `sha256` is pinned to the **v1.0.0** release tarball. If that tarball ever changes, recompute it (`shasum -a 256 claude-starter-kit-1.0.0.tgz`) and update both the `url`/`version` and the `sha256`. To host the tarball off GitHub, point `url` at your own CDN.

## Release tarball / curl — no package manager

```bash
gh release download --repo byerlikaya/claude-starter-kit -p '*.tgz' && tar xzf claude-starter-kit-*.tgz
bash start.sh         # fresh    ·    bash update.sh    # existing
```

## Claude Code plugin — planned (lighter channel)

Claude Code has a native plugin/marketplace system (`/plugin marketplace add …` → `/plugin install …`), including an Anthropic-curated official marketplace and support for non-GitHub hosts (any git URL or a plain HTTPS `marketplace.json`).

A plugin **registers** its bundled agents/skills/commands/hooks but **cannot run a setup script** — so a plugin edition would deliver the agents/skills for direct use in Claude Code, *without* the scaffolding (no profile pruning, no DevArchitecture base, no git-hook trace scan). It is a genuinely lighter product than the `start.sh`/`update.sh` installer, best offered as a secondary discovery channel.
