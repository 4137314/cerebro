;;; cerebro-study.el --- what you are doing to a note right now -*- lexical-binding: t; -*-

;; A note is read and written in the same buffer, and those are different
;; activities that want opposite things. Writing wants the source: the
;; markup visible, the formula at point turned back into `\(\eps\)' so it
;; can be edited, line numbers, the full width of the window. Studying
;; wants the opposite: everything rendered, no markup, a column narrow
;; enough to read, and *nothing watching the cursor*.
;;
;; Until now there was one setting of all of that, tuned for writing, and
;; it was simply on. Reading a note therefore meant reading it in the
;; writing configuration, which is both visually noisy and -- this is the
;; part that was measured rather than felt -- slow:
;;
;;   `org-appear' and `org-fragtog' both watch point from
;;   `post-command-hook', and each one asks `org-element-context' where
;;   point is. That call costs ~4ms on a note of this size. Scrolling
;;   with a trackpad under `pixel-scroll-precision-mode' issues ~100
;;   commands a second, and point does not move in any of them -- so
;;   roughly 800ms of every second of scrolling went to answering, a
;;   hundred times over, a question whose answer had not changed.
;;
;; That is not a bug in either package: they are doing what a *writing*
;; mode should do. It is a bug in having no other mode. So the fix and
;; the feature are the same thing, and this file is it: three named
;; modes, as data, and one of them turns the point-watchers off because
;; while you are reading there is no cursor to follow.
;;
;;   source  -- the file as it is. Nothing rendered, markup visible,
;;              line numbers on. What you switch to when a preview
;;              disagrees with the PDF and you need to see the bytes.
;;   write   -- the working mode: previews on, and the formula at point
;;              turns back into source as you arrive at it.
;;   study   -- reading for understanding: everything rendered, markup
;;              hidden, a centred column, and no timers at all.
;;
;; The mode is shown in the status line, because a mode you cannot see
;; is a mode you will be surprised by (`cerebro-modeline-left' carries
;; the `study' segment).

(require 'cerebro-guix)    ;; cerebro-guix-soft-require
(require 'cerebro-focus)   ;; the centred column
(require 'cerebro-preview) ;; rendering and the live-preview minor mode
(require 'org)

(defgroup cerebro-study nil
  "Reading and writing modes for a note."
  :group 'cerebro)

;; -- The modes, as data -------------------------------------------------
;; One row per mode, one property per thing that differs. Adding a mode is
;; adding a row; adding a *dimension* is adding a key here and a clause in
;; `cerebro-study--apply', which is the only place that knows how any of
;; this is switched on.
;;
;; `:watch-point' is the one that costs: nil means org-appear and
;; org-fragtog are off, which is what makes `study' scroll smoothly.

(defconst cerebro-study-modes
  '((source
     :describe    "the file as it is -- nothing rendered, markup visible"
     :render      nil
     :watch-point nil
     :markers     t
     :shapes      nil
     :focus       nil
     :numbers     t)
    (write
     :describe    "formulas rendered, the one at point turned back to source"
     :render      t
     :watch-point t
     :markers     nil
     :shapes      t
     :focus       nil
     :numbers     nil)
    (study
     :describe    "everything rendered, centred column, nothing watching point"
     :render      t
     :watch-point nil
     :markers     nil
     :shapes      t
     :focus       t
     :numbers     nil))
  "Named reading/writing modes: NAME followed by a plist of settings.
The name is also the label -- there is no `:label', because a display
string that repeats the key is a second name for one thing.

- `:render'      render LaTeX fragments in the buffer
- `:watch-point' run the point-following modes (org-appear, org-fragtog).
                 The expensive one: see the commentary at the top.
- `:markers'     show Org emphasis markers (=*bold*= rather than bold)
- `:shapes'      let org-modern draw headings, bullets, blocks and
                 keywords as shapes instead of as their markup
- `:focus'       centre the text (`cerebro-focus-mode')
- `:numbers'     show line numbers

`:shapes' is why `source' is now honest. It promised \"the file as it
is\" and \"the bytes\", and delivered neither: org-modern is a *global*
mode (cerebro-appearance.el), so a leading star was still hidden, a `-'
was still drawn as an en dash and every `#+begin_' was still a shape.
Turning off the emphasis markers alone was never going to show the
file -- and `source' exists exactly for the moment you distrust what is
on screen and need to compare it with what will compile.")

(defcustom cerebro-study-default 'write
  "The mode a note opens in.
`write' by default because a note is usually opened to be worked on. Set
it to `study' if this is mostly a reading archive for you -- and note
that `study' is also the fastest, since nothing follows the cursor."
  :type '(choice (const source) (const write) (const study))
  :group 'cerebro-study)

(defvar-local cerebro-study-mode-name nil
  "The `cerebro-study-modes' key currently in force in this buffer.")

;; -- Pure helpers -------------------------------------------------------

(defun cerebro-study-spec (name)
  "The settings plist for mode NAME, or nil if there is no such mode. Pure."
  (cdr (assq name cerebro-study-modes)))

