#!/usr/bin/env bash
#
# install-neovim.sh — instala Neovim (tarball oficial) + una configuración
#                     modular con perfiles por stack: una BASE compartida de
#                     plugins agnósticos + overlays dedicados por lenguaje.
#
# Coloca:
#   $PREFIX/bin/nvim                          (symlink al tarball en $PREFIX/opt)
#   $PREFIX/bin/nvim-setup                    (copia de este script: --update / --config-only)
#   $PREFIX/bin/{lazygit,lazydocker,rg,fd,tree-sitter} (si faltaban; binarios sin sudo)
#   ~/.config/nvim-shared/                    BASE compartida (plugins agnósticos al stack)
#   ~/.config/nvim/                           perfil "default" (generalista) = base
#   ~/.config/nvim-ruby/                      perfil Ruby/Rails  = base + dedicados
#   ~/.config/nvim-rust/                      perfil Rust        = base + esqueleto
#   $PREFIX/share/doc/neovim-setup/README.md  documentación de la estructura
#   bloque de aliases en ~/.zshrc             (nvim-ruby, nvr, nvim-rust, nvp)
#
# Perfiles = variable de entorno NVIM_APPNAME:
#   nvim                 -> perfil default
#   nvim-ruby  /  nvr    -> NVIM_APPNAME=nvim-ruby nvim
#   nvim-rust           -> NVIM_APPNAME=nvim-rust nvim
#   nvp                  -> autodetecta (Gemfile -> ruby, Cargo.toml -> rust)
#
# Uso:
#   ./install-neovim.sh [--prefix DIR] [--config-only] [--no-sync] [--update] [--uninstall]
#
#   --prefix DIR    raíz de instalación                  (def: ~/.local)
#   --config-only   solo regenera ~/.config/nvim* + sync (no toca binarios)
#   --no-sync       no instala plugins/LSP en headless   (se hará al abrir nvim)
#   --update        re-descarga nvim/lazygit/lazydocker + sync
#   --uninstall     quita binarios, perfiles y el bloque de ~/.zshrc
#
# Antes de tocar nada valida los prerequisitos del sistema (curl, git, tar,
# unzip, python3, make + compilador C). Si falta alguno OBLIGATORIO imprime el
# comando `apt install` correspondiente y aborta sin instalar. Para los
# recomendados (node/npm, portapapeles, ctags) avisa y pregunta si continuar.
#
set -uo pipefail

# ----------------------------------------------------------------- opciones
PREFIX="$HOME/.local"
DO_BIN=1 DO_CONFIG=1 DO_SYNC=1 UPDATE=0 ACTION=install

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)                PREFIX="$2"; shift ;;
    --config-only)           DO_BIN=0 ;;
    --no-sync|--skip-sync)   DO_SYNC=0 ;;
    --update)                UPDATE=1; DO_CONFIG=0 ;;
    --uninstall)             ACTION=uninstall ;;
    -h|--help)               sed -n '2,37p' "$0"; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done
[ "$UPDATE" = 1 ] && DO_BIN=1

# ----------------------------------------------------------------- infra
BIN="$PREFIX/bin"
OPT="$PREFIX/opt"
DOC="$PREFIX/share/doc/neovim-setup"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
SHARED="$CFG/nvim-shared"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
TMP="$(mktemp -d)"
LOG="$DATA/nvim-setup.log"
SELF="$(readlink -f "$0")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$BIN" "$OPT" "$DOC" "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
echo "===== install-neovim.sh ($ACTION) $(date -Is) ====="

log()  { printf '  \033[36m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1;35m▶ %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
wf()   { mkdir -p "$(dirname "$1")"; cat > "$1"; log "escrito ${1/#$HOME/\~}"; }

case "$(uname -m)" in
  x86_64|amd64)  ARCH=x86_64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "Arquitectura no soportada: $(uname -m)"; exit 1 ;;
esac

# node/npm en PATH para los instaladores headless de Mason (nvm no siempre exporta)
# nvm.sh no tolera 'set -u' (aborta a medio cargar), así que se desactiva al cargarlo
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  set +u; . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true; set -u
fi
# respaldo: si aun así no hay node, usar la versión más nueva instalada por nvm
if ! command -v node >/dev/null 2>&1 && [ -d "$HOME/.nvm/versions/node" ]; then
  _nvm_node="$(ls -d "$HOME"/.nvm/versions/node/v*/bin 2>/dev/null | sort -V | tail -n1)"
  [ -n "$_nvm_node" ] && export PATH="$_nvm_node:$PATH"
fi
if command -v node >/dev/null 2>&1; then
  NODE_BIN="$(cd "$(dirname "$(command -v node)")" && pwd)"
  export PATH="$NODE_BIN:$PATH"
fi

# ----------------------------------------------------------------- prerequisitos
check_prereqs() {
  step "Prerequisitos del sistema"

  local missing=() pkgs=()
  add_missing() { missing+=("$1"); pkgs+=("$2"); }

  have curl    || add_missing curl    curl
  have git     || add_missing git     git
  have tar     || add_missing tar     tar
  have unzip   || add_missing unzip   unzip
  have python3 || add_missing python3 python3
  have make    || add_missing make    build-essential
  if ! have cc && ! have gcc && ! have clang; then
    add_missing "compilador C (cc/gcc)" build-essential
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    local uniq
    uniq="$(printf '%s\n' "${pkgs[@]}" | awk '!seen[$0]++' | tr '\n' ' ')"
    echo
    echo "  ✗ Faltan herramientas OBLIGATORIAS: ${missing[*]}"
    echo
    echo "  Instálalas y vuelve a ejecutar este script:"
    echo
    echo "      sudo apt update && sudo apt install -y ${uniq% }"
    echo
    exit 1
  fi
  log "obligatorios OK  (curl git tar unzip python3 make + compilador C)"

  # -------------------------------------------------- recomendados (no abortan)
  local warn=0

  if ! have node; then
    warn=1
    log "⚠  node/npm ausente (tampoco vía nvm)"
    log "     lo usan LSP de js/ts/json/yaml/css/html, markdown-preview y live-server"
    log "     apt:  sudo apt install -y nodejs npm       (o instala nvm)"
  fi

  if [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
    have wl-copy || { warn=1
      log "⚠  Wayland sin wl-clipboard: el portapapeles del sistema (registro +) no funcionará"
      log "     apt:  sudo apt install -y wl-clipboard"; }
  elif ! have xclip && ! have xsel; then
    warn=1
    log "⚠  sin xclip/xsel: el portapapeles del sistema (registro +) no funcionará"
    log "     apt:  sudo apt install -y xclip"
  fi

  have ctags || { warn=1
    log "⚠  ctags ausente: gutentags no podrá generar tags para 'ir a definición'"
    log "     apt:  sudo apt install -y universal-ctags"; }

  log "ℹ  para los iconos necesitas una Nerd Font en la terminal: https://www.nerdfonts.com"

  if [ "$warn" = 1 ]; then
    printf '\n  Hay recomendados ausentes; la instalación seguirá con funciones limitadas.\n'
    printf '  ¿Continuar ahora? [Y/n] '
    read -r ans || ans=""
    case "${ans:-}" in
      n|N|no|NO) echo "  Abortado. Instala lo anterior y reintenta."; exit 1 ;;
    esac
  fi
}

