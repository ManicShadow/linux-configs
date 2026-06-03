#!/usr/bin/env bash
# ❄️   WSL / Native Ubuntu 24.04 — Full Dev Environment Setup (Nord Theme)
# ╭────────────────────────────────────────────────────────────────────────────╮
# │ 🚀 Full Dev Environment Clone Script                                        │
# │                                                                            │
# │ Installs all tools and writes fully configured dotfiles:                   │
# │   ~/.bashrc  ~/.zshrc  ~/.vimrc  ~/.tmux.conf                             │
# │   ~/.config/terminator/config  ~/.config/fontconfig/fonts.conf               │
# │                                                                            │
# │ 📋 WHAT IT CONFIGURES (prompted interactively):                             │
# │   • Git identity, GPG signing key (generate new or import existing)        │
# │   • Per-directory git identities (work vs personal)                        │
# │   • Default shell — zsh (recommended) or bash                              │
# │   • Nord theme (live colour palette preview shown before choosing)         │
# │   • MesloLGS Nerd Font — optionally set as global monospace font           │
# │   • Bash → Zsh history migration (auto-runs when switching to zsh)         │
# │   • Vim + vim-plug plugins (NERDTree, CoC LSP, fzf, Nord, GitGutter…)      │
# │   • Kubernetes channel (kubectl), Node.js LTS version                      │
# │   • WSL: Windows username, Terminator launcher (BAT + VBS)                  │
# │                                                                            │
# │ 🛠️  TOOLS INSTALLED:                                                        │
# │   apt  — docker, kubectl, terraform, ansible, azure-cli, gcloud,           │
# │           gh, nodejs, eza, zoxide, fzf, bat, ripgrep, tmux, vim …         │
# │   snap — yq                                                                │
# │   bin  — helm, helmfile, kubelogin, lazygit                                │
# │   pipx — git-filter-repo                                                   │
# │   zsh  — Oh My Zsh, Powerlevel10k, zsh-autosuggestions,                    │
# │           zsh-syntax-highlighting                                          │
# │                                                                            │
# │ 📖 HOW TO USE:                                                              │
# │   1. Copy this file to the new machine (git, scp, USB, shared folder…)     │
# │   2. chmod +x devops-setup.sh && bash devops-setup.sh                      │
# │   3. Answer the prompts — nothing personal is hardcoded in this file        │
# │   4. Grab a coffee ☕   — the full run takes 5–10 minutes                  │
# │                                                                            │
# │ ⚠️  RUN AS: your normal user (NOT root). You need sudo access.              │
# │ ✅  IDEMPOTENT: safe to re-run — already-installed items are skipped.       │
# ╰────────────────────────────────────────────────────────────────────────────╯

# Bash Strict Mode:
# -e: Exit immediately if any command returns a non-zero status.
# -u: Exit if an undefined variable is used.
# -o pipefail: Exit if any command in a pipeline fails (not just the last one).
set -euo pipefail

# ── 🧹 Cleanup Trap ────────────────────────────────────────────────────────
# Ensures temporary binaries and background processes are cleaned up even if
# the script fails, errors out, or is aborted (Ctrl+C).
# Note: kill $SUDO_PID ensures our background sudo-refresher doesn't turn into a zombie process.
SUDO_PID=""
trap 'rm -rf /tmp/kubelogin* /tmp/helmfile* /tmp/lazygit* /tmp/fontawesome*; kill ${SUDO_PID:-} 2>/dev/null || true' EXIT

# ── 🎨 Color & Print Helpers (Nord True Color Palette) ────────────────────────
RED='\033[38;2;191;97;106m'      # #BF616A
GREEN='\033[38;2;163;190;140m'   # #A3BE8C
YELLOW='\033[38;2;235;203;139m'  # #EBCB8B
BLUE='\033[38;2;129;161;193m'    # #81A1C1
PURPLE='\033[38;2;180;142;173m'  # #B48EAD
CYAN='\033[38;2;136;192;208m'    # #88C0D0
GRAY='\033[38;2;76;86;106m'      # #4C566A (Nord dark gray)
BOLD='\033[1m'
RESET='\033[0m'

# Fancy output formatters with Emojis
info()    { echo -e "${CYAN}${BOLD} ℹ️  ${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD} ✅  ${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD} ⚠️  ${RESET} $*"; }
skip()    { echo -e "${GRAY}${BOLD} ⏭️  ${RESET} ${GRAY}$*${RESET}"; }
prompt()  { echo -e " ${YELLOW}${BOLD}💭 ${RESET}  $*"; }

# 📥 Helper for interactive prompts with defaults.
# Usage: ask "VARIABLE" "Prompt Message" "Default Value"
ask() {
    local var_name=$1
    local prompt_msg=$2
    local default=$3
    local input

    # Visual indicators for y/n
    local display_default=$default
    if [[ "$default" == "y" ]]; then display_default="y"
    elif [[ "$default" == "n" ]]; then display_default="n"
    fi

    # Display prompt with default indicator using the user's requested format
    # "Press ENTER to accept [defaults <default value>] y/n"
    echo -ne " ${YELLOW}${BOLD}💭 ${RESET}  ${prompt_msg} Press ENTER to accept [defaults ${display_default}] y/n: "
    read -r input
    
    local final_val="${input:-$default}"
    
    # Auto-lowercase for y/n responses
    if [[ "$default" == "y" || "$default" == "n" ]]; then
        final_val="${final_val,,}"
    fi

    printf -v "$var_name" "%s" "$final_val"
}

# Beautiful section headers
section() {
    echo -e "\n${CYAN}${BOLD}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    printf   "┃ %-66s ┃\n" "$*"
    echo -e  "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${RESET}"
}

# ── 🔍 OS Detection ───────────────────────────────────────────────────────────
# Dynamically adjusts setup steps depending on whether we are in WSL or Native Linux
IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
fi

# ==============================================================================
# 🛠️ HELPER FUNCTIONS (Idempotency Handlers)
# ==============================================================================

