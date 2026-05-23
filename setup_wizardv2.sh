#!/bin/bash
set -e

# ================================================
# COLORES Y ESTILOS
# ================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'
CHECK="${GREEN}✔${RESET}"
CROSS="${RED}✘${RESET}"
ARROW="${CYAN}▶${RESET}"

# ================================================
# HELPERS UI
# ================================================
print_header() {
  echo -e "${BLUE}${BOLD}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║        🚀  Setup Wizard — Pop!_OS            ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo -e "${RESET}"
}

print_section() {
  echo -e "\n${MAGENTA}${BOLD}── $1 ──────────────────────────────────────${RESET}\n"
}

print_step()  { echo -e "  ${ARROW} $1"; }
print_ok()    { echo -e "  ${CHECK} ${GREEN}$1${RESET}"; }
print_skip()  { echo -e "  ${DIM}⊘  $1 — omitido${RESET}"; }
print_error() { echo -e "  ${CROSS} ${RED}$1${RESET}"; }
print_warn()  { echo -e "  ${YELLOW}⚠  $1${RESET}"; }

# ================================================
# SUDO — capturar y mantener vivo
# ================================================
require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    echo -e "\n  ${YELLOW}Se necesita contraseña de sudo para continuar.${RESET}"
    sudo -v
  fi
  while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done &
  SUDO_KEEPER_PID=$!
}

