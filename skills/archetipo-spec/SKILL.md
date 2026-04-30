---
name: archetipo-spec
description: Trasforma docs/PRD.md in un backlog di epic e user story creando label, issue GitHub e item nel project board via gh CLI. Versione semplificata per LLM piccoli — singolo file, niente connector, niente sub-agent. Personaggi-agente Emanuele (Requirements Analyst) e Andrea (PM) impersonati inline. Auto-detect di owner e project number, scrive .archetipo/config.yaml dopo conferma. Usa questa skill quando l'utente vuole bootstrap del backlog da un PRD esistente, generare epic e storie su GitHub Projects, o aggiungere nuove storie a un backlog esistente. Non usarla per discovery/PRD (usa archetipo-inception), planning (usa archetipo-plan) o implementazione (usa archetipo-implement).
---

# ARchetipo Spec (Lite) — Backlog su GitHub

Leggi `docs/PRD.md` → estrai epic + storie → crea label, issue e project items su GitHub via `gh` CLI inline. Singolo file, niente sub-agent, niente connector.

## Personaggi-agente (role-play inline)

| Icona | Nome | Ruolo |
|---|---|---|
| 🔎 | **Emanuele** | Requirements Analyst — decompone PRD in epic + storie, acceptance criteria |
| 💎 | **Andrea** | Product Manager — prioritizza, story points, ordine |

Prefissa interventi con `icona + nome:`. Niente Task tool.

## Fase 0 — Setup config

1. Verifica esistenza di `.archetipo/config.yaml`. Schema atteso:
   ```yaml
   github:
     owner: <login utente o org>
     project_number: <numero progetto>
   ```
2. Se manca:
   - `gh repo view --json owner,name,nameWithOwner` → ricava `owner.login`.
   - `gh project list --owner <owner> --format json` → mostra all'utente la lista dei project; chiede quale usare (numero).
   - Mostra all'utente i valori dedotti e chiedi conferma.
   - Dopo conferma: scrivi `.archetipo/config.yaml` con i due campi.

In tutto il flusso usa `$OWNER` e `$PN` come placeholder per i valori letti.

## Fase 1 — Lettura PRD

1. Leggi `docs/PRD.md`. Se non esiste, fermati e suggerisci `archetipo-inception`.
2. 🔎 Emanuele estrae silenziosamente: nome prodotto, vision, personas, scope MVP, FR-XXX, eventuali nice-to-have.

## Fase 2 — Decomposizione (Emanuele)

🔎 Emanuele identifica **epic** (raggruppamenti di valore coerenti):

- Min 2 epic, max ~6 per MVP.
- Ogni epic mappa a ≥1 FR del PRD.
- Ordine: MVP first.
- ID sequenziali: `EP-001`, `EP-002`, …

Per ogni epic, genera **user story** verticali. Format base:

- "Come [persona], voglio [azione], così [beneficio]"
- 2-5 acceptance criteria per storia
- ID sequenziali: `US-001`, `US-002`, …

### Checklist INVEST (applica a ogni storia)

- **I**ndependent — niente dipendenze cross-epic; dentro lo stesso epic solo `Blocked by` espliciti e giustificati.
- **N**egotiable — descrivi il *cosa*, non il *come*. Niente nomi di componenti, librerie o API specifiche nel body della storia.
- **V**aluable — il campo `Demonstrates` (vedi sotto) deve mostrare un incremento osservabile per la persona, non un task tecnico.
- **E**stimable — se non riesci a stimare in 1–5 SP, **splitta** usando SPIDR:
  - **P**ath (split per percorso utente: happy path prima, error path dopo)
  - **I**nterface (split per piattaforma/canale: web prima, mobile dopo)
  - **D**ata (split per tipologia di dato: 1 tipo prima, altri dopo)
  - **R**ules (split per regola di business: regola base prima, eccezioni dopo)
- **S**mall — 1–5 SP. **≥8 SP = split obbligatorio**, mai una storia da 8 nel backlog.
- **T**estable — gli acceptance criteria devono essere verificabili senza ambiguità (no "il sistema funziona bene", sì "il form rifiuta email senza @ con messaggio X").

**Salta tutto ciò già coperto dal boilerplate** (auth, OAuth, user sync, dashboard, ecc. — vedi `AGENTS.md`). Se una storia estende boilerplate, scrivilo nel body.

