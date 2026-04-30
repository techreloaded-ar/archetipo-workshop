$ErrorActionPreference = "Stop"

$TEMPLATE_REPO = "https://github.com/techreloaded-ar/archetipo-workshop.git"
$DEFAULT_DIR = "archetipo-workshop"

Write-Host ""
Write-Host "========================================="
Write-Host "  Archetipo Workshop — Setup"
Write-Host "========================================="
Write-Host ""

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git non e' installato. Installalo prima di continuare."
    exit 1
}

$Tools = @(
    @{ Name = "Claude Code";    SkillsPath = ".claude\skills" }
    @{ Name = "Codex";          SkillsPath = ".agents\skills" }
    @{ Name = "Gemini CLI";     SkillsPath = ".gemini\skills" }
    @{ Name = "OpenCode";       SkillsPath = ".opencode\skills" }
    @{ Name = "GitHub Copilot"; SkillsPath = ".github\skills" }
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

Set-Location $PROJECT_DIR

Write-Host "Imposto il remote origin: $REMOTE_URL"
git remote set-url origin $REMOTE_URL

Write-Host "Push verso il nuovo remote..."
git push -u origin main

# --- Copia .archetipo e skills ---

$SKILLS_SRC = Join-Path (Get-Location) "skills"
$DEST          = Resolve-Path "."

Write-Host ""
Write-Host "Installazione Archetipo in: $DEST" -ForegroundColor Green
Write-Host ""

foreach ($tool in $selectedTools) {
    $skillsDest = Join-Path $DEST $tool.SkillsPath
    Write-Host "Copia skills → $skillsDest  [$($tool.Name)]"
    if (-not (Test-Path $skillsDest)) {
        New-Item -ItemType Directory -Path $skillsDest -Force | Out-Null
    }
    Get-ChildItem -Path $SKILLS_SRC -Directory | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $skillsDest $_.Name) -Recurse -Force
    }
}

# --- Pulizia file di setup ---

Write-Host "Pulizia file di setup..."
Remove-Item -Path (Join-Path $DEST "skills") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $DEST "setup.ps1") -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $DEST "setup.sh") -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Fatto! Il progetto e' pronto in '.\$PROJECT_DIR'" -ForegroundColor Green
Write-Host "Remote origin: $REMOTE_URL"
Write-Host ""
Write-Host "Prossimi passi:"
Write-Host "  cd $PROJECT_DIR"
Write-Host "  cp .env.example .env.local  # configura le variabili d'ambiente"
Write-Host "  npm install"
Write-Host "  npm run dev"
Write-Host ""
