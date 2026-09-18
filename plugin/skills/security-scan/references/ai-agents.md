# Front 5 — AI, agent and MCP code

Read this front when the code under review builds on a model: it assembles prompts, retrieves context, stores
memory, exposes or calls tools, delegates to sub-agents, or speaks MCP. It is about the CODE around the model. For
testing whether a deployed agent's defences hold under attack, that is `red-team`.

## The rule that decides what counts

**Persuasive text is not a vulnerability. A missing deterministic control is.** A model can always be talked into
something; that alone proves nothing about the system. A finding here needs a boundary that code failed to hold:
content reached another principal's context, an action ran with authority the requester did not have, data was
disclosed to someone who could not read it, or a sink was driven that the attacker could not reach directly.

Three consequences follow, and they rule out most false positives in this front:

- **A system prompt is not a security boundary.** "The instructions tell it not to" is not a control. Count only
  what a deterministic path enforces: authorization scoped to the resource, isolation, binding, constrained
  credentials.
- **Everything the model reads or writes is untrusted input** — its own output, retrieved documents, memory, tool
  descriptions, MCP responses. Point to the line of code that trusts it.
- **Using your own authority on purpose is not a defect.** A user who asks the agent to do something they are
  allowed to do has not been attacked because a model carried it out.

Name, for every candidate: the attacker, the affected principal, the identity the action actually ran as, the
resource, the exact action, the authority used, and the result someone can observe.

## Where it breaks

### Context, retrieval and memory
- **Injected content reaching someone else's context.** Who can write each retrieved source — a document, page,
  ticket, email, tool result — and whose session ends up reading it? Check that retrieval is scoped to the reader,
  not just that the content looks benign.
- **Context bleeding across sessions or tenants.** History, embeddings, retrieval results and prompt caches keyed
  too broadly. A tenant field on the record is not enforcement if one query path or one cache key leaves it out.
- **Memory that turns low-trust observations into durable instructions.** Content an attacker influenced, or a
  model's own summary of it, written into memory that later steers another user or a privileged task. Who may
  create, merge and delete memory, and does retrieval tell a user's preference apart from policy? Memory a user
  saved for their own later requests is not a cross-boundary finding.
- **Forged provenance.** Prompt assembly that lets untrusted text pass as a system message, an earlier turn, a tool
  result or a memory record — string concatenation, untyped history, a caller-supplied role field. It matters when
  the forged label changes a trust decision or unlocks a capability.

### Tools and actions
- **Model-written arguments reaching a sink unchecked.** A tool schema shapes input; it does not authorize a path,
  a URL, a query or a resource id. Follow each argument from the decoded call to the SQL, shell, file or network
  call, and look for the handler's own validation.
- **Confused deputy.** The agent acts with a broad service credential and the handler never re-checks whether the
  requesting principal may touch that resource. Compare with what the same user could do through the normal
  product. A shared credential with enforced per-user scope is not a defect.
- **Approval that does not bind the action.** The user approves one described action, and execution can use
  different arguments, a different target, a later turn, a retry or a resumed session. Or attacker content triggers
  a side effect under the victim's valid authority that the victim never asked for — generic permission does not
  make that intentional. The approval has to bind the normalized tool name, the complete argument object, the
  requester and the target.
- **Schema and handler disagreeing.** Aliases, extra or duplicate keys, coercions, nested free-form objects,
  out-of-range values that validation accepts and the handler reads differently. Validate again where a value
  becomes a resource selector or a security option.
- **Delegated loops with no ceiling.** A bounded request that can enqueue unbounded spend, sends, mutations or
  external calls — no per-request budget, no per-action check, no cancellation, no idempotency. Establish it from
  the code and a locally bounded loop, never by exhausting a real service.

### MCP and sub-agents
- **Delegation that hands over everything.** A sub-agent or MCP call receives the whole session, its credentials,
  its memory, rather than the least authority the task needs; or its result is trusted on return.
- **Identity by name instead of by connection.** Calls or results routed by a server name, tool name, request id,
  resource URI or a model-chosen alias that an attacker can influence, instead of the authenticated connection and
  the pending request. Can two servers claim one tool? Does a reconnect change the binding? Can one server's
  response satisfy another's pending call?
- **Metadata treated as policy.** Tool descriptions, resource metadata, prompts, schemas and completion hints
  supplied by an MCP peer steer the model; they can never grant a capability. Find the allowlist, the server
  identity check and the handler authorization that stay authoritative when the metadata says otherwise.

### Output and disclosure
- **Model output rendered unencoded.** Output reaching HTML, Markdown, a template, a URL or a command without that
  sink's encoding. Whether a renderer outside the repository sanitizes it is a fact you do not have — that makes
  the candidate CANNOT_VERIFY, not confirmed.
- **Secrets extractable from the assembled context.** Credentials, another user's data or access-granting policy
  values placed in context that user-influenced output can reveal. Leaking generic instructions crosses no
  boundary and is not a finding.

## How to hunt it

Draw four maps before reading any single file: every identity code runs as, every capability, every context or
memory source something can write to, and every place output goes. Then connect the principal at the start to the
authority at the end. Work backward from each side-effecting tool through dispatcher, schema, confirmation, context,
retrieval and ingestion; work backward from each memory read to every writer. Compare the direct, queued, retried,
resumed, batched and delegated paths for the same action — the strongest check has to sit after the arguments are
final and before every side effect, on all of them.

## Before a finding here leaves the verifier

Apply `verify.md` as usual, plus:

1. It names the crossed boundary and the observable result — attacker, affected principal or shared resource,
   execution identity, target, and the unauthorized or unrequested action or disclosure.
2. A confused-deputy claim shows the handler lacks requester-and-resource authorization AND that the attacker could
   not do the same thing through the normal product. An action-binding claim instead shows attacker content caused
   an action under the affected principal's authority that the principal never intentionally requested or approved.
3. A memory or retrieval claim cites both ends: the attacker-controlled write and the later read by another
   principal or a privileged decision. A shared record nothing reads across a boundary is not enough.
4. An MCP identity claim checks the authenticated connection, the request correlation, the tool namespace and the
   effective credential. If it depends on how an external server or the deployment routes calls, it is
   CANNOT_VERIFY with the exact fact that would settle it.

---

The classes and the discipline above are adapted from the AI, LLM and agent companion in
`cloudflare/security-audit-skill` (MIT), rewritten for this skill's source→gate→sink model and its three-outcome
verdict.
