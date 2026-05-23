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
# HELPERS
# ================================================
print_header() {
  clear
  echo -e "${BLUE}${BOLD}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║        🚀  Setup Wizard — Pop!_OS            ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo -e "${RESET}"
}

print_section() {
  echo -e "\n${MAGENTA}${BOLD}── $1 ──────────────────────────────────────${RESET}\n"
}

print_step() {
  echo -e "  ${ARROW} $1"
}

print_ok() {
  echo -e "  ${CHECK} ${GREEN}$1${RESET}"
}

print_skip() {
  echo -e "  ${DIM}⊘  $1 — omitido${RESET}"
}

print_error() {
  echo -e "  ${CROSS} ${RED}$1${RESET}"
}

confirm() {
  # $1 = mensaje, $2 = default (y/n)
  local default="${2:-n}"
  local prompt
  if [[ "$default" == "y" ]]; then
    prompt="[Y/n]"
  else
    prompt="[y/N]"
  fi
  echo -ne "  ${YELLOW}?${RESET} $1 ${DIM}$prompt${RESET} "
  read -r answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    echo -e "\n  ${YELLOW}Se necesita contraseña de sudo para continuar.${RESET}"
    sudo -v
  fi
  # Mantener sudo vivo en background
  while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done &
  SUDO_KEEPER_PID=$!
}

cleanup() {
  [[ -n "$SUDO_KEEPER_PID" ]] && kill "$SUDO_KEEPER_PID" 2>/dev/null || true
}
trap cleanup EXIT

# ================================================
# VERIFICACIÓN DE DEPENDENCIAS DEL WIZARD
# ================================================
ensure_deps() {
  for dep in curl wget git gpg unzip; do
    if ! command -v "$dep" &>/dev/null; then
      sudo apt-get install -y "$dep" -qq
    fi
  done
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
    echo -e "  ${DIM}Oh My Zsh ya instalado, omitiendo...${RESET}"
  fi

  local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  git clone --quiet https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null || true
  git clone --quiet https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null || true

  print_ok "Zsh + Oh My Zsh instalados"
}

install_ohmyposh() {
  print_step "Instalando Oh My Posh..."
  mkdir -p "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
  curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
  print_ok "Oh My Posh instalado"
}

install_nerd_fonts() {
  print_step "Instalando Nerd Fonts (Hack + Cascadia Code)..."
  mkdir -p ~/.local/share/fonts
  local FONT_DIR="$HOME/.local/share/fonts"

  # Cascadia Code
  local cascadia_url
  cascadia_url=$(curl -s https://api.github.com/repos/microsoft/cascadia-code/releases/latest \
    | grep browser_download_url | grep '.zip' | grep 'CascadiaCode' | cut -d '"' -f 4 | head -n 1)
  if [[ -n "$cascadia_url" ]]; then
    wget -q "$cascadia_url" -O "$FONT_DIR/CascadiaCode.zip"
    unzip -q -o "$FONT_DIR/CascadiaCode.zip" -d "$FONT_DIR"
    rm -f "$FONT_DIR/CascadiaCode.zip"
    print_ok "Cascadia Code instalada"
  else
    print_error "No se pudo obtener Cascadia Code"
  fi

  # Hack Nerd Font
  local hack_url
  hack_url=$(curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest \
    | grep browser_download_url | grep 'Hack.zip' | cut -d '"' -f 4 | head -n 1)
  if [[ -n "$hack_url" ]]; then
    wget -q "$hack_url" -O "$FONT_DIR/Hack.zip"
    unzip -q -o "$FONT_DIR/Hack.zip" -d "$FONT_DIR"
    rm -f "$FONT_DIR/Hack.zip"
    print_ok "Hack Nerd Font instalada"
  else
    print_error "No se pudo obtener Hack Nerd Font"
  fi

  fc-cache -f ~/.local/share/fonts
  print_ok "Caché de fuentes actualizado"
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
  print_step "Instalando Obsidian (AppImage)..."
  local OBSIDIAN_DIR="$HOME/AppImages"
  local OBSIDIAN_APPIMAGE="$OBSIDIAN_DIR/Obsidian.AppImage"
  mkdir -p "$OBSIDIAN_DIR"

  local obsidian_url
  obsidian_url=$(curl -s https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest \
    | grep browser_download_url | grep AppImage | cut -d '"' -f 4 | head -n 1)

  if [[ -z "$obsidian_url" ]]; then
    print_error "No se pudo obtener URL de Obsidian"
    return 1
  fi

  wget -q "$obsidian_url" -O "$OBSIDIAN_APPIMAGE"
  chmod +x "$OBSIDIAN_APPIMAGE"

  # Ícono
  local ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"
  mkdir -p "$ICON_DIR"
  wget -q "https://upload.wikimedia.org/wikipedia/commons/thumb/1/10/2023_Obsidian_logo.svg/512px-2023_Obsidian_logo.svg.png" \
    -O "$ICON_DIR/obsidian.png"

  # .desktop
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
  print_step "Instalando CopyQ (gestor de portapapeles)..."
  sudo apt install -y -qq copyq
  print_ok "CopyQ instalado"
}

