---
name: db-migration
description: |
  Apply schema migrations safely: auto-detect the tool, classify the change by risk class,
  gate destructive ones behind approval, force a backup in prod, preview-apply-verify and roll back when needed.
  Trigger phrases: "migration", "schema change", "update database", "add column", "create table", "alter table"
---

# Database Migration

A migration is very often a **one-way gate**: once applied, going back is expensive or impossible
unless it was planned for. That is why the heart of the flow is not running a command, but **classifying
the change by risk class before it passes through the gate** — let the safe one flow through, stop and
get approval for the destructive one, and keep a rollback path ready in every case. The skill works with
all common ORM/migration tools.

> **Kit adaptation (local, .claude/):** Default stack is **EF Core + PostgreSQL**. `database-expert-cck`
> applies it; **a destructive migration requires explicit approval (§4.5)**, commit/push with explicit approval (§4.4). Authorization/IDOR
> impact → **security-expert-cck**; personal-data retention → **privacy-agent-cck**. §4 Prohibitions apply.

## Checklist
- [ ] Tool detected, pending migrations listed
- [ ] Every change classified (additive / destructive / ambiguous)
- [ ] Destructive/ambiguous changes approved by the user
- [ ] Backup taken (mandatory in prod, verified)
- [ ] Preview (dry-run) shown and approved
- [ ] Applied, schema verified post-apply
- [ ] Rollback path (tool or backup) ready

---

## 1. Detect the tool

Determine the tool from the file trace; if none is found, fall back to **raw SQL mode** (below); if several are found, ask the user.

| Trace | Tool |
|---|---|
| `prisma/schema.prisma` | Prisma |
| `knexfile.{js,ts}` | Knex |
| `.sequelizerc` / `config/config.json` + `models/` | Sequelize |
| `data-source.ts` (typeorm) / `ormconfig.ts` | TypeORM |
| `drizzle.config.ts` | Drizzle |
| `alembic.ini` / `alembic/` | Alembic |
| `manage.py` + `django` dependency | Django |
| `db/migrate/` + `rails` in Gemfile | Rails |
| `Microsoft.EntityFrameworkCore` in `*.csproj` + `Migrations/` | EF Core |

---

## 2. Classify the change — the heart of the flow

Extract the SQL to be applied (the "Preview" column in the matrix below) and place it into one of three classes:

| Class | Example operations | How it is handled |
|---|---|---|
| **Additive** (safe) | `CREATE TABLE`, nullable/defaulted `ADD COLUMN`, `CREATE INDEX`, non-destructive `ADD CONSTRAINT`, seed `INSERT` | Proceed in the normal flow |
| **Destructive** (dangerous) | `DROP TABLE/COLUMN/INDEX/CONSTRAINT`, `ALTER COLUMN … TYPE`, `TRUNCATE`, `DELETE` without WHERE, `RENAME` (breaks references) | **Always the approval gate** (below) |
| **Ambiguous** (human judgment) | `ALTER COLUMN`, `ADD COLUMN NOT NULL` without a default (blows up on a populated table), `UPDATE`, mixed migration | **Treat as destructive**, warn and ask |

**Approval gate (destructive/ambiguous):** list the operations one by one, show the environment and the target, wait for explicit approval. Even if "run" was said in the general flow, this gate requires separate approval.
```
WARNING — this migration contains a destructive operation:
  · DROP COLUMN "legacy_email" (table: users)
  · ALTER COLUMN "status" TYPE integer (table: orders)
CANNOT BE UNDONE without a backup.  Target: production (myapp_db @ db.example.com)
Continue? (yes / no)
```
If rejected, stop immediately and propose a safer path (e.g. a new column + background copy instead of changing the type).

---

## 3. Backup (mandatory in prod)

