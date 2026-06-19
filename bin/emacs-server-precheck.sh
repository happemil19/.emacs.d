#!/bin/sh
# Before starting emacs.service: drop a dead server socket / zombie daemon.
# Safe if a live daemon responds to emacsclient.

server="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/emacs/server"

[ -S "$server" ] || exit 0

if timeout 2 emacsclient -a '' -e '(+ 1 1)' >/dev/null 2>&1; then
  exit 0
fi

pkill -u "$USER" -x emacs 2>/dev/null || true
sleep 1
pkill -9 -u "$USER" -x emacs 2>/dev/null || true
rm -f "$server"
