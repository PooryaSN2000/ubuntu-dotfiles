# Ubuntu Setup & Dotfiles

Automated backup and restore repository for my **Ubuntu (GNOME)** workstation: UI customization, GNOME extensions, themes, Persian/system fonts, installed applications, and dotfiles.

## Structure

```text
.
├── backup.sh                   # Export current system state into this repo
├── install.sh                  # Restore packages, UI, extensions, and dotfiles
├── packages/
│   ├── apt-apps.txt            # Filtered user-installed APT packages
│   ├── apt-manual-raw.txt      # Full `apt-mark showmanual` output
│   ├── system-base-ignore.txt  # Base OS/driver packages excluded from apt-apps.txt
│   ├── apt-sources-reference/  # Reference .sources/.list files for third-party repos
│   ├── snap-apps.txt           # User-installed Snap apps
│   ├── flatpak-apps.txt        # Flatpak applications
│   └── vscode-extensions.txt   # VS Code extensions
├── gnome/
│   ├── dconf/                  # Split GNOME dconf dumps (__HOME__ normalized)
│   ├── archives/               # Compressed themes, user extensions, and fonts
│   ├── wallpapers/             # Desktop background
│   ├── gtk-3.0/                # Custom GTK3 CSS overrides
│   ├── extensions-enabled.txt  # Currently enabled GNOME extensions
│   ├── extensions-user.txt     # User-installed extensions list
│   ├── themes-list.txt         # Installed GTK/Shell themes
│   └── fonts-list.txt          # Installed user fonts
└── dotfiles/                   # .bashrc, .gitconfig, VS Code settings
```

## Backup Workflow (Current System)

Whenever you install new apps or tweak your desktop:

```bash
./backup.sh            # Refresh package lists, dconf dumps, wallpaper, and dotfiles
./backup.sh --assets   # Also re-archive ~/.themes, user extensions, and ~/.local/share/fonts
```

Then commit and push:

```bash
git add -A && git commit -m "Update Ubuntu setup" && git push
```

## Restore Workflow (Fresh Ubuntu Install)

```bash
git clone <YOUR_REPO_URL> ubuntu-setup
cd ubuntu-setup
chmod +x install.sh backup.sh

# Preview what will run
./install.sh --all --dry-run

# Run full restore (or pick individual flags: --packages, --assets, --gnome, --dotfiles)
./install.sh --all
```

> **Note:** After restoring GNOME extensions and themes, log out and log back in (or reboot) for GNOME Shell to reload everything.

## Manual Post-Install Checklist

Some items intentionally aren't automated for security and hardware compatibility:

1. **Third-party APT repos / `.deb` apps:** Check `packages/apt-sources-reference/` (Docker, Google Chrome, Cursor, ChatGPT, Steam) and standalone `.deb` downloads (e.g., Discord, Obsidian, VirtualBox, VPN clients) before/after running `--packages`.
2. **GPU drivers:** Install the appropriate NVIDIA driver via *Software & Updates → Additional Drivers* or `ubuntu-drivers install`.
3. **Secrets & Accounts:** Restore `~/.ssh` keys, Git credentials, and app logins manually.
4. **Node / Python tools:** Install `nvm` (referenced in `.bashrc`) and any global CLI tools if needed.
