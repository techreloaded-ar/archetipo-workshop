#!/usr/bin/env bash
set -e

TEMPLATE_REPO="https://github.com/techreloaded-ar/archetipo-workshop.git"
DEFAULT_DIR="archetipo-workshop"

TOOL_NAMES=("Claude Code" "Codex" "Gemini CLI" "OpenCode" "GitHub Copilot")
TOOL_PATHS=(".claude/skills" ".agents/skills" ".gemini/skills" ".opencode/skills" ".github/skills")

echo ""
echo "========================================="
echo "  Archetipo Workshop — Setup"
echo "========================================="
echo ""

if ! command -v git &> /dev/null; then
    echo "Errore: git non e' installato. Installalo prima di continuare."
    exit 1
fi

if ! command -v gh &> /dev/null; then
    echo "Errore: GitHub CLI (gh) non e' installata. Installala e autenticala con 'gh auth login'."
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo "Errore: GitHub CLI non e' autenticata."
    echo "Esegui: gh auth login"
    exit 1
fi

show_menu() {
    local count=${#TOOL_NAMES[@]}
    local -a selected
    local cursor=0
    SELECTED_INDICES=()

    for ((i=0; i<count; i++)); do selected[$i]=false; done

    while true; do
        clear
        echo -e "\033[36mSeleziona strumenti (Spazio = seleziona, Invio = conferma):\033[0m"
        echo ""
        for ((i=0; i<count; i++)); do
            local mark="[ ]"
            if [ "${selected[$i]}" = "true" ]; then mark="[x]"; fi
            if [ $i -eq $cursor ]; then
                echo -e "  \033[33m> $mark ${TOOL_NAMES[$i]}\033[0m"
            else
                echo "    $mark ${TOOL_NAMES[$i]}"
            fi
        done
        echo ""
        echo -e "\033[90mFrecce su/giu per navigare, Spazio per selezionare, Invio per confermare.\033[0m"

        IFS= read -r -s -n1 key < /dev/tty
        if [[ $key == $'\x1b' ]]; then
            read -r -s -n2 key2 < /dev/tty
            case "$key2" in
                '[A') if [ $cursor -gt 0 ]; then ((cursor--)); fi ;;
                '[B') if [ $cursor -lt $((count-1)) ]; then ((cursor++)); fi ;;
            esac
        elif [[ $key == ' ' ]]; then
            if [ "${selected[$cursor]}" = "true" ]; then
                selected[$cursor]=false
            else
                selected[$cursor]=true
            fi
        elif [[ $key == '' ]]; then
            break
        fi
    done

    for ((i=0; i<count; i++)); do
        if [ "${selected[$i]}" = "true" ]; then SELECTED_INDICES+=($i); fi
    done
}

require_project_scopes() {
    local owner="$1"

    if ! gh project list --owner "$owner" --limit 1 --format json > /dev/null 2>&1; then
        echo ""
        echo "Errore: mancano gli scope per accedere ai GitHub Projects."
        echo "Esegui:"
        echo "  gh auth refresh -s read:project -s project"
        echo "Poi rilancia lo script di setup."
        exit 1
    fi
}

get_project_field_id() {
    local project_number="$1"
    local owner="$2"
    local field_name="$3"

    gh project field-list "$project_number" --owner "$owner" --format json \
        --jq ".fields[] | select(.name == \"$field_name\") | .id" | head -n 1
}

get_project_field_type() {
    local project_number="$1"
    local owner="$2"
    local field_name="$3"

    gh project field-list "$project_number" --owner "$owner" --format json \
        --jq ".fields[] | select(.name == \"$field_name\") | (.dataType // .type // \"\")" | head -n 1
}

get_project_option_id() {
    local project_number="$1"
    local owner="$2"
    local field_name="$3"
    local option_name="$4"

    gh project field-list "$project_number" --owner "$owner" --format json \
        --jq ".fields[] | select(.name == \"$field_name\") | .options[]? | select((.name | ascii_downcase) == (\"$option_name\" | ascii_downcase)) | .id" | head -n 1
}