# ================================================
# TRAP — limpieza al salir (normal, error o Ctrl+C)
# ================================================
cleanup() {
  tput cnorm 2>/dev/null || true   # FIX: restaurar cursor aunque sea Ctrl+C
  stty sane  2>/dev/null || true   # FIX: restaurar terminal si quedó en raw mode
  [[ -n "${SUDO_KEEPER_PID:-}" ]] && kill "$SUDO_KEEPER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM   # FIX: también atrapa Ctrl+C (INT) y TERM

# ================================================
# CONFIRM — con restauración de terminal previa
# ================================================
confirm() {
  local default="${2:-n}"
  local prompt
  stty sane 2>/dev/null || true  # FIX: asegurar terminal sana antes de leer
  [[ "$default" == "y" ]] && prompt="[Y/n]" || prompt="[y/N]"
  echo -ne "  ${YELLOW}?${RESET} $1 ${DIM}$prompt${RESET} "
  read -r answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

# ================================================
# DEPENDENCIAS DEL WIZARD
# ================================================
ensure_deps() {
  for dep in curl wget git gpg unzip; do
    if ! command -v "$dep" &>/dev/null; then
      sudo apt-get install -y -qq "$dep"
    fi
  done
}

# ================================================
# GITHUB API — helper con manejo de rate limit
# ================================================
github_latest_url() {
  local repo="$1" filter="$2"
  local response url

  # FIX: sin -f para poder leer errores HTTP (rate limit, etc.) antes de fallar
  response=$(curl -s "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)
  if [[ -z "$response" ]]; then
    print_error "Sin respuesta de GitHub API (¿sin internet?)"
    return 1
  fi

  # Ahora sí llega aquí el JSON de error
  if echo "$response" | grep -q '"message"'; then
    local msg
    msg=$(echo "$response" | grep '"message"' | cut -d '"' -f 4)
    print_error "GitHub API: $msg"
    return 1
  fi

  url=$(echo "$response" | grep browser_download_url | grep "$filter" | cut -d '"' -f 4 | head -n 1)
  if [[ -z "$url" ]]; then
    print_error "No se encontró release para '$filter' en $repo"
    return 1
  fi
  echo "$url"
}

# ================================================
# INSTALADORES INDIVIDUALES
# ================================================

install_base() {
  print_step "Actualizando sistema y paquetes base..."
  sudo apt update -qq && sudo apt upgrade -y -qq
  sudo apt install -y -qq \
    build-essential curl wget git unzip zsh \
    software-properties-common apt-transport-https \
    ca-certificates gnupg lsb-release
  print_ok "Base del sistema lista"
}

install_zsh_ohmyzsh() {
  print_step "Instalando Zsh + Oh My Zsh..."
  sudo apt install -y -qq zsh fonts-powerline

  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    sudo chsh -s "$(which zsh)" "$USER"
  else
    print_skip "Oh My Zsh ya instalado"
  fi

  # FIX: verificar si el plugin ya existe antes de clonar
  local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone --quiet https://github.com/zsh-users/zsh-syntax-highlighting.git \
      "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  fi
  if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone --quiet https://github.com/zsh-users/zsh-autosuggestions \
      "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  fi

  print_ok "Zsh + Oh My Zsh instalados"
}

install_ohmyposh() {
  if command -v oh-my-posh &>/dev/null; then
    print_skip "Oh My Posh ya está instalado"
    return
  fi
  print_step "Instalando Oh My Posh..."
  mkdir -p "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
  curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
  print_ok "Oh My Posh instalado"
}

install_nerd_fonts() {
  print_step "Instalando Nerd Fonts (Hack + Cascadia Code)..."
  local FONT_DIR="$HOME/.local/share/fonts"
  mkdir -p "$FONT_DIR"
  local changed=false

  # Cascadia Code
  if ! fc-list | grep -qi "CascadiaCode"; then
    local cascadia_url
    if cascadia_url=$(github_latest_url "microsoft/cascadia-code" "CascadiaCode.*\.zip"); then
      wget -q "$cascadia_url" -O "$FONT_DIR/CascadiaCode.zip"
      # FIX: extraer a subdirectorio para no mezclar con otras fuentes
      mkdir -p "$FONT_DIR/CascadiaCode"
      unzip -q -o "$FONT_DIR/CascadiaCode.zip" -d "$FONT_DIR/CascadiaCode"
      rm -f "$FONT_DIR/CascadiaCode.zip"
      changed=true
      print_ok "Cascadia Code instalada"
    fi
  else
    print_skip "Cascadia Code ya instalada"
  fi

  # Hack Nerd Font
  if ! fc-list | grep -qi "HackNerdFont\|Hack Nerd"; then
    local hack_url
    if hack_url=$(github_latest_url "ryanoasis/nerd-fonts" "Hack\.zip"); then
      wget -q "$hack_url" -O "$FONT_DIR/Hack.zip"
      # FIX: extraer a subdirectorio
      mkdir -p "$FONT_DIR/HackNerdFont"
      unzip -q -o "$FONT_DIR/Hack.zip" -d "$FONT_DIR/HackNerdFont"
      rm -f "$FONT_DIR/Hack.zip"
      changed=true
      print_ok "Hack Nerd Font instalada"
    fi
  else
    print_skip "Hack Nerd Font ya instalada"
  fi

  if [[ "$changed" == true ]]; then
    fc-cache -f "$FONT_DIR"
    print_ok "Caché de fuentes actualizado"
  fi
}

install_vscode() {
  if command -v code &>/dev/null; then
    print_skip "VS Code ya está instalado"
    return
  fi
  print_step "Instalando Visual Studio Code..."
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
  sudo install -o root -g root -m 644 /tmp/packages.microsoft.gpg /usr/share/keyrings/
  sudo sh -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] \
    https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
  sudo apt update -qq
  sudo apt install -y -qq code
  rm -f /tmp/packages.microsoft.gpg
  print_ok "VS Code instalado"
}

install_obsidian() {
  local OBSIDIAN_DIR="$HOME/AppImages"
  local OBSIDIAN_APPIMAGE="$OBSIDIAN_DIR/Obsidian.AppImage"

  if [[ -x "$OBSIDIAN_APPIMAGE" ]]; then
    print_skip "Obsidian ya está instalado"
    return
  fi
  print_step "Instalando Obsidian (AppImage)..."
  mkdir -p "$OBSIDIAN_DIR"

  local obsidian_url
  if ! obsidian_url=$(github_latest_url "obsidianmd/obsidian-releases" "AppImage"); then
    print_error "No se pudo instalar Obsidian"
    return 0  # FIX: return 0 para no matar el script con set -e
  fi

  wget -q "$obsidian_url" -O "$OBSIDIAN_APPIMAGE"
  chmod +x "$OBSIDIAN_APPIMAGE"

  local ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"
  mkdir -p "$ICON_DIR"
  wget -q "https://upload.wikimedia.org/wikipedia/commons/thumb/1/10/2023_Obsidian_logo.svg/512px-2023_Obsidian_logo.svg.png" \
    -O "$ICON_DIR/obsidian.png"

  mkdir -p ~/.local/share/applications
  cat > ~/.local/share/applications/obsidian.desktop <<EOF
[Desktop Entry]
Name=Obsidian
Comment=Markdown knowledge base
Exec=$OBSIDIAN_APPIMAGE --enable-features=UseOzonePlatform --ozone-platform=wayland
Icon=obsidian
Terminal=false
Type=Application
Categories=Office;Utility;Notes;
StartupWMClass=obsidian
EOF

  update-desktop-database ~/.local/share/applications 2>/dev/null || true
  gtk-update-icon-cache ~/.local/share/icons/hicolor 2>/dev/null || true
  print_ok "Obsidian instalado en $OBSIDIAN_APPIMAGE"
}

install_steam() {
  if command -v steam &>/dev/null; then
    print_skip "Steam ya está instalado"
    return
  fi
  print_step "Instalando Steam..."
  sudo apt install -y -qq steam
  print_ok "Steam instalado"
}

install_copyq() {
  if command -v copyq &>/dev/null; then
    print_skip "CopyQ ya está instalado"
    return
  fi
  print_step "Instalando CopyQ..."
  sudo apt install -y -qq copyq
  print_ok "CopyQ instalado"
}

install_kdeconnect() {
  if command -v kdeconnectd &>/dev/null; then
    print_skip "KDE Connect ya está instalado"
    return
  fi
  print_step "Instalando KDE Connect..."
  sudo apt install -y -qq kdeconnect
  print_ok "KDE Connect instalado"
}

install_bat() {
  if command -v bat &>/dev/null || command -v batcat &>/dev/null; then
    print_skip "bat ya está instalado"
    return
  fi
  print_step "Instalando bat..."
  sudo apt install -y -qq bat
  # FIX: crear ~/.local/bin antes del symlink
  if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(which batcat)" "$HOME/.local/bin/bat"
    print_ok "bat instalado (symlink batcat → bat)"
  else
    print_ok "bat instalado"
  fi
}

install_eza() {
  if command -v eza &>/dev/null; then
    print_skip "eza ya está instalado"
    return
  fi
  print_step "Instalando eza..."
  sudo apt install -y -qq eza 2>/dev/null || {
    if command -v cargo &>/dev/null; then
      cargo install eza
    else
      print_error "eza no disponible en repos y cargo no está instalado — omitiendo"
      return 0  # FIX: no matar el script, solo reportar
    fi
  }
  print_ok "eza instalado"
}

install_rvm_ruby() {
  if command -v rvm &>/dev/null || [[ -s "/etc/profile.d/rvm.sh" ]]; then
    print_skip "RVM ya está instalado"
    return
  fi
  print_step "Instalando RVM + Ruby..."
  sudo apt install -y -qq gnupg2

  # FIX: fallback si el keyserver falla
  gpg --keyserver hkp://keyserver.ubuntu.com:80 \
    --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB 2>/dev/null || \
  gpg --keyserver hkp://keys.openpgp.org \
    --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB 2>/dev/null || \
    print_warn "No se pudieron importar las claves GPG de RVM — continuando igual"

  sudo apt-add-repository -y ppa:rael-gc/rvm
  sudo apt update -qq
  sudo apt install -y -qq rvm
  sudo usermod -a -G rvm "$USER"
  print_ok "RVM instalado (cierra sesión para activarlo)"
}

install_nvm_node() {
  print_step "Instalando NVM + Node.js (LTS)..."
  export NVM_DIR="$HOME/.nvm"

  if [ ! -d "$NVM_DIR" ]; then
    git clone --quiet https://github.com/nvm-sh/nvm.git "$NVM_DIR"
    # FIX: usar la última tag disponible en vez de versión hardcodeada
    local nvm_latest
    nvm_latest=$(cd "$NVM_DIR" && git describe --tags --abbrev=0 2>/dev/null || echo "v0.39.7")
    cd "$NVM_DIR" && git checkout "$nvm_latest" -q && cd -
  fi

  \. "$NVM_DIR/nvm.sh"

  # FIX: grep pattern corregido — nvm ls muestra "v22.x.x" con "(lts/name)" al lado
  if nvm ls --no-colors 2>/dev/null | grep -qE "v[0-9]+\.[0-9]+\.[0-9]+ \(lts/"; then
    print_skip "Node.js LTS ya instalado"
  else
    nvm install --lts
    nvm use --lts
    print_ok "Node.js $(node -v) instalado via NVM"
  fi
}

install_docker() {
  if command -v docker &>/dev/null; then
    print_skip "Docker ya está instalado"
    return
  fi
  print_step "Instalando Docker..."
  curl -fsSL https://get.docker.com | sudo bash
  sudo usermod -aG docker "$USER"
  print_ok "Docker instalado (cierra sesión para usarlo sin sudo)"
}

install_vlc() {
  if command -v vlc &>/dev/null; then
    print_skip "VLC ya está instalado"
    return
  fi
  print_step "Instalando VLC..."
  sudo apt install -y -qq vlc
  print_ok "VLC instalado"
}

install_gimp() {
  if command -v gimp &>/dev/null; then
    print_skip "GIMP ya está instalado"
    return
  fi
  print_step "Instalando GIMP..."
  sudo apt install -y -qq gimp
  print_ok "GIMP instalado"
}

install_flameshot() {
  if command -v flameshot &>/dev/null; then
    print_skip "Flameshot ya está instalado"
    return
  fi
  print_step "Instalando Flameshot..."
  sudo apt install -y -qq flameshot
  print_ok "Flameshot instalado"
}

install_htop() {
  if command -v htop &>/dev/null; then
    print_skip "htop ya está instalado"
    return
  fi
  print_step "Instalando htop..."
  sudo apt install -y -qq htop
  print_ok "htop instalado"
}

configure_zshrc() {
  print_step "Configurando ~/.zshrc..."

  # FIX: backup si ya existe un .zshrc con contenido
  if [[ -f "$HOME/.zshrc" && -s "$HOME/.zshrc" ]]; then
    local backup="$HOME/.zshrc.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$HOME/.zshrc" "$backup"
    print_warn "Backup guardado en $backup"
  fi

  # FIX: if/fi en vez de [[ ]] && para evitar set -e cuando rvm_ruby=off
  local plugins="git zsh-syntax-highlighting zsh-autosuggestions"
  if [[ "${SELECTIONS[rvm_ruby]:-off}" == "on" ]]; then
    plugins="$plugins rails git-flow"
  fi

  cat > "$HOME/.zshrc" <<ZSHRC
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=($plugins)
source \$ZSH/oh-my-zsh.sh

# PATH
export PATH="\$HOME/.local/bin:\$HOME/.local/share/bin:\$PATH"

# Oh My Posh
if command -v oh-my-posh &>/dev/null && [ "\$TERM_PROGRAM" != "Apple_Terminal" ]; then
  eval "\$(oh-my-posh init zsh --config \$HOME/.cache/oh-my-posh/themes/clean-detailed.omp.json)"
fi

# NVM
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"

# RVM
[[ -s "/etc/profile.d/rvm.sh" ]] && source /etc/profile.d/rvm.sh

# eza
if command -v eza &>/dev/null; then
  alias ls='eza --icons --color=auto'
  alias ll='eza -la --icons --color=auto'
  alias la='eza -la --icons --color=auto --git'
  alias lt='eza --tree --icons'
fi

# bat
if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
  alias bat='batcat'
fi
ZSHRC

  print_ok "~/.zshrc configurado"
}

# ================================================
# MENÚ INTERACTIVO — Navegación con teclado
# ================================================
declare -A SELECTIONS

_menu_title() {
  case "$1" in
    base)  echo "PASO 1 / 4 — Herramientas Base" ;;
    shell) echo "PASO 2 / 4 — Terminal & Shell" ;;
    dev)   echo "PASO 3 / 4 — Desarrollo" ;;
    apps)  echo "PASO 4 / 4 — Aplicaciones" ;;
  esac
}

