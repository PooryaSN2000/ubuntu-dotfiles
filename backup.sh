#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WITH_ASSETS=false

usage() {
  cat <<'EOF'
Usage: ./backup.sh [OPTIONS]

Export Ubuntu GNOME settings, extensions, package lists, and dotfiles into this repository.

Options:
  --assets    Also archive ~/.themes, ~/.local/share/gnome-shell/extensions, and ~/.local/share/fonts
  -h, --help  Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --assets)
      WITH_ASSETS=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

mkdir -p \
  "$REPO_DIR/packages/apt-sources-reference" \
  "$REPO_DIR/gnome/dconf" \
  "$REPO_DIR/gnome/wallpapers" \
  "$REPO_DIR/gnome/gtk-3.0" \
  "$REPO_DIR/gnome/archives" \
  "$REPO_DIR/dotfiles/vscode"

log() {
  printf '[backup] %s\n' "$1"
}

copy_if_exists() {
  local src="$1"
  local dst="$2"
  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -L "$src" "$dst"
  fi
}

backup_packages() {
  log "Exporting APT packages..."
  apt-mark showmanual | sort -u > "$REPO_DIR/packages/apt-manual-raw.txt"
  if [[ -f "$REPO_DIR/packages/system-base-ignore.txt" ]]; then
    grep -vxFf <(grep -vE '^\s*(#|$)' "$REPO_DIR/packages/system-base-ignore.txt") \
      "$REPO_DIR/packages/apt-manual-raw.txt" > "$REPO_DIR/packages/apt-apps.txt" || true
  else
    cp "$REPO_DIR/packages/apt-manual-raw.txt" "$REPO_DIR/packages/apt-apps.txt"
  fi

  log "Copying third-party APT source references..."
  rm -f "$REPO_DIR/packages/apt-sources-reference/"*
  if [[ -d /etc/apt/sources.list.d ]]; then
    for f in /etc/apt/sources.list.d/*; do
      [[ -f "$f" ]] || continue
      local base
      base="$(basename "$f")"
      [[ "$base" == ubuntu.sources* ]] && continue
      cp "$f" "$REPO_DIR/packages/apt-sources-reference/$base"
    done
  fi

  if command -v snap >/dev/null 2>&1; then
    log "Exporting Snap packages..."
    snap list > "$REPO_DIR/packages/snap-raw.txt"
    awk 'NR>1 {print $1}' "$REPO_DIR/packages/snap-raw.txt" \
      | grep -vxE 'bare|core[0-9]*|cups|desktop-security-center|firmware-updater|gnome-.*|gtk-common-themes|kf6-.*|mesa-.*|prompting-client|snap-store|snapd|snapd-desktop-integration' \
      | sort -u > "$REPO_DIR/packages/snap-apps.txt" || true
  fi

  if command -v flatpak >/dev/null 2>&1; then
    log "Exporting Flatpak apps..."
    flatpak list --app --columns=application | sort -u > "$REPO_DIR/packages/flatpak-apps.txt"
  fi

  if command -v code >/dev/null 2>&1; then
    log "Exporting VS Code extensions..."
    code --list-extensions | sort -u > "$REPO_DIR/packages/vscode-extensions.txt"
  fi
}

backup_gnome() {
  log "Exporting GNOME dconf settings..."
  local -A dconf_map=(
    ["/org/gnome/desktop/"]="desktop.ini"
    ["/org/gnome/shell/"]="shell.ini"
    ["/org/gnome/mutter/"]="mutter.ini"
    ["/org/gnome/settings-daemon/"]="settings-daemon.ini"
    ["/org/gnome/nautilus/"]="nautilus.ini"
    ["/org/gnome/TextEditor/"]="text-editor.ini"
    ["/org/gnome/Ptyxis/"]="ptyxis.ini"
  )

  for path in "${!dconf_map[@]}"; do
    local out="$REPO_DIR/gnome/dconf/${dconf_map[$path]}"
    # Normalize $HOME to __HOME__ and strip private/volatile entries
    dconf dump "$path" \
      | sed "s|$HOME|__HOME__|g" \
      | awk '
          /^\[extensions\/gsconnect/ { skip=1; next }
          /^\[/ { skip=0 }
          skip { next }
          /^(playback-history|device-list|last-save-directory)=/ { next }
          { print }
        ' \
      > "$out" || true
  done

  if command -v gnome-extensions >/dev/null 2>&1; then
    log "Exporting GNOME extensions lists..."
    gnome-extensions list --enabled | sort -u > "$REPO_DIR/gnome/extensions-enabled.txt"
    gnome-extensions list | sort -u > "$REPO_DIR/gnome/extensions-all.txt"
  fi

  if [[ -d "$HOME/.local/share/gnome-shell/extensions" ]]; then
    ls -1 "$HOME/.local/share/gnome-shell/extensions" | sort -u > "$REPO_DIR/gnome/extensions-user.txt"
  fi

  if [[ -d "$HOME/.themes" ]]; then
    ls -1 "$HOME/.themes" | sort -u > "$REPO_DIR/gnome/themes-list.txt"
  fi

  if [[ -d "$HOME/.local/share/fonts" ]]; then
    ls -1 "$HOME/.local/share/fonts" | sort -u > "$REPO_DIR/gnome/fonts-list.txt"
  fi

  log "Exporting wallpaper & GTK CSS..."
  copy_if_exists "$HOME/.config/background" "$REPO_DIR/gnome/wallpapers/background"
  copy_if_exists "$HOME/.config/gtk-3.0/gtk.css" "$REPO_DIR/gnome/gtk-3.0/gtk.css"
  copy_if_exists "$HOME/.config/gtk-3.0/custom-accent.css" "$REPO_DIR/gnome/gtk-3.0/custom-accent.css"

  if [[ "$WITH_ASSETS" == true ]]; then
    log "Archiving themes, user extensions, and fonts..."
    [[ -d "$HOME/.themes" ]] && tar -czf "$REPO_DIR/gnome/archives/themes.tar.gz" -C "$HOME" .themes
    [[ -d "$HOME/.local/share/gnome-shell/extensions" ]] && tar -czf "$REPO_DIR/gnome/archives/extensions.tar.gz" -C "$HOME/.local/share/gnome-shell" extensions
    [[ -d "$HOME/.local/share/fonts" ]] && tar -czf "$REPO_DIR/gnome/archives/fonts.tar.gz" -C "$HOME/.local/share" fonts
  fi
}

backup_dotfiles() {
  log "Exporting dotfiles..."
  copy_if_exists "$HOME/.bashrc" "$REPO_DIR/dotfiles/.bashrc"
  copy_if_exists "$HOME/.zshrc" "$REPO_DIR/dotfiles/.zshrc"
  copy_if_exists "$HOME/.gitconfig" "$REPO_DIR/dotfiles/.gitconfig"
  copy_if_exists "$HOME/.config/Code/User/settings.json" "$REPO_DIR/dotfiles/vscode/settings.json"
  copy_if_exists "$HOME/.config/Code/User/keybindings.json" "$REPO_DIR/dotfiles/vscode/keybindings.json"
}

backup_packages
backup_gnome
backup_dotfiles

log "Done! Review changes with: git status && git diff"