ensure_project_field() {
    local project_number="$1"
    local owner="$2"
    local field_name="$3"
    local expected_type="$4"
    local create_args=("${@:5}")
    local field_id
    local field_type

    field_id="$(get_project_field_id "$project_number" "$owner" "$field_name")"
    if [ -n "$field_id" ]; then
        field_type="$(get_project_field_type "$project_number" "$owner" "$field_name")"
        if [ -n "$field_type" ] && [ "$field_type" != "$expected_type" ]; then
            echo "Errore: il campo '$field_name' esiste gia' ma ha tipo '$field_type' invece di '$expected_type'."
            echo "Interrompo per evitare modifiche distruttive al GitHub Project."
            exit 1
        fi
        echo "$field_id"
        return
    fi

    gh project field-create "$project_number" --owner "$owner" --name "$field_name" "${create_args[@]}" > /dev/null
    get_project_field_id "$project_number" "$owner" "$field_name"
}

bootstrap_github_project() {
    echo ""
    echo "Configuro GitHub Project per Archetipo..."

    local owner
    local repo_name
    local project_title
    local project_number
    local project_node_id
    local status_field_id
    local priority_field_id
    local story_points_field_id
    local epic_field_id
    local todo_option_id
    local planned_option_id
    local in_progress_option_id
    local review_option_id
    local done_option_id
    local high_option_id
    local medium_option_id
    local low_option_id

    owner="$(gh repo view --json owner --jq '.owner.login')"
    repo_name="$(gh repo view --json name --jq '.name')"

    if [ -z "$owner" ] || [ -z "$repo_name" ]; then
        echo "Errore: non riesco a rilevare owner e nome del repository GitHub dal remote origin."
        exit 1
    fi

    require_project_scopes "$owner"

    project_title="$repo_name Backlog"
    echo "Creo GitHub Project: $project_title"
    project_number="$(gh project create --owner "$owner" --title "$project_title" --format json --jq '.number')"
    project_node_id="$(gh project view "$project_number" --owner "$owner" --format json --jq '.id')"

    if [ -z "$project_number" ] || [ -z "$project_node_id" ]; then
        echo "Errore: creazione GitHub Project non completata correttamente."
        exit 1
    fi

    status_field_id="$(get_project_field_id "$project_number" "$owner" "Status")"
    if [ -z "$status_field_id" ]; then
        echo "Errore: non trovo il campo Status nel GitHub Project appena creato."
        exit 1
    fi

    echo "Configuro Status: Todo, Planned, In Progress, Review, Done"
    status_query='
mutation {
  updateProjectV2Field(input: {
    fieldId: "__FIELD_ID__",
    singleSelectOptions: [
      {name: "Todo",        color: GRAY,   description: ""},
      {name: "Planned",     color: BLUE,   description: ""},
      {name: "In Progress", color: YELLOW, description: ""},
      {name: "Review",      color: PURPLE, description: ""},
      {name: "Done",        color: GREEN,  description: ""}
    ]
  }) {
    projectV2Field {
      ... on ProjectV2SingleSelectField { id options { id name } }
    }
  }
}
'
    status_query="${status_query/__FIELD_ID__/$status_field_id}"

    gh api graphql -f query="$status_query" > /dev/null

    priority_field_id="$(ensure_project_field "$project_number" "$owner" "Priority" "SINGLE_SELECT" --data-type SINGLE_SELECT --single-select-options "HIGH,MEDIUM,LOW")"
    story_points_field_id="$(ensure_project_field "$project_number" "$owner" "Story Points" "NUMBER" --data-type NUMBER)"
    epic_field_id="$(ensure_project_field "$project_number" "$owner" "Epic" "SINGLE_SELECT" --data-type SINGLE_SELECT --single-select-options "EP-000: placeholder")"

    todo_option_id="$(get_project_option_id "$project_number" "$owner" "Status" "Todo")"
    planned_option_id="$(get_project_option_id "$project_number" "$owner" "Status" "Planned")"
    in_progress_option_id="$(get_project_option_id "$project_number" "$owner" "Status" "In Progress")"
    review_option_id="$(get_project_option_id "$project_number" "$owner" "Status" "Review")"
    done_option_id="$(get_project_option_id "$project_number" "$owner" "Status" "Done")"
    high_option_id="$(get_project_option_id "$project_number" "$owner" "Priority" "HIGH")"
    medium_option_id="$(get_project_option_id "$project_number" "$owner" "Priority" "MEDIUM")"
    low_option_id="$(get_project_option_id "$project_number" "$owner" "Priority" "LOW")"

    if [ -z "$todo_option_id" ] || [ -z "$planned_option_id" ] || [ -z "$in_progress_option_id" ] || [ -z "$review_option_id" ] || [ -z "$done_option_id" ] || \
       [ -z "$priority_field_id" ] || [ -z "$high_option_id" ] || [ -z "$medium_option_id" ] || [ -z "$low_option_id" ] || \
       [ -z "$story_points_field_id" ] || [ -z "$epic_field_id" ]; then
        echo "Errore: non riesco a leggere tutti gli ID richiesti dal GitHub Project."
        exit 1
    fi

    echo "Creo label archetipo-spec..."
    gh label create "archetipo-spec" --description "Story generated by /archetipo-spec" --color 0E8A16 --force > /dev/null

    mkdir -p ".archetipo"
    cat > ".archetipo/config.yaml" <<EOF
#only valid for github connector
github:
  owner: $owner
  project_number: $project_number
  project_node_id: $project_node_id
  fields:
    status:
      id: $status_field_id
      options:
        todo: $todo_option_id
        planned: $planned_option_id
        in_progress: $in_progress_option_id
        review: $review_option_id
        done: $done_option_id
    priority:
      id: $priority_field_id
      options:
        high: $high_option_id
        medium: $medium_option_id
        low: $low_option_id
    story_points:
      id: $story_points_field_id
    epic:
      id: $epic_field_id
      # Options managed dynamically by /archetipo-spec
EOF

    echo "GitHub Project configurato: $project_title (#$project_number)"
    echo "Config scritto in .archetipo/config.yaml"
}

