# ~/.emacs.d

Минимальная конфигурация Emacs: один `init.el`, GUI через user-демон и `emacsclient`.

## Требования

- Emacs 28+ (сейчас: `/usr/local/bin/emacs`)
- GUI (GTK), X11
- `systemd --user`
- Для буфера обмена: `xsel` или `xclip`
- Опционально: RHVoice + Speech Dispatcher (`speechd-el`), `pylsp`, Git

## Установка

```bash
git clone <url> ~/.emacs.d
~/.emacs.d/bin/install-systemd.sh
~/.emacs.d/bin/install-desktop.sh
systemctl --user enable --now emacs.service
```

Пакеты из GNU ELPA / MELPA подтягиваются при первом запуске (`my/ensure-package`).

Если `emacs` установлен не в `/usr/local/bin/`, поправьте `ExecStart` в
`systemd/user/emacs.service` и `Exec=` в `desktop/*.desktop`, затем:

```bash
systemctl --user daemon-reload
systemctl --user restart emacs.service
```

Ярлыки подхватывают правки из репо сразу (симлинки). `daemon-reload` нужен
только для unit-файла systemd.

## Использование

Демон держит сессию (окна, буферы, desktop). Новое GUI-окно:

```bash
emacsclient -c          # пустое окно, восстановит desktop
emacsclient -c FILE     # файл в клиентском окне
```

Управление сервисом — **только** через systemd (не запускайте `emacs --daemon`
вручную параллельно):

```bash
systemctl --user status emacs.service
systemctl --user restart emacs.service
```

Перед стартом `bin/emacs-server-precheck.sh` убирает «мёртвый» сокет сервера,
если старый процесс завис.

## Клавиши (`C-c …`)

| Клавиши | Действие |
|---------|----------|
| `C-c h/j/k/l` | окно влево / вниз / вверх / вправо |
| `C-c n/p` | следующий / предыдущий буфер |
| `C-c [ / ]` | undo / redo раскладки окон (winner) |
| `C-c g` | Magit для выбранного проекта |
| `C-x g` | Magit для текущего репозитория |
| `C-c r` | недавние файлы |
| `C-c t` | vterm |
| `C-c o` / `C-c A` | Org inbox / agenda |
| `C-c ;` | comment-line |
| `C-c e` | открыть `init.el` |

`C-x p p` — выбор проекта; в списке `g` открывает Magit.

## Структура

```
init.el                 — вся конфигурация
bin/                    — install-скрипты, precheck
desktop/                — ярлыки для меню приложений (≠ .emacs.desktop)
systemd/user/           — emacs.service и drop-in
elpa/                   — пакеты (не в git)
```

Runtime-файлы (`history`, `recentf`, `.emacs.desktop`, …) в `.gitignore`.

`desktop/emacs.desktop` — ярлык в меню (Freedesktop). `~/.emacs.d/.emacs.desktop` —
сохранённая сессия Emacs (окна, буферы); это разные файлы с одним расширением.

## Заметки

- **Magit:** при byte-compile ломаются макросы `cond-let` (`void-variable $`);
  `init.el` удаляет `magit*.elc` при старте — не компилируйте Magit вручную.
- **Desktop:** сессия с окнами и сплитами восстанавливается в `emacsclient -c`.
- **Python:** Eglot + pylsp, venv проекта подхватывается автоматически.
