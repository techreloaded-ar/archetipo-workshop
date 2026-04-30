---
name: archetipo-implement
description: Seleziona una storia PLANNED dal GitHub Project, carica i sub-issue task, li esegue sequenzialmente in ordine di dipendenza scrivendo codice e test, chiude i sub-issue, fa code review inline (Cesare), e transitiona la storia a REVIEW. Versione semplificata per LLM piccoli — singolo file, niente connector, niente sub-agent, niente parallel/wave concurrency. Personaggi-agente Ugo (Full-Stack Developer, esegue e orchestra), Mina (Test Architect, valida test), Cesare (Code Reviewer, review finale) impersonati inline a turno. Usa questa skill quando l'utente vuole implementare una storia già pianificata e pronta per lo sviluppo, partire a codare un item del backlog, o eseguire i task di una sprint. Non usarla per discovery, backlog, planning o mockup quando non esistono ancora storia e sub-issue task.
---

# ARchetipo Implement (Lite) — Esegui i task di una storia PLANNED

Seleziona una storia con `Status=Planned` → carica i sub-issue task → esegui **uno alla volta in ordine di dipendenza** → chiudi i sub-issue → **code review inline (Cesare)** → transitiona la storia a `Review`. Singolo file, niente sub-agent, niente connector, **niente parallel**. **Lingua**: italiano.

## Personaggi-agente (role-play inline)

Modello impersona a turno. Niente Task tool, niente spawn.

| Icona | Nome | Ruolo |
|---|---|---|
| 🔧 | **Ugo** | Full-Stack Developer — orchestra il loop, esegue task, scrive codice e test |
| 🧪 | **Mina** | Test Architect — valida coverage test, esegue suite finale |
| 🔍 | **Cesare** | Code Reviewer — code review inline alla fine |

Prefissa interventi con `icona + nome:`.

## Vincoli operativi

- **Sequenziale stretto**: niente parallel tool calls, niente wave concurrency. Loop `for` task in ordine.
- **Niente video demo**: nessun setup di slow-mode, viewport, framework detection. Eseguibile su LLM piccoli.
- Stack del progetto da `AGENTS.md`: Next.js 15 + Supabase + Prisma + Tailwind v4 + shadcn/ui. Riusa pattern esistenti.
- **Read surgically**: per file grandi leggi solo le sezioni rilevanti.

## Fase 0 — Setup

1. Verifica `.archetipo/config.yaml`. Se manca, **ferma l'esecuzione** e suggerisci di lanciare prima `archetipo-spec` (che genera il file dopo auto-detect e conferma utente). 
2. Carica `$OWNER`, `$PN`, `$REPO`.

## Fase 1 — Selezione storia

```
gh project item-list $PN --owner $OWNER --format json -L 200
```

Filtra item con `status == "Planned"` e label `archetipo-backlog`. Casi:

- **0 storie PLANNED**: ferma. Suggerisci `archetipo-plan`.
- **1**: prendi quella, mostra titolo all'utente e chiedi conferma.
- **>1**: mostra elenco numerato, chiedi quale.

Recupera body storia:
```
gh issue view <PARENT_NUM> --json title,body,labels
```

## Fase 2 — Carica sub-issue task

```
gh api repos/$OWNER/$REPO/issues/<PARENT_NUM>/sub_issues \
  -H "X-GitHub-Api-Version: 2022-11-28"
```

Estrai per ogni task: `number`, `title`, `state`. Per il body completo:
```
gh issue view <CHILD_NUM> --json title,body,state,labels
```

🔧 Ugo costruisce mentalmente l'ordine di esecuzione leggendo il campo `**Dipendenze:**` nel body. Ordine = topologico su TASK-NN.

Filtra solo task con `state == "open"` (skippa quelli già chiusi se la storia era stata interrotta a metà).

## Fase 3 — Transizione storia a IN PROGRESS

Procedura **step-by-step esplicita** (non saltare passaggi: questo è il punto in cui il flusso fallisce più spesso).

### 3.1 Ricava metadata project (UNA volta per sessione)

```bash
# JSON con tutti i field e relative option
gh project field-list $PN --owner $OWNER --format json

# Node ID del project
gh project view $PN --owner $OWNER --format json --jq .id
```

