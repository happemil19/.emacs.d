;;; init.el --- Minimal Emacs config (loads lisp/)  -*- lexical-binding: t; -*-

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


;; Modular config under lisp/.  `load' (not require) so C-c C-c on init.el
;; reloads modules after edits.
(defun my/load-lisp (name)
  "Load `lisp/NAME.el' from `user-emacs-directory'."
  (load (expand-file-name name (expand-file-name "lisp" user-emacs-directory))
        nil nil nil))

(my/load-lisp "ui")


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

(my/load-lisp "langs")

(my/load-lisp "git")

;; Persistence: auto-save, backups, session restore, cursor & history.
(setq auto-save-default t)
(setq auto-save-timeout 5)
(setq auto-save-interval 200)

(setq make-backup-files t)
(setq version-control t)
(setq delete-old-versions t)
(setq kept-old-versions 5)

(my/load-lisp "desktop")

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

;; Two workflows: classic TODO|DONE, and an extended project chain.
;; Org picks the sequence by the keyword already on the headline.
(setq org-todo-keywords
      '((sequence "TODO(t)" "|" "DONE(d)" "CANCELED(c)")
        (sequence "NEW(n)" "WORKING_ON(w)" "TESTING(e)" "WAITING_FOR_DEPLOY(a)" "NEED_INFO(i)" "|"
                  "RESOLVED(r)" "CLOSED(o)" "CANCELED(x)")))
(setq org-todo-keyword-faces
      '(("TODO"               . (:foreground "red" :weight bold))
        ("DONE"               . (:foreground "green" :weight bold))
        ("NEW"                . (:foreground "red" :weight bold))
        ("WORKING_ON"         . (:foreground "orange" :weight bold))
        ("TESTING"            . (:foreground "goldenrod" :weight bold))
        ("WAITING_FOR_DEPLOY" . (:foreground "cyan" :weight bold))
        ("NEED_INFO"          . (:foreground "magenta" :weight bold))
        ("RESOLVED"           . (:foreground "green" :weight bold))
        ("CLOSED"             . (:foreground "green" :weight bold))
        ("CANCELED"           . (:foreground "gray" :weight bold))))

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
;; h/j/k/l: move between splits (like vim C-w).
;; n/p: next/previous buffer in the current project (or the non-project group).
;; [/]: undo window layout.
(require 'windmove)
(setq windmove-wrap-around t)
(winner-mode 1)

(global-set-key (kbd "C-c h") #'windmove-left)
(global-set-key (kbd "C-c j") #'windmove-down)
(global-set-key (kbd "C-c k") #'windmove-up)
(global-set-key (kbd "C-c l") #'windmove-right)
(global-set-key (kbd "C-c n") #'my/next-buffer-in-context)
(global-set-key (kbd "C-c p") #'my/previous-buffer-in-context)
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

;; Buffer display toggles (local): whitespace / line wrap.
;; Tabs, trailing spaces, and visible space/tab marks — not the full noisy set.
(setq whitespace-style '(face tabs trailing space-mark tab-mark))
;; Nowrap by default; wrap per buffer with C-c W (`toggle-truncate-lines').
;; eww markdown preview still enables wrap via `my/eww-wrap-display'.
(setq-default truncate-lines t)
(global-set-key (kbd "C-c w") #'whitespace-mode)
(global-set-key (kbd "C-c W") #'toggle-truncate-lines)

;; Convenience: open this config quickly.
(defun my/init-el-p ()
  "Non-nil when the current buffer is user-init-file."
  (and buffer-file-name
       (equal (expand-file-name buffer-file-name)
              (expand-file-name user-init-file))))

(defun my/lisp-config-el-p ()
  "Non-nil when the current buffer is a file under `lisp/'."
  (and buffer-file-name
       (string-prefix-p
        (expand-file-name "lisp/" user-emacs-directory)
        (expand-file-name buffer-file-name))))

(defun my/config-el-p ()
  "Non-nil when the current buffer is init.el or a lisp/ module."
  (or (my/init-el-p) (my/lisp-config-el-p)))

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

(defun my/config-el-check-syntax ()
  "Signal an error when the current config file does not parse."
  (let ((file (buffer-file-name)))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (skip-chars-forward " \t\n\r")
      (while (< (point) (point-max))
        (read (current-buffer))
        (skip-chars-forward " \t\n\r")))))

(defun my/eval-init-el ()
  "Save and evaluate the current config file (init.el or lisp/*.el).

Evaluating init.el reloads modules via `my/load-lisp'.  Evaluating a
module only re-runs that file.  Drops init.elc after a successful init
reload so restart matches source."
  (interactive)
  (unless (my/config-el-p)
    (user-error "Not in init.el or lisp/*.el"))
  (my/init-el-remove-eval-advice)
  (condition-case err
      (my/config-el-check-syntax)
    (error
     (user-error "Config syntax error (not evaluated): %S" err)))
  (condition-case err
      (progn
        (save-buffer)
        (eval-buffer nil nil nil t)
        (when (my/init-el-p)
          (my/purge-init-elc))
        (message "Evaluated %s" (file-name-nondirectory (buffer-file-name))))
    (error
     (message "Config eval failed: %S" err)
     (signal (car err) (cdr err)))))

(defun my/init-el-setup-local-keys ()
  (when (my/config-el-p)
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
 '(package-selected-packages
   '(consult diff-hl docker docker-compose-mode dockerfile-mode eglot
             exec-path-from-shell go-mode gruvbox-theme lua-mode magit
             markdown-mode nerd-icons-dired nerd-icons-ibuffer
             speechd-el vertico vterm)))

;; Личные настройки (не в git): скопируйте local.el.example -> local.el
(load (expand-file-name "local.el" user-emacs-directory) t t)
