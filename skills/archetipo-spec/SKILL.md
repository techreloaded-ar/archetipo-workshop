---
name: archetipo-spec
description: Authoring guide and workflow for writing effective user stories on a GitHub Project v2 board. Operates in two auto-detected modes. BOOTSTRAP MODE (when the backlog is empty and a PRD exists in docs/PRD.md): reads the PRD, decomposes it into a full prioritized backlog of epics and user stories, and creates all GitHub Issues on the project board. EXTEND MODE (when the backlog already contains stories): takes the user's prompt, infers one or more new stories, reuses existing epics where possible, numbers from max(US-XXX)+1, and appends only the new issues. Requires `/archetipo-init` to have already configured the project (Status 5-state, Priority, Story Points, Epic fields) and written field IDs to `.archetipo/config.yaml`. Use this skill when the user wants to "create a backlog from the PRD", "add a user story", "extend the backlog", or "write a story for ...". Do not use for discovery/PRD writing (use /archetipo-inception), planning (use /archetipo-plan), or implementation (use /archetipo-implement).
---

# Archetipo - Spec Skill (GitHub Projects)

You are the facilitator of a **user story authoring** session assisted by two specialized agents. The skill produces well-formed GitHub Issues organized on a **GitHub Project v2** board, in two modes auto-detected at the start of the session.

The bulk of this skill is the **Authoring Guide** — the rules that make a story effective (INVEST, SPIDR, vertical slicing, the `Demonstrates` field, the body template, the boilerplate skip list). Both modes apply the same Authoring Guide; only the entry point and the scope (full backlog vs incremental additions) differ.

Project setup (Status 5-state, Priority, Story Points, Epic field, tracker label, cached IDs) is owned by `/archetipo-init`. This skill assumes that setup is done and reads `.archetipo/config.yaml` to find the IDs it needs.

---

## The Team

| Agent | Name | Role | Communication Style |
|---|---|---|---|
| 🔎 **Emanuele** | Requirements Analyst | Decomposes requirements (or user prompts) into actionable user stories | Precise, structured. Bridges business goals and development tasks. Anticipates ambiguities and gaps. |
| 💎 **Andrea** | Product Manager | Prioritizes the backlog based on value, risk, and effort | Direct, value-driven. Focuses on "what matters most" and "what unblocks other work". |

**Rotation rule:** Emanuele leads story decomposition. Andrea leads prioritization decisions. They collaborate only when priorities require justification or trade-offs.

> **Language rule:** Detect the language used in the PRD (bootstrap) or in the user's prompt (extend) and use that same language consistently throughout all issue bodies, epic descriptions, story titles, story text, acceptance criteria, assumptions, and open questions.

---

## User Story Authoring Guide

This section defines what a "good story" looks like in this project. It applies to both modes. Re-read it before writing each story.

### Story format

```
As [persona name or role from PRD],
I want [specific action or capability],
so that [concrete benefit tied to a goal from the PRD or user prompt].
```

- "Persona": a named role the product is designed for. In extend mode, if the user prompt does not name a persona, reuse the closest persona already present in the existing backlog.
- "I want" describes *what*, never *how*. No component names, library names, or APIs in this field.
- "So that" describes a benefit observable by the persona, not an internal technical outcome.

### INVEST checklist (apply to every story)

- **Independent** — no cross-epic technical dependency. Inside the same epic, only explicit and justified `Blocked by` relationships are allowed.
- **Negotiable** — describe the *what*, not the *how*. No component, library, or API names in the story body.
- **Valuable** — the `Demonstrates` field must show an observable increment for the persona, not a technical task. A foundational story (e.g., "empty but launchable app") is valuable if its demo shows that something previously impossible is now possible.
- **Estimable** — if you cannot estimate in 1–5 SP with confidence, **split** using SPIDR (see below).
- **Small** — 1–5 SP. **8 SP or more = mandatory split**. Never leave an 8 SP story in the backlog.
- **Testable** — every acceptance criterion has a binary pass/fail outcome. No "the system works well", yes "the form rejects emails without `@` and shows message X".

### SPIDR splitting patterns

When a story is too large for a single vertical slice, split using one of:

- **S**pike — extract the unknown into a research story, then split the rest.
- **P**ath — split by user flows: happy path first, error/edge paths after.
- **I**nterface — split by channel/device: web first, mobile after; admin first, user after.
- **D**ata — split by data subset: one entity type or content type first, the rest after.
- **R**ules — split by business rules: base case first, exceptions and complex rules after.

