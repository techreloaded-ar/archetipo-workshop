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

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) non e' installata. Installala e autenticala con 'gh auth login'."
    exit 1
}

& gh auth status > $null 2> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "GitHub CLI non e' autenticata. Esegui: gh auth login"
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

function Invoke-GhText {
    param(
        [string[]]$Arguments,
        [string]$ErrorMessage
    )

    $output = & gh @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "$ErrorMessage`n$output"
        exit 1
    }

    return (($output | Out-String).Trim())
}

function Assert-ProjectScopes {
    param([string]$Owner)

    & gh project list --owner $Owner --limit 1 --format json > $null 2> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Error "Mancano gli scope per accedere ai GitHub Projects.`nEsegui: gh auth refresh -s read:project -s project`nPoi rilancia lo script di setup."
        exit 1
    }
}

function Get-ProjectFields {
    param(
        [string]$ProjectNumber,
        [string]$Owner
    )

    $json = Invoke-GhText -Arguments @("project", "field-list", $ProjectNumber, "--owner", $Owner, "--format", "json") -ErrorMessage "Non riesco a leggere i campi del GitHub Project."
    return ($json | ConvertFrom-Json).fields
}

function Get-ProjectField {
    param(
        [string]$ProjectNumber,
        [string]$Owner,
        [string]$Name
    )

    $fields = Get-ProjectFields -ProjectNumber $ProjectNumber -Owner $Owner
    return ($fields | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function Get-ProjectOptionId {
    param(
        [string]$ProjectNumber,
        [string]$Owner,
        [string]$FieldName,
        [string]$OptionName
    )

    $field = Get-ProjectField -ProjectNumber $ProjectNumber -Owner $Owner -Name $FieldName
    if (-not $field -or -not $field.options) {
        return ""
    }

    $option = $field.options | Where-Object { $_.name.ToLowerInvariant() -eq $OptionName.ToLowerInvariant() } | Select-Object -First 1
    if ($option) { return $option.id }
    return ""
}

function Ensure-ProjectField {
    param(
        [string]$ProjectNumber,
        [string]$Owner,
        [string]$Name,
        [string]$ExpectedType,
        [string[]]$CreateArguments
    )

    $field = Get-ProjectField -ProjectNumber $ProjectNumber -Owner $Owner -Name $Name
    if ($field) {
        $fieldType = if ($field.dataType) { $field.dataType } elseif ($field.type) { $field.type } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($fieldType) -and $fieldType -ne $ExpectedType) {
            Write-Error "Il campo '$Name' esiste gia' ma ha tipo '$fieldType' invece di '$ExpectedType'. Interrompo per evitare modifiche distruttive al GitHub Project."
            exit 1
        }
        return $field.id
    }

    Invoke-GhText -Arguments (@("project", "field-create", $ProjectNumber, "--owner", $Owner, "--name", $Name) + $CreateArguments) -ErrorMessage "Non riesco a creare il campo '$Name'." | Out-Null
    $createdField = Get-ProjectField -ProjectNumber $ProjectNumber -Owner $Owner -Name $Name
    if (-not $createdField) {
        Write-Error "Il campo '$Name' non e' stato trovato dopo la creazione."
        exit 1
    }
    return $createdField.id
}

function Initialize-ArchetipoGitHubProject {
    Write-Host ""
    Write-Host "Configuro GitHub Project per Archetipo..."

    $owner = Invoke-GhText -Arguments @("repo", "view", "--json", "owner", "--jq", ".owner.login") -ErrorMessage "Non riesco a rilevare l'owner del repository GitHub dal remote origin."
    $repoName = Invoke-GhText -Arguments @("repo", "view", "--json", "name", "--jq", ".name") -ErrorMessage "Non riesco a rilevare il nome del repository GitHub dal remote origin."

    if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repoName)) {
        Write-Error "Non riesco a rilevare owner e nome del repository GitHub dal remote origin."
        exit 1
    }

    Assert-ProjectScopes -Owner $owner

    $projectTitle = "$repoName Backlog"
    Write-Host "Creo GitHub Project: $projectTitle"
    $projectNumber = Invoke-GhText -Arguments @("project", "create", "--owner", $owner, "--title", $projectTitle, "--format", "json", "--jq", ".number") -ErrorMessage "Non riesco a creare il GitHub Project."
    $projectNodeId = Invoke-GhText -Arguments @("project", "view", $projectNumber, "--owner", $owner, "--format", "json", "--jq", ".id") -ErrorMessage "Non riesco a leggere il node ID del GitHub Project."

    if ([string]::IsNullOrWhiteSpace($projectNumber) -or [string]::IsNullOrWhiteSpace($projectNodeId)) {
        Write-Error "Creazione GitHub Project non completata correttamente."
        exit 1
    }

    $statusField = Get-ProjectField -ProjectNumber $projectNumber -Owner $owner -Name "Status"
    if (-not $statusField) {
        Write-Error "Non trovo il campo Status nel GitHub Project appena creato."
        exit 1
    }

    Write-Host "Configuro Status: Todo, Planned, In Progress, Review, Done"
    $statusOptions = @'
