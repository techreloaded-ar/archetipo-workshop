#!/usr/bin/env bash
set -e

TEMPLATE_REPO="https://github.com/techreloaded-ar/archetipo-workshop.git"
DEFAULT_DIR="archetipo-workshop"
BACKEND_NAMES=("File" "GitHub Projects")
BACKEND_KEYS=("file" "github")

TOOL_NAMES=("Claude Code" "Codex" "Gemini CLI" "OpenCode" "GitHub Copilot")
TOOL_KEYS=("claude" "codex" "gemini" "opencode" "copilot")

echo ""
echo "========================================="
echo "  Archetipo Workshop — Setup"
echo "========================================="
echo ""

# --- Prerequisiti ---

if ! command -v git &> /dev/null; then
    echo "Errore: git non e' installato. Installalo prima di continuare."
    exit 1
fi

if ! command -v node &> /dev/null; then
    echo "Errore: Node.js non e' installato. Installalo prima di continuare."
    exit 1
fi

if ! command -v npm &> /dev/null; then
    echo "Errore: npm non e' installato. Installalo prima di continuare."
    exit 1
fi

# --- Verifica / auto-install CLI globale archetipo ---

ARCHETIPO_BIN=""
if command -v archetipo &> /dev/null; then
    ARCHETIPO_BIN="archetipo"
fi

if [ -z "$ARCHETIPO_BIN" ]; then
    echo ""
    echo -e "\033[33mLa CLI globale 'archetipo' non e' trovata nel PATH. Tentativo di installazione automatica...\033[0m"
    echo ""
    if npm install -g @techreloaded/archetipo; then
        echo ""
    else
        echo ""
        echo -e "\033[31mInstallazione fallita.\033[0m"
        echo ""
        echo "Prova manualmente:"
        echo "  npm config set prefix ~/.npm-global"
        echo '  export PATH="$HOME/.npm-global/bin:$PATH"'
        echo "  npm install -g @techreloaded/archetipo"
        echo ""
        echo "Poi rilancia questo script."
        exit 1
    fi

    if command -v archetipo &> /dev/null; then
        ARCHETIPO_BIN="archetipo"
    else
        echo ""
        echo -e "\033[31mInstallazione completata ma 'archetipo' non e' ancora nel PATH.\033[0m"
        echo ""
        echo "Aggiungi il bin path di npm al tuo PATH:"
        echo "  export PATH=\"\$(npm config get prefix)/bin:\$PATH\""
        echo ""
        echo "Poi rilancia questo script."
        exit 1
    fi
fi

echo ""
echo -e "  \033[32marchetipo\033[0m $($ARCHETIPO_BIN --version 2>/dev/null || echo "rilevato")"

# --- Input utente ---

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
    local option_names=("$@")
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

show_single_choice_menu "${BACKEND_NAMES[@]}"

SELECTED_BACKEND_INDEX=$SELECTED_CHOICE
SELECTED_BACKEND_KEY="${BACKEND_KEYS[$SELECTED_BACKEND_INDEX]}"
SELECTED_BACKEND_NAME="${BACKEND_NAMES[$SELECTED_BACKEND_INDEX]}"

