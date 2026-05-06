#!/usr/bin/env bash
set -e

TEMPLATE_REPO="https://github.com/techreloaded-ar/archetipo-workshop.git"
DEFAULT_DIR="archetipo-workshop"
BACKEND_NAMES=("File" "GitHub Projects")
BACKEND_KEYS=("file" "github")
BACKEND_SKILLS_PATHS=("backend/file/skills" "backend/github/skills")
BACKEND_VIEWER_PATHS=("backend/file/archetipo-viewer" "")
BACKEND_ARCHETIPO_PATHS=("" "backend/github/.archetipo")

TOOL_NAMES=("Claude Code" "Codex" "Gemini CLI" "OpenCode" "GitHub Copilot")
TOOL_PATHS=(".claude/skills" ".agents/skills" ".gemini/skills" ".opencode/skills" ".github/skills")
ARCHETIPO_SKILLS=("archetipo-design" "archetipo-implement" "archetipo-inception" "archetipo-plan" "archetipo-spec")

echo ""
echo "========================================="
echo "  Archetipo Workshop — Setup"
echo "========================================="
echo ""

if ! command -v git &> /dev/null; then
    echo "Errore: git non e' installato. Installalo prima di continuare."
    exit 1
fi

if ! command -v node &> /dev/null; then
    echo "Errore: Node.js non e' installato. Installalo prima di continuare."
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

show_single_choice_menu() {
    local -n option_names=$1
    local count=${#option_names[@]}
    local cursor=0
    SELECTED_CHOICE=0

    while true; do
        clear
        echo -e "\033[36mSeleziona backend backlog:\033[0m"
        echo ""
        for ((i=0; i<count; i++)); do
            if [ $i -eq $cursor ]; then
                echo -e "  \033[33m> ${option_names[$i]}\033[0m"
            else
                echo "    ${option_names[$i]}"
            fi
        done
        echo ""
        echo -e "\033[90mFrecce su/giu per navigare, Invio per confermare.\033[0m"

        IFS= read -r -s -n1 key < /dev/tty
        if [[ $key == $'\x1b' ]]; then
            read -r -s -n2 key2 < /dev/tty
            case "$key2" in
                '[A') if [ $cursor -gt 0 ]; then ((cursor--)); fi ;;
                '[B') if [ $cursor -lt $((count-1)) ]; then ((cursor++)); fi ;;
            esac
        elif [[ $key == '' ]]; then
            SELECTED_CHOICE=$cursor
            break
        fi
    done
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

# --- Selezione backend backlog ---

show_single_choice_menu BACKEND_NAMES

SELECTED_BACKEND_INDEX=$SELECTED_CHOICE
SELECTED_BACKEND_KEY="${BACKEND_KEYS[$SELECTED_BACKEND_INDEX]}"
SELECTED_BACKEND_NAME="${BACKEND_NAMES[$SELECTED_BACKEND_INDEX]}"
SELECTED_BACKEND_SKILLS_PATH="${BACKEND_SKILLS_PATHS[$SELECTED_BACKEND_INDEX]}"
SELECTED_BACKEND_VIEWER_PATH="${BACKEND_VIEWER_PATHS[$SELECTED_BACKEND_INDEX]}"
SELECTED_BACKEND_ARCHETIPO_PATH="${BACKEND_ARCHETIPO_PATHS[$SELECTED_BACKEND_INDEX]}"

if [ "$SELECTED_BACKEND_KEY" = "github" ]; then
    if ! command -v gh &> /dev/null; then
        echo "Errore: GitHub CLI (gh) non e' installata. Installala e autenticala con 'gh auth login'."
        exit 1
    fi

    if ! gh auth status &> /dev/null; then
        echo "Errore: GitHub CLI non e' autenticata."
        echo "Esegui: gh auth login"
        exit 1
    fi
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

# --- Copia backend e skills ---

DEST="$(pwd)"
SKILLS_SRC="$DEST/$SELECTED_BACKEND_SKILLS_PATH"

echo ""
echo -e "\033[32mInstallazione Archetipo in: $DEST\033[0m"
echo -e "\033[32mBackend backlog: $SELECTED_BACKEND_NAME\033[0m"
echo ""

if [ ! -d "$SKILLS_SRC" ]; then
    echo "Errore: cartella skills backend mancante: $SKILLS_SRC"
    exit 1
fi

if [ "$SELECTED_BACKEND_KEY" = "github" ]; then
    BACKEND_ARCHETIPO_SRC="$DEST/$SELECTED_BACKEND_ARCHETIPO_PATH"
    ROOT_ARCHETIPO_DEST="$DEST/.archetipo"
    if [ -d "$BACKEND_ARCHETIPO_SRC" ]; then
        echo "Copia backend GitHub .archetipo → $ROOT_ARCHETIPO_DEST"
        rm -rf "$ROOT_ARCHETIPO_DEST"
        cp -r "$BACKEND_ARCHETIPO_SRC" "$ROOT_ARCHETIPO_DEST"
    fi
else
    VIEWER_SRC="$DEST/$SELECTED_BACKEND_VIEWER_PATH"
    VIEWER_DEST="$DEST/$(basename "$VIEWER_SRC")"
    if [ ! -d "$VIEWER_SRC" ]; then
        echo "Errore: cartella archetipo viewer mancante: $VIEWER_SRC"
        exit 1
    fi
    echo "Copia archetipo viewer → $VIEWER_DEST"
    cp -r "$VIEWER_SRC" "$VIEWER_DEST"
fi

for idx in "${SELECTED_INDICES[@]}"; do
    SKILLS_DEST="$DEST/${TOOL_PATHS[$idx]}"
    echo "Copia skills → $SKILLS_DEST  [${TOOL_NAMES[$idx]}]"
    mkdir -p "$SKILLS_DEST"
    for skill_name in "${ARCHETIPO_SKILLS[@]}"; do
        skill_dir="$SKILLS_SRC/$skill_name"
        if [ -d "$skill_dir" ]; then
            cp -r "$skill_dir" "$SKILLS_DEST/"
        else
            echo "Errore: skill mancante: $skill_name"
            exit 1
        fi
    done
done

# --- Pulizia file di setup e reinit git ---

echo "Pulizia file di setup..."
rm -rf "$DEST/backend"
if [ "$SELECTED_BACKEND_KEY" = "file" ]; then
    rm -rf "$DEST/.archetipo"
fi
rm -f "$DEST/setup.ps1"
rm -f "$DEST/setup.sh"

echo "Reinizializzo la storia git..."
rm -rf "$DEST/.git"
git init -b main

echo "Imposto il remote origin: $REMOTE_URL"
git remote add origin "$REMOTE_URL"

if [ "$SELECTED_BACKEND_KEY" = "github" ]; then
    node .archetipo/cli/archetipo.mjs setup-project
fi

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