(defun cerebro-study-names ()
  "Every mode name, in the order they are declared. Pure."
  (mapcar #'car cerebro-study-modes))

(defun cerebro-study-next (name)
  "The mode after NAME, wrapping around. Pure.
Declaration order is the cycle order, and it runs source -> write ->
study: from the rawest view of the note to the most finished."
  (let* ((names (cerebro-study-names))
         (position (seq-position names name)))
    (nth (if position (mod (1+ position) (length names)) 0) names)))

(defun cerebro-study-get (name key)
  "Setting KEY of mode NAME. Pure."
  (plist-get (cerebro-study-spec name) key))

;; -- Applying one ------------------------------------------------------

(defun cerebro-study--set-watchers (enable)
  "Turn the point-following modes ENABLE on or off in this buffer.

Both are optional packages, so both go through the soft-require: a
missing one costs the feature, never the mode. Switching them *off* is
the whole performance story -- each one asks `org-element-context' on
every command, and scrolling is thousands of commands during which point
never moves."
  (when (cerebro-guix-soft-require 'org-appear)
    (org-appear-mode (if enable 1 -1)))
  (when (cerebro-guix-soft-require 'org-fragtog)
    (cerebro-preview-live-mode (if enable 1 -1))))

(defun cerebro-study--set-shapes (enable)
  "Let org-modern redraw this buffer's markup, or stop it.

Buffer-local, against a mode that is enabled globally: `org-modern-mode'
is the per-buffer minor mode behind `global-org-modern-mode', so turning
it off here affects this note and leaves every other one alone. Soft, as
always -- outside the pinned environment there is no org-modern and
`source' simply looks like every other mode, which is the truth."
  (when (cerebro-guix-soft-require 'org-modern)
    (org-modern-mode (if enable 1 -1))))

(defun cerebro-study--set-render (enable)
  "Render every fragment in the buffer, or clear them all."
  (if enable
      (when (cerebro-preview-process) (org-latex-preview '(16)))
    (org-clear-latex-preview (point-min) (point-max))))

(defun cerebro-study--apply (name)
  "Put this buffer into mode NAME. The only place that knows how."
  (let ((spec (cerebro-study-spec name)))
    (unless spec (user-error "cerebro-study: unknown mode `%s'" name))
    ;; Order matters in one place: the watchers go off *before* rendering,
    ;; so org-fragtog does not immediately un-render the fragment point
    ;; happens to be sitting in.
    (cerebro-study--set-watchers (plist-get spec :watch-point))
    (setq-local org-hide-emphasis-markers (not (plist-get spec :markers)))
    (cerebro-study--set-shapes (plist-get spec :shapes))
    (font-lock-flush)
    (display-line-numbers-mode (if (plist-get spec :numbers) 1 -1))
    (cerebro-focus-mode (if (plist-get spec :focus) 1 -1))
    (cerebro-study--set-render (plist-get spec :render))
    (setq cerebro-study-mode-name name)
    (force-mode-line-update)))

;;;###autoload
(defun cerebro-study-set (name)
  "Put this note into mode NAME (`source', `write' or `study')."
  (interactive
   (list (intern (completing-read
                  "Mode: "
                  (mapcar (lambda (mode)
                            (format "%s" (car mode)))
                          cerebro-study-modes)
                  nil t))))
  (unless (derived-mode-p 'org-mode)
    (user-error "cerebro-study: not an Org buffer"))
  (cerebro-study--apply name)
  (message "cerebro: %s -- %s" name (cerebro-study-get name :describe)))

;;;###autoload
(defun cerebro-study-cycle ()
  "Move to the next mode: source -> write -> study -> source."
  (interactive)
  (cerebro-study-set (cerebro-study-next cerebro-study-mode-name)))

;;;###autoload
(defun cerebro-study-read ()
  "Go straight to `study': render everything, centre it, stop the timers."
  (interactive)
  (cerebro-study-set 'study))

;;;###autoload
(defun cerebro-study-source ()
  "Go straight to `source': show the file as it is."
  (interactive)
  (cerebro-study-set 'source))

;; (The status-line segment lives in cerebro-modeline.el, which reads
;; `cerebro-study-mode-name' defensively rather than requiring this file:
;; the status line must render in a buffer of any kind, including one
;; opened before this module loaded.)

;; -- Opening a note in the default mode --------------------------------

(defun cerebro-study--maybe-default ()
  "Put a freshly opened note into `cerebro-study-default'.

Not in the buffers the agenda and the dashboard open to read: those are
never looked at, and rendering their fragments would run LaTeX once per
formula for nobody (the same guard `cerebro-preview' uses)."
  (when (and (cerebro-interactive-note-buffer-p)
             (null cerebro-study-mode-name))
    ;; After the buffer has settled: `:render' compiles fragments, and
    ;; doing that inside `org-mode-hook' would put it on the path of
    ;; opening the file rather than of looking at it.
    (run-with-idle-timer
     0.1 nil
     (lambda (buffer)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (when (null cerebro-study-mode-name)
             (cerebro-study--apply cerebro-study-default)))))
     (current-buffer))))

(add-hook 'org-mode-hook #'cerebro-study--maybe-default)

(provide 'cerebro-study)
