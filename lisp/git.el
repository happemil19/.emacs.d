;;; git.el --- Magit, projects, consult/vertico, diff-hl  -*- lexical-binding: t; -*-

;; Git / projects.
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
        (consult-ripgrep "Live grep" ?s)
        (project-find-regexp "Find regexp")
        (project-find-dir "Find directory")
        (project-vc-dir "VC-Dir")
        (project-eshell "Eshell")
        (project-any-command "Other")))

;; Live project search, closer to Telescope than `project-find-regexp'.
;; Vertico lists matches in the minibuffer.  Consult restarts `rg` as you
;; type and previews the selected hit in its buffer (surrounding lines).
;; A leading `#' is inserted for you: text after it is the pattern (Emacs
;; regexp; space-separated words match in any order).  A second `#' filters
;; the current list without restarting `rg`.  Search starts at 3 characters.
(my/ensure-package 'vertico)
(my/ensure-package 'consult)
(require 'vertico)
(vertico-mode 1)
(setq vertico-cycle t)
(setq vertico-count 12)

;; C-s / C-r narrow the Vertico list.  The extra words stay in the minibuffer
;; (orange) and are highlighted in the candidates, not only the first word.
;; The search is a transient keymap, same idea as isearch: C-g is a command
;; here, so it restores the previous candidate list instead of quitting M-x.
(defvar my/vertico-isearch-last nil
  "Last string used to narrow a Vertico candidate list.")

(defvar-local my/vertico-isearch--pattern nil)
(defvar-local my/vertico-isearch--extra-patterns nil)
(defvar-local my/vertico-isearch--original nil)
(defvar-local my/vertico-isearch--origin-index nil)
(defvar-local my/vertico-isearch--origin-scroll nil)
(defvar-local my/vertico-isearch--direction 1)
(defvar-local my/vertico-isearch--exit nil)

(defun my/vertico-isearch-forward ()
  "Start narrowing Vertico candidates by an extra substring."
  (interactive)
  (setq quit-flag nil)
  (my/vertico-isearch-begin 1))

(defun my/vertico-isearch-backward ()
  "Start narrowing Vertico candidates from the end of the matches."
  (interactive)
  (setq quit-flag nil)
  (my/vertico-isearch-begin -1))

(defun my/vertico--isearch-text (cand)
  "Visible text of Vertico candidate CAND."
  (vertico--display-string (substring-no-properties cand)))

(defun my/vertico--isearch-match-p (cand pattern)
  "Non-nil when CAND contains PATTERN, like isearch."
  (let ((case-fold-search (not (string-match-p "[[:upper:]]" pattern))))
    (string-match-p (regexp-quote pattern) cand)))

(defun my/vertico--isearch-filter (original pattern)
  "Candidates from ORIGINAL whose visible text contains PATTERN."
  (let (filtered)
    (dolist (cand original)
      (when (my/vertico--isearch-match-p (my/vertico--isearch-text cand) pattern)
        (push cand filtered)))
    (nreverse filtered)))

(defun my/vertico--isearch-show (filtered prefer)
  "Display FILTERED, highlighting PREFER when it is still there."
  (let ((idx 0)
        (i 0))
    (dolist (cand filtered)
      (when (eq cand prefer)
        (setq idx i))
      (setq i (1+ i)))
    (setq vertico--candidates filtered
          vertico--total (length filtered)
          vertico--scroll 0)
    (vertico--goto idx)
    (vertico--exhibit)))

(defun my/vertico--isearch-restore (original index scroll)
  "Put back ORIGINAL candidates, INDEX and SCROLL."
  (setq quit-flag nil)
  (setq vertico--candidates original
        vertico--total (length original)
        vertico--scroll scroll)
  (vertico--goto index)
  (vertico--exhibit))

(defun my/vertico--isearch-commit (pattern)
  "Append PATTERN to the minibuffer and keep the narrowed list.
`vertico--input' is synced so the next refresh does not recompute
candidates from the combined text."
  (let ((filtered vertico--candidates)
        (idx vertico--index))
    (minibuffer--delete-message-overlay)
    (goto-char (point-max))
    (insert " " (propertize pattern 'face 'isearch))
    (setq vertico--input
          (cons (minibuffer-contents-no-properties)
                (max 0 (- (point) (minibuffer-prompt-end))))
          vertico--candidates filtered
          vertico--total (length filtered)
          vertico--scroll 0)
    (vertico--goto idx)
    (vertico--exhibit)))

