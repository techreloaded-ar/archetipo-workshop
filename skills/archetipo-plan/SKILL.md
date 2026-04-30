---
name: archetipo-plan
description: Seleziona una storia TODO dal GitHub Project, la analizza inline (recap, soluzione tecnica, strategia di test, decomposizione task), crea sub-issue TASK-NN linkate alla storia via API GitHub sub_issues, e transitiona la storia a PLANNED. Versione semplificata per LLM piccoli — singolo file, niente connector, niente sub-agent. Personaggi-agente Emanuele (Requirements Analyst), Leonardo (Architect), Mina (Test Architect), Ugo (Full-Stack Developer) impersonati inline a turno. Niente mockup UI, niente file plan markdown locali — il piano vive solo come sub-issues. Usa questa skill quando l'utente vuole pianificare una storia esistente del backlog prima di implementarla. Non usarla per discovery (archetipo-inception), bootstrap backlog (archetipo-spec), mockup (archetipo-design) o implementazione (archetipo-implement).
---

# ARchetipo Plan (Lite) — Pianifica una storia TODO

Seleziona una storia con `Status=Todo` dal project → analizza inline → crea sub-issue `TASK-NN` linkate alla storia → transitiona la storia a `Planned`. Singolo file, niente sub-agent, niente connector. **Lingua**: italiano.

## Personaggi-agente (role-play inline)

Il modello impersona ciascuno **a turno**, in sequenza. Niente Task tool, niente spawn.

| Icona | Nome | Ruolo |
|---|---|---|
| 🔎 | **Emanuele** | Requirements Analyst — rilegge storia + acceptance criteria |
| 📐 | **Leonardo** | Architect — file da toccare, librerie, decisioni tecniche |
| 🧪 | **Mina** | Test Architect — strategia test, scenari e2e, edge case |
| 🔧 | **Ugo** | Full-Stack Developer — decompone in task ordinati con dipendenze |

Prefissa interventi con `icona + nome:`.

## Vincolo hard

**Niente mockup in questa skill.** Anche se la storia è UI-visibile, plan **non** disegna mockup né invoca `archetipo-design`. Se l'utente vuole un mockup, dovrà invocare `archetipo-design` separatamente.

**Niente file markdown locali.** Il piano vive **solo** come sub-issues su GitHub.

## Fase 0 — Setup

1. Verifica `.archetipo/config.yaml`:
   ```yaml
   github:
     owner: <login>
     project_number: <N>
   ```
   Se manca, **ferma l'esecuzione** e suggerisci di lanciare prima `archetipo-spec` (che genera il file dopo auto-detect e conferma utente). 

2. Carica `$OWNER` e `$PN` dal file. Recupera anche `$REPO` (`gh repo view --json name --jq .name`).

## Fase 1 — Selezione storia

```
gh project item-list $PN --owner $OWNER --format json -L 200
```

Filtra item con `status == "Todo"` e label `archetipo-backlog`. Casi:

- **0 storie TODO**: ferma. Suggerisci `archetipo-spec` o di muovere a Todo una storia esistente.
- **1 storia TODO**: prendi quella, mostra titolo all'utente e chiedi conferma.
- **>1 storia TODO**: mostra elenco numerato (titolo + epic + priority + story points), chiedi quale pianificare.

Recupera il body della storia:
```
gh issue view <NUM> --json number,title,body,labels --jq '{n:.number,t:.title,b:.body,l:[.labels[].name]}'
```

## Fase 2 — Analisi inline (sequenziale, no parallel)

Esegui in ordine, ogni personaggio dice la sua **prima di passare al successivo**:

### 2.1 🔎 Emanuele — Recap storia

1-2 righe: chi/cosa/perché + lista acceptance criteria estratti dal body.

### 2.2 📐 Leonardo — Soluzione tecnica

Carica context minimo:
- `AGENTS.md` per stack obbligatorio (già lo conosci: Next.js 15 + Supabase + Prisma + Tailwind v4 + shadcn/ui).
- `prisma/schema.prisma` per modello dati esistente.
- Struttura `src/` rilevante (route, lib, componenti) — leggi solo i file chiave, non l'intero tree.

Produce:
- **File da modificare/creare**: elenco path con motivazione (1 riga ciascuno).
- **Librerie/route/componenti** coinvolti (incluse aggiunte esterne se necessarie).
- **Decisioni tecniche**: 2-4 bullet sulle scelte non ovvie (es. "RLS Supabase invece di middleware", "server action vs route handler", "indici DB").

### 2.3 🧪 Mina — Strategia di test

