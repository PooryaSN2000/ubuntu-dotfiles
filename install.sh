#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DO_PACKAGES=false
DO_GNOME=false
DO_ASSETS=false
DO_DOTFILES=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Restore Ubuntu packages, GNOME UI settings, extensions, assets, and dotfiles.

Options:
  --all         Restore everything (packages, assets, gnome settings, dotfiles)
  --packages    Install APT, Snap, Flatpak, and VS Code packages/extensions
  --assets      Extract themes, user extensions, fonts, and wallpaper
  --gnome       Load GNOME dconf settings and enable saved GNOME extensions
  --dotfiles    Restore .bashrc, .gitconfig, and VS Code settings (backs up existing files)
  --dry-run     Print actions without modifying the system
  -h, --help    Show this help message
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      DO_PACKAGES=true
      DO_ASSETS=true
      DO_GNOME=true
      DO_DOTFILES=true
      shift
      ;;
    --packages) DO_PACKAGES=true; shift ;;
    --assets)   DO_ASSETS=true; shift ;;
    --gnome)    DO_GNOME=true; shift ;;
    --dotfiles) DO_DOTFILES=true; shift ;;
    --dry-run)  DRY_RUN=true; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

log() {
  printf '[install] %s\n' "$1"
}

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

backup_and_copy() {
  local src="$1"
  local dst="$2"
  [[ -f "$src" ]] || return 0
  if [[ -f "$dst" || -L "$dst" ]]; then
    run cp -a "$dst" "${dst}.bak.$(date +%Y%m%d%H%M%S)"
  fi
  run mkdir -p "$(dirname "$dst")"
  run cp "$src" "$dst"
}

