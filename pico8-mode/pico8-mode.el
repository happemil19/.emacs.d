;;; pico8-mode.el --- a major-mode for editing Pico8 p8 files -*- lexical-binding: t -*-
;; Author: Väinö Järvelä <vaino@jarve.la>
;; URL: https://github.com/kaali/pico8-mode
;; Version: 20180215
;; Package-Requires: ((lua-mode "20180104"))
;;
;; This file is NOT part of Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 2
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
;; MA 02110-1301, USA.

(require 'seq)
(require 'lua-mode)
(require 'rx)
(require 'cl-lib)
(require 'xref)
(require 'subr-x)

;; TODO: Clean up and refactor
;; TODO: Highlight current argument with eldoc

;; TODO: Optimize?
;;       The code is currently really really inefficient, it goes through the
;;       file multiple times when doing navigation or completion. It also goes
;;       through the file to find images to render, and the image scaler is
;;       quite crude. But nothing really shows up in the profiler, and .p8
;;       files are so small that it doesn't show up in use at all.

;; Fix Emacs 25 support by defining when-let*
(eval-when-compile
  (unless (fboundp 'when-let*)
    (defalias 'when-let* 'when-let)))

(defgroup pico8 nil
  "pico8 major mode"
  :prefix "pico8-"
  :group 'languages)

;; TODO: Maybe rebuild documentation when setting this custom-var?
(defcustom pico8-documentation-file ""
  "Full path to pico8 manual.
Enables documentation annotations with eldoc and company"
  :type 'file
  :group 'pico8)

(defcustom pico8-dim-non-code-sections t
  "If enabled, then dim all sections that are not Lua code"
  :type 'boolean
  :group 'pico8)

(defcustom pico8-create-images t
  "If enabled, then image data is rendered inline."
  :type 'boolean
  :group 'pico8)

(defcustom pico8-use-font nil
  "If enabled, then apply the blocky PICO-8 font to the buffer.

Prefer installing a patched family name (e.g. \"PICO-8 Patched\") so you
can adjust font metrics without affecting other apps."
  :type 'boolean
  :group 'pico8)

(defcustom pico8-font-family "PICO-8 Patched"
  "Font family to use when `pico8-use-font' is enabled."
  :type 'string
  :group 'pico8)

(defcustom pico8-font-file
  (expand-file-name "fonts/PICO-8-Patched.ttf"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Path to a bundled PICO-8 font file (TTF).

If the family from `pico8-font-family' isn't available, `pico8-install-font'
can copy this file into your user font directory."
  :type 'file
  :group 'pico8)

(defun pico8-install-font ()
  "Install the bundled PICO-8 font for the current user (Linux).

Copies `pico8-font-file' into ~/.local/share/fonts/ and refreshes the font
cache via `fc-cache'."
  (interactive)
  (unless (and (stringp pico8-font-file) (file-readable-p pico8-font-file))
    (user-error "Font file not found/readable: %s" pico8-font-file))
  (let* ((target-dir (expand-file-name "~/.local/share/fonts/"))
         (target (expand-file-name (file-name-nondirectory pico8-font-file) target-dir)))
    (make-directory target-dir t)
    (copy-file pico8-font-file target t)
    (when (executable-find "fc-cache")
      (call-process "fc-cache" nil 0 nil "-f" target-dir))
    (message "Installed font to %s (restart GUI Emacs to pick up font list)" target)))

(defcustom pico8-set-column-fill t
  "If enabled, set column fill to 32. This represents what can be shown on one line in the pico-8 application."
  :type 'boolean
  :group 'pico8)

(defcustom pico8-line-spacing 0.25
  "Extra line spacing for `pico8-mode' when `pico8-use-font' is enabled.

The PICO-8 font can look vertically cramped in Emacs due to font metrics.
This adds additional leading between lines."
  :type 'number
  :group 'pico8)

(defcustom pico8-executable-path ""
  "Full path to pico8 executable."
  :type 'file
  :group 'pico8)

(defcustom pico8-editor-ui t
  "If non-nil, apply PICO-8 editor-like UI tweaks in `pico8-mode' buffers."
  :type 'boolean
  :group 'pico8)

(defcustom pico8-editor-bg "#1d2b53"
  "Background color used for PICO-8 editor-like styling."
  :type 'string
  :group 'pico8)

(defcustom pico8-editor-fg "#fff1e8"
  "Foreground color used for PICO-8 editor-like styling."
  :type 'string
  :group 'pico8)

(defcustom pico8-editor-var "#c2c3c7"
  "Variable identifier color used for PICO-8 editor-like styling."
  :type 'string
  :group 'pico8)

(defcustom pico8-editor-blue "#29adff"
  "Blue accent color used for PICO-8 editor-like styling."
  :type 'string
  :group 'pico8)

(defcustom pico8-editor-fn "#00e436"
  "Function/builtin color used for PICO-8 editor-like styling."
  :type 'string
  :group 'pico8)

(defcustom pico8-editor-kw "#ff77a8"
  "Keyword color used for PICO-8 editor-like styling."
  :type 'string
  :group 'pico8)

(defcustom pico8-editor-comment "#83769c"
  "Comment color used for PICO-8 editor-like styling."
  :type 'string
  :group 'pico8)

(defcustom pico8-editor-cursor "#ff004d"
  "Cursor background color used for PICO-8 editor-like styling."
  :type 'string
  :group 'pico8)

(defcustom pico8-editor-blink-interval 0.22
  "Cursor blink interval in PICO-8 buffers."
  :type 'number
  :group 'pico8)

(defcustom pico8-editor-blink-delay 0.15
  "Cursor blink delay in PICO-8 buffers."
  :type 'number
  :group 'pico8)

(defcustom pico8-editor-blink-forever t
  "If non-nil, keep cursor blinking indefinitely in PICO-8 buffers."
  :type 'boolean
  :group 'pico8)

(defvar-local pico8--face-remaps nil)
(defvar-local pico8--cursor-sync-installed nil)

(defun pico8--cursor-save-frame-state (frame)
  (unless (frame-parameter frame 'pico8--saved-cursor-color)
    (set-frame-parameter frame 'pico8--saved-cursor-color
                         (or (frame-parameter frame 'cursor-color)
                             (face-attribute 'cursor :background frame nil)))
    (set-frame-parameter frame 'pico8--saved-cursor-type
                         (frame-parameter frame 'cursor-type))))

(defun pico8--cursor-restore-frame-state (frame)
  (when-let ((color (frame-parameter frame 'pico8--saved-cursor-color)))
    (set-frame-parameter frame 'cursor-color color))
  (when-let ((ctype (frame-parameter frame 'pico8--saved-cursor-type)))
    (set-frame-parameter frame 'cursor-type ctype))
  (set-frame-parameter frame 'pico8--saved-cursor-color nil)
  (set-frame-parameter frame 'pico8--saved-cursor-type nil))

(defun pico8--sync-cursor ()
  "Keep cursor settings consistent when moving across buffers."
  (when (display-graphic-p)
    (let* ((frame (selected-frame))
           (buf (window-buffer (selected-window))))
      (cond
       ((and (buffer-live-p buf)
             (buffer-local-value 'pico8--cursor-sync-installed buf))
        (pico8--cursor-save-frame-state frame)
        ;; Cover the full character cell to include font padding.
        (setq x-stretch-cursor nil)
        (modify-frame-parameters frame '((cursor-type . box)))
        ;; Some builds ignore the `cursor' face background and use cursor-color.
        (set-cursor-color pico8-editor-cursor))
       (t
        (pico8--cursor-restore-frame-state frame))))))

(defun pico8--apply-editor-faces ()
  (setq pico8--face-remaps nil)
  (when (fboundp 'display-line-numbers-mode)
    (display-line-numbers-mode -1))
  ;; global-hl-line-mode can re-enable hl-line overlays; force it off and
  ;; also remap hl-line to background so it becomes invisible.
  (setq-local hl-line-mode nil)
  (when (fboundp 'hl-line-mode) (hl-line-mode -1))
  (when (boundp 'hl-line-overlay)
    (ignore-errors (delete-overlay hl-line-overlay)))

  (push (face-remap-add-relative 'default
                                 `(:background ,pico8-editor-bg
                                   :foreground ,pico8-editor-fg))
        pico8--face-remaps)
  (push (face-remap-add-relative 'hl-line
                                 `(:background ,pico8-editor-bg :extend t))
        pico8--face-remaps)
  (push (face-remap-add-relative 'font-lock-variable-name-face
                                 `(:foreground ,pico8-editor-var))
        pico8--face-remaps)
  (push (face-remap-add-relative 'font-lock-string-face
                                 `(:foreground ,pico8-editor-blue))
        pico8--face-remaps)
  (push (face-remap-add-relative 'font-lock-function-name-face
                                 `(:foreground ,pico8-editor-fn))
        pico8--face-remaps)
  (push (face-remap-add-relative 'font-lock-keyword-face
                                 `(:foreground ,pico8-editor-kw :weight bold))
        pico8--face-remaps)
  (push (face-remap-add-relative 'font-lock-builtin-face
                                 `(:foreground ,pico8-editor-fn))
        pico8--face-remaps)
  (push (face-remap-add-relative 'font-lock-comment-face
                                 `(:foreground ,pico8-editor-comment))
        pico8--face-remaps)
  ;; Cursor: background only, keep glyph color (where supported).
  (push (face-remap-add-relative 'cursor
                                 `(:background ,pico8-editor-cursor
                                   :foreground unspecified))
        pico8--face-remaps))

(defun pico8--apply-editor-ui ()
  (when pico8-editor-ui
    (pico8--apply-editor-faces)
    (setq-local blink-cursor-interval pico8-editor-blink-interval)
    (setq-local blink-cursor-delay pico8-editor-blink-delay)
    (when pico8-editor-blink-forever
      (setq-local blink-cursor-blinks 0))
    (blink-cursor-mode 1)
    ;; Keep cursor in sync while this buffer is active.
    (setq-local pico8--cursor-sync-installed t)
    (add-hook 'post-command-hook #'pico8--sync-cursor nil t)
    (pico8--sync-cursor)))

(defface pico8--non-lua-overlay
  '((((background light)) :foreground "grey90")
    (((background dark)) :foreground "grey10"))
  "Face for non-Lua sections of the p8 file"
  :group 'pico8)

(defvar pico8--lua-block-start nil "")
(make-variable-buffer-local 'pico8--lua-block-start)

(defvar pico8--lua-block-end nil "")
(make-variable-buffer-local 'pico8--lua-block-end)

(defvar pico8--lua-block-end-tag nil "")
(make-variable-buffer-local 'pico8--lua-block-end-tag)

(cl-defstruct (pico8-symbol (:constructor pico8-symbol--create))
  "A Lua symbol on pico8 mode."
  symbol line column signature location doc doc-position arguments)

(defun pico8--make-builtin (symbol signature &optional doc)
  "Constructs a built-in plist with symbol, signature and documentation."
  (pico8-symbol--create
   :symbol symbol
   :signature (concat "function " symbol "(" signature ")")
   :arguments signature
   :doc doc))

(defconst pico8--builtins-list
  '(("clip" "[x y w h]")
    ("pget" "x y")
    ("pset" "x y c")
    ("sget" "x y")
    ("sset" "x y c")
    ("fget" "n [f]")
    ("fset" "n [f] v")
    ;; print( text, [x,] [y,] [color] )
    ("print" "str [x y [col]]")
    ;; printh( str, [filename,] [overwrite] )
    ("printh" "str [filename overwrite]")
    ("cursor" "x y")
    ("color" "col")
    ("cls" "[col]")
    ("camera" "[x y]")
    ("circ" "x y r [col]")
    ("circfill" "x y r [col]")
    ("line" "x0 y0 x1 y1 [col]")
    ("rect" "x0 y0 x1 y1 [col]")
    ("rectfill" "x0 y0 x1 y1 [col]")
    ("pal" "c0 c1 [p]")
    ("palt" "c t")
    ("spr" "n x y [w h] [flip_x] [flip_y]")
    ("sspr" "sx sy sw sh dx dy [dw dh] [flip_x] [flip_y]")
    ("fillp" "p")
    ("add" "t v")
    ("del" "t v")
    ("all" "t")
    ("foreach" "t f")
    ("pairs" "t")
    ("btn" "[i [p]]")
    ("btnp" "[i [p]]")
    ("sfx" "n [channel [offset [length]]]")
    ("music" "[n [fade_len [channel_mask]]]")
    ("mget" "x y")
    ("mset" "x y v")
    ("map" "cel_x cel_y sx sy cel_w cel_h [layer]")
    ("peek" "addr")
    ("poke" "addr val")
    ("peek4" "addr")
    ("poke4" "addr val")
    ("memcpy" "dest_addr source_addr len")
    ("reload" "dest_addr source_addr len [filename]")
    ("cstore" "dest_addr source_addr len [filename]")
    ("memset" "dest_addr val len")
    ("max" "x y" "Returns maximum value of x and y")
    ("min" "x y" "Returns minimum value of x and y")
    ("mid" "x y z" "Returns middle value of x, y and z")
    ("flr" "x" "Floor x")
    ("ceil" "x" "Ceil x")
    ("cos" "x" "Cosine of x")
    ("sin" "x" "Sine of x")
    ("atan2" "dx dy")
    ("sqrt" "x")
    ("abs" "x")
    ("rnd" "x")
    ("srand" "x")
    ("band" "x y" "Boolean and")
    ("bor" "x y" "Boolean or")
    ("bxor" "x y" "Boolean xor")
    ("bnot" "x" "Boolean not")
    ("rotl" "x y" "Rotate right")
    ("rotr" "x y" "Ritate left")
    ("shl" "x n" "Shift left")
    ("shr" "x n" "Shift right")
    ("lshr" "x n" "Logical shift right")
    ("menuitem" "Index [label callback]")
    ("sub" "s a b")
    ("type" "val")
    ("tostr" "val [hex]")
    ("tonum" "val")
    ("cartdata" "id")
    ("dget" "index")
    ("dset" "index value")
    ("setmetatable" "t, m" "Get metatable")
    ("getmetatable" "t" "Set metatable")
    ("cocreate" "f")
    ("coresume" "c [p0 p1 ..]")
    ("costatus" "c")
    ("yield" "" "Yield coroutine execution")))

(defconst pico8--palette
  (concat "\"0 c #000000\",\n"
          "\"1 c #1d2b53\",\n"
          "\"2 c #7e2553\",\n"
          "\"3 c #008751\",\n"
          "\"4 c #ab5236\",\n"
          "\"5 c #5f574f\",\n"
          "\"6 c #c2c3c7\",\n"
          "\"7 c #fff1e8\",\n"
          "\"8 c #ff004d\",\n"
          "\"9 c #ffa300\",\n"
          "\"a c #ffec27\",\n"
          "\"b c #00e436\",\n"
          "\"c c #29adff\",\n"
          "\"d c #83769c\",\n"
          "\"e c #ff77a8\",\n"
          "\"f c #ffccaa\",\n"
          ;; alternate palette
          "\"g c #2f1e1b\",\n"
          "\"h c #142337\",\n"
          "\"i c #472638\",\n"
          "\"j c #005459\",\n"
          "\"k c #7a322e\",\n"
          "\"l c #4d363d\",\n"
          "\"m c #a58679\",\n"
          "\"n c #f6ec89\",\n"
          "\"o c #ca194f\",\n"
          "\"p c #ff6a34\",\n"
          "\"q c #9ee452\",\n"
          "\"r c #00b253\",\n"
          "\"s c #005eaf\",\n"
          "\"t c #794863\",\n"
          "\"u c #ff6c5c\",\n"
          "\"v c #ff9a83\",\n"))

(defconst pico8--builtins
  (seq-map (lambda (x) (apply #'pico8--make-builtin x)) pico8--builtins-list))

(defconst pico8--builtins-symbols
  (seq-map #'pico8-symbol-symbol pico8--builtins))

(defconst pico8--builtins-regex
  (concat "\\_<"
          (regexp-opt pico8--builtins-symbols t)
          "\\_>"))

(defun pico8--has-documentation-p ()
  "Is pico8-documentation-file set and does the file exits?"
  (and (> (length pico8-documentation-file) 0)
       (file-exists-p pico8-documentation-file)))

(defun pico8--find-documentation (symbol arguments)
  "Find a part of documentation for `symbol' with `arguments'.
Does a dumb lookup which can break if the file format changes.

Returns string and location in the documentation file."
  (if (pico8--has-documentation-p)
      (with-temp-buffer
        (insert-file-contents pico8-documentation-file)
        (save-excursion
          (goto-char 1)
          (when (search-forward-regexp (concat "\t" (regexp-quote symbol) " +" (regexp-quote arguments)) nil t)
            (let ((fun-start (point)))
              (when (search-forward-regexp "\t\t[A-Za-z]" nil t)
                (let ((start (1- (point)))
                      (end (line-end-position)))
                  (cons (buffer-substring-no-properties start end) fun-start)))))))
    (error "Define pico8-documentation-file to use documentation features")))

;;;###autoload
(defun pico8-build-documentation ()
  "Rebuild pico8 function documentation.
Requires `pico8-documentation-file' to be set."
  (interactive)
  (seq-do (lambda (s)
            (if (pico8-symbol-doc s)
                s
              (let* ((symbol (pico8-symbol-symbol s))
                     (arguments (pico8-symbol-arguments s))
                     (doc (pico8--find-documentation symbol arguments)))
                (setf (pico8-symbol-doc s) (car doc))
                (setf (pico8-symbol-doc-position s) (cdr doc)))))
          pico8--builtins)
  nil)

(defun pico8--modified-lua-font-lock ()
  "Return a modified `lua-font-lock-keywords'.

- Remove the Lua builtin rule that matches `loadstring' (so PICO-8 can redefine it).
- Add PICO-8 builtins as `font-lock-builtin-face'.
- Add number highlighting as `font-lock-string-face' (to match the PICO-8 editor)."
  (let* ((without-builtins
          (seq-filter
           (lambda (x)
             (let ((re (car-safe x)))
               (not (and (stringp re)
                         (string-match-p "loadstring" re)))))
           lua-font-lock-keywords))
         ;; PICO-8/Lua-ish numbers: hex, int, float (.5 and 0.5 both)
         ;; We intentionally avoid \\_<...\\_> on the *right* side so patterns
         ;; like X=5Y=0 still highlight 5 and 0 as number literals.  But we do
         ;; require a non-identifier character (or BOL) on the left so digits
         ;; inside identifiers like S_2 keep the identifier's color.
         (pico8--number-regex
          (rx (or bol (not (any "A-Za-z0-9_")))
              (group
               (or (seq "0" (any "xX") (+ (any "0-9a-fA-F")))
                   (seq (+ (any "0-9")) (opt "." (+ (any "0-9"))))
                   (seq "." (+ (any "0-9"))))))))
    (append
     `(
       (,pico8--builtins-regex 1 font-lock-builtin-face)
       (,pico8--number-regex 1 font-lock-string-face)
       ("\\_<\\(?:[Tt][Rr][Uu][Ee]\\|[Ff][Aa][Ll][Ss][Ee]\\|[Nn][Ii][Ll]\\)\\_>"
        0 font-lock-string-face)
       ;; Shorthand like X=5Y=0: treat the stuck "Y" as an identifier.
       ;; We only do this when the identifier is immediately followed by "=",
       ;; so we don't accidentally color parts of other tokens.
       (,(rx (or (seq "0" (any "xX") (+ (any "0-9a-fA-F")))
                 (seq (+ (any "0-9")) (opt "." (+ (any "0-9"))))
                 (seq "." (+ (any "0-9"))))
             (group (seq (any "A-Za-z_") (* (any "A-Za-z0-9_"))))
             (* (any " \t"))
             "=")
        1 font-lock-variable-name-face)
       ;; Function call: name(...)
       (,(rx (group (seq (any "A-Za-z_") (* (any "A-Za-z0-9_"))))
             (* (any " \t"))
             "(")
        1 font-lock-function-name-face)
       ;; Method/field call: obj.method(...) / obj:method(...)
       (,(rx (any ".:")
             (* (any " \t"))
             (group (seq (any "A-Za-z_") (* (any "A-Za-z0-9_"))))
             (* (any " \t"))
             "(")
        1 font-lock-function-name-face))
     without-builtins
     ;; In the PICO-8 editor, ordinary identifiers are rendered in a muted
     ;; color (distinct from punctuation).  We approximate that by coloring
     ;; any symbol-like word as a variable name, but only when nothing else
     ;; (keyword, builtin, string, comment, etc.) has already fontified it.
     `((,(rx symbol-start
             (group (seq (any "A-Za-z_")
                         (* (any "A-Za-z0-9_"))))
             symbol-end)
        1 'font-lock-variable-name-face keep)))))

;; Adapted from lua-mode.el (lua-send-defun)
(defun pico8--lua-function-bounds ()
  "Return Lua function bounds, or nil if not in a function."
  (save-excursion
    (let ((pos (point))
          (start (if (save-match-data (looking-at "^function[ \t]"))
                     (point)
                   (lua-beginning-of-proc)
                   (point)))
          (end (progn (lua-end-of-proc) (point))))
      (if (and (>= pos start) (< pos end))
          (cons start end)
        nil))))

(defun pico8--match-column (SUBEXPR)
  "Return a position of column at start of text matched by last search."
  (- (match-beginning SUBEXPR) (line-beginning-position)))

;; this is copied from lua-mode.el to match its functionality
(defconst pico8--lua-function-regex
  (lua-rx (or bol ";") ws (opt (seq (symbol "local") ws)) lua-funcheader))

(defconst pico8--lua-variable-regex
  (lua-rx (or bol ";") ws (opt (seq (group-n 1 (symbol "local")) ws)) (group-n 2 lua-funcname) ws "="))

(defvar pico8--lua-argument-regex
  (lua-rx (seq (group-n 1 lua-name))))

(defun pico8--find-all-functions ()
  "Find and return all lua functions from the current buffer."
  (let ((symbols))
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (or pico8--lua-block-start 1))
        (while (search-forward-regexp pico8--lua-function-regex
                                      pico8--lua-block-end t 1)
          (let ((symbol (pico8-symbol--create
                         :symbol (match-string-no-properties 1)
                         :line (line-number-at-pos)
                         :column (pico8--match-column 1)
                         :signature (thing-at-point 'line t)
                         :location (match-beginning 1))))
            ;; Augment with arguments
            (save-excursion
              (goto-char (match-beginning 0))
              (when (search-forward "(" (line-end-position) t 1)
                (let ((arguments '()))
                  (while (search-forward-regexp pico8--lua-argument-regex
                                                (line-end-position) t 1)
                    (push (match-string-no-properties 1) arguments))
                  (setf (pico8-symbol-arguments symbol) (string-join (reverse arguments) " ")))))
            (push symbol symbols)))))
    symbols))

(defun pico8--find-variables ()
  "Find and return lua variables.
Do some scoping with local variables."
  (let ((variables))
    (save-excursion
      (save-restriction
        (widen)
        (let ((fn-bounds (pico8--lua-function-bounds)))
          (goto-char (or pico8--lua-block-start 1))
          (while (search-forward-regexp pico8--lua-variable-regex
                                        pico8--lua-block-end t 1)
            (let ((is-local (match-string-no-properties 1))
                  (variable (match-string-no-properties 2))
                  (line-num (line-number-at-pos)))
              (when (or (not is-local)
                        (not fn-bounds)
                        (<= (car fn-bounds) (point) (cdr fn-bounds)))
                (push (pico8-symbol--create
                       :symbol variable
                       :line (line-number-at-pos)
                       :column (pico8--match-column 2)
                       :location (match-beginning 2))
                      variables)))))))
    variables))

;; TODO: Reduce code duplication in this pattern
(defun pico8--find-current-function-arguments ()
  "Find and return lua arguments of the current function."
  (let ((arguments))
    (save-excursion
      (save-restriction
        (widen)
        (when-let* ((fn-bounds (pico8--lua-function-bounds)))
          (goto-char (car fn-bounds))
          (when (search-forward "(" (cdr fn-bounds) t 1)
            (while (search-forward-regexp pico8--lua-argument-regex
                                          (line-end-position) t 1)
              (push (pico8-symbol--create
                     :symbol (match-string-no-properties 1)
                     :line (line-number-at-pos)
                     :column (pico8--match-column 1)
                     :location (match-beginning 1))
                    arguments))))))
    arguments))

(defun pico8--filter-symbol (symbol &optional symbols)
  "Find all symbols named symbol."
  (seq-filter (lambda (s) (string= symbol (pico8-symbol-symbol s)))
              (or symbols (pico8--completion-symbols-without-builtins))))

(defun pico8--find-symbol (symbol &optional symbols)
  "Find a single symbol named symbol.
Returns the first match in case of multiple matches."
  (seq-find (lambda (s) (string= symbol (pico8-symbol-symbol s)))
            (or symbols (pico8--find-all-functions))))

(defun pico8--make-xref-of-symbol (symbol)
  "Make a xref of a symbol."
  (xref-make (pico8-symbol-symbol symbol)
             (xref-make-file-location buffer-file-name
                                      (pico8-symbol-line symbol)
                                      (pico8-symbol-column symbol))))

(cl-defmethod xref-backend-identifier-at-point
  ((_backend (eql xref-pico8)))
  "pico8 xref identifier-at-point."
  (lua-funcname-at-point))

(cl-defmethod xref-backend-definitions
  ((_backend (eql xref-pico8)) symbol)
  "pico8 xref definitions."
  (seq-map #'pico8--make-xref-of-symbol
           (pico8--filter-symbol symbol)))

(cl-defmethod xref-backend-apropos
  ((_backend (eql xref-pico8)) symbol)
  "pico8 xref apropos."
  (seq-map #'pico8--make-xref-of-symbol
           (pico8--filter-symbol symbol)))

(cl-defmethod xref-backend-identifier-completion-table
  ((_backend (eql xref-pico8)))
  "pico8 xref identifier completion table."
  (pico8--completion-symbols-without-builtins))

(defun xref-pico8-backend ()
  "Return pico8 xref backend name."
  'xref-pico8)

(defun pico8--completion-symbols ()
  "Return a list of all completion symbols.
Including Lua and pico8 built-ins."
  (append pico8--builtins
          (pico8--find-all-functions)
          (pico8--find-variables)
          (pico8--find-current-function-arguments)))

(defun pico8--completion-symbols-without-builtins ()
  "Return a list of all completion symbols.
Including Lua and pico8 built-ins."
  (append (pico8--find-all-functions)
          (pico8--find-variables)
          (pico8--find-current-function-arguments)))

;; based on lua-funcname-at-point code from lua-mode.el
(defun pico8--lua-funcname-bounds-at-point ()
  (with-syntax-table (copy-syntax-table)
    (modify-syntax-entry ?. "_")
    (bounds-of-thing-at-point 'symbol)))

(defun pico8--company-doc-buffer (symbol)
  (cons
   (with-current-buffer (get-buffer-create "*company-documentation*")
     (erase-buffer)
     (insert-file-contents pico8-documentation-file)
     (current-buffer))
   (pico8-symbol-doc-position symbol)))

(defun pico8--company-location (symbol)
  (cons (current-buffer)
        (pico8-symbol-location symbol)))

(defun pico8--completion-at-point-exit-function (arg status symbol)
  (when (boundp 'company-mode)
    (when-let* ((arguments (pico8-symbol-arguments symbol)))
      (let* ((split-args (split-string arguments))
             (args-template (concat "(" (string-join split-args ", ") ")")))
        (insert args-template)
        (company-template-c-like-templatify
         (concat arg args-template))))))

(defun pico8--completion-at-point ()
  (when-let* ((bounds (pico8--lua-funcname-bounds-at-point))
              (symbols (pico8--completion-symbols))
              (symbol-names (seq-map 'pico8-symbol-symbol symbols)))
    (fset 'symbol (lambda (arg) (pico8--find-symbol arg symbols)))
    (list (car bounds)
          (cdr bounds)
          symbol-names
          :exclude 'no
          :company-docsig (lambda (arg) (pico8-symbol-signature (symbol arg)))
          :annotation-function (lambda (arg) (pico8-symbol-doc (symbol arg)))
          :company-doc-buffer (lambda (arg)
                                (pico8--company-doc-buffer (pico8--find-symbol arg symbols)))
          :company-location (lambda (arg)
                              (pico8--company-location (pico8--find-symbol arg symbols)))
          :exit-function (lambda (arg status)
                           (pico8--completion-at-point-exit-function
                            arg status (pico8--find-symbol arg symbols))))))

(defun pico8--eldoc-documentation ()
  "eldoc documentation function for pico8"
  (save-excursion
    (condition-case nil
        (backward-up-list nil t)
      (error nil))
    (when-let* ((symbol (pico8--find-symbol (lua-funcname-at-point)
                                            (pico8--completion-symbols)))
                (signature (pico8-symbol-signature symbol)))
      (concat signature
              (when-let* ((doc (pico8-symbol-doc symbol)))
                (concat ": " doc))))))

(defun pico8--put-non-lua-overlay (beg end)
  "Put pico8 non-Lua overlay in region."
  (overlay-put (make-overlay beg end) 'face 'pico8--non-lua-overlay))

(defun pico8--do-scan-for-lua-block-in-region (beg end)
  "Actually run the scan for pico8--scan-for-lua-block-in-region"
  (save-excursion
    (goto-char beg)
    (while (search-forward-regexp "^__\\([a-z]+\\)__$" end t 1)
      (if (string= "lua" (match-string 1))
          (setq pico8--lua-block-start (match-end 0))
        (when (and (> (match-beginning 0) (or pico8--lua-block-start 1))
                   (or (not pico8--lua-block-end)
                       (string= (match-string-no-properties 1) pico8--lua-block-end-tag)
                       (< (match-beginning 0) pico8--lua-block-end)))
          (setq pico8--lua-block-end-tag (match-string-no-properties 1))
          (setq pico8--lua-block-end (match-beginning 0)))))))

(defun pico8--scan-for-lua-block-in-region (beg end)
  "Try to find lua block in the region.
If a __lua__ line is found, then that is set as the start for a
lua block. If other __def__ lines are found, they might be chosen
as an end position for the lua block."
  (when (and pico8--lua-block-start (<= beg pico8--lua-block-start end))
    (setq pico8--lua-block-start nil))
  (when (and pico8--lua-block-end (<= beg pico8--lua-block-end end))
    (setq pico8--lua-block-end nil))
  (pico8--do-scan-for-lua-block-in-region beg end)
  (unless (and pico8--lua-block-start pico8--lua-block-end)
    (pico8--do-scan-for-lua-block-in-region (point-min) (point-max))))

(defun pico8--line-length (point)
  "Get line length at `point'"
  (save-excursion
    (goto-char point)
    (- (line-end-position) (line-beginning-position))))

(defun pico8--get-scaled-image-data (start end)
  "Get scaled pico8 image data in in the region between `start' and `end'.
Doubles the image data, otherwise it's too tiny to look at."
  (string-join
   (seq-map
    (lambda (x)
      (let ((line (concat "\"" (replace-regexp-in-string "\\([0-9a-v]\\)" "\\1\\1" x) "\"")))
        (concat line ",\n" line)))
    (split-string (buffer-substring-no-properties start end) "\n" t))
   ",\n"))

(defun pico8--generate-image (start end)
  "Generate an image from pico8 data in the region between `start' and `end'."
  (let ((height (number-to-string (* 2 (count-lines start end))))
        (width (number-to-string (* 2 (pico8--line-length start)))))
    (create-image
     (concat "/* XPM */\nstatic char *xpm[] ={\n"
             "\"" width " " height " 32 1\",\n"
             pico8--palette
             (pico8--get-scaled-image-data start end))
     'xpm t)))

(defvar pico8--gfx-overlays nil '())
(make-variable-buffer-local 'pico8--gfx-overlays)

(defun pico8--put-gfx-overlay (beg end)
  "Put pico8 gfx overlay in region."
  (interactive "r")
  (setq-local pico8--gfx-overlays
              (seq-filter
               (lambda (overlay)
                 (if (and (= beg (overlay-start overlay))
                          (= end (overlay-end overlay)))
                     (delete-overlay overlay)
                   t))
               pico8--gfx-overlays))
  (let ((overlay (make-overlay beg end)))
    (overlay-put overlay 'display (pico8--generate-image beg end))
    (push overlay pico8--gfx-overlays))
  nil)

(defun pico8--create-image-overlays ()
  "Create XPM image overlays over pico8 image data"
  (save-excursion
    (save-restriction
      (widen)
      (goto-char 1)
      (while (search-forward-regexp "__\\([a-z]+\\)" nil t 1)
        (forward-line 1)
        (let ((start (point)))
          (when (or (string= "gfx" (match-string-no-properties 1))
                    (string= "label" (match-string-no-properties 1)))
            (save-excursion
              (if (search-forward-regexp "__[a-z]+__" nil t 1)
                  (progn
                    (forward-line -1)
                    (end-of-line))
                (forward-paragraph))
              (pico8--put-gfx-overlay start (point)))))))))

(defun pico8--remove-image-overlays ()
  "Remove all XPM image overlays"
  (seq-do (lambda (overlay) (delete-overlay overlay)) pico8--gfx-overlays)
  (setq-local pico8--gfx-overlays '()))

(defun pico8--syntax-propertize (beg end)
  "pico8 syntax-table propertize function.
Sets an overlay on non-Lua code. And also keeps track of lua code
region."
  (lua--propertize-multiline-bounds beg end)
  (pico8--scan-for-lua-block-in-region beg end)
  ;; TODO: Revamp
  (when pico8-dim-non-code-sections
    (remove-overlays (point-min) (point-max) 'face 'pico8--non-lua-overlay)
    (when pico8--lua-block-start
      (pico8--put-non-lua-overlay (point-min) pico8--lua-block-start))
    (when pico8--lua-block-end
      (pico8--put-non-lua-overlay pico8--lua-block-end (point-max)))
    ))

(defvar pico8--process nil
  "The currently running PICO-8 process")

(defun pico8--process-running? ()
  "Return t if a PICO-8 process is already running"
  (when pico8--process
    (eq (process-status pico8--process)
        'run)))

(defun pico8--confirm-and-kill-process ()
  (when (y-or-n-p "PICO-8 is already running. Kill process?")
    (pico8-kill-process)))

(defun pico8-run-cartridge ()
  "Run the file visited by the current buffer as PICO-8 cartridge"
  (interactive)
  (when (pico8--process-running?)
    (pico8--confirm-and-kill-process))
  (setq pico8--process (start-process "pico8-process" "pico8-output"
                                      pico8-executable-path "-run" (buffer-file-name))))

(defun pico8-kill-process ()
  "Kill the currently running PICO-8 process by sending SIGQUIT"
  (interactive)
  (quit-process pico8--process))

;;;###autoload
(define-derived-mode pico8-mode lua-mode "pico8"
  "pico8 major mode."
  (setq-local lua-font-lock-keywords (pico8--modified-lua-font-lock))
  ;; PICO-8 API is case-insensitive; users also often type in uppercase.
  (setq-local font-lock-keywords-case-fold-search t)
  (font-lock-refresh-defaults)
  (pico8--apply-editor-ui)
  (add-to-list 'xref-backend-functions #'xref-pico8-backend)
  (add-to-list 'completion-at-point-functions #'pico8--completion-at-point)
  (setq-local eldoc-documentation-function #'pico8--eldoc-documentation)
  (setq-local syntax-propertize-function #'pico8--syntax-propertize)
  (when (pico8--has-documentation-p)
    (pico8-build-documentation))
  (when (and pico8-create-images
             (display-graphic-p)
             (image-type-available-p 'xpm))
    (add-hook 'before-revert-hook 'pico8--remove-image-overlays)
    (add-hook 'after-revert-hook 'pico8--create-image-overlays)
    (pico8--create-image-overlays))
  (when pico8-set-column-fill
    (set-fill-column 32))
  (when pico8-use-font
    (if (find-font (font-spec :family pico8-font-family))
        (progn
          ;; Don't force :height here — it would override text-scale
          ;; (C-x C-M-+/-/0).  Users can scale the buffer normally.
          (setq buffer-face-mode-face `(:family ,pico8-font-family))
          (setq-local line-spacing pico8-line-spacing)
          (buffer-face-mode))
      (message "No '%s' font installed. Available here: https://www.lexaloffle.com/bbs/?tid=3760"
               pico8-font-family))))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.p8\\'" . pico8-mode))

(provide 'pico8-mode)

;;; pico8-mode.el ends here
