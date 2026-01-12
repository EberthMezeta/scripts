#!/bin/bash
set -e

# ===============================
# Capturar sudo al inicio
# ===============================
sudo -v
# Mantener sudo activo durante la ejecución del script
while true; do
  sudo -n true
  sleep 60
  kill -0 "$$" || exit
done 2>/dev/null &

# ===============================
# Actualizar sistema y herramientas esenciales
# ===============================
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget build-essential zsh unzip software-properties-common \
  apt-transport-https ca-certificates gnupg lsb-release fonts-powerline eza

# ===============================
# Instalar Zsh si no está presente
# ===============================
if ! command -v zsh &>/dev/null; then
  sudo apt install -y zsh
fi

# ===============================
# Instalar Oh My Zsh
# ===============================
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  chsh -s $(which zsh) $USER
fi

# Plugins
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting || true
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions || true

# ===============================
# Instalar Oh My Posh
# ===============================
# Asegurarse de que ~/.local/bin esté en PATH
export PATH="$HOME/.local/bin:$PATH"
curl -s https://ohmyposh.dev/install.sh | bash

# ===============================
# Instalar Nerd Fonts (Hack y Cascadia)
# ===============================
mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts
# Cascadia
latest_url=$(curl -s https://api.github.com/repos/microsoft/cascadia-code/releases/latest |
  grep browser_download_url |
  grep '.zip' |
  grep 'CascadiaCode' |
  cut -d '"' -f 4 |
  head -n 1)

# Descargar y extraer
wget -q "$latest_url" -O CascadiaCode.zip
unzip -q CascadiaCode.zip
rm CascadiaCode.zip
# Hack
hack_latest_url=$(curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest |
  grep browser_download_url |
  grep 'Hack.zip' |
  cut -d '"' -f 4 |
  head -n 1)

if [ -z "$hack_latest_url" ]; then
  echo "No se pudo obtener la URL de la última versión de Hack Nerd Font"
  exit 1
fi

wget -q "$hack_latest_url" -O Hack.zip
unzip -q Hack.zip
rm Hack.zip

fc-cache -fv
cd -

# ===============================
# Instalar RVM y Ruby
# ===============================
sudo apt install -y gnupg2
gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 \
  7D2BAF1CF37B13E2069D6956105BD0E739499BDB
sudo apt update
sudo apt install -y software-properties-common

# Agregar PPA de RVM
sudo apt-add-repository -y ppa:rael-gc/rvm
sudo apt update

# Instalar RVM
sudo apt install -y rvm

# Añadir tu usuario al grupo rvm
sudo usermod -a -G rvm $USER

# ===============================
# Instalar NVM y Node
# ===============================
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
  git clone https://github.com/nvm-sh/nvm.git "$NVM_DIR"
  cd "$NVM_DIR" && git checkout v0.39.7
  cd -
fi
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# ===============================
# Instalar Visual Studio Code
# ===============================
if ! command -v code &>/dev/null; then
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor >packages.microsoft.gpg
  sudo install -o root -g root -m 644 packages.microsoft.gpg /usr/share/keyrings/
  sudo sh -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
  sudo apt update
  sudo apt install -y code
fi

# ===============================
# Instalar Obsidian (AppImage + Wayland)
# ===============================
OBSIDIAN_DIR="$HOME/AppImages"
OBSIDIAN_APPIMAGE="$OBSIDIAN_DIR/Obsidian.AppImage"
mkdir -p "$OBSIDIAN_DIR"

obsidian_url=$(curl -s https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest |
  grep browser_download_url | grep AppImage | cut -d '"' -f 4 | head -n 1)

wget -q "$obsidian_url" -O "$OBSIDIAN_APPIMAGE"
chmod +x "$OBSIDIAN_APPIMAGE"

# ===============================
# Icono de Obsidian
# ===============================
ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"
mkdir -p "$ICON_DIR"

wget -q https://upload.wikimedia.org/wikipedia/commons/thumb/1/10/2023_Obsidian_logo.svg/512px-2023_Obsidian_logo.svg.png \
  -O "$ICON_DIR/obsidian.png"

# ===============================
# .desktop de Obsidian
# ===============================
mkdir -p ~/.local/share/applications

cat >~/.local/share/applications/obsidian.desktop <<EOF
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

update-desktop-database ~/.local/share/applications || true
gtk-update-icon-cache ~/.local/share/icons/hicolor || true

# ===============================
# Instalar Steam (Pop!_OS trae multiverse habilitado)
# ===============================
command -v steam &>/dev/null || sudo apt install -y steam

# ===============================
# Instalar CopyQ (Pop!_OS)
# ===============================
command -v copyq &>/dev/null || sudo apt install -y copyq

# ===============================
# Configurar .zshrc
# ===============================
cat >~/.zshrc <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git rails zsh-syntax-highlighting zsh-autosuggestions git-flow)
source $ZSH/oh-my-zsh.sh

# PATH para Oh My Posh
export PATH="$HOME/.local/bin:$PATH"

# Oh My Posh
if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
  eval "$(oh-my-posh init zsh --config $HOME/.cache/oh-my-posh/themes/clean-detailed.omp.json)"
fi

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# RVM
source /etc/profile.d/rvm.sh

# eza aliases
alias ls='eza --icons --color=auto'
alias ll='eza -la --icons --color=auto'
EOF

echo "=================================="
echo "¡Setup completado! Cambia a zsh con 'zsh' o reinicia tu terminal."
echo "=================================="