install_kdeconnect() {
  if command -v kdeconnectd &>/dev/null; then
    print_skip "KDE Connect ya está instalado"
    return
  fi
  print_step "Instalando KDE Connect..."
  sudo apt update -qq && sudo apt install -y -qq kdeconnect
  print_ok "KDE Connect instalado"
}

install_bat() {
  if command -v bat &>/dev/null || command -v batcat &>/dev/null; then
    print_skip "bat ya está instalado"
    return
  fi
  print_step "Instalando bat (cat mejorado)..."
  sudo apt install -y -qq bat
  if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
    mkdir -p ~/.local/bin
    ln -sf "$(which batcat)" ~/.local/bin/bat
    print_ok "bat instalado (alias apuntando a batcat)"
  else
    print_ok "bat instalado"
  fi
}

install_eza() {
  if command -v eza &>/dev/null; then
    print_skip "eza ya está instalado"
    return
  fi
  print_step "Instalando eza (ls mejorado)..."
  sudo apt install -y -qq eza 2>/dev/null || {
    # fallback: instalar desde cargo si no está en el repo
    if command -v cargo &>/dev/null; then
      cargo install eza
    else
      print_error "eza no disponible en repos y cargo no está instalado"
      return 1
    fi
  }
  print_ok "eza instalado"
}

install_rvm_ruby() {
  print_step "Instalando RVM + Ruby..."
  sudo apt install -y -qq gnupg2

  gpg --keyserver hkp://keyserver.ubuntu.com:80 \
    --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB 2>/dev/null || true

  sudo apt-add-repository -y ppa:rael-gc/rvm
  sudo apt update -qq
  sudo apt install -y -qq rvm
  sudo usermod -a -G rvm "$USER"
  print_ok "RVM instalado (reinicia sesión para usarlo)"
}

install_nvm_node() {
  print_step "Instalando NVM + Node.js (LTS)..."
  export NVM_DIR="$HOME/.nvm"
  if [ ! -d "$NVM_DIR" ]; then
    git clone --quiet https://github.com/nvm-sh/nvm.git "$NVM_DIR"
    cd "$NVM_DIR" && git checkout v0.39.7 -q && cd -
  fi
  # Cargar NVM en la sesión actual
  # shellcheck source=/dev/null
  \. "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm use --lts
  print_ok "Node.js $(node -v) instalado via NVM"
}

install_docker() {
  if command -v docker &>/dev/null; then
    print_skip "Docker ya está instalado"
    return
  fi
  print_step "Instalando Docker..."
  curl -fsSL https://get.docker.com | sudo bash
  sudo usermod -aG docker "$USER"
  print_ok "Docker instalado (reinicia sesión para usarlo sin sudo)"
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
  print_step "Instalando Flameshot (capturas de pantalla)..."
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
  print_step "Escribiendo ~/.zshrc..."
  cat > ~/.zshrc <<'ZSHRC'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git rails zsh-syntax-highlighting zsh-autosuggestions git-flow)
source $ZSH/oh-my-zsh.sh

# PATH
export PATH="$HOME/.local/bin:$HOME/.local/share/bin:$PATH"

# Oh My Posh
if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
  eval "$(oh-my-posh init zsh --config $HOME/.cache/oh-my-posh/themes/clean-detailed.omp.json)"
fi

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# RVM
[[ -s "/etc/profile.d/rvm.sh" ]] && source /etc/profile.d/rvm.sh

# eza aliases
alias ls='eza --icons --color=auto'
alias ll='eza -la --icons --color=auto'
alias la='eza -la --icons --color=auto --git'
alias lt='eza --tree --icons'

# bat alias
command -v batcat &>/dev/null && alias bat='batcat'
ZSHRC
  print_ok "~/.zshrc configurado"
}

# ================================================
# MENÚ INTERACTIVO — Navegación con teclado
# ================================================

declare -A SELECTIONS

