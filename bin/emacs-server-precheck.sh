#!/bin/sh
# Before emacs.service starts: ensure no stale server socket or stray emacs.
# Do not use emacsclient -a '' — empty alternate editor can spawn a second daemon.

server="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/emacs/server"

[ -S "$server" ] || { pkill -u "$USER" -x emacs 2>/dev/null || true; exit 0; }

if timeout 3 emacsclient -e '(kill-emacs)' >/dev/null 2>&1; then
  i=0
  while [ -S "$server" ] && [ "$i" -lt 10 ]; do
    sleep 1
    i=$((i + 1))
  done
fi

if [ -S "$server" ] || pgrep -u "$USER" -x emacs >/dev/null 2>&1; then
  pkill -u "$USER" -x emacs 2>/dev/null || true
  sleep 1
  pkill -9 -u "$USER" -x emacs 2>/dev/null || true
  rm -f "$server"
fi
