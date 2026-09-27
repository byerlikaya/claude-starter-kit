# Sessions and cost

How full a session is gets **measured, not estimated** — the real token count, read every turn, the same figure `/context` reports. One warning at **{{FILL_WARN}}%**, one more at **{{FILL_ALERT}}%**, and neither interrupts your turn.

The standing cost is published, not hidden. The discipline plus every agent and skill description load into each session: **{{ALWAYS_ON_BYTES}} bytes**, measured by `smoke-test.sh`. A real `claude -p` turn in which 21,804 bytes of the same material cost 9,198 tokens gives the ratio; at that ratio this is about **{{ALWAYS_ON_TOKENS}} tokens**. The byte figure is what the suite gates. Each skill you add is a permanent **~100-token** tax on every session, so a byte budget per component is enforced as a gate. Raising it takes an explicit edit to the test.

**Why not install fewer components?** Because it buys almost nothing. Every agent and skill description together is {{DESC_BYTES}} bytes, about **{{DESC_TOKENS}} tokens** at the same ratio; leaving out the four UI skills and the frontend agent saves {{UI_BYTES}} of those bytes — roughly **{{UI_TOKENS}} tokens**. That is worth controlling per component, which the byte budget does, rather than per project.
