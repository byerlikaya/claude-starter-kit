# Reverse proxy and SSL — the file contents

Read the half you need. A deploy uses Nginx **or** Caddy, never both, and the two paths differ most exactly
where it matters: Caddy obtains and renews the certificate itself, Nginx needs Certbot wired up separately.

The decision — which proxy is installed, whether SSL applies at all, and that the app binds only to
`127.0.0.1` — stays in `SKILL.md`. This file is what to write once that is settled.

## Nginx

Site config:

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

Link it into `sites-enabled` with `ln -s`, then `nginx -t && systemctl reload nginx`. Run `nginx -t` before
the reload every time — a reload on a broken config takes the site down, and the test costs nothing.

### SSL on the Nginx path

Skip entirely when `ssl: false` or there is no domain. **Never attempt SSL on a bare IP** — a certificate
authority cannot issue for one, and the attempt burns rate-limited quota on the domain you will use later.

Verify DNS resolves to this host *first*, or Certbot's challenge fails in a way that looks like a proxy fault:

```bash
dig +short $DOMAIN        # must equal $HOST
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN
systemctl enable certbot.timer   # automatic renewal — without this the site breaks in 90 days
```

## Caddy

```
DOMAIN {
  reverse_proxy 127.0.0.1:APP_PORT
}
```

`systemctl reload caddy`. Caddy handles the certificate and its renewal on its own — no Certbot, no timer, no
separate SSL step. If the domain does not yet resolve, Caddy will retry rather than fail loudly, so check
`journalctl -u caddy` when a fresh domain serves plain HTTP longer than expected.
