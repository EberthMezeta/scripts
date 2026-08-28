# My Configuration Scripts

This repository contains my personal configuration script to quickly set up a development environment on Ubuntu/Debian-based systems.  
The script installs and configures essential tools, shells, fonts, and programming environments.

## 🚀 What does the script do?

The setup script will:

- Keep `sudo` active during execution.
- Update and upgrade your system.
- Install essential packages: `git`, `curl`, `wget`, `build-essential`, `zsh`, `eza`, etc.
- Install and configure **Zsh** with **Oh My Zsh** and useful plugins:
  - `zsh-syntax-highlighting`
  - `zsh-autosuggestions`
- Install **Oh My Posh** for a modern shell prompt.
- Install **Nerd Fonts** (Cascadia Code and Hack).
- Install **RVM** and configure Ruby.
- Install **NVM** and configure Node.js.
- Install **Visual Studio Code**.
- Configure your `~/.zshrc` with aliases and integrations for the installed tools.

## 📦 Requirements

- Ubuntu/Debian-based Linux distribution.
- Internet connection.
- `sudo` privileges.

## ⚡ How to run it

1. Clone the repository:

```bash
git clone https://github.com/EberthMezeta/scripts.git
cd scripts
```

2. Make the script executable:

```bash
chmod +x script.sh
```

3. Run the script:

```bash
./script.sh
```

## 🧩 Extra installers

These are standalone, no-sudo installers. Each one installs into `~/.local` by
default, adds a `~/.local/bin` entry, and supports `--uninstall`.
Run `./<script> --help` for the full list of options.

### 🐬 `install-mysql-import.sh`

Installs the `mysql-import` tool: imports a `.sql` / `.sql.gz` dump into
MySQL/MariaDB (Docker or native), creating the database and running `SOURCE`.
Adds a **"MySQL Import"** desktop launcher (zenity GUI).

```bash
chmod +x install-mysql-import.sh
./install-mysql-import.sh                 # install into ~/.local
./install-mysql-import.sh --no-config     # don't create ~/.config/mysql-import.env
./install-mysql-import.sh --prefix ~/.opt # custom install root
./install-mysql-import.sh --uninstall     # remove everything (keeps the .env)
```

After installing:

```bash
mysql-import --help
mysql-import dump.sql                     # derives the DB name from the file
mysql-import --drop backup.sql.gz my_db
mysql-import                              # no args → zenity file picker
```

> The GUI launcher needs `zenity` (`sudo apt install zenity`). Without it the
> desktop icon does nothing visible.

### 📝 `install-neovim.sh`

Installs Neovim (official tarball) plus a modular config with per-stack profiles
(`default`, `ruby`, `rust`) and drops helper binaries (`lazygit`, `lazydocker`,
`rg`, `fd`) if missing. Adds aliases to `~/.zshrc` (`nvr`, `nvim-rust`, `nvp`).

```bash
chmod +x install-neovim.sh
./install-neovim.sh                 # install into ~/.local
./install-neovim.sh --config-only   # only regenerate ~/.config/nvim* (no binaries)
./install-neovim.sh --no-sync       # skip headless plugin/LSP install
./install-neovim.sh --update        # re-download nvim + tools, then sync
./install-neovim.sh --uninstall     # remove binaries, profiles and the .zshrc block
```

It validates system prerequisites first (`curl`, `git`, `tar`, `unzip`,
`python3`, `make` + a C compiler) and prints the `apt install` command if any
required one is missing.

After installing:

```bash
nvim                # default profile
nvr                 # Ruby/Rails profile   (NVIM_APPNAME=nvim-ruby)
nvim-rust           # Rust profile
nvp                 # auto-detects (Gemfile → ruby, Cargo.toml → rust)
```
