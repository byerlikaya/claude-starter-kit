---
name: db-migration
description: |
  Şema migration'larını güvenle uygula: aracı otomatik tespit et, değişikliği risk sınıfına ayır,
  yıkıcı olanı onay kapısına al, prod'da yedek zorla, önizle-uygula-doğrula ve gerektiğinde geri dön.
  Trigger phrases: "migration", "şema değişikliği", "veritabanı güncelle", "kolon ekle", "tablo oluştur", "alter table"
---

# Veritabanı Migration

Bir migration çoğu zaman **tek yönlü bir kapıdır**: uygulandıktan sonra geri dönmek, planlanmadıysa
pahalı ya da imkânsızdır. Bu yüzden akışın kalbi komut çalıştırmak değil, **değişikliği kapıdan
geçmeden önce risk sınıfına ayırmak** — güvenli olanı akıcı geçir, yıkıcı olanı durdur ve onaylat,
her ihtimalde geri dönüş yolunu hazır tut. Skill tüm yaygın ORM/migration araçlarıyla çalışır.

> **Kit uyarlaması (lokal, .claude/):** Varsayılan stack **EF Core + PostgreSQL**. `database-expert-cck`
> uygular; **yıkıcı migration açık onay ister (§4.5)**, commit/push açık onayla (§4.4). Yetki/IDOR
> etkisi → **security-expert-cck**; kişisel veri saklama → **privacy-agent-cck**. §4 Yasaklar geçerlidir.

