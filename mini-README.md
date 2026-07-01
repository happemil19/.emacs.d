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
emacsclient -c                    # новое окно (desktop восстановится)
emacsclient -c FILE               # открыть файл
```

## Перезапуск

```bash
# Полный перезапуск daemon (новый init.el, desktop сохранится и восстановится):
systemctl --user restart emacs && emacsclient -c

# Только подтянуть init.el, daemon не трогать (C-c C-c в init.el то же самое):
emacsclient -e '(load user-init-file t t)'
```

Перед `restart` сохраните правки в файлах (`C-x C-s` или `C-x s`), иначе
несохранённое в буферах может потеряться. `M-x save-buffers-kill-emacs` daemon
не нужен — он делает то же, что остановка сервиса, но менее предсказуемо.

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
