---
name: vps-deploy
description: |
  Uygulamaları VPS sunuculara dağıt: otomatik runtime tespiti, reverse proxy kurulumu,
  SSL ve rollback desteği.
  Trigger phrases: "deploy", "sunucuya gönder", "VPS'e kur", "sunucuya at", "production'a çık"
---

# VPS Deploy

Herhangi bir uygulamayı Docker veya bare-metal ile VPS'e dağıt: reverse proxy, SSL, health-check ve rollback dahil.

> **Kit uyarlaması (lokal, .claude/):** Varsayılan backend **.NET (Docker önerilir)**. **Deploy açık onay ister (§4.4)**;
> her deploy öncesi yedek + sonrası health-check zorunlu. `.deploy.yml` sunucu kimliği taşırsa `.gitignore`'a alınır.
> §4 Yasaklar geçerli.

## Genel bakış
Tam deploy yaşam döngüsü:
1. Projeyi analiz et — runtime tespit, deploy yöntemi seç
2. Deploy yapılandırmasını oku/oluştur
3. Reverse proxy kur (Nginx veya Caddy)
4. SSL sertifikası
5. Uygulamayı dağıt (Docker veya bare-metal)
6. Health-check ile doğrula
7. Sorun olursa rollback
8. Tek-komut gelecek deploy için `deploy.sh` ve `update.sh` üret

## Deploy öncesi kontrol listesi
- [ ] Proje analiz edildi — runtime ve yöntem belirlendi
- [ ] Config `.deploy.yml`'den okundu veya kullanıcıdan alındı
- [ ] SSH bağlantısı doğrulandı
- [ ] Mevcut sürüm `releases/`'e yedeklendi
- [ ] Reverse proxy yapılandırıldı
- [ ] SSL sertifikası yerinde
- [ ] Kullanıcı deploy'u onayladı
- [ ] Deploy scriptleri (`deploy.sh`, `update.sh`) kullanıcıya sunuldu

---

## Adım 1: Proje analizi
```bash
# Dockerfile var mı
if [ -f Dockerfile ] || [ -f docker-compose.yml ]; then
  METHOD="docker"
elif [ -f package.json ]; then
  METHOD="bare"; RUNTIME="node"
elif [ -f requirements.txt ] || [ -f pyproject.toml ] || [ -f Pipfile ]; then
  METHOD="bare"; RUNTIME="python"
elif [ -f go.mod ]; then
  METHOD="bare"; RUNTIME="go"
else
  METHOD="unknown"
fi
```
**Kurallar:** `method: auto` ise yukarıdaki mantık. `method: docker` → Dockerfile yoksa oluştur. `method: bare` → runtime'a uygun process manager. Runtime tespit edilemez ve auto ise kullanıcıya sor.

---

## Adım 2: Yapılandırma
Proje kökünden `.deploy.yml` oku; yoksa her değeri kullanıcıya sor.
```yaml
host: 192.168.1.100
user: deploy
ssh_key: ~/.ssh/id_rsa
app_port: 3000
health_check: /api/health
deploy_path: /var/www/myapp
method: auto  # auto | docker | bare
domain: myapp.example.com
ssl: true
reverse_proxy: auto  # auto | nginx | caddy
```
**Alanlar:** `host` VPS IP/hostname (zorunlu) · `user` SSH kullanıcı (zorunlu) · `ssh_key` özel anahtar (varsayılan `~/.ssh/id_rsa`) · `app_port` uygulama portu (zorunlu) · `health_check` HTTP yolu (varsayılan `/`) · `deploy_path` sunucu yolu (zorunlu) · `method` deploy yöntemi · `domain` proxy/SSL için (ops.) · `ssl` (domain varsa varsayılan `true`) · `reverse_proxy` auto/nginx/caddy.

**SSH doğrula:**
```bash
ssh -i $SSH_KEY -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new $USER@$HOST "echo 'SSH connection OK'"
```

---

## Adım 3: Reverse proxy
Sunucuda hangi proxy kurulu, tespit et; uygun config'i üret.
```bash
ssh -i $SSH_KEY $USER@$HOST "command -v caddy && echo 'CADDY' || (command -v nginx && echo 'NGINX' || echo 'NONE')"
```
**Kurallar:** `auto` → kuruluysa Caddy, değilse Nginx (yoksa Nginx kur). `nginx`/`caddy` → belirtileni kullan, yoksa kur.