# 📦 Checks if apt packages are installed; installs only what is missing.
# Uses DEBIAN_FRONTEND=noninteractive to completely suppress pink apt prompt screens.
install_apt_packages() {
    local to_install=()
    for pkg in "$@"; do
        # dpkg-query is significantly faster than parsing 'apt list'
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            skip "$pkg is already installed."
        else
            to_install+=("$pkg")
        fi
    done

    if [ ${#to_install[@]} -gt 0 ]; then
        info "Downloading missing packages: ${to_install[*]}"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq "${to_install[@]}"
        success "New packages installed successfully."
    fi
}

# 🔑 Adds an APT repo safely, skipping if the list file already exists.
# Uses modern gpg --dearmor to store keys securely in /etc/apt/keyrings (bypassing deprecated apt-key).
add_repo() {
    local name=$1 url=$2 keyring=$3 repo_line=$4
    local list_file="/etc/apt/sources.list.d/${name}.list"

    if [[ -f "$list_file" ]]; then
        skip "Repo $name is already configured."
    else
        info "Adding ${name} repository..."
        local tmp_key; tmp_key=$(mktemp)
        if ! curl -fsSL --max-time 30 "$url" -o "$tmp_key"; then
            rm -f "$tmp_key"
            warn "Failed to download GPG key for ${name} (${url}). Skipping repo."
            return 0
        fi
        if ! sudo gpg --dearmor -o "$keyring" --yes < "$tmp_key"; then
            rm -f "$tmp_key"; sudo rm -f "$keyring"
            warn "Failed to import GPG key for ${name} (key may be malformed). Skipping repo."
            return 0
        fi
        sudo chmod a+r "$keyring"
        rm -f "$tmp_key"
        echo "$repo_line" | sudo tee "$list_file" > /dev/null
        APT_NEEDS_UPDATE=true
    fi
}

# Used to track if we added new repos so we can run `apt update` at the end of Section 3.
APT_NEEDS_UPDATE=false

# Prints a visual Nord colour palette so the user can preview the theme before choosing.
# Each colour swatch is 8 chars wide; hex codes use %-8s (7-char #XXXXXX + 1 pad space),
# keeping box rows and hex rows pixel-perfect at 62 chars of inner content.
show_nord_palette() {
    echo -e "\n${CYAN}${BOLD}  ❄️  Nord Theme Colour Palette${RESET}"
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════════╗"
    echo -e "  ║                                                              ║"

    # Polar Night (dark backgrounds) — 4 swatches: 15 label + 4×8 = 47; trailing = 15
    printf "  ║  Polar Night  "
    printf "\033[48;2;46;52;64m        \033[0m"   # #2E3440
    printf "\033[48;2;59;66;82m        \033[0m"   # #3B4252
    printf "\033[48;2;67;76;94m        \033[0m"   # #434C5E
    printf "\033[48;2;76;86;106m        \033[0m"  # #4C566A
    printf "               ${CYAN}║\n"
    printf "  ║               "
    printf "%-8s%-8s%-8s%-8s" "#2E3440" "#3B4252" "#434C5E" "#4C566A"
    printf "               ║\n"

    echo -e "  ║                                                              ║"

    # Snow Storm (light text / backgrounds) — 3 swatches: 15 + 3×8 = 39; trailing = 23
    printf "  ║  Snow Storm   "
    printf "\033[48;2;216;222;233m        \033[0m"  # #D8DEE9
    printf "\033[48;2;229;233;240m        \033[0m"  # #E5E9F0
    printf "\033[48;2;236;239;244m        \033[0m"  # #ECEFF4
    printf "                       ${CYAN}║\n"
    printf "  ║               "
    printf "%-8s%-8s%-8s" "#D8DEE9" "#E5E9F0" "#ECEFF4"
    printf "                       ║\n"

    echo -e "  ║                                                              ║"

    # Frost (blues / accents) — 4 swatches: 15 + 4×8 = 47; trailing = 15
    printf "  ║  Frost        "
    printf "\033[48;2;143;188;187m        \033[0m"  # #8FBCBB
    printf "\033[48;2;136;192;208m        \033[0m"  # #88C0D0
    printf "\033[48;2;129;161;193m        \033[0m"  # #81A1C1
    printf "\033[48;2;94;129;172m        \033[0m"   # #5E81AC
    printf "               ${CYAN}║\n"
    printf "  ║               "
    printf "%-8s%-8s%-8s%-8s" "#8FBCBB" "#88C0D0" "#81A1C1" "#5E81AC"
    printf "               ║\n"

    echo -e "  ║                                                              ║"

    # Aurora (accent colours) — 5 swatches: 15 + 5×8 = 55; trailing = 7
    printf "  ║  Aurora       "
    printf "\033[48;2;191;97;106m        \033[0m"   # #BF616A  Red
    printf "\033[48;2;208;135;112m        \033[0m"  # #D08770  Orange
    printf "\033[48;2;235;203;139m        \033[0m"  # #EBCB8B  Yellow
    printf "\033[48;2;163;190;140m        \033[0m"  # #A3BE8C  Green
    printf "\033[48;2;180;142;173m        \033[0m"  # #B48EAD  Purple
    printf "       ${CYAN}║\n"
    printf "  ║               "
    printf "%-8s%-8s%-8s%-8s%-8s" "#BF616A" "#D08770" "#EBCB8B" "#A3BE8C" "#B48EAD"
    printf "       ║\n"

    echo -e "  ║                                                              ║"
    echo -e "  ╚══════════════════════════════════════════════════════════════╝${RESET}\n"
}

# ==============================================================================
# 🧑‍💻 0. INTERACTIVE CONFIGURATION
# All personal / environment-specific values are collected here up front.
# They are used when writing .bashrc, .zshrc, .gitconfig, etc.
# Nothing is hardcoded below this block.
# ==============================================================================
section "❄️  0. Personal Configuration"

echo -e "${CYAN}${BOLD}"
echo "    _   __               __  ______  __                      "
echo "   / | / /___  _________/ / /_  __/ / /_  ___  ____ ___  ___ "
echo "  /  |/ / __ \/ ___/ __  /   / /   / __ \/ _ \/ __ \`__ \/ _ \\"
echo " / /|  / /_/ / /  / /_/ /   / /   / / / /  __/ / / / / /  __/"
echo "/_/ |_/\____/_/   \__,_/   /_/   /_/ /_/\___/_/ /_/ /_/\___/ "
echo -e "${RESET}"

if $IS_WSL; then
    info "Detected OS: 🪟  Windows Subsystem for Linux (WSL)"
else
    info "Detected OS: 🐧  Native Linux (Ubuntu)"
fi

echo ""
echo -e "${CYAN}✨  Answer the prompts below. Press ENTER to accept [defaults <value>] y/n or skip optional items.${RESET}"
echo ""

echo -e "🧹  Overwrite existing dotfiles (~/.bashrc, ~/.zshrc, ~/.vimrc, terminator)?"
ask "OVERWRITE_DOTFILES" "Overwrite dotfiles" "y"

echo ""
echo -e "🔐  Overwrite/Regenerate SSH and GPG keys if they exist?"
ask "OVERWRITE_KEYS" "Overwrite keys" "n"

# ── 🐙 Git Identity ──
echo ""
echo -e "👤  Your full name for git commits (e.g. Jane Doe):"
ask "GIT_NAME" "Git name" ""

echo ""
echo -e "📧  Your PRIMARY git email (e.g. jane@work.com):"
ask "GIT_EMAIL" "Git email" ""

# ── 🐙 GitHub Username ──
echo ""
echo -e "🐙  Your GitHub username (e.g. jdoe):"
ask "GITHUB_USERNAME" "GitHub user" ""

echo ""
echo -e "📝  Create/overwrite ~/.gitconfig with your git identity and settings?"
ask "CREATE_GITCONFIG" "Create gitconfig" "n"

# ── 🔐 SSH & GPG Automation ──
echo ""
echo -e "${CYAN}🔑  SSH key authenticates you with GitHub, GitLab, servers, etc."
echo -e "   new      — generate a fresh Ed25519 key from your git email (recommended)"
echo -e "   existing — import a key pair copied from another machine"
echo -e "   skip     — no SSH key setup${RESET}"
echo ""
echo -e "🔑  Choose your SSH key action."
ask "SSH_ACTION" "SSH key action" "skip"
[[ "$SSH_ACTION" != "new" && "$SSH_ACTION" != "existing" ]] && SSH_ACTION="skip"

GENERATE_SSH="n"
SSH_IMPORT_PRIVATE=""
SSH_IMPORT_PUBLIC=""

if [[ "$SSH_ACTION" == "new" ]]; then
    GENERATE_SSH="y"
elif [[ "$SSH_ACTION" == "existing" ]]; then
    echo ""
    echo -e "${CYAN}   Copy from your old machine first:"
    echo -e "     scp old-machine:~/.ssh/id_ed25519 ~/id_ed25519_import${RESET}"
    echo ""
    echo -e "📥  Path to your SSH private key file (e.g. ~/id_ed25519_import):"
    ask "SSH_IMPORT_PRIVATE" "SSH private key path" ""
    if [[ -n "$SSH_IMPORT_PRIVATE" ]]; then
        echo -e "📥  Path to the matching public key (leave blank to derive it automatically):"
        ask "SSH_IMPORT_PUBLIC" "SSH public key path" ""
    fi
fi

echo ""
echo -e "${CYAN}🛡️  GPG key is used to sign git commits (git commit -S)."
echo -e "   new      — generate a fresh ed25519 key from your git name & email (recommended)"
echo -e "   existing — import a key exported from another machine"
echo -e "   skip     — configure signing manually later${RESET}"
echo ""
echo -e "🛡️  Choose your GPG key action."
ask "GPG_ACTION" "GPG action" "skip"
[[ "$GPG_ACTION" != "new" && "$GPG_ACTION" != "existing" ]] && GPG_ACTION="skip"

CREATE_GPG="n"
GIT_SIGNING_KEY=""
GPG_IMPORT_PATH=""

if [[ "$GPG_ACTION" == "new" ]]; then
    CREATE_GPG="y"
elif [[ "$GPG_ACTION" == "existing" ]]; then
    echo ""
    echo -e "${CYAN}   Export from your old machine:"
    echo -e "     gpg --list-secret-keys --keyid-format=long"
    echo -e "     gpg --export-secret-keys YOUR_KEY_ID > ~/my-gpg-key.gpg${RESET}"
    echo ""
    echo -e "🔑  Enter your GPG signing key ID (16-char hex, e.g. 26F2E8CC98FCFB0F):"
    ask "GIT_SIGNING_KEY" "GPG key ID" ""
    if [[ -n "$GIT_SIGNING_KEY" ]]; then
        echo -e "📥  Path to your backed-up GPG private key file (leave blank to skip auto-import):"
        ask "GPG_IMPORT_PATH" "Import path" ""
    fi
fi

# ── 🔀 Multiple Git Identities ──
echo ""
echo -e "${CYAN}👔  Per-directory git identities let you auto-switch between"
echo -e "   a work email and a personal email based on the repo path.${RESET}"
echo ""
echo -e "🔀  Do you use multiple git identities (personal + work)?"
ask "USE_MULTI_GIT" "Use multiple identities" "n"

if [[ "$USE_MULTI_GIT" == "y" ]]; then
    echo -e "📂  Path pattern for identity #1 (e.g. ~/Github/MyOrg/):"
    ask "GIT_INCLUDE_PATH_1" "Path pattern" ""
    echo -e "📄  Config file for identity #1 (e.g. ~/.gitconfig-myorg):"
    ask "GIT_INCLUDE_FILE_1" "Config file" ""
    echo -e "📂  Path pattern for identity #2 (e.g. ~/Github/WorkOrg/) — leave blank to skip:"
    ask "GIT_INCLUDE_PATH_2" "Path pattern" ""
    echo -e "📄  Config file for identity #2 (e.g. ~/.gitconfig-work):"
    ask "GIT_INCLUDE_FILE_2" "Config file" ""
fi

# ── 📁 Windows Username (WSL Shared Folder Alias) ──
WINDOWS_USER=""
if $IS_WSL; then
    echo ""
    echo -e "${CYAN}📁 The 'shared_folder' alias points to a folder on your Windows C: drive."
    echo -e "   Path will be: /mnt/c/Users/<WINDOWS_USER>/Documents/SharedLinux${RESET}"
    echo ""
    # Try to auto-detect the Windows username from the running WSL session
    DETECTED_WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || true)
    if [[ -n "$DETECTED_WIN_USER" ]]; then
        echo -e "🪟  Confirm your Windows username for shared folder alias."
        ask "WINDOWS_USER_INPUT" "Windows username" "${DETECTED_WIN_USER}"
    else
        echo -e "🪟  Your Windows username (e.g. john.doe) — leave blank to skip alias:"
        ask "WINDOWS_USER_INPUT" "Windows username" ""
    fi
    WINDOWS_USER="${WINDOWS_USER_INPUT}"
fi

# ── 📝 Vim Setup ──
echo ""
echo -e "${CYAN}🪄  The Vim setup installs vim-plug and a full .vimrc with:"
echo -e "   NERDTree, Lightline, Nord theme, auto-pairs, CoC (LSP), fzf.vim${RESET}"
echo ""
echo -e "🪄  Set up Vim with plugins and .vimrc?"
ask "SETUP_VIM" "Setup Vim" "y"

# ── 🐚 Default Shell ──
echo ""
echo -e "🐚  Choose your default login shell."
echo -e "${CYAN}   zsh  — recommended: Oh My Zsh + Powerlevel10k + plugins (installed below)"
echo -e "   bash — simpler, already configured with the custom .bashrc${RESET}"
echo ""
ask "DEFAULT_SHELL_CHOICE" "Default shell" "zsh"
[[ "$DEFAULT_SHELL_CHOICE" != "bash" ]] && DEFAULT_SHELL_CHOICE="zsh"

# ── ❄️  Nord Theme ──
echo ""
show_nord_palette
echo -e "❄️  Apply Nord Theme styling (Vim, Terminal, Shell)?"
ask "APPLY_NORD" "Apply Nord Theme" "y"

# ── 🔤 MesloLGS NF Global Font ──
echo ""
echo -e "${CYAN}🔤 MesloLGS NF is a Nerd Font patched for icons used by Powerlevel10k."
echo -e "   Setting it globally makes it the default monospace font for all GTK apps."
echo -e "   Applies via gsettings (GNOME) and ~/.config/fontconfig/fonts.conf.${RESET}"
echo ""
echo -e "🔤  Set MesloLGS NF as the global monospace font?"
ask "SET_MESLO_GLOBAL" "Set global font" "y"

# ── ☸️  Kubernetes Channel ──
echo ""
echo -e "${CYAN}☸️  The Kubernetes apt channel determines which kubectl minor version is available."
echo -e "   Check current stable at: https://kubernetes.io/releases/${RESET}"
echo ""
echo -e "☸️  Choose your Kubernetes apt channel."
ask "K8S_CHANNEL" "Kubernetes channel" "v1.33"

# ── 🟢 Node.js Version ──
echo ""
echo -e "${CYAN}🟢 Available Node.js LTS versions via NodeSource: 20, 22${RESET}"
echo ""
echo -e "🟢  Choose your Node.js major version."
ask "NODE_VERSION" "Node.js version" "20"

# ── 📋 Summary ────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
echo -e "┃ 📋 Configuration Summary                                           ┃"
echo -e "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${RESET}"
# Helper to print aligned summary lines: emoji, label, value
print_summary() {
    # Use Cursor Horizontal Absolute (CHA) to ensure the label starts at column 7.
    # This handles both 1-column and 2-column emojis consistently across terminals.
    printf "  %s  \033[7G%-20s: ${BOLD}%s${RESET}\n" "$1" "$2" "$3"
}

print_summary "💻" "Detected OS" "$($IS_WSL && echo "WSL" || echo "Native Linux")"
print_summary "🔄" "Overwrite dotfiles" "${OVERWRITE_DOTFILES:-y}"
print_summary "🔄" "Overwrite keys" "${OVERWRITE_KEYS:-n}"
print_summary "👤" "Git name" "${GIT_NAME:-<not set>}"
print_summary "📧" "Git email" "${GIT_EMAIL:-<not set>}"
print_summary "🐙" "GitHub user" "${GITHUB_USERNAME:-<not set>}"
print_summary "🔑" "SSH key action" "${SSH_ACTION}"
if [[ "$SSH_ACTION" == "existing" ]]; then
    print_summary "📥" "SSH private key" "${SSH_IMPORT_PRIVATE:-<not set>}"
fi
print_summary "🛡️" "GPG action" "${GPG_ACTION}"
if [[ "$GPG_ACTION" == "existing" ]]; then
    print_summary "🔑" "GPG key ID" "${GIT_SIGNING_KEY:-<not set>}"
    print_summary "📥" "GPG import path" "${GPG_IMPORT_PATH:-<skipped>}"
fi
if $IS_WSL; then print_summary "🪟" "Windows user" "${WINDOWS_USER:-<not set>}"; fi
print_summary "📝" "Setup Vim" "${SETUP_VIM}"
print_summary "❄️" "Apply Nord Theme" "${APPLY_NORD}"
print_summary "🐚" "Default shell" "${DEFAULT_SHELL_CHOICE}"
print_summary "🔤" "Global font" "${SET_MESLO_GLOBAL}"
print_summary "☸️" "kubectl channel" "${K8S_CHANNEL}"
print_summary "🟢" "Node.js version" "${NODE_VERSION}"
echo ""
ask "CONFIRM_START" "Looks good? Press ENTER to start, or Ctrl+C to abort" "y"

# ── ⚙️ Pre-flight calculations ──
# Resolved here so both .bashrc and .zshrc can use the same placeholder logic.
# COMMIT_FLAGS drives the git commit command inside the 'gacp' function.
COMMIT_FLAGS=$([[ -n "$GIT_SIGNING_KEY" ]] && echo "-S -m" || echo "-m")
TERMINATOR_PROFILE=$([[ "$APPLY_NORD" == "y" ]] && echo "Nord" || echo "default")

# ── ❄️  Theme Helper ──
# If the user declined the Nord theme, this function strips Nord-specific
# lines and blocks from the generated configuration files.
apply_theme_choice() {
    local file=$1
    if [[ "$APPLY_NORD" == "y" ]]; then
        # Keep Nord, Remove Default
        sed -i '/NORD_THEME_START/d; /NORD_THEME_END/d' "$file"
        sed -i '/DEFAULT_THEME_START/,/DEFAULT_THEME_END/d' "$file"
    else
        # Keep MesloLGS globalDefault, Remove Nord
        sed -i '/NORD_THEME_START/,/NORD_THEME_END/d' "$file"
        sed -i '/DEFAULT_THEME_START/d; /DEFAULT_THEME_END/d' "$file"
    fi
    # Also handle the Terminator profile placeholder if it exists
    sed -i "s|__TERMINATOR_PROFILE__|${TERMINATOR_PROFILE}|g" "$file" 2>/dev/null || true
}


# ==============================================================================
# 🔐 SUDO KEEP-ALIVE
# Prevents password prompts mid-script by updating the user's timestamp.
# ==============================================================================
info "Caching sudo credentials so you can grab a coffee..."
sudo -v
# Background process ID is captured so the trap can kill it instantly on exit.
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_PID=$!


# ==============================================================================
# 📝  1. WRITE ~/.bashrc AND ACTIVATE ENVIRONMENT
# Written first so PATH, GPG_TTY, and environment variables are available
# for the rest of this script session.
# ==============================================================================
section "📝  1. Writing ~/.bashrc & Activating Environment"

if [[ -f ~/.bashrc ]] && [[ "$OVERWRITE_DOTFILES" != "y" ]]; then
    skip "~/.bashrc already exists and overwrite is disabled."
else
    if [[ -f ~/.bashrc ]]; then
        BASHRC_BACKUP="$HOME/.bashrc.backup.$(date +%Y%m%d%H%M%S)"
        cp ~/.bashrc "$BASHRC_BACKUP" 2>/dev/null || true
        warn "Existing default .bashrc backed up to $BASHRC_BACKUP"
    fi
    sudo rm -f ~/.bashrc

    info "Writing ~/.bashrc..."

    # Using 'BASHRC_EOF' (with quotes) prevents variable expansion during the write,
    # ensuring literal strings like $PATH are perfectly preserved in the final file.
    cat << 'BASHRC_EOF' > ~/.bashrc
# ✨ WSL / Native Ubuntu 24.04 — Full Dev Environment
# ==============================================================================
# 1. BASH CORE & COMPLETIONS
# ==============================================================================
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# ==============================================================================
# 2. HISTORY CONFIGURATION
# ==============================================================================
HISTFILE="$HOME/.bash_history"
HISTSIZE=100000   # Capped at 100k for performance
HISTFILESIZE=100000
HISTTIMEFORMAT="%d/%m/%Y "

shopt -s histappend                      # Append to history, don't overwrite it
HISTCONTROL=ignoreboth:erasedups         # Ignore duplicates and spaces

# ==============================================================================
# 3. EXPORTS & ENVIRONMENT VARIABLES
# ==============================================================================
export COLORTERM=truecolor
# --- NORD_THEME_START ---
export BAT_THEME="Nord"
# --- NORD_THEME_END ---
# --- DEFAULT_THEME_START ---
export BAT_THEME="base16"
# --- DEFAULT_THEME_END ---
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
export LANG=en_US.UTF-8
export VISUAL=vim
export EDITOR=vi
export GPG_TTY=$(tty)
export XDG_RUNTIME_DIR="/tmp/runtime-$USER"

if [ ! -d "$XDG_RUNTIME_DIR" ]; then mkdir -p "$XDG_RUNTIME_DIR"; chmod 0700 "$XDG_RUNTIME_DIR"; fi

[ -f ~/.aliases_cluster.zsh ] && source ~/.aliases_cluster.zsh
[ -f ~/.aliases_ssh.zsh ]     && source ~/.aliases_ssh.zsh
[ -f ~/.aliases_secret.zsh ] && source ~/.aliases_secret.zsh

# ==============================================================================
# 4. ALIASES (Modern CLI & QoL)
# ==============================================================================
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

alias ls="eza --color=always --icons --group-directories-first"
alias ll="eza -la --icons --group-directories-first --git"
alias cat="batcat --style=plain --paging=never"

alias gco="git checkout"
alias gcb="git checkout -b"
alias gfpo="git fetch --prune origin"
alias gbd="git branch -D"

alias git-perms-on="git config core.filemode true && echo '✅  Git is now TRACKING file permissions.'"
alias git-perms-off="git config core.filemode false && echo '🚫  Git is now IGNORING file permissions.'"

alias bashconfig="vim ~/.bashrc"
alias vimconfig="vim ~/.vimrc"
alias bash_reload="source ~/.bashrc"

# ==============================================================================
# 5. WSL SPECIFIC CONFIGURATION
# ==============================================================================
if grep -qi microsoft /proc/version 2>/dev/null; then
    export GALLIUM_DRIVER=d3d12
    alias explorer="explorer.exe ."
    alias chrome='google-chrome --use-angle=vulkan --use-vulkan --enable-features=Vulkan --ignore-gpu-blocklist &'
    # __WINDOWS_USER_ALIAS__
fi

# ==============================================================================
# 6. FUNCTIONS & PROMPT COMMAND
# ==============================================================================
function refresh_gpg_tty {
    export GPG_TTY=$(tty)
    gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
}

function __custom_prompt_cmd() {
    history -a; history -n; history -c; history -r
    refresh_gpg_tty
}
PROMPT_COMMAND="__custom_prompt_cmd"

function gacp {
    if [ -z "$1" ]; then
        echo -e "❌  \033[1;38;2;191;97;106mError: Please provide a commit message.\033[0m"
        echo -e "💡  \033[1;38;2;129;161;193mUsage: gacp \"your commit message\"\033[0m"
        return 1
    fi
    echo -e "\n🚀  \033[1;38;2;129;161;193mStarting Git workflow...\033[0m\n"
    echo -e "📦  \033[1;38;2;235;203;139m1. Staging all files (git add -A)...\033[0m"
    git add -A
    echo -e "\n✍️   \033[1;38;2;180;142;173m2. Committing changes...\033[0m"
    if ! git commit __COMMIT_FLAGS__ "$*"; then
        echo -e "\n❌  \033[1;38;2;191;97;106mCommit failed! Aborting push.\033[0m"
        return 1
    fi
    echo -e "\n☁️   \033[1;38;2;136;192;208m3. Pushing to remote repository...\033[0m"
    if ! git push; then
        echo -e "\n❌  \033[1;38;2;191;97;106mPush failed!\033[0m"
        return 1
    fi
    echo -e "\n✅  \033[1;38;2;163;190;140mSuccess! Final Git Status:\033[0m"
    echo -e "--------------------------------------------------"
    git status
}

function connect_cluster () {
    if [ "$#" -lt 3 ]; then
        echo 'Usage: connect_cluster <subscription> <resource-group> <cluster-name>'
        return 1
    fi
    local SUBSCRIPTION="$1"
    local RG="$2"
    local CLUSTER="$3"
    export KUBECONFIG="$HOME/.kube/config_${CLUSTER}"
    echo "☸️  Connecting to ${CLUSTER}..."
    az account set --subscription "${SUBSCRIPTION}"
    az aks get-credentials --resource-group "${RG}" --name "${CLUSTER}" --overwrite-existing
    if command -v kubelogin &> /dev/null; then
        kubelogin convert-kubeconfig -l azurecli
    fi
    export PS1="\[\e[38;2;136;192;208m\]☸️  ${CLUSTER^^}\[\e[0m\] \u@\h:\w $ "
}

# ==============================================================================
# 7. FZF SUPERCHARGED (Nord Theme + Previews)
# ==============================================================================
# --- NORD_THEME_START ---
export FZF_DEFAULT_OPTS="
  --color=fg:#e5e9f0,bg:#3b4252,hl:#81a1c1
  --color=fg+:#e5e9f0,bg+:#4c566a,hl+:#81a1c1
  --color=info:#ebcb8b,prompt:#bf616a,pointer:#b48ead
  --color=marker:#a3be8c,spinner:#b48ead,header:#a3be8c
  --border=rounded --margin=1 --padding=1"
# --- NORD_THEME_END ---
# --- DEFAULT_THEME_START ---
export FZF_DEFAULT_OPTS="--border=rounded --margin=1 --padding=1"
# --- DEFAULT_THEME_END ---
export FZF_CTRL_T_OPTS="
  --preview '(batcat --style=numbers --color=always {} || cat {}) 2> /dev/null | head -200'
  --preview-window=right:60%:border-rounded"
export FZF_CTRL_R_OPTS="
  --sort --exact
  --preview 'echo {}' --preview-window down:3:hidden:wrap
  --bind '?:toggle-preview'"

[ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && source /usr/share/doc/fzf/examples/key-bindings.bash
[ -f /usr/share/doc/fzf/examples/completion.bash ] && source /usr/share/doc/fzf/examples/completion.bash

# ==============================================================================
# 8. NORD PALETTE & VISUALS
# ==============================================================================
# --- NORD_THEME_START ---
function apply_nord_palette() {
    printf "\033]10;#D8DEE9\007"; printf "\033]11;#2E3440\007"; printf "\033]12;#D8DEE9\007"
    printf "\033]4;0;#3B4252\007"; printf "\033]4;1;#BF616A\007"; printf "\033]4;2;#A3BE8C\007"
    printf "\033]4;3;#EBCB8B\007"; printf "\033]4;4;#81A1C1\007"; printf "\033]4;5;#B48EAD\007"
    printf "\033]4;6;#88C0D0\007"; printf "\033]4;7;#E5E9F0\007"; printf "\033]4;8;#4C566A\007"
    printf "\033]4;9;#BF616A\007"; printf "\033]4;10;#A3BE8C\007"; printf "\033]4;11;#EBCB8B\007"
    printf "\033]4;12;#81A1C1\007"; printf "\033]4;13;#B48EAD\007"; printf "\033]4;14;#8FBCBB\007"
    printf "\033]4;15;#ECEFF4\007"
}
apply_nord_palette > /dev/null 2>&1
# --- NORD_THEME_END ---

function maincolors() {
    local hex=("#3B4252" "#BF616A" "#A3BE8C" "#EBCB8B" "#81A1C1" "#B48EAD" "#88C0D0" "#E5E9F0" "#4C566A" "#BF616A" "#A3BE8C" "#EBCB8B" "#81A1C1" "#B48EAD" "#8FBCBB" "#ECEFF4")
    echo -e "\nStandard Colors (0-7):"
    for i in {0..7}; do printf "\e[48;5;%sm              \e[0m " "$i"; done; echo ""
    for i in {0..7}; do printf "\e[48;5;%sm      %02d      \e[0m " "$i" "$i"; done; echo ""
    for i in {0..7}; do printf "\e[48;5;%sm              \e[0m " "$i"; done; echo ""
    for i in {0..7}; do printf "  %-7s      " "${hex[$i]}"; done; echo -e "\n"
   
    echo "Bright Colors (8-15):"
    for i in {8..15}; do printf "\e[48;5;%sm              \e[0m " "$i"; done; echo ""
    for i in {8..15}; do printf "\e[48;5;%sm      %02d      \e[0m " "$i" "$i"; done; echo ""
    for i in {8..15}; do printf "\e[48;5;%sm              \e[0m " "$i"; done; echo ""
    for i in {8..15}; do printf "  %-7s      " "${hex[$i]}"; done; echo -e "\n"
}

function fm() {
  pcmanfm "$@" > /dev/null 2>&1 &
}

# ==============================================================================
# 9. COMPLETIONS
# ==============================================================================
if command -v kubectl &> /dev/null; then
    source <(kubectl completion bash)
    alias k=kubectl; complete -o default -F __start_kubectl k
fi
eval "$(register-python-argcomplete pipx 2>/dev/null || echo '')"
if command -v zoxide &> /dev/null; then eval "$(zoxide init bash)"; fi
BASHRC_EOF

    # Dynamic alias insertion based on user inputs collected at the beginning of the script
    if [[ -n "$WINDOWS_USER" ]]; then
        sed -i "s|# __WINDOWS_USER_ALIAS__|alias shared_folder=\"cd /mnt/c/Users/${WINDOWS_USER}/Documents/SharedLinux\"|g" ~/.bashrc
    fi
    sed -i "s|__COMMIT_FLAGS__|${COMMIT_FLAGS}|g" ~/.bashrc
    apply_theme_choice ~/.bashrc
    success "~/.bashrc created."
fi

info "Activating environment..."
set +euo pipefail
# shellcheck disable=SC1090
source ~/.bashrc 2>/dev/null || true
set -euo pipefail
success "Environment active. ✨"


# ==============================================================================
# 🔄  2. SYSTEM UPDATE & ESSENTIAL PREREQUISITES
# Download agents, build tools, font builders, and crypto engines.
# ==============================================================================
section "🔄  2. System Update & Essential Prerequisites"

info "Cleaning up legacy/conflicting repository configurations..."
# Remove old/conflicting NodeSource, Azure CLI, and lazygit entries
sudo rm -f /usr/share/keyrings/nodesource.gpg
sudo rm -f /etc/apt/sources.list.d/nodesource.sources
sudo rm -f /etc/apt/sources.list.d/nodesource.list
sudo rm -f /etc/apt/sources.list.d/azure-cli.sources
sudo rm -f /etc/apt/sources.list.d/*lazygit*

# Remove ALL Docker source list files and both keyring formats (wildcard catches any variant
# created by docker's own convenience script, prior runs, or manual installs).
# add_repo will recreate them cleanly with the correct .gpg binary keyring.
sudo rm -f /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg
sudo rm -f /etc/apt/sources.list.d/docker*.list /etc/apt/sources.list.d/docker*.sources
# Belt-and-suspenders: remove any other source file that references the Docker CDN
sudo grep -rl "download\.docker\.com" /etc/apt/sources.list.d/ 2>/dev/null \
    | xargs --no-run-if-empty sudo rm -f || true

info "Refreshing APT index and upgrading packages..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -yq
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq

info "Checking base dependencies..."
install_apt_packages \
    apt-transport-https ca-certificates curl wget gnupg gpg lsb-release \
    software-properties-common build-essential fontconfig unzip zip p7zip \
    tar git vim pinentry-curses


# ==============================================================================
# 🔑  3. THIRD-PARTY APT REPOSITORIES & GPG KEYS
# Modern keyring storage for all our Dev & DevOps tools.
# ==============================================================================
section "🔑  3. Adding Third-Party APT Repositories"

info "Ensuring /etc/apt/keyrings/ exists..."
sudo install -m 0755 -d /etc/apt/keyrings

add_repo "docker" "https://download.docker.com/linux/ubuntu/gpg" "/etc/apt/keyrings/docker.gpg" \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

if [[ -f "/etc/apt/sources.list.d/github-cli.list" ]]; then
    skip "Repo GitHub CLI is already configured."
else
    info "Configuring GitHub CLI..."
    gh_tmp=$(mktemp)
    if curl -fsSL --max-time 30 "https://cli.github.com/packages/githubcli-archive-keyring.gpg" -o "$gh_tmp"; then
        if sudo dd if="$gh_tmp" of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null; then
            sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
            APT_NEEDS_UPDATE=true
        else
            warn "Failed to write GitHub CLI keyring. Skipping repo."
        fi
    else
        warn "Failed to download GitHub CLI GPG key. Skipping repo."
    fi
    rm -f "$gh_tmp"
fi

add_repo "google-chrome" "https://dl.google.com/linux/linux_signing_key.pub" "/etc/apt/keyrings/google-chrome.gpg" \
    "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main"

add_repo "google-cloud-sdk" "https://packages.cloud.google.com/apt/doc/apt-key.gpg" "/etc/apt/keyrings/cloud.google.gpg" \
    "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main"

add_repo "kubernetes" "https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/deb/Release.key" "/etc/apt/keyrings/kubernetes-apt-keyring.gpg" \
    "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/deb/ /"

add_repo "hashicorp" "https://apt.releases.hashicorp.com/gpg" "/etc/apt/keyrings/hashicorp-archive-keyring.gpg" \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

add_repo "azure-cli" "https://packages.microsoft.com/keys/microsoft.asc" "/etc/apt/keyrings/microsoft.gpg" \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main"

add_repo "gierens" "https://raw.githubusercontent.com/eza-community/eza/main/deb.asc" "/etc/apt/keyrings/gierens.gpg" \
    "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main"

if [[ -f "/etc/apt/sources.list.d/ansible-ubuntu-ansible-$(lsb_release -cs).list" ]]; then
    skip "Repo Ansible PPA is already configured."
else
    info "Adding Ansible PPA..."
    if sudo add-apt-repository -y ppa:ansible/ansible >/dev/null 2>&1; then
        APT_NEEDS_UPDATE=true
    else
        warn "Failed to add Ansible PPA. Skipping."
    fi
fi

if [[ -f "/etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-$(lsb_release -cs).list" ]]; then
    skip "Repo Deadsnakes PPA is already configured."
else
    info "Adding Deadsnakes PPA (Python 3.11 + 3.12 dev)..."
    if sudo add-apt-repository -y ppa:deadsnakes/ppa >/dev/null 2>&1; then
        APT_NEEDS_UPDATE=true
    else
        warn "Failed to add Deadsnakes PPA. Skipping."
    fi
fi

if [[ -f "/etc/apt/sources.list.d/nodesource.list" ]] || [[ -f "/etc/apt/sources.list.d/nodesource.sources" ]]; then
    skip "Repo NodeSource is already configured."
else
    info "Adding NodeSource (Node.js ${NODE_VERSION})..."
    sudo rm -f /usr/share/keyrings/nodesource.gpg
    sudo rm -f /etc/apt/sources.list.d/nodesource.sources
    node_tmp=$(mktemp)
    if curl -fsSL --max-time 30 "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" -o "$node_tmp"; then
        if sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes < "$node_tmp"; then
            sudo chmod a+r /etc/apt/keyrings/nodesource.gpg
            echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION}.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
            APT_NEEDS_UPDATE=true
        else
            warn "Failed to process NodeSource GPG key (key may be malformed). Skipping Node.js repo."
        fi
    else
        warn "Failed to download NodeSource GPG key. Skipping Node.js repo."
    fi
    rm -f "$node_tmp"
fi

if $APT_NEEDS_UPDATE; then
    info "New repositories added. Refreshing APT index..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -yq
    success "APT index updated."
fi


# ==============================================================================
# 📦  4. MAIN APT PACKAGE INSTALL
# This installs the bulk of the toolchain. Sit back and relax.
# ==============================================================================
section "📦  4. Installing APT Packages"

info "Installing main package groups (this might take a few minutes)..."

APT_PACKAGES=(
    # ── 💻 Developer Essentials ──
    git-lfs vim-gtk3 bat fzf jq xclip bind9-dnsutils extundelete sshuttle ripgrep fd-find tmux

    # ── 🐚 Shell & Terminal Environment ──
    zsh powerline powerline-doc powerline-gitstatus python3-powerline-gitstatus fonts-powerline terminator imagemagick pcmanfm mousepad

    # ── 🐍 Python ──
    python3 python3-pip python3-venv python3-requests
    python3.11 python3.11-dev python3.11-venv
    python3.12 python3.12-dev python3.12-venv pipx

    # ── ☕ Java & JVM Build Tools ──
    openjdk-21-jdk openjdk-21-jre maven gradle

    # ── 🐳 Containers ──
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # ── ☁️  Cloud & DevOps Toolchain ──
    kubectl terraform ansible azure-cli google-cloud-cli google-cloud-sdk-gke-gcloud-auth-plugin

    # ── 🌐 Browser & Modern CLI ──
    google-chrome-stable eza zoxide gh nodejs

    # ── 🖼️  WSL Display & GPU ──
    xvfb dbus-x11 mesa-utils mesa-vulkan-drivers xfonts-cyrillic xfonts-scalable libsecret-1-0

    # ── 🔤 Fonts ──
    fonts-font-awesome fonts-freefont-ttf fonts-ipafont-gothic fonts-liberation
    fonts-noto-color-emoji fonts-tlwg-loma-otf fonts-unifont fonts-wqy-zenhei
)

install_apt_packages "${APT_PACKAGES[@]}"

if git config --global --get filter.lfs.process >/dev/null 2>&1; then
    skip "Git LFS is already activated."
else
    info "Activating git-lfs filters..."
    git lfs install || warn "git lfs install failed — LFS filters may not be active."
fi

if getent group docker | grep -q "\b$USER\b"; then
    skip "User $USER is already in the 'docker' group."
else
    info "Adding $USER to the 'docker' group..."
    sudo usermod -aG docker "$USER" || warn "Failed to add $USER to docker group — run 'sudo usermod -aG docker $USER' manually."
    getent group docker | grep -q "\b$USER\b" && success "Docker group added."
fi


# ==============================================================================
# 🫰  5. SNAP PACKAGES
# ==============================================================================
section "🫰  5. Snap Packages"
if command -v yq &> /dev/null; then
    skip "yq is already installed."
else
    info "Installing yq via snap..."
    sudo snap install yq || warn "yq snap install failed. Skipping."
    command -v yq &>/dev/null && success "yq installed."
fi


# ==============================================================================
# 🔤  6. FONTS (Meslo Nerd Fonts & Font Awesome)
# ==============================================================================
section "🔤  6. Installing Custom Fonts"

mkdir -p ~/.local/share/fonts
FONTS_WERE_DOWNLOADED=false
WGET_PIDS=()

# ── Meslo Nerd Fonts ──
info "Downloading Meslo Nerd Fonts concurrently..."
FONT_BASE="https://github.com/romkatv/powerlevel10k-media/raw/master"
FONTS=("MesloLGS%20NF%20Regular.ttf" "MesloLGS%20NF%20Bold.ttf" "MesloLGS%20NF%20Italic.ttf" "MesloLGS%20NF%20Bold%20Italic.ttf")

for FONT_FILE in "${FONTS[@]}"; do
    TARGET="$HOME/.local/share/fonts/${FONT_FILE//%20/ }"
    if [[ ! -f "$TARGET" ]]; then
        wget -qO "$TARGET" "${FONT_BASE}/${FONT_FILE}" &
        WGET_PIDS+=($!) # Capture the exact PID to wait for later
        FONTS_WERE_DOWNLOADED=true
    else
        skip "${FONT_FILE//%20/ } already exists."
    fi
done

# Wait ONLY for the Meslo font downloads (ignores the sudo keep-alive)
if [[ ${#WGET_PIDS[@]} -gt 0 ]]; then
    wait "${WGET_PIDS[@]}" || warn "One or more Meslo font downloads failed; fonts may be incomplete."
fi

# ── Font Awesome Desktop (Free) ──
if ls ~/.local/share/fonts/*Font\ Awesome* 1> /dev/null 2>&1; then
    skip "Font Awesome is already installed in ~/.local/share/fonts."
else
    info "Downloading Font Awesome Desktop (Free)..."
    FA_ZIP="/tmp/fontawesome.zip"
    FA_DIR="/tmp/fontawesome_extracted"

    FA_VERSION=$(curl -fsSL --max-time 30 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/FortAwesome/Font-Awesome/releases/latest" \
        | grep '"tag_name"' | cut -d'"' -f4 || true)

    if [[ -z "$FA_VERSION" ]]; then
        warn "Could not fetch Font Awesome version from GitHub API (rate-limit or network). Skipping."
    else
        # GitHub Releases is the correct source for FA6 desktop zips (use.fontawesome.com CDN is FA5-era only)
        FA_URL="https://github.com/FortAwesome/Font-Awesome/releases/download/${FA_VERSION}/fontawesome-free-${FA_VERSION#v}-desktop.zip"
        if ! wget -qO "$FA_ZIP" "$FA_URL"; then
            warn "Font Awesome download failed (${FA_URL}). Skipping."
        elif ! unzip -qo "$FA_ZIP" -d "$FA_DIR" 2>/dev/null; then
            warn "Font Awesome archive extraction failed. Skipping."
        else
            find "$FA_DIR" -name "*.otf" -exec cp {} ~/.local/share/fonts/ \;
            FONTS_WERE_DOWNLOADED=true
            success "Font Awesome Free ${FA_VERSION} installed."
        fi
    fi
fi

if $FONTS_WERE_DOWNLOADED; then
    info "Rebuilding Linux font cache..."
    fc-cache -f > /dev/null || warn "fc-cache failed — fonts may not be immediately visible."
    success "Font cache rebuilt."
fi



# ── 🔤 Global Monospace Font ──
if [[ "$SET_MESLO_GLOBAL" == "y" ]]; then
    info "Setting MesloLGS NF as the global monospace font..."

    # GNOME / GTK apps via gsettings
    if command -v gsettings &>/dev/null; then
        gsettings set org.gnome.desktop.interface monospace-font-name 'MesloLGS NF 11' 2>/dev/null \
            && success "gsettings: monospace font set to 'MesloLGS NF 11'." \
            || warn "gsettings not available in this session (headless). fontconfig will still apply."
    fi

    # fontconfig: preferred monospace family for all apps (terminal, VS Code, etc.)
    mkdir -p ~/.config/fontconfig
    sudo rm -f ~/.config/fontconfig/fonts.conf
    cat > ~/.config/fontconfig/fonts.conf << 'FONTCONF_EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>MesloLGS NF</family>
    </prefer>
  </alias>
</fontconfig>
FONTCONF_EOF
    success "fontconfig: MesloLGS NF set as preferred monospace in ~/.config/fontconfig/fonts.conf."
else
    info "Setting system default monospace (Ubuntu Mono / DejaVu Sans Mono)..."
    if command -v gsettings &>/dev/null; then
        gsettings set org.gnome.desktop.interface monospace-font-name 'Ubuntu Mono 11' 2>/dev/null \
            || gsettings set org.gnome.desktop.interface monospace-font-name 'Monospace 11' 2>/dev/null \
            || true
    fi
    mkdir -p ~/.config/fontconfig
    sudo rm -f ~/.config/fontconfig/fonts.conf
    cat > ~/.config/fontconfig/fonts.conf << 'FONTCONF_EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>Ubuntu Mono</family>
      <family>DejaVu Sans Mono</family>
      <family>Liberation Mono</family>
    </prefer>
  </alias>
</fontconfig>
FONTCONF_EOF
    success "fontconfig: set Ubuntu Mono / DejaVu Sans Mono as preferred monospace."
fi


# ==============================================================================
# ⚙️   7. BINARIES (Helm, Kubelogin, Helmfile, Lazygit)
# ==============================================================================
section "⚙️  7. Binaries"

if command -v helm &> /dev/null; then
    skip "Helm is already installed."
else
    info "Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null || warn "Helm install script failed. Skipping."
    command -v helm &>/dev/null && success "Helm installed."
fi

if command -v kubelogin &> /dev/null; then
    skip "kubelogin is already installed."
else
    info "Installing kubelogin..."
    KUBELOGIN_VERSION=$(curl -fsSL --max-time 30 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/Azure/kubelogin/releases/latest" | grep '"tag_name"' | cut -d'"' -f4 || true)
    if [[ -z "$KUBELOGIN_VERSION" ]]; then
        warn "Could not determine kubelogin version from GitHub API. Skipping."
    elif ! curl -fsSL --max-time 120 "https://github.com/Azure/kubelogin/releases/download/${KUBELOGIN_VERSION}/kubelogin-linux-amd64.zip" -o /tmp/kubelogin.zip; then
        warn "Failed to download kubelogin ${KUBELOGIN_VERSION}. Skipping."
    elif ! unzip -qo /tmp/kubelogin.zip -d /tmp/kubelogin-bin 2>/dev/null; then
        warn "Failed to extract kubelogin archive. Skipping."
    else
        sudo mv /tmp/kubelogin-bin/bin/linux_amd64/kubelogin /usr/local/bin/kubelogin
        sudo chmod +x /usr/local/bin/kubelogin
        success "kubelogin installed."
    fi
fi

if command -v helmfile &> /dev/null; then
    skip "Helmfile is already installed."
else
    info "Installing Helmfile..."
    HELMFILE_VERSION=$(curl -fsSL --max-time 30 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/helmfile/helmfile/releases/latest" | grep '"tag_name"' | cut -d'"' -f4 || true)
    if [[ -z "$HELMFILE_VERSION" ]]; then
        warn "Could not determine Helmfile version from GitHub API. Skipping."
    elif ! curl -fsSL --max-time 120 "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION#v}_linux_amd64.tar.gz" -o /tmp/helmfile.tar.gz; then
        warn "Failed to download Helmfile ${HELMFILE_VERSION}. Skipping."
    elif ! tar -xzf /tmp/helmfile.tar.gz -C /tmp helmfile 2>/dev/null; then
        warn "Failed to extract Helmfile archive. Skipping."
    else
        sudo mv /tmp/helmfile /usr/local/bin/helmfile
        sudo chmod +x /usr/local/bin/helmfile
        success "Helmfile installed."
    fi
fi

if command -v lazygit &> /dev/null; then
    skip "lazygit is already installed."
else
    info "Installing lazygit..."
    LAZYGIT_VERSION=$(curl -fsSL --max-time 30 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep '"tag_name"' | cut -d'"' -f4 | sed 's/v//' || true)
    if [[ -z "$LAZYGIT_VERSION" ]]; then
        warn "Could not determine lazygit version from GitHub API. Skipping."
    elif ! curl -fsSL --max-time 120 "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" -o /tmp/lazygit.tar.gz; then
        warn "Failed to download lazygit ${LAZYGIT_VERSION}. Skipping."
    elif ! tar -xzf /tmp/lazygit.tar.gz -C /tmp lazygit 2>/dev/null; then
        warn "Failed to extract lazygit archive. Skipping."
    else
        sudo mv /tmp/lazygit /usr/local/bin/lazygit
        sudo chmod +x /usr/local/bin/lazygit
        success "lazygit installed."
    fi
fi


# ==============================================================================
# 🐍  8. PIPX CLI TOOLS
# ==============================================================================
section "🐍  8. pipx CLI Tools"
pipx ensurepath > /dev/null 2>&1 || true
if command -v git-filter-repo &> /dev/null; then
    skip "git-filter-repo is already installed."
else
    info "Installing git-filter-repo..."
    pipx install git-filter-repo >/dev/null 2>&1 || warn "git-filter-repo install failed (pipx/network error). Skipping."
    command -v git-filter-repo &>/dev/null && success "git-filter-repo installed."
fi


# ==============================================================================
# 🐚  9. OH MY ZSH & PLUGINS
# ==============================================================================
section "🐚  9. Oh My Zsh & Plugins"

if [[ -d "$HOME/.oh-my-zsh" ]] && [[ "$OVERWRITE_DOTFILES" != "y" ]]; then
    skip "Oh My Zsh is already installed and overwrite is disabled."
else
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        info "Backing up existing Oh My Zsh..."
        mv "$HOME/.oh-my-zsh" "$HOME/.oh-my-zsh.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || sudo rm -rf "$HOME/.oh-my-zsh"
    fi
    info "Installing Oh My Zsh..."
    # --unattended: prevents the script from pausing to drop us into a subshell
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || warn "Oh My Zsh install failed — check network and retry."
    [[ -d "$HOME/.oh-my-zsh" ]] && success "Oh My Zsh installed."
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [[ -d "$ZSH_CUSTOM/themes/powerlevel10k" ]] && [[ "$OVERWRITE_DOTFILES" != "y" ]]; then
    skip "Powerlevel10k is already cloned."
else
    [[ -d "$ZSH_CUSTOM/themes/powerlevel10k" ]] && sudo rm -rf "$ZSH_CUSTOM/themes/powerlevel10k"
    info "Cloning Powerlevel10k theme..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k" >/dev/null 2>&1 || warn "Failed to clone Powerlevel10k — check network."
    [[ -d "$ZSH_CUSTOM/themes/powerlevel10k" ]] && success "Powerlevel10k cloned."
fi

if [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] && [[ "$OVERWRITE_DOTFILES" != "y" ]]; then
    skip "zsh-autosuggestions is already cloned."
else
    [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] && sudo rm -rf "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    info "Cloning zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" >/dev/null 2>&1 || warn "Failed to clone zsh-autosuggestions — check network."
    [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] && success "zsh-autosuggestions cloned."
fi

if [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] && [[ "$OVERWRITE_DOTFILES" != "y" ]]; then
    skip "zsh-syntax-highlighting is already cloned."
else
    [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] && sudo rm -rf "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    info "Cloning zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" >/dev/null 2>&1 || warn "Failed to clone zsh-syntax-highlighting — check network."
    [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] && success "zsh-syntax-highlighting cloned."
fi


# ==============================================================================
# 🐙  10. GIT CONFIGURATION
# Matches the precise layout requested, populated with dynamic variables.
# ==============================================================================
section "🐙  10. Git Configuration"

if [[ "$CREATE_GITCONFIG" != "y" ]]; then
    skip "Skipping ~/.gitconfig — user opted out."
else
    if [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
        if [[ -f ~/.gitconfig ]]; then
            cp ~/.gitconfig "$HOME/.gitconfig.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
            warn "Existing ~/.gitconfig backed up."
        fi
        sudo rm -f ~/.gitconfig

        info "Writing ~/.gitconfig..."

        # Note: We use unquoted EOF here so variables like ${GIT_NAME} can expand
        cat << EOF > ~/.gitconfig
[user]
    name = ${GIT_NAME}
    email = ${GIT_EMAIL}
EOF

        if [[ -n "$GIT_SIGNING_KEY" ]]; then
            cat << EOF >> ~/.gitconfig
    signingkey = ${GIT_SIGNING_KEY}
EOF
        fi

        cat << EOF >> ~/.gitconfig
[push]
    autoSetupRemote = true
[pull]
    rebase = true
[filter "lfs"]
    process = git-lfs filter-process
    required = true
    clean = git-lfs clean -- %f
    smudge = git-lfs smudge -- %f
EOF

        if [[ -n "$GIT_SIGNING_KEY" ]]; then
            cat << EOF >> ~/.gitconfig
[commit]
    gpgsign = true
EOF
        fi

        # We switch to quoted 'EOF' here because we want literal strings (like \")
        # to bypass bash parsing completely. Also using xargs -r prevents errors if empty.
        cat << 'EOF' >> ~/.gitconfig
[alias]
    cleanup = "!f() { git branch | grep -vE \"main|develop|\\*\" | xargs -r git branch -D; }; f"
[init]
    defaultBranch = main
EOF

        if [[ "$USE_MULTI_GIT" == "y" ]]; then
            if [[ -n "${GIT_INCLUDE_PATH_1:-}" ]]; then
                cat << EOF >> ~/.gitconfig

[includeIf "gitdir:${GIT_INCLUDE_PATH_1}"]
    path = ${GIT_INCLUDE_FILE_1}
EOF
            fi
            if [[ -n "${GIT_INCLUDE_PATH_2:-}" ]]; then
                cat << EOF >> ~/.gitconfig

[includeIf "gitdir:${GIT_INCLUDE_PATH_2}"]
    path = ${GIT_INCLUDE_FILE_2}
EOF
            fi
        fi

        cat << EOF >> ~/.gitconfig
[core]
    filemode = false
EOF
        success "~/.gitconfig written. 📝"
    else
        skip "Git name/email not provided — skipping .gitconfig."
    fi
fi


# ==============================================================================
# 🔐  11. SSH & GPG KEYS
# Generates or imports an Ed25519 SSH key; generates a new GPG key or imports an existing one.
# ==============================================================================
section "🔐  11. SSH & GPG Keys"

if [[ "$GENERATE_SSH" == "y" && -n "$GIT_EMAIL" ]]; then
    if [[ -f ~/.ssh/id_ed25519 ]] && [[ "$OVERWRITE_KEYS" != "y" ]]; then
        skip "SSH key ~/.ssh/id_ed25519 already exists."
    else
        if [[ -f ~/.ssh/id_ed25519 ]]; then
            cp ~/.ssh/id_ed25519 "$HOME/.ssh/id_ed25519.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
            cp ~/.ssh/id_ed25519.pub "$HOME/.ssh/id_ed25519.pub.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
            sudo rm -f ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
            warn "Existing SSH key backed up and removed."
        fi
        info "Generating new Ed25519 SSH key for $GIT_EMAIL..."
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        if ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f ~/.ssh/id_ed25519 -N "" -q; then
            chmod 600 ~/.ssh/id_ed25519
            chmod 644 ~/.ssh/id_ed25519.pub
            success "SSH key generated. 🔑"
        else
            warn "ssh-keygen failed — SSH key was not generated."
        fi
    fi
elif [[ "$SSH_ACTION" == "existing" && -n "$SSH_IMPORT_PRIVATE" ]]; then
    SSH_IMPORT_PRIVATE="${SSH_IMPORT_PRIVATE/#\~/$HOME}"
    if [[ ! -f "$SSH_IMPORT_PRIVATE" ]]; then
        warn "SSH private key file not found at $SSH_IMPORT_PRIVATE. Skipping."
    elif [[ -f ~/.ssh/id_ed25519 ]] && [[ "$OVERWRITE_KEYS" != "y" ]]; then
        skip "SSH key ~/.ssh/id_ed25519 already exists (overwrite disabled)."
    else
        if [[ -f ~/.ssh/id_ed25519 ]]; then
            cp ~/.ssh/id_ed25519 "$HOME/.ssh/id_ed25519.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
            cp ~/.ssh/id_ed25519.pub "$HOME/.ssh/id_ed25519.pub.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
            sudo rm -f ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
            warn "Existing SSH key backed up and removed."
        fi
        info "Importing SSH private key from $SSH_IMPORT_PRIVATE..."
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        if ! cp "$SSH_IMPORT_PRIVATE" ~/.ssh/id_ed25519 2>/dev/null; then
            warn "Failed to copy SSH private key — check file permissions. Skipping."
        else
            chmod 600 ~/.ssh/id_ed25519
            if [[ -n "$SSH_IMPORT_PUBLIC" ]]; then
                SSH_IMPORT_PUBLIC="${SSH_IMPORT_PUBLIC/#\~/$HOME}"
                if [[ -f "$SSH_IMPORT_PUBLIC" ]]; then
                    cp "$SSH_IMPORT_PUBLIC" ~/.ssh/id_ed25519.pub
                    chmod 644 ~/.ssh/id_ed25519.pub
                else
                    warn "Public key not found at $SSH_IMPORT_PUBLIC — deriving from private key..."
                    ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub 2>/dev/null \
                        && chmod 644 ~/.ssh/id_ed25519.pub \
                        || warn "Could not derive public key — create ~/.ssh/id_ed25519.pub manually."
                fi
            else
                info "No public key path given — deriving from private key..."
                if ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub 2>/dev/null; then
                    chmod 644 ~/.ssh/id_ed25519.pub
                    success "Public key derived and written to ~/.ssh/id_ed25519.pub 🔑"
                else
                    warn "Could not derive public key — create ~/.ssh/id_ed25519.pub manually."
                fi
            fi
            [[ -f ~/.ssh/id_ed25519 ]] && success "SSH key pair imported to ~/.ssh/ 🔑"
        fi
    fi
else
    skip "SSH key setup skipped."
fi

if [[ "$CREATE_GPG" == "y" && -n "$GIT_EMAIL" && -n "$GIT_NAME" ]]; then
    if [[ "$OVERWRITE_KEYS" != "y" ]] && gpg --list-secret-keys "$GIT_EMAIL" >/dev/null 2>&1; then
        skip "GPG key for $GIT_EMAIL already exists in keyring."
        GIT_SIGNING_KEY=$(gpg --list-secret-keys --keyid-format=long "$GIT_EMAIL" 2>/dev/null \
            | grep '^sec' | head -1 | awk '{print $2}' | cut -d'/' -f2 || true)
        info "Using existing key: ${GIT_SIGNING_KEY}"
    else
        info "Generating new ed25519 GPG key for ${GIT_NAME} <${GIT_EMAIL}>..."
        gpg --batch --gen-key << GPGEOF || true
%no-protection
Key-Type: EdDSA
Key-Curve: ed25519
Subkey-Type: ECDH
Subkey-Curve: cv25519
Name-Real: ${GIT_NAME}
Name-Email: ${GIT_EMAIL}
Expire-Date: 0
GPGEOF
        GIT_SIGNING_KEY=$(gpg --list-secret-keys --keyid-format=long "$GIT_EMAIL" 2>/dev/null \
            | grep '^sec' | tail -1 | awk '{print $2}' | cut -d'/' -f2 || true)
        if [[ -n "$GIT_SIGNING_KEY" ]]; then
            printf '5\ny\n' | gpg --command-fd 0 --expert --edit-key "$GIT_SIGNING_KEY" trust >/dev/null 2>&1 || true
            success "GPG key created and trusted: ${GIT_SIGNING_KEY} 🛡️"
        else
            warn "GPG key generation failed — commit signing will not be configured."
        fi
    fi
    # Patch gitconfig and dotfiles with the newly known key ID
    # (gitconfig and .bashrc were written before this section, so we update them in-place)
    if [[ -n "$GIT_SIGNING_KEY" ]]; then
        if [[ "$CREATE_GITCONFIG" == "y" ]]; then
            git config --global user.signingkey "$GIT_SIGNING_KEY"
            git config --global commit.gpgsign true
            git config --global gpg.program gpg
            success "~/.gitconfig updated with signing key ${GIT_SIGNING_KEY}."
        fi
        COMMIT_FLAGS="-S -m"
        sed -i 's/git commit -m /git commit -S -m /g' ~/.bashrc 2>/dev/null || true
        sed -i 's/git commit -m /git commit -S -m /g' ~/.zshrc  2>/dev/null || true
    fi
elif [[ -n "$GPG_IMPORT_PATH" ]]; then
    GPG_IMPORT_PATH="${GPG_IMPORT_PATH/#\~/$HOME}"

    if [[ "$OVERWRITE_KEYS" != "y" ]] && gpg --list-secret-keys "$GIT_SIGNING_KEY" >/dev/null 2>&1; then
        skip "GPG key $GIT_SIGNING_KEY is already in keyring."
    elif [[ -f "$GPG_IMPORT_PATH" ]]; then
        info "Importing GPG key from $GPG_IMPORT_PATH..."
        if gpg --import "$GPG_IMPORT_PATH"; then
            success "GPG key imported."
            if [[ -n "$GIT_SIGNING_KEY" ]]; then
                info "Setting ultimate trust for GPG key $GIT_SIGNING_KEY..."
                printf '5\ny\n' | gpg --command-fd 0 --expert --edit-key "$GIT_SIGNING_KEY" trust >/dev/null 2>&1 || true
                success "GPG key trusted. 🛡️"
            fi
        else
            warn "gpg --import failed — key file may be corrupted or in the wrong format. Skipping."
        fi
    else
        warn "GPG key file not found at $GPG_IMPORT_PATH. Skipping."
    fi
else
    skip "GPG key setup skipped."
fi


# ==============================================================================
# 🪄  12. WRITE ~/.zshrc
# ==============================================================================
section "🪄  12. Writing ~/.zshrc"

if [[ -f ~/.zshrc ]] && [[ "$OVERWRITE_DOTFILES" != "y" ]]; then
    skip "~/.zshrc already exists and overwrite is disabled."
else
    if [[ -f ~/.zshrc ]]; then
        cp ~/.zshrc "$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    fi
    sudo rm -f ~/.zshrc

    info "Writing ~/.zshrc..."

    cat << 'ZSHRC_EOF' > ~/.zshrc
# ✨ WSL / Native Ubuntu 24.04 — Full Dev Environment
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ==============================================================================
# 1. OH MY ZSH CORE SETTINGS
# ==============================================================================
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
DISABLE_UNTRACKED_FILES_DIRTY="true"
zstyle ':omz:update' mode auto
COMPLETION_WAITING_DOTS="true"

# ==============================================================================
# 2. HISTORY CONFIGURATION
# ==============================================================================
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
HIST_STAMPS="dd/mm/yyyy"

setopt appendhistory        
setopt sharehistory        
setopt hist_ignore_all_dups
setopt hist_reduce_blanks  

# ==============================================================================
# 3. PLUGINS
# ==============================================================================
plugins=(
    git extract aws azure colorize helm kubectl kubectx kube-ps1
    zsh-autosuggestions zsh-syntax-highlighting
)
source "$ZSH/oh-my-zsh.sh"

# ==============================================================================
# 4. EXPORTS & ENVIRONMENT VARIABLES
# ==============================================================================
export COLORTERM=truecolor
# --- NORD_THEME_START ---
export BAT_THEME="Nord"
# --- NORD_THEME_END ---
# --- DEFAULT_THEME_START ---
export BAT_THEME="base16"
# --- DEFAULT_THEME_END ---
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
export LANG=en_US.UTF-8
export VISUAL=vim
export EDITOR=vi
export GPG_TTY=$(tty)
export XDG_RUNTIME_DIR="/tmp/runtime-$USER"

if [ ! -d "$XDG_RUNTIME_DIR" ]; then mkdir -p "$XDG_RUNTIME_DIR"; chmod 0700 "$XDG_RUNTIME_DIR"; fi

[ -f ~/.aliases_cluster.zsh ] && source ~/.aliases_cluster.zsh
[ -f ~/.aliases_ssh.zsh ]     && source ~/.aliases_ssh.zsh
[ -f ~/.aliases_secret.zsh ] && source ~/.aliases_secret.zsh

# ==============================================================================
# 5. ALIASES
# ==============================================================================
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

alias ls="eza --color=always --icons --group-directories-first"
alias ll="eza -la --icons --group-directories-first --git"
alias cat="batcat --style=plain --paging=never"

alias gco="git checkout"
alias gcb="git checkout -b"
alias gfpo="git fetch --prune origin"
alias gbd="git branch -D"

alias git-perms-on="git config core.filemode true && echo '✅  Git is now TRACKING file permissions.'"
alias git-perms-off="git config core.filemode false && echo '🚫  Git is now IGNORING file permissions.'"

alias zshconfig="vim ~/.zshrc"
alias vimconfig="vim ~/.vimrc"
alias zsh_reload="source ~/.zshrc"

# ==============================================================================
# 6. WSL SPECIFIC CONFIGURATION
# ==============================================================================
if grep -qi microsoft /proc/version 2>/dev/null; then
    export GALLIUM_DRIVER=d3d12
    alias explorer="explorer.exe ."
    alias chrome='google-chrome --use-angle=vulkan --use-vulkan --enable-features=Vulkan --ignore-gpu-blocklist &'
    # __WINDOWS_USER_ALIAS__
fi

# ==============================================================================
# 7. FUNCTIONS
# ==============================================================================
autoload -Uz add-zsh-hook
function refresh_gpg_tty {
    export GPG_TTY=$(tty)
    gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
}
add-zsh-hook preexec refresh_gpg_tty

function gacp {
    if [ -z "$1" ]; then
        echo -e "❌  \033[1;38;2;191;97;106mError: Please provide a commit message.\033[0m"
        echo -e "💡  \033[1;38;2;129;161;193mUsage: gacp \"your commit message\"\033[0m"
        return 1
    fi
    echo -e "\n🚀  \033[1;38;2;129;161;193mStarting Git workflow...\033[0m\n"
    echo -e "📦  \033[1;38;2;235;203;139m1. Staging all files (git add -A)...\033[0m"
    git add -A
    echo -e "\n✍️   \033[1;38;2;180;142;173m2. Committing changes...\033[0m"
    if ! git commit __COMMIT_FLAGS__ "$*"; then
        echo -e "\n❌  \033[1;38;2;191;97;106mCommit failed! Aborting push.\033[0m"
        return 1
    fi
    echo -e "\n☁️   \033[1;38;2;136;192;208m3. Pushing to remote repository...\033[0m"
    if ! git push; then
        echo -e "\n❌  \033[1;38;2;191;97;106mPush failed!\033[0m"
        return 1
    fi
    echo -e "\n✅  \033[1;38;2;163;190;140mSuccess! Final Git Status:\033[0m"
    echo -e "--------------------------------------------------"
    git status
}

function connect_cluster () {
    if [ "$#" -lt 3 ]; then
        echo 'Usage: connect_cluster <subscription> <resource-group> <cluster-name>'
        return 1
    fi
    local SUBSCRIPTION="$1"
    local RG="$2"
    local CLUSTER="$3"
    export KUBECONFIG="$HOME/.kube/config_${CLUSTER}"
    echo "☸️  Connecting to ${CLUSTER}..."
    az account set --subscription "${SUBSCRIPTION}"
    az aks get-credentials --resource-group "${RG}" --name "${CLUSTER}" --overwrite-existing
    if command -v kubelogin &> /dev/null; then
        kubelogin convert-kubeconfig -l azurecli
    fi
    export PROMPT="%F{#88C0D0}☸️  ${CLUSTER:u}%f %n@%m:%~ $ "
}

# ==============================================================================
# 8. FZF — NORD THEME + PREVIEWS
# ==============================================================================
# --- NORD_THEME_START ---
export FZF_DEFAULT_OPTS="
  --color=fg:#e5e9f0,bg:#3b4252,hl:#81a1c1
  --color=fg+:#e5e9f0,bg+:#4c566a,hl+:#81a1c1
  --color=info:#ebcb8b,prompt:#bf616a,pointer:#b48ead
  --color=marker:#a3be8c,spinner:#b48ead,header:#a3be8c
  --border=rounded --margin=1 --padding=1"
# --- NORD_THEME_END ---
# --- DEFAULT_THEME_START ---
export FZF_DEFAULT_OPTS="--border=rounded --margin=1 --padding=1"
# --- DEFAULT_THEME_END ---
export FZF_CTRL_T_OPTS="
  --preview '(batcat --style=numbers --color=always {} || cat {}) 2>/dev/null | head -200'
  --preview-window=right:60%:border-rounded"
export FZF_CTRL_R_OPTS="
  --sort --exact
  --preview 'echo {}' --preview-window down:3:hidden:wrap
  --bind '?:toggle-preview'"

[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh
[ -f /usr/share/doc/fzf/examples/completion.zsh ]   && source /usr/share/doc/fzf/examples/completion.zsh

# ==============================================================================
# 9. NORD TERMINAL PALETTE
# ==============================================================================
# --- NORD_THEME_START ---
function apply_nord_palette() {
    printf "\033]10;#D8DEE9\007"; printf "\033]11;#2E3440\007"; printf "\033]12;#D8DEE9\007"
    printf "\033]4;0;#3B4252\007"; printf "\033]4;1;#BF616A\007"; printf "\033]4;2;#A3BE8C\007"
    printf "\033]4;3;#EBCB8B\007"; printf "\033]4;4;#81A1C1\007"; printf "\033]4;5;#B48EAD\007"
    printf "\033]4;6;#88C0D0\007"; printf "\033]4;7;#E5E9F0\007"; printf "\033]4;8;#4C566A\007"
    printf "\033]4;9;#BF616A\007"; printf "\033]4;10;#A3BE8C\007"; printf "\033]4;11;#EBCB8B\007"
    printf "\033]4;12;#81A1C1\007"; printf "\033]4;13;#B48EAD\007"; printf "\033]4;14;#8FBCBB\007"
    printf "\033]4;15;#ECEFF4\007"
}
apply_nord_palette > /dev/null 2>&1
# --- NORD_THEME_END ---

function maincolors() {
    local hex=("#3B4252" "#BF616A" "#A3BE8C" "#EBCB8B" "#81A1C1" "#B48EAD" "#88C0D0" "#E5E9F0" "#4C566A" "#BF616A" "#A3BE8C" "#EBCB8B" "#81A1C1" "#B48EAD" "#8FBCBB" "#ECEFF4")
    echo -e "\nStandard Colors (0-7):"
    for i in {0..7}; do printf "\e[48;5;%sm              \e[0m " "$i"; done; echo ""
    for i in {0..7}; do printf "\e[48;5;%sm      %02d      \e[0m " "$i" "$i"; done; echo ""
    for i in {0..7}; do printf "\e[48;5;%sm              \e[0m " "$i"; done; echo ""
    for i in {0..7}; do printf "  %-7s      " "${hex[$i]}"; done; echo -e "\n"

    echo "Bright Colors (8-15):"
    for i in {8..15}; do printf "\e[48;5;%sm              \e[0m " "$i"; done; echo ""
    for i in {8..15}; do printf "\e[48;5;%sm      %02d      \e[0m " "$i" "$i"; done; echo ""
    for i in {8..15}; do printf "\e[48;5;%sm              \e[0m " "$i"; done; echo ""
    for i in {8..15}; do printf "  %-7s      " "${hex[$i]}"; done; echo -e "\n"
}

function fm() {
  pcmanfm "$@" > /dev/null 2>&1 &
}

# ==============================================================================
# 10. COMPLETIONS
# ==============================================================================
if command -v kubectl &> /dev/null; then
    source <(kubectl completion zsh)
    alias k=kubectl
    compdef k=kubectl
fi
eval "$(register-python-argcomplete pipx 2>/dev/null || true)"
if command -v zoxide &> /dev/null; then eval "$(zoxide init zsh)"; fi

# ==============================================================================
# 11. POST-LOAD SCRIPTS
# ==============================================================================
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
ZSHRC_EOF

    if [[ -n "$WINDOWS_USER" ]]; then
        sed -i "s|# __WINDOWS_USER_ALIAS__|alias shared_folder=\"cd /mnt/c/Users/${WINDOWS_USER}/Documents/SharedLinux\"|g" ~/.zshrc
    fi
    sed -i "s|__COMMIT_FLAGS__|${COMMIT_FLAGS}|g" ~/.zshrc
    apply_theme_choice ~/.zshrc
    success "~/.zshrc created. 🐚"
fi

# ==============================================================================
# 🎨  13. POWERLEVEL10K CONFIG (~/.p10k.zsh)
# Embeds the saved Powerlevel10k configuration so it is ready immediately
# after first login — no need to copy from another machine or run p10k configure.
# ==============================================================================
section "🎨  13. Powerlevel10k Config"

if [[ -f ~/.p10k.zsh ]] && [[ "$OVERWRITE_DOTFILES" != "y" ]]; then
    skip "~/.p10k.zsh already exists."
else
    if [[ -f ~/.p10k.zsh ]]; then
        cp ~/.p10k.zsh "$HOME/.p10k.zsh.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        warn "Existing ~/.p10k.zsh backed up."
    fi
    # Remove before rewriting — handles root-owned files from previous runs
    sudo rm -f ~/.p10k.zsh
    info "Writing embedded ~/.p10k.zsh..."
    cat << 'P10K_EMBED_EOF' > ~/.p10k.zsh
# Generated by Powerlevel10k configuration wizard on 2026-05-05 at 10:43 EEST.
# Based on romkatv/powerlevel10k/config/p10k-lean.zsh, checksum 02674.
# Wizard options: awesome-fontconfig, large icons, unicode, lean, 24h time, 1 line,
# compact, many icons, fluent, instant_prompt=verbose.
# Type `p10k configure` to generate another config.
#
# Config for Powerlevel10k with lean prompt style. Type `p10k configure` to generate
# your own config based on it.
#
# Tip: Looking for a nice color? Here's a one-liner to print colormap.
#
#   for i in {0..255}; do print -Pn "%K{$i}  %k%F{$i}${(l:3::0:)i}%f " ${${(M)$((i%6)):#3}:+$'\n'}; done

# Temporarily change options.
'builtin' 'local' '-a' 'p10k_config_opts'
[[ ! -o 'aliases'         ]] || p10k_config_opts+=('aliases')
[[ ! -o 'sh_glob'         ]] || p10k_config_opts+=('sh_glob')
[[ ! -o 'no_brace_expand' ]] || p10k_config_opts+=('no_brace_expand')
'builtin' 'setopt' 'no_aliases' 'no_sh_glob' 'brace_expand'

() {
  emulate -L zsh -o extended_glob

  # Unset all configuration options. This allows you to apply configuration changes without
  # restarting zsh. Edit ~/.p10k.zsh and type `source ~/.p10k.zsh`.
  unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'

  # Zsh >= 5.1 is required.
  [[ $ZSH_VERSION == (5.<1->*|<6->.*) ]] || return

  # The list of segments shown on the left. Fill it with the most important segments.
  typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    os_icon                 # os identifier
    dir                     # current directory
    vcs                     # git status
    kubecontext             # current kubernetes context
    prompt_char             # prompt symbol
  )

  # The list of segments shown on the right. Fill it with less important segments.
  # Right prompt on the last prompt line (where you are typing your commands) gets
  # automatically hidden when the input line reaches it. Right prompt above the
  # last prompt line gets hidden if it would overlap with left prompt.
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    status                  # exit code of the last command
    command_execution_time  # duration of the last command
    background_jobs         # presence of background jobs
    direnv                  # direnv status (https://direnv.net/)
    asdf                    # asdf version manager (https://github.com/asdf-vm/asdf)
    virtualenv              # python virtual environment (https://docs.python.org/3/library/venv.html)
    anaconda                # conda environment (https://conda.io/)
    pyenv                   # python environment (https://github.com/pyenv/pyenv)
    goenv                   # go environment (https://github.com/syndbg/goenv)
    nodenv                  # node.js version from nodenv (https://github.com/nodenv/nodenv)
    nvm                     # node.js version from nvm (https://github.com/nvm-sh/nvm)
    nodeenv                 # node.js environment (https://github.com/ekalinin/nodeenv)
    # node_version          # node.js version
    # go_version            # go version (https://golang.org)
    # rust_version          # rustc version (https://www.rust-lang.org)
    # dotnet_version        # .NET version (https://dotnet.microsoft.com)
    # php_version           # php version (https://www.php.net/)
    # laravel_version       # laravel php framework version (https://laravel.com/)
    # java_version          # java version (https://www.java.com/)
    # package               # name@version from package.json (https://docs.npmjs.com/files/package.json)
    rbenv                   # ruby version from rbenv (https://github.com/rbenv/rbenv)
    rvm                     # ruby version from rvm (https://rvm.io)
    fvm                     # flutter version management (https://github.com/leoafarias/fvm)
    luaenv                  # lua version from luaenv (https://github.com/cehoffman/luaenv)
    jenv                    # java version from jenv (https://github.com/jenv/jenv)
    plenv                   # perl version from plenv (https://github.com/tokuhirom/plenv)
    perlbrew                # perl version from perlbrew (https://github.com/gugod/App-perlbrew)
    phpenv                  # php version from phpenv (https://github.com/phpenv/phpenv)
    scalaenv                # scala version from scalaenv (https://github.com/scalaenv/scalaenv)
    haskell_stack           # haskell version from stack (https://haskellstack.org/)
    terraform               # terraform workspace (https://www.terraform.io)
    # terraform_version     # terraform version (https://www.terraform.io)
    aws                     # aws profile (https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html)
    aws_eb_env              # aws elastic beanstalk environment (https://aws.amazon.com/elasticbeanstalk/)
    azure                   # azure account name (https://docs.microsoft.com/en-us/cli/azure)
    gcloud                  # google cloud cli account and project (https://cloud.google.com/)
    google_app_cred         # google application credentials (https://cloud.google.com/docs/authentication/production)
    toolbox                 # toolbox name (https://github.com/containers/toolbox)
    context                 # user@hostname
    nordvpn                 # nordvpn connection status, linux only (https://nordvpn.com/)
    ranger                  # ranger shell (https://github.com/ranger/ranger)
    yazi                    # yazi shell (https://github.com/sxyazi/yazi)
    nnn                     # nnn shell (https://github.com/jarun/nnn)
    lf                      # lf shell (https://github.com/gokcehan/lf)
    xplr                    # xplr shell (https://github.com/sayanarijit/xplr)
    vim_shell               # vim shell indicator (:sh)
    midnight_commander      # midnight commander shell (https://midnight-commander.org/)
    nix_shell               # nix shell (https://nixos.org/nixos/nix-pills/developing-with-nix-shell.html)
    chezmoi_shell           # chezmoi shell (https://www.chezmoi.io/)
    # vpn_ip                # virtual private network indicator
    # load                  # CPU load
    # disk_usage            # disk usage
    # ram                   # free RAM
    # swap                  # used swap
    todo                    # todo items (https://github.com/todotxt/todo.txt-cli)
    timewarrior             # timewarrior tracking status (https://timewarrior.net/)
    taskwarrior             # taskwarrior task count (https://taskwarrior.org/)
    per_directory_history   # Oh My Zsh per-directory-history local/global indicator
    # cpu_arch              # CPU architecture
    time                    # current time
    # ip                    # ip address and bandwidth usage for a specified network interface
    # public_ip             # public IP address
    # proxy                 # system-wide http/https/ftp proxy
    # battery               # internal battery
    # wifi                  # wifi speed
    # example               # example user-defined segment (see prompt_example function below)
  )

  # Defines character set used by powerlevel10k. It's best to let `p10k configure` set it for you.
  typeset -g POWERLEVEL9K_MODE=awesome-fontconfig
  # When set to `moderate`, some icons will have an extra space after them. This is meant to avoid
  # icon overlap when using non-monospace fonts. When set to `none`, spaces are not added.
  typeset -g POWERLEVEL9K_ICON_PADDING=moderate

  # Basic style options that define the overall look of your prompt. You probably don't want to
  # change them.
  typeset -g POWERLEVEL9K_BACKGROUND=                            # transparent background
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_{LEFT,RIGHT}_WHITESPACE=  # no surrounding whitespace
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SUBSEGMENT_SEPARATOR=' '  # separate segments with a space
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SEGMENT_SEPARATOR=        # no end-of-line symbol

  # When set to true, icons appear before content on both sides of the prompt. When set
  # to false, icons go after content. If empty or not set, icons go before content in the left
  # prompt and after content in the right prompt.
  #
  # You can also override it for a specific segment:
  #
  #   POWERLEVEL9K_STATUS_ICON_BEFORE_CONTENT=false
  #
  # Or for a specific segment in specific state:
  #
  #   POWERLEVEL9K_DIR_NOT_WRITABLE_ICON_BEFORE_CONTENT=false
  typeset -g POWERLEVEL9K_ICON_BEFORE_CONTENT=true

  # Add an empty line before each prompt.
  typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=false

  # Connect left prompt lines with these symbols.
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX=
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_PREFIX=
  typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX=
  # Connect right prompt lines with these symbols.
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_SUFFIX=
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_SUFFIX=
  typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_SUFFIX=

  # The left end of left prompt.
  typeset -g POWERLEVEL9K_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=
  # The right end of right prompt.
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL=

  # Ruler, a.k.a. the horizontal line before each prompt. If you set it to true, you'll
  # probably want to set POWERLEVEL9K_PROMPT_ADD_NEWLINE=false above and
  # POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR=' ' below.
  typeset -g POWERLEVEL9K_SHOW_RULER=false
  typeset -g POWERLEVEL9K_RULER_CHAR='─'        # reasonable alternative: '·'
  typeset -g POWERLEVEL9K_RULER_FOREGROUND=242

  # Filler between left and right prompt on the first prompt line. You can set it to '·' or '─'
  # to make it easier to see the alignment between left and right prompt and to separate prompt
  # from command output. It serves the same purpose as ruler (see above) without increasing
  # the number of prompt lines. You'll probably want to set POWERLEVEL9K_SHOW_RULER=false
  # if using this. You might also like POWERLEVEL9K_PROMPT_ADD_NEWLINE=false for more compact
  # prompt.
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR=' '
  if [[ $POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR != ' ' ]]; then
    # The color of the filler.
    typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_FOREGROUND=242
    # Add a space between the end of left prompt and the filler.
    typeset -g POWERLEVEL9K_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=' '
    # Add a space between the filler and the start of right prompt.
    typeset -g POWERLEVEL9K_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL=' '
    # Start filler from the edge of the screen if there are no left segments on the first line.
    typeset -g POWERLEVEL9K_EMPTY_LINE_LEFT_PROMPT_FIRST_SEGMENT_END_SYMBOL='%{%}'
    # End filler on the edge of the screen if there are no right segments on the first line.
    typeset -g POWERLEVEL9K_EMPTY_LINE_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL='%{%}'
  fi

  #################################[ os_icon: os identifier ]##################################
  # OS identifier color.
  typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=
  # Custom icon.
  # typeset -g POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION='⭐'

  ################################[ prompt_char: prompt symbol ]################################
  # Green prompt symbol if the last command succeeded.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=76
  # Red prompt symbol if the last command failed.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=196
  # Default prompt symbol.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='❯'
  # Prompt symbol in command vi mode.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VICMD_CONTENT_EXPANSION='❮'
  # Prompt symbol in visual vi mode.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIVIS_CONTENT_EXPANSION='V'
  # Prompt symbol in overwrite vi mode.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIOWR_CONTENT_EXPANSION='▶'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OVERWRITE_STATE=true
  # No line terminator if prompt_char is the last segment.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  # No line introducer if prompt_char is the first segment.
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=

  ##################################[ dir: current directory ]##################################
  # Default current directory color.
  typeset -g POWERLEVEL9K_DIR_FOREGROUND=31
  # If directory is too long, shorten some of its segments to the shortest possible unique
  # prefix. The shortened directory can be tab-completed to the original.
  typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_last
  # Replace removed segment suffixes with this symbol.
  typeset -g POWERLEVEL9K_SHORTEN_DELIMITER=
  # Color of the shortened directory segments.
  typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=103
  # Color of the anchor directory segments. Anchor segments are never shortened. The first
  # segment is always an anchor.
  typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=39
  # Display anchor directory segments in bold.
  typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=true
  # Don't shorten directories that contain any of these files. They are anchors.
  local anchor_files=(
    .bzr
    .citc
    .git
    .hg
    .node-version
    .python-version
    .go-version
    .ruby-version
    .lua-version
    .java-version
    .perl-version
    .php-version
    .tool-versions
    .mise.toml
    .shorten_folder_marker
    .svn
    .terraform
    CVS
    Cargo.toml
    composer.json
    go.mod
    package.json
    stack.yaml
  )
  typeset -g POWERLEVEL9K_SHORTEN_FOLDER_MARKER="(${(j:|:)anchor_files})"
  # If set to "first" ("last"), remove everything before the first (last) subdirectory that contains
  # files matching $POWERLEVEL9K_SHORTEN_FOLDER_MARKER. For example, when the current directory is
  # /foo/bar/git_repo/nested_git_repo/baz, prompt will display git_repo/nested_git_repo/baz (first)
  # or nested_git_repo/baz (last). This assumes that git_repo and nested_git_repo contain markers
  # and other directories don't.
  #
  # Optionally, "first" and "last" can be followed by ":<offset>" where <offset> is an integer.
  # This moves the truncation point to the right (positive offset) or to the left (negative offset)
  # relative to the marker. Plain "first" and "last" are equivalent to "first:0" and "last:0"
  # respectively.
  typeset -g POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER=false
  # Don't shorten this many last directory segments. They are anchors.
  typeset -g POWERLEVEL9K_SHORTEN_DIR_LENGTH=3
  # Shorten directory if it's longer than this even if there is space for it. The value can
  # be either absolute (e.g., '80') or a percentage of terminal width (e.g, '50%'). If empty,
  # directory will be shortened only when prompt doesn't fit or when other parameters demand it
  # (see POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS and POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS_PCT below).
  # If set to `0`, directory will always be shortened to its minimum length.
  typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=80
  # When `dir` segment is on the last prompt line, try to shorten it enough to leave at least this
  # many columns for typing commands.
  typeset -g POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS=40
  # When `dir` segment is on the last prompt line, try to shorten it enough to leave at least
  # COLUMNS * POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS_PCT * 0.01 columns for typing commands.
  typeset -g POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS_PCT=50
  # If set to true, embed a hyperlink into the directory. Useful for quickly
  # opening a directory in the file manager simply by clicking the link.
  # Can also be handy when the directory is shortened, as it allows you to see
  # the full directory that was used in previous commands.
  typeset -g POWERLEVEL9K_DIR_HYPERLINK=false

  # Enable special styling for non-writable and non-existent directories. See POWERLEVEL9K_LOCK_ICON
  # and POWERLEVEL9K_DIR_CLASSES below.
  typeset -g POWERLEVEL9K_DIR_SHOW_WRITABLE=v3

  # The default icon shown next to non-writable and non-existent directories when
  # POWERLEVEL9K_DIR_SHOW_WRITABLE is set to v3.
  # typeset -g POWERLEVEL9K_LOCK_ICON='⭐'

  # POWERLEVEL9K_DIR_CLASSES allows you to specify custom icons and colors for different
  # directories. It must be an array with 3 * N elements. Each triplet consists of:
  #
  #   1. A pattern against which the current directory ($PWD) is matched. Matching is done with
  #      extended_glob option enabled.
  #   2. Directory class for the purpose of styling.
  #   3. An empty string.
  #
  # Triplets are tried in order. The first triplet whose pattern matches $PWD wins.
  #
  # If POWERLEVEL9K_DIR_SHOW_WRITABLE is set to v3, non-writable and non-existent directories
  # acquire class suffix _NOT_WRITABLE and NON_EXISTENT respectively.
  #
  # For example, given these settings:
  #
  #   typeset -g POWERLEVEL9K_DIR_CLASSES=(
  #     '~/work(|/*)'  WORK     ''
  #     '~(|/*)'       HOME     ''
  #     '*'            DEFAULT  '')
  #
  # Whenever the current directory is ~/work or a subdirectory of ~/work, it gets styled with one
  # of the following classes depending on its writability and existence: WORK, WORK_NOT_WRITABLE or
  # WORK_NON_EXISTENT.
  #
  # Simply assigning classes to directories doesn't have any visible effects. It merely gives you an
  # option to define custom colors and icons for different directory classes.
  #
  #   # Styling for WORK.
  #   typeset -g POWERLEVEL9K_DIR_WORK_VISUAL_IDENTIFIER_EXPANSION='⭐'
  #   typeset -g POWERLEVEL9K_DIR_WORK_FOREGROUND=31
  #   typeset -g POWERLEVEL9K_DIR_WORK_SHORTENED_FOREGROUND=103
  #   typeset -g POWERLEVEL9K_DIR_WORK_ANCHOR_FOREGROUND=39
  #
  #   # Styling for WORK_NOT_WRITABLE.
  #   typeset -g POWERLEVEL9K_DIR_WORK_NOT_WRITABLE_VISUAL_IDENTIFIER_EXPANSION='⭐'
  #   typeset -g POWERLEVEL9K_DIR_WORK_NOT_WRITABLE_FOREGROUND=31
  #   typeset -g POWERLEVEL9K_DIR_WORK_NOT_WRITABLE_SHORTENED_FOREGROUND=103
  #   typeset -g POWERLEVEL9K_DIR_WORK_NOT_WRITABLE_ANCHOR_FOREGROUND=39
  #
  #   # Styling for WORK_NON_EXISTENT.
  #   typeset -g POWERLEVEL9K_DIR_WORK_NON_EXISTENT_VISUAL_IDENTIFIER_EXPANSION='⭐'
  #   typeset -g POWERLEVEL9K_DIR_WORK_NON_EXISTENT_FOREGROUND=31
  #   typeset -g POWERLEVEL9K_DIR_WORK_NON_EXISTENT_SHORTENED_FOREGROUND=103
  #   typeset -g POWERLEVEL9K_DIR_WORK_NON_EXISTENT_ANCHOR_FOREGROUND=39
  #
  # If a styling parameter isn't explicitly defined for some class, it falls back to the classless
  # parameter. For example, if POWERLEVEL9K_DIR_WORK_NOT_WRITABLE_FOREGROUND is not set, it falls
  # back to POWERLEVEL9K_DIR_FOREGROUND.
  #
  # typeset -g POWERLEVEL9K_DIR_CLASSES=()

  # Custom prefix.
  # typeset -g POWERLEVEL9K_DIR_PREFIX='%fin '

  #####################################[ vcs: git status ]######################################
  # Branch icon. Set this parameter to '\UE0A0 ' for the popular Powerline branch icon.
  typeset -g POWERLEVEL9K_VCS_BRANCH_ICON='\uF126 '

  # Untracked files icon. It's really a question mark, your font isn't broken.
  # Change the value of this parameter to show a different icon.
  typeset -g POWERLEVEL9K_VCS_UNTRACKED_ICON='?'

  # Formatter for Git status.
  #
  # Example output: master wip ⇣42⇡42 *42 merge ~42 +42 !42 ?42.
  #
  # You can edit the function to customize how Git status looks.
  #
  # VCS_STATUS_* parameters are set by gitstatus plugin. See reference:
  # https://github.com/romkatv/gitstatus/blob/master/gitstatus.plugin.zsh.
  function my_git_formatter() {
    emulate -L zsh

    if [[ -n $P9K_CONTENT ]]; then
      # If P9K_CONTENT is not empty, use it. It's either "loading" or from vcs_info (not from
      # gitstatus plugin). VCS_STATUS_* parameters are not available in this case.
      typeset -g my_git_format=$P9K_CONTENT
      return
    fi

    if (( $1 )); then
      # Styling for up-to-date Git status.
      local       meta='%f'     # default foreground
      local      clean='%76F'   # green foreground
      local   modified='%178F'  # yellow foreground
      local  untracked='%39F'   # blue foreground
      local conflicted='%196F'  # red foreground
    else
      # Styling for incomplete and stale Git status.
      local       meta='%244F'  # grey foreground
      local      clean='%244F'  # grey foreground
      local   modified='%244F'  # grey foreground
      local  untracked='%244F'  # grey foreground
      local conflicted='%244F'  # grey foreground
    fi

    local res

    if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
      local branch=${(V)VCS_STATUS_LOCAL_BRANCH}
      # If local branch name is at most 32 characters long, show it in full.
      # Otherwise show the first 12 … the last 12.
      # Tip: To always show local branch name in full without truncation, delete the next line.
      (( $#branch > 32 )) && branch[13,-13]="…"  # <-- this line
      res+="${clean}${(g::)POWERLEVEL9K_VCS_BRANCH_ICON}${branch//\%/%%}"
    fi

    if [[ -n $VCS_STATUS_TAG
          # Show tag only if not on a branch.
          # Tip: To always show tag, delete the next line.
          && -z $VCS_STATUS_LOCAL_BRANCH  # <-- this line
        ]]; then
      local tag=${(V)VCS_STATUS_TAG}
      # If tag name is at most 32 characters long, show it in full.
      # Otherwise show the first 12 … the last 12.
      # Tip: To always show tag name in full without truncation, delete the next line.
      (( $#tag > 32 )) && tag[13,-13]="…"  # <-- this line
      res+="${meta}#${clean}${tag//\%/%%}"
    fi

    # Display the current Git commit if there is no branch and no tag.
    # Tip: To always display the current Git commit, delete the next line.
    [[ -z $VCS_STATUS_LOCAL_BRANCH && -z $VCS_STATUS_TAG ]] &&  # <-- this line
      res+="${meta}@${clean}${VCS_STATUS_COMMIT[1,8]}"

    # Show tracking branch name if it differs from local branch.
    if [[ -n ${VCS_STATUS_REMOTE_BRANCH:#$VCS_STATUS_LOCAL_BRANCH} ]]; then
      res+="${meta}:${clean}${(V)VCS_STATUS_REMOTE_BRANCH//\%/%%}"
    fi

    # Display "wip" if the latest commit's summary contains "wip" or "WIP".
    if [[ $VCS_STATUS_COMMIT_SUMMARY == (|*[^[:alnum:]])(wip|WIP)(|[^[:alnum:]]*) ]]; then
      res+=" ${modified}wip"
    fi

    if (( VCS_STATUS_COMMITS_AHEAD || VCS_STATUS_COMMITS_BEHIND )); then
      # ⇣42 if behind the remote.
      (( VCS_STATUS_COMMITS_BEHIND )) && res+=" ${clean}⇣${VCS_STATUS_COMMITS_BEHIND}"
      # ⇡42 if ahead of the remote; no leading space if also behind the remote: ⇣42⇡42.
      (( VCS_STATUS_COMMITS_AHEAD && !VCS_STATUS_COMMITS_BEHIND )) && res+=" "
      (( VCS_STATUS_COMMITS_AHEAD  )) && res+="${clean}⇡${VCS_STATUS_COMMITS_AHEAD}"
    elif [[ -n $VCS_STATUS_REMOTE_BRANCH ]]; then
      # Tip: Uncomment the next line to display '=' if up to date with the remote.
      # res+=" ${clean}="
    fi

    # ⇠42 if behind the push remote.
    (( VCS_STATUS_PUSH_COMMITS_BEHIND )) && res+=" ${clean}⇠${VCS_STATUS_PUSH_COMMITS_BEHIND}"
    (( VCS_STATUS_PUSH_COMMITS_AHEAD && !VCS_STATUS_PUSH_COMMITS_BEHIND )) && res+=" "
    # ⇢42 if ahead of the push remote; no leading space if also behind: ⇠42⇢42.
    (( VCS_STATUS_PUSH_COMMITS_AHEAD  )) && res+="${clean}⇢${VCS_STATUS_PUSH_COMMITS_AHEAD}"
    # *42 if have stashes.
    (( VCS_STATUS_STASHES        )) && res+=" ${clean}*${VCS_STATUS_STASHES}"
    # 'merge' if the repo is in an unusual state.
    [[ -n $VCS_STATUS_ACTION     ]] && res+=" ${conflicted}${VCS_STATUS_ACTION}"
    # ~42 if have merge conflicts.
    (( VCS_STATUS_NUM_CONFLICTED )) && res+=" ${conflicted}~${VCS_STATUS_NUM_CONFLICTED}"
    # +42 if have staged changes.
    (( VCS_STATUS_NUM_STAGED     )) && res+=" ${modified}+${VCS_STATUS_NUM_STAGED}"
    # !42 if have unstaged changes.
    (( VCS_STATUS_NUM_UNSTAGED   )) && res+=" ${modified}!${VCS_STATUS_NUM_UNSTAGED}"
    # ?42 if have untracked files. It's really a question mark, your font isn't broken.
    # See POWERLEVEL9K_VCS_UNTRACKED_ICON above if you want to use a different icon.
    # Remove the next line if you don't want to see untracked files at all.
    (( VCS_STATUS_NUM_UNTRACKED  )) && res+=" ${untracked}${(g::)POWERLEVEL9K_VCS_UNTRACKED_ICON}${VCS_STATUS_NUM_UNTRACKED}"
    # "─" if the number of unstaged files is unknown. This can happen due to
    # POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY (see below) being set to a non-negative number lower
    # than the number of files in the Git index, or due to bash.showDirtyState being set to false
    # in the repository config. The number of staged and untracked files may also be unknown
    # in this case.
    (( VCS_STATUS_HAS_UNSTAGED == -1 )) && res+=" ${modified}─"

    typeset -g my_git_format=$res
  }
  functions -M my_git_formatter 2>/dev/null

  # Don't count the number of unstaged, untracked and conflicted files in Git repositories with
  # more than this many files in the index. Negative value means infinity.
  #
  # If you are working in Git repositories with tens of millions of files and seeing performance
  # sagging, try setting POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY to a number lower than the output
  # of `git ls-files | wc -l`. Alternatively, add `bash.showDirtyState = false` to the repository's
  # config: `git config bash.showDirtyState false`.
  typeset -g POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY=-1

  # Don't show Git status in prompt for repositories whose workdir matches this pattern.
  # For example, if set to '~', the Git repository at $HOME/.git will be ignored.
  # Multiple patterns can be combined with '|': '~(|/foo)|/bar/baz/*'.
  typeset -g POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN='~'

  # Disable the default Git status formatting.
  typeset -g POWERLEVEL9K_VCS_DISABLE_GITSTATUS_FORMATTING=true
  # Install our own Git status formatter.
  typeset -g POWERLEVEL9K_VCS_CONTENT_EXPANSION='${$((my_git_formatter(1)))+${my_git_format}}'
  typeset -g POWERLEVEL9K_VCS_LOADING_CONTENT_EXPANSION='${$((my_git_formatter(0)))+${my_git_format}}'
  # Enable counters for staged, unstaged, etc.
  typeset -g POWERLEVEL9K_VCS_{STAGED,UNSTAGED,UNTRACKED,CONFLICTED,COMMITS_AHEAD,COMMITS_BEHIND}_MAX_NUM=-1

  # Icon color.
  typeset -g POWERLEVEL9K_VCS_VISUAL_IDENTIFIER_COLOR=76
  typeset -g POWERLEVEL9K_VCS_LOADING_VISUAL_IDENTIFIER_COLOR=244
  # Custom icon.
  # typeset -g POWERLEVEL9K_VCS_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # Custom prefix.
  typeset -g POWERLEVEL9K_VCS_PREFIX='%fon '

  # Show status of repositories of these types. You can add svn and/or hg if you are
  # using them. If you do, your prompt may become slow even when your current directory
  # isn't in an svn or hg repository.
  typeset -g POWERLEVEL9K_VCS_BACKENDS=(git)

  # These settings are used for repositories other than Git or when gitstatusd fails and
  # Powerlevel10k has to fall back to using vcs_info.
  typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND=76
  typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=76
  typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=178

  ##########################[ status: exit code of the last command ]###########################
  # Enable OK_PIPE, ERROR_PIPE and ERROR_SIGNAL status states to allow us to enable, disable and
  # style them independently from the regular OK and ERROR state.
  typeset -g POWERLEVEL9K_STATUS_EXTENDED_STATES=true

  # Status on success. No content, just an icon. No need to show it if prompt_char is enabled as
  # it will signify success by turning green.
  typeset -g POWERLEVEL9K_STATUS_OK=false
  typeset -g POWERLEVEL9K_STATUS_OK_FOREGROUND=70
  typeset -g POWERLEVEL9K_STATUS_OK_VISUAL_IDENTIFIER_EXPANSION='✔'

  # Status when some part of a pipe command fails but the overall exit status is zero. It may look
  # like this: 1|0.
  typeset -g POWERLEVEL9K_STATUS_OK_PIPE=true
  typeset -g POWERLEVEL9K_STATUS_OK_PIPE_FOREGROUND=70
  typeset -g POWERLEVEL9K_STATUS_OK_PIPE_VISUAL_IDENTIFIER_EXPANSION='✔'

  # Status when it's just an error code (e.g., '1'). No need to show it if prompt_char is enabled as
  # it will signify error by turning red.
  typeset -g POWERLEVEL9K_STATUS_ERROR=false
  typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=160
  typeset -g POWERLEVEL9K_STATUS_ERROR_VISUAL_IDENTIFIER_EXPANSION='✘'

  # Status when the last command was terminated by a signal.
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL=true
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_FOREGROUND=160
  # Use terse signal names: "INT" instead of "SIGINT(2)".
  typeset -g POWERLEVEL9K_STATUS_VERBOSE_SIGNAME=false
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_VISUAL_IDENTIFIER_EXPANSION='✘'

  # Status when some part of a pipe command fails and the overall exit status is also non-zero.
  # It may look like this: 1|0.
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE=true
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE_FOREGROUND=160
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE_VISUAL_IDENTIFIER_EXPANSION='✘'

  ###################[ command_execution_time: duration of the last command ]###################
  # Show duration of the last command if takes at least this many seconds.
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
  # Show this many fractional digits. Zero means round to seconds.
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=0
  # Execution time color.
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=101
  # Duration format: 1d 2h 3m 4s.
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FORMAT='d h m s'
  # Custom icon.
  # typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # Custom prefix.
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PREFIX='%ftook '

  #######################[ background_jobs: presence of background jobs ]#######################
  # Don't show the number of background jobs.
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_VERBOSE=false
  # Background jobs color.
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND=70
  # Custom icon.
  # typeset -g POWERLEVEL9K_BACKGROUND_JOBS_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #######################[ direnv: direnv status (https://direnv.net/) ]########################
  # Direnv color.
  typeset -g POWERLEVEL9K_DIRENV_FOREGROUND=178
  # Custom icon.
  # typeset -g POWERLEVEL9K_DIRENV_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ###############[ asdf: asdf version manager (https://github.com/asdf-vm/asdf) ]###############
  # Default asdf color. Only used to display tools for which there is no color override (see below).
  # Tip:  Override this parameter for ${TOOL} with POWERLEVEL9K_ASDF_${TOOL}_FOREGROUND.
  typeset -g POWERLEVEL9K_ASDF_FOREGROUND=66

  # There are four parameters that can be used to hide asdf tools. Each parameter describes
  # conditions under which a tool gets hidden. Parameters can hide tools but not unhide them. If at
  # least one parameter decides to hide a tool, that tool gets hidden. If no parameter decides to
  # hide a tool, it gets shown.
  #
  # Special note on the difference between POWERLEVEL9K_ASDF_SOURCES and
  # POWERLEVEL9K_ASDF_PROMPT_ALWAYS_SHOW. Consider the effect of the following commands:
  #
  #   asdf local  python 3.8.1
  #   asdf global python 3.8.1
  #
  # After running both commands the current python version is 3.8.1 and its source is "local" as
  # it takes precedence over "global". If POWERLEVEL9K_ASDF_PROMPT_ALWAYS_SHOW is set to false,
  # it'll hide python version in this case because 3.8.1 is the same as the global version.
  # POWERLEVEL9K_ASDF_SOURCES will hide python version only if the value of this parameter doesn't
  # contain "local".

  # Hide tool versions that don't come from one of these sources.
  #
  # Available sources:
  #
  # - shell   `asdf current` says "set by ASDF_${TOOL}_VERSION environment variable"
  # - local   `asdf current` says "set by /some/not/home/directory/file"
  # - global  `asdf current` says "set by /home/username/file"
  #
  # Note: If this parameter is set to (shell local global), it won't hide tools.
  # Tip:  Override this parameter for ${TOOL} with POWERLEVEL9K_ASDF_${TOOL}_SOURCES.
  typeset -g POWERLEVEL9K_ASDF_SOURCES=(shell local global)

  # If set to false, hide tool versions that are the same as global.
  #
  # Note: The name of this parameter doesn't reflect its meaning at all.
  # Note: If this parameter is set to true, it won't hide tools.
  # Tip:  Override this parameter for ${TOOL} with POWERLEVEL9K_ASDF_${TOOL}_PROMPT_ALWAYS_SHOW.
  typeset -g POWERLEVEL9K_ASDF_PROMPT_ALWAYS_SHOW=false

  # If set to false, hide tool versions that are equal to "system".
  #
  # Note: If this parameter is set to true, it won't hide tools.
  # Tip: Override this parameter for ${TOOL} with POWERLEVEL9K_ASDF_${TOOL}_SHOW_SYSTEM.
  typeset -g POWERLEVEL9K_ASDF_SHOW_SYSTEM=true

  # If set to non-empty value, hide tools unless there is a file matching the specified file pattern
  # in the current directory, or its parent directory, or its grandparent directory, and so on.
  #
  # Note: If this parameter is set to empty value, it won't hide tools.
  # Note: SHOW_ON_UPGLOB isn't specific to asdf. It works with all prompt segments.
  # Tip: Override this parameter for ${TOOL} with POWERLEVEL9K_ASDF_${TOOL}_SHOW_ON_UPGLOB.
  #
  # Example: Hide nodejs version when there is no package.json and no *.js files in the current
  # directory, in `..`, in `../..` and so on.
  #
  #   typeset -g POWERLEVEL9K_ASDF_NODEJS_SHOW_ON_UPGLOB='*.js|package.json'
  typeset -g POWERLEVEL9K_ASDF_SHOW_ON_UPGLOB=

  # Ruby version from asdf.
  typeset -g POWERLEVEL9K_ASDF_RUBY_FOREGROUND=168
  # typeset -g POWERLEVEL9K_ASDF_RUBY_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_RUBY_SHOW_ON_UPGLOB='*.foo|*.bar'

  # Python version from asdf.
  typeset -g POWERLEVEL9K_ASDF_PYTHON_FOREGROUND=37
  # typeset -g POWERLEVEL9K_ASDF_PYTHON_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_PYTHON_SHOW_ON_UPGLOB='*.foo|*.bar'

  # Go version from asdf.
  typeset -g POWERLEVEL9K_ASDF_GOLANG_FOREGROUND=37
  # typeset -g POWERLEVEL9K_ASDF_GOLANG_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_GOLANG_SHOW_ON_UPGLOB='*.foo|*.bar'

  # Node.js version from asdf.
  typeset -g POWERLEVEL9K_ASDF_NODEJS_FOREGROUND=70
  # typeset -g POWERLEVEL9K_ASDF_NODEJS_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_NODEJS_SHOW_ON_UPGLOB='*.foo|*.bar'

  # Rust version from asdf.
  typeset -g POWERLEVEL9K_ASDF_RUST_FOREGROUND=37
  # typeset -g POWERLEVEL9K_ASDF_RUST_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_RUST_SHOW_ON_UPGLOB='*.foo|*.bar'

  # .NET Core version from asdf.
  typeset -g POWERLEVEL9K_ASDF_DOTNET_CORE_FOREGROUND=134
  # typeset -g POWERLEVEL9K_ASDF_DOTNET_CORE_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_DOTNET_SHOW_ON_UPGLOB='*.foo|*.bar'

  # Flutter version from asdf.
  typeset -g POWERLEVEL9K_ASDF_FLUTTER_FOREGROUND=38
  # typeset -g POWERLEVEL9K_ASDF_FLUTTER_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_FLUTTER_SHOW_ON_UPGLOB='*.foo|*.bar'

  # Lua version from asdf.
  typeset -g POWERLEVEL9K_ASDF_LUA_FOREGROUND=32
  # typeset -g POWERLEVEL9K_ASDF_LUA_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_LUA_SHOW_ON_UPGLOB='*.foo|*.bar'

  # Java version from asdf.
  typeset -g POWERLEVEL9K_ASDF_JAVA_FOREGROUND=32
  # typeset -g POWERLEVEL9K_ASDF_JAVA_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_JAVA_SHOW_ON_UPGLOB='*.foo|*.bar'

  # Perl version from asdf.
  typeset -g POWERLEVEL9K_ASDF_PERL_FOREGROUND=67
  # typeset -g POWERLEVEL9K_ASDF_PERL_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_PERL_SHOW_ON_UPGLOB='*.foo|*.bar'

  # Erlang version from asdf.
  typeset -g POWERLEVEL9K_ASDF_ERLANG_FOREGROUND=125
  # typeset -g POWERLEVEL9K_ASDF_ERLANG_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_ERLANG_SHOW_ON_UPGLOB='*.foo|*.bar'

  # Elixir version from asdf.
  typeset -g POWERLEVEL9K_ASDF_ELIXIR_FOREGROUND=129
  # typeset -g POWERLEVEL9K_ASDF_ELIXIR_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_ELIXIR_SHOW_ON_UPGLOB='*.foo|*.bar'

  # Postgres version from asdf.
  typeset -g POWERLEVEL9K_ASDF_POSTGRES_FOREGROUND=31
  # typeset -g POWERLEVEL9K_ASDF_POSTGRES_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_POSTGRES_SHOW_ON_UPGLOB='*.foo|*.bar'

  # PHP version from asdf.
  typeset -g POWERLEVEL9K_ASDF_PHP_FOREGROUND=99
  # typeset -g POWERLEVEL9K_ASDF_PHP_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_PHP_SHOW_ON_UPGLOB='*.foo|*.bar'

  # Haskell version from asdf.
  typeset -g POWERLEVEL9K_ASDF_HASKELL_FOREGROUND=172
  # typeset -g POWERLEVEL9K_ASDF_HASKELL_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_HASKELL_SHOW_ON_UPGLOB='*.foo|*.bar'

  # Julia version from asdf.
  typeset -g POWERLEVEL9K_ASDF_JULIA_FOREGROUND=70
  # typeset -g POWERLEVEL9K_ASDF_JULIA_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_ASDF_JULIA_SHOW_ON_UPGLOB='*.foo|*.bar'

  ##########[ nordvpn: nordvpn connection status, linux only (https://nordvpn.com/) ]###########
  # NordVPN connection indicator color.
  typeset -g POWERLEVEL9K_NORDVPN_FOREGROUND=39
  # Hide NordVPN connection indicator when not connected.
  typeset -g POWERLEVEL9K_NORDVPN_{DISCONNECTED,CONNECTING,DISCONNECTING}_CONTENT_EXPANSION=
  typeset -g POWERLEVEL9K_NORDVPN_{DISCONNECTED,CONNECTING,DISCONNECTING}_VISUAL_IDENTIFIER_EXPANSION=
  # Custom icon.
  # typeset -g POWERLEVEL9K_NORDVPN_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #################[ ranger: ranger shell (https://github.com/ranger/ranger) ]##################
  # Ranger shell color.
  typeset -g POWERLEVEL9K_RANGER_FOREGROUND=178
  # Custom icon.
  # typeset -g POWERLEVEL9K_RANGER_VISUAL_IDENTIFIER_EXPANSION='⭐'
  
  ####################[ yazi: yazi shell (https://github.com/sxyazi/yazi) ]#####################
  # Yazi shell color.
  typeset -g POWERLEVEL9K_YAZI_FOREGROUND=178
  # Custom icon.
  # typeset -g POWERLEVEL9K_YAZI_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ######################[ nnn: nnn shell (https://github.com/jarun/nnn) ]#######################
  # Nnn shell color.
  typeset -g POWERLEVEL9K_NNN_FOREGROUND=72
  # Custom icon.
  # typeset -g POWERLEVEL9K_NNN_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ######################[ lf: lf shell (https://github.com/gokcehan/lf) ]#######################
  # lf shell color.
  typeset -g POWERLEVEL9K_LF_FOREGROUND=72
  # Custom icon.
  # typeset -g POWERLEVEL9K_LF_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ##################[ xplr: xplr shell (https://github.com/sayanarijit/xplr) ]##################
  # xplr shell color.
  typeset -g POWERLEVEL9K_XPLR_FOREGROUND=72
  # Custom icon.
  # typeset -g POWERLEVEL9K_XPLR_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ###########################[ vim_shell: vim shell indicator (:sh) ]###########################
  # Vim shell indicator color.
  typeset -g POWERLEVEL9K_VIM_SHELL_FOREGROUND=34
  # Custom icon.
  # typeset -g POWERLEVEL9K_VIM_SHELL_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ######[ midnight_commander: midnight commander shell (https://midnight-commander.org/) ]######
  # Midnight Commander shell color.
  typeset -g POWERLEVEL9K_MIDNIGHT_COMMANDER_FOREGROUND=178
  # Custom icon.
  # typeset -g POWERLEVEL9K_MIDNIGHT_COMMANDER_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #[ nix_shell: nix shell (https://nixos.org/nixos/nix-pills/developing-with-nix-shell.html) ]##
  # Nix shell color.
  typeset -g POWERLEVEL9K_NIX_SHELL_FOREGROUND=74

  # Display the icon of nix_shell if PATH contains a subdirectory of /nix/store.
  # typeset -g POWERLEVEL9K_NIX_SHELL_INFER_FROM_PATH=false

  # Tip: If you want to see just the icon without "pure" and "impure", uncomment the next line.
  # typeset -g POWERLEVEL9K_NIX_SHELL_CONTENT_EXPANSION=

  # Custom icon.
  # typeset -g POWERLEVEL9K_NIX_SHELL_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ##################[ chezmoi_shell: chezmoi shell (https://www.chezmoi.io/) ]##################
  # chezmoi shell color.
  typeset -g POWERLEVEL9K_CHEZMOI_SHELL_FOREGROUND=33
  # Custom icon.
  # typeset -g POWERLEVEL9K_CHEZMOI_SHELL_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ##################################[ disk_usage: disk usage ]##################################
  # Colors for different levels of disk usage.
  typeset -g POWERLEVEL9K_DISK_USAGE_NORMAL_FOREGROUND=35
  typeset -g POWERLEVEL9K_DISK_USAGE_WARNING_FOREGROUND=220
  typeset -g POWERLEVEL9K_DISK_USAGE_CRITICAL_FOREGROUND=160
  # Thresholds for different levels of disk usage (percentage points).
  typeset -g POWERLEVEL9K_DISK_USAGE_WARNING_LEVEL=90
  typeset -g POWERLEVEL9K_DISK_USAGE_CRITICAL_LEVEL=95
  # If set to true, hide disk usage when below $POWERLEVEL9K_DISK_USAGE_WARNING_LEVEL percent.
  typeset -g POWERLEVEL9K_DISK_USAGE_ONLY_WARNING=false
  # Custom icon.
  # typeset -g POWERLEVEL9K_DISK_USAGE_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ######################################[ ram: free RAM ]#######################################
  # RAM color.
  typeset -g POWERLEVEL9K_RAM_FOREGROUND=66
  # Custom icon.
  # typeset -g POWERLEVEL9K_RAM_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #####################################[ swap: used swap ]######################################
  # Swap color.
  typeset -g POWERLEVEL9K_SWAP_FOREGROUND=96
  # Custom icon.
  # typeset -g POWERLEVEL9K_SWAP_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ######################################[ load: CPU load ]######################################
  # Show average CPU load over this many last minutes. Valid values are 1, 5 and 15.
  typeset -g POWERLEVEL9K_LOAD_WHICH=5
  # Load color when load is under 50%.
  typeset -g POWERLEVEL9K_LOAD_NORMAL_FOREGROUND=66
  # Load color when load is between 50% and 70%.
  typeset -g POWERLEVEL9K_LOAD_WARNING_FOREGROUND=178
  # Load color when load is over 70%.
  typeset -g POWERLEVEL9K_LOAD_CRITICAL_FOREGROUND=166
  # Custom icon.
  # typeset -g POWERLEVEL9K_LOAD_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ################[ todo: todo items (https://github.com/todotxt/todo.txt-cli) ]################
  # Todo color.
  typeset -g POWERLEVEL9K_TODO_FOREGROUND=110
  # Hide todo when the total number of tasks is zero.
  typeset -g POWERLEVEL9K_TODO_HIDE_ZERO_TOTAL=true
  # Hide todo when the number of tasks after filtering is zero.
  typeset -g POWERLEVEL9K_TODO_HIDE_ZERO_FILTERED=false

  # Todo format. The following parameters are available within the expansion.
  #
  # - P9K_TODO_TOTAL_TASK_COUNT     The total number of tasks.
  # - P9K_TODO_FILTERED_TASK_COUNT  The number of tasks after filtering.
  #
  # These variables correspond to the last line of the output of `todo.sh -p ls`:
  #
  #   TODO: 24 of 42 tasks shown
  #
  # Here 24 is P9K_TODO_FILTERED_TASK_COUNT and 42 is P9K_TODO_TOTAL_TASK_COUNT.
  #
  # typeset -g POWERLEVEL9K_TODO_CONTENT_EXPANSION='$P9K_TODO_FILTERED_TASK_COUNT'

  # Custom icon.
  # typeset -g POWERLEVEL9K_TODO_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ###########[ timewarrior: timewarrior tracking status (https://timewarrior.net/) ]############
  # Timewarrior color.
  typeset -g POWERLEVEL9K_TIMEWARRIOR_FOREGROUND=110
  # If the tracked task is longer than 24 characters, truncate and append "…".
  # Tip: To always display tasks without truncation, delete the following parameter.
  # Tip: To hide task names and display just the icon when time tracking is enabled, set the
  # value of the following parameter to "".
  typeset -g POWERLEVEL9K_TIMEWARRIOR_CONTENT_EXPANSION='${P9K_CONTENT:0:24}${${P9K_CONTENT:24}:+…}'

  # Custom icon.
  # typeset -g POWERLEVEL9K_TIMEWARRIOR_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ##############[ taskwarrior: taskwarrior task count (https://taskwarrior.org/) ]##############
  # Taskwarrior color.
  typeset -g POWERLEVEL9K_TASKWARRIOR_FOREGROUND=74

  # Taskwarrior segment format. The following parameters are available within the expansion.
  #
  # - P9K_TASKWARRIOR_PENDING_COUNT   The number of pending tasks: `task +PENDING count`.
  # - P9K_TASKWARRIOR_OVERDUE_COUNT   The number of overdue tasks: `task +OVERDUE count`.
  #
  # Zero values are represented as empty parameters.
  #
  # The default format:
  #
  #   '${P9K_TASKWARRIOR_OVERDUE_COUNT:+"!$P9K_TASKWARRIOR_OVERDUE_COUNT/"}$P9K_TASKWARRIOR_PENDING_COUNT'
  #
  # typeset -g POWERLEVEL9K_TASKWARRIOR_CONTENT_EXPANSION='$P9K_TASKWARRIOR_PENDING_COUNT'

  # Custom icon.
  # typeset -g POWERLEVEL9K_TASKWARRIOR_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ######[ per_directory_history: Oh My Zsh per-directory-history local/global indicator ]#######
  # Color when using local/global history.
  typeset -g POWERLEVEL9K_PER_DIRECTORY_HISTORY_LOCAL_FOREGROUND=135
  typeset -g POWERLEVEL9K_PER_DIRECTORY_HISTORY_GLOBAL_FOREGROUND=130

  # Tip: Uncomment the next two lines to hide "local"/"global" text and leave just the icon.
  # typeset -g POWERLEVEL9K_PER_DIRECTORY_HISTORY_LOCAL_CONTENT_EXPANSION=''
  # typeset -g POWERLEVEL9K_PER_DIRECTORY_HISTORY_GLOBAL_CONTENT_EXPANSION=''

  # Custom icon.
  # typeset -g POWERLEVEL9K_PER_DIRECTORY_HISTORY_LOCAL_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # typeset -g POWERLEVEL9K_PER_DIRECTORY_HISTORY_GLOBAL_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ################################[ cpu_arch: CPU architecture ]################################
  # CPU architecture color.
  typeset -g POWERLEVEL9K_CPU_ARCH_FOREGROUND=172

  # Hide the segment when on a specific CPU architecture.
  # typeset -g POWERLEVEL9K_CPU_ARCH_X86_64_CONTENT_EXPANSION=
  # typeset -g POWERLEVEL9K_CPU_ARCH_X86_64_VISUAL_IDENTIFIER_EXPANSION=

  # Custom icon.
  # typeset -g POWERLEVEL9K_CPU_ARCH_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ##################################[ context: user@hostname ]##################################
  # Context color when running with privileges.
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND=178
  # Context color in SSH without privileges.
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_FOREGROUND=180
  # Default context color (no privileges, no SSH).
  typeset -g POWERLEVEL9K_CONTEXT_FOREGROUND=180

  # Context format when running with privileges: bold user@hostname.
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_TEMPLATE='%B%n@%m'
  # Context format when in SSH without privileges: user@hostname.
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_TEMPLATE='%n@%m'
  # Default context format (no privileges, no SSH): user@hostname.
  typeset -g POWERLEVEL9K_CONTEXT_TEMPLATE='%n@%m'

  # Don't show context unless running with privileges or in SSH.
  # Tip: Remove the next line to always show context.
  typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_{CONTENT,VISUAL_IDENTIFIER}_EXPANSION=

  # Custom icon.
  # typeset -g POWERLEVEL9K_CONTEXT_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # Custom prefix.
  typeset -g POWERLEVEL9K_CONTEXT_PREFIX='%fwith '

  ###[ virtualenv: python virtual environment (https://docs.python.org/3/library/venv.html) ]###
  # Python virtual environment color.
  typeset -g POWERLEVEL9K_VIRTUALENV_FOREGROUND=37
  # Don't show Python version next to the virtual environment name.
  typeset -g POWERLEVEL9K_VIRTUALENV_SHOW_PYTHON_VERSION=false
  # If set to "false", won't show virtualenv if pyenv is already shown.
  # If set to "if-different", won't show virtualenv if it's the same as pyenv.
  typeset -g POWERLEVEL9K_VIRTUALENV_SHOW_WITH_PYENV=false
  # Separate environment name from Python version only with a space.
  typeset -g POWERLEVEL9K_VIRTUALENV_{LEFT,RIGHT}_DELIMITER=
  # Custom icon.
  typeset -g POWERLEVEL9K_VIRTUALENV_VISUAL_IDENTIFIER_EXPANSION='🐍'

  #####################[ anaconda: conda environment (https://conda.io/) ]######################
  # Anaconda environment color.
  typeset -g POWERLEVEL9K_ANACONDA_FOREGROUND=37

  # Anaconda segment format. The following parameters are available within the expansion.
  #
  # - CONDA_PREFIX                 Absolute path to the active Anaconda/Miniconda environment.
  # - CONDA_DEFAULT_ENV            Name of the active Anaconda/Miniconda environment.
  # - CONDA_PROMPT_MODIFIER        Configurable prompt modifier (see below).
  # - P9K_ANACONDA_PYTHON_VERSION  Current python version (python --version).
  #
  # CONDA_PROMPT_MODIFIER can be configured with the following command:
  #
  #   conda config --set env_prompt '({default_env}) '
  #
  # The last argument is a Python format string that can use the following variables:
  #
  # - prefix       The same as CONDA_PREFIX.
  # - default_env  The same as CONDA_DEFAULT_ENV.
  # - name         The last segment of CONDA_PREFIX.
  # - stacked_env  Comma-separated list of names in the environment stack. The first element is
  #                always the same as default_env.
  #
  # Note: '({default_env}) ' is the default value of env_prompt.
  #
  # The default value of POWERLEVEL9K_ANACONDA_CONTENT_EXPANSION expands to $CONDA_PROMPT_MODIFIER
  # without the surrounding parentheses, or to the last path component of CONDA_PREFIX if the former
  # is empty.
  typeset -g POWERLEVEL9K_ANACONDA_CONTENT_EXPANSION='${${${${CONDA_PROMPT_MODIFIER#\(}% }%\)}:-${CONDA_PREFIX:t}}'

  # Custom icon.
  typeset -g POWERLEVEL9K_ANACONDA_VISUAL_IDENTIFIER_EXPANSION='🐍'

  ################[ pyenv: python environment (https://github.com/pyenv/pyenv) ]################
  # Pyenv color.
  typeset -g POWERLEVEL9K_PYENV_FOREGROUND=37
  # Hide python version if it doesn't come from one of these sources.
  typeset -g POWERLEVEL9K_PYENV_SOURCES=(shell local global)
  # If set to false, hide python version if it's the same as global:
  # $(pyenv version-name) == $(pyenv global).
  typeset -g POWERLEVEL9K_PYENV_PROMPT_ALWAYS_SHOW=false
  # If set to false, hide python version if it's equal to "system".
  typeset -g POWERLEVEL9K_PYENV_SHOW_SYSTEM=true

  # Pyenv segment format. The following parameters are available within the expansion.
  #
  # - P9K_CONTENT                Current pyenv environment (pyenv version-name).
  # - P9K_PYENV_PYTHON_VERSION   Current python version (python --version).
  #
  # The default format has the following logic:
  #
  # 1. Display just "$P9K_CONTENT" if it's equal to "$P9K_PYENV_PYTHON_VERSION" or
  #    starts with "$P9K_PYENV_PYTHON_VERSION/".
  # 2. Otherwise display "$P9K_CONTENT $P9K_PYENV_PYTHON_VERSION".
  typeset -g POWERLEVEL9K_PYENV_CONTENT_EXPANSION='${P9K_CONTENT}${${P9K_CONTENT:#$P9K_PYENV_PYTHON_VERSION(|/*)}:+ $P9K_PYENV_PYTHON_VERSION}'

  # Custom icon.
  typeset -g POWERLEVEL9K_PYENV_VISUAL_IDENTIFIER_EXPANSION='🐍'

  ################[ goenv: go environment (https://github.com/syndbg/goenv) ]################
  # Goenv color.
  typeset -g POWERLEVEL9K_GOENV_FOREGROUND=37
  # Hide go version if it doesn't come from one of these sources.
  typeset -g POWERLEVEL9K_GOENV_SOURCES=(shell local global)
  # If set to false, hide go version if it's the same as global:
  # $(goenv version-name) == $(goenv global).
  typeset -g POWERLEVEL9K_GOENV_PROMPT_ALWAYS_SHOW=false
  # If set to false, hide go version if it's equal to "system".
  typeset -g POWERLEVEL9K_GOENV_SHOW_SYSTEM=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_GOENV_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ##########[ nodenv: node.js version from nodenv (https://github.com/nodenv/nodenv) ]##########
  # Nodenv color.
  typeset -g POWERLEVEL9K_NODENV_FOREGROUND=70
  # Hide node version if it doesn't come from one of these sources.
  typeset -g POWERLEVEL9K_NODENV_SOURCES=(shell local global)
  # If set to false, hide node version if it's the same as global:
  # $(nodenv version-name) == $(nodenv global).
  typeset -g POWERLEVEL9K_NODENV_PROMPT_ALWAYS_SHOW=false
  # If set to false, hide node version if it's equal to "system".
  typeset -g POWERLEVEL9K_NODENV_SHOW_SYSTEM=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_NODENV_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ##############[ nvm: node.js version from nvm (https://github.com/nvm-sh/nvm) ]###############
  # Nvm color.
  typeset -g POWERLEVEL9K_NVM_FOREGROUND=70
  # If set to false, hide node version if it's the same as default:
  # $(nvm version current) == $(nvm version default).
  typeset -g POWERLEVEL9K_NVM_PROMPT_ALWAYS_SHOW=false
  # If set to false, hide node version if it's equal to "system".
  typeset -g POWERLEVEL9K_NVM_SHOW_SYSTEM=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_NVM_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ############[ nodeenv: node.js environment (https://github.com/ekalinin/nodeenv) ]############
  # Nodeenv color.
  typeset -g POWERLEVEL9K_NODEENV_FOREGROUND=70
  # Don't show Node version next to the environment name.
  typeset -g POWERLEVEL9K_NODEENV_SHOW_NODE_VERSION=false
  # Separate environment name from Node version only with a space.
  typeset -g POWERLEVEL9K_NODEENV_{LEFT,RIGHT}_DELIMITER=
  # Custom icon.
  # typeset -g POWERLEVEL9K_NODEENV_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ##############################[ node_version: node.js version ]###############################
  # Node version color.
  typeset -g POWERLEVEL9K_NODE_VERSION_FOREGROUND=70
  # Show node version only when in a directory tree containing package.json.
  typeset -g POWERLEVEL9K_NODE_VERSION_PROJECT_ONLY=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_NODE_VERSION_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #######################[ go_version: go version (https://golang.org) ]########################
  # Go version color.
  typeset -g POWERLEVEL9K_GO_VERSION_FOREGROUND=37
  # Show go version only when in a go project subdirectory.
  typeset -g POWERLEVEL9K_GO_VERSION_PROJECT_ONLY=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_GO_VERSION_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #################[ rust_version: rustc version (https://www.rust-lang.org) ]##################
  # Rust version color.
  typeset -g POWERLEVEL9K_RUST_VERSION_FOREGROUND=37
  # Show rust version only when in a rust project subdirectory.
  typeset -g POWERLEVEL9K_RUST_VERSION_PROJECT_ONLY=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_RUST_VERSION_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ###############[ dotnet_version: .NET version (https://dotnet.microsoft.com) ]################
  # .NET version color.
  typeset -g POWERLEVEL9K_DOTNET_VERSION_FOREGROUND=134
  # Show .NET version only when in a .NET project subdirectory.
  typeset -g POWERLEVEL9K_DOTNET_VERSION_PROJECT_ONLY=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_DOTNET_VERSION_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #####################[ php_version: php version (https://www.php.net/) ]######################
  # PHP version color.
  typeset -g POWERLEVEL9K_PHP_VERSION_FOREGROUND=99
  # Show PHP version only when in a PHP project subdirectory.
  typeset -g POWERLEVEL9K_PHP_VERSION_PROJECT_ONLY=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_PHP_VERSION_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ##########[ laravel_version: laravel php framework version (https://laravel.com/) ]###########
  # Laravel version color.
  typeset -g POWERLEVEL9K_LARAVEL_VERSION_FOREGROUND=161
  # Custom icon.
  # typeset -g POWERLEVEL9K_LARAVEL_VERSION_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ####################[ java_version: java version (https://www.java.com/) ]####################
  # Java version color.
  typeset -g POWERLEVEL9K_JAVA_VERSION_FOREGROUND=32
  # Show java version only when in a java project subdirectory.
  typeset -g POWERLEVEL9K_JAVA_VERSION_PROJECT_ONLY=true
  # Show brief version.
  typeset -g POWERLEVEL9K_JAVA_VERSION_FULL=false
  # Custom icon.
  # typeset -g POWERLEVEL9K_JAVA_VERSION_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ###[ package: name@version from package.json (https://docs.npmjs.com/files/package.json) ]####
  # Package color.
  typeset -g POWERLEVEL9K_PACKAGE_FOREGROUND=117
  # Package format. The following parameters are available within the expansion.
  #
  # - P9K_PACKAGE_NAME     The value of `name` field in package.json.
  # - P9K_PACKAGE_VERSION  The value of `version` field in package.json.
  #
  # typeset -g POWERLEVEL9K_PACKAGE_CONTENT_EXPANSION='${P9K_PACKAGE_NAME//\%/%%}@${P9K_PACKAGE_VERSION//\%/%%}'
  # Custom icon.
  # typeset -g POWERLEVEL9K_PACKAGE_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #############[ rbenv: ruby version from rbenv (https://github.com/rbenv/rbenv) ]##############
  # Rbenv color.
  typeset -g POWERLEVEL9K_RBENV_FOREGROUND=168
  # Hide ruby version if it doesn't come from one of these sources.
  typeset -g POWERLEVEL9K_RBENV_SOURCES=(shell local global)
  # If set to false, hide ruby version if it's the same as global:
  # $(rbenv version-name) == $(rbenv global).
  typeset -g POWERLEVEL9K_RBENV_PROMPT_ALWAYS_SHOW=false
  # If set to false, hide ruby version if it's equal to "system".
  typeset -g POWERLEVEL9K_RBENV_SHOW_SYSTEM=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_RBENV_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #######################[ rvm: ruby version from rvm (https://rvm.io) ]########################
  # Rvm color.
  typeset -g POWERLEVEL9K_RVM_FOREGROUND=168
  # Don't show @gemset at the end.
  typeset -g POWERLEVEL9K_RVM_SHOW_GEMSET=false
  # Don't show ruby- at the front.
  typeset -g POWERLEVEL9K_RVM_SHOW_PREFIX=false
  # Custom icon.
  # typeset -g POWERLEVEL9K_RVM_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ###########[ fvm: flutter version management (https://github.com/leoafarias/fvm) ]############
  # Fvm color.
  typeset -g POWERLEVEL9K_FVM_FOREGROUND=38
  # Custom icon.
  # typeset -g POWERLEVEL9K_FVM_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ##########[ luaenv: lua version from luaenv (https://github.com/cehoffman/luaenv) ]###########
  # Lua color.
  typeset -g POWERLEVEL9K_LUAENV_FOREGROUND=32
  # Hide lua version if it doesn't come from one of these sources.
  typeset -g POWERLEVEL9K_LUAENV_SOURCES=(shell local global)
  # If set to false, hide lua version if it's the same as global:
  # $(luaenv version-name) == $(luaenv global).
  typeset -g POWERLEVEL9K_LUAENV_PROMPT_ALWAYS_SHOW=false
  # If set to false, hide lua version if it's equal to "system".
  typeset -g POWERLEVEL9K_LUAENV_SHOW_SYSTEM=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_LUAENV_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ###############[ jenv: java version from jenv (https://github.com/jenv/jenv) ]################
  # Java color.
  typeset -g POWERLEVEL9K_JENV_FOREGROUND=32
  # Hide java version if it doesn't come from one of these sources.
  typeset -g POWERLEVEL9K_JENV_SOURCES=(shell local global)
  # If set to false, hide java version if it's the same as global:
  # $(jenv version-name) == $(jenv global).
  typeset -g POWERLEVEL9K_JENV_PROMPT_ALWAYS_SHOW=false
  # If set to false, hide java version if it's equal to "system".
  typeset -g POWERLEVEL9K_JENV_SHOW_SYSTEM=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_JENV_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ###########[ plenv: perl version from plenv (https://github.com/tokuhirom/plenv) ]############
  # Perl color.
  typeset -g POWERLEVEL9K_PLENV_FOREGROUND=67
  # Hide perl version if it doesn't come from one of these sources.
  typeset -g POWERLEVEL9K_PLENV_SOURCES=(shell local global)
  # If set to false, hide perl version if it's the same as global:
  # $(plenv version-name) == $(plenv global).
  typeset -g POWERLEVEL9K_PLENV_PROMPT_ALWAYS_SHOW=false
  # If set to false, hide perl version if it's equal to "system".
  typeset -g POWERLEVEL9K_PLENV_SHOW_SYSTEM=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_PLENV_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ###########[ perlbrew: perl version from perlbrew (https://github.com/gugod/App-perlbrew) ]############
  # Perlbrew color.
  typeset -g POWERLEVEL9K_PERLBREW_FOREGROUND=67
  # Show perlbrew version only when in a perl project subdirectory.
  typeset -g POWERLEVEL9K_PERLBREW_PROJECT_ONLY=true
  # Don't show "perl-" at the front.
  typeset -g POWERLEVEL9K_PERLBREW_SHOW_PREFIX=false
  # Custom icon.
  # typeset -g POWERLEVEL9K_PERLBREW_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ############[ phpenv: php version from phpenv (https://github.com/phpenv/phpenv) ]############
  # PHP color.
  typeset -g POWERLEVEL9K_PHPENV_FOREGROUND=99
  # Hide php version if it doesn't come from one of these sources.
  typeset -g POWERLEVEL9K_PHPENV_SOURCES=(shell local global)
  # If set to false, hide php version if it's the same as global:
  # $(phpenv version-name) == $(phpenv global).
  typeset -g POWERLEVEL9K_PHPENV_PROMPT_ALWAYS_SHOW=false
  # If set to false, hide php version if it's equal to "system".
  typeset -g POWERLEVEL9K_PHPENV_SHOW_SYSTEM=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_PHPENV_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #######[ scalaenv: scala version from scalaenv (https://github.com/scalaenv/scalaenv) ]#######
  # Scala color.
  typeset -g POWERLEVEL9K_SCALAENV_FOREGROUND=160
  # Hide scala version if it doesn't come from one of these sources.
  typeset -g POWERLEVEL9K_SCALAENV_SOURCES=(shell local global)
  # If set to false, hide scala version if it's the same as global:
  # $(scalaenv version-name) == $(scalaenv global).
  typeset -g POWERLEVEL9K_SCALAENV_PROMPT_ALWAYS_SHOW=false
  # If set to false, hide scala version if it's equal to "system".
  typeset -g POWERLEVEL9K_SCALAENV_SHOW_SYSTEM=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_SCALAENV_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ##########[ haskell_stack: haskell version from stack (https://haskellstack.org/) ]###########
  # Haskell color.
  typeset -g POWERLEVEL9K_HASKELL_STACK_FOREGROUND=172
  # Hide haskell version if it doesn't come from one of these sources.
  #
  #   shell:  version is set by STACK_YAML
  #   local:  version is set by stack.yaml up the directory tree
  #   global: version is set by the implicit global project (~/.stack/global-project/stack.yaml)
  typeset -g POWERLEVEL9K_HASKELL_STACK_SOURCES=(shell local)
  # If set to false, hide haskell version if it's the same as in the implicit global project.
  typeset -g POWERLEVEL9K_HASKELL_STACK_ALWAYS_SHOW=true
  # Custom icon.
  # typeset -g POWERLEVEL9K_HASKELL_STACK_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #############[ kubecontext: current kubernetes context (https://kubernetes.io/) ]#############
  # Show kubecontext only when the command you are typing invokes one of these tools.
  # Tip: Remove the next line to always show kubecontext.
  # typeset -g POWERLEVEL9K_KUBECONTEXT_SHOW_ON_COMMAND='kubectl|helm|kubens|kubectx|oc|istioctl|kogito|k9s|helmfile|flux|fluxctl|stern|kubeseal|skaffold|kubent|kubecolor|cmctl|sparkctl'

  # Kubernetes context classes for the purpose of using different colors, icons and expansions with
  # different contexts.
  #
  # POWERLEVEL9K_KUBECONTEXT_CLASSES is an array with even number of elements. The first element
  # in each pair defines a pattern against which the current kubernetes context gets matched.
  # More specifically, it's P9K_CONTENT prior to the application of context expansion (see below)
  # that gets matched. If you unset all POWERLEVEL9K_KUBECONTEXT_*CONTENT_EXPANSION parameters,
  # you'll see this value in your prompt. The second element of each pair in
  # POWERLEVEL9K_KUBECONTEXT_CLASSES defines the context class. Patterns are tried in order. The
  # first match wins.
  #
  # For example, given these settings:
  #
  #   typeset -g POWERLEVEL9K_KUBECONTEXT_CLASSES=(
  #     '*prod*'  PROD
  #     '*test*'  TEST
  #     '*'       DEFAULT)
  #
  # If your current kubernetes context is "deathray-testing/default", its class is TEST
  # because "deathray-testing/default" doesn't match the pattern '*prod*' but does match '*test*'.
  #
  # You can define different colors, icons and content expansions for different classes:
  #
  #   typeset -g POWERLEVEL9K_KUBECONTEXT_TEST_FOREGROUND=28
  #   typeset -g POWERLEVEL9K_KUBECONTEXT_TEST_VISUAL_IDENTIFIER_EXPANSION='⭐'
  #   typeset -g POWERLEVEL9K_KUBECONTEXT_TEST_CONTENT_EXPANSION='> ${P9K_CONTENT} <'
  typeset -g POWERLEVEL9K_KUBECONTEXT_CLASSES=(
      # '*prod*'  PROD    # These values are examples that are unlikely
      # '*test*'  TEST    # to match your needs. Customize them as needed.
      '*'       DEFAULT)
  typeset -g POWERLEVEL9K_KUBECONTEXT_DEFAULT_FOREGROUND=134
  typeset -g POWERLEVEL9K_KUBECONTEXT_DEFAULT_VISUAL_IDENTIFIER_EXPANSION='☸️ '

  # Use POWERLEVEL9K_KUBECONTEXT_CONTENT_EXPANSION to specify the content displayed by kubecontext
  # segment. Parameter expansions are very flexible and fast, too. See reference:
  # http://zsh.sourceforge.net/Doc/Release/Expansion.html#Parameter-Expansion.
  #
  # Within the expansion the following parameters are always available:
  #
  # - P9K_CONTENT                The content that would've been displayed if there was no content
  #                              expansion defined.
  # - P9K_KUBECONTEXT_NAME       The current context's name. Corresponds to column NAME in the
  #                              output of `kubectl config get-contexts`.
  # - P9K_KUBECONTEXT_CLUSTER    The current context's cluster. Corresponds to column CLUSTER in the
  #                              output of `kubectl config get-contexts`.
  # - P9K_KUBECONTEXT_NAMESPACE  The current context's namespace. Corresponds to column NAMESPACE
  #                              in the output of `kubectl config get-contexts`. If there is no
  #                              namespace, the parameter is set to "default".
  # - P9K_KUBECONTEXT_USER       The current context's user. Corresponds to column AUTHINFO in the
  #                              output of `kubectl config get-contexts`.
  #
  # If the context points to Google Kubernetes Engine (GKE) or Elastic Kubernetes Service (EKS),
  # the following extra parameters are available:
  #
  # - P9K_KUBECONTEXT_CLOUD_NAME     Either "gke" or "eks".
  # - P9K_KUBECONTEXT_CLOUD_ACCOUNT  Account/project ID.
  # - P9K_KUBECONTEXT_CLOUD_ZONE     Availability zone.
  # - P9K_KUBECONTEXT_CLOUD_CLUSTER  Cluster.
  #
  # P9K_KUBECONTEXT_CLOUD_* parameters are derived from P9K_KUBECONTEXT_CLUSTER. For example,
  # if P9K_KUBECONTEXT_CLUSTER is "gke_my-account_us-east1-a_my-cluster-01":
  #
  #   - P9K_KUBECONTEXT_CLOUD_NAME=gke
  #   - P9K_KUBECONTEXT_CLOUD_ACCOUNT=my-account
  #   - P9K_KUBECONTEXT_CLOUD_ZONE=us-east1-a
  #   - P9K_KUBECONTEXT_CLOUD_CLUSTER=my-cluster-01
  #
  # If P9K_KUBECONTEXT_CLUSTER is "arn:aws:eks:us-east-1:123456789012:cluster/my-cluster-01":
  #
  #   - P9K_KUBECONTEXT_CLOUD_NAME=eks
  #   - P9K_KUBECONTEXT_CLOUD_ACCOUNT=123456789012
  #   - P9K_KUBECONTEXT_CLOUD_ZONE=us-east-1
  #   - P9K_KUBECONTEXT_CLOUD_CLUSTER=my-cluster-01

  typeset -g POWERLEVEL9K_KUBECONTEXT_DEFAULT_CONTENT_EXPANSION='${P9K_KUBECONTEXT_CLOUD_CLUSTER:-${${P9K_KUBECONTEXT_NAME##*/}##*@}}'

  # Custom prefix.
  typeset -g POWERLEVEL9K_KUBECONTEXT_PREFIX=''

  ################[ terraform: terraform workspace (https://www.terraform.io) ]#################
  # Don't show terraform workspace if it's literally "default".
  typeset -g POWERLEVEL9K_TERRAFORM_SHOW_DEFAULT=false
  # POWERLEVEL9K_TERRAFORM_CLASSES is an array with even number of elements. The first element
  # in each pair defines a pattern against which the current terraform workspace gets matched.
  # More specifically, it's P9K_CONTENT prior to the application of context expansion (see below)
  # that gets matched. If you unset all POWERLEVEL9K_TERRAFORM_*CONTENT_EXPANSION parameters,
  # you'll see this value in your prompt. The second element of each pair in
  # POWERLEVEL9K_TERRAFORM_CLASSES defines the workspace class. Patterns are tried in order. The
  # first match wins.
  #
  # For example, given these settings:
  #
  #   typeset -g POWERLEVEL9K_TERRAFORM_CLASSES=(
  #     '*prod*'  PROD
  #     '*test*'  TEST
  #     '*'       OTHER)
  #
  # If your current terraform workspace is "project_test", its class is TEST because "project_test"
  # doesn't match the pattern '*prod*' but does match '*test*'.
  #
  # You can define different colors, icons and content expansions for different classes:
  #
  #   typeset -g POWERLEVEL9K_TERRAFORM_TEST_FOREGROUND=28
  #   typeset -g POWERLEVEL9K_TERRAFORM_TEST_VISUAL_IDENTIFIER_EXPANSION='⭐'
  #   typeset -g POWERLEVEL9K_TERRAFORM_TEST_CONTENT_EXPANSION='> ${P9K_CONTENT} <'
  typeset -g POWERLEVEL9K_TERRAFORM_CLASSES=(
      # '*prod*'  PROD    # These values are examples that are unlikely
      # '*test*'  TEST    # to match your needs. Customize them as needed.
      '*'         OTHER)
  typeset -g POWERLEVEL9K_TERRAFORM_OTHER_FOREGROUND=38
  # typeset -g POWERLEVEL9K_TERRAFORM_OTHER_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #############[ terraform_version: terraform version (https://www.terraform.io) ]##############
  # Terraform version color.
  typeset -g POWERLEVEL9K_TERRAFORM_VERSION_FOREGROUND=38
  # Custom icon.
  # typeset -g POWERLEVEL9K_TERRAFORM_VERSION_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #[ aws: aws profile (https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html) ]#
  # Show aws only when the command you are typing invokes one of these tools.
  # Tip: Remove the next line to always show aws.
  typeset -g POWERLEVEL9K_AWS_SHOW_ON_COMMAND='aws|awless|cdk|terraform|tofu|pulumi|terragrunt'

  # POWERLEVEL9K_AWS_CLASSES is an array with even number of elements. The first element
  # in each pair defines a pattern against which the current AWS profile gets matched.
  # More specifically, it's P9K_CONTENT prior to the application of context expansion (see below)
  # that gets matched. If you unset all POWERLEVEL9K_AWS_*CONTENT_EXPANSION parameters,
  # you'll see this value in your prompt. The second element of each pair in
  # POWERLEVEL9K_AWS_CLASSES defines the profile class. Patterns are tried in order. The
  # first match wins.
  #
  # For example, given these settings:
  #
  #   typeset -g POWERLEVEL9K_AWS_CLASSES=(
  #     '*prod*'  PROD
  #     '*test*'  TEST
  #     '*'       DEFAULT)
  #
  # If your current AWS profile is "company_test", its class is TEST
  # because "company_test" doesn't match the pattern '*prod*' but does match '*test*'.
  #
  # You can define different colors, icons and content expansions for different classes:
  #
  #   typeset -g POWERLEVEL9K_AWS_TEST_FOREGROUND=28
  #   typeset -g POWERLEVEL9K_AWS_TEST_VISUAL_IDENTIFIER_EXPANSION='⭐'
  #   typeset -g POWERLEVEL9K_AWS_TEST_CONTENT_EXPANSION='> ${P9K_CONTENT} <'
  typeset -g POWERLEVEL9K_AWS_CLASSES=(
      # '*prod*'  PROD    # These values are examples that are unlikely
      # '*test*'  TEST    # to match your needs. Customize them as needed.
      '*'       DEFAULT)
  typeset -g POWERLEVEL9K_AWS_DEFAULT_FOREGROUND=208
  # typeset -g POWERLEVEL9K_AWS_DEFAULT_VISUAL_IDENTIFIER_EXPANSION='⭐'

  # AWS segment format. The following parameters are available within the expansion.
  #
  # - P9K_AWS_PROFILE  The name of the current AWS profile.
  # - P9K_AWS_REGION   The region associated with the current AWS profile.
  typeset -g POWERLEVEL9K_AWS_CONTENT_EXPANSION='${P9K_AWS_PROFILE//\%/%%}${P9K_AWS_REGION:+ ${P9K_AWS_REGION//\%/%%}}'

  #[ aws_eb_env: aws elastic beanstalk environment (https://aws.amazon.com/elasticbeanstalk/) ]#
  # AWS Elastic Beanstalk environment color.
  typeset -g POWERLEVEL9K_AWS_EB_ENV_FOREGROUND=70
  # Custom icon.
  # typeset -g POWERLEVEL9K_AWS_EB_ENV_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ##########[ azure: azure account name (https://docs.microsoft.com/en-us/cli/azure) ]##########
  # Show azure only when the command you are typing invokes one of these tools.
  # Tip: Remove the next line to always show azure.
  typeset -g POWERLEVEL9K_AZURE_SHOW_ON_COMMAND='az|terraform|tofu|pulumi|terragrunt'

  # POWERLEVEL9K_AZURE_CLASSES is an array with even number of elements. The first element
  # in each pair defines a pattern against which the current azure account name gets matched.
  # More specifically, it's P9K_CONTENT prior to the application of context expansion (see below)
  # that gets matched. If you unset all POWERLEVEL9K_AZURE_*CONTENT_EXPANSION parameters,
  # you'll see this value in your prompt. The second element of each pair in
  # POWERLEVEL9K_AZURE_CLASSES defines the account class. Patterns are tried in order. The
  # first match wins.
  #
  # For example, given these settings:
  #
  #   typeset -g POWERLEVEL9K_AZURE_CLASSES=(
  #     '*prod*'  PROD
  #     '*test*'  TEST
  #     '*'       OTHER)
  #
  # If your current azure account is "company_test", its class is TEST because "company_test"
  # doesn't match the pattern '*prod*' but does match '*test*'.
  #
  # You can define different colors, icons and content expansions for different classes:
  #
  #   typeset -g POWERLEVEL9K_AZURE_TEST_FOREGROUND=28
  #   typeset -g POWERLEVEL9K_AZURE_TEST_VISUAL_IDENTIFIER_EXPANSION='⭐'
  #   typeset -g POWERLEVEL9K_AZURE_TEST_CONTENT_EXPANSION='> ${P9K_CONTENT} <'
  typeset -g POWERLEVEL9K_AZURE_CLASSES=(
      # '*prod*'  PROD    # These values are examples that are unlikely
      # '*test*'  TEST    # to match your needs. Customize them as needed.
      '*'         OTHER)

  # Azure account name color.
  typeset -g POWERLEVEL9K_AZURE_OTHER_FOREGROUND=32
  # Custom icon.
  # typeset -g POWERLEVEL9K_AZURE_OTHER_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ##########[ gcloud: google cloud account and project (https://cloud.google.com/) ]###########
  # Show gcloud only when the command you are typing invokes one of these tools.
  # Tip: Remove the next line to always show gcloud.
  typeset -g POWERLEVEL9K_GCLOUD_SHOW_ON_COMMAND='gcloud|gcs|gsutil'
   # Google cloud color.
  typeset -g POWERLEVEL9K_GCLOUD_FOREGROUND=32

  # Google cloud format. Change the value of POWERLEVEL9K_GCLOUD_PARTIAL_CONTENT_EXPANSION and/or
  # POWERLEVEL9K_GCLOUD_COMPLETE_CONTENT_EXPANSION if the default is too verbose or not informative
  # enough. You can use the following parameters in the expansions. Each of them corresponds to the
  # output of `gcloud` tool.
  #
  #   Parameter                | Source
  #   -------------------------|--------------------------------------------------------------------
  #   P9K_GCLOUD_CONFIGURATION | gcloud config configurations list --format='value(name)'
  #   P9K_GCLOUD_ACCOUNT       | gcloud config get-value account
  #   P9K_GCLOUD_PROJECT_ID    | gcloud config get-value project
  #   P9K_GCLOUD_PROJECT_NAME  | gcloud projects describe $P9K_GCLOUD_PROJECT_ID --format='value(name)'
  #
  # Note: ${VARIABLE//\%/%%} expands to ${VARIABLE} with all occurrences of '%' replaced with '%%'.
  #
  # Obtaining project name requires sending a request to Google servers. This can take a long time
  # and even fail. When project name is unknown, P9K_GCLOUD_PROJECT_NAME is not set and gcloud
  # prompt segment is in state PARTIAL. When project name gets known, P9K_GCLOUD_PROJECT_NAME gets
  # set and gcloud prompt segment transitions to state COMPLETE.
  #
  # You can customize the format, icon and colors of gcloud segment separately for states PARTIAL
  # and COMPLETE. You can also hide gcloud in state PARTIAL by setting
  # POWERLEVEL9K_GCLOUD_PARTIAL_VISUAL_IDENTIFIER_EXPANSION and
  # POWERLEVEL9K_GCLOUD_PARTIAL_CONTENT_EXPANSION to empty.
  typeset -g POWERLEVEL9K_GCLOUD_PARTIAL_CONTENT_EXPANSION='${P9K_GCLOUD_PROJECT_ID//\%/%%}'
  typeset -g POWERLEVEL9K_GCLOUD_COMPLETE_CONTENT_EXPANSION='${P9K_GCLOUD_PROJECT_NAME//\%/%%}'

  # Send a request to Google (by means of `gcloud projects describe ...`) to obtain project name
  # this often. Negative value disables periodic polling. In this mode project name is retrieved
  # only when the current configuration, account or project id changes.
  typeset -g POWERLEVEL9K_GCLOUD_REFRESH_PROJECT_NAME_SECONDS=60

  # Custom icon.
  # typeset -g POWERLEVEL9K_GCLOUD_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #[ google_app_cred: google application credentials (https://cloud.google.com/docs/authentication/production) ]#
  # Show google_app_cred only when the command you are typing invokes one of these tools.
  # Tip: Remove the next line to always show google_app_cred.
  typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_SHOW_ON_COMMAND='terraform|tofu|pulumi|terragrunt'

  # Google application credentials classes for the purpose of using different colors, icons and
  # expansions with different credentials.
  #
  # POWERLEVEL9K_GOOGLE_APP_CRED_CLASSES is an array with even number of elements. The first
  # element in each pair defines a pattern against which the current kubernetes context gets
  # matched. More specifically, it's P9K_CONTENT prior to the application of context expansion
  # (see below) that gets matched. If you unset all POWERLEVEL9K_GOOGLE_APP_CRED_*CONTENT_EXPANSION
  # parameters, you'll see this value in your prompt. The second element of each pair in
  # POWERLEVEL9K_GOOGLE_APP_CRED_CLASSES defines the context class. Patterns are tried in order.
  # The first match wins.
  #
  # For example, given these settings:
  #
  #   typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_CLASSES=(
  #     '*:*prod*:*'  PROD
  #     '*:*test*:*'  TEST
  #     '*'           DEFAULT)
  #
  # If your current Google application credentials is "service_account deathray-testing x@y.com",
  # its class is TEST because it doesn't match the pattern '* *prod* *' but does match '* *test* *'.
  #
  # You can define different colors, icons and content expansions for different classes:
  #
  #   typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_TEST_FOREGROUND=28
  #   typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_TEST_VISUAL_IDENTIFIER_EXPANSION='⭐'
  #   typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_TEST_CONTENT_EXPANSION='$P9K_GOOGLE_APP_CRED_PROJECT_ID'
  typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_CLASSES=(
      # '*:*prod*:*'  PROD    # These values are examples that are unlikely
      # '*:*test*:*'  TEST    # to match your needs. Customize them as needed.
      '*'             DEFAULT)
  typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_DEFAULT_FOREGROUND=32
  # typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_DEFAULT_VISUAL_IDENTIFIER_EXPANSION='⭐'

  # Use POWERLEVEL9K_GOOGLE_APP_CRED_CONTENT_EXPANSION to specify the content displayed by
  # google_app_cred segment. Parameter expansions are very flexible and fast, too. See reference:
  # http://zsh.sourceforge.net/Doc/Release/Expansion.html#Parameter-Expansion.
  #
  # You can use the following parameters in the expansion. Each of them corresponds to one of the
  # fields in the JSON file pointed to by GOOGLE_APPLICATION_CREDENTIALS.
  #
  #   Parameter                        | JSON key file field
  #   ---------------------------------+---------------
  #   P9K_GOOGLE_APP_CRED_TYPE         | type
  #   P9K_GOOGLE_APP_CRED_PROJECT_ID   | project_id
  #   P9K_GOOGLE_APP_CRED_CLIENT_EMAIL | client_email
  #
  # Note: ${VARIABLE//\%/%%} expands to ${VARIABLE} with all occurrences of '%' replaced by '%%'.
  typeset -g POWERLEVEL9K_GOOGLE_APP_CRED_DEFAULT_CONTENT_EXPANSION='${P9K_GOOGLE_APP_CRED_PROJECT_ID//\%/%%}'

  ##############[ toolbox: toolbox name (https://github.com/containers/toolbox) ]###############
  # Toolbox color.
  typeset -g POWERLEVEL9K_TOOLBOX_FOREGROUND=178
  # Don't display the name of the toolbox if it matches fedora-toolbox-*.
  typeset -g POWERLEVEL9K_TOOLBOX_CONTENT_EXPANSION='${P9K_TOOLBOX_NAME:#fedora-toolbox-*}'
  # Custom icon.
  # typeset -g POWERLEVEL9K_TOOLBOX_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # Custom prefix.
  typeset -g POWERLEVEL9K_TOOLBOX_PREFIX='%fin '

  ###############################[ public_ip: public IP address ]###############################
  # Public IP color.
  typeset -g POWERLEVEL9K_PUBLIC_IP_FOREGROUND=94
  # Custom icon.
  # typeset -g POWERLEVEL9K_PUBLIC_IP_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ########################[ vpn_ip: virtual private network indicator ]#########################
  # VPN IP color.
  typeset -g POWERLEVEL9K_VPN_IP_FOREGROUND=81
  # When on VPN, show just an icon without the IP address.
  # Tip: To display the private IP address when on VPN, remove the next line.
  typeset -g POWERLEVEL9K_VPN_IP_CONTENT_EXPANSION=
  # Regular expression for the VPN network interface. Run `ifconfig` or `ip -4 a show` while on VPN
  # to see the name of the interface.
  typeset -g POWERLEVEL9K_VPN_IP_INTERFACE='(gpd|wg|(.*tun)|tailscale)[0-9]*|(zt.*)'
  # If set to true, show one segment per matching network interface. If set to false, show only
  # one segment corresponding to the first matching network interface.
  # Tip: If you set it to true, you'll probably want to unset POWERLEVEL9K_VPN_IP_CONTENT_EXPANSION.
  typeset -g POWERLEVEL9K_VPN_IP_SHOW_ALL=false
  # Custom icon.
  # typeset -g POWERLEVEL9K_VPN_IP_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ###########[ ip: ip address and bandwidth usage for a specified network interface ]###########
  # IP color.
  typeset -g POWERLEVEL9K_IP_FOREGROUND=38
  # The following parameters are accessible within the expansion:
  #
  #   Parameter             | Meaning
  #   ----------------------+-------------------------------------------
  #   P9K_IP_IP             | IP address
  #   P9K_IP_INTERFACE      | network interface
  #   P9K_IP_RX_BYTES       | total number of bytes received
  #   P9K_IP_TX_BYTES       | total number of bytes sent
  #   P9K_IP_RX_BYTES_DELTA | number of bytes received since last prompt
  #   P9K_IP_TX_BYTES_DELTA | number of bytes sent since last prompt
  #   P9K_IP_RX_RATE        | receive rate (since last prompt)
  #   P9K_IP_TX_RATE        | send rate (since last prompt)
  typeset -g POWERLEVEL9K_IP_CONTENT_EXPANSION='$P9K_IP_IP${P9K_IP_RX_RATE:+ %70F⇣$P9K_IP_RX_RATE}${P9K_IP_TX_RATE:+ %215F⇡$P9K_IP_TX_RATE}'
  # Show information for the first network interface whose name matches this regular expression.
  # Run `ifconfig` or `ip -4 a show` to see the names of all network interfaces.
  typeset -g POWERLEVEL9K_IP_INTERFACE='[ew].*'
  # Custom icon.
  # typeset -g POWERLEVEL9K_IP_VISUAL_IDENTIFIER_EXPANSION='⭐'

  #########################[ proxy: system-wide http/https/ftp proxy ]##########################
  # Proxy color.
  typeset -g POWERLEVEL9K_PROXY_FOREGROUND=68
  # Custom icon.
  # typeset -g POWERLEVEL9K_PROXY_VISUAL_IDENTIFIER_EXPANSION='⭐'

  ################################[ battery: internal battery ]#################################
  # Show battery in red when it's below this level and not connected to power supply.
  typeset -g POWERLEVEL9K_BATTERY_LOW_THRESHOLD=20
  typeset -g POWERLEVEL9K_BATTERY_LOW_FOREGROUND=160
  # Show battery in green when it's charging or fully charged.
  typeset -g POWERLEVEL9K_BATTERY_{CHARGING,CHARGED}_FOREGROUND=70
  # Show battery in yellow when it's discharging.
  typeset -g POWERLEVEL9K_BATTERY_DISCONNECTED_FOREGROUND=178
  # Battery pictograms going from low to high level of charge.
  typeset -g POWERLEVEL9K_BATTERY_STAGES=('%K{232}▁' '%K{232}▂' '%K{232}▃' '%K{232}▄' '%K{232}▅' '%K{232}▆' '%K{232}▇' '%K{232}█')
  # Don't show the remaining time to charge/discharge.
  typeset -g POWERLEVEL9K_BATTERY_VERBOSE=false

  #####################################[ wifi: wifi speed ]#####################################
  # WiFi color.
  typeset -g POWERLEVEL9K_WIFI_FOREGROUND=68
  # Custom icon.
  # typeset -g POWERLEVEL9K_WIFI_VISUAL_IDENTIFIER_EXPANSION='⭐'

  # Use different colors and icons depending on signal strength ($P9K_WIFI_BARS).
  #
  #   # Wifi colors and icons for different signal strength levels (low to high).
  #   typeset -g my_wifi_fg=(68 68 68 68 68)                           # <-- change these values
  #   typeset -g my_wifi_icon=('WiFi' 'WiFi' 'WiFi' 'WiFi' 'WiFi')     # <-- change these values
  #
  #   typeset -g POWERLEVEL9K_WIFI_CONTENT_EXPANSION='%F{${my_wifi_fg[P9K_WIFI_BARS+1]}}$P9K_WIFI_LAST_TX_RATE Mbps'
  #   typeset -g POWERLEVEL9K_WIFI_VISUAL_IDENTIFIER_EXPANSION='%F{${my_wifi_fg[P9K_WIFI_BARS+1]}}${my_wifi_icon[P9K_WIFI_BARS+1]}'
  #
  # The following parameters are accessible within the expansions:
  #
  #   Parameter             | Meaning
  #   ----------------------+---------------
  #   P9K_WIFI_SSID         | service set identifier, a.k.a. network name
  #   P9K_WIFI_LINK_AUTH    | authentication protocol such as "wpa2-psk" or "none"; empty if unknown
  #   P9K_WIFI_LAST_TX_RATE | wireless transmit rate in megabits per second
  #   P9K_WIFI_RSSI         | signal strength in dBm, from -120 to 0
  #   P9K_WIFI_NOISE        | noise in dBm, from -120 to 0
  #   P9K_WIFI_BARS         | signal strength in bars, from 0 to 4 (derived from P9K_WIFI_RSSI and P9K_WIFI_NOISE)

  ####################################[ time: current time ]####################################
  # Current time color.
  typeset -g POWERLEVEL9K_TIME_FOREGROUND=66
  # Format for the current time: 09:51:02. See `man 3 strftime`.
  typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%H:%M:%S}'
  # If set to true, time will update when you hit enter. This way prompts for the past
  # commands will contain the start times of their commands as opposed to the default
  # behavior where they contain the end times of their preceding commands.
  typeset -g POWERLEVEL9K_TIME_UPDATE_ON_COMMAND=false
  # Custom icon.
  # typeset -g POWERLEVEL9K_TIME_VISUAL_IDENTIFIER_EXPANSION='⭐'
  # Custom prefix.
  typeset -g POWERLEVEL9K_TIME_PREFIX=''

  # Example of a user-defined prompt segment. Function prompt_example will be called on every
  # prompt if `example` prompt segment is added to POWERLEVEL9K_LEFT_PROMPT_ELEMENTS or
  # POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS. It displays an icon and orange text greeting the user.
  #
  # Type `p10k help segment` for documentation and a more sophisticated example.
  function prompt_example() {
    p10k segment -f 208 -i '⭐' -t 'hello, %n'
  }

  # User-defined prompt segments may optionally provide an instant_prompt_* function. Its job
  # is to generate the prompt segment for display in instant prompt. See
  # https://github.com/romkatv/powerlevel10k#instant-prompt.
  #
  # Powerlevel10k will call instant_prompt_* at the same time as the regular prompt_* function
  # and will record all `p10k segment` calls it makes. When displaying instant prompt, Powerlevel10k
  # will replay these calls without actually calling instant_prompt_*. It is imperative that
  # instant_prompt_* always makes the same `p10k segment` calls regardless of environment. If this
  # rule is not observed, the content of instant prompt will be incorrect.
  #
  # Usually, you should either not define instant_prompt_* or simply call prompt_* from it. If
  # instant_prompt_* is not defined for a segment, the segment won't be shown in instant prompt.
  function instant_prompt_example() {
    # Since prompt_example always makes the same `p10k segment` calls, we can call it from
    # instant_prompt_example. This will give us the same `example` prompt segment in the instant
    # and regular prompts.
    prompt_example
  }

  # User-defined prompt segments can be customized the same way as built-in segments.
  # typeset -g POWERLEVEL9K_EXAMPLE_FOREGROUND=208
  # typeset -g POWERLEVEL9K_EXAMPLE_VISUAL_IDENTIFIER_EXPANSION='⭐'

  # Transient prompt works similarly to the builtin transient_rprompt option. It trims down prompt
  # when accepting a command line. Supported values:
  #
  #   - off:      Don't change prompt when accepting a command line.
  #   - always:   Trim down prompt when accepting a command line.
  #   - same-dir: Trim down prompt when accepting a command line unless this is the first command
  #               typed after changing current working directory.
  typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=off

  # Instant prompt mode.
  #
  #   - off:     Disable instant prompt. Choose this if you've tried instant prompt and found
  #              it incompatible with your zsh configuration files.
  #   - quiet:   Enable instant prompt and don't print warnings when detecting console output
  #              during zsh initialization. Choose this if you've read and understood
  #              https://github.com/romkatv/powerlevel10k#instant-prompt.
  #   - verbose: Enable instant prompt and print a warning when detecting console output during
  #              zsh initialization. Choose this if you've never tried instant prompt, haven't
  #              seen the warning, or if you are unsure what this all means.
  typeset -g POWERLEVEL9K_INSTANT_PROMPT=verbose

  # Hot reload allows you to change POWERLEVEL9K options after Powerlevel10k has been initialized.
  # For example, you can type POWERLEVEL9K_BACKGROUND=red and see your prompt turn red. Hot reload
  # can slow down prompt by 1-2 milliseconds, so it's better to keep it turned off unless you
  # really need it.
  typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true

  # If p10k is already loaded, reload configuration.
  # This works even with POWERLEVEL9K_DISABLE_HOT_RELOAD=true.
  (( ! $+functions[p10k] )) || p10k reload
}

