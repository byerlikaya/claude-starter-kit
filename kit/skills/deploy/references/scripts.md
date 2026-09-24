# Single-command scripts (optional)

After a successful deploy, **ask:** "Shall I generate `deploy.sh` and `adopt.sh` so you can deploy/update with a single command in the future?"

If you generate them, **don't use a generic template** — analyze the actual project (package.json scripts / Dockerfile / Makefile / docker-compose / `.env.example`) and derive the exact build+start steps. Two scripts:
- **`deploy.sh`** — first-time setup + deploy: load config · verify SSH · proxy + SSL · back up to `releases/` · project-specific build · transfer · dependencies · start · health gate with retries · rollback on failure.
- **`adopt.sh`** — quick update: config · backup · code sync · (if needed) build/dependencies · restart · health gate · rollback on failure.

Rules: `chmod +x`; if `.deploy.yml` carries credentials, ask about `.gitignore`; don't overwrite an existing script without approval (show a diff); no hardcoded credentials — always read from `.deploy.yml`; comment and explain every project-specific decision.
