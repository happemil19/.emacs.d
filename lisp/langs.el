;;; langs.el --- File modes, Go/Python, Eglot  -*- lexical-binding: t; -*-

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

;; TRAMP over VPN: a blackholed TCP (VPN drop) freezes the whole UI until SSH
;; dies.  ServerAlive fails the multiplexed control socket quickly; ConnectTimeout
;; bounds new handshakes.  After a hang: M-x my/tramp-flush, or kill the stuck
;; `ssh … tramp.%C …' child of the Emacs daemon.
(with-eval-after-load 'tramp
  (setq tramp-connection-timeout 15)
  (setq tramp-ssh-controlmaster-options
        (concat "-o ControlMaster=auto "
                "-o ControlPath=tramp.%%C "
                "-o ControlPersist=no "
                "-o ServerAliveInterval=5 "
                "-o ServerAliveCountMax=2 "
                "-o ConnectTimeout=10")))

(defun my/tramp-flush ()
  "Drop all Tramp connections and related buffers (after VPN drop / hang)."
  (interactive)
  (when (fboundp 'tramp-cleanup-all-connections)
    (tramp-cleanup-all-connections))
  (when (fboundp 'tramp-cleanup-all-buffers)
    (tramp-cleanup-all-buffers))
  (message "Tramp: connections flushed"))

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

(setq python-indent-offset 4)
(setq-default indent-tabs-mode nil)

;; Go: this Emacs build has no tree-sitter, so use classic go-mode for .go.
(my/ensure-package 'go-mode)

;; Prefer ~/go/bin (go install …) over Debian /usr/bin tools like gopls.
(let ((go-bin (expand-file-name "go/bin" (getenv "HOME"))))
  (when (file-directory-p go-bin)
    (setq exec-path (cons go-bin (delete go-bin exec-path)))
    (setenv "PATH" (concat go-bin path-separator (getenv "PATH")))))

(defun my/pylsp-executable ()
  "Return pylsp: `uv tool install` (~/.local/bin) first, then PATH.

Look up from HOME so a project `.python-version` cannot redirect through
a leftover pyenv shim."
  (or (let ((p (expand-file-name "pylsp" "~/.local/bin")))
        (and (file-executable-p p) p))
      (let ((default-directory (expand-file-name "~")))
        (executable-find "pylsp"))))

(defun my/pyright-executable ()
  "Return pyright language-server binary, if installed."
  (let ((default-directory (getenv "HOME")))
    (or (executable-find "pyright-langserver")
        (executable-find "basedpyright-langserver"))))

(defun my/gopls-executable ()
  "Prefer user-installed gopls (matches newer Go) over Debian's."
  (or (let ((p (expand-file-name "go/bin/gopls" (getenv "HOME"))))
        (and (file-executable-p p) p))
      (let ((default-directory (getenv "HOME")))
        (executable-find "gopls"))))

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

;; Only one Python LSP at a time.  Toggle with C-c y.
(global-set-key (kbd "C-c y") #'my/eglot-toggle-python-server)

(defcustom my/python-lsp-server 'pylsp
  "Active Python language server for Eglot: `pylsp' or `pyright'."
  :type '(choice (const :tag "pylsp (Jedi)" pylsp)
                 (const :tag "pyright" pyright))
  :group 'eglot)

(defun my/python-lsp-contact ()
  "Eglot contact for `my/python-lsp-server', or nil if missing."
  (pcase my/python-lsp-server
    ('pylsp (my/pylsp-executable))
    ('pyright (when-let ((bin (my/pyright-executable)))
                (list bin "--stdio")))
    (_ nil)))