# FIX: _draw_menu ya no recibe parámetros muertos — solo category y cursor
_draw_menu() {
  local category="$1" cursor="$2"
  local total="${#MENU_IDS[@]}"

  clear
  print_header
  echo -e "  ${WHITE}${BOLD}$(_menu_title "$category")${RESET}\n"
  echo -e "  ${DIM}↑↓ mover  •  Space marcar  •  a todo  •  n nada  •  Enter continuar  •  q salir${RESET}\n"

  for (( i=0; i<total; i++ )); do
    local id="${MENU_IDS[$i]}"
    local label="${MENU_LABELS[$i]}"
    local checked="${SELECTIONS[$id]:-off}"

    if (( i == cursor )); then
      if [[ "$checked" == "on" ]]; then
        echo -e "  ${CYAN}${BOLD}❯ ${GREEN}[✔]${CYAN} $label${RESET}"
      else
        echo -e "  ${CYAN}${BOLD}❯ [ ] $label${RESET}"
      fi
    else
      if [[ "$checked" == "on" ]]; then
        echo -e "    ${GREEN}[✔]${RESET} $label"
      else
        echo -e "    ${DIM}[ ] $label${RESET}"
      fi
    fi
  done
  echo ""
}

MENU_IDS=()
MENU_LABELS=()

