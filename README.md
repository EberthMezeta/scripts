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