## Fase 3 — Prioritizzazione (Andrea)

💎 Andrea assegna priority a ogni storia:

| Priority | Criterio |
|---|---|
| HIGH | MVP, capability bloccante, primo incremento di un epic |
| MEDIUM | MVP non-bloccante, o Growth con valore strategico |
| LOW | Nice-to-have, vision, low impact |

Andrea propone l'ordine. Mostra all'utente il piano riepilogativo (tabella epic + count storie + priority breakdown) e chiedi conferma prima di creare nulla su GitHub.

## Fase 4 — Creazione GitHub

### 4.0 Setup Status field del project (workflow Archetipo)

Il flusso Archetipo richiede 5 stati specifici sul Status field: `Todo`, `Planned`, `In Progress`, `Review`, `Done`. Il default GitHub è `Todo / In Progress / Done` — vanno aggiunti `Planned` e `Review`.

1. Recupera metadata field:
   ```
   gh project field-list $PN --owner $OWNER --format json
   ```
2. Trova il field `Status` (presente di default su ogni project) ed estrai:
   - `STATUS_FIELD_ID`
   - elenco option correnti (name + id)
3. Confronta con i 5 stati attesi (case-insensitive). Se la lista è esattamente `Todo / Planned / In Progress / Review / Done`, **skip**.
4. Se mancano option, **mostra all'utente** lo stato attuale del field e i 5 stati attesi, chiedi conferma prima di sovrascrivere (la mutation seguente **rimpiazza tutte le option**, anche quelle esistenti).
5. Dopo conferma esegui:
   ```
   gh api graphql -f query='
     mutation($f:ID!,$opts:[ProjectV2SingleSelectFieldOptionInput!]!){
       updateProjectV2Field(input:{fieldId:$f, singleSelectOptions:$opts}){
         projectV2Field {
           ... on ProjectV2SingleSelectField { id options { id name } }
         }
       }
     }' \
     -f f=$STATUS_FIELD_ID \
     -f opts='[
       {"name":"Todo","color":"GRAY","description":""},
       {"name":"Planned","color":"BLUE","description":""},
       {"name":"In Progress","color":"YELLOW","description":""},
       {"name":"Review","color":"PURPLE","description":""},
       {"name":"Done","color":"GREEN","description":""}
     ]'
   ```
6. **Salva gli option ID** dal response — servono in `archetipo-plan` (TODO→PLANNED) e `archetipo-implement` (PLANNED→IN PROGRESS, →REVIEW). I successivi run riusano `gh project field-list`, quindi non è critico persisterli, ma menzionali nell'output finale per l'utente.

> ⚠️ Usa `-f` (stringa) per le variabili GraphQL — `-F` di `gh api` interpreta il valore come tipo GraphQL inferito (numero/booleano) e fallisce con `argumentLiteralsIncompatible` su stringhe arbitrarie.

### 4.1 Verifica/crea altri field custom del project

`gh project field-list $PN --owner $OWNER --format json` → controlla che esistano:

- **Priority** (SINGLE_SELECT): `HIGH`, `MEDIUM`, `LOW`.
- **Story Points** (NUMBER).
- **Epic** (SINGLE_SELECT): un'opzione per ogni epic generato.

Se mancano:
- `gh project field-create $PN --owner $OWNER --name "Priority" --data-type SINGLE_SELECT --single-select-options "HIGH,MEDIUM,LOW"`
- `gh project field-create $PN --owner $OWNER --name "Story Points" --data-type NUMBER`
- Per Epic: crea il field SINGLE_SELECT con tutte le opzioni `EP-XXX: Titolo` in un unico comando (le opzioni si possono passare separate da virgola).

### 4.2 Crea label

Per ogni epic, crea label `EP-XXX: Titolo`:
```
gh label create "EP-XXX: Titolo" --color C0C0C0 --description "Epic XXX" --force
```

Crea anche la label generica:
```
gh label create "archetipo-backlog" --color 0E8A16 --description "Storia generata da archetipo-spec" --force
```

### 4.3 Crea issue per ogni storia

Per ogni `US-XXX`:

