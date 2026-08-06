;;; cerebro-modeline.el --- a status line made of segments -*- lexical-binding: t; -*-

;; Emacs' default mode line shows, in order: coding system, line ending,
;; modified flags, buffer name, position, major mode, and every active
;; minor mode. For this repo that is roughly one useful item and six
;; constants -- and the one thing actually worth watching (an org-clock
;; running, which cerebro-time.el mirrors into Timewarrior) is absent
;; unless you turn it on.
;;
;; So the status line here is built from *segments*: small pure functions
;; that each return a string or nil, listed in two data variables (left
;; group, right group). Adding an indicator is adding a function and a
;; symbol to a list; removing one is deleting a symbol -- no format-string
;; surgery, and every segment is unit-testable in batch (tests/
;; cerebro-modeline-tests.el) because none of them touches redisplay.
;;
;; What earns a place, and why:
;;   ● modified     the only file-state flag that ever changes here
;;   name           with the notes/-relative directory, since twenty notes
;;                  named after twenty theorems live in different courses
;;   clock          what you are timing, because it is *costing* you time
;;   branch         a notes repo with git hooks as gates
;;   env            pinned-guix vs host PATH: the single most confusing
;;                  difference in behaviour (see cerebro-guix.el)
;;
;; No icons, no external package: everything renders in a terminal frame
;; exactly as in a graphical one.