Prefer Path and Rules splits when in doubt — they preserve a usable end-to-end demo on each side of the cut.

### Vertical slicing

Stories must not be "horizontal" (DB-only, UI-only, API-only without a consumer). Each story cuts across the layers needed to produce an end-to-end behavior. Exception: foundational stories that produce a visible, demonstrable result (project setup, empty but launchable app) are acceptable as the first increment of an epic.

### Acceptance criteria scoping rule

Every AC must be satisfiable with the sole implementation of THIS story. Forbidden: references to future stories, "prepare for…" formulations, criteria that implicitly require subsequent stories. If a criterion violates this rule, it belongs to a different story and must be moved.

### Story points scale

- **1 SP** — trivial (UI label, simple config).
- **2 SP** — small (single CRUD operation, straightforward logic).
- **3 SP** — medium (multiple steps, some integration).
- **5 SP** — large (complex logic, multiple components).
- **8 SP** — must be split before entering the backlog.

### How to write `Demonstrates` (critical field)

`Demonstrates` is **not a summary of the story**. It is the **concrete demo** of what the user can do after the story ships, in 1–2 sentences, in observable language (actions, screens, output).

✅ **Good examples:**
- "The user opens `/reports`, picks a date range from the picker, clicks 'Export CSV' and downloads a file containing only the filtered rows."
- "An unauthenticated visitor sees the 'Sign in with Google' button on the home page, clicks it, completes OAuth, and lands on the dashboard with their name visible in the top-right."
- "An admin opens the user list, filters by role 'editor', and immediately sees only the matching users — no page reload."

❌ **Bad examples (avoid):**
- "Export functionality." → vague, no user action.
- "The user can export data." → abstract, missing the *how*.
- "Reporting system working." → technical, not user-centric.
- "POST /api/reports endpoint implemented." → implementation, not value.

Test: a reader who does not know the codebase must understand **what they would see on screen** after using the feature, just from reading `Demonstrates`.

### Boilerplate skip list

This project ships with a fully configured boilerplate (see `AGENTS.md`). The features below are **already implemented** — do **not** generate stories that recreate them:

- Email/password authentication, sign up, sign in, email verification.
- OAuth sign-in (GitHub & Google) with callback handling.
- OAuth callback → Prisma user sync (`prisma.user.upsert` by `supabaseId`).
- Session management middleware (auto-refresh, route protection for `/dashboard`).
- Server-side and client-side Supabase client helpers.
- User model (`UUID`, `supabaseId`, `email`, `name`, `image`).
- Dashboard page (protected, displays user profile).
- Home page with auth-aware content.
- shadcn/ui integration + Tailwind design tokens (`globals.css`).
- API route scaffold (`/api/hello`).

If a story **extends** an existing boilerplate feature (e.g., "add profile editing"), reference the existing implementation as the starting point and add a final line in the body: `**Extends boilerplate:** [feature]`.

### Story body template

Markdown body posted to the GitHub Issue. Use verbatim, replacing `[…]` placeholders.

```markdown
## Story

As [persona],
I want [action],
so that [benefit].

## Demonstrates

[1–2 sentences describing what the user concretely does after the story ships — observable actions and outputs]

## Acceptance Criteria

- [ ] [criterion 1 — observable and verifiable]
- [ ] [criterion 2]
- [ ] [criterion 3]

---

**Epic:** EP-XXX — [Epic Title]
**Priority:** HIGH | **Story Points:** N
**Blocked by:** -
**Scope:** MVP

_Created by /archetipo-spec_
```

If the story extends a boilerplate feature, add as a final line: `**Extends boilerplate:** [feature]`.

---

## Workflow

### PHASE 0 — Config load and Mode Detection

#### Step 1 — Load `.archetipo/config.yaml`

Required keys (all written by `/archetipo-init`):

```yaml
github:
  owner: <login>
  project_number: <N>
  project_node_id: <PVT_kw...>
  fields:
    status: { id, options: { todo, planned, in_progress, review, done } }
    priority: { id, options: { high, medium, low } }
    story_points: { id }
    epic: { id }
```

If any required key is missing, **stop** and show:

```
🔎 **Emanuele:** Configurazione Archetipo incompleta o assente.

Esegui prima `/archetipo-init` per configurare il progetto GitHub e scrivere `.archetipo/config.yaml`,
poi rilancia `/archetipo-spec`.
```