## Kontrol listesi
- [ ] Araç tespit edildi, bekleyen migration'lar listelendi
- [ ] Her değişiklik sınıflandırıldı (additive / destructive / belirsiz)
- [ ] Yıkıcı/belirsiz değişiklikler kullanıcıca onaylandı
- [ ] Yedek alındı (prod'da zorunlu, doğrulandı)
- [ ] Önizleme (dry-run) gösterildi ve onaylandı
- [ ] Uygulandı, şema uygulama-sonrası doğrulandı
- [ ] Geri dönüş yolu (araç veya yedek) hazır

---

## 1. Aracı tespit et

Dosya izinden aracı belirle; bulunamazsa **ham SQL moduna** düş (aşağı), birden çok bulunursa kullanıcıya sor.

| İz | Araç |
|---|---|
| `prisma/schema.prisma` | Prisma |
| `knexfile.{js,ts}` | Knex |
| `.sequelizerc` / `config/config.json` + `models/` | Sequelize |
| `data-source.ts` (typeorm) / `ormconfig.ts` | TypeORM |
| `drizzle.config.ts` | Drizzle |
| `alembic.ini` / `alembic/` | Alembic |
| `manage.py` + `django` bağımlılığı | Django |
| `db/migrate/` + Gemfile'da `rails` | Rails |
| `*.csproj`'ta `Microsoft.EntityFrameworkCore` + `Migrations/` | EF Core |

---

## 2. Değişikliği sınıflandır — akışın kalbi

Uygulanacak SQL'i çıkar (aşağıdaki matriste "Önizle" sütunu) ve üç sınıftan birine koy:

| Sınıf | Örnek işlemler | Nasıl ele alınır |
|---|---|---|
| **Additive** (güvenli) | `CREATE TABLE`, nullable/default'lu `ADD COLUMN`, `CREATE INDEX`, yıkıcı-olmayan `ADD CONSTRAINT`, seed `INSERT` | Normal akışta ilerle |
| **Destructive** (tehlikeli) | `DROP TABLE/COLUMN/INDEX/CONSTRAINT`, `ALTER COLUMN … TYPE`, `TRUNCATE`, WHERE'siz `DELETE`, `RENAME` (referans kırar) | **Her zaman onay kapısı** (aşağı) |
| **Belirsiz** (insan yargısı) | `ALTER COLUMN`, default'suz `ADD COLUMN NOT NULL` (dolu tabloda patlar), `UPDATE`, karışık migration | **Yıkıcı gibi ele al**, uyar ve sor |

**Onay kapısı (yıkıcı/belirsiz):** işlemleri tek tek listele, ortamı ve hedefi göster, açık onay bekle. Genel akışta "çalıştır" denmiş olsa bile bu kapı ayrı onay ister.
```
UYARI — bu migration yıkıcı işlem içeriyor:
  · DROP COLUMN "legacy_email" (tablo: users)
  · ALTER COLUMN "status" TYPE integer (tablo: orders)
Yedek olmadan GERİ ALINAMAZ.  Hedef: production (myapp_db @ db.example.com)
Devam? (evet / hayır)
```
Reddedilirse hemen dur ve daha güvenli bir yol öner (ör. tip değiştirmek yerine yeni kolon + arka planda kopyalama).

---

## 3. Yedek (prod'da zorunlu)

Herhangi bir migration'dan önce yedekle; prod'da atlanamaz, dev'de onayla atlanabilir.
```bash
# PostgreSQL — sıkıştırılmış tam yedek
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME -F c -f backup_$(date +%Y%m%d_%H%M%S).dump
# MySQL
mysqldump -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME > backup_$(date +%Y%m%d_%H%M%S).sql
# SQLite
sqlite3 $DB_PATH ".backup 'backup_$(date +%Y%m%d_%H%M%S).db'"
```
İlerlemeden **yedeğin oluştuğunu ve boş olmadığını** doğrula — aksi halde iptal:
```bash
[ -s "$BACKUP_FILE" ] || { echo "HATA: Yedek boş/oluşmadı — migration iptal."; exit 1; }
```

---

## 4. Araç × yaşam-döngüsü matrisi

Sınıflandırma ve yedek tamamsa: **Önizle → (onay) → Uygula → Doğrula**. Tek referans:

| Araç | Durum | Önizle (dry-run) | Uygula | Doğrula | Geri al |
|---|---|---|---|---|---|
| Prisma | `migrate status` | `migrate diff … --script` | `migrate deploy` | `migrate status` | `migrate resolve --rolled-back` + yedek |
| Knex | `migrate:status` | `migrate:latest --dry-run` | `migrate:latest` | `migrate:status` | `migrate:rollback` |
| Sequelize | `db:migrate:status` | migration dosyasını oku | `db:migrate` | `db:migrate:status` | `db:migrate:undo` |
| TypeORM | `migration:show` | bekleyen dosyayı oku | `migration:run` | `migration:show` | `migration:revert` |
| Drizzle | `drizzle-kit status` | `generate` → SQL incele | `drizzle-kit push` | `drizzle-kit status` | `drizzle-kit drop` (yedek tercih et) |
| Alembic | `current` + `history` | `upgrade head --sql` | `upgrade head` | `current` (=head) | `downgrade -1` |
| Django | `showmigrations` | `sqlmigrate <app> <ad>` | `migrate` | `showmigrations` ([X]) | `migrate <app> <önceki>` |
| Rails | `db:migrate:status` | migration dosyasını oku | `db:migrate` | `db:migrate:status` (up) | `db:rollback STEP=1` |
| EF Core | `migrations list` | `migrations script` | `database update` | `migrations list` | `database update <önceki>` |

*(Node araçlarında `npx …`, Python'da uygun kabuk, .NET'te `dotnet ef …` öneki.)*

**Kurallar:** Önizlemeyi **her zaman** uygulamadan önce göster ve onaylat (araç desteklemiyorsa dosyayı önizleme say). Yıkıcı migration onay kapısını (§2) geçmeden uygulanmaz. Uygulama çıktısının tamamını göster; hata olursa geri dön.

**Uygulama-sonrası ek doğrulama** — beklenen şemayla karşılaştır:
```bash
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "\d $TABLE"      # PostgreSQL
mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME -e "DESCRIBE $TABLE;"   # MySQL
```

---

## 5. Geri dönüş

Önce araca-özel geri alma (matris son sütun); başarısızsa yedekten yükle; ardından yeniden doğrula. İkisi de olmazsa kullanıcıyı tam hata detayıyla uyar.
```bash
# PostgreSQL — yedekten
pg_restore -h $DB_HOST -U $DB_USER -d $DB_NAME --clean --if-exists $BACKUP_FILE
# MySQL
mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME < $BACKUP_FILE
# SQLite
cp $BACKUP_FILE $DB_PATH
```

---

## Araçsız — ham SQL modu

Hiçbir araç tespit edilmezse numaralı up/down dosyalarını yönet; her `up`'ın bir `down`'ı olur, her SQL `BEGIN`/`COMMIT` içinde çalışır.
```
migrations/001_create_users.up.sql   +   001_create_users.down.sql
```
```sql
-- 001_create_users.up.sql
BEGIN;
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
COMMIT;
-- 001_create_users.down.sql
BEGIN;
DROP TABLE IF EXISTS users;
COMMIT;
```
Uygulanmışları bir izleme tablosunda tut; yalnız kaydı olmayanları çalıştır:
```bash
psql … -c "CREATE TABLE IF NOT EXISTS _migrations(id SERIAL PRIMARY KEY, name TEXT UNIQUE, applied_at TIMESTAMP DEFAULT NOW())"
for f in migrations/*.up.sql; do
  n=$(basename "$f" .up.sql)
  [ "$(psql … -tAc "SELECT count(*) FROM _migrations WHERE name='$n'")" = 0 ] || continue
  psql … -f "$f" && psql … -c "INSERT INTO _migrations(name) VALUES('$n')"
done
```

---

## Değişmez kurallar
1. **Önce sınıflandır** — additive/destructive/belirsiz; belirsizi yıkıcı say.
2. **Yıkıcı = insan onayı** — otomatik akışta bile ayrı kapı.
3. **Prod yedeği zorunlu** — doğrulanmış yedek olmadan uygulama.
4. **Önizleme varsayılan açık** — opt-out açık talep ister.
5. **Uygulamadan sonra hep doğrula.**
6. **Geri dönüş yolu her zaman hazır** — araç veya yedek.
7. **Hedefi göster** — DB adı/host/ortam, uygulamadan önce.