# ----------------------------------------------------------------- desinstalar
uninstall_all() {
  step "Desinstalando Neovim + perfiles"
  rm -fv "$BIN/nvim" "$BIN/nvim-setup"
  rm -rfv "$OPT"/nvim-linux-*
  # bloque de ~/.zshrc entre marcadores
  local rc="$HOME/.zshrc"
  if [ -f "$rc" ] && grep -qF '# >>> nvim-setup (perfiles) >>>' "$rc"; then
    sed -i '/# >>> nvim-setup (perfiles) >>>/,/# <<< nvim-setup (perfiles) <<</d' "$rc"
    log "bloque de aliases eliminado de ~/.zshrc"
  fi
  printf '  ¿Borrar también los perfiles y sus plugins (~/.config/nvim*, %s/nvim*)? [y/N] ' "$DATA"
  read -r ans || ans=""
  if [ "$ans" = y ] || [ "$ans" = Y ]; then
    for d in nvim nvim-ruby nvim-rust nvim-shared; do
      [ -f "$CFG/$d/.nvim-setup" ] && rm -rfv "$CFG/$d"
      rm -rfv "$DATA/$d" "${XDG_STATE_HOME:-$HOME/.local/state}/$d" "$HOME/.cache/$d"
    done
  else
    log "conservados los directorios de config y datos"
  fi
  rm -rfv "$DOC"
  log "lazygit / lazydocker / rg / fd NO se tocan (pueden usarlos otras herramientas)"
  echo "Hecho."
}

if [ "$ACTION" = uninstall ]; then uninstall_all; exit 0; fi

check_prereqs

# ----------------------------------------------------------------- binarios
install_neovim() {
  step "Neovim (tarball oficial, sin sudo)"
  local url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${ARCH}.tar.gz"
  log "descargando $url"
  curl -fL --retry 3 -o "$TMP/nvim.tgz" "$url" \
    || { echo "FALLO: no pude descargar Neovim"; exit 1; }
  rm -rf "$OPT"/nvim-linux-*
  tar -C "$OPT" -xzf "$TMP/nvim.tgz"
  local nb; nb="$(find "$OPT" -maxdepth 3 -type f -path '*/bin/nvim' -print -quit)"
  [ -n "$nb" ] || { echo "no encontré el binario nvim tras extraer"; exit 1; }
  ln -sf "$nb" "$BIN/nvim"
  local vl; vl="$("$BIN/nvim" --version 2>/dev/null)"; vl="${vl%%$'\n'*}"
  log "$vl"
  case "$vl" in
    *v0.9.*|*v0.10.*) log "⚠  versión < 0.11: parte del LSP usará el modo clásico" ;;
  esac
}

gh_tag() { curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["tag_name"])'; }

install_gh_tool() { # <bin> <repo> <asset_prefix>
  local name="$1" repo="$2" pref="$3" tag ver aarch
  step "$name"
  if ! tag="$(gh_tag "$repo" 2>/dev/null)"; then
    log "⚠  no pude consultar $repo (rate-limit?). Omitido."; return 0
  fi
  ver="${tag#v}"
  case "$ARCH" in x86_64) aarch=x86_64 ;; arm64) aarch=arm64 ;; esac
  # lazygit usa 'linux' en minúsculas desde ~v0.5x; lazydocker sigue con 'Linux'
  local os ok=0
  for os in Linux linux; do
    curl -fsL --retry 3 -o "$TMP/$name.tgz" \
      "https://github.com/$repo/releases/download/$tag/${pref}_${ver}_${os}_${aarch}.tar.gz" \
      && { ok=1; break; }
  done
  [ "$ok" = 1 ] || { log "⚠  fallo la descarga de $name"; return 0; }
  tar -C "$BIN" -xzf "$TMP/$name.tgz" "$name"
  chmod +x "$BIN/$name"
  log "$name $ver -> $BIN/$name"
}

install_ripgrep() {
  step "ripgrep (binario, sin sudo)"
  local tag ver a
  if ! tag="$(gh_tag BurntSushi/ripgrep 2>/dev/null)"; then
    log "⚠  no pude consultar ripgrep. Instala:  sudo apt install ripgrep"; return 0
  fi
  ver="${tag#v}"
  case "$ARCH" in
    x86_64) a="x86_64-unknown-linux-musl" ;;
    arm64)  a="aarch64-unknown-linux-gnu" ;;
  esac
  curl -fL --retry 3 -o "$TMP/rg.tgz" \
    "https://github.com/BurntSushi/ripgrep/releases/download/${tag}/ripgrep-${ver}-${a}.tar.gz" \
    || { log "⚠  fallo la descarga de ripgrep"; return 0; }
  local d; d="$(mktemp -d "$TMP/rg.XXXX")"; tar -C "$d" -xzf "$TMP/rg.tgz"
  local rb; rb="$(find "$d" -type f -name rg -print -quit)"
  [ -n "$rb" ] && install -m755 "$rb" "$BIN/rg" && log "ripgrep $ver -> $BIN/rg"
}

install_tree_sitter_cli() {
  # nvim-treesitter (rama main) compila los parsers con tree-sitter-cli >= 0.26.1.
  # apt trae 0.20.x, así que se baja el binario oficial.
  local cur
  cur="$(tree-sitter --version 2>/dev/null | awk '{print $2}')"
  if [ -n "$cur" ] && [ "$(printf '%s\n' 0.26.1 "$cur" | sort -V | head -n1)" = 0.26.1 ]; then
    log "tree-sitter $cur ok"; return 0
  fi
  local a; case "$ARCH" in x86_64) a=x64 ;; arm64) a=arm64 ;; esac
  curl -fL --retry 3 -o "$TMP/ts.gz" \
    "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-${a}.gz" \
    || { log "⚠  fallo la descarga de tree-sitter-cli (los parsers no se podrán compilar)"; return 0; }
  gunzip -c "$TMP/ts.gz" > "$BIN/tree-sitter" && chmod +x "$BIN/tree-sitter"
  log "$("$BIN/tree-sitter" --version) -> $BIN/tree-sitter"
}

