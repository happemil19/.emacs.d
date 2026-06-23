# ~/.emacs.d — кратко

Минимальный Emacs: демон + `emacsclient -c`. Вся конфигурация в `init.el`.

## Быстрый старт

```bash
git clone <url> ~/.emacs.d
~/.emacs.d/bin/install-systemd.sh
~/.emacs.d/bin/install-desktop.sh
systemctl --user enable --now emacs.service
emacsclient -c
```

## Каждый день

```bash
emacsclient -c              # новое окно (desktop восстановится)
emacsclient -c FILE           # открыть файл
systemctl --user restart emacs.service
```

Не запускайте `emacs --daemon` вручную — только systemd.

## Горячие клавиши

| Клавиши | Действие |
|---------|----------|
| `C-c h/j/k/l` | окно ← ↓ ↑ → |
| `C-c n/p` | буфер вперёд / назад |
| `C-c g` / `C-x g` | Magit (проект / репо) |
| `C-c r` | недавние файлы |
| `C-c e` | `init.el` |

Подробнее — [README.md](README.md).