restore_packages() {
  if [[ -f "$REPO_DIR/packages/apt-apps.txt" ]]; then
    log "Updating APT cache..."
    run sudo apt-get update

    local available=()
    local missing=()
    while IFS= read -r pkg; do
      [[ -z "$pkg" || "$pkg" == \#* ]] && continue
      if apt-cache show "$pkg" >/dev/null 2>&1; then
        available+=("$pkg")
      else
        missing+=("$pkg")
      fi
    done < "$REPO_DIR/packages/apt-apps.txt"

    if [[ ${#available[@]} -gt 0 ]]; then
      log "Installing ${#available[@]} APT packages..."
      run sudo apt-get install -y "${available[@]}"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
      log "NOTE: These packages require third-party repos/.deb files (see packages/apt-sources-reference/):"
      printf '  - %s\n' "${missing[@]}"
    fi
  fi

  if [[ -f "$REPO_DIR/packages/snap-apps.txt" ]] && command -v snap >/dev/null 2>&1; then
    log "Installing Snap packages..."
    while IFS= read -r pkg; do
      [[ -z "$pkg" || "$pkg" == \#* ]] && continue
      if snap list "$pkg" >/dev/null 2>&1; then
        continue
      fi
      # Try standard install first; fall back to --classic if needed (e.g., code)
      if [[ "$DRY_RUN" == true ]]; then
        run snap install "$pkg"
      else
        sudo snap install "$pkg" || sudo snap install "$pkg" --classic || log "WARN: Failed to snap install $pkg"
      fi
    done < "$REPO_DIR/packages/snap-apps.txt"
  fi

  if [[ -f "$REPO_DIR/packages/flatpak-apps.txt" ]] && command -v flatpak >/dev/null 2>&1; then
    log "Installing Flatpak apps..."
    run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    while IFS= read -r app; do
      [[ -z "$app" || "$app" == \#* ]] && continue
      run flatpak install -y flathub "$app" || log "WARN: Failed to flatpak install $app"
    done < "$REPO_DIR/packages/flatpak-apps.txt"
  fi

  if [[ -f "$REPO_DIR/packages/vscode-extensions.txt" ]] && command -v code >/dev/null 2>&1; then
    log "Installing VS Code extensions..."
    while IFS= read -r ext; do
      [[ -z "$ext" || "$ext" == \#* ]] && continue
      run code --install-extension "$ext" || true
    done < "$REPO_DIR/packages/vscode-extensions.txt"
  fi
}

restore_assets() {
  if [[ -f "$REPO_DIR/gnome/archives/themes.tar.gz" ]]; then
    log "Restoring ~/.themes..."
    run tar -xzf "$REPO_DIR/gnome/archives/themes.tar.gz" -C "$HOME"
    run mkdir -p "$HOME/.local/share"
    if [[ ! -e "$HOME/.local/share/themes" ]]; then
      run ln -s "$HOME/.themes" "$HOME/.local/share/themes"
    fi
    if [[ -d "$HOME/.themes/Nordic-darker-v40" ]]; then
      run mkdir -p "$HOME/.config/gtk-4.0"
      run ln -sfn "$HOME/.themes/Nordic-darker-v40/assets" "$HOME/.config/gtk-4.0/assets"
      run ln -sfn "$HOME/.themes/Nordic-darker-v40/gtk-4.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
      run ln -sfn "$HOME/.themes/Nordic-darker-v40/gtk-4.0/gtk-dark.css" "$HOME/.config/gtk-4.0/gtk-dark.css"
    fi
  fi

  if [[ -f "$REPO_DIR/gnome/archives/extensions.tar.gz" ]]; then
    log "Restoring user GNOME extensions..."
    run mkdir -p "$HOME/.local/share/gnome-shell"
    run tar -xzf "$REPO_DIR/gnome/archives/extensions.tar.gz" -C "$HOME/.local/share/gnome-shell"
  fi

  if [[ -f "$REPO_DIR/gnome/archives/fonts.tar.gz" ]]; then
    log "Restoring user fonts..."
    run mkdir -p "$HOME/.local/share"
    run tar -xzf "$REPO_DIR/gnome/archives/fonts.tar.gz" -C "$HOME/.local/share"
    run fc-cache -fv >/dev/null
  fi

  backup_and_copy "$REPO_DIR/gnome/wallpapers/background" "$HOME/.config/background"
  backup_and_copy "$REPO_DIR/gnome/gtk-3.0/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"
  backup_and_copy "$REPO_DIR/gnome/gtk-3.0/custom-accent.css" "$HOME/.config/gtk-3.0/custom-accent.css"
}

restore_gnome() {
  local -A dconf_map=(
    ["desktop.ini"]="/org/gnome/desktop/"
    ["shell.ini"]="/org/gnome/shell/"
    ["mutter.ini"]="/org/gnome/mutter/"
    ["settings-daemon.ini"]="/org/gnome/settings-daemon/"
    ["nautilus.ini"]="/org/gnome/nautilus/"
    ["text-editor.ini"]="/org/gnome/TextEditor/"
    ["ptyxis.ini"]="/org/gnome/Ptyxis/"
  )

  log "Loading GNOME dconf settings..."
  for file in "${!dconf_map[@]}"; do
    local ini="$REPO_DIR/gnome/dconf/$file"
    local path="${dconf_map[$file]}"
    [[ -f "$ini" ]] || continue
    if [[ "$DRY_RUN" == true ]]; then
      printf '[dry-run] dconf load %s < %s (with __HOME__ -> %s)\n' "$path" "$ini" "$HOME"
    else
      sed "s|__HOME__|$HOME|g" "$ini" | dconf load "$path"
    fi
  done

  if [[ -f "$REPO_DIR/gnome/extensions-enabled.txt" ]] && command -v gnome-extensions >/dev/null 2>&1; then
    log "Enabling GNOME extensions (may require logout/login to take effect)..."
    while IFS= read -r ext; do
      [[ -z "$ext" || "$ext" == \#* ]] && continue
      run gnome-extensions enable "$ext" || log "WARN: Could not enable $ext (try after relogin)"
    done < "$REPO_DIR/gnome/extensions-enabled.txt"
  fi
}

restore_dotfiles() {
  log "Restoring dotfiles..."
  backup_and_copy "$REPO_DIR/dotfiles/.bashrc" "$HOME/.bashrc"
  backup_and_copy "$REPO_DIR/dotfiles/.zshrc" "$HOME/.zshrc"
  backup_and_copy "$REPO_DIR/dotfiles/.gitconfig" "$HOME/.gitconfig"
  backup_and_copy "$REPO_DIR/dotfiles/vscode/settings.json" "$HOME/.config/Code/User/settings.json"
  backup_and_copy "$REPO_DIR/dotfiles/vscode/keybindings.json" "$HOME/.config/Code/User/keybindings.json"
}

[[ "$DO_PACKAGES" == true ]] && restore_packages
[[ "$DO_ASSETS" == true ]] && restore_assets
[[ "$DO_GNOME" == true ]] && restore_gnome
[[ "$DO_DOTFILES" == true ]] && restore_dotfiles

log "Done! Log out and log back in (or reboot) for all GNOME extensions and theme changes to apply."