### Nginx şablonu
```bash
ssh -i $SSH_KEY $USER@$HOST "cat > /etc/nginx/sites-available/$APP_NAME" << 'NGINX_CONF'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;
    location / {
        proxy_pass http://127.0.0.1:APP_PORT_PLACEHOLDER;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
NGINX_CONF
ssh -i $SSH_KEY $USER@$HOST "ln -sf /etc/nginx/sites-available/$APP_NAME /etc/nginx/sites-enabled/$APP_NAME"
ssh -i $SSH_KEY $USER@$HOST "nginx -t && systemctl reload nginx"
```
### Caddy şablonu
```bash
ssh -i $SSH_KEY $USER@$HOST "cat >> /etc/caddy/Caddyfile" << 'CADDY_CONF'
DOMAIN_PLACEHOLDER {
    reverse_proxy 127.0.0.1:APP_PORT_PLACEHOLDER
}
CADDY_CONF
ssh -i $SSH_KEY $USER@$HOST "systemctl reload caddy"
```
`DOMAIN_PLACEHOLDER` → `domain`, `APP_PORT_PLACEHOLDER` → `app_port`.

---

## Adım 4: SSL sertifikaları
### Caddy (otomatik)
Caddy SSL'i kendi yönetir; ekstra adım yok — Caddyfile'da domain tanımlıysa Let's Encrypt sertifikasını alır ve yeniler.

### Nginx (Certbot)
```bash
ssh -i $SSH_KEY $USER@$HOST "command -v certbot || (apt-get update && apt-get install -y certbot python3-certbot-nginx)"
ssh -i $SSH_KEY $USER@$HOST "certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN"
ssh -i $SSH_KEY $USER@$HOST "systemctl enable certbot.timer && systemctl start certbot.timer"
ssh -i $SSH_KEY $USER@$HOST "certbot renew --dry-run"
```
**Kurallar:** `ssl: false` veya domain yoksa atla. Çıplak IP için SSL yapma. Sertifikadan önce DNS'in sunucu IP'sine çözdüğünü doğrula:
```bash
RESOLVED_IP=$(dig +short $DOMAIN)
if [ "$RESOLVED_IP" != "$HOST" ]; then
  echo "UYARI: $DOMAIN -> $RESOLVED_IP (beklenen $HOST). SSL başarısız olur."
fi
```

---

## Adım 5: Deploy

### 5a. Mevcut sürümü yedekle
```bash
ssh -i $SSH_KEY $USER@$HOST "mkdir -p $DEPLOY_PATH/releases"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ssh -i $SSH_KEY $USER@$HOST "
  if [ -d $DEPLOY_PATH/current ]; then
    cp -a $DEPLOY_PATH/current $DEPLOY_PATH/releases/$TIMESTAMP
    echo 'Yedek: releases/$TIMESTAMP'
  else
    echo 'Yedeklenecek mevcut sürüm yok (ilk deploy)'
  fi
"
# Eski release'leri buda — son 3'ü tut
ssh -i $SSH_KEY $USER@$HOST "cd $DEPLOY_PATH/releases && ls -dt */ | tail -n +4 | xargs -r rm -rf"
```

### 5b. Docker deploy
```bash
docker build -t $APP_NAME:latest .
docker save $APP_NAME:latest | gzip > /tmp/$APP_NAME.tar.gz
scp -i $SSH_KEY /tmp/$APP_NAME.tar.gz $USER@$HOST:/tmp/
ssh -i $SSH_KEY $USER@$HOST "
  docker load < /tmp/$APP_NAME.tar.gz
  docker stop $APP_NAME 2>/dev/null || true
  docker rm $APP_NAME 2>/dev/null || true
  docker run -d --name $APP_NAME --restart unless-stopped \
    -p 127.0.0.1:$APP_PORT:$APP_PORT $APP_NAME:latest
  rm /tmp/$APP_NAME.tar.gz
"
rm /tmp/$APP_NAME.tar.gz
```

### 5c. Bare-metal — Node.js + PM2
```bash
rsync -avz --delete --exclude node_modules --exclude .git --exclude .env.local \
  -e "ssh -i $SSH_KEY" ./ $USER@$HOST:$DEPLOY_PATH/current/
ssh -i $SSH_KEY $USER@$HOST "
  cd $DEPLOY_PATH/current
  npm ci --production
  command -v pm2 || npm install -g pm2
  pm2 stop $APP_NAME 2>/dev/null || true
  pm2 delete $APP_NAME 2>/dev/null || true
  pm2 start ecosystem.config.js --name $APP_NAME 2>/dev/null || pm2 start npm --name $APP_NAME -- start
  pm2 save
  pm2 startup systemd -u $USER --hp /home/$USER 2>/dev/null || true
"
```

