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

echo "Imposto il remote origin: $REMOTE_URL"
git remote set-url origin "$REMOTE_URL"

echo "Push verso il nuovo remote..."
git push -u origin main

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

# --- Pulizia file di setup ---

echo "Pulizia file di setup..."
rm -rf "$DEST/skills"
rm -f "$DEST/setup.ps1"
rm -f "$DEST/setup.sh"

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
