;;; init.el --- Minimal Emacs config  -*- lexical-binding: t; -*-

;; Prefer init.el over init.elc when the source is newer (stale .elc bites).
;; Must be set in early-init.el too — Emacs chooses .el/.elc before init.el runs.
(setq load-prefer-newer t)

;; Goal: keep the configuration as small and reproducible as possible.
;; Primary UI: emacs --fg-daemon + emacsclient -c (GUI).  RHVoice via speechd-el.

;; Basic UX: less GUI noise.
(tooltip-mode -1)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(setq use-dialog-box nil)
(setq ring-bell-function 'ignore)
;; emacsclient -c with no files: skip "When done with this frame…" in *Messages*.
(setq server-client-instructions nil)

;; UTF-8 everywhere.
(set-language-environment 'UTF-8)
(prefer-coding-system 'utf-8)

;; System clipboard (X11; xsel or xclip in PATH — you have xsel).
(setq select-enable-clipboard t)
(setq select-enable-primary t)
(setq save-interprogram-paste-before-kill t)

;; Package manager.
(require 'package)
(setq package-archives
      '(("gnu"   . "https://elpa.gnu.org/packages/")
        ("melpa" . "https://melpa.org/packages/")))
(package-initialize)

(defun my/ensure-package (pkg)
  "Install PKG if it's not installed."
  (unless (package-installed-p pkg)
    (unless package-archive-contents
      (package-refresh-contents))
    (package-install pkg)))

;; Shell PATH in GUI/daemon Emacs (often narrower than login session).
(my/ensure-package 'exec-path-from-shell)
(require 'exec-path-from-shell)
(exec-path-from-shell-copy-env "PATH")

;; Theme + highlight current line and the active window in splits.
(my/ensure-package 'gruvbox-theme)

(defun my/fix-gruvbox-gnus-face-cycle ()
  "Break gnus news-low face cycle (gruvbox vs Emacs 31 defaults).

Emacs 31: `gnus-group-news-low' inherits `gnus-group-news-low-empty'.
Gruvbox:  `gnus-group-news-low-empty' inherits `gnus-group-news-low'.
Re-applying the theme (C-c C-c) then errors with an inheritance cycle and
aborts the rest of init.el — including .env mode setup."
  (when (and (facep 'gnus-group-news-low)
             (facep 'gnus-group-news-low-empty))
    ;; Same pattern as gnus-group-mail-low / mail-low-empty in gruvbox.
    (set-face-attribute 'gnus-group-news-low-empty nil
                        :inherit 'gnus-group-mail-1-empty)
    (set-face-attribute 'gnus-group-news-low nil
                        :inherit 'gnus-group-mail-1)))

(defun my/load-theme (theme)
  "Load THEME if not already enabled (safe for init.el re-eval)."
  (my/fix-gruvbox-gnus-face-cycle)
  (unless (memq theme custom-enabled-themes)
    (load-theme theme t))
  (my/fix-gruvbox-gnus-face-cycle))

(my/load-theme 'gruvbox-dark-medium)

(global-hl-line-mode 1)
(setq hl-line-sticky-flag t)

;; Active window: blinking bar cursor (does not cover the glyph).  Daemon
;; starts without a display, so color is reapplied on each GUI frame below.
(defconst my/cursor-color "#fbf1c7")
(setq cursor-in-non-selected-windows nil)
(setq cursor-type 'bar)
(setq x-stretch-cursor nil)
(blink-cursor-mode 1)
(setq blink-cursor-delay 0.5)
(setq blink-cursor-interval 0.5)
(add-to-list 'default-frame-alist `(cursor-type . bar))
(add-to-list 'default-frame-alist `(cursor-color . ,my/cursor-color))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(cursor ((t (:background "#fbf1c7"))))
 '(hl-line ((t (:background "#504945" :extend t))))
 '(line-number-current ((t (:foreground "#fbf1c7" :background "#504945" :weight bold))))
 '(mode-line ((t (:background "#504945" :foreground "#fbf1c7" :box (:line-width 3 :color "#fe8019")))))
 '(mode-line-inactive ((t (:background "#282828" :foreground "#665c54" :box (:line-width 1 :color "#3c3836"))))))

(setq display-line-numbers-type 'relative)

(defun my/display-line-numbers-for-file ()
  "Relative line numbers only in buffers visiting a file.
Special buffers (vterm, buffer list, Help, Magit, …) stay unnumbered."
  (if buffer-file-name
      (display-line-numbers-mode 1)
    (display-line-numbers-mode -1)))

(add-hook 'after-change-major-mode-hook #'my/display-line-numbers-for-file)
(window-divider-mode -1)

(defun my/apply-cursor-frame (&optional frame)
  (let ((frame (or frame (selected-frame))))
    (when (display-graphic-p frame)
      (modify-frame-parameters frame '((cursor-type . bar)))
      (set-cursor-color my/cursor-color))))

(defun my/apply-mode-line-settings ()
  "Mode-line icons; also undo legacy prepends from older init versions."
  (my/mode-line--strip-legacy-nerd-icons)
  (setq mode-line-buffer-identification
        '((:eval (my/mode-line-buffer-identification)))))

(defun my/reapply-init-gui-frame (&optional frame)
  "Per-frame GUI settings that desktop frameset restore can override."
  (my/apply-cursor-frame frame))

(defun my/reapply-init-gui-settings ()
  "Reapply global + per-frame GUI init after desktop restore."
  (my/apply-mode-line-settings)
  (dolist (frame (my/desktop-gui-frames))
    (my/reapply-init-gui-frame frame))
  (force-mode-line-update t))

(add-hook 'after-make-frame-functions #'my/reapply-init-gui-frame)
(add-hook 'emacs-startup-hook #'my/reapply-init-gui-settings)

;; File-type icons (Nerd Font glyphs, not emoji).  GUI only.
(my/ensure-package 'nerd-icons)
(my/ensure-package 'nerd-icons-dired)
(my/ensure-package 'nerd-icons-ibuffer)
(require 'nerd-icons)
(require 'nerd-icons-dired)
(require 'nerd-icons-ibuffer)

(setq nerd-icons-font-family "FiraCode Nerd Font")

(defun my/nerd-icons-file-icon (&optional file)
  "File-extension icon for FILE or the current buffer (GUI only)."
  (when (display-graphic-p)
    (nerd-icons-icon-for-file
     (or file
         (and buffer-file-name (file-name-nondirectory buffer-file-name))
         (buffer-name))
     :height 0.9 :v-adjust 0.05)))

(defun my/mode-line--strip-legacy-nerd-icons ()
  "Drop stacked nerd-icon prepends left by older init.el versions."
  (let ((legacy '(:eval (my/mode-line-buffer-icon)))
        (fmt (default-value 'mode-line-format)))
    (while (and fmt (equal (car fmt) legacy))
      (setq fmt (cdr fmt)))
    (setq-default mode-line-format fmt)))

(defun my/mode-line-buffer-identification ()
  "Buffer name with a single file-extension icon (GUI only)."
  (let ((name (buffer-name)))
    (if-let ((icon (my/nerd-icons-file-icon)))
        (concat icon " " (propertize name 'face 'mode-line-buffer-id))
      (propertize name 'face 'mode-line-buffer-id))))

(my/apply-mode-line-settings)

(add-hook 'dired-mode-hook #'nerd-icons-dired-mode)
(add-hook 'ibuffer-mode-hook #'nerd-icons-ibuffer-mode)

(defun my/nerd-icons-buffer-menu--inject-icons (&rest _)
  (when (derived-mode-p 'Buffer-menu-mode)
    (mapc (lambda (entry)
            (let ((buf (car entry))
                  (vec (cadr entry)))
              (when (buffer-live-p buf)
                (with-current-buffer buf
                  (let ((icon (my/nerd-icons-file-icon)))
                    (when icon
                      (aset vec 3 (concat icon " " (aref vec 3)))))))))
          tabulated-list-entries)))

(advice-add 'list-buffers--refresh :after #'my/nerd-icons-buffer-menu--inject-icons)

;; Size for new GUI frames.  Must be set before a display exists (emacs
;; --fg-daemon loads init with (display-graphic-p) nil).
(defun my/tiling-wm-p ()
  "Non-nil when cortile (or EMACS_TILING_WM) tiles outer Emacs frames."
  (or (getenv "EMACS_TILING_WM")
      (and (executable-find "pgrep")
           (= 0 (call-process "pgrep" nil nil nil "-x" "cortile")))))

(unless (my/tiling-wm-p)
  (add-to-list 'default-frame-alist '(width . 140))
  (add-to-list 'default-frame-alist '(height . 40)))

(defun my/tiling-wm--inhibit-frame-geometry (orig &rest args)
  "Let cortile own position/size; Emacs only manages internal windows."
  (unless (my/tiling-wm-p)
    (apply orig args)))

(dolist (fn '(set-frame-position set-frame-size adjust-frame-size))
  (advice-add fn :around #'my/tiling-wm--inhibit-frame-geometry))

(defun my/tiling-wm--frame-hook (frame)
  (when (my/tiling-wm-p)
    (modify-frame-parameters frame '((fullscreen . nil)))))
(add-hook 'after-make-frame-functions #'my/tiling-wm--frame-hook)

;; Hint: available keys after a prefix (C-x, C-c, …). Not M-x command names.
(my/ensure-package 'which-key)
(require 'which-key)
(which-key-mode 1)
(setq which-key-idle-delay 0.8)
;; Drop legacy which-key advice from older init versions.
(dolist (sym '(my/which-key--side-window-margin my/which-key--pad-side-window
                my/which-key--side-window-taller my/which-key--nudge-bottom-gap
                my/which-key--no-bottom-divider))
  (advice-remove 'which-key--show-buffer-side-window sym))
;; Let which-key page C-h bindings: C-h C-h n / C-h C-h p (not help-for-help).
(global-unset-key (kbd "C-h C-h"))

;; Speech Dispatcher: RHVoice + Russian language.
;; Open only with speechd-speak-mode — startup speechd-open kept RHVoice on
;; PulseAudio and caused speaker pops when Alt+Tab focused Emacs.
(my/ensure-package 'speechd-el)
(require 'speechd)

(setq speechd-language "ru")

(defvar my/speechd-configured nil
  "Non-nil after `my/speechd-ensure' configured RHVoice.")

(defun my/speechd-ensure ()
  "Connect to Speech Dispatcher and configure RHVoice (once)."
  (unless my/speechd-configured
    (ignore-errors
      (speechd-open nil :quiet t :force-reopen t)
      (speechd-set-output-module "rhvoice")
      (speechd-set-language speechd-language)
      (speechd-set-rate 40)
      (speechd-set-pitch 30)
      (speechd-set-volume 100)
      (speechd-set-synthesizer-voice "Aleksandr")
      (setq my/speechd-configured t))))

(defun my/speechd-on-speak-mode ()
  (when speechd-speak-mode
    (my/speechd-ensure)))

;; Optional: enable a "talking Emacs" minor mode.
;; Toggle with: M-x speechd-speak-mode
(require 'speechd-speak)
(add-hook 'speechd-speak-mode-hook #'my/speechd-on-speak-mode)
;; Uncomment if you want it always on:
;; (speechd-speak-mode 1)
;; (speechd-speak)   ;; включает global-speechd-speak-mode

;; Terminal: vterm (libvterm; native module built on first require).
(my/ensure-package 'vterm)
(require 'vterm)
(setq vterm-max-scrollback 10000)
(setq vterm-shell (or (getenv "SHELL") "/bin/bash"))

(defun my/vterm-setup-cursor ()
  "Orange box cursor in vterm.

Bash/readline sends DECSCUSR (bar) and libvterm overrides `cursor-type';
`my/vterm--filter-enforce-cursor' keeps box after each redraw."
  (face-remap-add-relative 'cursor '(:background "#fe8019"))
  (setq cursor-type 'box)
  (run-with-timer 0.2 nil
                  (lambda ()
                    (when (derived-mode-p 'vterm-mode)
                      (vterm-send-string "\e[2 q")))))

(defun my/vterm--filter-enforce-cursor (orig proc input)
  (let ((buf (process-buffer proc)))
    (prog1 (funcall orig proc input)
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (unless (eq cursor-type 'box)
            (setq cursor-type 'box)))))))

(advice-add 'vterm--filter :around #'my/vterm--filter-enforce-cursor)

(add-hook 'vterm-mode-hook #'my/vterm-setup-cursor)

(defun my/vterm ()
  "Open a vterm in `default-directory'."
  (interactive)
  (vterm default-directory))

(global-set-key (kbd "C-c t") #'my/vterm)

;; .env / .env.* / .env.dev.example — like Vim `ft=conf` (# comments, KEY=val).
;; Use conf-unix-mode, not conf-mode: set-auto-mode binds delay-mode-hooks, so
;; conf-mode's advice skips conf--guess-mode and leaves bare Conf[?] (; comments).
(defconst my/env-file-name-re "\\.env\\(?:\\..*\\)?\\'"
  "Regexp for dotenv-style file names (matched against `buffer-file-name').")

(add-to-list 'auto-mode-alist `(,my/env-file-name-re . conf-unix-mode))

(defun my/env-apply-conf-mode (&rest _)
  "Apply `conf-unix-mode' to .env* buffers (desktop may restore fundamental-mode)."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (and buffer-file-name
                 (string-match-p my/env-file-name-re buffer-file-name)
                 (not (derived-mode-p 'conf-mode)))
        (conf-unix-mode)))))

;; Desktop restores the major mode that was saved; old sessions have fundamental.
(add-hook 'desktop-after-read-hook #'my/env-apply-conf-mode)
;; Fix already-open buffers when init.el is re-evaluated (C-c C-c).
(my/env-apply-conf-mode)

;; Docker: Dockerfiles, compose YAML, container UI (M-x docker), TRAMP (/docker:…).
(my/ensure-package 'dockerfile-mode)
(require 'dockerfile-mode)

(my/ensure-package 'docker-compose-mode)
(require 'docker-compose-mode)
(add-to-list 'auto-mode-alist '("\\`compose\\.ya?ml\\'" . docker-compose-mode))

(my/ensure-package 'docker)
(require 'docker)

(require 'tramp-container)

;; PICO-8: .p8 cartridges (Kaali/pico8-mode + porcow/shanecelis/broquaint patches).
(my/ensure-package 'lua-mode)
(add-to-list 'load-path (expand-file-name "pico8-mode" user-emacs-directory))
(require 'pico8-mode)
(setq pico8-use-font t)
(add-to-list 'auto-mode-alist '("\\.p8\\'" . pico8-mode))
(when-let ((exe (executable-find "pico8")))
  (setq pico8-executable-path (file-truename exe))
  (let ((manual (expand-file-name "pico-8_manual.txt"
                                  (file-name-directory pico8-executable-path))))
    (when (file-readable-p manual)
      (setq pico8-documentation-file manual))))

;; Markdown: gfm-mode for .md.  Browser: C-c C-c p; live: C-c C-c l.
(defvar my/markdown-preview-css
  (expand-file-name "markdown/preview.css" user-emacs-directory))

(defcustom my/markdown-browser-preview-format 'html
  "Default format for `my/markdown-preview-browser' (C-c C-c p).
`html' runs markdown_py and opens styled HTML; `markdown' opens the
.md file so a browser extension can render it.  Prefix (C-u) inverts
the choice for one call."
  :type '(choice (const :tag "HTML (markdown_py + preview.css)" html)
                 (const :tag "Markdown (browser extension)" markdown))
  :group 'markdown)

;; Desktop default browser via xdg-open.  browse-url-xdg-open passes file://
;; URLs; on MATE that often opens Firefox instead of the MIME default (Vivaldi).
(require 'browse-url)

(defun my/browse-url--local-path (url)
  "Return a filesystem path for file:// URL, or URL unchanged otherwise."
  (if (string-prefix-p "file://" url)
      (url-unhex-string
       (if (string-prefix-p "file://localhost" url)
           (substring url (length "file://localhost"))
         (substring url (length "file://"))))
    url))

(defun my/browse-url-open (url &rest _args)
  "Open URL in Vivaldi (fallback: xdg-open)."
  (let* ((display (or (frame-parameter nil 'display) (getenv "DISPLAY")))
         (target (my/browse-url--local-path url))
         (browser (or (executable-find "vivaldi-stable")
                      (executable-find "vivaldi"))))
    (when display (setenv "DISPLAY" display))
    (if browser
        (start-process "browser" nil browser target)
      (call-process "xdg-open" nil 0 nil target))))

(setq browse-url-browser-function #'my/browse-url-open)
(setq browse-url-secondary-browser-function #'my/browse-url-open)

;; markdown_py without -x tables leaves pipe tables as plain text.
(setq markdown-command '("markdown_py" "-x" "tables" "-x" "fenced_code"))
(setq markdown-css-paths (list my/markdown-preview-css))

(my/ensure-package 'markdown-mode)
(require 'markdown-mode)
(add-to-list 'auto-mode-alist '("\\.md\\'" . gfm-mode))
(add-to-list 'auto-mode-alist '("\\.markdown\\'" . gfm-mode))

;; Live preview uses eww/shr, not the browser — shr ignores most CSS.
(setq shr-max-width nil)
(setq shr-width nil)
(setq shr-fill-text nil)

(defun my/eww-wrap-display ()
  "Wrap long lines at the window edge in eww (markdown live preview)."
  (setq-local truncate-lines nil)
  (visual-line-mode 1)
  (when (fboundp 'visual-wrap-prefix-mode)
    (visual-wrap-prefix-mode 1)))

(add-hook 'eww-mode-hook #'my/eww-wrap-display)

(defun my/markdown-preview-markdown ()
  "Open the buffer as .md in the browser (for a Markdown extension)."
  (interactive)
  (let ((file
         (if (and buffer-file-name (not (buffer-modified-p)))
             buffer-file-name
           (let ((f (make-temp-file "md-preview-" nil ".md")))
             (write-region (point-min) (point-max) f nil 'no-message)
             f))))
    (my/browse-url-open file)))

(defun my/markdown-preview-browser (&optional output-buffer-name)
  "Preview in browser as HTML or Markdown.
See `my/markdown-browser-preview-format'; C-u inverts the choice."
  (interactive "P")
  (let ((as-markdown (if current-prefix-arg
                         (eq my/markdown-browser-preview-format 'html)
                       (eq my/markdown-browser-preview-format 'markdown))))
    (if as-markdown
        (my/markdown-preview-markdown)
      (markdown-preview output-buffer-name))))

(with-eval-after-load 'markdown-mode
  (define-key markdown-mode-map (kbd "C-c C-c p") #'my/markdown-preview-browser)
  (define-key gfm-mode-map (kbd "C-c C-c p") #'my/markdown-preview-browser))

;; Git / projects / Python.
(require 'project)
(setq vc-follow-symlinks t)

(defun my/delete-shorthand-bytecode ()
  "Delete .elc for packages that use `read-symbol-shorthands' (`$').

Byte-compilation does not honor shorthands, so compiled code references
bare `$' and Magit/Transient fail with \"void-variable $\"."
  (dolist (prefix '("magit" "transient" "cond-let"))
    (dolist (dir (directory-files package-user-dir t (concat "\\`" prefix)))
      (dolist (elc (directory-files dir t "\\.elc\\'"))
        (delete-file elc)))))

(my/ensure-package 'magit)
(my/delete-shorthand-bytecode)
(require 'magit)
(global-set-key (kbd "C-x g") #'magit-status)

(defun my/magit-project ()
  "Choose a project root, then open Magit there."
  (interactive)
  (when-let ((dir (project-prompt-project-dir)))
    (let ((default-directory (expand-file-name dir)))
      (when-let ((pr (project-current t)))
        (project-remember-project pr)
        (magit-project-status)))))

;; C-x g: Magit for the current buffer's repo.  C-c g: pick project first.
(global-set-key (kbd "C-c g") #'my/magit-project)

;; C-x p p: after choosing a project, g opens Magit (f = find file, …).
(setq project-switch-commands
      '((magit-project-status "Magit" ?g)
        (project-find-file "Find file")
        (project-find-regexp "Find regexp")
        (project-find-dir "Find directory")
        (project-vc-dir "VC-Dir")
        (project-eshell "Eshell")
        (project-any-command "Other")))

;; Git change markers in the fringe while editing (diff-hl).
(my/ensure-package 'diff-hl)
(require 'diff-hl)
(global-diff-hl-mode 1)
(add-hook 'after-save-hook #'diff-hl-update)
(with-eval-after-load 'magit
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh))

(defvar my/diff-hl--update-timer nil
  "Idle timer for debounced `diff-hl-update'.")

(defun my/diff-hl-update-debounced (&rest _)
  "Refresh fringe markers shortly after buffer edits."
  (when (timerp my/diff-hl--update-timer)
    (cancel-timer my/diff-hl--update-timer))
  (setq my/diff-hl--update-timer
        (run-with-idle-timer 0.35 nil #'diff-hl-update)))

(add-hook 'diff-hl-mode-hook
          (lambda ()
            (add-hook 'after-change-functions #'my/diff-hl-update-debounced nil t)))

(setq python-indent-offset 4)
(setq-default indent-tabs-mode nil)

(defun my/pylsp-executable ()
  "Return real pylsp binary, not a pyenv shim with local .python-version."
  (let* ((pyenv-root (or (getenv "PYENV_ROOT")
                         (expand-file-name "~/.pyenv")))
         (candidates
          (list (expand-file-name "versions/3.14-dev/envs/global-venv/bin/pylsp"
                                  pyenv-root)
                (expand-file-name "versions/global-venv/bin/pylsp" pyenv-root)
                (expand-file-name "~/.local/bin/pylsp"))))
    (or (seq-find #'file-executable-p candidates)
        (let ((default-directory (getenv "HOME")))
          (executable-find "pylsp")))))

(defun my/python-project-venv ()
  "Return project `.venv' or `venv' directory when present."
  (when-let ((root (locate-dominating-file
                    default-directory
                    (lambda (dir)
                      (or (file-directory-p (expand-file-name ".venv" dir))
                          (file-directory-p (expand-file-name "venv" dir)))))))
    (or (and (file-directory-p (expand-file-name ".venv" root))
             (expand-file-name ".venv" root))
        (expand-file-name "venv" root))))

(eval-when-compile (require 'eglot))

(defun my/eglot-configure-python-server ()
  "Register pylsp for Python modes; bypass pyenv shims."
  (when-let ((pylsp (my/pylsp-executable)))
    (require 'eglot)
    (setq eglot-server-programs
          (cons `((python-mode python-ts-mode) ,pylsp)
                (cl-remove-if
                 (lambda (entry)
                   (and (listp (car entry))
                        (or (memq 'python-mode (car entry))
                            (memq 'python-ts-mode (car entry)))))
                 eglot-server-programs)))))

(defun my/eglot-python-workspace-config ()
  "Point pylsp/jedi at the project virtualenv when one exists."
  (when (derived-mode-p 'python-mode 'python-ts-mode)
    (when-let ((venv (my/python-project-venv)))
      (setq eglot-workspace-configuration
            `(:pylsp (:plugins (:jedi (:environment ,venv))))))))

(defun my/eglot-ensure ()
  "Start Eglot when a Python LSP server is available."
  (cond ((my/pylsp-executable)
         (my/eglot-configure-python-server)
         (eglot-ensure))
        ((let ((default-directory (getenv "HOME")))
           (or (executable-find "pyright-langserver")
               (executable-find "pyright")))
         (require 'eglot)
         (eglot-ensure))))

(add-hook 'eglot-managed-mode-hook #'my/eglot-python-workspace-config)

(add-hook 'python-mode-hook #'my/eglot-ensure)
(add-hook 'python-ts-mode-hook #'my/eglot-ensure)

;; Persistence: auto-save, backups, session restore, cursor & history.
(setq auto-save-default t)
(setq auto-save-timeout 5)
(setq auto-save-interval 200)

(setq make-backup-files t)
(setq version-control t)
(setq delete-old-versions t)
(setq kept-old-versions 5)

;; Desktop session: ~/.emacs.d/.emacs.desktop
;;
;; Restart (daemon + desktop restore):
;;   systemctl --user restart emacs && emacsclient -c
;; Reload init.el only (no daemon restart): C-c C-c in init.el, or
;;   emacsclient -e '(load user-init-file t t)'
;; Avoid M-x save-buffers-kill-emacs — it stops the daemon like restart, but
;; is easier to hit with desktop-save-mode off or a broken init.el.
;;
;; With `emacs --daemon', enable desktop-save on the first emacsclient -c frame.
;; desktop-read must run with that client frame *selected*; otherwise
;; `desktop-restoring-frameset-p' is nil and only *scratch* comes back.
(setq desktop-path (list user-emacs-directory))
(setq desktop-prompt-restore nil)
(setq desktop-save t)
(setq desktop-autosave-interval 300)
;; Prefer the live emacsclient display over a stale saved one.
(setq desktop-restore-in-current-display t)
;; Daemon + emacsclient: reuse scratch frame breaks frameset restore (nil markers).
(setq desktop-restore-reuses-frames (if (daemonp) nil t))
(setq desktop-buffers-not-to-save
      (concat "\\` \\|"
              (regexp-opt '("*scratch*" "*Messages*" "*Warnings*"
                             "*Completions*" "*Help*" "*Backtrace*")
                          t)))

;; Under daemon, frameset.el always honors the saved `display' parameter and
;; ignores `desktop-restore-in-current-display'.  On Wayland sessions an X11
;; Emacs can persist (display . "wayland-0"), which then fails restore with
;; "Don't know how to interpret display \"wayland-0\"".
(defun my/wayland-socket-display-p (name)
  "Non-nil when NAME looks like a Wayland socket (not an X display)."
  (and (stringp name) (string-match-p "\\`wayland-[0-9]+\\'" name)))

(defun my/frameset-keep-original-display-p (orig force-display)
  "Honor FORCE-DISPLAY even when running as a daemon."
  (if (and (daemonp) force-display)
      nil
    (funcall orig force-display)))

(defun my/frameset-filter-display (current _filtered _parameters saving)
  "Rewrite Wayland socket names to a usable X display on X11 builds."
  (let ((val (cdr current)))
    (if (and (my/wayland-socket-display-p val) (not (featurep 'pgtk)))
        (let ((x (or (frame-parameter nil 'display)
                     (getenv "DISPLAY"))))
          (when (and x (not (my/wayland-socket-display-p x)))
            (cons 'display x)))
      t)))

(with-eval-after-load 'frameset
  (advice-add #'frameset-keep-original-display-p :around
              #'my/frameset-keep-original-display-p)
  (setf (alist-get 'display frameset-filter-alist)
        #'my/frameset-filter-display))

(defvar my/desktop--enabled nil)
(defvar my/desktop--after-restored nil)
(defvar my/desktop--restore-ok nil)

(defun my/desktop-buffer-worth-saving-p (buf)
  "Non-nil when BUF is worth a desktop snapshot (not just *scratch*)."
  (with-current-buffer buf
    (or (buffer-file-name)
        (and (derived-mode-p 'dired-mode) dired-directory)
        (derived-mode-p 'magit-mode)
        (derived-mode-p 'vterm-mode))))

(defun my/desktop-save-ok-p ()
  "True when at least one visible window shows a meaningful buffer."
  (seq-find (lambda (buf)
              (and (get-buffer-window buf t)
                   (my/desktop-buffer-worth-saving-p buf)))
            (buffer-list)))

(defun my/desktop-save-guard (orig dir &optional release only-if-changed version)
  "Do not overwrite .emacs.desktop with scratch/*Warnings* garbage."
  (if (my/desktop-save-ok-p)
      (apply orig dir release only-if-changed version)
    (message "Desktop save skipped (no file/dired/magit/vterm in windows)")))

(defun my/desktop-clamp-frame-positions ()
  "Keep saved frame coords on-screen (avoids `left + -10' in .emacs.desktop)."
  (unless (my/tiling-wm-p)
    (dolist (frame (my/desktop-gui-frames))
      (let* ((pos (frame-position frame))
             (left (car pos))
             (top (cdr pos)))
        (when (or (not (numberp left)) (< left 0) (>= left 1600)
                  (not (numberp top)) (< top 0))
          (set-frame-position frame (max 0 (if (numberp left) left 100))
                              (max 0 (if (numberp top) top 100))))))))

(with-eval-after-load 'desktop
  (advice-add #'desktop-save :around #'my/desktop-save-guard)
  (add-hook 'desktop-save-hook #'my/desktop-clamp-frame-positions))

(defun my/desktop-gui-frame-p (frame)
  "Non-terminal frame (emacsclient GUI or restored desktop frame)."
  (and frame (frame-live-p frame)
       (not (eq (frame-terminal frame) 'terminal))))

(defun my/desktop-show-frame (frame)
  (when (my/desktop-gui-frame-p frame)
    (modify-frame-parameters frame '((visibility . t)))
    (unless (my/tiling-wm-p)
      (raise-frame frame))))

(defun my/desktop-show-frame-ready (frame)
  "Show FRAME on the next idle tick, after splits and faces are painted."
  (run-with-idle-timer
   0 nil
   (lambda ()
     (when (frame-live-p frame)
       (select-frame frame)
       (redisplay t)
       (my/desktop-show-frame frame)))))

(defun my/desktop-gui-frames ()
  (seq-filter #'my/desktop-gui-frame-p (frame-list)))

(defun my/desktop-best-gui-frame (frames)
  "Return the GUI frame with the most windows."
  (let (best best-n)
    (dolist (frame frames)
      (let ((n (length (window-list frame))))
        (when (> n (or best-n 0))
          (setq best frame best-n n))))
    (or best (car frames))))

(defun my/desktop-scratch-frame-p (frame)
  (and frame
       (= (length (window-list frame)) 1)
       (string= (buffer-name (window-buffer (frame-root-window frame)))
                "*scratch*")))

(defun my/desktop-frames-on-screen ()
  "Move GUI frames onto the visible display (desktop can save off-screen coords)."
  (my/desktop-clamp-frame-positions))

(defun my/desktop-after-restore ()
  "Raise the restored GUI frame; drop leftover tty/scratch frames."
  (unless my/desktop--after-restored
    (setq my/desktop--after-restored t)
    (my/desktop-frames-on-screen)
    (dolist (frame (frame-list))
      (when (and (not (display-graphic-p frame))
                 (not (eq (frame-parameter frame 'minibuffer) 'only)))
        (ignore-errors (delete-frame frame))))
    (let* ((gui-frames (my/desktop-gui-frames))
           (best-frame (my/desktop-best-gui-frame gui-frames)))
      (dolist (frame gui-frames)
        (when (and (not (eq frame best-frame))
                   (my/desktop-scratch-frame-p frame))
          (ignore-errors (delete-frame frame))))
      (when (my/tiling-wm-p)
        (dolist (frame gui-frames)
          (modify-frame-parameters frame '((fullscreen . nil)))))
      (my/reapply-init-gui-settings)
      (when best-frame
        (ignore-errors
          (my/desktop-show-frame-ready best-frame)))
      (setq my/desktop--restore-ok t))))

(defun my/desktop-enable-save-mode ()
  "Turn on desktop autosave and save-on-exit for this daemon session."
  (desktop-save-mode 1))

(defun my/desktop-file ()
  (expand-file-name ".emacs.desktop" user-emacs-directory))

(defun my/desktop-clear-stale-lock ()
  "Remove a leftover lock from a dead Emacs process."
  (let ((lockfile (expand-file-name ".emacs.desktop.lock" user-emacs-directory)))
    (when (file-exists-p lockfile)
      (let ((owner (ignore-errors
                     (with-temp-buffer
                       (insert-file-contents lockfile)
                       (string-to-number (string-trim (buffer-string)))))))
        (unless (and owner (= owner (emacs-pid)))
          (delete-file lockfile))))))

(defun my/desktop-purge-zombie-frames ()
  "Drop hidden client scratch frames left by failed restore attempts."
  (dolist (frame (my/desktop-gui-frames))
    (when (and (frame-parameter frame 'client)
               (not (frame-visible-p frame))
               (my/desktop-scratch-frame-p frame))
      (ignore-errors (delete-frame frame)))))

(defun my/desktop-enable (&optional client-frame)
  (unless my/desktop--enabled
    (setq my/desktop--enabled t)
    (setq my/desktop--after-restored nil)
    (setq my/desktop--restore-ok nil)
    (my/desktop-clear-stale-lock)
    (my/desktop-purge-zombie-frames)
    ;; Off only during desktop-read; on again at the end (even if restore failed).
    (setq desktop-save-mode nil)
    (add-hook 'desktop-after-read-hook #'my/desktop-after-restore)
    (when client-frame
      (select-frame client-frame))
    (if (file-exists-p (my/desktop-file))
        (unwind-protect
            (let ((inhibit-redisplay t))
              (condition-case err
                  (desktop-read)
                (error
                 (message "Desktop restore failed: %S (keeping previous .emacs.desktop)"
                          err)
                 (ignore-errors (desktop-clear))
                 (setq my/desktop--after-restored t))))
          (unless my/desktop--after-restored
            (my/desktop-show-frame-ready (or client-frame (selected-frame)))))
      (when client-frame
        (my/desktop-show-frame-ready client-frame)))
    (my/desktop-enable-save-mode)))

(defun my/desktop-enable-server-frame ()
  "First emacsclient GUI frame restores desktop; later ones show immediately."
  (let ((frame (selected-frame)))
    (when (my/desktop-gui-frame-p frame)
      (if my/desktop--enabled
          (my/desktop-show-frame-ready frame)
        (my/desktop-enable frame)))))

(with-eval-after-load 'server
  (setq server-raise-frame (not (my/tiling-wm-p)))
  (add-hook 'server-after-make-frame-hook #'my/desktop-enable-server-frame))
(when (and (display-graphic-p) (not noninteractive) (not (daemonp)))
  (my/desktop-enable))

(save-place-mode 1)

(savehist-mode 1)
(setq history-length 1000)

(recentf-mode 1)
(setq recentf-max-saved-items 200)

(setq confirm-kill-processes t)

;; Org (built-in).
(require 'org)

(setq org-directory (expand-file-name "~/org"))
(setq org-default-notes-file (expand-file-name "inbox.org" org-directory))
;; All *.org in ~/org/ (inbox.org, projects.org, …) — otherwise agenda is empty.
(setq org-agenda-files (list org-directory))
(setq org-ellipsis "…")
(setq org-hide-leading-stars t)
(setq org-startup-indented t)

(org-babel-do-load-languages
 'org-babel-load-languages
 '((emacs-lisp . t)
   (python . t)))

(defun my/org-inbox ()
  "Open Org inbox (create ~/org if needed)."
  (interactive)
  (make-directory org-directory t)
  (find-file org-default-notes-file))

(defun my/org-notes ()
  "Open Org notes (~/org/notes.org)."
  (interactive)
  (make-directory org-directory t)
  (find-file (expand-file-name "notes.org" org-directory)))

(defun my/org-agenda-todos ()
  "Org agenda: all TODO items (C-c a t)."
  (interactive)
  (org-agenda nil "t"))

;; Windows and buffers — home row under C-c (no arrow keys).
;; h/j/k/l: move between splits (like vim C-w).  n/p: prev/next buffer.  [/]: undo window layout.
(require 'windmove)
(setq windmove-wrap-around t)
(winner-mode 1)

(global-set-key (kbd "C-c h") #'windmove-left)
(global-set-key (kbd "C-c j") #'windmove-down)
(global-set-key (kbd "C-c k") #'windmove-up)
(global-set-key (kbd "C-c l") #'windmove-right)
(global-set-key (kbd "C-c n") #'next-buffer)
(global-set-key (kbd "C-c p") #'previous-buffer)
(global-set-key (kbd "C-c [") #'winner-undo)
(global-set-key (kbd "C-c ]") #'winner-redo)

(global-set-key (kbd "C-c o") #'my/org-notes)
(global-set-key (kbd "C-c i") #'my/org-inbox)
(global-set-key (kbd "C-c a t") #'my/org-agenda-todos)
(global-set-key (kbd "C-c r") #'recentf-open-files)

;; comment-line on C-c ; toggles line comments (C-u 3 affects three lines).
;; With prefix: C-u 3 C-c ; comments three lines.
(global-set-key (kbd "C-c ;") #'comment-line)
;; Built-in M-; (`comment-dwim'): region if highlighted, else toggles current line.

;; Convenience: open this config quickly.
(defun my/init-el-p ()
  "Non-nil when the current buffer is user-init-file."
  (and buffer-file-name
       (equal (expand-file-name buffer-file-name)
              (expand-file-name user-init-file))))

(defun my/purge-init-elc ()
  "Remove init.elc so restart always loads the init.el we just evaluated."
  (let ((elc (concat user-init-file "c")))
    (when (file-exists-p elc)
      (delete-file elc))
    (message "init.el evaluated (init.elc removed; restart loads source)")))

(defun my/init-el-remove-eval-advice ()
  "Remove legacy/broken advice on `eval-buffer'."
  (dolist (sym '(my/eval-init-el-byte-compile
                  my/eval-init-el--around
                  ad-Advice-eval-buffer))
    (advice-remove 'eval-buffer sym)))

(defun my/init-el-check-syntax ()
  "Signal an error when user-init-file does not parse."
  (with-temp-buffer
    (insert-file-contents user-init-file)
    (goto-char (point-min))
    (skip-chars-forward " \t\n\r")
    (while (< (point) (point-max))
      (read (current-buffer))
      (skip-chars-forward " \t\n\r"))))

(defun my/eval-init-el ()
  "Save and evaluate init.el; drop init.elc so restart matches the buffer."
  (interactive)
  (unless (my/init-el-p)
    (user-error "Not in %s" user-init-file))
  (my/init-el-remove-eval-advice)
  (condition-case err
      (my/init-el-check-syntax)
    (error
      (user-error "init.el syntax error (not evaluated): %S" err)))
  (condition-case err
      (progn
        (save-buffer)
        (eval-buffer nil nil nil t)
        (my/purge-init-elc))
    (error
     (message "init.el eval failed: %S" err)
     (signal (car err) (cdr err)))))

(defun my/init-el-setup-local-keys ()
  (when (my/init-el-p)
    (local-set-key (kbd "C-c C-c") #'my/eval-init-el)))

(add-hook 'emacs-lisp-mode-hook #'my/init-el-setup-local-keys)
(my/init-el-remove-eval-advice)

(defun my/open-init-file ()
  (interactive)
  (find-file user-init-file))
(global-set-key (kbd "C-c e") #'my/open-init-file)
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages nil))

;; Личные настройки (не в git): скопируйте local.el.example -> local.el
(load (expand-file-name "local.el" user-emacs-directory) t t)