Back up before any migration; it cannot be skipped in prod, and can be skipped in dev with approval.
```bash
# PostgreSQL — compressed full backup
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME -F c -f backup_$(date +%Y%m%d_%H%M%S).dump
# MySQL
mysqldump -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME > backup_$(date +%Y%m%d_%H%M%S).sql
# SQLite
sqlite3 $DB_PATH ".backup 'backup_$(date +%Y%m%d_%H%M%S).db'"
```
Before proceeding, verify **that the backup was created and is not empty** — otherwise abort:
```bash
[ -s "$BACKUP_FILE" ] || { echo "ERROR: Backup empty/not created — migration aborted."; exit 1; }
```

---

## 4. Tool × life-cycle matrix

Once classification and backup are complete: **Preview → (approval) → Apply → Verify**. A single reference:

| Tool | Status | Preview (dry-run) | Apply | Verify | Roll back |
|---|---|---|---|---|---|
| Prisma | `migrate status` | `migrate diff … --script` | `migrate deploy` | `migrate status` | `migrate resolve --rolled-back` + backup |
| Knex | `migrate:status` | `migrate:latest --dry-run` | `migrate:latest` | `migrate:status` | `migrate:rollback` |
| Sequelize | `db:migrate:status` | read the migration file | `db:migrate` | `db:migrate:status` | `db:migrate:undo` |
| TypeORM | `migration:show` | read the pending file | `migration:run` | `migration:show` | `migration:revert` |
| Drizzle | `drizzle-kit status` | `generate` → inspect SQL | `drizzle-kit push` | `drizzle-kit status` | `drizzle-kit drop` (prefer backup) |
| Alembic | `current` + `history` | `upgrade head --sql` | `upgrade head` | `current` (=head) | `downgrade -1` |
| Django | `showmigrations` | `sqlmigrate <app> <name>` | `migrate` | `showmigrations` ([X]) | `migrate <app> <previous>` |
| Rails | `db:migrate:status` | read the migration file | `db:migrate` | `db:migrate:status` (up) | `db:rollback STEP=1` |
| EF Core | `migrations list` | `migrations script` | `database update` | `migrations list` | `database update <previous>` |

*(For Node tools prefix `npx …`, for Python the appropriate shell, for .NET `dotnet ef …`.)*

**Rules:** **Always** show the preview before applying and get it approved (if the tool does not support it, treat the file as the preview). A destructive migration is not applied without passing the approval gate (§2). Show the full apply output; if there is an error, roll back.

**Additional post-apply verification** — compare against the expected schema:
```bash
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "\d $TABLE"      # PostgreSQL
mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME -e "DESCRIBE $TABLE;"   # MySQL
```

---

## 5. Rollback

First the tool-specific rollback (last column of the matrix); if that fails, restore from the backup; then re-verify. If neither works, warn the user with the full error detail.
```bash
# PostgreSQL — from backup
pg_restore -h $DB_HOST -U $DB_USER -d $DB_NAME --clean --if-exists $BACKUP_FILE
# MySQL
mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME < $BACKUP_FILE
# SQLite
cp $BACKUP_FILE $DB_PATH
```

---

## No tool — raw SQL mode

If no tool is detected, manage numbered up/down files; every `up` has a `down`, and every SQL runs inside `BEGIN`/`COMMIT`.
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
Keep the applied ones in a tracking table; run only those with no record:
```bash
psql … -c "CREATE TABLE IF NOT EXISTS _migrations(id SERIAL PRIMARY KEY, name TEXT UNIQUE, applied_at TIMESTAMP DEFAULT NOW())"
for f in migrations/*.up.sql; do
  n=$(basename "$f" .up.sql)
  [ "$(psql … -tAc "SELECT count(*) FROM _migrations WHERE name='$n'")" = 0 ] || continue
  psql … -f "$f" && psql … -c "INSERT INTO _migrations(name) VALUES('$n')"
done
```

---

## Invariant rules
1. **Classify first** — additive/destructive/ambiguous; treat the ambiguous as destructive.
2. **Destructive = human approval** — a separate gate even in an automated flow.
3. **Prod backup mandatory** — no apply without a verified backup.
4. **Preview on by default** — opting out requires an explicit request.
5. **Always verify after applying.**
6. **Rollback path always ready** — tool or backup.
7. **Show the target** — DB name/host/environment, before applying.
