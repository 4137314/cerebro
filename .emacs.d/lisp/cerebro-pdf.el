;;; cerebro-pdf.el --- compile a note and read the PDF next to it -*- lexical-binding: t; -*-

;; The export pipeline produces a real typeset document, and until now
;; looking at it meant leaving Emacs: run `make export', find the file,
;; open a viewer, re-run, alt-tab, remember which window was which. For a
;; repo whose whole point is that the note and the paper are the same
;; file, that round trip is the wrong shape.
;;
;; So: `C-c e e' compiles the note in the background and shows the PDF in
;; a window beside it. Re-export and the view refreshes in place, on the
;; page you were reading -- so "does this display equation break?" is a
;; keystroke, not a context switch.
;;
;; Three decisions worth stating:
;;
;;   - The compile is *asynchronous*, in a compilation buffer. A real
;;     latexmk run takes seconds, `org-latex-export-to-pdf' is
;;     synchronous, and an editor that freezes on export is an editor you
;;     stop exporting from. The compilation buffer is also where a LaTeX
;;     error shows up -- and exports here are strict (`-halt-on-error'),
;;     so errors are the interesting case.
;;   - It shells out to bin/org-export-latex.el, the same batch entry
;;     point `make export' uses. One implementation of "compile a note",
;;     not two (invariant 2).
;;   - The viewer is `pdf-tools' when the environment has it and plain
;;     `doc-view' (built into Emacs) otherwise. Both are checked at
;;     runtime: pdf-tools needs a helper *binary*, and a missing binary
;;     must degrade to the built-in viewer rather than to an error in a
;;     buffer you cannot read.

(require 'cerebro-org)   ;; cerebro-root
(require 'cerebro-latex) ;; cerebro-latex-profiles (what can be compiled)
(require 'cerebro-guix)  ;; cerebro-guix-soft-require
(require 'cerebro-theme) ;; cerebro-theme-after-apply-hook (PDFs follow the theme)
(require 'compile)

(defgroup cerebro-pdf nil
  "Reading the compiled PDF inside Emacs."
  :group 'cerebro)

(defcustom cerebro-pdf-default-profile "lecture"
  "Export profile `C-c e e' offers first.
`lecture' is the note as an article -- statements and their proofs, with
the asides dropped -- which is how you read one while writing it. `C-u
C-c e e' picks another: `handbook' is the same note with everything in
it, and `single' (`C-c e r') is one result on its own page."
  :type 'string
  :group 'cerebro-pdf)

