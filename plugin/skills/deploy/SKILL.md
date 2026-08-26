---
name: deploy
description: |
  Ship a build reversibly — to a host you manage or a platform that manages it. Pick the topology first, keep
  the previous version reachable, gate on health, roll back without rebuilding. Use when shipping anywhere
  users can reach.
---

# Deploy

<!-- routing-eval reads this line; it lives in the BODY so the always-on skill LISTING stays inside
     Claude Code's budget (1% of the context window) — an overflowing listing gets descriptions
     truncated or dropped, which strips the very keywords a match depends on. -->
Trigger phrases: "deploy", "push to the server", "to the server", "onto the server", "build on the server", "install on the VPS", "ship it to the server", "go to production", "to production", "go live"

A deploy has a single idea, and it does not depend on where you are deploying: **make the new version live in a
way you can undo.** Keep the previous version reachable until the new one has proved itself; if it fails the
health gate, go back to the old one and nobody notices.

**Two topologies implement that idea differently, and mixing them is where deploys go wrong.** On a host you
manage, "reversible" means the previous release still sits on disk and the swap is a pointer you can move back.
On a platform that manages the host for you, "reversible" means the previous *artefact* is still addressable and
you re-point the environment at it — you do not rebuild it. Phase 0 picks the branch; everything after follows.

> **Kit adaptation (local, .claude/):** Default backend is **.NET (Docker recommended)**. **Deploy requires explicit
> approval (§4.4)**; a backup before every swap and a health gate after are mandatory. If `.deploy.yml` carries server
> credentials it goes into `.gitignore`. §4 Prohibitions apply.

## Phase 0 — Which topology
Answer before anything else, because the rest of the skill forks here. Ask if it is not obvious; do not infer it
from the language or the framework.

| | **A · Self-managed host** | **B · Managed platform** |
|---|---|---|
| You have | SSH to a machine you own or rent | an API/CLI, and no shell on the box |
| A release is | a directory on that host | an immutable artefact (image digest, build id, bundle) |
| "Deploy" means | put the files in place and restart | promote an existing artefact to an environment |
| Rollback means | move the pointer back to the previous directory | re-point the environment at the previous artefact |
| Owned by | **Phases 1–5 below** | **Phase B1–B4 below** |

Signals for B: the platform builds from a push, or the runtime is described as containers/functions/dynos/pods
that you do not administer. Signals for A: you are given a host, a user and a port. A Kubernetes cluster is B
when a controller reconciles it from a manifest, and A only if you are genuinely hand-placing files on nodes.

**If both are in play** — a managed platform in front, a self-managed worker behind — run the branches
separately and gate each on its own health check. One approval does not cover two topologies.

## Checklist (A · self-managed host)
- [ ] Topology decided (Phase 0)
- [ ] Runtime + deploy method determined
- [ ] Config taken from `.deploy.yml`/the user, SSH verified
- [ ] Reverse proxy + (if there is a domain) SSL in place
- [ ] Running version backed up to `releases/`
- [ ] User approved the deploy, new version deployed
- [ ] Health gate passed (otherwise automatic rollback performed)
- [ ] If requested, single-command scripts (`deploy.sh` / `adopt.sh`) generated

## Checklist (B · managed platform)
- [ ] Topology decided (Phase 0)
- [ ] Artefact built once and addressed immutably (digest / build id, not a moving tag)
- [ ] Which artefact is in which environment is recorded
- [ ] Config and secrets injected per environment, not baked into the artefact
- [ ] User approved the promotion to this environment
- [ ] Health gate passed from OUTSIDE — not the platform's own status
- [ ] Previous artefact still addressable, and the migration question settled before the deploy

---

## Phase 1 (A) — Surface: method and runtime

```bash
if   [ -f Dockerfile ] || [ -f docker-compose.yml ]; then METHOD=docker
elif [ -f package.json ];                                then METHOD=bare RUNTIME=node
elif [ -f requirements.txt ] || [ -f pyproject.toml ];   then METHOD=bare RUNTIME=python
elif [ -f go.mod ];                                      then METHOD=bare RUNTIME=go
elif ls ./*.csproj ./*.sln >/dev/null 2>&1;              then METHOD=bare RUNTIME=dotnet
elif [ -f pom.xml ] || [ -f build.gradle ];              then METHOD=bare RUNTIME=java
elif [ -f Cargo.toml ];                                  then METHOD=bare RUNTIME=rust
elif [ -f Gemfile ];                                     then METHOD=bare RUNTIME=ruby
elif [ -f composer.json ];                               then METHOD=bare RUNTIME=php
else METHOD=unknown; fi
```
If `method: docker` and there's no Dockerfile, generate one. `method: bare` → a process manager suited to the runtime; build the release artefact with the runtime's own command (`dotnet publish -c Release`, `mvn package`, `cargo build --release`, …) and run it under systemd. Prefer Docker for any runtime whose bare setup needs a toolchain on the box. If detection is ambiguous, ask the user — never guess a runtime.