(defun my/vertico-isearch--note ()
  "Show the in-progress extra search string."
  (minibuffer-message "%ssearch: %s"
                      (if (< my/vertico-isearch--direction 0) "Reverse-" "")
                      my/vertico-isearch--pattern))

(defun my/vertico-isearch--patterns ()
  "Extra substrings that should be highlighted in candidates."
  (let ((pats my/vertico-isearch--extra-patterns))
    (if (and my/vertico-isearch--pattern
             (not (string-empty-p my/vertico-isearch--pattern)))
        (cons my/vertico-isearch--pattern pats)
      pats)))

(defun my/vertico-isearch--paint (text pattern)
  "Mark PATTERN in TEXT with the `isearch' face."
  (let ((case-fold-search (not (string-match-p "[[:upper:]]" pattern)))
        (re (regexp-quote pattern))
        (start 0)
        (text (copy-sequence text)))
    (while (and (< start (length text))
                (string-match re text start))
      ;; Prepend so the orange face wins over `vertico-current'.
      (add-face-text-property (match-beginning 0) (match-end 0)
                              'isearch nil text)
      (setq start (match-end 0)))
    text))

(defun my/vertico-isearch--paint-all (text)
  "Highlight every active extra search string in TEXT."
  (dolist (pat (my/vertico-isearch--patterns))
    (when (and pat (not (string-empty-p pat)))
      (setq text (my/vertico-isearch--paint text pat))))
  text)

(defun my/vertico--format-candidate-extra (orig cand prefix suffix index start)
  "Highlight extra search words after Vertico formats CAND."
  (my/vertico-isearch--paint-all
   (funcall orig cand prefix suffix index start)))

(advice-remove 'vertico--format-candidate #'my/vertico--format-candidate-extra)
(advice-add 'vertico--format-candidate :around #'my/vertico--format-candidate-extra)

(defvar my/vertico-isearch--which-key nil
  "Value of `which-key-inhibit' saved for the extra search.")

(defvar-local my/vertico-isearch--saved-overriding-map nil
  "Previous `overriding-terminal-local-map' for the extra search.")

(defun my/vertico-isearch--deactivate ()
  "Leave the extra-search keymap without quitting the minibuffer."
  (when my/vertico-isearch--exit
    (setq my/vertico-isearch--exit nil
          overriding-terminal-local-map my/vertico-isearch--saved-overriding-map
          which-key-inhibit my/vertico-isearch--which-key)))

(defun my/vertico-isearch--type (text)
  "Append TEXT to the extra search and narrow the list."
  (let* ((next (concat my/vertico-isearch--pattern text))
         (filtered (my/vertico--isearch-filter my/vertico-isearch--original next))
         (current (and (>= vertico--index 0)
                       (nth vertico--index vertico--candidates))))
    (if (not filtered)
        (ding)
      (setq my/vertico-isearch--pattern next)
      (unless (memq current filtered)
        (setq current (if (< my/vertico-isearch--direction 0)
                          (car (last filtered))
                        (car filtered))))
      (my/vertico--isearch-show filtered current)))
  (my/vertico-isearch--note))

(defun my/vertico-isearch-begin (direction)
  "Start an extra search in DIRECTION, 1 or -1."
  (if (null vertico--candidates)
      (minibuffer-message "No candidates")
    ;; Own the key lookup the way isearch does.  A transient map lets RET
    ;; (`return') and C-g fall through to Vertico and `keyboard-quit'.
    (setq my/vertico-isearch--which-key which-key-inhibit
          which-key-inhibit t
          my/vertico-isearch--original vertico--candidates
          my/vertico-isearch--origin-index vertico--index
          my/vertico-isearch--origin-scroll vertico--scroll
          my/vertico-isearch--pattern ""
          my/vertico-isearch--direction direction
          my/vertico-isearch--saved-overriding-map overriding-terminal-local-map
          overriding-terminal-local-map my/vertico-isearch-map
          my/vertico-isearch--exit t)
    (my/vertico-isearch--note)))

(defun my/vertico-isearch-step-forward ()
  "Next match of the extra search, or repeat the last one."
  (interactive)
  (setq quit-flag nil
        my/vertico-isearch--direction 1)
  (cond
   ((not (string-empty-p my/vertico-isearch--pattern))
    (vertico-next 1)
    (vertico--exhibit)
    (my/vertico-isearch--note))
   (my/vertico-isearch-last
    (my/vertico-isearch--type my/vertico-isearch-last))))

(defun my/vertico-isearch-step-backward ()
  "Previous match of the extra search, or repeat the last one."
  (interactive)
  (setq quit-flag nil
        my/vertico-isearch--direction -1)
  (cond
   ((not (string-empty-p my/vertico-isearch--pattern))
    (vertico-next -1)
    (vertico--exhibit)
    (my/vertico-isearch--note))
   (my/vertico-isearch-last
    (my/vertico-isearch--type my/vertico-isearch-last)
    (when (> vertico--total 0)
      (vertico--goto (1- vertico--total))
      (vertico--exhibit)))))

(defun my/vertico-isearch-quit ()
  "Restore the candidate list from before this extra search.
Does not exit the minibuffer."
  (interactive)
  (let ((inhibit-quit t))
    (discard-input)
    (setq quit-flag nil
          my/vertico-isearch--pattern nil)
    (my/vertico--isearch-restore my/vertico-isearch--original
                                 my/vertico-isearch--origin-index
                                 my/vertico-isearch--origin-scroll)
    (my/vertico-isearch--deactivate)
    (setq quit-flag nil)))

(defun my/vertico-isearch-confirm ()
  "Keep the narrowed list and write the extra word into the minibuffer."
  (interactive)
  (setq quit-flag nil)
  (let ((pattern my/vertico-isearch--pattern))
    (when (and pattern (not (string-empty-p pattern)))
      (setq my/vertico-isearch-last pattern)
      (push pattern my/vertico-isearch--extra-patterns)
      (setq my/vertico-isearch--pattern nil)
      (my/vertico--isearch-commit pattern)))
  (my/vertico-isearch--deactivate))

(defun my/vertico-isearch-backspace ()
  "Delete the last character of the extra search."
  (interactive)
  (setq quit-flag nil)
  (when (> (length my/vertico-isearch--pattern) 0)
    (setq my/vertico-isearch--pattern
          (substring my/vertico-isearch--pattern 0 -1)))
  (if (string-empty-p my/vertico-isearch--pattern)
      (my/vertico--isearch-restore my/vertico-isearch--original
                                   my/vertico-isearch--origin-index
                                   my/vertico-isearch--origin-scroll)
    (my/vertico--isearch-show
     (my/vertico--isearch-filter my/vertico-isearch--original
                                 my/vertico-isearch--pattern)
     (and (>= vertico--index 0)
          (nth vertico--index vertico--candidates))))
  (my/vertico-isearch--note))

(defun my/vertico-isearch-insert ()
  "Add the typed character to the extra search.
RET confirms it.  C-g restores the previous list.  Another key confirms
the search and is then run normally."
  (interactive)
  (setq quit-flag nil)
  (let ((ev last-command-event))
    (cond
     ((eq ev ?\C-g)
      (my/vertico-isearch-quit))
     ((memq ev '(?\C-m ?\r return kp-enter))
      (my/vertico-isearch-confirm))
     ((and (characterp ev)
           (not (string-match-p "[[:cntrl:]]" (string ev))))
      (my/vertico-isearch--type (string ev)))
     (t
      (my/vertico-isearch-confirm)
      (setq unread-command-events (cons ev unread-command-events))))))

(defvar my/vertico-isearch-map
  (let ((map (make-sparse-keymap)))
    ;; Character form, same as `isearch-mode-map'.  The GUI Return key is
    ;; the symbol `return', which the default [t] binding would otherwise
    ;; replay as `vertico-exit'.
    (define-key map "\C-g" #'my/vertico-isearch-quit)
    (define-key map "\C-s" #'my/vertico-isearch-step-forward)
    (define-key map "\C-r" #'my/vertico-isearch-step-backward)
    (define-key map "\C-m" #'my/vertico-isearch-confirm)
    (define-key map [return] #'my/vertico-isearch-confirm)
    (define-key map [kp-enter] #'my/vertico-isearch-confirm)
    (define-key map "\C-h" #'my/vertico-isearch-backspace)
    (define-key map [backspace] #'my/vertico-isearch-backspace)
    (define-key map [?\d] #'my/vertico-isearch-backspace)
    (define-key map [t] #'my/vertico-isearch-insert)
    map)
  "Keymap while an extra Vertico search is in progress.")

(define-key vertico-map (kbd "C-s") #'my/vertico-isearch-forward)
(define-key vertico-map (kbd "C-r") #'my/vertico-isearch-backward)

(require 'consult)
(setq consult-preview-key '(:debounce 0.2 any))
(setq xref-show-xrefs-function #'consult-xref
      xref-show-definitions-function #'consult-xref)
(global-set-key (kbd "C-c s") #'consult-ripgrep)
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

(provide 'my-git)