show_menu() {
  local category="$1"
  shift

  MENU_IDS=()
  MENU_LABELS=()
  for opt in "$@"; do
    MENU_IDS+=("${opt%%:*}")
    MENU_LABELS+=("${opt#*:}")
  done

  local total="${#MENU_IDS[@]}"
  local cursor=0

  tput civis 2>/dev/null || true

  while true; do
    _draw_menu "$category" "$cursor"

    local key
    IFS= read -rsn1 key

    if [[ "$key" == $'\x1b' ]]; then
      local seq1 seq2
      IFS= read -rsn1 -t 0.1 seq1 2>/dev/null || true
      IFS= read -rsn1 -t 0.1 seq2 2>/dev/null || true
      if [[ "$seq1" == '[' ]]; then
        case "$seq2" in
          'A') (( cursor > 0 ))         && (( cursor-- )) || true ;;
          'B') (( cursor < total - 1 )) && (( cursor++ )) || true ;;
        esac
      fi

    elif [[ "$key" == ' ' ]]; then
      local id="${MENU_IDS[$cursor]}"
      if [[ "${SELECTIONS[$id]:-off}" == "on" ]]; then
        SELECTIONS[$id]="off"
      else
        SELECTIONS[$id]="on"
      fi
      (( cursor < total - 1 )) && (( cursor++ )) || true

    elif [[ "$key" == 'a' || "$key" == 'A' ]]; then
      for id in "${MENU_IDS[@]}"; do SELECTIONS[$id]="on"; done

    elif [[ "$key" == 'n' || "$key" == 'N' ]]; then
      for id in "${MENU_IDS[@]}"; do SELECTIONS[$id]="off"; done

    elif [[ "$key" == '' ]]; then
      break

    elif [[ "$key" == 'q' || "$key" == 'Q' ]]; then
      tput cnorm 2>/dev/null || true
      echo -e "\n  ${YELLOW}Instalación cancelada.${RESET}\n"
      exit 0
    fi
  done

  tput cnorm 2>/dev/null || true
}