(require 'cerebro-guix) ;; cerebro-guix-inside-p
(require 'org-clock)
(require 'vc-hooks)

(defgroup cerebro-modeline nil
  "The cerebro status line."
  :group 'cerebro)

(defface cerebro-modeline-emphasis '((t :inherit mode-line-emphasis))
  "Face for the buffer name -- the one thing you look for first.")

(defface cerebro-modeline-dim '((t :inherit shadow))
  "Face for context that must be readable but never draw the eye.")

(defface cerebro-modeline-alert '((t :inherit warning))
  "Face for state that should be noticed: unsaved changes, a running clock.")

(defcustom cerebro-modeline-left '(state buffer position narrow)
  "Segments shown on the left, in order.
Symbols must be keys of `cerebro-modeline-segment-alist'."
  :type '(repeat symbol)
  :group 'cerebro-modeline)

(defcustom cerebro-modeline-right '(clock vc mode env)
  "Segments shown right-aligned, in order."
  :type '(repeat symbol)
  :group 'cerebro-modeline)

(defcustom cerebro-modeline-clock-width 24
  "Maximum width of the org-clock segment, in columns."
  :type 'integer
  :group 'cerebro-modeline)

;; -- Segments -----------------------------------------------------------
;; Each returns a string to show, or nil for "nothing to say". They read
;; the current buffer and nothing else, which is what makes them testable
;; with `with-temp-buffer'.

(defun cerebro-modeline-segment-state ()
  "Buffer state: unsaved changes, or read-only."
  (cond
   (buffer-read-only (propertize "◇" 'face 'cerebro-modeline-dim))
   ((buffer-modified-p) (propertize "●" 'face 'cerebro-modeline-alert))))

(defun cerebro-modeline-buffer-context ()
  "The notes/-relative directory of the current file, with a trailing /.
Nil for a buffer with no file, or one sitting directly in notes/. This is
the segment that makes twenty `example.org's tellable apart -- the path
carries the course, which the file name deliberately does not."
  (let ((file (buffer-file-name)))
    (when (and file (boundp 'org-directory) org-directory)
      (let ((dir (file-name-directory (expand-file-name file)))
            (root (file-name-as-directory (expand-file-name org-directory))))
        (when (and (string-prefix-p root dir) (> (length dir) (length root)))
          (substring dir (length root)))))))

(defun cerebro-modeline-segment-buffer ()
  "Buffer name, prefixed by its place in the notes tree.
`%' is doubled in both halves: the line is handed back to
`format-mode-line', which reads `%b'/`%f' as format specifications --
so a note called `50%-bound.org' would otherwise print its own name
wrong, or something else entirely."
  (concat
   (when-let* ((context (cerebro-modeline-buffer-context)))
     (propertize (string-replace "%" "%%" context) 'face 'cerebro-modeline-dim))
   (propertize (string-replace "%" "%%" (buffer-name))
               'face 'cerebro-modeline-emphasis)))

(defun cerebro-modeline-segment-position ()
  "Line and column, the two coordinates that ever matter in a note.
Computed here rather than handed to redisplay as \"%l:%c\" for two
reasons: the right-alignment in `cerebro-modeline-render' measures the
string it is given (and a %-construct is four columns wide as text,
two to six once drawn), and %-constructs only expand inside a real
window -- in batch, which is where the tests run, they expand to
nothing."
  (propertize (format "%d:%d" (line-number-at-pos (point) t) (current-column))
              'face 'cerebro-modeline-dim))

(defun cerebro-modeline-segment-narrow ()
  "Marker for a narrowed buffer -- invisible state that changes what you see."
  (when (buffer-narrowed-p)
    (propertize "narrow" 'face 'cerebro-modeline-alert)))

(defun cerebro-modeline-clock-string ()
  "The running org-clock as \"HEADING 12m\", or nil when nothing is clocked.
Pure formatting split from the segment so the truncation is testable."
  (when (org-clocking-p)
    (let* ((minutes (org-clock-get-clocked-time))
           ;; Brackets out (they are link syntax in a heading), and `%'
           ;; doubled -- an issue titled "95% of the proof" must not turn
           ;; into a format specification on the way to redisplay.
           (heading (string-replace
                     "%" "%%"
                     (replace-regexp-in-string
                      "[][]" "" (or org-clock-heading "task"))))
           (time (format "%dm" minutes))
           ;; Keep the elapsed time whole and cut the heading: "which
           ;; task" is guessable from three words, "how long" is not.
           (room (max 3 (- cerebro-modeline-clock-width (length time) 1))))
      (concat (truncate-string-to-width heading room nil nil "…") " " time))))

(defun cerebro-modeline-segment-clock ()
  (when-let* ((clock (cerebro-modeline-clock-string)))
    (propertize clock 'face 'cerebro-modeline-alert)))

(defun cerebro-modeline-segment-vc ()
  "Current git branch, without the backend prefix Emacs normally shows."
  (when (and vc-mode (stringp vc-mode))
    (propertize (string-trim (replace-regexp-in-string "\\`[ ]*Git[-:@]" "" vc-mode))
                'face 'cerebro-modeline-dim)))

(defconst cerebro-modeline-mode-names
  '((org-mode . "org")
    (emacs-lisp-mode . "elisp")
    (lisp-interaction-mode . "elisp")
    (scheme-mode . "scheme")
    (latex-mode . "latex")
    (dired-mode . "dired")
    (dired-sidebar-mode . "tree")
    (org-agenda-mode . "agenda")
    (magit-status-mode . "magit"))
  "Short names for the modes seen daily here; anything else uses `mode-name'.")

(defun cerebro-modeline-segment-mode ()
  "Major mode, short. `mode-name' can be a mode-line construct rather than
a string (several modes build a clickable one), and expanding it needs a
window -- so anything that is not already a string falls back to the mode
symbol, which is stable, printable and what you would type at `M-x'."
  (propertize (or (cdr (assq major-mode cerebro-modeline-mode-names))
                  (and (stringp mode-name) mode-name)
                  (string-remove-suffix "-mode" (symbol-name major-mode)))
              'face 'cerebro-modeline-dim))

(defun cerebro-modeline-segment-env ()
  "Whether this Emacs came out of the pinned profile or off the host PATH.
Shown only in the degraded case: inside the environment -- the normal
state -- the status line stays quiet."
  (unless (cerebro-guix-inside-p)
    (propertize "host" 'face 'cerebro-modeline-alert)))

(defconst cerebro-modeline-segment-alist
  '((state . cerebro-modeline-segment-state)
    (buffer . cerebro-modeline-segment-buffer)
    (position . cerebro-modeline-segment-position)
    (narrow . cerebro-modeline-segment-narrow)
    (clock . cerebro-modeline-segment-clock)
    (vc . cerebro-modeline-segment-vc)
    (mode . cerebro-modeline-segment-mode)
    (env . cerebro-modeline-segment-env))
  "Segment name -> function returning its string (or nil).")

;; -- Composition --------------------------------------------------------

(defun cerebro-modeline-compose (segments)
  "Render SEGMENTS (a list of names) into one space-separated string.
A segment returning nil or an empty string contributes nothing, not even
a separator -- which is what keeps the line from filling up with the
gaps of things that are not happening."
  (mapconcat
   #'identity
   (delq nil (mapcar (lambda (name)
                       (when-let* ((fn (cdr (assq name cerebro-modeline-segment-alist)))
                                   (value (funcall fn)))
                         (unless (string-empty-p value) value)))
                     segments))
   " "))

(defun cerebro-modeline-render (left right width)
  "Compose LEFT and RIGHT into a line WIDTH columns wide.
RIGHT is pushed against the right edge with padding. When the two cannot
both fit, RIGHT is dropped whole and LEFT truncated: in a 30-column
sidebar the file you are looking at matters, the major mode does not.
Pure string arithmetic -- no window, no redisplay -- so the layout is
testable."
  (let* ((left (or left "")) (right (or right ""))
         (lw (string-width left))
         (rw (string-width right))
         ;; One column of slack on the right: with a proportional-ish
         ;; frame font the last cell is easy to lose under the fringe.
         (gap (- width lw rw 1)))
    (if (>= gap 1)
        (concat left (make-string gap ?\s) right)
      (truncate-string-to-width left (max 0 (1- width)) nil nil "…"))))

(defun cerebro-modeline--line ()
  "The status line for the window being redisplayed."
  (let ((right (if (or (not (fboundp 'mode-line-window-selected-p))
                       (mode-line-window-selected-p))
                   (cerebro-modeline-compose cerebro-modeline-right)
                 ;; An unfocused window says what it is, not what the
                 ;; session is doing: clock and branch are global facts,
                 ;; and repeating them in every window is noise.
                 (cerebro-modeline-compose '(mode)))))
    ;; Every segment is already expanded text, so what comes out is
    ;; displayed verbatim -- escape the one character redisplay would
    ;; still interpret. A note titled "50% density" must not turn its own
    ;; status line into a line number.
    (replace-regexp-in-string
     "%" "%%"
     (cerebro-modeline-render
      (cerebro-modeline-compose cerebro-modeline-left)
      right
      (window-total-width)))))

(defconst cerebro-modeline-format
  '(:eval (cerebro-modeline--line))
  "The `mode-line-format' this module installs.")

(defvar cerebro-modeline--saved-format nil
  "The `mode-line-format' replaced by `cerebro-modeline-mode'.")

;;;###autoload
(define-minor-mode cerebro-modeline-mode
  "Use cerebro's segment-based status line.
Global, and reversible: turning it off restores the `mode-line-format'
that was in effect when it was first turned on."
  :global t
  :group 'cerebro-modeline
  (if cerebro-modeline-mode
      (progn
        (unless cerebro-modeline--saved-format
          (setq cerebro-modeline--saved-format (default-value 'mode-line-format)))
        (setq-default mode-line-format cerebro-modeline-format)
        ;; `%l' is only computed for lines below this limit; the default
        ;; (0) means "always", which is fine, but org-clock's own modeline
        ;; string would double up with the clock segment.
        (setq org-clock-clocked-in-display nil))
    (setq-default mode-line-format (or cerebro-modeline--saved-format
                                       (default-value 'mode-line-format))))
  ;; Buffers that already exist keep a buffer-local copy of the old
  ;; format if anything ever set one; leave those alone (dired-sidebar and
  ;; magit do this deliberately) and just force a redisplay.
  (force-mode-line-update t))

(cerebro-modeline-mode 1)

(provide 'cerebro-modeline)