# Títulos por categoría
_menu_title() {
  case "$1" in
    base)  echo "PASO 1 / 4 — Herramientas Base" ;;
    shell) echo "PASO 2 / 4 — Terminal & Shell" ;;
    dev)   echo "PASO 3 / 4 — Desarrollo" ;;
    apps)  echo "PASO 4 / 4 — Aplicaciones" ;;
  esac
}

# Dibuja el menú sin llamar a clear (lo hace el loop)
_draw_menu() {
  local category="$1"
  local cursor="$2"
  shift 2
  local -a ids=("$@")

  echo -e "${BLUE}${BOLD}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║        🚀  Setup Wizard — Pop!_OS            ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo -e "${RESET}"

  echo -e "  ${WHITE}${BOLD}$(_menu_title "$category")${RESET}\n"
  echo -e "  ${DIM}↑ ↓  moverse   •   Space  marcar/desmarcar   •   a  todo   •   n  nada   •   Enter  continuar${RESET}\n"

  local total="${#MENU_IDS[@]}"
  for (( i=0; i<total; i++ )); do
    local id="${MENU_IDS[$i]}"
    local label="${MENU_LABELS[$i]}"
    local checked="${SELECTIONS[$id]:-off}"

    if (( i == cursor )); then
      # Fila seleccionada (cursor encima)
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

# Arrays globales compartidos entre funciones del menú
MENU_IDS=()
MENU_LABELS=()

show_menu() {
  local category="$1"
  shift
  local -a options=("$@")

  # Parsear ids y labels
  MENU_IDS=()
  MENU_LABELS=()
  for opt in "${options[@]}"; do
    MENU_IDS+=("${opt%%:*}")
    MENU_LABELS+=("${opt#*:}")
  done

  local total="${#MENU_IDS[@]}"
  local cursor=0

  # Ocultar cursor para evitar parpadeo
  tput civis 2>/dev/null || true

  while true; do
    clear
    _draw_menu "$category" "$cursor" "${MENU_IDS[@]}"

    # Leer una tecla (sin eco, sin buffering)
    local key
    IFS= read -rsn1 key

    if [[ "$key" == $'\x1b' ]]; then
      # Secuencia de escape (teclas especiales)
      local seq1 seq2
      IFS= read -rsn1 -t 0.1 seq1 2>/dev/null || true
      IFS= read -rsn1 -t 0.1 seq2 2>/dev/null || true
      if [[ "$seq1" == '[' ]]; then
        case "$seq2" in
          'A') (( cursor > 0 ))         && (( cursor-- )) || true ;;  # Flecha arriba
          'B') (( cursor < total - 1 )) && (( cursor++ )) || true ;;  # Flecha abajo
        esac
      fi

    elif [[ "$key" == ' ' ]]; then
      # Espacio: toggle del item bajo el cursor
      local id="${MENU_IDS[$cursor]}"
      if [[ "${SELECTIONS[$id]:-off}" == "on" ]]; then
        SELECTIONS[$id]="off"
      else
        SELECTIONS[$id]="on"
      fi
      # Avanzar cursor automáticamente si no es el último
      (( cursor < total - 1 )) && (( cursor++ )) || true

    elif [[ "$key" == 'a' || "$key" == 'A' ]]; then
      # Seleccionar todo
      for id in "${MENU_IDS[@]}"; do SELECTIONS[$id]="on"; done

    elif [[ "$key" == 'n' || "$key" == 'N' ]]; then
      # Deseleccionar todo
      for id in "${MENU_IDS[@]}"; do SELECTIONS[$id]="off"; done

    elif [[ "$key" == '' ]]; then
      # Enter: salir del menú
      break

    elif [[ "$key" == 'q' || "$key" == 'Q' ]]; then
      tput cnorm 2>/dev/null || true
      echo -e "\n  ${YELLOW}Instalación cancelada.${RESET}\n"
      exit 0
    fi
  done

  # Restaurar cursor
  tput cnorm 2>/dev/null || true
}

# ================================================
# PANTALLA DE RESUMEN
# ================================================