1. Crea issue:
   ```
   gh issue create \
     --title "US-XXX: <titolo>" \
     --label "archetipo-backlog" --label "EP-XXX: <Titolo Epic>" \
     --body "<body dal template inline>"
   ```
2. Recupera node ID:
   ```
   gh issue view <NUM> --json id --jq .id
   ```
3. Aggiungi al project (GraphQL):
   ```
   gh api graphql -f query='mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,contentId:$c}){item{id}}}' -F p=<PROJECT_NODE_ID> -F c=<ISSUE_NODE_ID>
   ```
   Il `PROJECT_NODE_ID` lo recuperi una volta sola con:
   ```
   gh project view $PN --owner $OWNER --format json --jq .id
   ```
4. Imposta i field sull'item del project (usa `--id <ITEM_NODE_ID>` ricevuto dalla mutation):
   - Status = Todo: `gh project item-edit --project-id <PROJECT_NODE_ID> --id <ITEM_ID> --field-id <STATUS_FIELD_ID> --single-select-option-id <TODO_OPTION_ID>`
   - Priority: idem con field Priority e opzione HIGH/MEDIUM/LOW
   - Story Points: `--field-id <SP_FIELD_ID> --number <N>`
   - Epic: `--field-id <EPIC_FIELD_ID> --single-select-option-id <EP_XXX_OPTION_ID>`

   Field ID e option ID si ricavano una volta da `gh project field-list $PN --owner $OWNER --format json`.

### Template body storia

```markdown
## Storia
Come [persona], voglio [azione], così [beneficio].

## Demonstrates
[1-2 frasi che descrivono cosa l'utente FA concretamente dopo che la storia è completata, in linguaggio osservabile]

## Acceptance Criteria
- [ ] [criterio 1 osservabile e verificabile]
- [ ] [criterio 2]
- [ ] [criterio 3]

---
**Epic:** EP-XXX — [Titolo]
**Priority:** HIGH | **Story Points:** N
**Blocked by:** -
**Scope:** MVP
```

Sostituisci `[…]` coi contenuti reali. Se la storia estende boilerplate, aggiungi una riga finale: `**Estende boilerplate:** [feature]`.

#### Come scrivere `Demonstrates` (campo critico)

`Demonstrates` **non è un riassunto della storia**. È la **demo concreta** di cosa l'utente può fare dopo che la storia è in produzione, in 1–2 frasi, in linguaggio osservabile (azioni, schermate, output).

✅ **Buoni esempi:**
- "L'utente apre `/reports`, seleziona un range di date dal picker, clicca 'Esporta CSV' e riceve un file con le righe filtrate."
- "Un visitatore non autenticato vede il pulsante 'Accedi con Google' nella home, lo clicca, completa OAuth e atterra sulla dashboard col proprio nome visibile in alto a destra."
- "L'admin apre la lista utenti, filtra per ruolo 'editor', vede esattamente gli utenti corrispondenti senza ricarica pagina."

❌ **Cattivi esempi (da evitare):**
- "Funzionalità di export." → vago, nessuna azione utente.
- "L'utente può esportare i dati." → astratto, manca il "come".
- "Sistema di reporting funzionante." → tecnico, non centrato sull'utente.
- "Endpoint POST /api/reports implementato." → implementazione, non valore.

Test: leggendo il `Demonstrates`, qualcuno che non conosce il codice deve capire **cosa vedrebbe sullo schermo** dopo aver usato la feature.

## Modalità "extend backlog"

Se trovi storie già esistenti nel project (item con label `archetipo-backlog`), **non duplicarle**. Aggiungi solo le storie nuove e numera ripartendo dal max(US-XXX)+1. Idem per gli epic: riusa quelli esistenti se il nome combacia.

## Output finale

Stampa riepilogo:

```
Backlog creato.
- Epic: N
- Storie: N (HIGH: N, MEDIUM: N, LOW: N)
- Story points totali: N
- Project: https://github.com/orgs/<owner>/projects/<PN>
```

Suggerisci come prossimo passo: `archetipo-plan` per pianificare una storia TODO.

## Note

- Esegui i comandi `gh` **sequenzialmente**, una storia alla volta. Niente parallel tool calls.
- Se un comando fallisce (es. label già esistente con `--force`, o issue già presente), continua e segnala a fine flusso.
- Mai modificare file fuori da `.archetipo/config.yaml`.