install_extras() {
  step "Dependencias externas"
  install_tree_sitter_cli
  if ! have fd; then
    if have fdfind; then ln -sf "$(command -v fdfind)" "$BIN/fd"; log "fd -> fdfind (symlink)"; fi
  else log "fd ok"; fi
  have rg || install_ripgrep
  have rg && log "ripgrep ok"
  local apt_pkgs=()
  have ctags || apt_pkgs+=(universal-ctags)
  [ "${XDG_SESSION_TYPE:-}" = wayland ] && ! have wl-copy && apt_pkgs+=(wl-clipboard)
  if [ "${#apt_pkgs[@]}" -gt 0 ]; then
    if sudo -n true 2>/dev/null; then
      sudo apt-get update -qq && sudo apt-get install -y "${apt_pkgs[@]}" && log "${apt_pkgs[*]} instalado(s)"
    else
      log "⚠  ejecuta a mano:  sudo apt install ${apt_pkgs[*]}"
    fi
  else log "ctags / portapapeles ok"; fi
  have node && log "node $(node -v) ok" \
    || log "⚠  node/npm no en PATH (nvm): necesario para algunos LSP y markdown-preview"
}

# ----------------------------------------------------------------- config
backup_existing() {
  for d in nvim nvim-ruby nvim-rust nvim-shared; do
    if [ -e "$CFG/$d" ] && [ ! -L "$CFG/$d" ] && [ ! -f "$CFG/$d/.nvim-setup" ]; then
      mv "$CFG/$d" "$CFG/$d.bak.$(date +%Y%m%d%H%M%S)"
      log "backup: ~/.config/$d -> .bak"
    fi
  done
}

