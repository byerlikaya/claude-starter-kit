---
name: vps-deploy
description: |
  Uygulamayı VPS'e güvenle dağıt: runtime/yöntem tespiti, reverse proxy + SSL, atomik takas,
  eski sürümü saklama, deploy-sonrası sağlık kapısı ve başarısızlıkta otomatik geri dönüş.
  Trigger phrases: "deploy", "sunucuya gönder", "VPS'e kur", "sunucuya at", "production'a çık"
---

# VPS Deploy

Sağlam bir deploy'un tek fikri var: **çalışan sürümü, yenisiyle geri-alınabilir biçimde takas et.**
Yani yeni sürümü koyarken eskisini atma — kenarda tut. Yeni sürüm sağlık kapısından geçemezse
takası geri al, kimse fark etmesin. Bu skill deploy'u bu takas etrafında kurar; Docker veya
bare-metal, tek bir uygulama ya da farklı runtime'lar fark etmez.

> **Kit uyarlaması (lokal, .claude/):** Varsayılan backend **.NET (Docker önerilir)**. **Deploy açık
> onay ister (§4.4)**; her takastan önce yedek, sonra sağlık kapısı zorunlu. `.deploy.yml` sunucu
> kimliği taşırsa `.gitignore`'a alınır. §4 Yasaklar geçerlidir.

## Kontrol listesi
- [ ] Runtime + deploy yöntemi belirlendi
- [ ] Config `.deploy.yml`'den/kullanıcıdan alındı, SSH doğrulandı
- [ ] Reverse proxy + (domain varsa) SSL yerinde
- [ ] Çalışan sürüm `releases/`'e yedeklendi
- [ ] Kullanıcı deploy'u onayladı, yeni sürüm dağıtıldı
- [ ] Sağlık kapısı geçti (yoksa otomatik geri dönüş yapıldı)
- [ ] İstenirse tek-komut scriptler (`deploy.sh` / `update.sh`) üretildi

---

## Faz 1 — Yüzey: yöntem ve runtime

```bash
if   [ -f Dockerfile ] || [ -f docker-compose.yml ]; then METHOD=docker
elif [ -f package.json ];                                then METHOD=bare RUNTIME=node
elif [ -f requirements.txt ] || [ -f pyproject.toml ];   then METHOD=bare RUNTIME=python
elif [ -f go.mod ];                                      then METHOD=bare RUNTIME=go
else METHOD=unknown; fi
```
`method: docker` ve Dockerfile yoksa üret. `method: bare` → runtime'a uygun process manager. Tespit belirsizse kullanıcıya sor. **.NET:** Docker önerilir; bare gerekirse `dotnet publish -c Release` çıktısını systemd ile çalıştır.

---

## Faz 2 — Hazırlık: config, SSH, proxy, SSL

**Config** — kökten `.deploy.yml` oku, yoksa her alanı sor:
```yaml
host: 192.168.1.100        # VPS IP/hostname (zorunlu)
user: deploy               # SSH kullanıcısı (zorunlu)
ssh_key: ~/.ssh/id_rsa     # özel anahtar
app_port: 3000             # uygulama portu (zorunlu)
health_check: /api/health  # HTTP yolu (varsayılan /)
deploy_path: /var/www/app  # sunucu yolu (zorunlu)
method: auto               # auto | docker | bare
domain: app.example.com    # proxy/SSL için (ops.)
ssl: true                  # domain varsa varsayılan true
reverse_proxy: auto        # auto | nginx | caddy
```
**SSH'ı önce doğrula** — kurulamıyorsa hemen dur:
```bash
ssh -i $SSH_KEY -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new $USER@$HOST "echo OK"
```

**Reverse proxy** — sunucuda kurulu olanı tespit et (`auto` → Caddy varsa Caddy, yoksa Nginx). Uygulama yalnız `127.0.0.1`'e bağlanır; dışarı **sadece** proxy üzerinden açılır.

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
`ln -s` ile `sites-enabled`'a bağla, `nginx -t && systemctl reload nginx`.
</details>

<details><summary>Caddyfile (SSL dahil, otomatik)</summary>

```
DOMAIN {
  reverse_proxy 127.0.0.1:APP_PORT
}
```
`systemctl reload caddy`. Caddy sertifikayı kendi alır/yeniler — ek adım yok.
</details>

**SSL (Nginx yolu)** — `ssl: false` veya domain yoksa atla; çıplak IP'ye SSL yapma. Önce DNS'in host'a çözdüğünü doğrula (`dig +short $DOMAIN` = `$HOST`), sonra Certbot:
```bash
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN
systemctl enable certbot.timer   # otomatik yenileme
```

---

## Faz 3 — Takas: eskiyi sakla, yeniyi koy

**Önce çalışan sürümü yedekle** (zaman damgalı `releases/`, son 3 tutulur):
```bash
ssh -i $SSH_KEY $USER@$HOST "
  mkdir -p $DEPLOY_PATH/releases
  [ -d $DEPLOY_PATH/current ] && cp -a $DEPLOY_PATH/current $DEPLOY_PATH/releases/$(date +%Y%m%d_%H%M%S)
  cd $DEPLOY_PATH/releases && ls -dt */ | tail -n +4 | xargs -r rm -rf
"
```