### 5d. Bare-metal — Python + systemd
```bash
rsync -avz --delete --exclude __pycache__ --exclude .git --exclude .venv --exclude .env.local \
  -e "ssh -i $SSH_KEY" ./ $USER@$HOST:$DEPLOY_PATH/current/
ssh -i $SSH_KEY $USER@$HOST "
  cd $DEPLOY_PATH/current
  python3 -m venv venv
  ./venv/bin/pip install -r requirements.txt 2>/dev/null || ./venv/bin/pip install -e . 2>/dev/null
  if [ -f manage.py ]; then
    EXEC_CMD='$DEPLOY_PATH/current/venv/bin/gunicorn --bind 127.0.0.1:$APP_PORT --workers 3 config.wsgi:application'
  elif [ -f app.py ] || [ -f main.py ]; then
    ENTRY=\$([ -f app.py ] && echo app.py || echo main.py)
    EXEC_CMD='$DEPLOY_PATH/current/venv/bin/python \$ENTRY'
  fi
  sudo tee /etc/systemd/system/$APP_NAME.service > /dev/null << SERVICE
[Unit]
Description=$APP_NAME
After=network.target
[Service]
Type=simple
User=$USER
WorkingDirectory=$DEPLOY_PATH/current
ExecStart=\$EXEC_CMD
Restart=always
RestartSec=5
Environment=PORT=$APP_PORT
[Install]
WantedBy=multi-user.target
SERVICE
  sudo systemctl daemon-reload
  sudo systemctl enable $APP_NAME
  sudo systemctl restart $APP_NAME
"
```

### 5e. Bare-metal — Go + systemd
```bash
GOOS=linux GOARCH=amd64 go build -o /tmp/$APP_NAME .
scp -i $SSH_KEY /tmp/$APP_NAME $USER@$HOST:$DEPLOY_PATH/current/$APP_NAME
ssh -i $SSH_KEY $USER@$HOST "
  chmod +x $DEPLOY_PATH/current/$APP_NAME
  sudo tee /etc/systemd/system/$APP_NAME.service > /dev/null << SERVICE
[Unit]
Description=$APP_NAME
After=network.target
[Service]
Type=simple
User=$USER
WorkingDirectory=$DEPLOY_PATH/current
ExecStart=$DEPLOY_PATH/current/$APP_NAME
Restart=always
RestartSec=5
Environment=PORT=$APP_PORT
[Install]
WantedBy=multi-user.target
SERVICE
  sudo systemctl daemon-reload
  sudo systemctl enable $APP_NAME
  sudo systemctl restart $APP_NAME
"
```

> **Not (.NET / varsayılan stack):** Docker önerilir (5b). Bare-metal gerekirse `dotnet publish -c Release`
> çıktısını rsync'le ve yukarıdaki systemd şablonunu `ExecStart=/usr/bin/dotnet $DEPLOY_PATH/current/App.dll` ile uyarla.

---

## Adım 6: Health-check
Deploy'dan hemen sonra; servis sağlıklı olana dek 30 sn'ye kadar bekle.
```bash
HEALTH_URL="http://127.0.0.1:$APP_PORT$HEALTH_CHECK"
MAX_RETRIES=6
RETRY_DELAY=5
ssh -i $SSH_KEY $USER@$HOST "
  for i in \$(seq 1 $MAX_RETRIES); do
    STATUS=\$(curl -s -o /dev/null -w '%{http_code}' $HEALTH_URL 2>/dev/null)
    if [ \"\$STATUS\" = '200' ]; then echo 'Health check GEÇTİ (HTTP 200)'; exit 0; fi
    echo \"Deneme \$i/$MAX_RETRIES: HTTP \$STATUS — ${RETRY_DELAY}s sonra tekrar...\"
    sleep $RETRY_DELAY
  done
  echo 'Health check BAŞARISIZ ($MAX_RETRIES deneme)'
  exit 1
"
```
**Process doğrulama:**
```bash
ssh -i $SSH_KEY $USER@$HOST "
  if [ '$METHOD' = 'docker' ]; then
    docker ps --filter name=$APP_NAME --format '{{.Status}}'
  else
    systemctl is-active $APP_NAME 2>/dev/null || pm2 show $APP_NAME 2>/dev/null | grep status
  fi
"
```
**Health-check başarısızsa otomatik rollback tetikle.**

---

## Adım 7: Rollback
`releases/`'teki en son yedeği geri yükle ve servisi yeniden başlat.
```bash
LATEST_RELEASE=$(ssh -i $SSH_KEY $USER@$HOST "ls -dt $DEPLOY_PATH/releases/*/ 2>/dev/null | head -1")
if [ -z "$LATEST_RELEASE" ]; then echo "HATA: Yedek yok. Rollback yapılamaz."; exit 1; fi
echo "Rollback: $LATEST_RELEASE"
ssh -i $SSH_KEY $USER@$HOST "
  rm -rf $DEPLOY_PATH/current
  cp -a $LATEST_RELEASE $DEPLOY_PATH/current
  if [ '$METHOD' = 'docker' ]; then
    docker stop $APP_NAME 2>/dev/null || true
    docker rm $APP_NAME 2>/dev/null || true
    docker run -d --name $APP_NAME --restart unless-stopped \
      -p 127.0.0.1:$APP_PORT:$APP_PORT $APP_NAME:previous
  else
    sudo systemctl restart $APP_NAME 2>/dev/null || pm2 restart $APP_NAME 2>/dev/null
  fi
  echo 'Rollback tamam.'
"
# Rollback sonrası health-check (Adım 6 tekrar)
```

