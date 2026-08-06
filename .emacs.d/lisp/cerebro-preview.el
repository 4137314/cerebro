;;; cerebro-preview.el --- formulas and TikZ, rendered in the buffer -*- lexical-binding: t; -*-

;; A note in this repo is mathematics: \(\norm{x}_p\), a displayed
;; estimate, a commutative diagram in tikz-cd, a pgfplots figure. Reading
;; it as source means holding the typeset form in your head; compiling the
;; PDF to check one formula is a ten-second round trip. Emacs can render
;; those fragments in place -- and Org has done it for twenty years, with
;; real LaTeX, no JavaScript, no MathJax approximation of the notation.
;;
;; What was missing is that a *preview* and an *export* must agree. Org's
;; default preview preamble is a bare article class, so a note using the
;; project's own notation (\R, \norm{}, \inner{}{}, the tikz libraries)
;; previews as an error while compiling perfectly to PDF -- the worst kind
;; of divergence, because it teaches you to distrust the preview.
;;
;; So this module points the preview machinery at the *same* source of
;; truth the exporter uses: latex/cerebro-macros.sty, loaded with one
;; \usepackage and found via TEXINPUTS exactly as in cerebro-latex.el.
;; Every macro, and tikz/tikz-cd/pgfplots with it, therefore renders in
;; the buffer with the same meaning it will have in the PDF. One
;; consequence worth stating: a fragment that fails to preview is a
;; fragment that will fail to compile.
;;
;; Two mechanisms, one preamble:
;;
;;   - LaTeX fragments and environments -- \(...\), \[...\] and any
;;     \begin{env}...\end{env} written directly in the note, which is
;;     where a tikzpicture or a tikz-cd diagram lives (Org exports those
;;     verbatim, so they are already the portable way to draw here).
;;     Rendered by Org's `org-latex-preview' (C-c C-x C-l).
;;   - #+begin_src latex blocks with a :file header -- the generated
;;     figure case (a pgfplots plot over data, a diagram built by a
;;     loop). Compiled by ob-latex into an SVG that Org then shows
;;     inline.
;;
;; Images are SVG when this Emacs and this toolchain can do it: a formula
;; is line art, and at 12pt on a HiDPI screen a PNG of it looks like a
;; photocopy. The renderer is chosen from a table of candidates by what is
;; actually installed, so the module degrades to dvipng, then to nothing,
;; without a broken preview in between.

