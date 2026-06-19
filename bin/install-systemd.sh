#!/bin/sh
# Link emacs.service from ~/.emacs.d into systemd --user and reload.
set -e

emacs_d="${EMACSD:-$HOME/.emacs.d}"
unit_dir="$HOME/.config/systemd/user"
dropin_dir="$unit_dir/emacs.service.d"

mkdir -p "$dropin_dir"
chmod +x "$emacs_d/bin/emacs-server-precheck.sh"

ln -sfn "$emacs_d/systemd/user/emacs.service" "$unit_dir/emacs.service"
ln -sfn "$emacs_d/systemd/user/emacs.service.d/precheck.conf" \
  "$dropin_dir/precheck.conf"

systemctl --user daemon-reload
echo "Linked emacs.service from $emacs_d"
echo "  systemctl --user enable --now emacs.service   # enable at login"
echo "  systemctl --user status emacs.service         # check status"