# ================================================
# RESUMEN
# ================================================
show_summary() {
  clear
  print_header
  echo -e "  ${WHITE}${BOLD}Resumen de instalación${RESET}\n"

  declare -A LABEL_MAP=(
    [base]="Actualizar sistema + paquetes esenciales"
    [eza]="eza — ls mejorado"
    [bat]="bat — cat con syntax highlighting"
    [htop]="htop — monitor de procesos"
    [zsh_ohmyzsh]="Zsh + Oh My Zsh + plugins"
    [ohmyposh]="Oh My Posh"
    [nerd_fonts]="Nerd Fonts (Hack + Cascadia Code)"
    [zshrc]="Generar ~/.zshrc preconfigurado"
    [vscode]="Visual Studio Code"
    [nvm_node]="NVM + Node.js LTS"
    [rvm_ruby]="RVM + Ruby"
    [docker]="Docker Engine"
    [obsidian]="Obsidian (AppImage + Wayland)"
    [steam]="Steam"
    [copyq]="CopyQ — gestor de portapapeles"
    [kdeconnect]="KDE Connect"
    [vlc]="VLC"
    [gimp]="GIMP"
    [flameshot]="Flameshot"
  )

  local count=0
  # FIX: mostrar en orden definido, no el aleatorio de las claves del asociativo
  local ordered=(base eza bat htop zsh_ohmyzsh ohmyposh nerd_fonts zshrc
                 vscode nvm_node rvm_ruby docker
                 obsidian steam copyq kdeconnect vlc gimp flameshot)
  for key in "${ordered[@]}"; do
    if [[ "${SELECTIONS[$key]:-off}" == "on" ]]; then
      echo -e "  ${CHECK} ${LABEL_MAP[$key]:-$key}"
      count=$(( count + 1 ))
    fi
  done

  if (( count == 0 )); then
    echo -e "  ${YELLOW}No seleccionaste nada. Saliendo...${RESET}\n"
    exit 0
  fi

  echo ""
  echo -e "  ${DIM}Se instalarán $count componentes.${RESET}\n"

  if ! confirm "¿Continuar con la instalación?" "y"; then
    echo -e "\n  ${YELLOW}Instalación cancelada.${RESET}\n"
    exit 0
  fi
}

