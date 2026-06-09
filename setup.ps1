$ErrorActionPreference = "Stop"

$TEMPLATE_REPO = "https://github.com/techreloaded-ar/archetipo-workshop.git"
$DEFAULT_DIR = "archetipo-workshop"

$Backends = @(
    @{ Name = "File"; Key = "file" }
    @{ Name = "GitHub Projects"; Key = "github" }
)

$Tools = @(
    @{ Name = "Claude Code";    Key = "claude" }
    @{ Name = "Codex";          Key = "codex" }
    @{ Name = "Gemini CLI";     Key = "gemini" }
    @{ Name = "OpenCode";       Key = "opencode" }
    @{ Name = "GitHub Copilot"; Key = "copilot" }
)

Write-Host ""
Write-Host "========================================="
Write-Host "  Archetipo Workshop — Setup"
Write-Host "========================================="
Write-Host ""

# --- Prerequisiti ---

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git non e' installato. Installalo prima di continuare."
    exit 1
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js non e' installato. Installalo prima di continuare."
    exit 1
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Error "npm non e' installato. Installalo prima di continuare."
    exit 1
}

# --- Verifica / auto-install CLI globale archetipo ---

$archetipoCmd = Get-Command archetipo -ErrorAction SilentlyContinue

if (-not $archetipoCmd) {
    Write-Host ""
    Write-Host "La CLI globale 'archetipo' non e' trovata nel PATH. Tentativo di installazione automatica..." -ForegroundColor Yellow
    Write-Host ""
    npm install -g @techreloaded/archetipo
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Installazione fallita." -ForegroundColor Red
        Write-Host ""
        Write-Host "Prova manualmente:"
        Write-Host "  npm config set prefix $env:APPDATA\npm"
        Write-Host "  npm install -g @techreloaded/archetipo"
        Write-Host ""
        Write-Host "Poi rilancia questo script."
        exit 1
    }

    $archetipoCmd = Get-Command archetipo -ErrorAction SilentlyContinue
    if (-not $archetipoCmd) {
        Write-Host ""
        Write-Host "Installazione completata ma 'archetipo' non e' ancora nel PATH." -ForegroundColor Red
        Write-Host ""
        Write-Host "Aggiungi il bin path di npm al tuo PATH:"
        Write-Host "  `$env:Path += `";`$(npm config get prefix)\bin`""
        Write-Host ""
        Write-Host "Poi rilancia questo script."
        exit 1
    }
}

$version = & archetipo --version 2>$null
Write-Host ""
Write-Host "  archetipo $version" -ForegroundColor Green

# --- Menu interattivi ---

function Show-Menu {
    param([array]$Options)
    $selected = @($false) * $Options.Count
    $cursor = 0

    while ($true) {
        Clear-Host
        Write-Host "Seleziona strumenti (Spazio = seleziona, Invio = conferma):" -ForegroundColor Cyan
        Write-Host ""
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $mark = if ($selected[$i]) { "[x]" } else { "[ ]" }
            if ($i -eq $cursor) {
                Write-Host "  > $mark $($Options[$i].Name)" -ForegroundColor Yellow
            } else {
                Write-Host "    $mark $($Options[$i].Name)"
            }
        }
        Write-Host ""
        Write-Host "Frecce su/giu per navigare, Spazio per selezionare, Invio per confermare." -ForegroundColor DarkGray

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($key.VirtualKeyCode) {
            38 { if ($cursor -gt 0) { $cursor-- } }
            40 { if ($cursor -lt $Options.Count - 1) { $cursor++ } }
            32 { $selected[$cursor] = -not $selected[$cursor] }
            13 { return $selected }
        }
    }
}

function Show-SingleChoiceMenu {
    param(
        [array]$Options,
        [string]$Title
    )

    $cursor = 0

    while ($true) {
        Clear-Host
        Write-Host $Title -ForegroundColor Cyan
        Write-Host ""
        for ($i = 0; $i -lt $Options.Count; $i++) {
            if ($i -eq $cursor) {
                Write-Host "  > $($Options[$i].Name)" -ForegroundColor Yellow
            } else {
                Write-Host "    $($Options[$i].Name)"
            }
        }
        Write-Host ""
        Write-Host "Frecce su/giu per navigare, Invio per confermare." -ForegroundColor DarkGray

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($key.VirtualKeyCode) {
            38 { if ($cursor -gt 0) { $cursor-- } }
            40 { if ($cursor -lt $Options.Count - 1) { $cursor++ } }
            13 { return $Options[$cursor] }
        }
    }
}

# --- Selezione cartella progetto e remote ---

$PROJECT_DIR = Read-Host "Nome cartella progetto [$DEFAULT_DIR]"
if ([string]::IsNullOrWhiteSpace($PROJECT_DIR)) {
    $PROJECT_DIR = $DEFAULT_DIR
}

if (Test-Path $PROJECT_DIR) {
    Write-Error "La directory '$PROJECT_DIR' esiste gia'."
    exit 1
}

$REMOTE_URL = Read-Host "URL del tuo repository remoto"
if ([string]::IsNullOrWhiteSpace($REMOTE_URL)) {
    Write-Error "L'URL remoto non puo' essere vuoto."
    exit 1
}

# --- Selezione backend backlog ---

$selectedBackend = Show-SingleChoiceMenu -Options $Backends -Title "Seleziona backend backlog:"