(require 'cerebro-org)   ;; cerebro-root, cerebro-report
(require 'cerebro-guix)  ;; cerebro-guix-soft-require (org-fragtog is optional)
(require 'cerebro-theme) ;; font size + `cerebro-theme-after-apply-hook'
(require 'org)
;; ob-latex reads `org-preview-latex-process-alist' at load time, so org
;; itself must be loaded first -- requiring ob-latex on its own fails.
(require 'ob-latex nil t)

(defgroup cerebro-preview nil
  "In-buffer rendering of LaTeX formulas and TikZ figures."
  :group 'cerebro)

;; -- Where LaTeX finds the project's own packages -----------------------

(defun cerebro-preview-texinputs (dir &optional existing)
  "TEXINPUTS with DIR first, keeping EXISTING and the default path.
A trailing empty entry is what tells kpathsea \"then look where you
normally would\"; without it, adding the project's latex/ directory
would *replace* the whole search path and every standard package would
go missing. Idempotent, so re-running it (a second `require', a theme
reload) cannot grow the variable without bound."
  (let* ((dir (file-name-as-directory (expand-file-name dir)))
         (existing (or existing ""))
         (parts (split-string existing ":")))
    (if (member (directory-file-name dir) (mapcar #'directory-file-name parts))
        existing
      (concat dir ":" existing))))

(defconst cerebro-preview-latex-dir
  (expand-file-name "latex" cerebro-root)
  "Directory holding cerebro-macros.sty -- the notation previews share
with the PDF (see cerebro-latex.el, which sets the same TEXINPUTS for
the export).")

(setenv "TEXINPUTS" (cerebro-preview-texinputs cerebro-preview-latex-dir
                                               (getenv "TEXINPUTS")))

;; -- The preamble -------------------------------------------------------
;; One \usepackage, because cerebro-macros.sty already \RequirePackage's
;; amsmath, amssymb, mathtools, tikz, tikz-cd and pgfplots. Adding them
;; here would be a second, driftable list of what the notation needs.
;;
;; `[NO-DEFAULT-PACKAGES]' and `[NO-PACKAGES]' keep Org from splicing in
;; its own export package list: the export preamble is built for a
;; document (hyperref, cleveref, biblatex), and a preview is a 2cm
;; snippet -- every extra package is compile time on every fragment, and
;; cleveref in particular expects hyperref, which a preview has no use
;; for.
(defcustom cerebro-preview-preamble
  (concat "\\documentclass{article}\n"
          "\\usepackage[usenames]{color}\n"
          "\\usepackage{cerebro-macros}\n"
          "[NO-DEFAULT-PACKAGES]\n"
          "[NO-PACKAGES]\n"
          "\\pagestyle{empty}\n")
  "Preamble used to render fragments, sharing the notes' own macro file."
  :type 'string
  :group 'cerebro-preview)

;; -- Choosing a renderer ------------------------------------------------
;; Candidates in order of quality. Each says what it needs; the first one
;; whose image type Emacs supports *and* whose programs exist wins. This
;; is the whole "what if the toolchain is incomplete" policy, as data.
(defconst cerebro-preview-processes
  '((dvisvgm   :image svg :programs ("latex" "dvisvgm")
               :why "vector output: crisp at any size, scales with the font")
    (dvipng    :image png :programs ("latex" "dvipng")
               :why "raster fallback: fine at one size, blurry when zoomed")
    (imagemagick :image png :programs ("latex" "convert")
               :why "last resort: works wherever ImageMagick does"))
  "Preview backends, best first. Keys match `org-preview-latex-process-alist'.")

(defun cerebro-preview-select-process (candidates image-supported-p program-available-p)
  "First entry of CANDIDATES this system can run, or nil.
IMAGE-SUPPORTED-P and PROGRAM-AVAILABLE-P are predicates, injected so the
selection is a pure function -- the tests exercise \"no dvisvgm\", \"no
SVG support\" and \"nothing at all\" without touching the machine."
  (seq-find
   (lambda (entry)
     (let ((spec (cdr entry)))
       (and (funcall image-supported-p (plist-get spec :image))
            (seq-every-p program-available-p (plist-get spec :programs)))))
   candidates))

(defun cerebro-preview-process ()
  "The backend to use here, or nil when the toolchain cannot render at all."
  (car (cerebro-preview-select-process
        cerebro-preview-processes
        #'image-type-available-p
        (lambda (program) (and (executable-find program) t)))))

;; -- Size ---------------------------------------------------------------

(defun cerebro-preview-scale (font-size)
  "Preview scale matching a body FONT-SIZE in 1/10 pt.
Org renders fragments at 10pt and scales the image; 1.0 next to 12pt text
is visibly small, and a formula that reads smaller than the sentence
containing it defeats the point. The reference (120 -> 1.4) was chosen by
eye and then kept proportional, so changing the body size keeps
formulas and prose in the same relation."
  (/ (* 1.4 font-size) 120.0))

;; -- Wiring Org ---------------------------------------------------------

(defun cerebro-preview-apply ()
  "Point Org's preview machinery at cerebro's preamble, backend and size.
Called at load and again from `cerebro-theme-after-apply-hook', because
previews bake the theme's foreground colour and the body size into the
image: after a theme switch the cached images are wrong, not stale."
  (setq org-format-latex-header cerebro-preview-preamble)
  (when-let* ((process (cerebro-preview-process)))
    (setq org-preview-latex-default-process process))
  ;; Cache the generated images outside the notes tree. Org's default
  ;; ("ltximg/", relative to the note) drops a directory of derived files
  ;; into every notes subdirectory -- untracked litter in a repo whose
  ;; whole premise is that what is committed is the second brain.
  (setq org-preview-latex-image-directory
        (expand-file-name ".emacs.d/var/ltximg/" cerebro-root))
  (setq org-format-latex-options
        (plist-put (plist-put (copy-sequence org-format-latex-options)
                              :scale (cerebro-preview-scale cerebro-theme-font-size))
                   ;; `default' = take the colours from the `default'
                   ;; face, so a formula is the same ink as the prose in
                   ;; either theme variant.
                   :foreground 'default))
  ;; Transparent, NOT the `default' face background -- and this one is
  ;; worth the paragraph, because the failure it avoids looks like a bug
  ;; in LaTeX rather than in a colour setting.
  ;;
  ;; Asking for a background makes Org emit `\pagecolor', which dvisvgm
  ;; renders as a `<rect>' behind the formula. When that colour is the
  ;; page default, dvisvgm writes the rect with *no* `fill' attribute --
  ;; and Emacs' SVG renderer fills an unattributed shape with the
  ;; *foreground* colour of the face it is displayed in. So the backing
  ;; rectangle comes out the same colour as the glyphs on top of it, and
  ;; every rendered formula is an opaque block of text colour. (Observed
  ;; on screen, then isolated: the identical file with the rect removed,
  ;; or with an explicit `fill', renders perfectly.)
  ;;
  ;; With no background there is no rect at all: the glyphs carry their
  ;; own explicit colour from `:foreground' above, and Emacs composites
  ;; them over the buffer -- which is also what makes a preview sitting in
  ;; a highlighted line or a focus-mode margin look right.
  (setq org-format-latex-options
        (plist-put org-format-latex-options :background "Transparent"))
  ;; Which delimiters count as a fragment. Org's default list includes
  ;; "$" and "$$" -- forbidden in this repo (bin/notes-lint.el rejects a
  ;; naked `$', because `$x$--$y$' mis-parses silently). Previewing them
  ;; would render exactly the notation the linter is about to reject.
  (setq org-format-latex-options
        (plist-put org-format-latex-options :matchers '("begin" "\\(" "\\["))))

(cerebro-preview-apply)
(add-hook 'cerebro-theme-after-apply-hook #'cerebro-preview-apply)

;; -- Previews already on screen when the theme changes ------------------
;; Setting the options above only fixes the *next* render. The images
;; already displayed were generated with the old palette and the old body
;; size, and they are bitmaps: nothing about them updates. Org's cache
;; hashes the resolved colours into the file name, so a re-render does
;; produce a new file -- but only if something asks for one.

(defcustom cerebro-preview-on-theme-change 'clear
  "What to do with rendered previews when the theme or font size changes.

`clear'  -- remove them, showing the source again. Instant, and the
            default: a formula drawn in the previous palette is wrong,
            not merely stale, and re-rendering a note full of fragments
            runs LaTeX once per fragment -- seconds of frozen Emacs at
            the moment you pressed a key expecting a colour change.
`render' -- clear, then re-render the buffers currently on screen.
nil      -- leave them; they will be wrong until you press C-c u p."
  :type '(choice (const clear) (const render) (const nil))
  :group 'cerebro-preview)

(defun cerebro-preview-buffer-previewed-p (&optional buffer)
  "Non-nil when BUFFER (default current) has rendered fragments in it.
Org marks each one with an `org-overlay-type' of `org-latex-overlay';
the overlays are the only record that a buffer was ever previewed."
  (with-current-buffer (or buffer (current-buffer))
    (seq-some (lambda (ov) (eq (overlay-get ov 'org-overlay-type) 'org-latex-overlay))
              (overlays-in (point-min) (point-max)))))

(defun cerebro-preview-previewed-buffers ()
  "Every live Org buffer currently showing rendered fragments."
  (seq-filter (lambda (buffer)
                (with-current-buffer buffer
                  (and (derived-mode-p 'org-mode)
                       (cerebro-preview-buffer-previewed-p))))
              (buffer-list)))

;;;###autoload
(defun cerebro-preview-refresh ()
  "Invalidate rendered previews, per `cerebro-preview-on-theme-change'.
Interactively, or on a theme/size change -- the moment the images on
screen stopped matching the text around them."
  (interactive)
  (when cerebro-preview-on-theme-change
    (let ((buffers (cerebro-preview-previewed-buffers)))
      (dolist (buffer buffers)
        (with-current-buffer buffer
          (org-clear-latex-preview (point-min) (point-max))
          (when (and (eq cerebro-preview-on-theme-change 'render)
                     (get-buffer-window buffer t))
            (org-latex-preview '(16)))))
      (when buffers
        (message "cerebro: previews dropped in %d buffer(s) -- C-c u p re-renders"
                 (length buffers))))))

;; Appended, so it runs *after* `cerebro-preview-apply' has installed the
;; new colours and scale: a `render' refresh must generate the new images,
;; not the ones it is replacing.
(add-hook 'cerebro-theme-after-apply-hook #'cerebro-preview-refresh t)

;; Images produced by a src block (`:file fig.svg') are shown as soon as
;; the note opens, like the fragments -- otherwise the figure you
;; generated last week is an invisible link until you remember to press a
;; key.
(setq org-startup-with-inline-images t)

;; -- Generated figures (ob-latex) ---------------------------------------
(when (featurep 'ob-latex)
  (org-babel-do-load-languages
   'org-babel-load-languages
   (append (bound-and-true-p org-babel-load-languages)
           '((latex . t) (emacs-lisp . t))))

  ;; The same notation for generated figures: a src block compiles inside
  ;; `standalone' (tight bounding box, no page furniture) with
  ;; cerebro-macros loaded, so a \norm or a \R in a tikz label means what
  ;; it means everywhere else.
  (setq org-babel-latex-preamble
        (lambda (_params)
          "\\documentclass[preview,border=2pt]{standalone}\n\\usepackage{cerebro-macros}\n"))

  ;; ob-latex's default PDF->SVG step is pdf2svg, which is not in
  ;; guix.scm (and one more binary to pin). dvisvgm is already there for
  ;; the fragment previews and reads PDF directly with --pdf.
  (setq org-babel-latex-pdf-svg-process "dvisvgm --pdf --no-fonts --exact-bbox -o %O %f")

  (defun cerebro-preview-confirm-babel (language _body)
    "Ask before evaluating a src block unless it is LaTeX.
Compiling a figure should not require confirming a prompt every time the
buffer is re-rendered; running arbitrary code from a file should. LaTeX
is the exception because these blocks are compiled without
-shell-escape, so they typeset -- they do not execute."
    (not (equal language "latex")))
  (setq org-confirm-babel-evaluate #'cerebro-preview-confirm-babel))

;; -- Commands -----------------------------------------------------------

;;;###autoload
(defun cerebro-preview-buffer (&optional clear)
  "Render every formula and environment in the buffer.
With a prefix argument CLEAR, remove the previews instead and show the
source again -- which is what you want while *writing* a fragment, since
a rendered one hides the markup you are editing."
  (interactive "P")
  (unless (derived-mode-p 'org-mode)
    (user-error "cerebro-preview: not an Org buffer"))
  (unless (cerebro-preview-process)
    (user-error "cerebro-preview: no usable renderer -- M-x cerebro-preview-status"))
  (if clear
      (progn (org-clear-latex-preview (point-min) (point-max))
             (message "cerebro: previews cleared"))
    ;; `(16)' -- two universal arguments -- is Org's own "whole buffer"
    ;; scope. Not `(4)': that one *clears* the current section, which
    ;; would make this command do the opposite of what it says.
    (org-latex-preview '(16))))

;;;###autoload
(defun cerebro-preview-figures ()
  "Compile the LaTeX src blocks of this buffer and show the results inline.
The generated-figure half of the module: a `#+begin_src latex :file
fig.svg' block becomes an SVG next to its `#+RESULTS:' link."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "cerebro-preview: not an Org buffer"))
  (org-babel-execute-buffer)
  (org-display-inline-images))

;; -- Live previews ------------------------------------------------------
;; The friction with rendered formulas is editing them: a preview covers
;; the markup, so fixing a typo means clearing it, editing, re-rendering.
;; `org-fragtog' (guix.scm) removes exactly that: the fragment the cursor
;; is inside shows its source, and re-renders the moment you leave it.
;; Nothing else changes -- it toggles Org's own previews, so everything
;; above (preamble, renderer, scale) still applies.

(defcustom cerebro-preview-live-by-default t
  "Whether Org buffers get `cerebro-preview-live-mode' automatically.
Turning a fragment back into source costs one LaTeX run per fragment you
leave; on a very long note on a slow machine that is noticeable, and this
is the switch to turn it off."
  :type 'boolean
  :group 'cerebro-preview)

;;;###autoload
(define-minor-mode cerebro-preview-live-mode
  "Show the source of the formula at point, render it again on leaving.
A no-op (with a message) when org-fragtog is not installed -- the manual
commands keep working."
  :lighter nil
  :group 'cerebro-preview
  (if (not (cerebro-guix-soft-require 'org-fragtog))
      (when cerebro-preview-live-mode
        (setq cerebro-preview-live-mode nil)
        (message "cerebro: org-fragtog is missing -- use C-c u p / C-c C-x C-l"))
    (org-fragtog-mode (if cerebro-preview-live-mode 1 -1))))

(defun cerebro-preview--maybe-live ()
  "Enable live previews in this Org buffer, if configured and possible."
  (when (and cerebro-preview-live-by-default
             (cerebro-preview-process)
             (featurep 'org-fragtog)
             ;; Not in the notes the agenda and the dashboard open to
             ;; read: a live preview there is a timer per file, in a
             ;; buffer nobody is looking at.
             (cerebro-interactive-note-buffer-p))
    (cerebro-preview-live-mode 1)))

;; Only hooked when the package is actually there, so an Emacs outside the
;; pinned environment does not run a per-buffer check that can only fail.
(when (cerebro-guix-soft-require 'org-fragtog)
  (add-hook 'org-mode-hook #'cerebro-preview--maybe-live))

;;;###autoload
(defun cerebro-preview-status ()
  "Report what the in-buffer renderer can and cannot do here."
  (interactive)
  (let ((process (cerebro-preview-process)))
    (cerebro-report
     (format "cerebro preview -- %s"
             (if process (format "renderer: %s" process) "NO RENDERER"))
     (append
      (list (format "renderer   : %s" (or process "none -- formulas stay as source"))
            (format "scale      : %.2f (body %spt)"
                    (cerebro-preview-scale cerebro-theme-font-size)
                    (/ cerebro-theme-font-size 10))
            (format "images     : %s"
                    (mapconcat (lambda (type)
                                 (format "%s=%s" type
                                         (if (image-type-available-p type) "yes" "no")))
                               '(svg png) "  "))
            (format "macros     : %s"
                    (let ((sty (expand-file-name "cerebro-macros.sty"
                                                 cerebro-preview-latex-dir)))
                      (if (file-readable-p sty) sty "MISSING -- previews will fail")))
            (format "cache      : %s" org-preview-latex-image-directory)
            ""
            "candidates (first usable wins):")
      (mapcar
       (lambda (entry)
         (let* ((spec (cdr entry))
                (missing (seq-remove #'executable-find (plist-get spec :programs))))
           (format "  [%s] %-12s %s%s"
                   (if (eq (car entry) process) "ok" "--")
                   (car entry) (plist-get spec :why)
                   (if missing (format " (missing: %s)"
                                       (string-join missing ", "))
                     ""))))
       cerebro-preview-processes))
     #'identity
     "*cerebro-preview*")))

(provide 'cerebro-preview)