# --- Input utente ---

read -p "Nome cartella progetto [$DEFAULT_DIR]: " PROJECT_DIR < /dev/tty
PROJECT_DIR="${PROJECT_DIR:-$DEFAULT_DIR}"

if [ -d "$PROJECT_DIR" ]; then
    echo "Errore: la directory '$PROJECT_DIR' esiste gia'."
    exit 1
fi

read -p "URL del tuo repository remoto: " REMOTE_URL < /dev/tty
if [ -z "$REMOTE_URL" ]; then
    echo "Errore: l'URL remoto non puo' essere vuoto."
    exit 1
fi

# --- Selezione strumenti ---

show_menu

if [ ${#SELECTED_INDICES[@]} -eq 0 ]; then
    echo ""
    echo -e "\033[33mNessuno strumento selezionato. Uscita.\033[0m"
    exit 0
fi

clear
echo ""

# --- Clone template ---

echo "Clono il template in '$PROJECT_DIR'..."
git clone "$TEMPLATE_REPO" "$PROJECT_DIR"

cd "$PROJECT_DIR"

# --- Copia skills ---

SKILLS_SRC="$(pwd)/skills"
DEST="$(pwd)"

echo ""
echo -e "\033[32mInstallazione Archetipo in: $DEST\033[0m"
echo ""

for idx in "${SELECTED_INDICES[@]}"; do
    SKILLS_DEST="$DEST/${TOOL_PATHS[$idx]}"
    echo "Copia skills → $SKILLS_DEST  [${TOOL_NAMES[$idx]}]"
    mkdir -p "$SKILLS_DEST"
    for skill_dir in "$SKILLS_SRC"/*; do
        if [ -d "$skill_dir" ]; then
            cp -r "$skill_dir" "$SKILLS_DEST/"
        fi
    done
done

# --- Pulizia file di setup e reinit git ---

echo "Pulizia file di setup..."
rm -rf "$DEST/skills"
rm -f "$DEST/setup.ps1"
rm -f "$DEST/setup.sh"

echo "Reinizializzo la storia git..."
rm -rf "$DEST/.git"
git init -b main

echo "Imposto il remote origin: $REMOTE_URL"
git remote add origin "$REMOTE_URL"

bootstrap_github_project

git add -A
git commit -m "Initial commit from archetipo-workshop"

echo "Push verso il nuovo remote..."
git push -u origin main

echo ""
echo -e "\033[32mFatto! Il progetto e' pronto in './$PROJECT_DIR'\033[0m"
echo "Remote origin: $REMOTE_URL"
echo ""
echo "Prossimi passi:"
echo "  cd $PROJECT_DIR"
echo "  cp .env.example .env  # configura le variabili d'ambiente"
echo "  npm install"
echo "  npm run dev"
echo ""