# ================================================
# EJECUTAR INSTALACIONES
# ================================================
run_installations() {
  clear
  print_header
  print_section "Instalando..."

  require_sudo
  ensure_deps
  # FIX: solo hacer apt update aquí si NO se seleccionó install_base
  # (install_base ya lo hace internamente)
  if [[ "${SELECTIONS[base]:-off}" != "on" ]]; then
    sudo apt update -qq
  fi

  # FIX: if/fi en vez de [[ ]] && fn — evita que set -e mate el script
  #      cuando una selección es "off" (exit code 1)
  if [[ "${SELECTIONS[base]:-off}"       == "on" ]]; then install_base;       fi
  if [[ "${SELECTIONS[zsh_ohmyzsh]:-off}" == "on" ]]; then install_zsh_ohmyzsh; fi
  if [[ "${SELECTIONS[ohmyposh]:-off}"   == "on" ]]; then install_ohmyposh;  fi
  if [[ "${SELECTIONS[nerd_fonts]:-off}" == "on" ]]; then install_nerd_fonts; fi
  if [[ "${SELECTIONS[eza]:-off}"        == "on" ]]; then install_eza;        fi
  if [[ "${SELECTIONS[bat]:-off}"        == "on" ]]; then install_bat;        fi
  if [[ "${SELECTIONS[htop]:-off}"       == "on" ]]; then install_htop;       fi
  if [[ "${SELECTIONS[zshrc]:-off}"      == "on" ]]; then configure_zshrc;    fi
  if [[ "${SELECTIONS[vscode]:-off}"     == "on" ]]; then install_vscode;     fi
  if [[ "${SELECTIONS[nvm_node]:-off}"   == "on" ]]; then install_nvm_node;   fi
  if [[ "${SELECTIONS[rvm_ruby]:-off}"   == "on" ]]; then install_rvm_ruby;   fi
  if [[ "${SELECTIONS[docker]:-off}"     == "on" ]]; then install_docker;     fi
  if [[ "${SELECTIONS[obsidian]:-off}"   == "on" ]]; then install_obsidian;   fi
  if [[ "${SELECTIONS[steam]:-off}"      == "on" ]]; then install_steam;      fi
  if [[ "${SELECTIONS[copyq]:-off}"      == "on" ]]; then install_copyq;      fi
  if [[ "${SELECTIONS[kdeconnect]:-off}" == "on" ]]; then install_kdeconnect; fi
  if [[ "${SELECTIONS[vlc]:-off}"        == "on" ]]; then install_vlc;        fi
  if [[ "${SELECTIONS[gimp]:-off}"       == "on" ]]; then install_gimp;       fi
  if [[ "${SELECTIONS[flameshot]:-off}"  == "on" ]]; then install_flameshot;  fi
}

