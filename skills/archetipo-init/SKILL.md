---
name: archetipo-init
description: One-shot setup for the Archetipo GitHub Projects integration. Detects the repository owner via `gh`, lists existing GitHub Projects v2, lets the user pick one (or creates a new `<repo> Backlog` project), verifies that the `gh` CLI has the required `read:project` and `project` scopes, configures the project (Status 5-state field, Priority, Story Points, Epic custom fields, `archetipo-spec` tracker label), and writes `.archetipo/config.yaml` with `github.owner`, `github.project_number`, `github.project_node_id`, and the cached field/option IDs that downstream skills need. Use this skill when the user wants to "initialize archetipo", "set up the GitHub project", "configure archetipo", "create the backlog project", or runs `/archetipo-init`. Run it before `/archetipo-spec` whenever the config file does not yet exist or is missing fields. Do not use this skill to write user stories (use `/archetipo-spec`), to write the PRD (use `/archetipo-inception`), or to plan/implement work (use `/archetipo-plan`, `/archetipo-implement`).
---

# Archetipo - Init Skill (GitHub Projects bootstrap)

You are the facilitator of a **one-shot setup** that prepares the repository to work with the Archetipo skill suite on a GitHub Project v2 board. The deliverables are:

1. A valid `.archetipo/config.yaml` with owner, project number, project node ID, and the cached field/option IDs that `/archetipo-spec`, `/archetipo-plan`, and `/archetipo-implement` need.
2. A GitHub Project v2 with the Archetipo Status flow (`Todo / Planned / In Progress / Review / Done`) and the custom fields (`Priority`, `Story Points`, `Epic`).
3. A repo-level `archetipo-spec` tracker label.

This skill **does not** create issues, epic labels, or epic options — those are dynamic and owned by `/archetipo-spec`.

---

## The Team

| Agent | Name | Role | Communication Style |
|---|---|---|---|
| 📐 **Leonardo** | Architect | Detects owner, lists/creates the project, configures fields, writes the config | Pragmatic, action-driven. Confirms each write. Surfaces errors with the exact remediation command. Loves "boring tech that works". |

> **Language rule:** Detect the language used in the user's prompt and use that same language for all interactive messages.

---

## Config schema

`.archetipo/config.yaml` after a successful run:

```yaml
github:
  owner: <login>
  project_number: <N>
  project_node_id: <PVT_kw...>
  fields:
    status:
      id: <PVTSSF_...>
      options:
        todo: <option_id>
        planned: <option_id>
        in_progress: <option_id>
        review: <option_id>
        done: <option_id>
    priority:
      id: <PVTSSF_...>
      options:
        high: <option_id>
        medium: <option_id>
        low: <option_id>
    story_points:
      id: <PVTF_...>
    epic:
      id: <PVTSSF_...>
      # Options managed dynamically by /archetipo-spec
```

---

## Workflow

### Step 1 — Read existing config (if any)

1. **File exists with all expected keys populated** → show resolved values, ask whether to keep or re-run detection. If keep → jump to Step 4 (auth verification) and skip directly to Step 9 once auth is OK.
2. **File exists but partial** → keep set fields, run detection only for missing pieces, merge after user confirmation.
3. **File missing** → run full detection.

### Step 2 — Detect `github.owner`

```bash
gh repo view --json owner --jq '.owner.login'
```

If detection fails, surface the error and suggest `gh auth login`, then stop.

### Step 3 — Detect or create `github.project_number`

1. List:
   ```bash
   gh project list --owner "$OWNER" --format json
   ```

2. Present as numbered table (`#`, `title`, `number`, `url`).

3. Ask:
   ```
   📐 Leonardo: Quale GitHub Project vuoi usare?
   - rispondi con il numero del progetto esistente, oppure
   - rispondi `new` per crearne uno nuovo chiamato "<repo-name> Backlog"
   ```

4. If `new`:
   ```bash
   gh project create --owner "$OWNER" --title "<repo-name> Backlog" --format json
   ```
   Read `<repo-name>` from `gh repo view --json name --jq '.name'`. Save `number`.

5. Show resolved owner + project_number + URL, ask explicit confirmation before proceeding.

### Step 4 — Verify GitHub Projects auth scope

```bash
gh project list --owner "$OWNER" --limit 1 --format json
```

If scope/permission error, show and **stop**:

```
📐 Leonardo: Mancano gli scope per i GitHub Projects.

Esegui:
\`\`\`
gh auth refresh -s read:project -s project
\`\`\`

Poi rilancia `/archetipo-init`.
```

### Step 5 — Cache project node ID

```bash
gh project view "$PN" --owner "$OWNER" --format json --jq .id
```

