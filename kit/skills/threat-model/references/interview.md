# Threat-model interview + bootstrap

## Interview mode — Shostack four questions, ONE at a time
Never present a questionnaire. Ask, capture into the schema, move on. Mirror the user's language.

### 1 · What are we building?
System context, assets, entry points, trust boundaries. Draw the boundary explicitly: *"untrusted input crosses
into trusted code HERE."* List every entry point — this becomes section 3 and the coverage checklist.

### 2 · What can go wrong?
Open-ended first ("what would hurt most if it broke?"). Then, per entry point with nothing yet, walk **STRIDE**:

| STRIDE | asks |
|---|---|
| **S**poofing | can someone pretend to be another principal? |
| **T**ampering | can data / requests be modified in transit or at rest? |
| **R**epudiation | can an action be denied, or does it go unlogged? |
| **I**nformation disclosure | can data leak across a trust boundary? |
| **D**enial of service | can availability be exhausted (beyond plain volumetric floods)? |
| **E**levation of privilege | can a lower role reach a higher-privilege action? |

Derive **5-8 domain-specific attack classes** at the right granularity — "IDOR on dataset rows", "integer
overflow on length fields", "tenant bleed via a missing scope check" — **not** "web vulnerabilities". Granularity
test: a class should name *a surface + a mechanism*, so the scanner knows exactly what to grep for.

### 3 · What are we doing about it?
For each threat: `impact`, residual `likelihood`, `status`, `controls`. "Accept the risk, with a written reason"
(`risk_accepted`) is a legitimate status — record the reason verbatim in section 6.

### 4 · Did we do a good job?
Read the ranked table back to the owner. **Coverage check:** every entry point from Q1 appears in ≥1 threat's
`surface`. Add anything missing before you emit.

**Provenance discipline:** tag every fact **`[Code-verified]`** (you read it) or **`[Owner-states]`** (they said
it). Every owner claim that changes a score becomes an open question in section 6 with **"Verify by: <how>."**

## Bootstrap mode — no owner available
1. **Map** (in parallel where the codebase is large): docs, the entry-point surface, infra / IAM, the assets,
   and past advisories — `git log --all -i --grep=<stack keywords>`, `gh api repos/<o>/<r>/security-advisories`.
2. **Generalize** each past vulnerability into a *threat*: cluster by `(entry point, bug class, asset reached)`.
   Run a **variant scan** — grep for siblings of each vulnerable pattern — to estimate how much of the surface
   shares it (more siblings → higher likelihood; sibling locations become **scan leads, not evidence**).
3. **Gap-fill with STRIDE** for every entry point that still has no threat ("past vulnerabilities are biased
   toward what has already been found"). Invariant: the final table must contain **≥1 threat with empty
   evidence**, or the gap-fill step did not actually run.
4. **Flag** every scored owner-would-know claim as an open question, so a later 10-minute interview closes it.

## Handing scope to security-scan
`security-scan` reads `docs/THREAT_MODEL.md`: section 3 (entry points) and section 5 (attack classes) become its
focus areas; the threat `impact`/`likelihood` bias which findings it treats as high severity. No threat model →
`security-scan` falls back to its own Front 0 discovery.
