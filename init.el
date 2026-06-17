;;; init.el --- Minimal Emacs config  -*- lexical-binding: t; -*-

;; Goal: keep the configuration as small and reproducible as possible.
;; We keep Speech Dispatcher (RHVoice) support as the primary feature.

;; Basic UX: less GUI noise.
(tooltip-mode -1)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(setq use-dialog-box nil)
(setq ring-bell-function 'ignore)

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

;; Theme + highlight current line (cursor position is easier to see).
(my/ensure-package 'gruvbox-theme)
(load-theme 'gruvbox-dark-medium t)

(global-hl-line-mode 1)
(setq hl-line-sticky-flag t)
(blink-cursor-mode -1)

(custom-set-faces
 ;; Near-white block on dark Gruvbox — high contrast at point.
 '(cursor ((t (:background "#fbf1c7" :foreground "#1d2021" :weight ultra-bold))))
 '(hl-line ((t (:background "#504945" :extend t))))
 '(line-number-current
   ((t (:foreground "#fbf1c7" :background "#504945" :weight bold)))))

(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)

;; Size for new GUI frames.  Must be set before a display exists (emacs
;; --fg-daemon loads init with (display-graphic-p) nil).
(add-to-list 'default-frame-alist '(width . 140))
(add-to-list 'default-frame-alist '(height . 40))

(if (display-graphic-p)
    (progn
      ;; Filled cell over the character (bar + stretch), not a thin line.
      (setq x-stretch-cursor t)
      (setq cursor-type 'box)
      (set-cursor-color "#fbf1c7"))
  (setq cursor-type 'box))

;; Hint: available keys after a prefix (C-x, C-c, …). Not M-x command names.
(my/ensure-package 'which-key)
(require 'which-key)
(which-key-mode 1)
(setq which-key-idle-delay 0.8)
;; Let which-key page C-h bindings: C-h C-h n / C-h C-h p (not help-for-help).
(global-unset-key (kbd "C-h C-h"))

;; Speech Dispatcher: RHVoice + Russian language.
(my/ensure-package 'speechd-el)
(require 'speechd)

(setq speechd-language "ru")
(with-eval-after-load 'speechd
  ;; Connection settings apply only after opening (or reopening) a connection.
  (ignore-errors
    (speechd-open nil :quiet t :force-reopen t)
    (speechd-set-output-module "rhvoice")
    (speechd-set-language speechd-language)
    (speechd-set-rate 40)  ;; быстрее/медленнее
    (speechd-set-pitch 30)  ;; выше/ниже
    (speechd-set-volume 100)
    (speechd-set-synthesizer-voice "Aleksandr")  ;; из списка M-x speechd-set-synthesizer-voice
  )
)

;; Optional: enable a "talking Emacs" minor mode.
;; Toggle with: M-x speechd-speak-mode
(require 'speechd-speak)
;; Uncomment if you want it always on:
;; (speechd-speak-mode 1)
;; (speechd-speak)   ;; включает global-speechd-speak-mode

;; Terminal: vterm (libvterm; native module built on first require).
(my/ensure-package 'vterm)
(require 'vterm)
(setq vterm-max-scrollback 10000)
(setq vterm-shell (or (getenv "SHELL") "/bin/bash"))

(defun my/vterm ()
  "Open a vterm in `default-directory'."
  (interactive)
  (vterm default-directory))

(global-set-key (kbd "C-c t") #'my/vterm)

;; Git / projects / Python.
(require 'project)
(setq vc-follow-symlinks t)

(my/ensure-package 'magit)
(require 'magit)
(global-set-key (kbd "C-x g") #'magit-status)

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
  "Return a real pylsp binary, not a pyenv shim that fails under local .python-version."
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

(global-set-key (kbd "C-c o") #'my/org-inbox)
(global-set-key (kbd "C-c A") #'org-agenda)

;; Convenience: open this config quickly.
(defun my/open-init-file ()
  (interactive)
  (find-file user-init-file))
(global-set-key (kbd "C-c e") #'my/open-init-file)
