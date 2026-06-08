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

    & gh auth status > $null 2> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "GitHub CLI non e' autenticata. Esegui: gh auth login`nPoi: gh auth refresh -s read:project -s project"
        exit 1
    }

    Write-Host ""
    Write-Host "Verifica scope GitHub Projects..." -ForegroundColor Yellow
    & gh project list --limit 1 --format json > $null 2> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Mancano gli scope per GitHub Projects v2. Esegui: gh auth refresh -s read:project -s project"
        exit 1
    }
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

    $initArgs = @("init", "--connector", $selectedBackend.Key, "--yes")
    foreach ($tool in $selectedTools) {
        $initArgs += @("--tool", $tool.Key)
    }

    Write-Host ""
    Write-Host "Eseguo archetipo init..."
    Write-Host "  archetipo $($initArgs -join ' ')"
    & archetipo $initArgs
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
            Write-Error "archetipo config show fallito."
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
