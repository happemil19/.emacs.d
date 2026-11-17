;;; ui.el --- Theme, mode-line, frames, ediff  -*- lexical-binding: t; -*-

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
 ;; No :box: it steals pixels so the focus frame's bottom ±14 line clips
 ;; and recenter looks uneven (more lines above than below).
 '(mode-line ((t (:background "#504945" :foreground "#fbf1c7" :box nil))))
 '(mode-line-inactive ((t (:background "#282828" :foreground "#665c54" :box nil)))))

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
  "Mode-line icons/position; also undo legacy prepends from older init versions.

`mode-line-buffer-identification' is buffer-local once set, so a plain
`setq' (for example while re-evaluating init.el) updates only that
buffer and every other mode-line keeps the stock name."
  (my/mode-line--strip-legacy-nerd-icons)
  (line-number-mode 1)
  (column-number-mode 1)
  (setq mode-line-position-column-line-format '(" L%l,C%c"))
  (my/mode-line--ensure-region-segment)
  (setq-default mode-line-buffer-identification
                '((:eval (my/mode-line-buffer-identification))))
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (kill-local-variable 'mode-line-buffer-identification))))

(defun my/reapply-init-gui-frame (&optional frame)
  "Per-frame GUI settings that desktop frameset restore can override."
  (my/apply-cursor-frame frame))

(defun my/reapply-init-gui-settings ()
  "Reapply global + per-frame GUI init after desktop restore."
  (my/apply-mode-line-settings)
  (when (fboundp 'my/apply-preferred-font-height)
    (my/apply-preferred-font-height))
  (dolist (frame (if (fboundp 'my/desktop-gui-frames)
                     (my/desktop-gui-frames)
                   (seq-filter #'display-graphic-p (frame-list))))
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

(defun my/nerd-icons-buffer-icon (&optional file)
  "Icon for FILE, or for the current buffer (GUI only).
A visited file keeps its extension glyph.  A buffer with no file
takes the glyph of its major mode, so Magit, VTerm and *Messages*
are not the same generic file icon."
  (when (display-graphic-p)
    (let ((name (or file
                    (and buffer-file-name
                         (file-name-nondirectory buffer-file-name)))))
      (if name
          (nerd-icons-icon-for-file name :height 0.9 :v-adjust 0.05)
        (nerd-icons-icon-for-mode major-mode :height 0.9 :v-adjust 0.05)))))

(defun my/mode-line--strip-legacy-nerd-icons ()
  "Drop stacked nerd-icon prepends left by older init.el versions."
  (let ((legacy '(:eval (my/mode-line-buffer-icon)))
        (fmt (default-value 'mode-line-format)))
    (while (and fmt (equal (car fmt) legacy))
      (setq fmt (cdr fmt)))
    (setq-default mode-line-format fmt)))

(defun my/mode-line-region ()
  "Mode-line fragment: active region as V3L.128ch (lines.characters)."
  (when (use-region-p)
    (let* ((beg (region-beginning))
           (end (region-end))
           (lines (count-lines beg end))
           (chars (- end beg)))
      (propertize (format " V%dL.%dch" lines chars)
                  'help-echo "Active region size (lines.characters)"))))

(defun my/mode-line--ensure-region-segment ()
  "Keep region size immediately after `mode-line-position'."
  (let ((segment '(:eval (my/mode-line-region)))
        (fmt (default-value 'mode-line-format))
        result found)
    (dolist (elt fmt)
      (unless (equal elt segment)
        (setq result (nconc result (list elt)))
        (when (eq elt 'mode-line-position)
          (setq result (nconc result (list segment))
                found t))))
    (unless found
      (setq result (nconc result (list segment))))
    (setq-default mode-line-format result)))

(defun my/mode-line-buffer-identification ()
  "Buffer name with one icon: extension for a file, major mode otherwise."
  (let ((name (buffer-name)))
    (if-let ((icon (my/nerd-icons-buffer-icon)))
        (concat icon " " (propertize name 'face 'mode-line-buffer-id))
      (propertize name 'face 'mode-line-buffer-id))))

(my/apply-mode-line-settings)

;; Plasma keyboard layout (en/ru) in the mode line — same source as tmux-kbd-layout.
(require 'dbus)

(defvar my/kbd-layout--cache "en"
  "Short Plasma keyboard layout name for the mode line.")

(defvar my/kbd-layout--signal nil
  "D-Bus signal object for `layoutChanged', if registered.")

(defvar my/kbd-layout--timer nil
  "Idle fallback timer when D-Bus signal is unavailable.")

(defvar my/kbd-layout--enabled nil
  "Non-nil after mode-line layout indicator has been installed once.")

(defun my/kbd-layout-short (code)
  "Map XKB layout CODE to a short mode-line label (us→en)."
  (pcase code
    ((or "us" "en") "en")
    (_ (or code "?"))))

(defun my/kbd-layout-refresh (&optional index)
  "Refresh `my/kbd-layout--cache' from Plasma (optional INDEX from signal)."
  (condition-case nil
      (let* ((idx (or (and (natnump index) index)
                      (dbus-call-method
                       :session "org.kde.keyboard" "/Layouts"
                       "org.kde.KeyboardLayouts" "getLayout")))
             (layouts (dbus-call-method
                       :session "org.kde.keyboard" "/Layouts"
                       "org.kde.KeyboardLayouts" "getLayoutsList"))
             (entry (nth idx layouts))
             (code (car-safe entry)))
        (setq my/kbd-layout--cache (my/kbd-layout-short code)))
    (error
     ;; Fallback: same script as tmux status (Wayland/X11).
     (let ((script (executable-find "tmux-kbd-layout")))
       (when (and script (file-executable-p script))
         (let ((out (string-trim (shell-command-to-string script))))
           (when (and out (not (string-empty-p out)))
             (setq my/kbd-layout--cache out)))))))
  (force-mode-line-update t)
  my/kbd-layout--cache)

(defun my/kbd-layout-mode-line ()
  "Mode-line fragment: current Plasma layout (en/ru)."
  (propertize (format " %s" my/kbd-layout--cache)
              'face 'bold
              'help-echo "Plasma keyboard layout"))

(defun my/kbd-layout-enable ()
  "Show Plasma layout on the mode line; update on D-Bus (timer fallback)."
  (my/kbd-layout-refresh)
  (unless (member '(:eval (my/kbd-layout-mode-line)) global-mode-string)
    (add-to-list 'global-mode-string '(:eval (my/kbd-layout-mode-line)) t))
  (unless my/kbd-layout--signal
    (setq my/kbd-layout--signal
          (ignore-errors
            (dbus-register-signal
             :session "org.kde.keyboard" "/Layouts"
             "org.kde.KeyboardLayouts" "layoutChanged"
             #'my/kbd-layout-refresh))))
  (unless my/kbd-layout--enabled
    (setq my/kbd-layout--enabled t)
    ;; Plasma may start after the daemon; one delayed poll.
    (run-with-timer 2 nil #'my/kbd-layout-refresh))
  (unless (or my/kbd-layout--signal my/kbd-layout--timer)
    (setq my/kbd-layout--timer
          (run-with-timer 1.5 1.5 #'my/kbd-layout-refresh))))

(my/kbd-layout-enable)

(add-hook 'dired-mode-hook #'nerd-icons-dired-mode)
(add-hook 'ibuffer-mode-hook #'nerd-icons-ibuffer-mode)

(defconst my/buffer-menu-no-project "No project"
  "Buffer Menu group for buffers outside any `project.el' project.")

(defun my/buffer-menu--pretty-name (orig name)
  "Prepend a buffer icon before column width is calculated.
Doing this inside `Buffer-menu--pretty-name' (rather than after
`list-buffers--refresh') keeps the Buffer column wide enough for the
glyph plus the name.  Files use the extension glyph; other buffers
use the major-mode glyph."
  (let ((pretty (funcall orig name)))
    (if-let* ((icon (my/nerd-icons-buffer-icon)))
        (concat icon " " pretty)
      pretty)))

(advice-add 'Buffer-menu--pretty-name :around #'my/buffer-menu--pretty-name)
;; Drop the post-refresh injector: it prepended icons after the column
;; width was fixed, so glyphs were clipped, and it double-applies now.
(advice-remove 'list-buffers--refresh #'my/nerd-icons-buffer-menu--inject-icons)

(defun my/buffer-menu--project-buffer-p ()
  "Non-nil when the current buffer belongs to a project context.
File buffers, Dired, Magit, VC and terminals do.  Incidental special
buffers (`*Messages*', `*Help*', `*Completions*', …) do not, even when
their `default-directory' happens to sit inside a repository."
  (or buffer-file-name
      (derived-mode-p 'dired-mode 'magit-mode 'vterm-mode 'eshell-mode
                      'shell-mode 'vc-dir-mode 'diff-mode 'log-view-mode
                      'compilation-mode)))

(defun my/buffer-context-root (&optional buffer)
  "Project root of BUFFER, or nil when BUFFER is outside any project.
Uses the same notion of project context as the Buffer Menu groups."
  (with-current-buffer (or buffer (current-buffer))
    (let ((non-essential t))
      (when (my/buffer-menu--project-buffer-p)
        (when-let* ((project (ignore-errors (project-current))))
          (expand-file-name (project-root project)))))))

(defun my/buffer-same-context-p (buffer root)
  "Non-nil when BUFFER belongs to ROOT.
ROOT nil means the group of buffers outside any project."
  (let ((other (my/buffer-context-root buffer)))
    (if root
        (and other (file-equal-p root other))
      (not other))))

(defun my/buffer-menu-group-by-project (entry)
  "Project root label for buffer-menu ENTRY, or `my/buffer-menu-no-project'."
  (if-let* ((root (my/buffer-context-root (car entry))))
      (abbreviate-file-name (directory-file-name root))
    my/buffer-menu-no-project))

(defun my/buffer-cycle-skip-p (buffer)
  "Non-nil when BUFFER stays in the project list but not in C-c n/p.
The Magit process buffer is a log of git commands already run; it is
not a place to land while stepping through the project."
  (with-current-buffer buffer
    (derived-mode-p 'magit-process-mode)))

(defun my/switch-buffer-in-context (next)
  "Switch to the next or previous buffer in the current context.
NEXT non-nil moves forward (`switch-to-next-buffer'), otherwise back.
Buffers from another project, and project buffers when the current
buffer has none, are skipped.  `my/buffer-cycle-skip-p' also drops
buffers that belong to the context but are not worth stepping through.
The existing `switch-to-prev-buffer-skip' rules still apply."
  (let* ((root (my/buffer-context-root))
         (orig switch-to-prev-buffer-skip)
         (switch-to-prev-buffer-skip
          (lambda (window buffer &optional bury-or-kill)
            (or (not (my/buffer-same-context-p buffer root))
                (my/buffer-cycle-skip-p buffer)
                (switch-to-prev-buffer-skip-p
                 orig window buffer bury-or-kill)))))
    (if next
        (switch-to-next-buffer)
      (switch-to-prev-buffer))))

(defun my/next-buffer-in-context (&optional arg)
  "Switch to the ARGth next buffer in the current project context."
  (interactive "p")
  (dotimes (_ (or arg 1))
    (unless (my/switch-buffer-in-context t)
      (user-error "No next buffer in this context"))))

(defun my/previous-buffer-in-context (&optional arg)
  "Switch to the ARGth previous buffer in the current project context."
  (interactive "p")
  (dotimes (_ (or arg 1))
    (unless (my/switch-buffer-in-context nil)
      (user-error "No previous buffer in this context"))))

(defun my/buffer-menu--came-from-project ()
  "Abbreviated root of the buffer that was current when the menu opened."
  (when-let* ((entry (seq-find (lambda (e)
                                 (equal (aref (cadr e) 0) "."))
                               tabulated-list-entries)))
    (let ((label (my/buffer-menu-group-by-project entry)))
      (unless (equal label my/buffer-menu-no-project)
        label))))

(defun my/buffer-menu-group-sort (groups _level)
  "Current project first, other projects by name, non-project buffers last."
  (let* ((current (my/buffer-menu--came-from-project))
         (rank (lambda (name)
                 (cond ((and current (equal name current)) 0)
                       ((equal name my/buffer-menu-no-project) 2)
                       (t 1)))))
    (sort groups
          :in-place t
          :lessp (lambda (a b)
                   (let ((ra (funcall rank (car a)))
                         (rb (funcall rank (car b))))
                     (if (= ra rb)
                         (string< (car a) (car b))
                       (< ra rb)))))))

;; A list of functions, not a bare function: `list-buffers--refresh' wraps
;; each one as a single outline level.  A function used directly is treated
;; as a path list and splits the label into characters.
(setq Buffer-menu-group-by '(my/buffer-menu-group-by-project))
(setq Buffer-menu-group-sort-by #'my/buffer-menu-group-sort)

;; Size for new GUI frames.  Must be set before a display exists (emacs
;; --fg-daemon loads init with (display-graphic-p) nil).
;; Focus lens: fixed char geometry.  Width 93 ≈ 88 code cols after
;; line-number gutter (90 left only ~84).  Height 31 = 29 body lines
;; (current ±14) + mode-line + echo.  Widen via KDE when needed.
(defconst my/focus-frame-width 93)
(defconst my/focus-frame-height 31)
;; Habitual size: three `global-text-scale-adjust' steps (each 5 in 1/10 pt)
;; below Emacs default.  Two `C-x C-M--' plus a transient `-' lands here
;; too; two steps alone left the face slightly larger than this setup.
(defconst my/font-height-steps-below-default 3)
(defvar my/font-height-base nil
  "Emacs default face :height captured before preferred shrink.")

(defun my/tiling-wm-p ()
  "Non-nil when cortile (or EMACS_TILING_WM) tiles outer Emacs frames."
  (or (getenv "EMACS_TILING_WM")
      (and (executable-find "pgrep")
           (= 0 (call-process "pgrep" nil nil nil "-x" "cortile")))))

(unless (my/tiling-wm-p)
  (add-to-list 'default-frame-alist (cons 'width my/focus-frame-width))
  (add-to-list 'default-frame-alist (cons 'height my/focus-frame-height)))

(defun my/preferred-font-height ()
  "Face :height after `my/font-height-steps-below-default' global steps."
  (require 'face-remap)
  (- my/font-height-base
     (* my/font-height-steps-below-default
        global-text-scale-adjust--increment-factor)))

(defun my/focus-frame-apply-size (&optional frame)
  "Apply the fixed focus frame size (`my/focus-frame-width'×height)."
  (let ((frame (or frame (selected-frame))))
    (when (and (display-graphic-p frame) (not (my/tiling-wm-p)))
      (set-frame-size frame my/focus-frame-width my/focus-frame-height))))

(defun my/apply-preferred-font-height (&optional frame)
  "Shrink `default' face like habitual `C-x C-M--', then keep focus geometry.

`early-init.el' sets `frame-inhibit-implied-resize' to `force', so a
smaller face would otherwise leave a larger character grid; re-assert
the fixed focus size after the face change.
Safe to run again after desktop frameset restore."
  (when (display-graphic-p (or frame (selected-frame)))
    (require 'face-remap)
    (unless my/font-height-base
      (setq my/font-height-base
            (or global-text-scale-adjust--default-height
                (face-attribute 'default :height)))
      (setq global-text-scale-adjust--default-height my/font-height-base))
    (let ((new (my/preferred-font-height))
          (cur (face-attribute 'default :height)))
      (when (and (< (car global-text-scale-adjust-limits)
                    new
                    (cdr global-text-scale-adjust-limits))
                 (/= cur new))
        (set-face-attribute 'default nil :height new))
      (dolist (f (frame-list))
        (my/focus-frame-apply-size f)))))

(add-hook 'after-make-frame-functions #'my/apply-preferred-font-height)
(add-hook 'emacs-startup-hook #'my/apply-preferred-font-height)

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

;; Ediff default is a separate tiny control frame + vertical stack of A/B.
;; That fights `my/apply-preferred-font-height' (resizes every frame).  Stay in
;; the current frame; compare A|B side by side; merges use vimdiff layout.
(setq ediff-window-setup-function #'my/ediff-setup-windows)
(setq ediff-split-window-function #'split-window-horizontally)
(setq ediff-show-ancestor t)

(defun my/ediff-setup-windows (buffer-A buffer-B buffer-C control-buffer)
  "Like `ediff-setup-windows-plain', but merge layout matches vimdiff."
  (with-current-buffer control-buffer
    (setq ediff-multiframe nil))
  (if (buffer-local-value 'ediff-merge-job control-buffer)
      (my/ediff-setup-windows-merge-vimdiff
       buffer-A buffer-B buffer-C control-buffer)
    (ediff-setup-windows-plain-compare
     buffer-A buffer-B buffer-C control-buffer)))

(defun my/ediff-setup-windows-merge-vimdiff (buf-A buf-B buf-C control-buffer)
  "Merge windows like vimdiff: Local | Base | Remote over Merge.

Control strip stays at the bottom (Ediff needs it).  Without an ancestor,
top row is Local | Remote only."
  (ediff-destroy-control-frame control-buffer)
  (let* ((window-min-height 1)
         (with-ancestor-p
          (buffer-local-value 'ediff-merge-with-ancestor-job control-buffer))
         (buf-ancestor
          (buffer-local-value 'ediff-ancestor-buffer control-buffer))
         (merge-window-share
          (buffer-local-value 'ediff-merge-window-share control-buffer))
         merge-window-lines
         wind-A wind-B wind-C wind-Ancestor)
    (delete-other-windows)
    (set-window-dedicated-p (selected-window) nil)
    (split-window-vertically)
    (ediff-select-lowest-window)
    (ediff-setup-control-buffer control-buffer)

    ;; Upper pane: variants on top, merge buffer below.
    (other-window 1)
    (setq merge-window-lines
          (max 2 (round (* (window-height) merge-window-share))))
    (switch-to-buffer buf-A)
    (setq wind-A (selected-window))
    (split-window-vertically
     (max 2 (- (window-height) merge-window-lines)))
    (when (eq (selected-window) wind-A)
      (other-window 1))
    (setq wind-C (selected-window))
    (switch-to-buffer buf-C)

    ;; Top row: A | Ancestor | B  (or A | B if no base).
    (select-window wind-A)
    (if (and ediff-show-ancestor with-ancestor-p buf-ancestor)
        (let* ((top-width (window-total-width wind-A))
               (col (/ top-width 3)))
          (setq wind-Ancestor (split-window wind-A col 'right))
          (with-selected-window wind-Ancestor
            (switch-to-buffer buf-ancestor)
            (setq wind-B (split-window nil (/ (window-total-width) 2) 'right))
            (with-selected-window wind-B
              (switch-to-buffer buf-B))))
      (setq wind-B (split-window wind-A (/ (window-total-width wind-A) 2) 'right))
      (with-selected-window wind-B
        (switch-to-buffer buf-B)))

    (with-current-buffer control-buffer
      (setq ediff-window-A wind-A
            ediff-window-B wind-B
            ediff-window-C wind-C
            ediff-window-Ancestor wind-Ancestor))
    (ediff-select-lowest-window)
    (ediff-setup-control-buffer control-buffer)))


(provide 'my-ui)