(defcustom cerebro-pdf-window-width 0.5
  "Fraction of the frame the PDF window takes, as a side window on the right."
  :type 'number
  :group 'cerebro-pdf)

;; -- Which viewer (pure, so the fallback logic is testable) -------------

(defun cerebro-pdf-pick-viewer (pdf-tools-p epdfinfo-p doc-view-p)
  "Choose a viewer from what is available. Returns a symbol or nil.
PDF-TOOLS-P is whether the package loaded, EPDFINFO-P whether its helper
binary is really there (the package is Elisp; the rendering is done by a
C program that Guix builds for us -- but a profile can be half-built, and
`pdf-view-mode' without it fails on the first page rather than at load),
DOC-VIEW-P whether the built-in viewer can run."
  (cond ((and pdf-tools-p epdfinfo-p) 'pdf-tools)
        (doc-view-p 'doc-view)
        (t nil)))

(defun cerebro-pdf-epdfinfo-available-p ()
  "Non-nil when pdf-tools' helper binary can actually be executed."
  (and (boundp 'pdf-info-epdfinfo-program)
       (stringp pdf-info-epdfinfo-program)
       (file-executable-p pdf-info-epdfinfo-program)))

(defun cerebro-pdf-doc-view-available-p ()
  "Non-nil when the built-in `doc-view' has a renderer on PATH.
doc-view converts pages with poppler's `pdftoppm' (or ghostscript);
without either it opens an empty buffer and says nothing useful."
  (and (or (executable-find "pdftoppm") (executable-find "gs")) t))

(defun cerebro-pdf-viewer ()
  "The viewer this session will use, or nil if a PDF cannot be shown."
  (cerebro-pdf-pick-viewer (featurep 'pdf-tools)
                           (cerebro-pdf-epdfinfo-available-p)
                           (cerebro-pdf-doc-view-available-p)))

;; pdf-tools is loaded (not installed) at startup: `pdf-loader-install'
;; only registers the autoloads and the auto-mode entry, so nothing runs
;; the helper binary until a PDF is actually opened.
(when (cerebro-guix-soft-require 'pdf-tools)
  (when (fboundp 'pdf-loader-install)
    (pdf-loader-install))
  ;; Fit the page to the window: the useful default for a two-window
  ;; note-and-paper layout, where the PDF window is half a frame wide.
  (setq-default pdf-view-display-size 'fit-page)
  (setq pdf-view-resize-factor 1.1))

;; -- The PDF in the editor's own colours --------------------------------
;; A white page in a dark frame is the brightest thing on the screen, and
;; it sits *next* to the note you are reading -- the one place where the
;; contrast between window and window is worst. pdf-tools can recolour
;; the rendering to the current theme's foreground/background
;; (`pdf-view-themed-minor-mode', which drives the renderer's colour
;; filter, so it is the real page recoloured, not an image inverted).
;;
;; It is on by default here, and it follows `C-c u t': the mode itself
;; only refreshes on save/revert, so a theme switch would otherwise leave
;; every open PDF in the palette you just left -- the same staleness
;; cerebro-preview.el has to handle for formula images, fixed at the same
;; seam.

(defcustom cerebro-pdf-themed t
  "Whether PDFs are rendered in the current theme's colours.
Nil shows the document as it will be printed -- which is what you want
when checking the actual page, and why this is one keystroke away
(`C-c e d') rather than a setting you have to remember."
  :type 'boolean
  :group 'cerebro-pdf)

(defun cerebro-pdf--apply-theme ()
  "Turn themed rendering on in this PDF buffer, if configured."
  (when (and cerebro-pdf-themed (fboundp 'pdf-view-themed-minor-mode))
    (pdf-view-themed-minor-mode 1)))

(add-hook 'pdf-view-mode-hook #'cerebro-pdf--apply-theme)

(defun cerebro-pdf-refresh-theme ()
  "Re-render every themed PDF buffer in the palette now in force."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and (derived-mode-p 'pdf-view-mode)
                 (bound-and-true-p pdf-view-themed-minor-mode)
                 (fboundp 'pdf-view-refresh-themed-buffer))
        ;; Non-nil argument: re-read the theme's colours, not just redraw.
        (pdf-view-refresh-themed-buffer t)))))

(add-hook 'cerebro-theme-after-apply-hook #'cerebro-pdf-refresh-theme)

;;;###autoload
(defun cerebro-pdf-toggle-theme ()
  "Switch this PDF between the editor's colours and the printed page (`C-c e d')."
  (interactive)
  (unless (derived-mode-p 'pdf-view-mode)
    (user-error "cerebro-pdf: not a PDF buffer"))
  (unless (fboundp 'pdf-view-themed-minor-mode)
    (user-error "cerebro-pdf: needs pdf-tools (doc-view cannot recolour a page)"))
  (pdf-view-themed-minor-mode 'toggle)
  (message "cerebro: PDF in %s colours"
           (if (bound-and-true-p pdf-view-themed-minor-mode) "theme" "print")))

;; -- Which file -----------------------------------------------------

(defun cerebro-pdf-file-for (note)
  "The PDF the exporter produces for NOTE.

Not next to the note: builds go to `.build/' beside the source
(`cerebro-latex-output-file'), so a directory of mathematics contains
mathematics and nothing else. One function decides that for the whole
config -- this module, `make export' and bin/cerebro-course-export all
ask it."
  (cerebro-latex-output-file note))

(defun cerebro-pdf-stale-p (note pdf)
  "Non-nil when PDF is missing or older than NOTE.
Used only to *offer* a compile: a stale PDF is still worth showing while
the new one builds."
  (or (not (file-exists-p pdf))
      (time-less-p (file-attribute-modification-time (file-attributes pdf))
                   (file-attribute-modification-time (file-attributes note)))))

(defun cerebro-pdf--note ()
  "The note this command applies to: the current Org buffer's file."
  (or (and (derived-mode-p 'org-mode) (buffer-file-name))
      (user-error "cerebro-pdf: not visiting an Org note")))

(defun cerebro-pdf-name-at-point ()
  "The `#+NAME:' of the block point is in or under, or nil.
What the `single' profile needs as its target -- read from the buffer so
that \"compile just this theorem\" needs no typing."
  (save-excursion
    (let ((bound (max (point-min) (- (point) 4000))))
      (when (re-search-backward "^[ \t]*#\\+NAME:[ \t]*\\(\\S-+\\)[ \t]*$" bound t)
        (match-string-no-properties 1)))))

;; -- Showing it ---------------------------------------------------------

(defun cerebro-pdf--display (buffer)
  "Show BUFFER in the PDF side window: right half, and it stays there."
  (display-buffer
   buffer
   `(display-buffer-in-side-window
     (side . right)
     (slot . 0)
     (window-width . ,cerebro-pdf-window-width)
     (preserve-size . (t . nil)))))

;;;###autoload
(defun cerebro-pdf-show-file (pdf)
  "Show PDF in the side window, reverting as it is rebuilt.
The one place a document is put on screen -- used for a note's own PDF
and for the course documents (cerebro-course.el), so both behave the
same: same window, same auto-revert, same themed colours."
  (unless (cerebro-pdf-viewer)
    (user-error "cerebro-pdf: no viewer available (pdf-tools/poppler missing -- M-x cerebro-guix-status)"))
  (unless (file-exists-p pdf)
    (user-error "cerebro-pdf: %s has not been compiled yet" (file-name-nondirectory pdf)))
  (let ((buffer (find-file-noselect pdf)))
    (with-current-buffer buffer
      ;; `auto-revert' is the whole trick: pdf-tools and doc-view both
      ;; revert in place, keeping the current page, so the window
      ;; behaves like a live preview of the compile.
      (setq-local auto-revert-verbose nil)
      (auto-revert-mode 1))
    (cerebro-pdf--display buffer)
    buffer))

;;;###autoload
(defun cerebro-pdf-view (&optional note)
  "Show the PDF of NOTE (default: this note) beside it."
  (interactive)
  (let* ((note (or note (cerebro-pdf--note)))
         (pdf (cerebro-pdf-file-for note)))
    (unless (file-exists-p pdf)
      (user-error "cerebro-pdf: %s has not been compiled yet -- C-c e e"
                  (file-name-nondirectory note)))
    (cerebro-pdf-show-file pdf)))

;; -- Compiling ----------------------------------------------------------

(defun cerebro-pdf--command (note profile &optional target)
  "The shell command that compiles NOTE with PROFILE (and TARGET).
Calls the same batch entry point as `make export'. Deliberately the plain
`emacs' on PATH rather than bin/guix-run: inside the pinned environment
that *is* the pinned Emacs, and outside it a compile that works is better
than one that first materialises several gigabytes."
  (format "emacs --batch -l %s -- --profile=%s%s %s"
          (shell-quote-argument (expand-file-name "bin/org-export-latex.el" cerebro-root))
          (shell-quote-argument profile)
          (if target (concat " --target=" (shell-quote-argument target)) "")
          (shell-quote-argument note)))

(defun cerebro-pdf-log-file (note)
  "The LaTeX log of NOTE's last build."
  (cerebro-latex-output-file note "log"))

(defun cerebro-pdf-first-error (log-file)
  "The first real LaTeX error in LOG-FILE, as one line, or nil.
TeX logs are thousands of lines and the message that matters starts with
`!'. Finding it is what turns \"the export failed\" into something you
can act on without opening a log."
  (when (file-readable-p log-file)
    (with-temp-buffer
      (insert-file-contents log-file)
      (goto-char (point-min))
      (when (re-search-forward "^! \\(.*\\)$" nil t)
        (let ((message (match-string 1))
              (line (when (re-search-forward "^l\\.\\([0-9]+\\)" nil t)
                      (match-string 1))))
          (if line (format "%s (line %s of the generated .tex)" message line)
            message))))))

(defun cerebro-pdf--compile (note profile &optional target)
  "Compile NOTE asynchronously, then show the PDF when it succeeds."
  (let* ((default-directory cerebro-root)
         (pdf (cerebro-pdf-file-for note))
         (compilation-buffer-name-function (lambda (&rest _) "*cerebro-export*"))
         (buffer (compile (cerebro-pdf--command note profile target))))
    (with-current-buffer buffer
      (add-hook 'compilation-finish-functions
                (lambda (_buffer status)
                  (if (string-prefix-p "finished" status)
                      (progn (cerebro-pdf-view note)
                             (message "cerebro: %s (%s)"
                                      (file-name-nondirectory pdf) profile))
                    ;; Leave the compilation buffer on screen, but say
                    ;; what went wrong in the echo area: with
                    ;; `-halt-on-error' there is exactly one error, and
                    ;; reading it should not require scrolling a log.
                    (let ((first (cerebro-pdf-first-error (cerebro-pdf-log-file note))))
                      (message "cerebro: export failed -- %s"
                               (or first "see *cerebro-export*")))))
                nil t))
    buffer))

(defun cerebro-pdf--read-profile ()
  "Ask which export profile to use, completing over the real list."
  ;; The profile table is keyed by symbols; the command line takes a
  ;; string, so complete over the names rather than over the symbols.
  (completing-read (format "Profile (default %s): " cerebro-pdf-default-profile)
                   (mapcar (lambda (row) (symbol-name (car row)))
                           cerebro-latex-profiles)
                   nil t nil nil cerebro-pdf-default-profile))

;;;###autoload
(defun cerebro-pdf-export (&optional profile)
  "Compile this note with PROFILE and show the PDF beside it (`C-c e e').
With a prefix argument, ask for the profile; otherwise use
`cerebro-pdf-default-profile' -- while writing, the profile you want is
almost always the same one."
  (interactive (list (when current-prefix-arg (cerebro-pdf--read-profile))))
  (let* ((note (cerebro-pdf--note))
         (pdf (cerebro-pdf-file-for note)))
    (when (buffer-modified-p) (save-buffer))
    ;; A LaTeX run is ten seconds. Doing it again for a note that has not
    ;; changed since the PDF was written is ten seconds of nothing, and
    ;; the habit it teaches is to stop pressing the key.
    (if (and (not current-prefix-arg)
             (not (cerebro-pdf-stale-p note pdf)))
        (progn (cerebro-pdf-show-file pdf)
               (message "cerebro: %s is already current (C-u C-c e e to rebuild)"
                        (file-name-nondirectory pdf)))
      (cerebro-pdf--compile note (or profile cerebro-pdf-default-profile)))))

;; -- Rebuild as you write -----------------------------------------------

(defcustom cerebro-pdf-watch-idle 2.0
  "Seconds of quiet after a save before a watched note is recompiled."
  :type 'number
  :group 'cerebro-pdf)

(defvar-local cerebro-pdf--watch-timer nil)

;;;###autoload
(define-minor-mode cerebro-pdf-watch-mode
  "Recompile this note, and refresh the PDF window, on every save (`C-c e w').

The loop this closes: write, save, look right. The compile is the same
asynchronous one as `C-c e e' and the window already auto-reverts, so
turning this on makes the PDF a live view of the note -- at the cost of
a LaTeX run per save, which is why it is a mode and not the default."
  :lighter " pdf-watch"
  :group 'cerebro-pdf
  (if cerebro-pdf-watch-mode
      (add-hook 'after-save-hook #'cerebro-pdf--watch-rebuild nil t)
    (remove-hook 'after-save-hook #'cerebro-pdf--watch-rebuild t)
    (when cerebro-pdf--watch-timer
      (cancel-timer cerebro-pdf--watch-timer)
      (setq cerebro-pdf--watch-timer nil))))

(defun cerebro-pdf--watch-rebuild ()
  "Queue a rebuild of this note after `cerebro-pdf-watch-idle' seconds.
Debounced: saving three times while thinking should compile once, not
three times, and the third compile is the only one whose output anyone
will look at."
  (let ((buffer (current-buffer)))
    (when cerebro-pdf--watch-timer (cancel-timer cerebro-pdf--watch-timer))
    (setq cerebro-pdf--watch-timer
          (run-with-idle-timer
           cerebro-pdf-watch-idle nil
           (lambda ()
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (setq cerebro-pdf--watch-timer nil)
                 (cerebro-pdf--compile (buffer-file-name)
                                       cerebro-pdf-default-profile))))))))

;;;###autoload
(defun cerebro-pdf-export-result ()
  "Compile *only* the result at point, via the `single' profile (`C-c e r').
The `single' profile keeps one `#+NAME'd block (plus its proof) and
nothing else, which is the fastest way to check one theorem's typesetting
without waiting for the whole note. The name is read from the buffer."
  (interactive)
  (let ((note (cerebro-pdf--note))
        (name (or (cerebro-pdf-name-at-point)
                  (user-error "cerebro-pdf: no #+NAME: above point -- name the result first"))))
    (when (buffer-modified-p) (save-buffer))
    (cerebro-pdf--compile note "single" name)))

;;;###autoload
(defun cerebro-pdf-status ()
  "Report what this session can do with PDFs, and why."
  (interactive)
  (let ((viewer (cerebro-pdf-viewer)))
    (cerebro-report
     (format "cerebro pdf -- %s" (or viewer "NO VIEWER"))
     (list (format "viewer     : %s" (or viewer "none -- install pdf-tools or poppler"))
           (format "pdf-tools  : %s" (if (featurep 'pdf-tools) "loaded" "absent"))
           (format "epdfinfo   : %s"
                   (if (cerebro-pdf-epdfinfo-available-p)
                       (bound-and-true-p pdf-info-epdfinfo-program)
                     "not executable -- falling back to doc-view"))
           (format "doc-view   : %s"
                   (if (cerebro-pdf-doc-view-available-p)
                       (or (executable-find "pdftoppm") (executable-find "gs"))
                     "no pdftoppm/gs on PATH"))
           ""
           (format "this note  : %s"
                   (if (and (derived-mode-p 'org-mode) (buffer-file-name))
                       (let* ((note (buffer-file-name))
                              (pdf (cerebro-pdf-file-for note)))
                         (format "%s (%s)"
                                 (file-relative-name pdf cerebro-root)
                                 (cond ((not (file-exists-p pdf)) "not compiled yet")
                                       ((cerebro-pdf-stale-p note pdf) "stale -- C-c e e")
                                       (t "up to date"))))
                     "not an Org note")))
     #'identity
     "*cerebro-pdf*")))

(provide 'cerebro-pdf)
