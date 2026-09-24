# Distribution / publishing

The kit ships through several channels. These files support the ones that do **not** depend on a GitHub clone. Each channel bundles the same payload (`start.sh`, `adopt.sh`, `kit/`, `VERSION`).

## npm (npx) — primary

`package.json` + `bin/cli.js` at the repo root make this an npm package that bundles the whole payload.

```bash
npm login
npm publish --access public
```

Users then need nothing but Node:

```bash
npx crewforth            # fresh project (start.sh wizard)
npx crewforth adopt      # existing project (adopt.sh handover)
```

`bin/cli.js` stages the payload in a temp dir and runs it with the user's project as the CWD, so `start.sh`'s self-cleanup never touches the package or the project.

> Published as `crewforth` — scoped under the author, because the unscoped `crewforth` is taken and npm's name-similarity check blocks close variants. A scoped name sidesteps both. Users run `npx crewforth`.

## Homebrew (tap)

`homebrew/crewforth.rb` is the formula.

1. Create a repo named `homebrew-tap` (e.g. `github.com/byerlikaya/homebrew-tap`).
2. Add the formula at `Formula/crewforth.rb`.
3. Users install:

```bash
brew install byerlikaya/tap/crewforth
crewforth            # fresh project    ·    crewforth adopt    # existing project
```

The formula's `sha256` is pinned to the **v1.0.0** release tarball. If that tarball ever changes, recompute it (`shasum -a 256 crewforth-1.0.0.tgz`) and update both the `url`/`version` and the `sha256`. To host the tarball off GitHub, point `url` at your own CDN.

## Release tarball / curl — no package manager

```bash
gh release download --repo Crewforth/crewforth -p '*.tgz' && tar xzf crewforth-*.tgz
bash start.sh         # fresh    ·    bash adopt.sh    # existing
```

## Release automation (CI)

`.github/workflows/release.yml` publishes everything on a version tag — no manual publish.

**Cut a release:**

```bash
# bump VERSION + package.json version (+ CHANGELOG), commit, then:
git tag vX.Y.Z
git push origin main --tags
```

On the tag, the workflow builds the tarball, creates the GitHub release, runs `npm publish`, and bumps the Homebrew formula in `byerlikaya/homebrew-tap` — all automatically. It first checks that `VERSION` matches the tag.

**One-time secrets** (repo → Settings → Secrets and variables → Actions → New repository secret):

- `NPM_TOKEN` — an npm **Automation** access token (npmjs.com → Access Tokens → Generate New Token → *Automation*). Automation tokens bypass 2FA, which an interactive `--otp` cannot do in CI.
- `TAP_TOKEN` — a GitHub token with write access to `byerlikaya/homebrew-tap` (a classic PAT with `repo` scope, or a fine-grained token with *Contents: read and write* on that repo). Used to push the formula bump.

## Claude Code plugin (lite channel)

Users can install the kit's agents, skills, and commands directly in Claude Code:

```
/plugin marketplace add Crewforth/crewforth
/plugin install crewforth@crewforth
```

This is the **lite** edition — it registers the agents/skills/commands only, *without* the scaffolding (no git-hook gates, no `.gitignore` / `kit.conf` writes). The component set is identical to a `start.sh` install, and `e2e.sh` asserts that parity. For the full kit use `start.sh` / `adopt.sh`.

`plugin/` (and its `.claude-plugin/plugin.json`) is generated from `kit/` by **`packaging/build-plugin.sh`** — rerun it after changing agents/skills/commands so the plugin stays in sync. The release workflow verifies this on every tag. The marketplace manifest is `.claude-plugin/marketplace.json` at the repo root.
