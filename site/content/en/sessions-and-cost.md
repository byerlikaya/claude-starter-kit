# Sessions and cost

How full a session is gets **measured, not estimated** — the real token count, read every turn, the same figure `/context` reports. One warning at **75%**, one more at **90%**, and neither interrupts your turn.

The standing cost is published, not hidden. The discipline plus every agent and skill description load into each session: **29,567 bytes**, measured by `smoke-test.sh`. A real `claude -p` turn in which 21,804 bytes of the same material cost 9,198 tokens gives the ratio; at that ratio this is about **12.5k tokens**. The byte figure is what the suite gates. Each skill you add is a permanent **~100-token** tax on every session, so a byte budget per component is enforced as a gate. Raising it takes an explicit edit to the test.

**Why not install fewer components?** Because it buys almost nothing. Every agent and skill description together is 15,855 bytes, about **6.7k tokens** at the same ratio; leaving out the four UI skills and the frontend agent saves 1,558 of those bytes — roughly **660 tokens**, or **0.3%** of a 200k window. That is worth controlling per component, which the byte budget does, rather than per project.

## Working as a team

**A team board, when more than one of you shares the repo.** Taking an item is a push to a git ref, and pushing is fast-forward-only — so of two simultaneous claims exactly one lands and the other is refused in under a second, before any code is written. Decisions and handover notes travel with it, so what one session settled reaches the next person's. Off until you ask for it (`/crew-board init`); solo work never sees it.

<div align="center">
  <img src="../../../assets/board-en.svg" alt="The team board: a claim is an atomic push to a git ref" width="820">
</div>
