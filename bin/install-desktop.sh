#!/bin/sh
# Link desktop launchers from ~/.emacs.d into ~/.local/share/applications.
set -e

emacs_d="${EMACSD:-$HOME/.emacs.d}"
app_dir="$HOME/.local/share/applications"

mkdir -p "$app_dir"

ln -sfn "$emacs_d/desktop/emacs.desktop" "$app_dir/emacs.desktop"
ln -sfn "$emacs_d/desktop/emacsclient.desktop" "$app_dir/emacsclient.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$app_dir"
fi

echo "Linked desktop launchers from $emacs_d"
echo "  Overrides vendor emacs.desktop (no standalone Emacs in the menu)."