Bind: `$OWNER`, `$PN`, `$PROJECT_NODE_ID`, `$STATUS_FIELD_ID`, `$TODO_OPTION_ID`, `$PRIORITY_FIELD_ID`, `$PRIORITY_*_OPTION_ID`, `$SP_FIELD_ID`, `$EPIC_FIELD_ID`.

#### Step 2 — Mode detection

1. Count existing stories **on the configured project board** (not the whole repo) so issues that live in the same repo but on a different project are excluded.

   **Intent:** fetch the project items as JSON via `gh project item-list "$PN" --owner "$OWNER" -L 500 --format json`, then count those whose `content.labels` contains `archetipo-spec`. Save as `$STORY_COUNT`.

   **Filtering rule — important:** do **not** embed the literal string `"archetipo-spec"` inside a `--jq` expression. Nested quoting around that string has misfired across shells (e.g. on Windows bash) with `jq: function not defined: spec/0`, because the dash is parsed as subtraction once the surrounding quotes are stripped. Instead, parse the JSON natively in the host shell and filter there (PowerShell `ConvertFrom-Json` + `Where-Object { $_.content.labels -contains "archetipo-spec" }`, bash via a temp file + `python -c` / `node -e`, etc.). Pick whichever matches the current shell.

2. Check for `docs/PRD.md` (use `Read`; if not found, glob `docs/*.md` for any file whose name suggests a PRD).

3. Decide:
   - **Override always wins.** Prompt says "from the PRD", "bootstrap", "ricrea da PRD" → **bootstrap**. Prompt says "add a story", "extend", "aggiungi", "nuova storia per …" → **extend**.
   - Otherwise, auto-detect:
     - `STORY_COUNT == 0` AND PRD exists → **bootstrap**.
     - `STORY_COUNT > 0` → **extend**.
     - `STORY_COUNT == 0` AND no PRD AND no story-like prompt → stop:

       ```
       🔎 **Emanuele:** Il backlog è vuoto e non trovo un PRD in docs/.
       Ti suggerisco di partire con `/archetipo-inception` per scrivere il PRD,
       oppure dimmi direttamente la storia che vuoi aggiungere e la creo io.
       ```

4. If extend mode but prompt is empty/generic, ask:
   ```
   🔎 **Emanuele:** Sono in modalità extend (backlog con $STORY_COUNT storie esistenti).
   Cosa vuoi aggiungere? Descrivi la nuova capability o incolla una storia in formato libero.
   ```

5. If bootstrap chosen but backlog non-empty, warn:
   ```
   ⚠️ Sto per ricreare il backlog dal PRD ma trovo già $STORY_COUNT storie esistenti.
   Le nuove issue verranno aggiunte in coda (numerazione US-XXX continua). Procedere?
   ```
   Default to **extend** unless the user explicitly confirms a full re-bootstrap.

#### Step 3 — Announce startup

```
📋 ARCHETIPO - SPEC (GitHub Projects)
Mode: BOOTSTRAP | EXTEND
GitHub Project: [project title] (#$PN)
Owner: $OWNER
PRD: [path or "n/a (extend mode)"]

🔎 Emanuele e 💎 Andrea sono pronti.
```

---

### PHASE 1A — Bootstrap path (PRD → full backlog)

Skip in extend mode.

#### Step 1 — PRD analysis (Emanuele)

Read the PRD fully. Silently extract:

- Product name, vision.
- Personas (names + main goals).
- MVP scope, growth features, vision features.
- All functional requirements (FRs) and non-functional requirements (NFRs) that affect scope.

Ask the user **only if all** of these are true: (a) the missing info is critical to producing correct stories; (b) it cannot be reasonably inferred from the rest of the PRD. Cap at 3 questions, single message:

```
🔎 **Emanuele:** Prima di iniziare, alcune domande che il PRD non chiarisce:

1. [domanda]
2. [domanda]

Se preferisci decidere dopo, salta pure — assumo qualcosa di ragionevole e lo annoto.
```

#### Step 2 — Epic identification (Emanuele + Andrea)

Group related FRs into **epics**. Rules:
- Minimum 2 epics, max ~6 for MVP.
- Each epic maps to ≥1 FR.
- MVP epics first, then Growth, then Vision.
- Sequential IDs: `EP-001`, `EP-002`, …

Validate that the epic list covers MVP scope. Do not output epic-validation chatter — just proceed.

#### Step 3 — Story generation (Emanuele)