write_base() {
  step "BASE compartida  (~/.config/nvim-shared)"
  mkdir -p "$SHARED"; : > "$SHARED/.nvim-setup"

  wf "$SHARED/lua/base/options.lua" <<'EOF'
local o = vim.opt
vim.g.mapleader = " "
vim.g.maplocalleader = " "
o.number = true
o.relativenumber = true
o.mouse = "a"
o.clipboard = "unnamedplus"
o.breakindent = true
o.undofile = true
o.ignorecase = true
o.smartcase = true
o.signcolumn = "yes"
o.updatetime = 250
o.timeoutlen = 400
o.splitright = true
o.splitbelow = true
o.list = true
o.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
o.inccommand = "split"
o.cursorline = true
o.scrolloff = 8
o.termguicolors = true
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.softtabstop = 2
o.smartindent = true
o.wrap = false
o.confirm = true
pcall(function() o.winborder = "rounded" end) -- 0.11+

-- proveedores remotos: ningún plugin de esta config los usa (todo es Lua);
-- desactivarlos acelera el arranque y limpia :checkhealth
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0
EOF

  wf "$SHARED/lua/base/keymaps.lua" <<'EOF'
local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<cr>")
map("i", "jk", "<Esc>")
map("i", "kj", "<Esc>")

-- moverse entre splits sin la 'w' (cómodo en teclado 60%)
map("n", "<C-h>", "<C-w>h"); map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k"); map("n", "<C-l>", "<C-w>l")
map("n", "<leader>-", "<cmd>split<cr>",  { desc = "Split horizontal" })
map("n", "<leader>\\", "<cmd>vsplit<cr>", { desc = "Split vertical" })

-- buffers
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Cerrar buffer" })
map("n", "<leader>bo", "<cmd>%bd|e#|bd#<cr>", { desc = "Cerrar los demás buffers" })

-- guardar / salir
map("n", "<leader>w", "<cmd>write<cr>", { desc = "Guardar" })
map("n", "<leader>W", "<cmd>wall<cr>",  { desc = "Guardar todo" })
map("n", "<leader>q", "<cmd>quit<cr>",  { desc = "Cerrar ventana" })
map("n", "<leader>Q", "<cmd>qall<cr>",  { desc = "Salir de Neovim" })

-- edición
map("v", "J", ":m '>+1<cr>gv=gv")
map("v", "K", ":m '<-2<cr>gv=gv")
map("v", "<", "<gv"); map("v", ">", ">gv")
map("x", "<leader>p", [["_dP]], { desc = "Pegar sin pisar el registro" })
map({ "n", "v" }, "<leader>y", [["+y]], { desc = "Copiar al portapapeles del sistema" })
map("n", "<C-d>", "<C-d>zz"); map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv"); map("n", "N", "Nzzzv")

map("n", "<leader>xx", vim.diagnostic.setloclist, { desc = "Diagnósticos (loclist)" })
EOF

  wf "$SHARED/lua/base/autocmds.lua" <<'EOF'
local aug = vim.api.nvim_create_augroup("base-autocmds", { clear = true })
local hl = vim.hl or vim.highlight

vim.api.nvim_create_autocmd("TextYankPost", {
  group = aug, callback = function() pcall(hl.on_yank) end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
  group = aug, callback = function(ev)
    if vim.bo[ev.buf].filetype == "gitcommit" then return end
    local m = vim.api.nvim_buf_get_mark(ev.buf, '"')
    if m[1] > 0 and m[1] <= vim.api.nvim_buf_line_count(ev.buf) then
      pcall(vim.api.nvim_win_set_cursor, 0, m)
    end
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = aug,
  pattern = { "help", "qf", "man", "lspinfo", "checkhealth", "aerial", "dbout" },
  callback = function(ev)
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = ev.buf, silent = true })
  end,
})
EOF

  wf "$SHARED/lua/base/init.lua" <<'EOF'
local M = {}

function M.setup(profile)
  vim.g.nvim_profile = profile or "default"
  -- overlay del perfil (si existe lua/profile/extras.lua): tablas y funciones
  -- que la BASE mezcla en sus specs. Determinista, sin depender del merge de lazy.
  local ok, extras = pcall(require, "profile.extras")
  _G.PROFILE = (ok and type(extras) == "table") and extras or {}
  require("base.options")
  require("base.keymaps")
  require("base.autocmds")

  local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
  if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.fn.system({ "git", "clone", "--filter=blob:none",
      "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
  end
  vim.opt.rtp:prepend(lazypath)

  local specs = { { import = "base.plugins" } }
  local pdir = vim.fn.stdpath("config") .. "/lua/profile/plugins"
  if (vim.uv or vim.loop).fs_stat(pdir) then
    specs[#specs + 1] = { import = "profile.plugins" }
  end

  require("lazy").setup(specs, {
    lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json",
    change_detection = { notify = false },
    rocks = { enabled = false }, -- ningún plugin necesita luarocks
    install = { colorscheme = { "onedark_vivid", "habamax" } },
    ui = { border = "rounded" },
    performance = { rtp = { disabled_plugins = { "gzip", "tarPlugin", "zipPlugin", "netrwPlugin" } } },
  })
end

return M
EOF

  wf "$SHARED/lua/base/plugins/ui.lua" <<'EOF'
return {
  { "olimorris/onedarkpro.nvim", priority = 1000,
    config = function()
      require("onedarkpro").setup({ options = { cursorline = true } })
      vim.cmd.colorscheme("onedark_vivid")
    end },

  { "nvim-tree/nvim-web-devicons", lazy = true },

  { "nvim-lualine/lualine.nvim", event = "VeryLazy",
    opts = { options = { theme = "auto", globalstatus = true,
      section_separators = "", component_separators = "|" } } },

  { "akinsho/bufferline.nvim", event = "VeryLazy",
    opts = { options = { diagnostics = "nvim_lsp", always_show_bufferline = false,
      offsets = { { filetype = "neo-tree", text = "Explorer", separator = true } } } },
    keys = {
      { "<S-l>", "<cmd>BufferLineCycleNext<cr>", desc = "Buffer siguiente" },
      { "<S-h>", "<cmd>BufferLineCyclePrev<cr>", desc = "Buffer anterior" },
      { "<leader>bp", "<cmd>BufferLinePickClose<cr>", desc = "Cerrar buffer (pick)" },
    } },

  { "folke/which-key.nvim", event = "VeryLazy", opts = {} },

  { "lukas-reineke/indent-blankline.nvim", main = "ibl", event = "BufReadPost",
    opts = { indent = { char = "│" }, scope = { enabled = false } } },

  { "folke/todo-comments.nvim", event = "BufReadPost",
    dependencies = "nvim-lua/plenary.nvim", opts = { signs = false } },
}
EOF

  wf "$SHARED/lua/base/plugins/editor.lua" <<'EOF'
return {
  { "nvim-lua/plenary.nvim", lazy = true },

  -- Explorador de archivos
  { "nvim-neo-tree/neo-tree.nvim", branch = "v3.x",
    dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim", "nvim-tree/nvim-web-devicons" },
    cmd = "Neotree",
    keys = { { "<leader>e", "<cmd>Neotree toggle<cr>", desc = "Explorador" } },
    opts = { filesystem = { follow_current_file = { enabled = true }, use_libuv_file_watcher = true,
      filtered_items = { visible = true, hide_dotfiles = false, hide_gitignored = false } } } },

  -- Fuzzy finder
  { "nvim-telescope/telescope.nvim", version = "*",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
      "nvim-telescope/telescope-ui-select.nvim",
    },
    cmd = "Telescope",
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>",   desc = "Archivos" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>",    desc = "Grep proyecto" },
      { "<leader>fw", "<cmd>Telescope grep_string<cr>",  desc = "Grep palabra" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>",      desc = "Buffers" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>",     desc = "Recientes" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>",    desc = "Ayuda" },
      { "<leader>fd", "<cmd>Telescope diagnostics<cr>",  desc = "Diagnósticos" },
      { "<leader>fs", "<cmd>Telescope lsp_document_symbols<cr>", desc = "Símbolos" },
      { "<leader>fk", "<cmd>Telescope keymaps<cr>",      desc = "Atajos" },
      { "<leader><leader>", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
    },
    config = function()
      local t = require("telescope")
      t.setup({
        defaults = { path_display = { "truncate" }, sorting_strategy = "ascending",
          layout_config = { prompt_position = "top" } },
        extensions = { ["ui-select"] = { require("telescope.themes").get_dropdown() } },
      })
      pcall(t.load_extension, "fzf")
      pcall(t.load_extension, "ui-select")
    end },

  -- mini: autopairs + surround (prefijo gs, para no chocar con flash 's') + text objects
  { "echasnovski/mini.nvim", version = false, event = "VeryLazy",
    config = function()
      require("mini.pairs").setup()
      require("mini.ai").setup({ n_lines = 500 })
      require("mini.surround").setup({ mappings = {
        add = "gsa", delete = "gsd", find = "gsf", find_left = "gsF",
        highlight = "gsh", replace = "gsr", update_n_lines = "gsn",
      } })
    end },

  -- resalta y salta (%) entre def/if/do … end
  { "andymass/vim-matchup", event = "BufReadPost",
    init = function() vim.g.matchup_matchparen_offscreen = { method = "popup" } end },

  -- saltos rápidos (reemplaza la necesidad de flechas / Home / End)
  { "folke/flash.nvim", event = "VeryLazy", opts = {},
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
    } },

  -- ctags automáticos = 'ir a definición' universal (Ctrl-] / g])
  { "ludovicchabant/vim-gutentags", event = { "BufReadPost", "BufNewFile" },
    init = function()
      vim.g.gutentags_cache_dir = vim.fn.stdpath("cache") .. "/gutentags"
      vim.g.gutentags_generate_on_new = 1
      vim.g.gutentags_generate_on_missing = 1
      vim.g.gutentags_generate_on_write = 1
      vim.g.gutentags_ctags_exclude = {
        "node_modules", ".git", "tmp", "log", "public", "vendor", "dist",
        "build", "target", "coverage", "*.min.js", "*.map",
      }
    end },

  -- outline de símbolos (LSP / treesitter / ctags)
  { "stevearc/aerial.nvim", opts = { backends = { "lsp", "treesitter", "markdown" } },
    keys = { { "<leader>o", "<cmd>AerialToggle<cr>", desc = "Outline" } } },

  -- bookmarks persistentes con nota
  { "tomasky/bookmarks.nvim", event = "VeryLazy",
    opts = { save_file = vim.fn.expand("$HOME/.bookmarks") },
    keys = {
      { "<leader>mm", function() require("bookmarks").bookmark_toggle() end, desc = "Bookmark toggle" },
      { "<leader>mi", function() require("bookmarks").bookmark_ann() end,    desc = "Bookmark + nota" },
      { "<leader>ml", function() require("bookmarks").bookmark_list() end,   desc = "Listar bookmarks" },
      { "<leader>mx", function() require("bookmarks").bookmark_clean() end,  desc = "Limpiar bookmarks" },
    } },

  -- marcas nativas (ma / `a) con signos en el margen
  { "chentoast/marks.nvim", event = "BufReadPost", opts = {} },
}
EOF

  wf "$SHARED/lua/base/plugins/treesitter.lua" <<'EOF'
-- nvim-treesitter rama 'main' (la 'master' está congelada y no soporta nvim 0.12).
-- Requiere tree-sitter-cli >= 0.26.1 (lo instala el script en ~/.local/bin).
local ensure = {
  "lua", "vim", "vimdoc", "query", "bash", "regex",
  "markdown", "markdown_inline", "json", "yaml", "toml",
  "html", "css", "scss", "javascript", "typescript", "tsx",
  "sql", "dockerfile", "gitcommit", "gitignore", "git_rebase", "diff",
}
vim.list_extend(ensure, (_G.PROFILE or {}).treesitter or {}) -- parsers del perfil
_G.TS_ENSURE = ensure -- lo usa el sync headless de install-neovim.sh

return {
  { "nvim-treesitter/nvim-treesitter", branch = "main", lazy = false, build = ":TSUpdate",
    config = function()
      local ts = require("nvim-treesitter")
      -- en headless el script instala y espera; con UI se instala en segundo plano
      if #vim.api.nvim_list_uis() > 0 then ts.install(ensure) end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("base-treesitter", { clear = true }),
        callback = function(ev)
          local lang = vim.treesitter.language.get_lang(ev.match)
          if not (lang and pcall(vim.treesitter.start, ev.buf, lang)) then return end
          vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end },

  -- cierra def/if/do … con 'end' (Ruby, Lua, Bash…); ya no depende de los módulos de master
  { "RRethy/nvim-treesitter-endwise", event = "InsertEnter" },
}
EOF

  wf "$SHARED/lua/base/plugins/lsp.lua" <<'EOF'
return {
  { "mason-org/mason.nvim", build = ":MasonUpdate", cmd = "Mason",
    opts = {
      ui = { border = "rounded" },
      -- un solo Mason para todos los perfiles: se instala una vez y se reutiliza
      install_root_dir = vim.fn.expand("~/.local/share/nvim/mason"),
    } },
  { "WhoIsSethDaniel/mason-tool-installer.nvim", dependencies = "mason-org/mason.nvim" },

  { "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "mason-org/mason.nvim",
      "mason-org/mason-lspconfig.nvim",
      "WhoIsSethDaniel/mason-tool-installer.nvim",
      "saghen/blink.cmp",
    },
    opts = {
      servers = {
        lua_ls = { settings = { Lua = {
          diagnostics = { globals = { "vim" } },
          workspace = { checkThirdParty = false }, telemetry = { enable = false },
        } } },
        bashls = {},
        jsonls = {},
        yamlls = {},
        taplo = {},
        marksman = {},
        dockerls = {},
        docker_compose_language_service = {},
        html = {},
        cssls = {},
        ts_ls = {},
        eslint = {},
      },
      -- herramientas (formateadores/linters) que instala Mason además de los servers
      tools = { "stylua", "shfmt", "prettierd", "hadolint", "shellcheck", "markdownlint-cli2" },
    },
    config = function(_, opts)
      local caps = require("blink.cmp").get_lsp_capabilities()

      -- servidores LSP que añada el perfil (lua/profile/extras.lua -> lsp_servers)
      opts.servers = vim.tbl_deep_extend("force", opts.servers, (_G.PROFILE or {}).lsp_servers or {})

      local ensure = vim.tbl_keys(opts.servers)
      vim.list_extend(ensure, opts.tools or {})
      require("mason-tool-installer").setup({ ensure_installed = ensure, run_on_start = true })
      pcall(function() require("mason-lspconfig").setup({ automatic_enable = false }) end)

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("base-lsp-attach", { clear = true }),
        callback = function(ev)
          local m = function(k, fn, d)
            vim.keymap.set("n", k, fn, { buffer = ev.buf, desc = "LSP: " .. d })
          end
          m("gd", "<cmd>Telescope lsp_definitions<cr>", "definición")
          m("gr", "<cmd>Telescope lsp_references<cr>", "referencias")
          m("gI", "<cmd>Telescope lsp_implementations<cr>", "implementaciones")
          m("gy", "<cmd>Telescope lsp_type_definitions<cr>", "tipo")
          m("K", vim.lsp.buf.hover, "hover")
          m("<leader>rn", vim.lsp.buf.rename, "renombrar")
          m("<leader>ca", vim.lsp.buf.code_action, "code action")
          m("<leader>cd", vim.diagnostic.open_float, "ver diagnóstico")
          m("[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, "diag. anterior")
          m("]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, "diag. siguiente")
        end,
      })

      vim.diagnostic.config({
        virtual_text = false, severity_sort = true,
        float = { border = "rounded", source = true },
        signs = { text = { [vim.diagnostic.severity.ERROR] = "",
          [vim.diagnostic.severity.WARN] = "", [vim.diagnostic.severity.INFO] = "",
          [vim.diagnostic.severity.HINT] = "" } },
      })

      if vim.fn.has("nvim-0.11") == 1 then
        for name, cfg in pairs(opts.servers) do
          cfg.capabilities = vim.tbl_deep_extend("force", {}, caps, cfg.capabilities or {})
          vim.lsp.config(name, cfg)
          vim.lsp.enable(name)
        end
      else
        local lsp = require("lspconfig")
        for name, cfg in pairs(opts.servers) do
          cfg.capabilities = vim.tbl_deep_extend("force", {}, caps, cfg.capabilities or {})
          if lsp[name] then lsp[name].setup(cfg) end
        end
      end
    end },

  -- diagnósticos inline en la línea (tipo Error Lens)
  { "rachartier/tiny-inline-diagnostic.nvim", event = "LspAttach",
    opts = { preset = "modern" } },
}
EOF

  wf "$SHARED/lua/base/plugins/completion.lua" <<'EOF'
return {
  { "saghen/blink.cmp", version = "*", event = "InsertEnter",
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = {
      keymap = {
        preset = "default",
        ["<CR>"] = { "accept", "fallback" },
        ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
        ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
      },
      appearance = { nerd_font_variant = "mono" },
      sources = { default = { "lsp", "path", "snippets", "buffer" } },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
        ghost_text = { enabled = true },
      },
      signature = { enabled = true },
    } },
}
EOF

  wf "$SHARED/lua/base/plugins/git.lua" <<'EOF'
return {
  { "lewis6991/gitsigns.nvim", event = { "BufReadPre", "BufNewFile" },
    opts = {
      on_attach = function(buf)
        local gs = require("gitsigns")
        local m = function(mode, k, fn, d)
          vim.keymap.set(mode, k, fn, { buffer = buf, desc = d })
        end
        m("n", "]h", function() gs.nav_hunk("next") end, "Hunk siguiente")
        m("n", "[h", function() gs.nav_hunk("prev") end, "Hunk anterior")
        m("n", "<leader>hs", gs.stage_hunk,   "Stage hunk")
        m("n", "<leader>hr", gs.reset_hunk,   "Reset hunk")
        m("n", "<leader>hS", gs.stage_buffer, "Stage buffer")
        m("n", "<leader>hp", gs.preview_hunk, "Preview hunk")
        m("n", "<leader>hb", function() gs.blame_line({ full = true }) end, "Blame línea")
        m("n", "<leader>hd", gs.diffthis,     "Diff archivo")
      end,
    } },

  { "f-person/git-blame.nvim", event = "BufReadPost",
    opts = { enabled = false, message_template = "  <author> • <date> • <summary>",
      date_format = "%Y-%m-%d" },
    keys = { { "<leader>gb", "<cmd>GitBlameToggle<cr>", desc = "Blame inline (toggle)" } } },

  { "sindrets/diffview.nvim", cmd = { "DiffviewOpen", "DiffviewFileHistory" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>",            desc = "Diff working tree" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>",   desc = "Historial del archivo" },
      { "<leader>gH", "<cmd>DiffviewFileHistory<cr>",     desc = "Historial del repo" },
    } },

  { "tpope/vim-fugitive",
    cmd = { "Git", "G", "Gdiffsplit", "Gvdiffsplit", "Gread", "Gwrite", "Gclog" },
    keys = { { "<leader>gs", "<cmd>Git<cr>", desc = "Git status (fugitive)" } } },

  { "rbong/vim-flog", dependencies = "tpope/vim-fugitive", cmd = { "Flog", "Flogsplit" },
    keys = { { "<leader>gl", "<cmd>Flog<cr>", desc = "Git log (grafo)" } } },
}
EOF

  wf "$SHARED/lua/base/plugins/format-lint.lua" <<'EOF'
local P = _G.PROFILE or {}
local prettier = { "prettierd", "prettier", stop_after_first = true }

return {
  { "stevearc/conform.nvim", event = "BufWritePre", cmd = "ConformInfo",
    opts = {
      formatters_by_ft = vim.tbl_extend("force", {
        lua = { "stylua" },
        sh = { "shfmt" },
        json = prettier, jsonc = prettier, yaml = prettier,
        html = prettier, css = prettier, scss = prettier, markdown = prettier,
        javascript = prettier, typescript = prettier, typescriptreact = prettier,
      }, P.formatters_by_ft or {}),            -- formateadores del perfil
      formatters = P.formatters or {},         -- overrides de comando (ej. bundle exec)
      -- formato al guardar en todo… menos Ruby/ERB (ahí, manual con <leader>cf)
      format_on_save = function(bufnr)
        local ft = vim.bo[bufnr].filetype
        if ft == "ruby" or ft == "eruby" then return nil end
        return { timeout_ms = 1500, lsp_format = "fallback" }
      end,
    },
    keys = { { "<leader>cf", function()
      require("conform").format({ async = true, lsp_format = "fallback" })
    end, mode = { "n", "v" }, desc = "Formatear" } } },

  { "mfussenegger/nvim-lint", event = { "BufReadPost", "BufWritePost", "InsertLeave" },
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = vim.tbl_extend("force", {
        dockerfile = { "hadolint" }, sh = { "shellcheck" }, markdown = { "markdownlint-cli2" },
      }, P.linters_by_ft or {})               -- linters del perfil
      if type(P.on_lint_setup) == "function" then pcall(P.on_lint_setup, lint) end
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
        group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
        callback = function()
          if vim.bo.buftype == "" then lint.try_lint() end
        end,
      })
    end },
}
EOF

  wf "$SHARED/lua/base/plugins/dap.lua" <<'EOF'
return {
  { "mfussenegger/nvim-dap",
    dependencies = {
      { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
      { "theHamsta/nvim-dap-virtual-text", opts = {} },
    },
    keys = {
      { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Breakpoint" },
      { "<leader>dc", function() require("dap").continue() end,          desc = "Continuar / iniciar" },
      { "<leader>di", function() require("dap").step_into() end,         desc = "Step into" },
      { "<leader>do", function() require("dap").step_over() end,         desc = "Step over" },
      { "<leader>dO", function() require("dap").step_out() end,          desc = "Step out" },
      { "<leader>dr", function() require("dap").repl.toggle() end,       desc = "REPL" },
      { "<leader>du", function() require("dapui").toggle() end,          desc = "DAP UI" },
      { "<leader>dt", function() require("dap").terminate() end,         desc = "Terminar" },
    },
    config = function()
      local dap, dapui = require("dap"), require("dapui")
      dapui.setup()
      dap.listeners.before.attach.dapui_config = dapui.open
      dap.listeners.before.launch.dapui_config = dapui.open
      dap.listeners.before.event_terminated.dapui_config = dapui.close
      dap.listeners.before.event_exited.dapui_config = dapui.close
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
      vim.fn.sign_define("DapStopped",    { text = "▶", texthl = "DiagnosticWarn" })
    end },
}
EOF

  wf "$SHARED/lua/base/plugins/tools.lua" <<'EOF'
return {
  -- Terminal flotante + LazyGit + LazyDocker (usan los binarios del sistema)
  { "akinsho/toggleterm.nvim", version = "*",
    opts = { open_mapping = [[<c-\>]], direction = "float",
      float_opts = { border = "curved" }, shade_terminals = false },
    keys = {
      { [[<c-\>]], desc = "Terminal flotante" },
      { "<leader>gg", function()
          local T = require("toggleterm.terminal").Terminal
          _G.__lg = _G.__lg or T:new({ cmd = "lazygit", direction = "float", hidden = true,
            float_opts = { border = "curved" } })
          _G.__lg:toggle()
        end, desc = "LazyGit" },
      { "<leader>ld", function()
          local T = require("toggleterm.terminal").Terminal
          _G.__ld = _G.__ld or T:new({ cmd = "lazydocker", direction = "float", hidden = true,
            float_opts = { border = "curved" } })
          _G.__ld:toggle()
        end, desc = "LazyDocker (contenedores)" },
    } },

  -- Base de datos (tipo database-client de VS Code)
  { "kristijanhusak/vim-dadbod-ui",
    dependencies = {
      { "tpope/vim-dadbod", lazy = true },
      { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" }, lazy = true },
    },
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
    init = function()
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_save_location = vim.fn.expand("~/.local/share/db_ui")
    end,
    keys = { { "<leader>D", "<cmd>DBUIToggle<cr>", desc = "DB UI" } } },

  -- Cliente HTTP (.http / .rest) — tipo Thunder Client / Bruno
  { "mistweaverco/kulala.nvim", ft = { "http", "rest" },
    opts = { global_keymaps = false },
    keys = { { "<leader>rr", function() require("kulala").run() end,
      ft = { "http", "rest" }, desc = "Ejecutar request HTTP" } } },

  -- Markdown: render inline + preview en navegador (mermaid incluido)
  { "MeanderingProgrammer/render-markdown.nvim", ft = "markdown",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts = {} },
  { "iamcco/markdown-preview.nvim", ft = "markdown",
    build = "cd app && npm install",
    init = function() vim.g.mkdp_filetypes = { "markdown" } end,
    keys = { { "<leader>cp", "<cmd>MarkdownPreviewToggle<cr>", ft = "markdown",
      desc = "Markdown preview" } } },

  -- Live server para HTML estático (tipo Live Server de VS Code)
  { "barrett-ruth/live-server.nvim", build = "npm add -g live-server",
    cmd = { "LiveServerStart", "LiveServerStop" } },
}
EOF

  wf "$SHARED/README.md" <<'EOF'
# Config Neovim modular — base + perfiles

## Estructura
    ~/.config/nvim-shared/     BASE compartida (este directorio). No se lanza sola.
      lua/base/options.lua     opciones de vim
      lua/base/keymaps.lua     atajos que no dependen de plugins
      lua/base/autocmds.lua    autocomandos
      lua/base/init.lua        M.setup(perfil): carga base + arranca lazy.nvim
      lua/base/plugins/*.lua   plugins AGNÓSTICOS al stack (una spec por archivo)

    ~/.config/nvim/            perfil "default" (generalista) = solo base
    ~/.config/nvim-ruby/       perfil Ruby/Rails  = base + overlay ruby
    ~/.config/nvim-rust/       perfil Rust        = base + overlay rust

Cada perfil tiene su propio conjunto de plugins, lockfile y estado
(`~/.local/share/nvim-<perfil>/`), porque se selecciona con la variable
`NVIM_APPNAME`. La BASE (código Lua) es la misma para todos vía runtimepath.

## Cómo un perfil extiende la base (dos vías)
1. `lua/profile/extras.lua`  -> tabla que la BASE mezcla en SUS plugins:
       treesitter        = { ... }            parsers extra
       formatters_by_ft  = { ft = { ... } }   conform
       formatters        = { name = { ... } } overrides de comando
       linters_by_ft     = { ft = { ... } }   nvim-lint
       on_lint_setup     = function(lint) ... end
       lsp_servers       = { name = { ... } } servidores LSP extra
   La BASE lo lee como `_G.PROFILE` (cargado en base/init.lua ANTES de lazy).
2. `lua/profile/plugins/*.lua` -> specs de plugins NUEVOS e independientes
   (p.ej. vim-rails, rustaceanvim). Una spec por archivo, `return { ... }`.

## Lanzar
    nvim               -> perfil default
    nvim-ruby / nvr    -> NVIM_APPNAME=nvim-ruby nvim
    nvim-rust          -> NVIM_APPNAME=nvim-rust nvim
    nvp               -> autodetecta por Gemfile / Cargo.toml

## Añadir un perfil nuevo (ej. "web")
    mkdir -p ~/.config/nvim-web/lua/profile/plugins
    cat > ~/.config/nvim-web/init.lua <<'LUA'
    vim.opt.runtimepath:prepend(vim.fn.expand("~/.config/nvim-shared"))
    require("base").setup("web")
    LUA
    # crea ~/.config/nvim-web/lua/profile/plugins/web.lua con tus specs
    echo "alias nvim-web='NVIM_APPNAME=nvim-web nvim'" >> ~/.zshrc

Las specs de perfil pueden AMPLIAR las de la base (mismo repo, lazy.nvim
hace merge de `opts`). Ej: sumar parsers de treesitter o formateadores.

## Mantenimiento
    :Lazy         gestionar/actualizar plugins del perfil actual
    :Mason        instalar/quitar servidores LSP, formateadores, linters
    :checkhealth  diagnóstico
    nvim-setup --config-only   regenerar estos archivos (pisa cambios locales)
    nvim-setup --update        actualizar binarios nvim/lazygit/lazydocker
    install-neovim.sh --uninstall   desinstalar todo
EOF
}

write_profile_default() {
  step "Perfil default  (~/.config/nvim)"
  mkdir -p "$CFG/nvim"; : > "$CFG/nvim/.nvim-setup"
  wf "$CFG/nvim/init.lua" <<'EOF'
-- Perfil: default (generalista). Base compartida en ~/.config/nvim-shared
vim.opt.runtimepath:prepend(vim.fn.expand("~/.config/nvim-shared"))
require("base").setup("default")
EOF
}

write_profile_ruby() {
  step "Perfil Ruby/Rails  (~/.config/nvim-ruby)"
  mkdir -p "$CFG/nvim-ruby"; : > "$CFG/nvim-ruby/.nvim-setup"
  wf "$CFG/nvim-ruby/init.lua" <<'EOF'
-- Perfil: ruby (Rails 4.2 / Ruby 2.7.8). Base + dedicados.
vim.opt.runtimepath:prepend(vim.fn.expand("~/.config/nvim-shared"))
require("base").setup("ruby")
EOF
  # overlay: la BASE lo mezcla en treesitter / conform / nvim-lint
  wf "$CFG/nvim-ruby/lua/profile/extras.lua" <<'EOF'
-- Ajustes que la BASE inyecta en sus propios plugins para el perfil Ruby.
return {
  treesitter = { "ruby", "embedded_template" },        -- parsers extra
  formatters_by_ft = { ruby = { "rubocop" } },
  -- rubocop desde el bundle del proyecto (gemset RVM 2.7.8), no del PATH global
  formatters = { rubocop = { command = "bundle", prepend_args = { "exec", "rubocop" } } },
  linters_by_ft = { ruby = { "rubocop" } },
  on_lint_setup = function(lint)
    local rc = lint.linters.rubocop
    rc.cmd = "bundle"
    rc.args = vim.list_extend({ "exec", "rubocop" }, rc.args)
  end,
  -- Sin solargraph a propósito (Ruby 2.7 + Rails 4.2): navegación por ctags
  -- (gutentags, en la base) con Ctrl-] / g]. Para activarlo algún día:
  --   gem "solargraph", "~> 0.49"  y aquí:
  --   lsp_servers = { solargraph = { cmd = { "bundle","exec","solargraph","stdio" } } },
}
EOF

  wf "$CFG/nvim-ruby/lua/profile/plugins/ruby.lua" <<'EOF'
-- Plugins DEDICADOS a Ruby/Rails (independientes; se suman a la base).
return {
  -- Navegación Rails + DSL: :A (alternar), :Emodel, :Eview, gf en render "shared/x"
  { "tpope/vim-rails", ft = { "ruby", "eruby", "haml", "slim" } },
  { "tpope/vim-bundler", ft = { "ruby", "eruby" }, cmd = { "Bundle", "Bopen" } },
  { "tpope/vim-rake", ft = "ruby" },
  { "vim-ruby/vim-ruby", ft = { "ruby", "eruby" } },
  { "slim-template/vim-slim", ft = "slim" },

  -- Debug con rdbg (necesita la gem 'debug' en el Gemfile del proyecto)
  { "suketa/nvim-dap-ruby", dependencies = "mfussenegger/nvim-dap",
    config = function() require("dap-ruby").setup() end },
}
EOF
}

write_profile_rust() {
  step "Perfil Rust  (~/.config/nvim-rust)  [esqueleto]"
  mkdir -p "$CFG/nvim-rust"; : > "$CFG/nvim-rust/.nvim-setup"
  wf "$CFG/nvim-rust/init.lua" <<'EOF'
-- Perfil: rust. Base + dedicados.
vim.opt.runtimepath:prepend(vim.fn.expand("~/.config/nvim-shared"))
require("base").setup("rust")
EOF
  wf "$CFG/nvim-rust/lua/profile/extras.lua" <<'EOF'
return {
  treesitter = { "rust", "ron" },
  formatters_by_ft = { rust = { "rustfmt" } },
}
EOF

  wf "$CFG/nvim-rust/lua/profile/plugins/rust.lua" <<'EOF'
-- Plugins DEDICADOS a Rust. Requiere toolchain:
--   rustup component add rust-analyzer && rustup component add rustfmt clippy
return {
  { "mrcjkb/rustaceanvim", version = "^5", ft = "rust" },
  { "saecki/crates.nvim", event = { "BufRead Cargo.toml" }, opts = {} },
}
EOF
}

write_aliases() {
  step "Aliases de perfiles en ~/.zshrc"
  local rc="$HOME/.zshrc" mark="# >>> nvim-setup (perfiles) >>>"
  [ -f "$rc" ] || touch "$rc"
  if grep -qF "$mark" "$rc"; then log "ya presente, no toco ~/.zshrc"; return 0; fi
  cat >> "$rc" <<'EOF'

# >>> nvim-setup (perfiles) >>>
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
alias v='nvim'
alias vi='nvim'
alias nvim-ruby='NVIM_APPNAME=nvim-ruby nvim'
alias nvr='NVIM_APPNAME=nvim-ruby nvim'
alias nvim-rust='NVIM_APPNAME=nvim-rust nvim'
nvp() {  # abre el perfil adecuado según el proyecto
  if [ -f Gemfile ]; then NVIM_APPNAME=nvim-ruby nvim "$@"
  elif [ -f Cargo.toml ]; then NVIM_APPNAME=nvim-rust nvim "$@"
  else nvim "$@"; fi
}
# <<< nvim-setup (perfiles) <<<
EOF
  log "aliases añadidos (haz 'source ~/.zshrc' o abre otra terminal)"
}

sync_profile() { # <appname|"">
  local app="${1:-}"
  local label="${app:-default}"
  step "Instalando plugins — perfil $label"
  local env=()
  [ -n "$app" ] && env=(env NVIM_APPNAME="$app")
  # 1) clona/actualiza plugins + compila parsers de Treesitter
  timeout 900 "${env[@]}" "$BIN/nvim" --headless "+Lazy! sync" +qa 2>&1 | tail -n 8 || true
  # 1b) parsers de Treesitter (rama main: install() es asíncrono, aquí se espera)
  timeout 900 "${env[@]}" "$BIN/nvim" --headless \
    -c 'lua require("nvim-treesitter").install(_G.TS_ENSURE or {}):wait(840000)' +qa 2>&1 | tail -n 5 || true
  # 2) instala servidores LSP + formateadores (abre un buffer real para cargar lspconfig;
  #    sale solo al terminar Mason, con tope de 12 min por si algo se cuelga)
  timeout 780 "${env[@]}" "$BIN/nvim" --headless "$SHARED/lua/base/options.lua" \
    -c 'autocmd User MasonToolsUpdateCompleted ++once qall' \
    -c 'lua vim.defer_fn(function() pcall(vim.cmd, "MasonToolsInstall") end, 1500)' \
    -c 'lua vim.defer_fn(function() vim.cmd("qall!") end, 720000)' 2>&1 | tail -n 20 || true
  log "perfil $label listo"
}

self_install() {
  step "nvim-setup (mantenimiento)"
  if [ "$SELF" != "$(readlink -f "$BIN/nvim-setup" 2>/dev/null)" ]; then
    install -m 755 "$SELF" "$BIN/nvim-setup"
    log "copiado -> $BIN/nvim-setup   (usa: nvim-setup --update | --config-only)"
  else
    log "ya es $BIN/nvim-setup"
  fi
  install -m 644 "$SHARED/README.md" "$DOC/README.md" 2>/dev/null \
    && log "doc -> $DOC/README.md" || true
}

# ----------------------------------------------------------------- run
if [ "$DO_BIN" = 1 ]; then
  install_neovim
  install_gh_tool lazygit    jesseduffield/lazygit    lazygit
  install_gh_tool lazydocker jesseduffield/lazydocker lazydocker
  install_extras
fi

if [ "$DO_CONFIG" = 1 ]; then
  step "Generando configuración"
  backup_existing
  write_base
  write_profile_default
  write_profile_ruby
  write_profile_rust
  write_aliases
fi

self_install

if [ "$DO_SYNC" = 1 ]; then
  sync_profile ""
  # los perfiles de lenguaje solo se sincronizan si su toolchain está instalado;
  # si no, se instalan solos la primera vez que abras nvim-ruby / nvim-rust
  if have ruby || have bundle; then sync_profile "nvim-ruby"
  else step "Perfil ruby: sin Ruby instalado, se omite el sync"; fi
  if have cargo; then sync_profile "nvim-rust"
  else step "Perfil rust: sin cargo instalado, se omite el sync"; fi
fi

step "Hecho"
NVIM_V="$("$BIN/nvim" --version 2>/dev/null)"; NVIM_V="${NVIM_V%%$'\n'*}"
LG_OK="no instalado"; command -v lazygit    >/dev/null && LG_OK="ok"
LD_OK="no instalado"; command -v lazydocker >/dev/null && LD_OK="ok"
cat <<EOF

  Neovim:      ${NVIM_V:-no instalado}
  lazygit:     $LG_OK
  lazydocker:  $LD_OK
  Log:         $LOG

  Siguiente:
    source ~/.zshrc          # cargar los aliases
    nvim                      # perfil generalista
    nvim-ruby   (o  nvr)      # perfil Rails
    nvp                       # autodetecta por Gemfile / Cargo.toml

  Dentro de Neovim:
    <Space>       menú de atajos (which-key)
    <Space>ff     buscar archivos      <Space>fg  grep en el proyecto
    <Space>e      explorador           <Space>o   outline
    <Space>gg     LazyGit              <Space>ld  LazyDocker
    gd / gr / K   LSP                  ]d / [d   diagnósticos
    :Lazy  :Mason  :checkhealth

  Mantenimiento:  nvim-setup --update | --config-only     (o  install-neovim.sh --uninstall)
  Aprende lo básico:  nvim +Tutor
EOF
