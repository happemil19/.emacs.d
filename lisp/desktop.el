;;; desktop.el --- Session restore for emacsclient/daemon  -*- lexical-binding: t; -*-

;; Needs `my/tiling-wm-p' and `my/reapply-init-gui-settings' from lisp/ui.el.

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

(defun my/desktop-frame-pos-on-screen-p (left top)
  "Non-nil when LEFT,TOP lie inside some monitor workarea."
  (and (numberp left) (numberp top)
       (seq-some
        (lambda (m)
          (pcase-let ((`(,x ,y ,w ,h) (alist-get 'workarea m)))
            (and (<= x left (+ x w -1))
                 (<= y top (+ y h -1)))))
        (display-monitor-attributes-list))))

(defun my/desktop-clamp-frame-positions ()
  "Keep saved frame coords on-screen across all monitors.

Skip invisible / unpositioned frames (daemon leftover \"F1\" has nil
left/top; `frame-position' reports (0 . 0) and must not be \"fixed\").
Do not call `set-frame-position' unless the position is actually
off-screen: on Xwayland even a reposition to the same coords drifts
the outer frame when desktop autosave runs during idle/echo-area
activity."
  (unless (my/tiling-wm-p)
    (dolist (frame (my/desktop-gui-frames))
      (let ((left (frame-parameter frame 'left))
            (top (frame-parameter frame 'top)))
        (when (and (frame-visible-p frame)
                   (numberp left) (numberp top)
                   (not (my/desktop-frame-pos-on-screen-p left top)))
          (pcase-let* ((wa (alist-get
                            'workarea
                            (or (frame-monitor-attributes frame)
                                (car (display-monitor-attributes-list)))))
                       (`(,x ,y ,_w ,_h) wa)
                       (nl left)
                       (nt top))
            (unless (my/desktop-frame-pos-on-screen-p nl nt)
              (setq nl (+ x 100) nt (+ y 100)))
            (unless (and (eql nl left) (eql nt top))
              (set-frame-position frame nl nt))))))))

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

(provide 'my-desktop)
