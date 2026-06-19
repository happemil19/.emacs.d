;;; init.el --- Minimal Emacs config  -*- lexical-binding: t; -*-

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

;; Theme + highlight current line and the active window in splits.
(my/ensure-package 'gruvbox-theme)
(load-theme 'gruvbox-dark-medium t)

(global-hl-line-mode 1)
(setq hl-line-sticky-flag t)

;; Active window: blinking cursor.  Others: no cursor at all.
(setq cursor-in-non-selected-windows nil)
(blink-cursor-mode 1)
(setq blink-cursor-delay 0.5)
(setq blink-cursor-interval 0.5)

(custom-set-faces
 ;; Near-white block on dark Gruvbox — high contrast at point.
 '(cursor ((t (:background "#fbf1c7" :foreground "#1d2021" :weight ultra-bold))))
 '(hl-line ((t (:background "#504945" :extend t))))
 '(line-number-current
   ((t (:foreground "#fbf1c7" :background "#504945" :weight bold))))
 ;; Active window mode line (status bar at the bottom).
 '(mode-line
   ((t (:background "#504945" :foreground "#fbf1c7"
                  :box (:line-width 3 :color "#fe8019")))))
 ;; Inactive: darker band so it does not read like a comment line (#7c6f64).
 '(mode-line-inactive
   ((t (:background "#1d2021" :foreground "#928374"
                  :box (:line-width 1 :color "#3c3836")))))
 '(window-divider
   ((t (:foreground "#3c3836" :background "#3c3836")))))

(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)

;; Thin, low-contrast grooves between split windows.
(setq window-divider-default-places t)
(setq window-divider-default-bottom-width 2)
(setq window-divider-default-right-width 2)
(window-divider-mode 1)
(window-divider-mode-apply t)

(defun my/apply-window-dividers ()
  (when (and (display-graphic-p) window-divider-mode)
    (window-divider-mode-apply t)))

(add-hook 'after-make-frame-functions #'my/apply-window-dividers)

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

;; Persistence: auto-save, backups, session restore, cursor & history.
(setq auto-save-default t)
(setq auto-save-timeout 5)
(setq auto-save-interval 200)

(setq make-backup-files t)
(setq version-control t)
(setq delete-old-versions t)
(setq kept-old-versions 5)

;; Desktop session: ~/.emacs.d/.emacs.desktop
;; With `emacs --daemon', enable desktop-save on the first emacsclient -c frame.
;; desktop-read must run with that client frame *selected*; otherwise
;; `desktop-restoring-frameset-p' is nil and only *scratch* comes back.
(setq desktop-path (list user-emacs-directory))
(setq desktop-prompt-restore 'yes)
(setq desktop-save t)
(setq desktop-autosave-interval 300)
(setq desktop-restore-reuses-frames t)

(defvar my/desktop--enabled nil)
(defvar my/desktop--after-restored nil)

(defun my/desktop-hide-frame (frame)
  (when (and frame (frame-live-p frame) (display-graphic-p frame))
    (modify-frame-parameters frame '((visibility . nil)))))

(defun my/desktop-show-frame (frame)
  (when (and frame (frame-live-p frame) (display-graphic-p frame))
    (modify-frame-parameters frame '((visibility . t)))
    (raise-frame frame)))

(defun my/desktop-show-frame-ready (frame)
  "Show FRAME on the next idle tick, after splits and faces are painted."
  (run-with-idle-timer
   0 nil
   (lambda ()
     (when (frame-live-p frame)
       (select-frame frame)
       (redisplay t)
       (my/desktop-show-frame frame)))))

(defun my/desktop-client-frame-params-p (params)
  (and params (plist-member params 'client)
       (not (plist-get params 'terminal))))

(defun my/desktop-make-frame-invisible (orig &rest args)
  "Create emacsclient GUI frames hidden when a desktop session will load."
  (let ((params (car args)))
    (when (and (daemonp)
               (not my/desktop--enabled)
               (file-exists-p (my/desktop-file))
               (my/desktop-client-frame-params-p params))
      (setf (car args) (append params '((visibility . nil)))))
    (apply orig args)))

(defun my/desktop-hide-client-frame (frame)
  "Hide the emacsclient scratch frame until desktop restore finishes."
  (when (and (daemonp)
             (not my/desktop--enabled)
             (display-graphic-p frame)
             (frame-parameter frame 'client)
             (file-exists-p (my/desktop-file)))
    (my/desktop-hide-frame frame)))

(defun my/desktop-gui-frames ()
  (let (frames)
    (dolist (frame (frame-list))
      (when (display-graphic-p frame)
        (push frame frames)))
    frames))

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
  (dolist (frame (my/desktop-gui-frames))
    (let ((pos (frame-position frame)))
      (when (>= (car pos) 1600)
        (set-frame-position frame 100 100)))))

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
      (my/apply-window-dividers)
      (when best-frame
        (ignore-errors
          (my/desktop-show-frame-ready best-frame))))))

(defun my/desktop-file ()
  (expand-file-name ".emacs.desktop" user-emacs-directory))

(defun my/desktop-clear-stale-lock ()
  "Remove a leftover lock from a dead Emacs process."
  (let ((lockfile (expand-file-name ".emacs.desktop.lock" user-emacs-directory)))
    (when (file-exists-p lockfile)
      (let ((owner (ignore-errors
                     (string-to-number (string-trim (file-string lockfile))))))
        (unless (and owner (= owner (emacs-pid)))
          (delete-file lockfile))))))

(defun my/desktop-enable (&optional client-frame)
  (unless my/desktop--enabled
    (setq my/desktop--enabled t)
    (setq my/desktop--after-restored nil)
    (my/desktop-clear-stale-lock)
    (setq desktop-save-mode nil)
    (desktop-save-mode 1)
    (add-hook 'desktop-after-read-hook #'my/desktop-after-restore)
    (when (and client-frame (file-exists-p (my/desktop-file)))
      (select-frame client-frame)
      (my/desktop-hide-frame client-frame))
    (when (file-exists-p (my/desktop-file))
      (unwind-protect
          (let ((inhibit-redisplay t))
            (desktop-read))
        (unless my/desktop--after-restored
          (my/desktop-show-frame-ready (or client-frame (selected-frame))))))))

(defun my/desktop-enable-server-frame ()
  (when (display-graphic-p (selected-frame))
    (my/desktop-enable (selected-frame))))

(with-eval-after-load 'server
  (advice-add #'make-frame :around #'my/desktop-make-frame-invisible)
  (add-hook 'server-after-make-frame-hook #'my/desktop-enable-server-frame)
  (add-hook 'after-make-frame-functions #'my/desktop-hide-client-frame))
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

(global-set-key (kbd "C-c o") #'my/org-inbox)
(global-set-key (kbd "C-c A") #'org-agenda)
(global-set-key (kbd "C-c r") #'recentf-open-files)

;; Comment/uncomment line(s): `;;' in Elisp, `#' in Python, etc.
;; With prefix: C-u 3 C-c ; comments three lines.
(global-set-key (kbd "C-c ;") #'comment-line)
;; Built-in M-; (`comment-dwim'): region if highlighted, else toggles current line.

;; Convenience: open this config quickly.
(defun my/open-init-file ()
  (interactive)
  (find-file user-init-file))
(global-set-key (kbd "C-c e") #'my/open-init-file)