- **Unit**: cosa va testato a livello di funzione/util.
- **Integration / API**: route handler, server action, Prisma queries.
- **E2E (high-level)**: 1-3 scenari user-flow che coprono il `Demonstrates` + edge case principali.
- **Edge case**: lista breve (auth scaduta, input vuoto, errore network, race condition se applicabile).

### 2.4 🔧 Ugo — Decomposizione task

Produce lista ordinata `TASK-01`, `TASK-02`, … con campi:

- **Titolo** (action-oriented, es. "Aggiungi modello Project a Prisma")
- **Tipo**: `IMPLEMENTATION` | `TEST` | `REVIEW`
- **Dipendenze**: ID di task precedenti, o `-`
- **Criterio di completamento**: 1 frase verificabile

Regole:
- Ogni task = una sessione di lavoro singola, indipendentemente verificabile.
- Ordine: lower layers first (DB → API → UI), test interlivellati (non tutti a fine).
- Dipendenze solo dentro la stessa storia (no cross-story).
- Se totale task > 15: avvisa l'utente che la storia è grossa, suggerisci split.
- Includi almeno 1 task `TEST` se la storia ha acceptance criteria osservabili.

## Fase 3 — Conferma utente

Prima di scrivere su GitHub, mostra il piano completo come tabella:

```
| ID      | Titolo                           | Tipo           | Dipendenze | Criterio |
|---------|----------------------------------|----------------|------------|----------|
| TASK-01 | …                                | IMPLEMENTATION | -          | …        |
| TASK-02 | …                                | TEST           | TASK-01    | …        |
```

Chiedi conferma. Se l'utente chiede modifiche, applicale prima di procedere.

## Fase 4 — Creazione sub-issue su GitHub

Per ogni task in ordine `TASK-01 → TASK-NN`:

### 4.1 Crea issue child

```
gh issue create \
  --title "TASK-NN: <titolo>" \
  --label "EP-XXX: <Titolo Epic>" \
  --body "<body dal template inline>"
```

Recupera child node ID:
```
gh issue view <CHILD_NUM> --json id --jq .id
```

### 4.2 Linka come sub-issue alla storia

```
gh api -X POST \
  repos/$OWNER/$REPO/issues/<PARENT_NUM>/sub_issues \
  -F sub_issue_id=<CHILD_DATABASE_ID> \
  -H "X-GitHub-Api-Version: 2022-11-28"
```

⚠️ `sub_issue_id` richiede il **database id numerico** dell'issue child (non il node id GraphQL). Recuperalo con:
```
gh api repos/$OWNER/$REPO/issues/<CHILD_NUM> --jq .id
```

### Template body sub-issue (inline)

```markdown
**Tipo:** IMPLEMENTATION | TEST | REVIEW
**Dipendenze:** TASK-XX, TASK-YY (oppure `-`)
**Storia parent:** #<PARENT_NUM>

## Cosa fare
[1-3 frasi: cosa va implementato/testato]

## File coinvolti
- `path/to/file.ts` — [motivo]

## Criterio di completamento
- [ ] [criterio osservabile e verificabile]
```

## Fase 5 — Transizione storia a PLANNED

Imposta lo Status della storia parent sul project board:

```
gh project item-edit \
  --project-id <PROJECT_NODE_ID> \
  --id <ITEM_NODE_ID_STORIA> \
  --field-id <STATUS_FIELD_ID> \
  --single-select-option-id <PLANNED_OPTION_ID>
```

Per recuperare `ITEM_NODE_ID` della storia parent:
```
gh project item-list $PN --owner $OWNER --format json -L 200 \
  --jq '.items[] | select(.content.number == <PARENT_NUM>) | .id'
```

`PROJECT_NODE_ID`, `STATUS_FIELD_ID`, `PLANNED_OPTION_ID` si ricavano una volta da `gh project view` e `gh project field-list`.

## Output finale

```
Piano creato per US-XXX: <titolo storia>
- Task creati: N (sub-issue #X, #Y, #Z, …)
- Storia transitionata a: Planned
- Link storia: https://github.com/<owner>/<repo>/issues/<PARENT_NUM>
```

Suggerisci come prossimo passo: `archetipo-implement` per eseguire i task.

## Note operative

- **Sequenziale**: niente parallel tool calls. Crea i sub-issue uno alla volta.
- Se un comando fallisce, fermati, segnala l'errore e non lasciare la storia in stato inconsistente.
- Se la storia è già `Planned` o oltre, avvisa l'utente e chiedi se vuole rigenerare il piano (richiede prima rimozione manuale dei sub-issue esistenti).
- Mai modificare codice applicativo (`src/`, `prisma/`, ecc.) in questa skill.