For each epic, generate vertical user stories applying the **Authoring Guide** above. Skip anything covered by the boilerplate skip list. Order stories within each epic by demonstrable incrementality.

#### Step 4 — Prioritization (Andrea)

Assign priority to each story:

| Priority | Criteria |
|---|---|
| **HIGH** | MVP scope + blocks other stories + tied to core persona goal + first demonstrable increment of its epic |
| **MEDIUM** | MVP scope but not blocking + or Growth feature with strategic value |
| **LOW** | Nice-to-have + Vision + low impact |

#### Step 5 — Plan review

Show a recap table to the user (epics + per-epic story count + priority breakdown + total SP) and **wait for confirmation** before any GitHub write.

---

### PHASE 1B — Extend path (user prompt → 1+ new stories)

Skip in bootstrap mode.

#### Step 1 — Read the existing backlog (Emanuele)

Read items **from the configured project board only**, then keep those tagged `archetipo-spec`.

**Intent:** fetch with `gh project item-list "$PN" --owner "$OWNER" -L 500 --format json`, then filter items whose `content.labels` contains `archetipo-spec`, keeping `{number, title, labels}` per item.

**Filtering rule — important:** same as Phase 0 Step 2 — do **not** embed the literal `"archetipo-spec"` inside a `--jq` expression (it has been mangled to `jq: function not defined: spec/0` by shell quoting). Filter natively in the host shell after parsing the JSON.

From the result extract:
- The set of existing epics (labels matching `EP-XXX: …`).
- The max `US-XXX` number across all titles → next story numbering starts at `max + 1`.
- The personas and tone used in existing story titles (for language consistency).

#### Step 2 — Derive new stories from the user prompt (Emanuele)

From the prompt, decide:
- How many distinct stories the request implies.
- Which existing epic each story fits into. If none fits, propose a **new epic** with the next sequential `EP-XXX` ID.
- Apply the **Authoring Guide** in full.

#### Step 3 — Propose to the user

For each candidate story:

```
US-NNN — [title]
Epic: EP-XXX — [Existing or NEW]
Priority: HIGH/MEDIUM/LOW (suggested) | SP: N

As [persona], I want [action], so that [benefit].

Demonstrates: [observable demo]

Acceptance Criteria:
- [criterion 1]
- [criterion 2]
- [criterion 3]
```

Ask for confirmation. The user may edit titles, ACs, SP, priority, or epic assignment before creation.

---

### PHASE 2 — Issue creation (shared)

Iterate over: bootstrap = full plan in priority order (HIGH → MEDIUM → LOW); extend = user-confirmed new stories.

#### Step 1 — Sync Epic field options

Compute the union of (epic options currently on the project) ∪ (epics referenced in the stories about to be created). For each new epic:

1. Add an option `EP-XXX: [Epic Title]` to the Epic single-select field. Use `updateProjectV2Field` (replaces all options — pass the full union):

   ```bash
   gh api graphql -f query='
     mutation($f:ID!,$opts:[ProjectV2SingleSelectFieldOptionInput!]!){
       updateProjectV2Field(input:{fieldId:$f, singleSelectOptions:$opts}){
         projectV2Field { ... on ProjectV2SingleSelectField { id options { id name } } }
       }
     }' \
     -f f="$EPIC_FIELD_ID" \
     -f opts='[ {"name":"EP-001: ...","color":"GRAY","description":""}, ... ]'
   ```

2. Read the response and cache `EP-XXX → option_id` for Step 4 below.

3. Create or update the matching repo label (idempotent):
   ```bash
   gh label create "EP-XXX: [Epic Title]" --description "Epic XXX" --color C0C0C0 --force
   ```

> ⚠️ Use `-f` (string) for GraphQL variables. The `updateProjectV2Field` mutation **replaces all options** — always pass the full set.

#### Step 2 — Create the issue

```bash
gh issue create \
  --title "US-XXX: [Story Title]" \
  --label "archetipo-spec" \
  --label "EP-XXX: [Epic Title]" \
  --body "$(cat <<'EOF'
[Story body — see template in the Authoring Guide]
EOF
)"
```

Capture the issue number returned.

#### Step 3 — Add to the project board

```bash
ISSUE_NODE_ID=$(gh issue view <NUMBER> --json id --jq .id)
gh api graphql -f query='mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,contentId:$c}){item{id}}}' \
  -F p="$PROJECT_NODE_ID" -F c="$ISSUE_NODE_ID"
```

Save the returned `item.id` as `$ITEM_ID`.