if ($selectedBackend.Key -eq "github") {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI (gh) non e' installata. Installala e autenticala con 'gh auth login'."
        exit 1
    }

    Write-Host ""
    Write-Host "Verifica autenticazione e scope GitHub Projects..." -ForegroundColor Yellow
    $ghApiOutput = & gh api -i user 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERRORE: GitHub CLI non e' autenticata. Esegui:" -ForegroundColor Red
        Write-Host "  gh auth login" -ForegroundColor Cyan
        Write-Host "  gh auth refresh -s read:project -s project" -ForegroundColor Cyan
        Write-Host "Poi RILANCIA questo script di installazione." -ForegroundColor Yellow
        exit 1
    }
    $scopeLine = ($ghApiOutput | Where-Object { $_ -match '^X-Oauth-Scopes:' }) | Select-Object -First 1
    if ($scopeLine) {
        $scopes = $scopeLine -replace '^X-Oauth-Scopes:\s*', ''
        $hasWriteProject = ($scopes -split ',\s*') | Where-Object { $_.Trim() -eq 'project' }
        if (-not $hasWriteProject) {
            Write-Host ""
            Write-Host "ERRORE: Il token GitHub non ha lo scope di scrittura 'project', necessario per creare il GitHub Project v2." -ForegroundColor Red
            Write-Host "(Lo scope attuale consente solo la lettura: la creazione del progetto fallirebbe.)" -ForegroundColor Red
            Write-Host ""
            Write-Host "Esegui:" -ForegroundColor Yellow
            Write-Host "  gh auth refresh -s read:project -s project" -ForegroundColor Cyan
            Write-Host "Verifica con quale account sei autenticato (se ne hai piu' di uno):" -ForegroundColor Yellow
            Write-Host "  gh auth status        # eventualmente: gh auth switch" -ForegroundColor Cyan
            Write-Host "Poi RILANCIA questo script di installazione." -ForegroundColor Yellow
            exit 1
        }
    }
    # Se l'header non e' leggibile si prosegue (rete di sicurezza)
}

# --- Selezione strumenti ---

$selectedFlags = Show-Menu -Options $Tools
$selectedTools = @()
for ($i = 0; $i -lt $Tools.Count; $i++) {
    if ($selectedFlags[$i]) { $selectedTools += $Tools[$i] }
}

if ($selectedTools.Count -eq 0) {
    Write-Host ""
    Write-Host "Nessuno strumento selezionato. Uscita." -ForegroundColor Yellow
    exit 0
}

Clear-Host
Write-Host ""

# --- Clone template ---

Write-Host "Clono il template in '$PROJECT_DIR'..."
git clone $TEMPLATE_REPO $PROJECT_DIR

Push-Location $PROJECT_DIR
try {
    # --- Pulizia asset template obsoleti ---

    Write-Host ""
    Write-Host "Installazione Archetipo in: $((Get-Location).Path)" -ForegroundColor Green
    Write-Host "Backend backlog: $($selectedBackend.Name)" -ForegroundColor Green
    Write-Host ""

    Write-Host "Pulizia asset template obsoleti..."
    Remove-Item -Path "backend" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path ".archetipo" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "setup.ps1" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "setup.sh" -Force -ErrorAction SilentlyContinue

    # --- Reinizializza git ---

    Write-Host "Reinizializzo la storia git..."
    Remove-Item -Path ".git" -Recurse -Force
    git init -b main

    Write-Host "Imposto il remote origin: $REMOTE_URL"
    git remote add origin $REMOTE_URL

    # --- Esegui archetipo init ---

    $toolFlatArgs = @()
    foreach ($tool in $selectedTools) {
        $toolFlatArgs += @("--tool", $tool.Key)
    }

    Write-Host ""
    Write-Host "Eseguo archetipo init..."
    Write-Host "  archetipo init --connector $($selectedBackend.Key) --yes $($toolFlatArgs -join ' ')"
    & archetipo init --connector $selectedBackend.Key --yes @toolFlatArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "archetipo init fallito."
        exit 1
    }

    # --- Per GitHub: archetipo config show ---

    if ($selectedBackend.Key -eq "github") {
        Write-Host ""
        Write-Host "Configuro GitHub Project via archetipo config show..."
        & archetipo config show
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "ERRORE: archetipo config show fallito." -ForegroundColor Red
            Write-Host "Causa probabile: token senza scope 'project' oppure account senza permessi sull'owner di destinazione." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Comandi di diagnosi/fix:" -ForegroundColor Yellow
            Write-Host "  gh auth status" -ForegroundColor Cyan
            Write-Host "  gh auth refresh -s read:project -s project   # eventuale: gh auth switch" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Il progetto e' gia' stato inizializzato. NON rilancia lo script." -ForegroundColor Yellow
            Write-Host "Riprendi dall'interno della cartella progetto:" -ForegroundColor Yellow
            Write-Host "  cd $PROJECT_DIR" -ForegroundColor Cyan
            Write-Host "  archetipo config show" -ForegroundColor Cyan
            Write-Host "  git add -A" -ForegroundColor Cyan
            Write-Host "  git commit -m ""Initial commit from archetipo-workshop""" -ForegroundColor Cyan
            Write-Host "  git push -u origin main" -ForegroundColor Cyan
            exit 1
        }
    }

    # --- Commit iniziale ---

    Write-Host ""
    Write-Host "Commit iniziale..."
    git add -A
    git commit -m "Initial commit from archetipo-workshop"

    Write-Host "Push verso il nuovo remote..."
    git push -u origin main
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Fatto! Il progetto e' pronto in '.\$PROJECT_DIR'" -ForegroundColor Green
Write-Host "Remote origin: $REMOTE_URL"
Write-Host ""
Write-Host "Prossimi passi:"
Write-Host "  cd $PROJECT_DIR"
Write-Host "  cp .env.example .env  # configura le variabili d'ambiente"
Write-Host "  npm install"
Write-Host "  npm run dev"
Write-Host ""