---

## Phase 2 (A) — Preparation: config, SSH, proxy, SSL

**Config** — read `.deploy.yml` from the root, and if it's missing ask for each field:
```yaml
host: 192.168.1.100        # VPS IP/hostname (required)
user: deploy               # SSH user (required)
ssh_key: ~/.ssh/id_rsa     # private key
app_port: 3000             # application port (required)
health_check: /api/health  # HTTP path (default /)
deploy_path: /var/www/app  # server path (required)
method: auto               # auto | docker | bare
domain: app.example.com    # for proxy/SSL (optional)
ssl: true                  # default true if there is a domain
reverse_proxy: auto        # auto | nginx | caddy
```
**Verify SSH first** — if you can't connect, stop immediately:
```bash
ssh -i $SSH_KEY -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new $USER@$HOST "echo OK"
```

**Reverse proxy** — detect the one installed on the server (`auto` → Caddy if present, otherwise Nginx). The application binds only to `127.0.0.1`; it is exposed outward **only** through the proxy.

**SSL** — skip if `ssl: false` or there's no domain, and never on a bare IP. On the Nginx path, verify DNS resolves to the host (`dig +short $DOMAIN` = `$HOST`) *before* running Certbot; on the Caddy path the certificate and its renewal are automatic and there is no separate step.

Config file contents for both proxies, the Certbot commands and the renewal timer: **`references/proxy-ssl.md`** — read the half for the proxy you found, not both.

---

## Phase 3 (A) — Swap: keep the old, put the new

**First back up the running version** (timestamped `releases/`, last 3 kept):
```bash
ssh -i $SSH_KEY $USER@$HOST "
  mkdir -p $DEPLOY_PATH/releases
  [ -d $DEPLOY_PATH/current ] && cp -a $DEPLOY_PATH/current $DEPLOY_PATH/releases/$(date +%Y%m%d_%H%M%S)
  cd $DEPLOY_PATH/releases && ls -dt */ | tail -n +4 | xargs -r rm -rf
"
```

**Docker** — build the image locally, transfer it, replace the container:
```bash
docker build -t $APP:latest .
docker save $APP:latest | gzip | ssh -i $SSH_KEY $USER@$HOST "gunzip | docker load"
ssh -i $SSH_KEY $USER@$HOST "
  docker rm -f $APP 2>/dev/null || true
  docker run -d --name $APP --restart unless-stopped -p 127.0.0.1:$APP_PORT:$APP_PORT $APP:latest
"
```

**Bare-metal** — `rsync` the source, install dependencies, start with the process manager:
```bash
rsync -avz --delete --exclude .git --exclude node_modules --exclude .venv \
  -e "ssh -i $SSH_KEY" ./ $USER@$HOST:$DEPLOY_PATH/current/
```

| Runtime | Dependencies + startup |
|---|---|
| Node | `npm ci --production` → PM2: `pm2 start ecosystem.config.js --name $APP || pm2 start npm --name $APP -- start` → `pm2 save` |
| Python | `python3 -m venv venv && venv/bin/pip install -r requirements.txt` → systemd (gunicorn/uvicorn or `python main.py`) |
| Go | build locally `GOOS=linux GOARCH=amd64 go build -o $APP` → `scp` → systemd |

systemd unit (for Python/Go, fill in ExecStart per the runtime):
```ini
[Unit]
After=network.target
[Service]
Type=simple
User=$USER
WorkingDirectory=$DEPLOY_PATH/current
ExecStart=<runtime command>
Restart=always
Environment=PORT=$APP_PORT
[Install]
WantedBy=multi-user.target
```
`systemctl daemon-reload && systemctl enable --now $APP`.

---

## Phase 4 (A) — Health gate