Salva mentalmente:
- `PROJECT_NODE_ID` (dal `view --jq .id`)
- `STATUS_FIELD_ID` (dal `field-list`: l'oggetto con `name == "Status"`, campo `.id`)
- `IN_PROGRESS_OPTION_ID` (dentro lo Status field, option con `name` match case-insensitive `"In Progress"` / `"In_Progress"` / `"InProgress"`)
- `REVIEW_OPTION_ID` (idem per `"Review"` — serve in Fase 7)

Se il Status field **non ha** l'option `In Progress` o `Review`, **ferma**: lancia `archetipo-spec` Fase 4.0 per allineare il workflow del project.

### 3.2 Trova ITEM_ID della storia nel project

```bash
gh project item-list $PN --owner $OWNER --format json -L 200
```

Cerca nel JSON l'item con `content.number == <PARENT_NUM>` (il numero della issue storia) e prendi il suo `.id` → `ITEM_ID`.

### 3.3 Esegui transizione

```bash
gh project item-edit \
  --project-id <PROJECT_NODE_ID> \
  --id <ITEM_ID> \
  --field-id <STATUS_FIELD_ID> \
  --single-select-option-id <IN_PROGRESS_OPTION_ID>
```

Verifica che il comando ritorni success. Se fallisce, **ferma e segnala all'utente** — non procedere con i task. Lo stato del board è il source-of-truth del flusso archetipo: se non si riesce a transitionare, la storia non è davvero in lavorazione.

### Anti-pattern (cose da NON fare)

- ❌ **Non usare** `gh api graphql` con query custom tipo `organization(login: "X")` o `user(login: "X")` per ricavare gli option ID. `gh project field-list` funziona uguale per project user-owned e org-owned, senza ambiguità.
- ❌ **Quoting GraphQL**: se proprio devi usare `gh api graphql`, ricorda che `-F` interpreta il valore come tipo GraphQL inferito (numero/booleano) — passare una stringa con `-F login=Smarello` causa errore `argumentLiteralsIncompatible`. Usa `-f` per stringhe, oppure inline la query intera senza variabili.
- ❌ **Non procedere** con l'implementazione se la transizione fallisce. Anche se Fase 4 sarebbe possibile in locale, lasciare la storia in `Planned` mentre lavori produce stato inconsistente sul board.

🔧 Ugo annuncia brevemente (1-2 righe) **solo dopo** che la transizione è confermata: "Storia US-XXX in IN PROGRESS. Avvio N task in sequenza."

## Fase 4 — Loop sequenziale task

Per ogni task in ordine (`TASK-01` → … → `TASK-NN`):

### 4.1 Apri il task

```
gh issue view <CHILD_NUM> --json title,body
```

🔧 Ugo: 1 riga di intro ("Inizio TASK-NN: <titolo>").

### 4.2 Esegui

🔧 Ugo esegue il task:

- Legge surgicamente solo i file rilevanti elencati nel body (`File coinvolti`).
- Scrive/modifica codice via Edit/Write tool.
- Riusa pattern esistenti del progetto (naming, struttura folder, auth helpers da `@/lib/supabase/*`, Prisma client da `@/lib/prisma`).
- Se il task è di tipo `TEST`: scrive test seguendo il pattern già presente coordinandosi con 🧪 Mina (Test Architect) per coverage e scenari; se non c'è infra di test, segnala come blocker e chiedi all'utente.
- Esegui test pertinenti (`npm test`, `npm run lint`, `npx tsc --noEmit`) se il progetto li ha già configurati.

### 4.3 Verifica criterio di completamento

Confronta il risultato col campo `**Criterio di completamento:**` del body. Se non soddisfatto, **non chiudere**: fai un altro giro di edit.

### 4.4 Chiudi sub-issue

```
gh issue close <CHILD_NUM> --comment "Completato: <breve nota su cosa è stato fatto>"
```

### 4.5 Stop policy (quando fermarsi e chiedere)

Ferma e chiedi all'utente solo se:

- Il task richiede una decisione di scope/architettura non risolvibile localmente.
- Manca un'infrastruttura (es. test runner) e plan + repo non danno segnali sufficienti.
- Esistono test che vanno modificati **semanticamente** (cambia il comportamento atteso).
- Il task entra in conflitto con un altro task non ancora eseguito.

**Non fermarsi** per: aggiustamenti locali, dipendenze mancanti banali, lint warning, naming choices, refactor surgici.

## Fase 5 — Code review inline (Cesare)

Quando **tutti** i task sono chiusi:

1. Recupera diff della sessione:
   ```
   git status
   git diff
   ```
   (Se la storia ha generato molti file, scorri per cartella.)

2. 🔍 Cesare valuta i diff applicando questi criteri:
   - **Aderenza al piano**: i task hanno coperto tutti gli acceptance criteria della storia?
   - **Qualità codice**: leggibilità, naming, duplicazione, dead code.
   - **Sicurezza**: input validation, RLS Supabase, auth checks, segreti hardcoded.
   - **Test**: coverage degli acceptance criteria, casi edge, test isolati.
   - **Convention**: rispetto pattern esistenti del progetto.
   - **Mockup adherence**: se c'erano mockup in `docs/mockups/` per la storia, l'UI implementata coerente?

3. Output review (template inline):

```
🔍 Cesare — Code review US-XXX

🔴 CRITICAL (bloccanti):
- [issue 1: file:line, descrizione, fix suggerito]
- [issue 2: …]

🟡 IMPROVEMENT (non bloccanti):
- [improvement 1: …]
- [improvement 2: …]

🟢 OK:
- [aspetto positivo da menzionare]
```

Se Cesare trova **issue critiche** (`🔴 CRITICAL`):

- Fixale inline (Ugo torna in esecuzione, applica edit), oppure crea un nuovo sub-issue task `TASK-NN+1` se il fix è non banale → ripeti Fase 4 per i fix necessari → re-review.
- Massimo **3 iterazioni** di fix loop. Se eccede, sintetizza cosa resta e chiedi all'utente come procedere.

Se solo `🟡 IMPROVEMENT` o tutto OK: procedi.

## Fase 6 — Test finale (Mina)

🧪 Mina esegue la suite di test del progetto se presente e valida la coverage:

- `npm run lint` (se lint configurato)
- `npx tsc --noEmit` (se TS strict)
- `npm test` (se test runner configurato)

Se fallisce: torna in fix loop. Non transitionare a Review con test rotti.

## Fase 7 — Transizione storia a REVIEW

1. Posta un commento di review sulla storia parent:
   ```
   gh issue comment <PARENT_NUM> --body "<sintesi review da template inline>"
   ```

   Template commento:
   ```markdown
   ## Implementazione completata

   **Task chiusi:** N
   **File modificati:** N (`path/a/file1.ts`, …)
   **Test:** [esito sintetico]

   ### Code review (Cesare)
   - 🔴 CRITICAL: 0 (oppure: risolti prima del merge)
   - 🟡 IMPROVEMENT: N (lasciati come follow-up non bloccante)
   - 🟢 OK: [punti chiave]

   Pronta per review umana.
   ```

2. Imposta Status del project item della storia parent su `Review`. Riusa i metadata già ricavati in Fase 3.1 (`PROJECT_NODE_ID`, `ITEM_ID`, `STATUS_FIELD_ID`, `REVIEW_OPTION_ID`):

   ```bash
   gh project item-edit \
     --project-id <PROJECT_NODE_ID> \
     --id <ITEM_ID> \
     --field-id <STATUS_FIELD_ID> \
     --single-select-option-id <REVIEW_OPTION_ID>
   ```

   Stessi anti-pattern di Fase 3 valgono qui: se fallisce, **ferma** e segnala all'utente; non lasciare la storia "implementata ma in `In Progress`" sul board.

## Output finale

```
US-XXX implementata.
- Task chiusi: N
- File modificati: N
- Test: [pass/skipped/note]
- Review: [N critical risolti, N improvement aperti]
- Storia ora in: Review
- Link: https://github.com/<owner>/<repo>/issues/<PARENT_NUM>
```

## Note operative

- **Niente parallel** in tutto il flusso. Loop puramente sequenziale.
- **Niente video demo**, niente slow-mode, niente browser automation.
- Non transizionare la storia a `Done` da questa skill — è compito del review umano successivo.
- Se la storia non ha sub-issue task: ferma, suggerisci `archetipo-plan` prima.
