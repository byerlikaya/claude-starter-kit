---
name: vps-deploy
description: |
  Deploy to a VPS safely: runtime detection, reverse proxy + SSL, atomic swap, keep the previous version,
  post-deploy health gate, automatic rollback on failure.
  Trigger phrases: "deploy", "push to the server", "install on the VPS", "ship it to the server", "go to production"
---

# VPS Deploy

A solid deploy has a single idea: **swap the running version with the new one in a reversible way.**
That is, when you put the new version in place, don't throw the old one away — keep it aside. If the new version
can't pass the health gate, undo the swap and no one notices. This skill builds the deploy around this swap;
Docker or bare-metal, a single app or different runtimes, it makes no difference.

> **Kit adaptation (local, .claude/):** Default backend is **.NET (Docker recommended)**. **Deploy requires explicit
> approval (§4.4)**; a backup before every swap and a health gate after are mandatory. If `.deploy.yml` carries server
> credentials it goes into `.gitignore`. §4 Prohibitions apply.

## Checklist
- [ ] Runtime + deploy method determined
- [ ] Config taken from `.deploy.yml`/the user, SSH verified
- [ ] Reverse proxy + (if there is a domain) SSL in place
- [ ] Running version backed up to `releases/`
- [ ] User approved the deploy, new version deployed
- [ ] Health gate passed (otherwise automatic rollback performed)
- [ ] If requested, single-command scripts (`deploy.sh` / `adopt.sh`) generated

---

## Phase 1 — Surface: method and runtime

```bash
if   [ -f Dockerfile ] || [ -f docker-compose.yml ]; then METHOD=docker
elif [ -f package.json ];                                then METHOD=bare RUNTIME=node
elif [ -f requirements.txt ] || [ -f pyproject.toml ];   then METHOD=bare RUNTIME=python
elif [ -f go.mod ];                                      then METHOD=bare RUNTIME=go
else METHOD=unknown; fi
```
If `method: docker` and there's no Dockerfile, generate one. `method: bare` → a process manager suited to the runtime. If detection is ambiguous, ask the user. **.NET:** Docker recommended; if bare is required, run the `dotnet publish -c Release` output with systemd.

---

## Phase 2 — Preparation: config, SSH, proxy, SSL

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

<details><summary>Nginx site config</summary>

```nginx
server {
  listen 80;
  server_name DOMAIN;
  location / {
    proxy_pass http://127.0.0.1:APP_PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```
Link it into `sites-enabled` with `ln -s`, then `nginx -t && systemctl reload nginx`.
</details>

<details><summary>Caddyfile (SSL included, automatic)</summary>

```
DOMAIN {
  reverse_proxy 127.0.0.1:APP_PORT
}
```
`systemctl reload caddy`. Caddy obtains/renews the certificate on its own — no extra step.
</details>

**SSL (Nginx path)** — skip if `ssl: false` or there's no domain; don't do SSL on a bare IP. First verify that DNS resolves to the host (`dig +short $DOMAIN` = `$HOST`), then Certbot:
```bash
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN
systemctl enable certbot.timer   # automatic renewal
```

---

## Phase 3 — Swap: keep the old, put the new

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

## Phase 4 — Health gate

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

## Phase 5 — Rollback

On health-gate failure: put the most recent `releases/` version back into `current`, restart the service, and
re-run the health gate (Phase 4). Guard-safe rollback script (uses `rsync --delete`, not `rm -rf`) + the
approval-gate note: **`references/rollback.md`**.

---

## Single-command scripts (optional)

After a successful deploy, **ask** whether to generate project-specific `deploy.sh` / `adopt.sh` (single-command
deploy/update). Derive the steps from the real project (package.json / Dockerfile / Makefile / compose), never a
generic template. Full guidance + what each script contains: **`references/scripts.md`**.

---

## Invariant rules
1. **No deploy without approval** — show the method/host/domain/port plan, wait for approval.
2. **Always back up before the swap** — timestamped into `releases/`; if the backup fails, abort.
3. **Always a health gate after the swap** — HTTP + process; if it doesn't pass, automatic rollback.
4. **Keep the last 3 versions** — don't delete them all.
5. **Don't deploy to prod without knowing the target** — host/deploy_path/domain must be approved.
6. **Verify SSH first** — if you can't connect, fail fast.
7. **Don't expose the port directly** — the app binds to `127.0.0.1`, outward only through the proxy.
8. **SSL is mandatory when there's a domain** — always set it up unless `ssl` is explicitly `false`.