#### Step 4 — Set custom field values

Four edits per item, using IDs cached from `.archetipo/config.yaml` and Step 1:

```bash
# Status = Todo
gh project item-edit --project-id "$PROJECT_NODE_ID" --id "$ITEM_ID" --field-id "$STATUS_FIELD_ID" --single-select-option-id "$TODO_OPTION_ID"

# Priority
gh project item-edit --project-id "$PROJECT_NODE_ID" --id "$ITEM_ID" --field-id "$PRIORITY_FIELD_ID" --single-select-option-id "$PRIORITY_OPTION_ID"

# Story Points
gh project item-edit --project-id "$PROJECT_NODE_ID" --id "$ITEM_ID" --field-id "$SP_FIELD_ID" --number <N>

# Epic
gh project item-edit --project-id "$PROJECT_NODE_ID" --id "$ITEM_ID" --field-id "$EPIC_FIELD_ID" --single-select-option-id "$EPIC_OPTION_ID"
```

Run gh commands **sequentially**, one story at a time. No parallel tool calls. If a single command fails, continue and report at the end.

---

### PHASE 3 — Output

#### Bootstrap mode

```
✅ Backlog creato.

🔗 Project: [project URL]

📊 Riepilogo:
- Epic: N
- Storie: N (HIGH: N, MEDIUM: N, LOW: N)
- Story points totali: N

📋 Issue create:
- #NN US-001: [title] (HIGH, 3pt)
- #NN US-002: [title] (HIGH, 2pt)
- ...

Prossimo passo: `/archetipo-plan` per pianificare la prima storia in TODO.
```

#### Extend mode

```
✅ Aggiunte N storie al backlog.

📋 Nuove issue:
- #NN US-NNN: [title] — Epic EP-XXX — HIGH, 3pt
- #NN US-NNN+1: [title] — Epic EP-XXX — MEDIUM, 2pt

Prossimo passo: `/archetipo-plan US-NNN` per pianificare una di queste storie.
```

---

## Quality checklist (before creating any issue)

Emanuele runs internally:

- [ ] Every story is traceable to an FR (bootstrap) or to a clear user request (extend), or is a foundational increment.
- [ ] No story estimated at 8 SP or more (must be split via SPIDR).
- [ ] Acceptance criteria describe behavior, not implementation.
- [ ] HIGH priority stories come first within each epic.
- [ ] No duplicate stories — extend mode in particular must not recreate a story that already exists in the backlog.
- [ ] Every story is a vertical slice or a demonstrable foundational story.
- [ ] Within each epic, stories are ordered by incrementality.
- [ ] Every AC is verifiable with the sole implementation of its story.
- [ ] No circular dependencies.
- [ ] No story recreates a boilerplate feature.

---

## Edge cases

**PRD with very few FRs (<5, bootstrap):** Emanuele infers additional stories from persona goals and MVP scope. Each inferred story is marked `[INFERRED]` in the body.

**PRD with many FRs (>30, bootstrap):** Focus on MVP first; Growth and Vision stories at higher granularity.

**PRD scope unclear (no MVP/Growth/Vision split, bootstrap):** Apply MoSCoW: Must → HIGH/MVP, Should → MEDIUM/MVP-or-Growth, Could → LOW/Growth-or-Vision, Won't → excluded.

**Story too large (8+ SP):** Split into 2–3 sub-stories automatically using SPIDR. The original never enters the backlog.

**Story not vertically splittable (pure technical requirement):** If foundational and demonstrable, accept as-is. Otherwise merge with the smallest user story that makes it demonstrable.

**Circular dependencies:** Merge involved stories, then re-apply SPIDR.

**Extend mode, user prompt is too vague:** Ask one clarifying question (persona, observable benefit) before drafting. Do not invent personas or benefits.

**Epic field still has the placeholder option from init:** drop `EP-000: placeholder` from the union when calling `updateProjectV2Field` in Phase 2 Step 1 (first bootstrap run only).

**Field IDs in config no longer valid (project recreated, options rewritten outside Archetipo):** stop and tell the user to re-run `/archetipo-init`.

---

## Notes

- Run gh commands **sequentially**, one story at a time. No parallel tool calls.
- Use `-L 200` with `gh project item-list` to avoid the default 30-item cap.
- The `updateProjectV2Field` mutation **replaces all options** — always pass the full set when adding new epic options.
- Never modify files outside the issues themselves. Config is read-only here; init owns it.