show_summary() {
  clear
  echo -e "${BLUE}${BOLD}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║        🚀  Setup Wizard — Pop!_OS            ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo -e "${RESET}"
  echo -e "  ${WHITE}${BOLD}Resumen de instalación${RESET}\n"

  # Mapa id → label legible
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
  for key in "${!SELECTIONS[@]}"; do
    if [[ "${SELECTIONS[$key]}" == "on" ]]; then
      local label="${LABEL_MAP[$key]:-$key}"
      echo -e "  ${CHECK} $label"
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
# EJECUTAR INSTALACIONES SELECCIONADAS
# ================================================

run_installations() {
  print_header
  print_section "Instalando..."

  # Siempre
  require_sudo
  ensure_deps
  sudo apt update -qq

  # Base
  [[ "${SELECTIONS[base]}" == "on" ]]        && install_base
  [[ "${SELECTIONS[zsh_ohmyzsh]}" == "on" ]] && install_zsh_ohmyzsh
  [[ "${SELECTIONS[ohmyposh]}" == "on" ]]    && install_ohmyposh
  [[ "${SELECTIONS[nerd_fonts]}" == "on" ]]  && install_nerd_fonts
  [[ "${SELECTIONS[eza]}" == "on" ]]         && install_eza
  [[ "${SELECTIONS[bat]}" == "on" ]]         && install_bat
  [[ "${SELECTIONS[htop]}" == "on" ]]        && install_htop
  [[ "${SELECTIONS[zshrc]}" == "on" ]]       && configure_zshrc

  # Dev
  [[ "${SELECTIONS[vscode]}" == "on" ]]      && install_vscode
  [[ "${SELECTIONS[nvm_node]}" == "on" ]]    && install_nvm_node
  [[ "${SELECTIONS[rvm_ruby]}" == "on" ]]    && install_rvm_ruby
  [[ "${SELECTIONS[docker]}" == "on" ]]      && install_docker

  # Apps
  [[ "${SELECTIONS[obsidian]}" == "on" ]]    && install_obsidian
  [[ "${SELECTIONS[steam]}" == "on" ]]       && install_steam
  [[ "${SELECTIONS[copyq]}" == "on" ]]       && install_copyq
  [[ "${SELECTIONS[kdeconnect]}" == "on" ]]  && install_kdeconnect
  [[ "${SELECTIONS[vlc]}" == "on" ]]         && install_vlc
  [[ "${SELECTIONS[gimp]}" == "on" ]]        && install_gimp
  [[ "${SELECTIONS[flameshot]}" == "on" ]]   && install_flameshot
}

# ================================================
# FLUJO PRINCIPAL
# ================================================

clear
echo -e "${BLUE}${BOLD}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║        🚀  Setup Wizard — Pop!_OS            ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  ${DIM}Bienvenido al instalador interactivo para Pop!_OS / Ubuntu.${RESET}"
echo -e "  ${DIM}Navega con ${RESET}${BOLD}↑ ↓${RESET}${DIM}, marca con ${RESET}${BOLD}Space${RESET}${DIM}, confirma con ${RESET}${BOLD}Enter${RESET}${DIM}.${RESET}\n"
sleep 2

# — Paso 1: Herramientas base
show_menu "base" \
  "base:Actualizar sistema + paquetes esenciales (recomendado)" \
  "eza:eza — ls con esteroides e íconos" \
  "bat:bat — cat con syntax highlighting" \
  "htop:htop — monitor de procesos interactivo"

# — Paso 2: Shell
show_menu "shell" \
  "zsh_ohmyzsh:Zsh + Oh My Zsh + plugins (syntax, autosuggestions)" \
  "ohmyposh:Oh My Posh (prompt bonito para Zsh)" \
  "nerd_fonts:Nerd Fonts — Hack + Cascadia Code" \
  "zshrc:Generar ~/.zshrc preconfigurado"

# — Paso 3: Desarrollo
show_menu "dev" \
  "vscode:Visual Studio Code" \
  "nvm_node:NVM + Node.js LTS" \
  "rvm_ruby:RVM + Ruby (vía PPA rael-gc)" \
  "docker:Docker Engine"

# — Paso 4: Aplicaciones
show_menu "apps" \
  "obsidian:Obsidian (AppImage, con soporte Wayland)" \
  "steam:Steam (gaming)" \
  "copyq:CopyQ — gestor de portapapeles avanzado" \
  "kdeconnect:KDE Connect — sincronización con Android" \
  "vlc:VLC — reproductor multimedia" \
  "gimp:GIMP — editor de imágenes" \
  "flameshot:Flameshot — capturas de pantalla"

# — Resumen y confirmación
show_summary

# — Instalar
run_installations

# — Final
echo ""
print_section "¡Todo listo!"
echo -e "  ${CHECK} ${GREEN}${BOLD}Instalación completada.${RESET}"
echo ""
echo -e "  ${YELLOW}Próximos pasos:${RESET}"
echo -e "  ${DIM}• Reinicia la terminal o ejecuta:${RESET} ${CYAN}exec zsh${RESET}"
echo -e "  ${DIM}• Si instalaste RVM o Docker, cierra y vuelve a abrir sesión.${RESET}"
echo -e "  ${DIM}• Para cambiar el tema de Oh My Posh:${RESET} ${CYAN}oh-my-posh font install${RESET}"
echo ""