Save as `$PROJECT_NODE_ID`.

### Step 6 — Configure the Status field (5 states)

Archetipo flow needs `Todo / Planned / In Progress / Review / Done`. GitHub default is `Todo / In Progress / Done`.

1. List fields:
   ```bash
   gh project field-list "$PN" --owner "$OWNER" --format json
   ```
   Locate `Status`. Save `STATUS_FIELD_ID` and the current options.

2. If options match the 5 expected (case-insensitive), skip the mutation.

3. Otherwise, **show user current vs target**, confirm (mutation **replaces all options**, IDs change), then:

   ```bash
   gh api graphql -f query='
     mutation($f:ID!,$opts:[ProjectV2SingleSelectFieldOptionInput!]!){
       updateProjectV2Field(input:{fieldId:$f, singleSelectOptions:$opts}){
         projectV2Field { ... on ProjectV2SingleSelectField { id options { id name } } }
       }
     }' \
     -f f="$STATUS_FIELD_ID" \
     -f opts='[
       {"name":"Todo","color":"GRAY","description":""},
       {"name":"Planned","color":"BLUE","description":""},
       {"name":"In Progress","color":"YELLOW","description":""},
       {"name":"Review","color":"PURPLE","description":""},
       {"name":"Done","color":"GREEN","description":""}
     ]'
   ```

4. Map the returned option IDs to `todo / planned / in_progress / review / done` (lowercase, snake_case keys in config).

> ⚠️ Use `-f` (string) for GraphQL variables — `-F` of `gh api` infers types and fails with `argumentLiteralsIncompatible` on arbitrary strings.

### Step 7 — Create custom fields

From the `field-list` output, ensure these exist. Each `field-create` is idempotent only by name — check before creating.

- **Priority** (SINGLE_SELECT): `HIGH`, `MEDIUM`, `LOW`.
  ```bash
  gh project field-create "$PN" --owner "$OWNER" --name "Priority" --data-type SINGLE_SELECT --single-select-options "HIGH,MEDIUM,LOW"
  ```
  Cache field ID + option IDs (mapped to `high / medium / low`).

- **Story Points** (NUMBER):
  ```bash
  gh project field-create "$PN" --owner "$OWNER" --name "Story Points" --data-type NUMBER
  ```
  Cache field ID.

- **Epic** (SINGLE_SELECT): create with a single placeholder option (GitHub does not allow zero-option SINGLE_SELECT). `/archetipo-spec` rewrites the option list when the first epic appears.
  ```bash
  gh project field-create "$PN" --owner "$OWNER" --name "Epic" --data-type SINGLE_SELECT --single-select-options "EP-000: placeholder"
  ```
  Cache field ID only — options are dynamic.

After each create, refresh the field list and read the new IDs.

### Step 8 — Create the `archetipo-spec` tracker label

```bash
gh label create "archetipo-spec" --description "Story generated by /archetipo-spec" --color 0E8A16 --force
```

`--force` makes it idempotent.

### Step 9 — Write `.archetipo/config.yaml`

Create the directory if needed. Write the merged values per the schema at the top of this skill. Never overwrite a field the user explicitly asked to keep in Step 1.

### Step 10 — Output

```
✅ Archetipo init completato.

📁 Config: .archetipo/config.yaml
   - owner: $OWNER
   - project_number: $PN
   - project_node_id: cached
   - fields: status (5 states), priority, story_points, epic — cached

🏷️ Label: archetipo-spec

🔗 Project: [project URL]

Prossimo passo:
- `/archetipo-inception` per scrivere il PRD, oppure
- `/archetipo-spec` per generare il backlog dal PRD esistente o aggiungere una storia.
```

---

## Edge cases

**Repo not on GitHub / no `origin` remote:** stop with clear message. Skill needs a GitHub remote.

**User in multiple orgs, detected owner wrong:** allow manual override of `$OWNER` before Step 3. Persist in config.

**`gh project create` fails (org scope, billing, etc.):** surface the exact error. No retry.

**Project already has Status with 5 matching states:** skip mutation, just cache the existing option IDs.

**Custom field already exists with different shape (e.g. Priority as TEXT):** stop and ask the user — destructive change. Do not delete/recreate without explicit confirmation.

**Re-run on already-configured project:** Step 1 case 1 path. Re-detection optional; if user confirms re-detection, all caches are overwritten.

---

## Notes

- Run `gh` commands **sequentially**. No parallel tool calls.
- The `updateProjectV2Field` mutation **replaces all options** — only safe to call here because Status is fixed and Epic is initialized empty (placeholder).
- Field/option IDs go stale only if the project is recreated or the Status options are rewritten outside Archetipo. In that case re-run `/archetipo-init`.
