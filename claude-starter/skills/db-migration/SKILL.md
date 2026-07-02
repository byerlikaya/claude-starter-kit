---
name: db-migration
description: |
  Veritabanı migration'larını güvenle çalıştır: otomatik araç tespiti, dry-run önizleme,
  yıkıcı değişiklik uyarısı, yedek ve rollback desteği.
  Trigger phrases: "migration", "şema değişikliği", "veritabanı güncelle", "kolon ekle", "tablo oluştur", "alter table"
---

# Veritabanı Migration

Herhangi bir ORM/migration aracıyla migration'ı güvenle çalıştır: otomatik tespit, dry-run önizleme, yıkıcı değişiklik koruması, zorunlu prod yedeği ve rollback.

> **Kit uyarlaması (lokal, .claude/):** Varsayılan stack **EF Core + PostgreSQL** (algılama/komut tablolarına eklendi).
> `database-expert` uygular; **yıkıcı/destrüktif migration açık onay ister (§4.5)**, commit/push açık onayla (§4.4).
> IDOR/yetki etkisi → **security-expert**; kişisel veri retention → **privacy-agent**. §4 Yasaklar geçerli.

## Genel bakış
Tam migration yaşam döngüsü:
1. Proje dosyalarından migration aracını tespit et
2. Migration durumunu kontrol et
3. Değişikliği analiz et (additive / destructive / belirsiz)
4. Güvenlik kapısı — yıkıcı değişiklikte onay iste
5. Veritabanını yedekle (prod'da zorunlu)
6. Dry-run (varsayılan AÇIK)
7. Migration'ı uygula
8. Şema durumunu doğrula
9. Sorun olursa rollback
10. ORM yoksa ham SQL desteği

## Migration öncesi kontrol listesi
- [ ] Migration aracı tespit edildi
- [ ] Durum kontrol edildi — bekleyen migration'lar belirlendi
- [ ] Değişiklik sınıflandırıldı (additive / destructive / belirsiz)
- [ ] Yıkıcı değişiklikler kullanıcıca onaylandı (varsa)
- [ ] Veritabanı yedeklendi (prod'da zorunlu)
- [ ] Dry-run tamamlandı ve incelendi
- [ ] Kullanıcı uygulamayı onayladı
- [ ] Migration uygulandı
- [ ] Şema uygulama sonrası doğrulandı
- [ ] Rollback planı hazır

---

## Adım 1: Migration aracını tespit et

**Tespit tablosu:**
| Dosya / Kalıp | Araç |
|---|---|
| `prisma/schema.prisma` | Prisma |
| `knexfile.js` / `knexfile.ts` | Knex |
| `.sequelizerc` veya `config/config.json` + `models/` | Sequelize |
| `ormconfig.ts` veya `data-source.ts` (typeorm import) | TypeORM |
| `drizzle.config.ts` | Drizzle |
| `alembic.ini` veya `alembic/` | Alembic |
| `manage.py` + requirements'ta `django` | Django |
| `Gemfile`'da `rails` + `db/migrate/` | Rails ActiveRecord |
| `*.csproj`'ta `Microsoft.EntityFrameworkCore` + `Migrations/` | EF Core (.NET) |

**Tespit mantığı:**
```bash
[ -f prisma/schema.prisma ] && TOOL="prisma"
([ -f knexfile.js ] || [ -f knexfile.ts ]) && TOOL="knex"
([ -f .sequelizerc ] || ([ -f config/config.json ] && [ -d models ])) && TOOL="sequelize"
([ -f ormconfig.ts ] || ([ -f data-source.ts ] && grep -q "typeorm" data-source.ts)) && TOOL="typeorm"
[ -f drizzle.config.ts ] && TOOL="drizzle"
([ -f alembic.ini ] || [ -d alembic ]) && TOOL="alembic"
([ -f manage.py ] && grep -qi "django" requirements*.txt Pipfile pyproject.toml 2>/dev/null) && TOOL="django"
([ -d db/migrate ] && grep -q "rails" Gemfile 2>/dev/null) && TOOL="rails"
(ls *.csproj >/dev/null 2>&1 && grep -rq "Microsoft.EntityFrameworkCore" ./*.csproj 2>/dev/null) && TOOL="efcore"
```
**Kurallar:** Araç bulunamazsa ham SQL moduna düş (Adım 10). Birden çok tespit edilirse kullanıcıya sor.

---

## Adım 2: Migration durumunu kontrol et
| Araç | Durum komutu |
|---|---|
| Prisma | `npx prisma migrate status` |
| Knex | `npx knex migrate:status` |
| Sequelize | `npx sequelize-cli db:migrate:status` |
| TypeORM | `npx typeorm migration:show` |
| Drizzle | `npx drizzle-kit status` |
| Alembic | `alembic current` + `alembic history` |
| Django | `python manage.py showmigrations` |
| Rails | `bin/rails db:migrate:status` |
| EF Core | `dotnet ef migrations list` |

**Kurallar:** Devam etmeden bekleyen migration'ları göster. Bekleyen yoksa bilgilendir ve yeni migration oluşturulmuyorsa dur.

---

## Adım 3: Değişikliği analiz et
**additive**, **destructive** veya **belirsiz** olarak sınıflandır.

**Additive (güvenli):** `CREATE TABLE`, `ADD COLUMN` (nullable/default'lu), `CREATE INDEX`, `ADD CONSTRAINT` (yıkıcı olmayan), seed `INSERT`.

**Destructive (tehlikeli — her zaman onay):** `DROP TABLE`, `DROP COLUMN`, `ALTER TYPE`/`ALTER COLUMN ... TYPE`, `DROP INDEX`, `DROP CONSTRAINT`, `TRUNCATE`, WHERE'siz `DELETE`, `RENAME TABLE`/`RENAME COLUMN` (referansları kırar).

**Belirsiz (insan yargısı):** `ALTER TABLE ... ALTER COLUMN`, default'suz `ADD COLUMN ... NOT NULL` (dolu tabloda hata), `UPDATE`, additive+destructive karışık migration.

**Nasıl sınıflandırılır:**
- Prisma: `prisma migrate diff --preview`
- Knex/Sequelize/TypeORM: migration dosyasını oku
- Alembic: `upgrade()` fonksiyonunu oku
- Django: `python manage.py sqlmigrate <app> <ad>`
- Rails: `change`/`up` metodunu oku
- Drizzle: `npx drizzle-kit generate` → SQL çıktısını incele
- EF Core: migration'ın `Up()`/`Down()`'unu oku, veya `dotnet ef migrations script`

---

## Adım 4: Güvenlik kapısı
**Yıkıcı değişiklikler için zorunlu kurallar:**
1. Kullanıcıyı açıkça **uyar** — her yıkıcı işlemi listele.
2. **Onay iste** — açık onay olmadan ilerleme.
3. **Otomatik uygulama yok** — genel akış için "çalıştır" denmiş olsa bile yıkıcı değişiklikler tek tek onaylanır.

**Uyarı formatı:**
```
UYARI: Bu migration yıkıcı değişiklik içeriyor:
  - DROP TABLE "users_backup"
  - DROP COLUMN "legacy_email" (tablo "users")
  - ALTER TYPE, kolon "status" (tablo "orders"): varchar -> integer
Bu değişiklikler yedek olmadan GERİ ALINAMAZ.
Veritabanı: production (myapp_db @ db.example.com)
Devam edilsin mi? (evet/hayır)
```
**Kurallar:** Hedef prod ise uyarıya DB adı+host'u ekle. Reddedilirse hemen dur ve alternatif öner (ör. tip değiştirmek yerine yeni kolon).

---

## Adım 5: Yedek
Herhangi bir migration'dan önce yedekle. **Prod'da zorunlu.**

### PostgreSQL
```bash
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME -F c -f backup_$(date +%Y%m%d_%H%M%S).dump
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME --schema-only -f schema_backup_$(date +%Y%m%d_%H%M%S).sql
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME -t $TABLE_NAME -F c -f table_backup_$(date +%Y%m%d_%H%M%S).dump
```
### MySQL
```bash
mysqldump -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME > backup_$(date +%Y%m%d_%H%M%S).sql
mysqldump -h $DB_HOST -u $DB_USER -p$DB_PASS --no-data $DB_NAME > schema_backup_$(date +%Y%m%d_%H%M%S).sql
```
### SQLite
```bash
cp $DB_PATH backup_$(date +%Y%m%d_%H%M%S).db
sqlite3 $DB_PATH ".backup 'backup_$(date +%Y%m%d_%H%M%S).db'"
```
**Kurallar:** Prod'da yedek zorunlu, atlanmaz. Dev'de önerilir (onayla atlanabilir). İlerlemeden önce yedeğin oluştuğunu ve boş olmadığını doğrula:
```bash
BACKUP_FILE="backup_$(date +%Y%m%d_%H%M%S).dump"
if [ ! -s "$BACKUP_FILE" ]; then echo "HATA: Yedek boş/oluşmadı. Migration iptal."; exit 1; fi
echo "Yedek: $BACKUP_FILE ($(du -h $BACKUP_FILE | cut -f1))"
```

---

## Adım 6: Dry-run (varsayılan AÇIK)
| Araç | Dry-run / önizleme |
|---|---|
| Prisma | `npx prisma migrate diff --from-schema-datamodel prisma/schema.prisma --to-schema-datasource prisma/schema.prisma --script` |
| Knex | `npx knex migrate:latest --dry-run` (veya dosyayı oku) |
| Sequelize | Migration dosyasındaki `up` mantığını göster |
| TypeORM | Bekleyen migration dosyasını oku |
| Drizzle | `npx drizzle-kit generate --custom` → SQL incele |
| Alembic | `alembic upgrade head --sql` |
| Django | `python manage.py sqlmigrate <app> <ad>` |
| Rails | Bekleyen migration dosyasını oku |
| EF Core | `dotnet ef migrations script` |

**Kurallar:** Uygulamadan önce dry-run çıktısını göster. Araç desteklemiyorsa dosyayı önizleme olarak göster. Kullanıcı inceledikten sonra onaylamalı. Atlamak için açık talep gerek.
```
DRY-RUN ÖNİZLEME:
Migration: 20240115_add_user_email_verified  ·  Araç: Prisma
SQL:
  ALTER TABLE "users" ADD COLUMN "email_verified" BOOLEAN NOT NULL DEFAULT false;
  CREATE INDEX "idx_users_email_verified" ON "users" ("email_verified");
Sınıf: ADDITIVE (güvenli)
Uygula? (evet/hayır)
```

---

## Adım 7: Migration'ı uygula
| Araç | Uygula |
|---|---|
| Prisma | `npx prisma migrate deploy` |
| Knex | `npx knex migrate:latest` |
| Sequelize | `npx sequelize-cli db:migrate` |
| TypeORM | `npx typeorm migration:run` |
| Drizzle | `npx drizzle-kit push` |
| Alembic | `alembic upgrade head` |
| Django | `python manage.py migrate` |
| Rails | `bin/rails db:migrate` |
| EF Core | `dotnet ef database update` |

**Yeni migration üretme:**
| Araç | Üret |
|---|---|
| Prisma | `npx prisma migrate dev --name <ad>` |
| Knex | `npx knex migrate:make <ad>` |
| Sequelize | `npx sequelize-cli migration:generate --name <ad>` |
| TypeORM | `npx typeorm migration:generate -n <ad>` |
| Drizzle | `npx drizzle-kit generate` |
| Alembic | `alembic revision --autogenerate -m "<ad>"` |
| Django | `python manage.py makemigrations` |
| Rails | `bin/rails generate migration <ad>` |
| EF Core | `dotnet ef migrations add <ad>` |

**Kurallar:** Dry-run tamamlanmadan uygulama (açıkça atlanmadıkça). Yıkıcı migration'ı güvenlik kapısı (Adım 4) geçmeden uygulama. Çıktının tamamını göster. Hata olursa rollback öner.

---

## Adım 8: Doğrula
| Araç | Doğrula |
|---|---|
| Prisma | `npx prisma migrate status` (bekleyen olmamalı) |
| Knex | `npx knex migrate:status` |
| Sequelize | `npx sequelize-cli db:migrate:status` |
| TypeORM | `npx typeorm migration:show` |
| Drizzle | `npx drizzle-kit status` |
| Alembic | `alembic current` (head'e eşit) |
| Django | `python manage.py showmigrations` (hepsi `[X]`) |
| Rails | `bin/rails db:migrate:status` (hepsi `up`) |
| EF Core | `dotnet ef migrations list` (bekleyen yok) |

**Ek doğrulama:**
```bash
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "\d $TABLE_NAME"     # PostgreSQL
mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME -e "DESCRIBE $TABLE_NAME;"   # MySQL
sqlite3 $DB_PATH ".schema $TABLE_NAME"                          # SQLite
```
Uygulamadan sonra hep doğrula; beklenen şemayla karşılaştır; başarısızsa uyar ve rollback öner.

---

## Adım 9: Rollback
| Araç | Rollback |
|---|---|
| Prisma | `npx prisma migrate resolve --rolled-back <ad>` + yedekten geri yükle |
| Knex | `npx knex migrate:rollback` |
| Sequelize | `npx sequelize-cli db:migrate:undo` |
| TypeORM | `npx typeorm migration:revert` |
| Drizzle | `npx drizzle-kit drop` (sınırlı — yedek tercih et) |
| Alembic | `alembic downgrade -1` |
| Django | `python manage.py migrate <app> <önceki_migration>` |
| Rails | `bin/rails db:rollback STEP=1` |
| EF Core | `dotnet ef database update <ÖncekiMigration>` |

**Yedekten geri yükleme (fallback):**
```bash
# PostgreSQL
pg_restore -h $DB_HOST -U $DB_USER -d $DB_NAME --clean --if-exists $BACKUP_FILE
psql -h $DB_HOST -U $DB_USER -d $DB_NAME < $BACKUP_FILE
# MySQL
mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME < $BACKUP_FILE
# SQLite
cp $BACKUP_FILE $DB_PATH
```
**Kurallar:** Önce araca-özel rollback; başarısızsa yedekten geri yükle; sonra doğrula (Adım 8). İkisi de olmazsa kullanıcıyı tam hata detayıyla uyar.

---

## Adım 10: Ham SQL desteği
ORM/araç tespit edilmezse numaralı up/down SQL dosyalarını destekle:
```
migrations/
  001_create_users.up.sql
  001_create_users.down.sql
  002_add_email_verified.up.sql
  002_add_email_verified.down.sql
```
**Up şablonu:**
```sql
-- migrations/001_create_users.up.sql
BEGIN;
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_users_email ON users (email);
COMMIT;
```
**Down şablonu:**
```sql
-- migrations/001_create_users.down.sql
BEGIN;
DROP INDEX IF EXISTS idx_users_email;
DROP TABLE IF EXISTS users;
COMMIT;
```
**Takip tablosu:**
```sql
CREATE TABLE IF NOT EXISTS _migrations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    applied_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```
**Uygula (PostgreSQL):**
```bash
for f in migrations/*.up.sql; do
  NAME=$(basename "$f" .up.sql)
  APPLIED=$(psql -h $DB_HOST -U $DB_USER -d $DB_NAME -tAc "SELECT COUNT(*) FROM _migrations WHERE name = '$NAME'")
  if [ "$APPLIED" = "0" ]; then
    psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f "$f"
    psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "INSERT INTO _migrations (name) VALUES ('$NAME')"
  fi
done
```
**Kurallar:** Her up'ın down'ı olmalı; SQL'ler `BEGIN`/`COMMIT` içinde; sıralı numaralı adlar; `_migrations` tablosu yoksa otomatik oluşturulur.

---

## Güvenlik kuralları özeti
Zorunlu, asla atlanmaz:
1. **Dry-run varsayılan AÇIK** — açıkça opt-out gerekir.
2. **Yıkıcı değişiklik onay ister** — DROP/ALTER TYPE/TRUNCATE/RENAME.
3. **Prod yedeği zorunlu** — doğrulanmış yedek olmadan uygulama.
4. **Otomatik akışta bile yıkıcı = insan onayı.**
5. **Uygulamadan sonra hep doğrula.**
6. **Rollback planı hazır olmalı** (araç veya yedek).
7. **Belirsiz değişikliği yıkıcı gibi ele al**, uyar.
8. **Hedefi göster** — DB adı/host/ortam uygulamadan önce.