# ================================================
# FLUJO PRINCIPAL
# ================================================
clear
print_header
echo -e "  ${DIM}Bienvenido al instalador interactivo para Pop!_OS / Ubuntu.${RESET}"
echo -e "  ${DIM}Navega con ${RESET}${BOLD}↑ ↓${RESET}${DIM}, marca con ${RESET}${BOLD}Space${RESET}${DIM}, confirma con ${RESET}${BOLD}Enter${RESET}${DIM}.${RESET}\n"
sleep 2

show_menu "base" \
  "base:Actualizar sistema + paquetes esenciales (recomendado)" \
  "eza:eza — ls con esteroides e íconos" \
  "bat:bat — cat con syntax highlighting" \
  "htop:htop — monitor de procesos interactivo"

show_menu "shell" \
  "zsh_ohmyzsh:Zsh + Oh My Zsh + plugins (syntax, autosuggestions)" \
  "ohmyposh:Oh My Posh (prompt bonito para Zsh)" \
  "nerd_fonts:Nerd Fonts — Hack + Cascadia Code" \
  "zshrc:Generar ~/.zshrc preconfigurado"

show_menu "dev" \
  "vscode:Visual Studio Code" \
  "nvm_node:NVM + Node.js LTS" \
  "rvm_ruby:RVM + Ruby (vía PPA rael-gc)" \
  "docker:Docker Engine"

show_menu "apps" \
  "obsidian:Obsidian (AppImage, con soporte Wayland)" \
  "steam:Steam (gaming)" \
  "copyq:CopyQ — gestor de portapapeles avanzado" \
  "kdeconnect:KDE Connect — sincronización con Android" \
  "vlc:VLC — reproductor multimedia" \
  "gimp:GIMP — editor de imágenes" \
  "flameshot:Flameshot — capturas de pantalla"

show_summary
run_installations

echo ""
print_section "¡Todo listo!"
echo -e "  ${CHECK} ${GREEN}${BOLD}Instalación completada.${RESET}\n"
echo -e "  ${YELLOW}Próximos pasos:${RESET}"
echo -e "  ${DIM}• Cambia a zsh:${RESET}                    ${CYAN}exec zsh${RESET}"
echo -e "  ${DIM}• Si instalaste RVM o Docker:${RESET}       cierra y vuelve a abrir sesión"
echo -e "  ${DIM}• Para explorar temas de Oh My Posh:${RESET} ${CYAN}ls ~/.cache/oh-my-posh/themes/${RESET}"
echo ""
