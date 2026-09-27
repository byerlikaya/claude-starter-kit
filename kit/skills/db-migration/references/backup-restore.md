# Backup & restore — per engine

Take the backup **before** any migration (mandatory in prod; dev may skip with approval), then verify it is
non-empty or abort. Rollback order: the tool-specific rollback first (matrix, last column) → if it fails, restore
from this backup → re-verify. Read **only the section for your database**.

## PostgreSQL
```bash
# backup — compressed full dump
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME -F c -f backup_$(date +%Y%m%d_%H%M%S).dump
# restore (rollback)
pg_restore -h $DB_HOST -U $DB_USER -d $DB_NAME --clean --if-exists $BACKUP_FILE
# post-apply verify
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "\d $TABLE"
```

## MySQL
```bash
# backup
mysqldump -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME > backup_$(date +%Y%m%d_%H%M%S).sql
# restore (rollback)
mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME < $BACKUP_FILE
# post-apply verify
mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME -e "DESCRIBE $TABLE;"
```

## SQLite
```bash
# backup
sqlite3 $DB_PATH ".backup 'backup_$(date +%Y%m%d_%H%M%S).db'"
# restore (rollback)
cp $BACKUP_FILE $DB_PATH
```