Right after the swap; retry for ~30 s until a 200 comes back. **If it doesn't pass, trigger Phase 5 automatically.**
```bash
ssh -i $SSH_KEY $USER@$HOST '
  for i in $(seq 1 6); do
    [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:'"$APP_PORT$HEALTH_CHECK"')" = 200 ] \
      && { echo "Health gate PASSED"; exit 0; }
    sleep 5
  done
  echo "Health gate FAILED"; exit 1
'
```
Also verify the process is up: `docker ps` on Docker, otherwise `systemctl is-active $APP` / `pm2 show $APP`.

---

## Phase 5 (A) — Rollback

On health-gate failure: put the most recent `releases/` version back into `current`, restart the service, and
re-run the health gate (Phase 4). Guard-safe rollback script (uses `rsync --delete`, not `rm -rf`) + the
approval-gate note: **`references/rollback.md`**.

---

## Phase B1 — Build once, and know what you built
The artefact is produced **once**, and the same one moves through every environment. Rebuilding for production
means the thing you tested is not the thing you shipped — the inputs moved underneath you (a floating base
image, a lockfile resolved a minute later, a different builder). Two consequences:
- **Address it immutably.** A digest or a build id, never a moving tag. `latest`, `main` and a branch name all
  name different bytes on different days, which makes both promotion and rollback unverifiable.
- **Record which artefact is in which environment.** If nobody can answer "what exactly is running in
  production", rollback is a guess and the health gate has nothing to compare against.

## Phase B2 — Promote, do not rebuild
Deploying to the next environment means pointing that environment at an artefact that already exists and has
already passed the previous gate. Configuration is injected per environment, never baked into the artefact — the
same bytes must be able to run in staging and in production, or you are back to rebuilding. Secrets come from
the platform's own store; a secret inside the artefact ships to everyone who can pull it.

**Approval is per environment (§4.4), and per topology.** Promoting to a user-facing environment is a deploy,
whatever the platform calls it.

## Phase B3 — Health gate, from outside
Identical in spirit to Phase 4 (A) and worth stating because platforms invite the opposite: **the platform
reporting "deployed", "healthy" or "active" is not the verification.** It reports that its own reconciliation
finished. Check the thing users touch — a request through the public entry point, a real response body, the
version endpoint returning the version you promoted. Give it the same failure rule: if the gate does not pass,
go back before investigating.

## Phase B4 — Roll back by re-pointing
Rollback is promoting the previous artefact, not rebuilding the previous commit — a rebuild is a new artefact
with new inputs and it may not even reproduce the bug you are escaping. So:
- Keep the previous artefacts addressable for at least as long as you promise to be able to roll back. A
  retention policy that deletes them is a rollback policy that does not work.
- Rolling back **code** does not roll back a **migration**. If the release included an irreversible schema
  change, the old artefact may not run against the new schema — that is `db-migration`'s expand/contract
  question and it has to be answered before the deploy, not during the incident.
- After a rollback, the environment is running an artefact older than the recorded state. Say so plainly to
  whoever is watching; a silent rollback is how two people fix the same outage twice.

## Single-command scripts (optional)

After a successful deploy, **ask** whether to generate project-specific `deploy.sh` / `adopt.sh` (single-command
deploy/update). Derive the steps from the real project (package.json / Dockerfile / Makefile / compose), never a
generic template. Full guidance + what each script contains: **`references/scripts.md`**.

---

## Invariant rules
These hold on BOTH branches; where the mechanism differs, the rule does not.
0. **The topology is decided, not assumed** — Phase 0, once, out loud. Everything downstream depends on it.
1. **No deploy without approval** — show the method/host/domain/port plan, wait for approval.
2. **Always back up before the swap** — timestamped into `releases/`; if the backup fails, abort.
3. **Always a health gate after the swap** — HTTP + process; if it doesn't pass, automatic rollback.
4. **Keep the last 3 versions** — don't delete them all.
5. **Don't deploy to prod without knowing the target** — host/deploy_path/domain must be approved.
6. **Verify SSH first** — if you can't connect, fail fast.
7. **Don't expose the port directly** — the app binds to `127.0.0.1`, outward only through the proxy.
8. **SSL is mandatory when there's a domain** — always set it up unless `ssl` is explicitly `false`.
9. **Never rebuild to roll back** (B) — promote the previous artefact. A rebuild is a different artefact.
10. **The platform's own status is not the health gate** (B) — verify from where a user stands.
11. **Rolling back code does not roll back a migration** — settle the schema question before the deploy.
