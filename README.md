# Archetipo Workshop

Questo è un workshop pratico in cui costruirai un prodotto digitale da zero usando l'AI come copilota e il framework [Archetipo](https://github.com/techreloaded-ar/archetipo) come guida metodologica. Il boilerplate di partenza include Next.js 15, SQLite via Prisma con auth email/password integrata, Tailwind CSS v4 e shadcn/ui: tutto già configurato per permetterti di concentrarti sul prodotto, non sull'infrastruttura.

## 🚀 Installazione Rapida

Esegui lo script di setup per il tuo sistema operativo. **Lo script fa tutto in automatico** — installa la CLI Archetipo, esegue `archetipo init`, configura il backlog e le skill.

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/techreloaded-ar/archetipo-workshop/main/setup.sh | bash
```

**Windows (PowerShell)**

```powershell
irm https://raw.githubusercontent.com/techreloaded-ar/archetipo-workshop/main/setup.ps1 | iex
```

Lo script ti chiederà:

1. nome della cartella del progetto;
2. strumenti AI sui quali installare le skill ufficiali di Archetipo.


Al termine entra nella cartella del progetto:

```bash
cd nome-cartella-progetto
```

Poi prosegui con la [Guida Setup](#guida-setup) qui sotto per completare la configurazione (variabili d'ambiente, dipendenze).

## Guida Setup

### Backend backlog disponibili

Il backlog è gestito su file locali (`.archetipo/`). Lo script configura automaticamente `connector: file`.

### Prerequisiti comuni

- **Node.js** v18+ installato ([nodejs.org](https://nodejs.org))
- **Git** installato

---

### 1. Configura le variabili d'ambiente

Copia il file di esempio (già pronto per SQLite, nessun servizio esterno):

```bash
cp .env.example .env
```

`.env` contiene solo `DATABASE_URL="file:./dev.db"`: il database SQLite viene creato
automaticamente in `prisma/dev.db` durante `npm install`.

---

### 2. Installa le dipendenze

```bash
npm install
```

Durante `npm install` viene eseguito anche `postinstall`, che genera il Prisma Client e sincronizza lo schema con il database. Non sono necessari altri comandi Prisma durante il setup iniziale.

---

### 3. Avvia il server di sviluppo

```bash
npm run dev
```

Apri [http://localhost:3000](http://localhost:3000) nel browser.

---

### 4. Testa il login

1. Vai su [http://localhost:3000/auth/signin](http://localhost:3000/auth/signin).
2. Registrati con email e password: vieni reindirizzato alla dashboard protetta.
3. Rifai logout e login con le stesse credenziali.



## Troubleshooting

### `archetipo` non viene trovato dopo l'installazione

- L'installazione globale di npm potrebbe non essere nel PATH.
- Su macOS/Linux: `export PATH="$(npm config get prefix)/bin:$PATH"`
- Su Windows: aggiungi la cartella bin di npm al PATH di sistema.
- In alternativa, installa con un node version manager come `nvm` o `fnm`.

### "Can't reach database server"

- Verifica che il file `.env` esista (`cp .env.example .env`).
- Verifica che `DATABASE_URL="file:./dev.db"` sia presente in `.env`.

### Dopo `npm install` compare un errore Prisma

- Verifica che `DATABASE_URL` in `.env` sia corretta.
- Prova a eseguire manualmente `npx prisma generate`.
- Se hai modificato `prisma/schema.prisma`, esegui `npm run db:push`.

## Deploy su Vercel

### 1. Prepara il repository

Assicurati che il codice sia pushato su GitHub e che il progetto faccia build correttamente in locale:

```bash
npm run build
```

### 2. Importa il progetto su Vercel

1. Vai su [vercel.com](https://vercel.com) e accedi con il tuo account GitHub.
2. Clicca **Add New -> Project**.
3. Seleziona il repository dalla lista e autorizza l'accesso se richiesto.
4. Vercel rileva automaticamente Next.js: lascia le impostazioni di default.

### 3. Configura le variabili d'ambiente

Prima di cliccare Deploy, aggiungi questa variabile nella sezione **Environment Variables**:

| Variabile | Valore |
|---|---|
| `DATABASE_URL` | `file:./dev.db` |

⚠️ SQLite usa il filesystem locale, che su Vercel (serverless) non è persistente: i dati vengono
azzerati a ogni deploy/scale. Questa versione light è pensata per uso locale; per la produzione
sostituisci `DATABASE_URL` con un database persistente (es. PostgreSQL o Turso/libSQL).

### 4. Clicca Deploy

Vercel eseguirà build e deploy. Al termine riceverai un URL pubblico, per esempio `https://tuo-progetto.vercel.app`.

### Troubleshooting Deploy

**Build fallisce con errore Prisma "Cannot find module"**

- Vercel deve generare il Prisma Client durante il build. Verifica che `postinstall` in `package.json` includa `prisma generate`.

**Le modifiche alle variabili d'ambiente non hanno effetto**

- Dopo aver modificato le env su Vercel, fai un **Redeploy** da **Deployments -> ultimo deploy -> Redeploy**.
