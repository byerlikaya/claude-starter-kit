# No tool — raw SQL mode

If no migration tool is detected, manage numbered up/down files; every `up` has a `down`, and every SQL runs
inside `BEGIN`/`COMMIT`.
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