[
  {"name":"Todo","color":"GRAY","description":""},
  {"name":"Planned","color":"BLUE","description":""},
  {"name":"In Progress","color":"YELLOW","description":""},
  {"name":"Review","color":"PURPLE","description":""},
  {"name":"Done","color":"GREEN","description":""}
]
'@

    Invoke-GhText -Arguments @(
        "api", "graphql",
        "-f", "query=mutation(`$f:ID!,`$opts:[ProjectV2SingleSelectFieldOptionInput!]!){updateProjectV2Field(input:{fieldId:`$f, singleSelectOptions:`$opts}){projectV2Field { ... on ProjectV2SingleSelectField { id options { id name } } }}}",
        "-f", "f=$($statusField.id)",
        "-f", "opts=$statusOptions"
    ) -ErrorMessage "Non riesco a configurare le opzioni del campo Status." | Out-Null

    $priorityFieldId = Ensure-ProjectField -ProjectNumber $projectNumber -Owner $owner -Name "Priority" -ExpectedType "SINGLE_SELECT" -CreateArguments @("--data-type", "SINGLE_SELECT", "--single-select-options", "HIGH,MEDIUM,LOW")
    $storyPointsFieldId = Ensure-ProjectField -ProjectNumber $projectNumber -Owner $owner -Name "Story Points" -ExpectedType "NUMBER" -CreateArguments @("--data-type", "NUMBER")
    $epicFieldId = Ensure-ProjectField -ProjectNumber $projectNumber -Owner $owner -Name "Epic" -ExpectedType "SINGLE_SELECT" -CreateArguments @("--data-type", "SINGLE_SELECT", "--single-select-options", "EP-000: placeholder")

    $todoOptionId = Get-ProjectOptionId -ProjectNumber $projectNumber -Owner $owner -FieldName "Status" -OptionName "Todo"
    $plannedOptionId = Get-ProjectOptionId -ProjectNumber $projectNumber -Owner $owner -FieldName "Status" -OptionName "Planned"
    $inProgressOptionId = Get-ProjectOptionId -ProjectNumber $projectNumber -Owner $owner -FieldName "Status" -OptionName "In Progress"
    $reviewOptionId = Get-ProjectOptionId -ProjectNumber $projectNumber -Owner $owner -FieldName "Status" -OptionName "Review"
    $doneOptionId = Get-ProjectOptionId -ProjectNumber $projectNumber -Owner $owner -FieldName "Status" -OptionName "Done"
    $highOptionId = Get-ProjectOptionId -ProjectNumber $projectNumber -Owner $owner -FieldName "Priority" -OptionName "HIGH"
    $mediumOptionId = Get-ProjectOptionId -ProjectNumber $projectNumber -Owner $owner -FieldName "Priority" -OptionName "MEDIUM"
    $lowOptionId = Get-ProjectOptionId -ProjectNumber $projectNumber -Owner $owner -FieldName "Priority" -OptionName "LOW"

    $requiredValues = @(
        $todoOptionId, $plannedOptionId, $inProgressOptionId, $reviewOptionId, $doneOptionId,
        $priorityFieldId, $highOptionId, $mediumOptionId, $lowOptionId,
        $storyPointsFieldId, $epicFieldId
    )
    if ($requiredValues | Where-Object { [string]::IsNullOrWhiteSpace($_) }) {
        Write-Error "Non riesco a leggere tutti gli ID richiesti dal GitHub Project."
        exit 1
    }

    Write-Host "Creo label archetipo-spec..."
    Invoke-GhText -Arguments @("label", "create", "archetipo-spec", "--description", "Story generated by /archetipo-spec", "--color", "0E8A16", "--force") -ErrorMessage "Non riesco a creare la label archetipo-spec." | Out-Null

    $configDir = Join-Path (Get-Location) ".archetipo"
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $configContent = @"
#only valid for github connector
github:
  owner: $owner
  project_number: $projectNumber
  project_node_id: $projectNodeId
  fields:
    status:
      id: $($statusField.id)
      options:
        todo: $todoOptionId
        planned: $plannedOptionId
        in_progress: $inProgressOptionId
        review: $reviewOptionId
        done: $doneOptionId
    priority:
      id: $priorityFieldId
      options:
        high: $highOptionId
        medium: $mediumOptionId
        low: $lowOptionId
    story_points:
      id: $storyPointsFieldId
    epic:
      id: $epicFieldId
      # Options managed dynamically by /archetipo-spec
"@

    Set-Content -Path (Join-Path $configDir "config.yaml") -Value $configContent -Encoding utf8

    Write-Host "GitHub Project configurato: $projectTitle (#$projectNumber)"
    Write-Host "Config scritto in .archetipo/config.yaml"
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

# --- Copia .archetipo e skills ---

$DEST       = Resolve-Path $PROJECT_DIR
$SKILLS_SRC = Join-Path $DEST "skills"

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

# --- Pulizia file di setup e reinit git ---

Push-Location $DEST
try {
    Write-Host "Pulizia file di setup..."
    Remove-Item -Path (Join-Path $DEST "skills") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $DEST "setup.ps1") -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $DEST "setup.sh") -Force -ErrorAction SilentlyContinue

    Write-Host "Reinizializzo la storia git..."
    Remove-Item -Path (Join-Path $DEST ".git") -Recurse -Force
    git init -b main

    Write-Host "Imposto il remote origin: $REMOTE_URL"
    git remote add origin $REMOTE_URL

    Initialize-ArchetipoGitHubProject

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