(eval-when-compile (require 'eglot))

(defun my/eglot-remove-python-programs ()
  "Drop Python entries from `eglot-server-programs'."
  (setq eglot-server-programs
        (cl-remove-if
         (lambda (entry)
           (let ((m (car entry)))
             (or (memq m '(python-mode python-ts-mode))
                 (and (listp m)
                      (or (memq 'python-mode m)
                          (memq 'python-ts-mode m))))))
         eglot-server-programs)))

(defun my/eglot-configure-servers ()
  "Register preferred language servers for Python and Go.

For Python, only the server selected by `my/python-lsp-server' is
registered, so pylsp and pyright never run together."
  (require 'eglot)
  (my/eglot-remove-python-programs)
  (when-let ((contact (my/python-lsp-contact)))
    (setq eglot-server-programs
          (cons `((python-mode python-ts-mode) . ,(ensure-list contact))
                eglot-server-programs)))
  (when-let ((gopls (my/gopls-executable)))
    (setq eglot-server-programs
          (cons `((go-mode go-dot-mod-mode go-dot-work-mode
                           go-ts-mode go-mod-ts-mode go-work-ts-mode)
                  . (,gopls))
                (cl-remove-if
                 (lambda (entry)
                   (let ((m (car entry)))
                     (or (eq m 'go-mode)
                         (and (listp m)
                              (or (memq 'go-mode m)
                                  (memq 'go-ts-mode m))))))
                 eglot-server-programs)))))

(defun my/eglot-python-workspace-config ()
  "Point the active Python LSP at the project virtualenv when present."
  (when (derived-mode-p 'python-mode 'python-ts-mode)
    (when-let ((venv (my/python-project-venv)))
      (setq eglot-workspace-configuration
            (pcase my/python-lsp-server
              ('pylsp
               `(:pylsp (:plugins (:jedi (:environment ,venv)))))
              ('pyright
               `(:python
                 (:pythonPath ,(expand-file-name "bin/python" venv)
                  :venvPath ,(file-name-directory (directory-file-name venv))
                  :venv ,(file-name-nondirectory
                          (directory-file-name venv)))))
              (_ nil))))))

(defun my/eglot-shutdown-python-servers ()
  "Shut down every Eglot server that manages a Python buffer."
  (require 'eglot)
  (let (servers)
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (and (derived-mode-p 'python-mode 'python-ts-mode)
                   (fboundp 'eglot-current-server)
                   (eglot-current-server))
          (cl-pushnew (eglot-current-server) servers))))
    (dolist (server servers)
      (ignore-errors (eglot-shutdown server)))))

(defvar my/eglot--connect-lock nil
  "Non-nil while `my/eglot-try-connect' is starting a server.")

(defun my/eglot-try-connect ()
  "Connect Eglot for the current buffer if needed.

Serializes attempts so several open files (or toggle + hooks) do not
race `eglot--connect' and trip \"Selecting deleted buffer\"."
  (require 'eglot)
  (when (and buffer-file-name
             (my/eglot-server-available-p)
             (not (eglot-current-server))
             (not my/eglot--connect-lock))
    (setq my/eglot--connect-lock t)
    (unwind-protect
        (condition-case err
            (apply #'eglot--connect (eglot--guess-contact))
          (error (message "my/eglot-try-connect: %s"
                          (error-message-string err))))
      (setq my/eglot--connect-lock nil))))

(defun my/eglot-restart-python-buffers ()
  "Start one Eglot Python session; it manages all project Python buffers."
  (catch 'connected
    (dolist (buf (buffer-list))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (when (and buffer-file-name
                     (derived-mode-p 'python-mode 'python-ts-mode))
            (my/eglot-configure-servers)
            (my/eglot-try-connect)
            (throw 'connected t)))))))

(defun my/eglot-toggle-python-server ()
  "Switch Python LSP between pylsp and pyright; only one stays running."
  (interactive)
  (let* ((next (if (eq my/python-lsp-server 'pylsp) 'pyright 'pylsp))
         (prev my/python-lsp-server))
    (setq my/python-lsp-server next)
    (unless (my/python-lsp-contact)
      (setq my/python-lsp-server prev)
      (user-error
       "Python LSP `%s' is not installed (need %s)"
       next
       (if (eq next 'pyright)
           "`pyright-langserver' (npm i -g pyright) or basedpyright"
         "`pylsp'")))
    (my/eglot-shutdown-python-servers)
    (my/eglot-configure-servers)
    (my/eglot-restart-python-buffers)
    (message "Python LSP → %s (was %s)" next prev)))

(defun my/eglot-server-available-p ()
  "Non-nil when a language server for the current major mode exists.

Skip TRAMP/remote buffers: Eglot would start the (local) LSP contact on
the remote host, where those binaries usually are missing → \"server died\"."
  (and buffer-file-name
       (not (file-remote-p buffer-file-name))
       (cond
        ((derived-mode-p 'python-mode 'python-ts-mode)
         (my/python-lsp-contact))
        ((derived-mode-p 'c-mode 'c++-mode 'c-ts-mode 'c++-ts-mode)
         (let ((default-directory (expand-file-name "~")))
           (or (executable-find "clangd")
               (executable-find "ccls"))))
        ((derived-mode-p 'go-mode 'go-ts-mode)
         (my/gopls-executable)))))

(defun my/eglot-ensure ()
  "Start Eglot when a language server for this buffer is available.

`eglot-ensure' defers to `post-command-hook'; also schedule one serialized
connect for desktop-restored buffers that never get a command."
  (when (and buffer-file-name (my/eglot-server-available-p))
    (my/eglot-configure-servers)
    (eglot-ensure)
    (let ((buf (current-buffer)))
      (run-at-time
       0.05 nil
       (lambda ()
         (when (buffer-live-p buf)
           (with-current-buffer buf
             (unless (eglot-current-server)
               (my/eglot-try-connect)))))))))

(add-hook 'eglot-managed-mode-hook #'my/eglot-python-workspace-config)

(dolist (hook '(python-mode-hook python-ts-mode-hook
                 c-mode-hook c++-mode-hook
                 c-ts-mode-hook c++-ts-mode-hook
                 go-mode-hook go-ts-mode-hook))
  (add-hook hook #'my/eglot-ensure))

;; After init/reload: attach Eglot to already-open code buffers (desktop).
(defun my/eglot-ensure-open-buffers ()
  "Run `my/eglot-ensure' in open buffers that look like code we manage."
  (dolist (buf (buffer-list))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when (and buffer-file-name
                   (derived-mode-p 'python-mode 'python-ts-mode
                                   'c-mode 'c++-mode 'c-ts-mode 'c++-ts-mode
                                   'go-mode 'go-ts-mode)
                   (not (bound-and-true-p eglot--managed-mode)))
          (my/eglot-ensure))))))

(add-hook 'after-init-hook #'my/eglot-ensure-open-buffers)
(when after-init-time
  (run-at-time 0.1 nil #'my/eglot-ensure-open-buffers))

;; M-g n/p are `next-error'/`previous-error' (compilation, grep).  While
;; Flymake is on (Eglot), jump LSP diagnostics instead.
(with-eval-after-load 'flymake
  (define-key flymake-mode-map (kbd "M-g n") #'flymake-goto-next-error)
  (define-key flymake-mode-map (kbd "M-g p") #'flymake-goto-prev-error)
  (define-key flymake-mode-map (kbd "M-g M-n") #'flymake-goto-next-error)
  (define-key flymake-mode-map (kbd "M-g M-p") #'flymake-goto-prev-error))

(provide 'my-langs)
