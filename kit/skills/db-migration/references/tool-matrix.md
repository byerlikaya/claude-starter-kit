# Tool × life-cycle commands

Find your tool's row and use it. A project has one migration tool; the other eight rows are noise at the
moment you are running a migration, which is why they are here rather than in `SKILL.md`.

The sequence itself — **Preview → (approval) → Apply → Verify** — and the rule that a destructive migration
never skips the approval gate live in `SKILL.md`. This file only says which command spells each step.

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

Invocation prefix: `npx …` for the Node tools, the project's Python environment for Alembic and Django,
`dotnet ef …` for EF Core.

## Where a preview does not exist

Sequelize, TypeORM and Rails have no true dry-run. **Treat the migration file itself as the preview** — read
it out and get it approved before applying. "The tool cannot preview" is not a reason to skip the gate; it is
a reason the preview is manual.

## Rollback is not a substitute for the backup

Every `Roll back` command above reverses *schema* intent. None of them restores data a destructive migration
already dropped. That is what the mandatory production backup is for — see `references/backup-restore.md`.
Drizzle's entry says "prefer backup" for exactly this reason, and the same caution applies to the others
whenever the migration touched data rather than only structure.
