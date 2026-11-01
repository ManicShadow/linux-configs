# ❄️   linux-configs — Full Dev Environment Setup

[![Support me on Patreon](https://img.shields.io/badge/Patreon-Support_Me-F96854?style=for-the-badge&logo=patreon&logoColor=white)](https://patreon.com/ManicShadow)

A single, idempotent Bash script that clones a complete DevOps-ready development environment onto any fresh Ubuntu 24.04 machine or WSL instance. Answer the prompts once, grab a coffee, and come back to a fully configured workstation.

---

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Interactive Prompts](#interactive-prompts)
- [Nord Theme](#nord-theme)
- [Tools Installed](#tools-installed)
- [Dotfiles Generated](#dotfiles-generated)
- [Shell Configuration](#shell-configuration)
- [WSL Integration](#wsl-integration)
- [Post-Install Checklist](#post-install-checklist)
- [Requirements](#requirements)
- [License](#license)

---

## Features

| Feature | Details |
| :--- | :--- |
| **Idempotent** | Safe to re-run — already-installed packages are skipped; dotfiles are updated/overwritten by default. Existing dotfiles are automatically backed up with a timestamp (e.g. `~/.bashrc.backup.20260514120000`) before any overwrite. |
| **Nord Theme** | Live terminal colour palette preview before you choose; applied to Vim, Terminator, and shell prompts. **Fallback to clean global defaults if disabled.** |
| **Dual Shell** | Choose `zsh` (recommended, with Oh My Zsh + Powerlevel10k) or `bash` as your default login shell |
| **Powerlevel10k Config** | Your personal `~/.p10k.zsh` is embedded directly — prompt is ready on first login, no wizard needed. Directory segment names are always shown in full (`truncate_to_last`, 3 segments kept); no single-char abbreviations even with long Kubernetes context names. |
| **History Migration** | When switching to zsh, bash history is automatically deduplicated and merged into `~/.zsh_history` |
| **Nerd Font** | MesloLGS NF downloaded and optionally set as the global monospace font. **Fallback to Ubuntu Mono / DejaVu if disabled.** |
| **GPG Signing** | Generate a new ed25519 GPG key, or import an existing one — both are auto-trusted and wired into git commit signing |
| **SSH Key** | Generate a new Ed25519 SSH key, or import an existing key pair — public key is derived automatically if only the private key is provided |
| **Multi-Identity Git** | Per-directory `[includeIf]` blocks for work vs. personal git identities |
| **Sudo Keep-Alive** | Background process keeps sudo credentials refreshed for the entire run |
| **WSL Extras** | Simple Terminator launcher (BAT + VBS) in `Documents\Terminator\`, Terminator icon, Windows shared-folder alias, and a custom Terminator Grid Layout plugin |

---

## Quick Start

```bash
# Clone the repo
git clone https://github.com/ManicShadow/linux-configs.git
cd linux-configs

# Make executable and run
chmod +x scripts/devops-setup.sh
bash scripts/devops-setup.sh
```

> **Run as your normal user — not root.** You need `sudo` access.  
> The full run takes approximately **5–10 minutes** on a fresh machine.

---

## Interactive Prompts

All personal data is collected up-front in Section 0. Nothing is hardcoded in the script. Prompts follow a two-line format: a description line with a context-specific emoji, followed by an input line with default value indicators. **Press ENTER to accept [defaults <default value>] y/n.**

### Prompt Format Example:
```bash
🐚   Choose your default login shell.
 💭  Default shell Press ENTER to accept [defaults zsh] y/n: 
```
*(Pressing ENTER here would select zsh)*

| Prompt | Default | Category | Notes |
| :--- | :---: | :---: | :--- |
| Overwrite dotfiles? | `Y` | 🧹   | Overwrites .bashrc, .zshrc, .vimrc, terminator config, etc. The previous version of each file is saved as `<file>.backup.<timestamp>` before being replaced. |
| Overwrite SSH & GPG keys? | `N` | 🔐   | Safe to answer `N` on re-runs |
| Git name | — | 👤   | Your full name for git commits |
| Git email | — | 📧   | Your primary git email |
| GitHub username | — | 🐙   | Used for GitHub CLI (gh) authentication guidance |
| Create ~/.gitconfig? | `N` | 📝   | Opt-in — writes identity, GPG signing, LFS filters, aliases; never touched unless `Y` |
| SSH key action | `skip` | 🔑   | `new` (generate Ed25519), `existing` (import key pair), or `skip` |
| Path to SSH private key | — | 📥  | Only shown when action is `existing` — copied to `~/.ssh/id_ed25519` |
| Path to SSH public key | — | 📥  | Optional — if blank, derived automatically from the private key |
| GPG key action | `skip` | 🛡️    | `new`, `existing`, or `skip` |
| GPG signing key ID | — | 🔑   | 16-char hex ID from your old machine |
| Path to GPG key file | — | 📥  | Auto-imported and trusted at ultimate level |
| Multiple git identities? | `N` | 🔀   | Sets up `[includeIf]` blocks in `.gitconfig` |
| Windows username | detected | 🪟   | Sets `shared_folder` alias (WSL only) |
| Set up Vim with plugins? | `Y` | 🪄   | Installs vim-plug + NERDTree, CoC, etc. |
| Default shell | `zsh` | 🐚   | `zsh` or `bash` |
| Apply Nord Theme? | `Y` | ❄️    | Live colour palette preview shown before this |
| Set global font? | `Y` | 🔤   | Applies via `gsettings` and `fontconfig` |
| Kubernetes channel | `v1.33` | ☸️    | Determines `kubectl` apt minor version |
| Node.js version | `20` | 🟢   | Installed via NodeSource (20, 22) |

---

## Nord Theme

The script renders a true-colour palette preview in your terminal so you can see the theme before committing to it.

### Polar Night — dark backgrounds

| Swatch | Hex | Usage |
| :---: | :--- | :--- |
| ![#2E3440](https://placehold.co/24x24/2E3440/2E3440.png) | `#2E3440` | Primary terminal / editor background |
| ![#3B4252](https://placehold.co/24x24/3B4252/3B4252.png) | `#3B4252` | Status bars, tab backgrounds |
| ![#434C5E](https://placehold.co/24x24/434C5E/434C5E.png) | `#434C5E` | Selection highlights, indent guides |
| ![#4C566A](https://placehold.co/24x24/4C566A/4C566A.png) | `#4C566A` | Comments, subtle UI elements |

### Snow Storm — light text

| Swatch | Hex | Usage |
| :---: | :--- | :--- |
| ![#D8DEE9](https://placehold.co/24x24/D8DEE9/D8DEE9.png) | `#D8DEE9` | Primary foreground text |
| ![#E5E9F0](https://placehold.co/24x24/E5E9F0/E5E9F0.png) | `#E5E9F0` | Brighter text, active item labels |
| ![#ECEFF4](https://placehold.co/24x24/ECEFF4/ECEFF4.png) | `#ECEFF4` | Highlighted / selected text |

### Frost — blue accents

| Swatch | Hex | Usage |
| :---: | :--- | :--- |
| ![#8FBCBB](https://placehold.co/24x24/8FBCBB/8FBCBB.png) | `#8FBCBB` | Classes, types |
| ![#88C0D0](https://placehold.co/24x24/88C0D0/88C0D0.png) | `#88C0D0` | Functions, primary accent |
| ![#81A1C1](https://placehold.co/24x24/81A1C1/81A1C1.png) | `#81A1C1` | Keywords, links |
| ![#5E81AC](https://placehold.co/24x24/5E81AC/5E81AC.png) | `#5E81AC` | Operators, constants |

### Aurora — semantic colours

| Swatch | Hex | Usage |
| :---: | :--- | :--- |
| ![#BF616A](https://placehold.co/24x24/BF616A/BF616A.png) | `#BF616A` | Errors, deleted lines |
| ![#D08770](https://placehold.co/24x24/D08770/D08770.png) | `#D08770` | Warnings, annotations |
| ![#EBCB8B](https://placehold.co/24x24/EBCB8B/EBCB8B.png) | `#EBCB8B` | Modified lines, strings |
| ![#A3BE8C](https://placehold.co/24x24/A3BE8C/A3BE8C.png) | `#A3BE8C` | Added lines, success |
| ![#B48EAD](https://placehold.co/24x24/B48EAD/B48EAD.png) | `#B48EAD` | Numbers, constants |

Nord is applied to **Vim** (via `vim-nord`), **Terminator** (colour palette + profile), **tmux** (status bar), and **shell** (FZF colours + terminal palette via `apply_nord_palette`). 

**Declining Nord keeps a clean default configuration instead**, with fallback logic for fonts (Ubuntu Mono / DejaVu) and CLI tools (base16 for bat, rounded borders for fzf).

---

## Tools Installed

### APT packages

| Category | Packages |
| :--- | :--- |
| **Containers** | `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin` |
| **Kubernetes** | `kubectl` (via official k8s apt channel) |
| **Cloud / IaC** | `terraform`, `ansible`, `azure-cli`, `google-cloud-cli`, `google-cloud-sdk-gke-gcloud-auth-plugin` |
| **Shell** | `zsh`, `fzf`, `zoxide`, `eza`, `tmux` |
| **Editors** | `vim-gtk3` |
| **VCS** | `git`, `git-lfs`, `gh` (GitHub CLI) |
| **Languages** | `python3`, `python3.11`, `python3.12` (with `-dev`/`-venv` variants), `python3-pip`, `pipx`, `nodejs`, `openjdk-21-jdk`, `openjdk-21-jre`, `maven`, `gradle` |
| **Utilities** | `bat`, `jq`, `ripgrep`, `fd-find`, `wget`, `curl`, `unzip`, `fontconfig`, `imagemagick`, `google-chrome-stable`, `bind9-dnsutils`, `sshuttle`, `extundelete` |
| **Terminal** | `terminator`, `pcmanfm`, `mousepad`, `powerline`, `powerline-doc`, `powerline-gitstatus`, `python3-powerline-gitstatus`, `fonts-powerline`, `xclip` |
| **WSL / Display** | `xvfb`, `dbus-x11`, `mesa-utils`, `mesa-vulkan-drivers`, `xfonts-cyrillic`, `xfonts-scalable`, `libsecret-1-0` |
| **Fonts (apt)** | `fonts-font-awesome`, `fonts-freefont-ttf`, `fonts-ipafont-gothic`, `fonts-liberation`, `fonts-noto-color-emoji`, `fonts-tlwg-loma-otf`, `fonts-unifont`, `fonts-wqy-zenhei` |

### Snap

| Package | Notes |
| :--- | :--- |
| `yq` | YAML processor (classic channel) |

### Binary installs (to `/usr/local/bin`)

| Tool | Source |
| :--- | :--- |
| **Helm** | Latest release from `get.helm.sh` |
| **Helmfile** | Latest GitHub release |
| **kubelogin** | Latest GitHub release (Azure AD kubectl plugin) |
| **Lazygit** | Latest GitHub release |

### pipx

| Package | Notes |
| :--- | :--- |
| `git-filter-repo` | Rewrites git history without BFG |

### Zsh plugins (Oh My Zsh)

| Plugin | Source |
| :--- | :--- |
| **Oh My Zsh** | `ohmyzsh/ohmyzsh` |
| **Powerlevel10k** | `romkatv/powerlevel10k` theme |
| **zsh-autosuggestions** | `zsh-users/zsh-autosuggestions` |
| **zsh-syntax-highlighting** | `zsh-users/zsh-syntax-highlighting` |

### Fonts

| Font | Source |
| :--- | :--- |
| **MesloLGS NF** | 4 variants (Regular, Bold, Italic, Bold Italic) from `romkatv/powerlevel10k-media` |
| **Font Awesome Free** | Latest desktop `.zip` from `FortAwesome/Font-Awesome` GitHub Releases (OTF files) |

---

## Dotfiles Generated

| File | Contents |
| :--- | :--- |
| `~/.bashrc` | PATH, GPG TTY, aliases, `gacp` function, Nord FZF colours + terminal palette (when Nord enabled) |
| `~/.zshrc` | Oh My Zsh + Powerlevel10k, same aliases as bashrc, zoxide init, Nord FZF colours + terminal palette |
| `~/.vimrc` | vim-plug, NERDTree, Lightline, Nord colorscheme, CoC LSP, fzf.vim, GitGutter, auto-pairs, vim-devicons, vim-fugitive, vim-polyglot |
| `~/.gitconfig` | **Opt-in** (`Create ~/.gitconfig? → Y`). Writes: `user.name/email`, GPG signing, `push.autoSetupRemote`, `pull.rebase`, LFS filters, `init.defaultBranch = main`, `core.filemode = false`, `[includeIf]` identity blocks, `cleanup` alias |
| `~/.tmux.conf` | Mouse support, Nord status bar, intuitive split/reload bindings |
| `~/.config/terminator/config` | Nord colour palette profile, custom font, layout; `copy_on_selection = False` to suppress WSL clipboard warnings |
| `~/.config/terminator/plugins/grid_tabs.py` | GridTabIconizer — Python plugin that shows Unicode pane-layout icons in Terminator tab and window titles based on the active split layout |
| `~/.p10k.zsh` | Your saved Powerlevel10k configuration — embedded directly, active on first zsh login *(zsh only)* |
| `~/.config/fontconfig/fonts.conf` | Prefers MesloLGS NF for all monospace applications (when enabled) |

---

## Shell Configuration

### Aliases (available in both bash and zsh)

| Alias | Expands to |
| :--- | :--- |
| `ls` | `eza --color=always --icons --group-directories-first` |
| `ll` | `eza -la --icons --group-directories-first --git` |
| `cat` | `batcat --style=plain --paging=never` |
| `k` | `kubectl` *(added when kubectl is on PATH)* |
| `..` / `...` / `....` | `cd ..` / `cd ../..` / `cd ../../..` |
| `gco` | `git checkout` |
| `gcb` | `git checkout -b` |
| `gfpo` | `git fetch --prune origin` |
| `gbd` | `git branch -D` |
| `git-perms-on` | `git config core.filemode true` |
| `git-perms-off` | `git config core.filemode false` |
| `bashconfig` | `vim ~/.bashrc` *(bash only)* |
| `vimconfig` | `vim ~/.vimrc` |
| `bash_reload` | `source ~/.bashrc` *(bash only)* |
| `zshconfig` | `vim ~/.zshrc` *(zsh only)* |
| `zsh_reload` | `source ~/.zshrc` *(zsh only)* |
| `explorer` | `explorer.exe .` *(WSL only)* |
| `chrome` | `google-chrome --use-angle=vulkan --use-vulkan --enable-features=Vulkan --ignore-gpu-blocklist &` *(WSL only)* |
| `shared_folder` | `cd /mnt/c/Users/<WINDOWS_USER>/Documents/SharedLinux` *(WSL only)* |

### `gacp` function

A single command to stage, commit (with optional GPG signing), and push:

```bash
gacp "commit message"
# expands to: git add -A && git commit [-S] -m "commit message" && git push
```

### Other shell functions (available in both bash and zsh)

| Function | Description |
| :--- | :--- |
| `connect_cluster <sub> <rg> <cluster>` | Sets `KUBECONFIG`, runs `az aks get-credentials`, and converts kubeconfig with `kubelogin` (Azure AD). Also updates the shell prompt to show the cluster name. |
| `maincolors` | Prints a visual grid of the 16 terminal colours (indices 0–15) with their current hex values — useful for verifying Nord or custom palette output. |
| `fm [path]` | Opens PCManFM file manager detached from the terminal (silent, backgrounded). |

### Bash → Zsh history migration

When you choose `zsh` as your default shell, the script automatically:

1. Reads `~/.bash_history` and strips timestamp comment lines (`#1234567890`)
2. Deduplicates against any existing `~/.zsh_history` entries
3. Appends the unique commands to `~/.zsh_history`

> **Manual tip (if skipping migration):** `cat ~/.bash_history >> ~/.zsh_history`

### GPG TTY

Both dotfiles export `GPG_TTY=$(tty)` so commit signing works correctly in terminal sessions.

---

## WSL Integration

When the script detects WSL (`/proc/version` contains `microsoft`), it performs additional setup:

| Feature | Details |
| :--- | :--- |
| **Terminator Launcher** | Creates `%USERPROFILE%\Documents\Terminator\` and writes `terminator-launch.bat` (launches Terminator with `--cd ~` to start in the WSL home directory, `XDG_RUNTIME_DIR`, `XCURSOR_SIZE=24`, and `dbus-run-session terminator -m`) and `terminator-invisible.vbs` (invisible wrapper — no console window on launch) |
| **Terminator Icon** | Converts the installed `terminator.png` to `terminator.ico` (via ImageMagick) and saves it to `%USERPROFILE%\Documents\Terminator\` |
| **Shared Folder Alias** | `shared_folder` alias → `/mnt/c/Users/<WINDOWS_USER>/Documents/SharedLinux` |

### Creating a Windows Desktop Shortcut for Terminator

1. **Right-click** the Desktop → **New** → **Shortcut**
2. **Target:** `wscript.exe "%USERPROFILE%\Documents\Terminator\terminator-invisible.vbs"`
3. Click **Next**, name it `Terminator`, click **Finish**
4. **Right-click** the shortcut → **Properties** → **Change Icon** → browse to `%USERPROFILE%\Documents\Terminator\terminator.ico`
5. Click **OK** and pin to taskbar if desired

---

## Post-Install Checklist

After the script completes, follow these steps:

- [ ] **Log out and log back in** — activates the new default shell and `docker` group membership
- [ ] **Add SSH key to GitHub** *(if you chose `new`)*: `cat ~/.ssh/id_ed25519.pub` then paste into GitHub → Settings → SSH Keys. Skip if you imported an existing key that is already there.
- [ ] **Add GPG key to GitHub:** `gpg --armor --export <KEY_ID>` then paste into GitHub → Settings → SSH and GPG Keys → New GPG key
- [ ] **Back up your GPG key** *(if you chose `new`)*: `gpg --export-secret-keys <KEY_ID> > ~/gpg-backup.key` and store it safely
- [ ] **Powerlevel10k:** your saved `~/.p10k.zsh` config is embedded and written automatically — no setup needed. Run `p10k configure` only if you want to regenerate it.
- [ ] **Set terminal font:** In Terminator/your terminal emulator, select **MesloLGS NF** as the font to display Powerlevel10k icons correctly
- [ ] **Verify commit signing:** `git commit --allow-empty -m "test gpg" -S` then `git log --show-signature -1`
- [ ] **WSL only:** Create the Windows Terminator shortcut (target: `wscript.exe "%USERPROFILE%\Documents\Terminator\terminator-invisible.vbs"`)

---

## Requirements

| Requirement | Notes |
| :--- | :--- |
| Ubuntu 24.04 (or WSL2 running Ubuntu 24.04) | Other Debian-based distros may work with minor adjustments |
| `sudo` access | Required for apt installs, `chsh`, and Docker group management |
| Internet connection | All tools are downloaded from official sources during the run |
| ~3 GB disk space | For all packages, fonts, and plugin installations |

---

## License

This project is licensed under the GNU General Public License v3.0 — see the [LICENSE](LICENSE) file for details.
