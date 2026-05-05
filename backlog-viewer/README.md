# ARchetipo Viewer

Viewer Kanban statico per `docs/BACKLOG.md`.

## Avvio

1. Apri `index.html` con Chrome o Edge.
2. Premi `Apri progetto`.
3. Seleziona la cartella suggerita dal viewer. Di solito e la cartella superiore a `backlog-viewer`, per esempio `C:\Users\smare\repo\ws1`.

Dopo la prima autorizzazione, il viewer prova a riaprire automaticamente la stessa root di progetto. Se il browser revoca il permesso, chiede solo di riautorizzare la stessa cartella.

La pagina legge `docs/BACKLOG.md` e, quando presenti, i task da `docs/planning/US-XXX.md`.
Spostando una card via drag & drop, il Markdown viene aggiornato e salvato subito in `docs/BACKLOG.md`.
Il bottone `Salva` resta disponibile come fallback se il browser non riesce a persistere automaticamente una modifica.

Se `docs/BACKLOG.md` non esiste, il viewer mostra un messaggio e resta utilizzabile senza errori.

## Note browser

La persistenza diretta su file locale usa la File System Access API, disponibile nei browser Chromium recenti.