---

## Adım 8: Deploy scriptleri üret
Başarılı deploy sonrası, **projeye özel** `deploy.sh` ve `update.sh` üret ki gelecekte tek komutla deploy/update yapılsın.

**Her zaman sor:** "Deploy başarılı. Gelecekte tek komutla deploy/update için `deploy.sh` ve `update.sh` scriptlerini oluşturmamı ister misiniz?"

### Neden projeye özel?
Jenerik script her durumu kapsayamaz. Her projenin farklı build adımı (npm build, go build, pip install, docker compose, Makefile), runtime config'i (env, .env), process manager'ı (PM2/systemd/Docker), bağımlılık kurulumu, dosya hariç-tutmaları ve pre/post hook'ları (migration, cache temizleme) vardır. **Jenerik şablon KULLANMA** — gerçek projeyi analiz et.

### Nasıl üretilir
1. Projeyi analiz et — package.json scripts, Dockerfile, Makefile, CI/CD, docker-compose.yml, .env.example
2. Bu projenin tam build/start komutlarını belirle
3. Projeye özel ihtiyaçları kontrol et: build adımı? migration? env? özel start? docker-compose? pre/post hook?
4. Bu projeye uyarlanmış iki script üret

### deploy.sh — ilk kurulum + deploy
Şunları içermeli (projeye uyarlanmış): `.deploy.yml` config yükleme · SSH doğrulama · reverse proxy kurulumu (Adım 3) · SSL (Adım 4) · `releases/`'e yedek · projeye özel build · transfer+deploy (Adım 1) · bağımlılık kurulumu · process start/restart · retry'li health-check · başarısızlıkta otomatik rollback · release budama (son 3).

### update.sh — hızlı kod güncelleme
Şunları içermeli: config yükleme · yedek · kod senkronu (rsync veya docker build+transfer) · gereğinde bağımlılık kurulumu · gereğinde build · process restart · retry'li health-check · başarısızlıkta otomatik rollback.

### Script iskelet şablonu
```bash
#!/usr/bin/env bash
set -euo pipefail
# ============================================
# [deploy.sh | update.sh] — [İlk kurulum | Hızlı güncelleme]
# Üretildiği proje: [proje-adı]
# Proje tipi: [Node.js/Python/Go/Docker/...]
# Deploy yöntemi: [docker | pm2 | systemd]
# ============================================
# --- Config (.deploy.yml'den) ---
# --- SSH doğrulama ---
# --- Mevcut sürüm yedeği ---
# --- [PROJE-ÖZEL: Build] ---
# --- [PROJE-ÖZEL: Transfer] ---
# --- [PROJE-ÖZEL: Bağımlılık kurulumu] ---
# --- [PROJE-ÖZEL: Migration (gerekirse)] ---
# --- [PROJE-ÖZEL: Start/restart] ---
# --- Health-check ---
# --- Başarısızlıkta rollback ---
```

### Script üretim kuralları
- Çalıştırma izni ver: `chmod +x deploy.sh update.sh`
- `.deploy.yml` sunucu kimliği taşıyabilir → `.gitignore`'a alınsın mı diye sor
- Mevcut scriptleri onaysız üzerine yazma; varsa diff göster ve sor
- Scriptler config'i `.deploy.yml`'den okur — sabit kimlik yok
- Her projeye-özel kararı yorumla açıkla (kullanıcı sonra değiştirebilsin)
- Scriptleri zihinsel test et — her komutu bu projeye göre izle

---

## Adım 9: Güvenlik kuralları
Zorunlu, asla atlanmaz:
1. **Onaysız deploy yok** — deploy planını (yöntem, host, domain, port) göster ve açık onay bekle.
2. **Deploy öncesi hep yedek** — `releases/`'e zaman damgalı; yedek başarısızsa iptal.
3. **Deploy sonrası hep health-check** — HTTP + process; başarısızsa otomatik rollback.
4. **Son 3 release'i tut** — başarılı deploy sonrası buda; hepsini silme.
5. **Hedefi bilmeden prod'a deploy etme** — host/deploy_path/domain'i onayla.
6. **Önce SSH doğrula** — bağlantı kurulamıyorsa hızlı başarısız ol.
7. **Portları doğrudan açma** — uygulama `127.0.0.1`'e bağlanır, yalnız proxy üzerinden erişilir.
8. **Domain varsa SSL zorunlu** — `domain` set ve `ssl` açıkça `false` değilse hep SSL kur.
