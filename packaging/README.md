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
npx @byerlikaya/claude-starter-kit            # fresh project (start.sh wizard)
npx @byerlikaya/claude-starter-kit adopt      # existing project (update.sh handover)
```

`bin/cli.js` stages the payload in a temp dir and runs it with the user's project as the CWD, so `start.sh`'s self-cleanup never touches the package or the project.

> Published as `@byerlikaya/claude-starter-kit` — scoped under the author, because the unscoped `claude-starter-kit` is taken and npm's name-similarity check blocks close variants. A scoped name sidesteps both. Users run `npx @byerlikaya/claude-starter-kit`.

## Homebrew (tap)

`homebrew/claude-starter-kit.rb` is the formula.

1. Create a repo named `homebrew-tap` (e.g. `github.com/byerlikaya/homebrew-tap`).
2. Add the formula at `Formula/claude-starter-kit.rb`.
3. Users install:

```bash
brew install byerlikaya/tap/claude-starter-kit
claude-starter-kit            # fresh project    ·    claude-starter-kit adopt    # existing project
```

The formula's `sha256` is pinned to the **v1.0.0** release tarball. If that tarball ever changes, recompute it (`shasum -a 256 claude-starter-kit-1.0.0.tgz`) and update both the `url`/`version` and the `sha256`. To host the tarball off GitHub, point `url` at your own CDN.

## Release tarball / curl — no package manager

```bash
gh release download --repo byerlikaya/claude-starter-kit -p '*.tgz' && tar xzf claude-starter-kit-*.tgz
bash start.sh         # fresh    ·    bash update.sh    # existing
```

## Release automation (CI)

`.github/workflows/release.yml` publishes everything on a version tag — no manual publish.

**Cut a release:**

```bash
# bump VERSION + package.json version (+ CHANGELOG), commit, then:
git tag v1.1.0
git push origin main --tags
```

On the tag, the workflow builds the tarball, creates the GitHub release, runs `npm publish`, and bumps the Homebrew formula in `byerlikaya/homebrew-tap` — all automatically. It first checks that `VERSION` matches the tag.

**One-time secrets** (repo → Settings → Secrets and variables → Actions → New repository secret):

- `NPM_TOKEN` — an npm **Automation** access token (npmjs.com → Access Tokens → Generate New Token → *Automation*). Automation tokens bypass 2FA, which an interactive `--otp` cannot do in CI.
- `TAP_TOKEN` — a GitHub token with write access to `byerlikaya/homebrew-tap` (a classic PAT with `repo` scope, or a fine-grained token with *Contents: read and write* on that repo). Used to push the formula bump.

## Claude Code plugin — planned (lighter channel)

Claude Code has a native plugin/marketplace system (`/plugin marketplace add …` → `/plugin install …`), including an Anthropic-curated official marketplace and support for non-GitHub hosts (any git URL or a plain HTTPS `marketplace.json`).

A plugin **registers** its bundled agents/skills/commands/hooks but **cannot run a setup script** — so a plugin edition would deliver the agents/skills for direct use in Claude Code, *without* the scaffolding (no profile pruning, no DevArchitecture base, no git-hook trace scan). It is a genuinely lighter product than the `start.sh`/`update.sh` installer, best offered as a secondary discovery channel.
