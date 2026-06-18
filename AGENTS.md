# AGENTS.md — Archetipo Workshop

## Stack
- **Next.js 15** (App Router, `src/` directory, Turbopack dev)
- **SQLite** via **Prisma** per il database; auth custom email/password (sessioni su DB, cookie httpOnly) — niente servizi esterni.
- **Tailwind CSS v4** with `@tailwindcss/postcss`
- **shadcn/ui** for UI components

## File Structure
```
src/
  app/
    layout.tsx          # Root layout (Geist font, globals.css)
    page.tsx            # Home page (server component)
    providers.tsx       # Client wrapper (extensible)
    globals.css         # Tailwind + shadcn CSS vars
    dashboard/
      page.tsx          # Protected page (middleware guards)
    auth/
      signin/page.tsx   # Sign-in page (email/password)
      signout/route.ts  # POST handler for sign out
    api/
      hello/route.ts    # Example API route (GET + POST)
      auth/
        signup/route.ts # POST handler for sign up
        signin/route.ts # POST handler for sign in
  components/ui/        # shadcn/ui components
  lib/
    utils.ts            # cn() utility (shadcn)
    prisma.ts           # Prisma client singleton
    auth.ts              # hashPassword, verifyPassword, createSession, getCurrentUser, destroySession
  middleware.ts          # Protects /dashboard checking the "session" cookie
prisma/
  schema.prisma         # User model (id, email, passwordHash, name, image) + Session model
```

## Common Tasks

### Add a shadcn/ui component
```bash
npx shadcn@latest add <component-name>
```

### Extend the Prisma schema
1. Edit `prisma/schema.prisma`
2. Run `npx prisma db push`
3. Use `prisma` from `@/lib/prisma` to query

### Query with Prisma
```ts
import { prisma } from "@/lib/prisma";
const users = await prisma.user.findMany();
```

### Auth Patterns

**Server Component / Route Handler**:
```ts
import { getCurrentUser } from "@/lib/auth";
const user = await getCurrentUser(); // User | null
```

**Sign up / Sign in**: i client chiamano via `fetch` i route handler `POST /api/auth/signup` e
`POST /api/auth/signin` con `{ email, password }`. Entrambi creano la sessione su DB e impostano
il cookie httpOnly `session` tramite `createSession()`.

**Sign out**: `destroySession()` elimina la sessione corrente dal DB e cancella il cookie.

## Environment Variables
- `DATABASE_URL` — connection string SQLite (es. `file:./dev.db`)

## Archetipo Skills — Boilerplate Constraints

This project ships with a fully configured boilerplate. The skills `/archetipo-inception` and `/archetipo-spec` **must** respect the existing implementation described above.

### Constraint for `archetipo-inception` (Phase 2 — Technical Architecture)

When Leonardo (Architect) proposes the technical architecture:

- **Mandate the existing stack** — the base technology choices are not up for discussion:
  - Next.js 15 (App Router, `src/` directory, Turbopack dev)
  - SQLite via Prisma + auth custom email/password
  - Tailwind CSS v4 with `@tailwindcss/postcss`
  - shadcn/ui for UI components
- **Explain why** when presenting the stack: *"This project uses an existing boilerplate with auth, database, and UI already configured. Rebuilding would waste time and introduce inconsistencies."*
- **Additions are welcome** — Leonardo may propose new libraries, APIs, external services, or tools on top of the base stack, but must never replace or contradict it.
- **Pre-fill** the Technology Stack table in the PRD with the boilerplate values listed above.

### Constraint for `archetipo-inception` and `archetipo-spec` (Requirements & Stories)

The following features are **already implemented** in the boilerplate. Agents must not generate functional requirements or user stories that recreate them:

- Email/password authentication (sign up, sign in)
- Session management middleware checking the "session" cookie (route protection for `/dashboard`)
- User model (`UUID`, `email`, `passwordHash`, `name`, `image`) + `Session` model
- Dashboard page (protected, displays user profile)
- Home page with auth-aware content
- shadcn/ui integration + Tailwind design tokens (`globals.css`)
- API route scaffold (`/api/hello`)

When generating FRs or user stories:

- **Skip** anything fully covered by the boilerplate list above.
- If a requirement **extends** an existing feature (e.g., "add profile editing"), reference the existing implementation as the starting point instead of recreating it.
- Mark any story that builds on boilerplate features with: **"Extends existing boilerplate: [feature]"**.
