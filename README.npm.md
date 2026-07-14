<div align="center">

<img src="https://raw.githubusercontent.com/byerlikaya/claude-starter-kit/main/assets/logo.png" alt="Claude Starter Kit" width="460">

**An agentic working kit for Claude Code** — a reusable scaffold that drives any project, at any stage, with the same engineering discipline.

*plan → build → review → commit, where every critical rule is a **gate**, not a reminder.*

[![npm](https://img.shields.io/npm/v/@byerlikaya/claude-starter-kit?style=flat-square&color=2563eb)](https://www.npmjs.com/package/@byerlikaya/claude-starter-kit)
![License](https://img.shields.io/npm/l/@byerlikaya/claude-starter-kit?style=flat-square&color=16a34a)
![Agents](https://img.shields.io/badge/agents-11-f59e0b?style=flat-square)
![Skills](https://img.shields.io/badge/skills-34-f59e0b?style=flat-square)

</div>

---

## Install

```bash
npx @byerlikaya/claude-starter-kit             # fresh project — the setup wizard
npx @byerlikaya/claude-starter-kit adopt       # existing project — hand the kit over, brownfield-safe
npx @byerlikaya/claude-starter-kit@latest update   # refresh a project that already has the kit
```

No global install needed. Runs on macOS, Linux, and Windows (Git Bash).

## What you get

- **11 namespaced agents + 34 skills**, wired to a `plan → build → review → ship` workflow so the right expert and the right check fire at the right moment.
- **Tool-level gates, not reminders** — a git-commit trace/secret scan, Bash and Write guards, and session/context hooks enforce the rules instead of hoping you remember them.
- **In-session commands** — `/plan` · `/review` · `/ship` · `/handoff` · `/update-csk` (update the install) · `/doctor-csk` (health-check it).
- **Stack-aware** — a `.NET`/DevArchitecture backend pattern when detected, stack-agnostic otherwise; the frontend stays framework-neutral.

## Documentation

Full docs, the architecture, other install methods (**Homebrew** · **Claude Code plugin**), and the update/handover flow live on GitHub:

**→ https://github.com/byerlikaya/claude-starter-kit**

## License & attribution

MIT © Barış Yerlikaya. Built on [google/eng-practices](https://github.com/google/eng-practices) (code review, CC-BY 3.0), the [Karpathy working principles](https://github.com/multica-ai/andrej-karpathy-skills), and the [DevArchitecture](https://github.com/DevArchitecture/DevArchitecture) backend pattern — full credits in the [repository README](https://github.com/byerlikaya/claude-starter-kit#license--attribution).
