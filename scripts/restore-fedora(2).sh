#!/usr/bin/env bash
# restore-fedora.sh
# Put this in the ROOT of your popos-dotfiles repo and run it from inside a
# logged-in GNOME session (a normal terminal window, not a TTY / SSH).
#   bash restore-fedora.sh
#
# Replaces scripts/install.sh + scripts/setup.sh, which are apt-only.

set -uo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
GN="$REPO/popos/gnome/backups"
FAILED="$HOME/ext-failed.txt"
: > "$FAILED"

echo "=== 1/7 Packages (dnf) ==="
sudo dnf install -y git curl kitty tilix fastfetch gnome-tweaks gnome-extensions-app \
  java-17-openjdk-devel pipx lm_sensors tesseract tesseract-langpack-eng
# lm_sensors -> Vitals extension, tesseract -> textgrabber extension

echo "=== 1b/7 Flatpak apps ==="
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
FP_FAILED="$HOME/flatpak-failed.txt"
: > "$FP_FAILED"
if [ -f "$REPO/flatpak-apps.txt" ]; then
  while read -r app; do
    [ -z "$app" ] && continue
    flatpak install -y flathub "$app" || echo "$app" >> "$FP_FAILED"
  done < "$REPO/flatpak-apps.txt"
else
  echo "  !! no flatpak-apps.txt in repo - skipping"
fi

echo "=== 2/7 Sublime Text ==="
sudo rpm -v --import https://download.sublimetext.com/sublimehq-rpm-pub.gpg
sudo dnf config-manager addrepo --from-repofile=https://download.sublimetext.com/rpm/stable/x86_64/sublime-text.repo
sudo dnf install -y sublime-text
mkdir -p "$HOME/.config/sublime-text"
cp -r "$REPO"/sublime/config/* "$HOME/.config/sublime-text/"

echo "=== 3/7 keyd ==="
sudo dnf install -y keyd || {
  sudo dnf copr enable -y alternateved/keyd && sudo dnf install -y keyd
}
sudo mkdir -p /etc/keyd
sudo cp "$REPO/configs/keyd/default.conf" /etc/keyd/default.conf
sudo systemctl enable --now keyd
sudo keyd reload || true

echo "=== 4/7 Fonts ==="
# Your GNOME font is 'Slate For OnePlus'. It is NOT in the repo, so put the
# font files in a  fonts/  folder in the repo root before running this.
mkdir -p "$HOME/.local/share/fonts"
if [ -d "$REPO/fonts" ]; then
  cp -r "$REPO"/fonts/. "$HOME/.local/share/fonts/"
  fc-cache -f
else
  echo "  !! no fonts/ folder in repo - Slate For OnePlus will be missing"
fi

echo "=== 5/7 GNOME extensions (gext) ==="
pipx install gnome-extensions-cli --system-site-packages
export PATH="$HOME/.local/bin:$PATH"
while read -r uuid; do
  [ -z "$uuid" ] && continue
  echo "  -> $uuid"
  gext install "$uuid" || echo "$uuid" >> "$FAILED"
done < "$GN/extensions/enabled.txt"

echo "=== 6/7 GNOME settings (dconf) ==="
# full.dconf already contains everything. The per-category *.dconf files are
# skipped on purpose: the old restore.sh loaded them to wrong paths.
dconf load / < "$GN/dconf/full.dconf"
for f in "$GN"/extensions/settings-*.dconf; do
  [ -f "$f" ] || continue
  name="$(basename "$f" .dconf | sed 's/^settings-//')"
  dconf load "/org/gnome/shell/extensions/$name/" < "$f" 2>/dev/null || true
done

WALL="$GN/wallpaper/current-wallpaper.jpg"
if [ -f "$WALL" ]; then
  mkdir -p "$HOME/.local/share/backgrounds"
  cp "$WALL" "$HOME/.local/share/backgrounds/restored-wallpaper.jpg"
  U="file://$HOME/.local/share/backgrounds/restored-wallpaper.jpg"
  gsettings set org.gnome.desktop.background picture-uri "$U"
  gsettings set org.gnome.desktop.background picture-uri-dark "$U"
  gsettings set org.gnome.desktop.screensaver picture-uri "$U"
fi

echo "=== 7/7 Shell bits ==="
# Your repo's .bashrc/.profile are the stock Ubuntu ones, so don't copy them
# over Fedora's. Only the extra aliases are kept.
mkdir -p "$HOME/.bashrc.d"
printf "alias la='ls -A'\nalias l='ls -CF'\n" > "$HOME/.bashrc.d/aliases.sh"

echo
echo "Done. LOG OUT and log back in so the extensions load."
if [ -s "$FP_FAILED" ]; then
  echo "These flatpaks were not found on Flathub (install them manually):"
  cat "$FP_FAILED"
fi
if [ -s "$FAILED" ]; then
  echo "These extensions failed to install (not compatible with this GNOME yet, or renamed):"
  cat "$FAILED"
fi