if [ "$SELECTED_BACKEND_KEY" = "github" ]; then
    if ! command -v gh &> /dev/null; then
        echo "Errore: GitHub CLI (gh) non e' installata. Installala e autenticala con 'gh auth login'."
        exit 1
    fi

    echo ""
    echo -e "\033[33mVerifica autenticazione e scope GitHub Projects...\033[0m"
    if ! GH_API_OUTPUT=$(gh api -i user 2>&1); then
        echo ""
        echo -e "\033[31mERRORE: GitHub CLI non e' autenticata. Esegui:\033[0m"
        echo -e "  \033[36mgh auth login\033[0m"
        echo -e "  \033[36mgh auth refresh -s read:project -s project\033[0m"
        echo -e "\033[33mPoi RILANCIA questo script di installazione.\033[0m"
        exit 1
    fi
    SCOPE_LINE=$(echo "$GH_API_OUTPUT" | grep -i '^x-oauth-scopes:' | head -1)
    if [ -n "$SCOPE_LINE" ]; then
        SCOPES=$(echo "$SCOPE_LINE" | sed 's/^[Xx]-[Oo]auth-[Ss]copes:[[:space:]]*//')
        if ! echo "$SCOPES" | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep -qx 'project'; then
            echo ""
            echo -e "\033[31mERRORE: Il token GitHub non ha lo scope di scrittura 'project', necessario per creare il GitHub Project v2.\033[0m"
            echo -e "\033[31m(Lo scope attuale consente solo la lettura: la creazione del progetto fallirebbe.)\033[0m"
            echo ""
            echo -e "\033[33mEsegui:\033[0m"
            echo -e "  \033[36mgh auth refresh -s read:project -s project\033[0m"
            echo -e "\033[33mVerifica con quale account sei autenticato (se ne hai piu' di uno):\033[0m"
            echo -e "  \033[36mgh auth status        # eventualmente: gh auth switch\033[0m"
            echo -e "\033[33mPoi RILANCIA questo script di installazione.\033[0m"
            exit 1
        fi
    fi
    # Se l'header non e' leggibile si prosegue (rete di sicurezza)
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

# --- Pulizia asset template obsoleti ---

echo ""
echo -e "\033[32mInstallazione Archetipo in: $(pwd)\033[0m"
echo -e "\033[32mBackend backlog: $SELECTED_BACKEND_NAME\033[0m"
echo ""

echo "Pulizia asset template obsoleti..."
rm -rf backend
rm -rf .archetipo
rm -f setup.ps1
rm -f setup.sh

# --- Reinizializza git ---

echo "Reinizializzo la storia git..."
rm -rf .git
git init -b main

echo "Imposto il remote origin: $REMOTE_URL"
git remote add origin "$REMOTE_URL"

# --- Esegui archetipo init ---

ARCHETIPO_INIT_ARGS=("init" "--connector" "$SELECTED_BACKEND_KEY" "--yes")
for idx in "${SELECTED_INDICES[@]}"; do
    ARCHETIPO_INIT_ARGS+=("--tool" "${TOOL_KEYS[$idx]}")
done

echo ""
echo "Eseguo archetipo init..."
echo "  $ARCHETIPO_BIN ${ARCHETIPO_INIT_ARGS[*]}"
$ARCHETIPO_BIN "${ARCHETIPO_INIT_ARGS[@]}"

# --- Per GitHub: archetipo config show ---

if [ "$SELECTED_BACKEND_KEY" = "github" ]; then
    echo ""
    echo "Configuro GitHub Project via archetipo config show..."
    if ! $ARCHETIPO_BIN config show; then
        echo ""
        echo -e "\033[31mERRORE: archetipo config show fallito.\033[0m"
        echo -e "\033[33mCausa probabile: token senza scope 'project' oppure account senza permessi sull'owner di destinazione.\033[0m"
        echo ""
        echo -e "\033[33mComandi di diagnosi/fix:\033[0m"
        echo -e "  \033[36mgh auth status\033[0m"
        echo -e "  \033[36mgh auth refresh -s read:project -s project   # eventuale: gh auth switch\033[0m"
        echo ""
        echo -e "\033[33mIl progetto e' gia' stato inizializzato. NON rilancia lo script.\033[0m"
        echo -e "\033[33mRiprendi dall'interno della cartella progetto:\033[0m"
        echo -e "  \033[36mcd $PROJECT_DIR\033[0m"
        echo -e "  \033[36marchetipo config show\033[0m"
        echo -e "  \033[36mgit add -A\033[0m"
        echo -e "  \033[36mgit commit -m \"Initial commit from archetipo-workshop\"\033[0m"
        echo -e "  \033[36mgit push -u origin main\033[0m"
        exit 1
    fi
fi

# --- Commit iniziale ---

echo ""
echo "Commit iniziale..."
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