# Tell `p10k configure` which file it should overwrite.
typeset -g POWERLEVEL9K_CONFIG_FILE=${${(%):-%x}:a}

(( ${#p10k_config_opts} )) && setopt ${p10k_config_opts[@]}
'builtin' 'unset' 'p10k_config_opts'
P10K_EMBED_EOF
    chmod 644 ~/.p10k.zsh
    success "~/.p10k.zsh written. 🎨"
fi

# ==============================================================================
# 📝  14. VIM-PLUG + VIM SETUP
# ==============================================================================
if [[ "$SETUP_VIM" == "y" ]]; then
    section "📝  14. Vim Config"
   
    if [[ -f "$HOME/.vim/autoload/plug.vim" ]] && [[ "$OVERWRITE_DOTFILES" != "y" ]]; then
        skip "vim-plug is already installed."
    else
        info "Downloading vim-plug plugin manager..."
        sudo rm -f ~/.vim/autoload/plug.vim
        if curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim; then
            success "vim-plug installed."
        else
            warn "vim-plug download failed — Vim plugins will not be installed."
        fi
    fi
   
    if [[ ! -d "$HOME/.vim/undodir" ]]; then
        info "Creating ~/.vim/undodir for persistent undo history..."
        mkdir -p ~/.vim/undodir
        success "Vim directories ready."
    else
        skip "~/.vim/undodir already exists."
    fi
   
    if [[ -f ~/.vimrc ]] && [[ "$OVERWRITE_DOTFILES" != "y" ]]; then
        skip "~/.vimrc already exists and overwrite is disabled."
    else
        if [[ -f ~/.vimrc ]]; then
            cp ~/.vimrc "$HOME/.vimrc.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
            warn "Existing ~/.vimrc backed up."
        fi
        sudo rm -f ~/.vimrc
        info "Writing ~/.vimrc..."
        cat << 'VIMRC_EOF' > ~/.vimrc
" ✨ WSL / Native Ubuntu 24.04 — Full Dev Environment
" ==============================================================================
" 1. PLUGINS
" ==============================================================================
call plug#begin('~/.vim/plugged')

Plug 'preservim/nerdtree'                                         " File explorer sidebar (Ctrl+n)
Plug 'itchyny/lightline.vim'                                      " Lightweight, configurable status bar
Plug 'nordtheme/vim'                                              " Modern Nord color scheme
Plug 'jiangmiao/auto-pairs'                                       " Auto-close brackets, quotes, etc.
Plug 'neoclide/coc.nvim', {'branch': 'release'}                   " Language Server Protocol client
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }               " fzf core (uses system fzf)
Plug 'junegunn/fzf.vim'                                           " fzf-powered :Files, :Buffers, :Rg
Plug 'ryanoasis/vim-devicons'                                     " Icons for NERDTree and others
Plug 'tpope/vim-fugitive'                                         " Git integration
Plug 'airblade/vim-gitgutter'                                     " Git diff in gutter
Plug 'sheerun/vim-polyglot'                                       " Better syntax highlighting for all languages

call plug#end()

" ==============================================================================
" 2. THEME & UI
" ==============================================================================
syntax on
if (has("termguicolors"))
    set termguicolors
endif

" --- NORD_THEME_START ---
" Nord theme configuration
let g:nord_italic = 1
let g:nord_italic_comments = 1
let g:nord_underline = 1
let g:nord_cursor_line_number_background = 1
let g:nord_uniform_diff_background = 1
let g:nord_bold_vertical_split_line = 1

set background=dark
silent! colorscheme nord
let g:lightline = { 'colorscheme': 'nord' }
" --- NORD_THEME_END ---

" Fix for transparent background if using a terminal with Nord background
" highlight Normal guibg=NONE ctermbg=NONE
" highlight LineNr guibg=NONE ctermbg=NONE

" ==============================================================================
" 3. CORE SETTINGS
" ==============================================================================
set nocompatible             " Disable vi compatibility mode
set encoding=utf-8
set autoread                 " Auto-reload files changed outside Vim
set number                   " Absolute line number on current line
set relativenumber           " Relative numbers on all other lines
set cursorline               " Highlight the entire current line
set wildmenu                 " Enhanced command-line completion
set showmatch                " Briefly jump to matching bracket
set ruler                    " Show cursor position (row, col)
set splitbelow               " :split opens new pane below
set splitright               " :vsplit opens new pane to the right
set scrolloff=8              " Context above/below cursor
set signcolumn=yes           " Always show the gutter column
set updatetime=300           " ms before CursorHold fires

" --- Indentation ---
set expandtab                " Insert spaces instead of tabs
set tabstop=4                " Visual width of a tab
set shiftwidth=4             " Size of an indent step
set autoindent               " Copy indent from previous line
set smartindent              " Extra auto-indent for code blocks

" --- Search ---
set incsearch                " Highlight matches as you type
set hlsearch                 " Keep matches highlighted
set ignorecase               " Case-insensitive search by default
set smartcase                " Case-sensitive if uppercase used

" --- Misc ---
set noerrorbells
set visualbell               " Flash screen instead of beeping
set history=1000
set backspace=indent,eol,start
set clipboard=unnamedplus    " Use system clipboard

" --- Persistent Undo ---
if !isdirectory($HOME."/.vim/undodir")
    call mkdir($HOME."/.vim/undodir", "p")
endif
set undodir=~/.vim/undodir
set undofile

" ==============================================================================
" 4. PLUGIN SETTINGS
" ==============================================================================
map <C-n> :NERDTreeToggle<CR>
let NERDTreeShowHidden=1
autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif

" ==============================================================================
" 5. KEY MAPPINGS
" ==============================================================================
let mapleader = " "

nnoremap <leader><CR> :noh<CR>  
nnoremap <leader>w    :w<CR>    
nnoremap <leader>q    :q<CR>    
nnoremap <leader>n :set invnumber invrelativenumber<CR>

" Window navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

xnoremap p "_dP

nnoremap <leader>f :Files<CR>
nnoremap <leader>b :Buffers<CR>
nnoremap <leader>h :History<CR>

" ==============================================================================
" 6. COC.NVIM
" ==============================================================================
inoremap <expr> <Tab>   pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <CR>    pumvisible() ? "\<C-y>" : "\<CR>"

nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)
nmap <leader>rn <Plug>(coc-rename)

nnoremap <silent> K :call <SID>show_documentation()<CR>
function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  elseif (coc#rpc#ready())
    call CocActionAsync('doHover')
  else
    execute '!' . &keywordprg . " " . expand('<cword>')
  endif
endfunction
VIMRC_EOF

        info "Installing Vim plugins via vim-plug (this may take a moment)..."
        apply_theme_choice ~/.vimrc
        vim -E -s +PlugInstall +qall || true
        success "Vim setup complete. Open vim and run :PlugStatus to verify."
    fi
else
    section "📝  14. Vim Config — SKIPPED (user opt-out)"
fi


# ==============================================================================
# 📋  15. TMUX CONFIGURATION (Nord Theme)
# ==============================================================================
section "📋  15. Tmux Configuration"

if [[ -f ~/.tmux.conf ]] && [[ "$OVERWRITE_DOTFILES" != "y" ]]; then
    skip "~/.tmux.conf already exists."
else
    if [[ -f ~/.tmux.conf ]]; then
        cp ~/.tmux.conf "$HOME/.tmux.conf.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        warn "Existing ~/.tmux.conf backed up."
    fi
    sudo rm -f ~/.tmux.conf

    info "Writing ~/.tmux.conf with Nord theme..."
    cat << 'TMUX_EOF' > ~/.tmux.conf
# ✨ WSL / Native Ubuntu 24.04 — Full Dev Environment

# --- General ---
set -g default-terminal "screen-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
set -g history-limit 10000
set -g mouse on
set -s escape-time 0
set -g base-index 1
setw -g pane-base-index 1

# --- NORD_THEME_START ---
# --- Nord Theme ---
set -g status-bg "#3B4252"
set -g status-fg "#D8DEE9"
set -g status-interval 1

# Status bar layout
set -g status-left-length 30
set -g status-left "#[fg=#3B4252,bg=#88C0D0,bold] #S #[default] "

set -g status-right-length 150
set -g status-right "#[fg=#D8DEE9,bg=#434C5E] %Y-%m-%d #[fg=#D8DEE9,bg=#4C566A] %H:%M #[fg=#3B4252,bg=#88C0D0,bold] #H "

# Window status
setw -g window-status-format "#[fg=#D8DEE9,bg=#3B4252] #I:#W "
setw -g window-status-current-format "#[fg=#3B4252,bg=#81A1C1,bold] #I:#W "
setw -g window-status-separator ""

# Pane borders
set -g pane-border-style "fg=#4C566A"
set -g pane-active-border-style "fg=#88C0D0"

# Message style
set -g message-style "fg=#D8DEE9,bg=#434C5E"
# --- NORD_THEME_END ---

# --- Keybindings ---
bind r source-file ~/.tmux.conf \; display "Reloaded!"
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
TMUX_EOF
    apply_theme_choice ~/.tmux.conf
    success "~/.tmux.conf created. 📋"
fi


# ==============================================================================
# 🪟  16. TERMINATOR CONFIGURATION & PYTHON PLUGIN
# ==============================================================================
section "🪟  16. Terminator Configuration & Plugins"

if [[ -f ~/.config/terminator/config ]] && [[ "$OVERWRITE_DOTFILES" != "y" ]]; then
    skip "~/.config/terminator/config already exists."
else
    if [[ -f ~/.config/terminator/config ]]; then
        cp ~/.config/terminator/config "$HOME/.config/terminator/config.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        warn "Existing terminator config backed up."
    fi
    sudo rm -f ~/.config/terminator/config

    info "Writing ~/.config/terminator/config..."
    mkdir -p ~/.config/terminator

    cat << 'TERMINATOR_EOF' > ~/.config/terminator/config
[global_config]
  window_state = maximise
  enabled_plugins = LaunchpadBugURLHandler, LaunchpadCodeURLHandler, APTURLHandler, GridTabIconizer
  always_split_with_profile = True
  link_single_click = True
  copy_on_selection = False
[keybindings]
[profiles]
  [[default]]
    cursor_shape = underline
    font = MesloLGS NF 11
    scrollback_infinite = True
    use_system_font = False
    title_hide_sizetext = True
    title_transmit_fg_color = "#e5e9f0"
    title_transmit_bg_color = "#bf616a"
    title_receive_fg_color = "#e5e9f0"
    title_receive_bg_color = "#81a1c1"
    title_inactive_fg_color = "#c0bebf"
    title_inactive_bg_color = "#4c566a"
    title_use_system_font = False
    title_font = MesloLGS NF 12
# --- NORD_THEME_START ---
  [[Nord]]
    background_color = "#2E3440"
    cursor_shape = underline
    cursor_bg_color = "#D8DEE9"
    font = MesloLGS NF 11
    foreground_color = "#D8DEE9"
    scrollback_infinite = True
    palette = "#3b4252:#bf616a:#a3be8c:#ebcb8b:#81a1c1:#b48ead:#88c0d0:#e5e9f0:#4c566a:#bf616a:#a3be8c:#ebcb8b:#81a1c1:#b48ead:#8fbcbb:#eceff4"
    use_system_font = False
    title_hide_sizetext = True
    title_transmit_fg_color = "#e5e9f0"
    title_transmit_bg_color = "#bf616a"
    title_receive_fg_color = "#e5e9f0"
    title_receive_bg_color = "#81a1c1"
    title_inactive_fg_color = "#c0bebf"
    title_inactive_bg_color = "#4c566a"
    title_use_system_font = False
    title_font = MesloLGS NF 12
# --- NORD_THEME_END ---
[layouts]
  [[default]]
    [[[child0]]]
      type = Window
      parent = ""
      order = 0
      maximised = True
      fullscreen = False
      title = TERMINATOR
      last_active_term = aa999a93-860e-4ec0-a9ce-e4d3d55e9bec
      last_active_window = True
    [[[terminal1]]]
      type = Terminal
      parent = child0
      order = 0
      profile = __TERMINATOR_PROFILE__
      uuid = aa999a93-860e-4ec0-a9ce-e4d3d55e9bec
[plugins]
TERMINATOR_EOF
   
    apply_theme_choice ~/.config/terminator/config
    success "Terminator configuration written. 🪟"

    info "Installing GridTabIconizer Python plugin..."
    mkdir -p ~/.config/terminator/plugins
    sudo rm -f ~/.config/terminator/plugins/grid_tabs.py

    # We flush this to the left margin to ensure strict Python indentation
    cat << 'PYTHON_EOF' > ~/.config/terminator/plugins/grid_tabs.py
import gi
from gi.repository import Gtk, GLib
import terminatorlib.plugin as plugin
from terminatorlib.terminator import Terminator
from terminatorlib.notebook import Notebook
from terminatorlib.terminal import Terminal

AVAILABLE = ['GridTabIconizer']

class GridTabIconizer(plugin.Plugin):
    """Dynamically updates tab AND Window titles to ONLY show layout grid icons."""
   
    capabilities = []

    def __init__(self):
        super(GridTabIconizer, self).__init__()
        self.terminator = Terminator()
        # Checks layout twice a second (500ms) to beat ZSH/Bash title updates
        self.timer_id = GLib.timeout_add(500, self.update_titles)

    def update_titles(self):
        try:
            for window in self.terminator.windows:
                # 1. Update tabs if they exist
                has_notebook = self._find_and_update_notebooks(window)
               
                # 2. If there are no tabs, update the main Window Title
                if not has_notebook:
                    icon = self._get_layout_icon(window)
                    if window.get_title() != icon:
                        window.set_title(icon)

        except Exception as e:
            print(f"GridTabIconizer Error: {e}")
           
        return True # Return True to keep the GTK timer running loop alive

    def _get_layout_icon(self, widget):
        """Map layout topologies to exact Unicode icons."""
        count = self._count_terminals(widget)
       
        if count == 1:
            return ""
        elif count == 2:
            return self._analyze_2pane_split(widget)
        elif count == 3:
            return self._analyze_3pane_split(widget)
        else:
            return ""

    def _analyze_2pane_split(self, widget):
        """Determine if a 2-pane layout is Side-by-Side () or Stacked ()."""
        if hasattr(widget, 'get_children'):
            children = widget.get_children()
           
            # Terminator Paned widgets (splits) have exactly 2 children
            if len(children) == 2:
                class_name = type(widget).__name__
               
                # HPaned = side-by-side (Left/Right)
                if class_name == 'HPaned':
                    return ""
                # VPaned = stacked (Top/Bottom)
                elif class_name == 'VPaned':
                    return ""
                # Fallback check for GTK3 Orientation
                elif hasattr(widget, 'get_orientation'):
                    if widget.get_orientation() == Gtk.Orientation.HORIZONTAL:
                        return ""
                    else:
                        return ""
           
            # Search deeper if the split is inside a container (like a Window)
            for child in children:
                res = self._analyze_2pane_split(child)
                if res in ["", ""]:
                    return res
                   
        return "" # Fallback default

    def _analyze_3pane_split(self, widget):
        """Determine if a 3-pane layout is Left-Split () or Right-Split ()."""
        if hasattr(widget, 'get_children'):
            children = widget.get_children()
           
            if len(children) == 2:
                c0_count = self._count_terminals(children[0]) # Left or Top
                c1_count = self._count_terminals(children[1]) # Right or Bottom
               
                if c0_count == 2 and c1_count == 1:
                    return "" # Left pane is split, right pane is full
                elif c0_count == 1 and c1_count == 2:
                    return "" # Left pane is full, right pane is split
           
            for child in children:
                res = self._analyze_3pane_split(child)
                if res in ["", ""]:
                    return res
                   
        return ""

    def _find_and_update_notebooks(self, widget):
        """Recursively search for the GTK Notebook and update its tabs. Returns True if found."""
        found = False
        if isinstance(widget, Notebook):
            self._update_notebook_pages(widget)
            return True
        elif hasattr(widget, 'get_children'):
            for child in widget.get_children():
                if self._find_and_update_notebooks(child):
                    found = True
        return found

    def _update_notebook_pages(self, notebook):
        """Iterate over tabs and update their titles based on pane count and topology."""
        for i in range(notebook.get_n_pages()):
            page = notebook.get_nth_page(i)
            icon = self._get_layout_icon(page)
           
            # Update the main OS window title to match the currently active tab
            if notebook.get_current_page() == i:
                window = notebook.get_toplevel()
                if isinstance(window, Gtk.Window) and window.get_title() != icon:
                    window.set_title(icon)
           
            # Update the GTK Tab Label
            label_box = notebook.get_tab_label(page)
            if not label_box:
                continue

            # Terminator specifically wraps the text in a '.label' attribute inside TabLabel
            label_widget = getattr(label_box, 'label', None)
           
            # Fallback search just in case GTK hierarchy changes in future versions
            if not label_widget and hasattr(label_box, 'get_children'):
                for child in label_box.get_children():
                    if isinstance(child, Gtk.Label):
                        label_widget = child
                        break
                       
            if label_widget and label_widget.get_text() != icon:
                label_widget.set_text(icon)

    def _count_terminals(self, widget):
        """Recursively count how many terminal panes are nested in a specific tab or window."""
        count = 0
        if isinstance(widget, Terminal):
            return 1
        if hasattr(widget, 'get_children'):
            for child in widget.get_children():
                count += self._count_terminals(child)
        return count

    def unload(self):
        """Cleanup GTK timer when the plugin is disabled or Terminator closes."""
        if self.timer_id:
            GLib.source_remove(self.timer_id)
PYTHON_EOF
   
    success "GridTabIconizer Python plugin injected."
fi


# ==============================================================================
# 🖥️  17. WSL — WINDOWS TERMINATOR LAUNCHER  (skipped on native Linux)
# ==============================================================================
section "🖥️  17. Windows Integration"

if $IS_WSL; then
    if [[ -n "$WINDOWS_USER" ]]; then
        WIN_DOCS="/mnt/c/Users/${WINDOWS_USER}/Documents"
        WIN_TERM="$WIN_DOCS/Terminator"

        if [[ -d "$WIN_DOCS" ]]; then
            info "Creating Documents/Terminator/ folder and writing launcher scripts..."
            mkdir -p "$WIN_TERM"

            cat << 'BAT_EOF' > "$WIN_TERM/terminator-launch.bat"
@echo off
wsl.exe --cd ~ -- bash -c "mkdir -p /tmp/runtime-$USER && chmod 0700 /tmp/runtime-$USER && XDG_RUNTIME_DIR=/tmp/runtime-$USER XCURSOR_SIZE=24 dbus-run-session terminator -m >/dev/null 2>&1"
BAT_EOF

            cat << 'VBS_EOF' > "$WIN_TERM/terminator-invisible.vbs"
Set WshShell = CreateObject("WScript.Shell")
batPath = WshShell.ExpandEnvironmentStrings("%USERPROFILE%\Documents\Terminator\terminator-launch.bat")
WshShell.Run Chr(34) & batPath & Chr(34), 0, False
VBS_EOF

            info "Converting Terminator icon to Windows .ico format..."
            if command -v convert >/dev/null 2>&1; then
                ICON_SRC=""
                for p in /usr/share/pixmaps/terminator.png /usr/share/icons/hicolor/48x48/apps/terminator.png; do
                    if [[ -f "$p" ]]; then ICON_SRC="$p"; break; fi
                done

                if [[ -n "$ICON_SRC" ]]; then
                    convert "$ICON_SRC" -strip -background none "$WIN_TERM/terminator.ico" 2>/dev/null || true
                    success "Launcher scripts and ICO written to Documents/Terminator/. 🪄"
                else
                    warn "terminator.png not found, skipping icon conversion."
                fi
            else
                warn "ImageMagick not found, skipping icon conversion."
            fi
        else
            warn "Could not find Windows directory at $WIN_DOCS. Skipping."
        fi
    else
        skip "Windows username not provided, skipping Terminator launcher."
    fi
else
    skip "Native Linux detected, skipping Windows integration."
fi


# ==============================================================================
# 👑  18. DEFAULT SHELL → ZSH
# ==============================================================================
section "👑  18. Setting Default Shell to ${DEFAULT_SHELL_CHOICE^^}"

SHELL_BIN="$(which "${DEFAULT_SHELL_CHOICE}" 2>/dev/null || true)"
if [[ -z "$SHELL_BIN" ]]; then
    warn "${DEFAULT_SHELL_CHOICE} binary not found — shell change skipped."
elif [[ "$SHELL" != "$SHELL_BIN" ]]; then
    info "Changing default shell to $SHELL_BIN for user $USER..."
    if sudo chsh -s "$SHELL_BIN" "$USER"; then
        success "Default shell changed to ${DEFAULT_SHELL_CHOICE}."
    else
        warn "chsh failed — change shell manually: sudo chsh -s $SHELL_BIN $USER"
    fi
else
    success "${DEFAULT_SHELL_CHOICE^} is already the default shell."
fi
# ── 📜 Bash → Zsh History Migration ──
if [[ "$DEFAULT_SHELL_CHOICE" == "zsh" && -f ~/.bash_history ]]; then
    BASH_HIST_LINES=$(wc -l < ~/.bash_history)
    if [[ "$BASH_HIST_LINES" -gt 0 ]]; then
        info "Importing bash history into ~/.zsh_history..."

        # Bash history may contain HISTTIMEFORMAT comment lines (e.g. #1234567890).
        # Filter those out, deduplicate, then append only entries not already in zsh history.
        TMPFILE=$(mktemp)

        grep -v '^#[0-9]\+' ~/.bash_history > "$TMPFILE" || true

        if [[ -f ~/.zsh_history ]]; then
            # Strip zsh extended-history timestamps (: 1234:0;command → command)
            ZSH_CMDS=$(grep -v '^:' ~/.zsh_history || true)
            # Append only lines not already present in zsh history
            while IFS= read -r line; do
                if [[ -n "$line" ]] && ! grep -qxF "$line" <(echo "$ZSH_CMDS"); then
                    echo "$line" >> ~/.zsh_history
                fi
            done < "$TMPFILE"
        else
            cp "$TMPFILE" ~/.zsh_history
        fi

        rm -f "$TMPFILE"
        IMPORTED=$(wc -l < ~/.zsh_history)
        success "History migrated — ~/.zsh_history now has ${IMPORTED} entries."
    else
        skip "~/.bash_history is empty, skipping history migration."
    fi
else
    skip "History migration skipped (shell: ${DEFAULT_SHELL_CHOICE}, bash_history exists: $([ -f ~/.bash_history ] && echo yes || echo no))."
fi


# ==============================================================================
# 🎉  19. DONE — POST-INSTALL CHECKLIST
# ==============================================================================
section "🎉  19. Setup Complete!"

echo -e "\n${GREEN}${BOLD}All requested steps have finished.${RESET} Reminder of manual steps:\n"
echo -e "${YELLOW}📜  Shell & Tool configs written${RESET}"
echo -e "  ┣ ${BOLD}~/.bashrc${RESET}  — active for bash sessions"
echo -e "  ┣ ${BOLD}~/.zshrc${RESET}   — active for zsh sessions (default: ${DEFAULT_SHELL_CHOICE})"
echo -e "  ┣ ${BOLD}~/.config/terminator/config${RESET}  — ready for Terminator"
echo -e "  ┣ ${BOLD}~/.p10k.zsh${RESET} — embedded Powerlevel10k config written automatically"
echo -e "  ┗ To regenerate the prompt wizard: run 'p10k configure'\n"
echo -e "${YELLOW}🐚  Shell${RESET}"
echo -e "  ┣ Default shell set to: ${BOLD}${DEFAULT_SHELL_CHOICE}${RESET}"
if [[ "$DEFAULT_SHELL_CHOICE" == "zsh" && -f ~/.zsh_history ]]; then
    echo -e "  ┗ Bash history imported into ~/.zsh_history ($(wc -l < ~/.zsh_history) entries).\n"
else
    echo -e "  ┗ To migrate history later: grep -v '^#[0-9]' ~/.bash_history >> ~/.zsh_history\n"
fi

if $IS_WSL; then
    echo -e "${YELLOW}🪟  Terminator Launcher (Windows Desktop Shortcut)${RESET}"
    if [[ -n "$WINDOWS_USER" && -f "/mnt/c/Users/${WINDOWS_USER}/Documents/Terminator/terminator-invisible.vbs" ]]; then
        echo -e "  ┣ Right-click your Windows Desktop -> New -> Shortcut"
        printf "  ┣ Set Target: %b%s%b\n" "${BOLD}" 'wscript.exe "%USERPROFILE%\Documents\Terminator\terminator-invisible.vbs"' "${RESET}"
        echo -e "  ┣ Click Next, name it 'Terminator', and click Finish"
        printf "  ┗ Right-click Shortcut -> Properties -> Change Icon -> Browse to %b%s%b\n\n" "${BOLD}" 'Documents\Terminator\terminator.ico' "${RESET}"
    else
        echo -e "  ┗ (Skipped — Windows username not provided)\n"
    fi

    echo -e "${YELLOW}🔤  Fonts (Windows side)${RESET}"
    echo -e "  ┣ Install MesloLGS NF in Windows (same URL as WSL download)"
    echo -e "  ┣ Install Font Awesome Desktop files to your Windows Font folder (from the website)"
    echo -e "  ┣ Set them as the fallback font in Windows Terminal / VS Code / etc."
    if [[ "$SET_MESLO_GLOBAL" == "y" ]]; then
        echo -e "  ┗ MesloLGS NF set as system monospace via fontconfig for Linux apps.\n"
    else
        echo -e "  ┗ System default (Ubuntu Mono/DejaVu) set as system monospace.\n"
    fi
else
    echo -e "${YELLOW}🔤  Fonts${RESET}"
    echo -e "  ┣ MesloLGS NF and Font Awesome are now installed on your system."
    echo -e "  ┣ Ensure your terminal emulator uses MesloLGS NF."
    if [[ "$SET_MESLO_GLOBAL" == "y" ]]; then
        echo -e "  ┗ MesloLGS NF set as system monospace via gsettings + fontconfig.\n"
    else
        echo -e "  ┗ System default (Ubuntu Mono/DejaVu) set as system monospace.\n"
    fi
fi

if [[ "$CREATE_GPG" == "y" && -n "$GIT_SIGNING_KEY" ]]; then
    echo -e "${YELLOW}🛡️  GPG key (for signed git commits)${RESET}"
    echo -e "  ┣ New key created and trusted: ${BOLD}${GIT_SIGNING_KEY}${RESET}"
    echo -e "  ┣ Add to GitHub (Settings → SSH and GPG keys → New GPG key):"
    echo -e "  ┃   gpg --armor --export ${GIT_SIGNING_KEY}"
    echo -e "  ┗ Back it up: gpg --export-secret-keys ${GIT_SIGNING_KEY} > ~/gpg-backup.key\n"
elif [[ -n "$GIT_SIGNING_KEY" && -n "$GPG_IMPORT_PATH" ]]; then
    echo -e "${YELLOW}🛡️  GPG key (for signed git commits)${RESET}"
    echo -e "  ┣ Key ID ${BOLD}${GIT_SIGNING_KEY}${RESET} imported and trusted."
    echo -e "  ┣ Add to GitHub if not already there (Settings → SSH and GPG keys → New GPG key):"
    echo -e "  ┃   gpg --armor --export ${GIT_SIGNING_KEY}"
    echo -e "  ┗ Commits will be signed automatically with 'gacp' or 'git commit -S'.\n"
elif [[ -n "$GIT_SIGNING_KEY" && -z "$GPG_IMPORT_PATH" ]]; then
    echo -e "${YELLOW}🛡️  GPG key (for signed git commits)${RESET}"
    echo -e "  ┣ Key ID ${BOLD}${GIT_SIGNING_KEY}${RESET} is configured in git."
    echo -e "  ┣ Import your key: gpg --import ~/gpg.key"
    echo -e "  ┗ Trust it: gpg --edit-key YOUR_KEY_ID  →  trust  →  5  →  quit\n"
fi

if [[ "$GENERATE_SSH" == "y" && -f ~/.ssh/id_ed25519.pub ]]; then
    echo -e "${YELLOW}🔑  SSH keys${RESET}"
    echo -e "  ┣ New Ed25519 key generated successfully!"
    echo -e "  ┣ ${BOLD}$(cat ~/.ssh/id_ed25519.pub)${RESET}"
    echo -e "  ┗ Add this key to GitHub / GitLab / Bitbucket (Settings → SSH Keys)\n"
elif [[ "$SSH_ACTION" == "existing" && -f ~/.ssh/id_ed25519.pub ]]; then
    echo -e "${YELLOW}🔑  SSH keys${RESET}"
    echo -e "  ┣ Key pair imported to ~/.ssh/id_ed25519 successfully!"
    echo -e "  ┣ ${BOLD}$(cat ~/.ssh/id_ed25519.pub)${RESET}"
    echo -e "  ┗ Ensure this key is already added to GitHub / GitLab / Bitbucket\n"
elif [[ -f ~/.ssh/id_ed25519.pub ]]; then
    echo -e "${YELLOW}🔑  SSH keys${RESET}"
    echo -e "  ┣ Using existing public key found in ~/.ssh/id_ed25519.pub:"
    echo -e "  ┣ ${BOLD}$(cat ~/.ssh/id_ed25519.pub)${RESET}"
    echo -e "  ┗ Ensure this key is added to GitHub / GitLab / Bitbucket\n"
else
    echo -e "${YELLOW}🔑  SSH keys${RESET}"
    echo -e "  ┣ No SSH key was set up. To add one later:"
    echo -e "  ┃   ssh-keygen -t ed25519 -C 'your@email.com'"
    echo -e "  ┗ Then add the public key to GitHub / GitLab / Bitbucket\n"
fi

if [[ "$USE_MULTI_GIT" == "y" ]]; then
    echo -e "${YELLOW}👔  Per-directory git identity files${RESET}"
    [[ -n "${GIT_INCLUDE_FILE_1:-}" ]] && echo -e "  ┣ Create ${BOLD}${GIT_INCLUDE_FILE_1}${RESET} with [user] name/email/signingkey"
    [[ -n "${GIT_INCLUDE_FILE_2:-}" ]] && echo -e "  ┗ Create ${BOLD}${GIT_INCLUDE_FILE_2}${RESET} with [user] name/email/signingkey\n"
fi

echo -e "${YELLOW}☁️  Cloud CLI authentication${RESET}"
echo -e "  ┣ GitHub:        gh auth login${GITHUB_USERNAME:+  (your username: $GITHUB_USERNAME)}"
echo -e "  ┣ Azure:         az login"
echo -e "  ┗ Google Cloud:  gcloud auth login\n"

echo -e "${BOLD}🚀 → Log out and log back in to fully activate ${DEFAULT_SHELL_CHOICE} and docker groups!${RESET}\n"
