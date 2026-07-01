;;; early-init.el --- runs before init.el  -*- lexical-binding: t; -*-

;; Emacs picks init.el vs init.elc *before* init.el is read.  With the default
;; (load-prefer-newer nil) a leftover init.elc wins even when init.el is newer.
(setq load-prefer-newer t)

;; init.el is source of truth: drop bytecode when the source was edited.
(let ((init (expand-file-name "init.el" user-emacs-directory))
      (elc (expand-file-name "init.elc" user-emacs-directory)))
  (when (and (file-exists-p init) (file-exists-p elc)
             (file-newer-than-file-p init elc))
    (delete-file elc)))