**Docker** — imajı yerelde derle, taşı, konteyneri değiştir:
```bash
docker build -t $APP:latest .
docker save $APP:latest | gzip | ssh -i $SSH_KEY $USER@$HOST "gunzip | docker load"
ssh -i $SSH_KEY $USER@$HOST "
  docker rm -f $APP 2>/dev/null || true
  docker run -d --name $APP --restart unless-stopped -p 127.0.0.1:$APP_PORT:$APP_PORT $APP:latest
"
```

**Bare-metal** — kaynağı `rsync`'le, bağımlılığı kur, process manager'la başlat:
```bash
rsync -avz --delete --exclude .git --exclude node_modules --exclude .venv \
  -e "ssh -i $SSH_KEY" ./ $USER@$HOST:$DEPLOY_PATH/current/
```

| Runtime | Bağımlılık + başlatma |
|---|---|
| Node | `npm ci --production` → PM2: `pm2 start ecosystem.config.js --name $APP || pm2 start npm --name $APP -- start` → `pm2 save` |
| Python | `python3 -m venv venv && venv/bin/pip install -r requirements.txt` → systemd (gunicorn/uvicorn ya da `python main.py`) |
| Go | yerelde `GOOS=linux GOARCH=amd64 go build -o $APP` → `scp` → systemd |

systemd birimi (Python/Go için ExecStart'ı runtime'a göre doldur):
```ini
[Unit]
After=network.target
[Service]
Type=simple
User=$USER
WorkingDirectory=$DEPLOY_PATH/current
ExecStart=<runtime komutu>
Restart=always
Environment=PORT=$APP_PORT
[Install]
WantedBy=multi-user.target
```
`systemctl daemon-reload && systemctl enable --now $APP`.

---

## Faz 4 — Sağlık kapısı

Takastan hemen sonra; 200 gelene dek ~30 sn dene. **Geçmezse Faz 5'i otomatik tetikle.**
```bash
ssh -i $SSH_KEY $USER@$HOST '
  for i in $(seq 1 6); do
    [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:'"$APP_PORT$HEALTH_CHECK"')" = 200 ] \
      && { echo "Sağlık kapısı GEÇTİ"; exit 0; }
    sleep 5
  done
  echo "Sağlık kapısı BAŞARISIZ"; exit 1
'
```
Ayrıca process ayakta mı doğrula: Docker'da `docker ps`, aksi halde `systemctl is-active $APP` / `pm2 show $APP`.

---

## Faz 5 — Geri dönüş

Takası geri al: `releases/`'teki en son sürümü `current`'a koy, servisi yeniden başlat, sağlık kapısını (Faz 4) tekrarla.
```bash
LATEST=$(ssh -i $SSH_KEY $USER@$HOST "ls -dt $DEPLOY_PATH/releases/*/ 2>/dev/null | head -1")
[ -z "$LATEST" ] && { echo "HATA: yedek yok — geri dönüş yapılamaz"; exit 1; }
ssh -i $SSH_KEY $USER@$HOST "
  rm -rf $DEPLOY_PATH/current && cp -a $LATEST $DEPLOY_PATH/current
  { docker rm -f $APP 2>/dev/null && docker run -d --name $APP --restart unless-stopped \
      -p 127.0.0.1:$APP_PORT:$APP_PORT $APP:previous; } \
    || systemctl restart $APP || pm2 restart $APP
"
```

---

## Tek-komut scriptler (opsiyonel)

Başarılı deploy sonrası **sor:** "Gelecekte tek komutla deploy/update için `deploy.sh` ve `update.sh` üreteyim mi?"

Üretirsen **jenerik şablon kullanma** — gerçek projeyi analiz et (package.json scripts / Dockerfile / Makefile / docker-compose / `.env.example`) ve tam build+start adımlarını çıkar. İki script:
- **`deploy.sh`** — ilk kurulum + deploy: config yükle · SSH doğrula · proxy + SSL · `releases/`'e yedek · projeye özel build · transfer · bağımlılık · start · retry'li sağlık kapısı · başarısızlıkta geri dönüş.
- **`update.sh`** — hızlı güncelleme: config · yedek · kod senkronu · (gerekirse) build/bağımlılık · restart · sağlık kapısı · başarısızlıkta geri dönüş.

Kurallar: `chmod +x`; `.deploy.yml` kimlik taşırsa `.gitignore` sor; mevcut scripti onaysız ezme (diff göster); kimlik sabitleme yok — hep `.deploy.yml`'den oku; projeye-özel her kararı yorumla açıkla.

---

## Değişmez kurallar
1. **Onaysız deploy yok** — yöntem/host/domain/port planını göster, onay bekle.
2. **Takastan önce hep yedek** — `releases/`'e zaman damgalı; yedek başarısızsa iptal.
3. **Takastan sonra hep sağlık kapısı** — HTTP + process; geçmezse otomatik geri dönüş.
4. **Son 3 sürümü tut** — hepsini silme.
5. **Hedefi bilmeden prod'a deploy etme** — host/deploy_path/domain onaylı olmalı.
6. **Önce SSH doğrula** — bağlanamıyorsan hızlı başarısız ol.
7. **Portu doğrudan açma** — uygulama `127.0.0.1`'e bağlanır, dışarı yalnız proxy'den.
8. **Domain varsa SSL zorunlu** — `ssl` açıkça `false` değilse hep kur.
