$ErrorActionPreference = "Stop"

$TEMPLATE_REPO = "https://github.com/techreloaded-ar/archetipo-workshop.git"
$DEFAULT_DIR = "archetipo-workshop"
$BACKENDS = @(
    @{ Name = "File"; Key = "file"; SkillsPath = "backend\file\skills"; ViewerPath = "backend\file\archetipo-viewer" }
    @{ Name = "GitHub Projects"; Key = "github"; SkillsPath = "backend\github\skills"; ArchetipoPath = "backend\github\.archetipo" }
)

Write-Host ""
Write-Host "========================================="
Write-Host "  Archetipo Workshop — Setup"
Write-Host "========================================="
Write-Host ""

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git non e' installato. Installalo prima di continuare."
    exit 1
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js non e' installato. Installalo prima di continuare."
    exit 1
}

$Tools = @(
    @{ Name = "Claude Code";    SkillsPath = ".claude\skills" }
    @{ Name = "Codex";          SkillsPath = ".agents\skills" }
    @{ Name = "Gemini CLI";     SkillsPath = ".gemini\skills" }
    @{ Name = "OpenCode";       SkillsPath = ".opencode\skills" }
    @{ Name = "GitHub Copilot"; SkillsPath = ".github\skills" }
)

$ArchetipoSkills = @(
    "archetipo-design",
    "archetipo-implement",
    "archetipo-inception",
    "archetipo-plan",
    "archetipo-spec"
)

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

$selectedBackend = Show-SingleChoiceMenu -Options $BACKENDS -Title "Seleziona backend backlog:"

if ($selectedBackend.Key -eq "github") {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI (gh) non e' installata. Installala e autenticala con 'gh auth login'."
        exit 1
    }

    & gh auth status > $null 2> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "GitHub CLI non e' autenticata. Esegui: gh auth login"
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

# --- Copia .archetipo e skills ---

$DEST       = Resolve-Path $PROJECT_DIR
$SKILLS_SRC = Join-Path $DEST $selectedBackend.SkillsPath

Write-Host ""
Write-Host "Installazione Archetipo in: $DEST" -ForegroundColor Green
Write-Host "Backend backlog: $($selectedBackend.Name)" -ForegroundColor Green
Write-Host ""

if (-not (Test-Path $SKILLS_SRC)) {
    Write-Error "Cartella skills backend mancante: $SKILLS_SRC"
    exit 1
}

if ($selectedBackend.Key -eq "github") {
    $backendArchetipoPath = Join-Path $DEST $selectedBackend.ArchetipoPath
    $rootArchetipoPath = Join-Path $DEST ".archetipo"
    if (Test-Path $backendArchetipoPath) {
        Write-Host "Copia backend GitHub .archetipo → $rootArchetipoPath"
        if (Test-Path $rootArchetipoPath) {
            Remove-Item -Path $rootArchetipoPath -Recurse -Force
        }
        Copy-Item -Path $backendArchetipoPath -Destination $rootArchetipoPath -Recurse -Force
    }
} else {
    $viewerSrc = Join-Path $DEST $selectedBackend.ViewerPath
    $viewerDest = Join-Path $DEST (Split-Path $viewerSrc -Leaf)
    if (-not (Test-Path $viewerSrc)) {
        Write-Error "Cartella archetipo viewer mancante: $viewerSrc"
        exit 1
    }
    Write-Host "Copia archetipo viewer → $viewerDest"
    Copy-Item -Path $viewerSrc -Destination $viewerDest -Recurse -Force
}

foreach ($tool in $selectedTools) {
    $skillsDest = Join-Path $DEST $tool.SkillsPath
    Write-Host "Copia skills → $skillsDest  [$($tool.Name)]"
    if (-not (Test-Path $skillsDest)) {
        New-Item -ItemType Directory -Path $skillsDest -Force | Out-Null
    }
    foreach ($skillName in $ArchetipoSkills) {
        $skillPath = Join-Path $SKILLS_SRC $skillName
        if (-not (Test-Path $skillPath)) {
            Write-Error "Skill mancante: $skillName"
            exit 1
        }
        Copy-Item -Path $skillPath -Destination (Join-Path $skillsDest $skillName) -Recurse -Force
    }
}

# --- Pulizia file di setup e reinit git ---

Push-Location $DEST
try {
    Write-Host "Pulizia file di setup..."
    Remove-Item -Path (Join-Path $DEST "backend") -Recurse -Force -ErrorAction SilentlyContinue
    if ($selectedBackend.Key -eq "file") {
        Remove-Item -Path (Join-Path $DEST ".archetipo") -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path (Join-Path $DEST "setup.ps1") -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $DEST "setup.sh") -Force -ErrorAction SilentlyContinue

    Write-Host "Reinizializzo la storia git..."
    Remove-Item -Path (Join-Path $DEST ".git") -Recurse -Force
    git init -b main

    Write-Host "Imposto il remote origin: $REMOTE_URL"
    git remote add origin $REMOTE_URL

    if ($selectedBackend.Key -eq "github") {
        node .archetipo/cli/archetipo.mjs setup-project
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Configurazione GitHub Project non completata."
            exit 1
        }
    }

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
