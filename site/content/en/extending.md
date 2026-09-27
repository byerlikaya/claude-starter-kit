# Extending

Three rules hold the design together.

1. **An agent is a thin trigger.** It says *who* and *when*, nothing more. It stays short, because its description is loaded into every session.
2. **A skill is the single source of truth.** The actual method lives there once, and is never copied into an agent.
3. **A rule that matters becomes a gate.** Enforcement sits at the tool level — a hook, a permission, a test case. The model is not asked to remember it.

When you add an agent or a skill, follow the `AGENT_TEMPLATE.md` contract: frontmatter (name · description · least-privilege tools · model tier), the `Trigger phrases:` line in the body, and the body sections (When → Expertise stance → How → Coordination → Definition of Done → Output → Escalation → Example → Constraints). `smoke-test.sh` refuses a component that nothing routes to, so nothing ships asleep. `/crew-skill` walks you through it and ends in the gates.

To take a single component rather than the full install, `npx crewforth add <name>` copies one agent or skill (and the skills an agent uses) into `./.claude`; `npx crewforth add --list` shows the catalogue.
