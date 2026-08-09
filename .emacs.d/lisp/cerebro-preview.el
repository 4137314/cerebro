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

;; -- Making it fast: the preamble, compiled once -------------------------
;; Org renders one fragment per LaTeX run. The preamble above is small to
;; read and enormous to execute -- cerebro-macros.sty pulls in amsmath,
;; amssymb, mathtools, tikz, tikz-cd and pgfplots, 33 .sty files in all --
;; so every single \(\eps\) in a note paid ~0.66s to load a plotting
;; library it did not use. On a note with forty fragments that is half a
;; minute of frozen Emacs, which is the whole reason previews felt
;; unusable.
;;
;; The fix is LaTeX's own: dump the executed preamble into a format file
;; once (mylatexformat.ltx, part of texlive) and start every later run
;; from it. Measured here, same fragment, same output:
;;
;;     plain preamble        663 ms/run
;;     precompiled format    202 ms/run     3.3x
;;
;; Deliberately ONE format, holding the full preamble including the
;; graphics packages. A second, math-only format measured 160 ms -- a
;; further 20% -- and would have cost a per-fragment classifier deciding
;; which format a fragment needs, plus a wrong answer rendering a
;; tikzpicture against a preamble without tikz. This module's premise is
;; that the preview and the export agree; splitting the preamble is
;; exactly the way to lose that, for 40ms.
;;
;; Everything here degrades to "no format, compile as before": a missing
;; mylatexformat, a failed dump, a format built by a different TeX -- all
;; of them leave previews working and say so in `cerebro-preview-status'.

(defcustom cerebro-preview-use-format t
  "Whether to precompile the preview preamble into a LaTeX format file.
Set to nil to always run the full preamble per fragment (slower, one
fewer moving part). `cerebro-preview-status' reports which happened."
  :type 'boolean
  :group 'cerebro-preview)

(defconst cerebro-preview-format-directory
  (expand-file-name ".emacs.d/var/texfmt/" cerebro-root)
  "Where the precompiled preview format and its stamp live.
Under var/, with the image cache: both are derived, both are
gitignored, and both can be deleted at any time without losing
anything but the time to rebuild them.")

(defconst cerebro-preview-format-name "cerebro-preview"
  "Job name of the dumped format, hence the name of the .fmt file.")

;; -- Pure: is the format still the one this preamble asks for? ----------

(defun cerebro-preview-format-signature (preamble inputs)
  "A short digest identifying a format built from PREAMBLE. Pure.

INPUTS is an alist of (KEY . STAMP) for everything the format depends on
-- the stamp being anything that changes when that thing does. Editing
cerebro-macros.sty must invalidate the format as surely as editing the
preamble string does, and neither is visible in the .fmt itself.

The *engine* is one of those inputs, and leaving it out was a real bug
rather than an oversight: a .fmt is specific to the TeX that wrote it,
so a format dumped by the system TeX Live and then loaded by the pinned
Guix one is rejected outright -- latex aborts, no .dvi appears, and
every preview in the buffer fails with a message about dvisvgm that has
nothing to do with dvisvgm. Including `latex --version' here turns that
from a silent breakage into an automatic rebuild."
  (substring (secure-hash 'sha256
                          (format "%s\0%S\0%s" preamble inputs emacs-version))
             0 16))

(defvar cerebro-preview--engine nil
  "Cached identity of the TeX engine, or nil before it is asked for.
One `latex --version' per session: the engine cannot change underneath a
running Emacs, and this is on the path of every `cerebro-preview-apply'
\(load, and every theme change).")

(defun cerebro-preview-engine-identity ()
  "A string identifying the TeX that would run here.
Version *and* path: two TeX Lives of the same version in different
profiles -- exactly the system/Guix pair this repository lives with --
still write incompatible formats."
  (or cerebro-preview--engine
      (setq cerebro-preview--engine
            (if-let* ((program (executable-find "latex")))
                (format "%s\0%s" program
                        (car (split-string
                              (with-output-to-string
                                (with-current-buffer standard-output
                                  (ignore-errors
                                    (call-process "latex" nil t nil "--version"))))
                              "\n")))
              "no-latex"))))

(defun cerebro-preview-format-stale-p (recorded wanted)
  "Non-nil when a format stamped RECORDED cannot serve WANTED. Pure.
A missing stamp counts as stale, which is what makes the first run build."
  (not (and (stringp recorded) (equal recorded wanted))))

(defun cerebro-preview-format-compiler (command format-name)
  "COMMAND with `-fmt=FORMAT-NAME' spliced in after the program. Pure.

Org's `:latex-compiler' entries are command *strings* whose first token
is the engine (`latex', or `%l' where Org substitutes it). Inserting
after that token rather than rebuilding the command keeps every other
flag Org chose -- including ones a later Org may add."
  (if (string-match "\\`[ \t]*\\([^ \t]+\\)" command)
      (concat (substring command 0 (match-end 1))
              (format " -fmt=%s" format-name)
              (substring command (match-end 1)))
    command))

;; -- Impure: build it, prove it works, install it ----------------------

(defvar cerebro-preview--format nil
  "Path of the usable format file, or nil. See `cerebro-preview--format-note'.")
(defvar cerebro-preview--format-note "not built yet"
  "Why `cerebro-preview--format' is what it is, for the status report.")
(defvar cerebro-preview--format-checked nil
  "Non-nil once this session has decided about the format.")

(defun cerebro-preview--format-inputs ()
  "Everything the built format depends on, with a stamp per item."
  (let ((sty (expand-file-name "cerebro-macros.sty" cerebro-preview-latex-dir)))
    (list (cons sty (when (file-readable-p sty)
                      (format "%S" (file-attribute-modification-time
                                    (file-attributes sty)))))
          (cons "engine" (cerebro-preview-engine-identity)))))

(defun cerebro-preview--format-run (dir &rest args)
  "Run latex with ARGS in DIR, ignoring its exit status.

The status is ignored on purpose, and this is not laziness: a successful
`latex -ini' format dump *exits 1* (it produces no pages, which TeX
reports as a failure), while `latex -interaction=nonstopmode' happily
exits 0 on a document full of errors. The exit code is therefore
evidence of nothing in either direction. Every caller decides success by
looking for the file it wanted -- which is the thing that actually has
to exist."
  (let ((default-directory (file-name-as-directory dir))
        (process-environment
         (cons (format "TEXFORMATS=%s:" (directory-file-name dir))
               process-environment)))
    (apply #'call-process "latex" nil nil nil args)))

(defun cerebro-preview--format-probe (dir)
  "Compile a real fragment through the format in DIR. Non-nil if a .dvi appears.

This is the whole safety net, and it runs on the *cached* format too,
not only on a freshly built one. A .fmt is a binary artefact of one
particular TeX; anything that makes this engine refuse it -- a different
TeX Live, an upgraded one, a truncated file -- makes latex abort with no
output, and Org then reports \"File ... wasn't produced. Please adjust
`dvisvgm'\", which points at the wrong component entirely. One ~200ms
run per session is a cheap price for never handing Org a compiler that
cannot compile."
  (let ((probe (expand-file-name "probe.tex" dir))
        (probe-dvi (expand-file-name "probe.dvi" dir)))
    (when (file-exists-p probe-dvi) (delete-file probe-dvi))
    ;; A real fragment using real macros: if cerebro-macros.sty did not
    ;; survive the dump, `\abs' and `\eps' are undefined and no .dvi
    ;; appears -- which is the answer we want.
    (with-temp-file probe
      (insert cerebro-preview-preamble
              "\\begin{document}\n\\(\\abs{x}<\\eps\\)\n\\end{document}\n"))
    (cerebro-preview--format-run
     dir "-interaction=nonstopmode"
     (format "-fmt=%s" cerebro-preview-format-name)
     "-output-directory" (directory-file-name dir) probe)
    (file-readable-p probe-dvi)))

(defun cerebro-preview--format-build (dir)
  "Dump the preamble into a format in DIR, then prove it typesets.
Returns the .fmt path on success, nil on any failure -- a format that
dumps but cannot compile a fragment is worse than no format at all, so
the probe is not optional."
  (make-directory dir t)
  (let* ((source (expand-file-name "preamble.tex" dir))
         (fmt (expand-file-name (concat cerebro-preview-format-name ".fmt") dir)))
    (when (file-exists-p fmt) (delete-file fmt))
    (with-temp-file source
      (insert cerebro-preview-preamble "\\endofdump\n"))
    ;; `\endofdump' is mylatexformat's marker; `&latex' says which format
    ;; to extend. Without -ini this is not a dump but an ordinary run.
    (cerebro-preview--format-run
     dir "-interaction=nonstopmode" "-ini"
     (format "-jobname=%s" cerebro-preview-format-name)
     "&latex" "mylatexformat.ltx" source)
    (when (and (file-readable-p fmt) (cerebro-preview--format-probe dir))
      fmt)))

(defun cerebro-preview-ensure-format (&optional build)
  "The usable precompiled format, or nil. With BUILD, make one if missing.

Called two ways, and the distinction is the whole reason for the
argument. At load time it is called WITHOUT build: an existing, valid
format is picked up for free, and a missing one costs nothing -- dumping
5MB of format takes about a second, and a second of frozen Emacs at
startup to speed up something you may not do this session is a bad
trade. The first actual preview calls it WITH build and pays once.

Idempotent: the decision is cached once made, because it is reached from
every preview and cannot change without a file changing."
  (unless cerebro-preview--format-checked
    (cond
     ((not cerebro-preview-use-format)
      (setq cerebro-preview--format-checked t
            cerebro-preview--format-note "disabled (cerebro-preview-use-format)"))
     ((not (executable-find "latex"))
      (setq cerebro-preview--format-checked t
            cerebro-preview--format-note "no latex on PATH"))
     (t
      (let* ((dir cerebro-preview-format-directory)
             (stamp-file (expand-file-name "stamp" dir))
             (wanted (cerebro-preview-format-signature
                      cerebro-preview-preamble (cerebro-preview--format-inputs)))
             (recorded (when (file-readable-p stamp-file)
                         (with-temp-buffer (insert-file-contents stamp-file)
                                           (string-trim (buffer-string)))))
             (fmt (expand-file-name
                   (concat cerebro-preview-format-name ".fmt") dir)))
        (cond
         ;; A cached format is *verified*, never merely trusted -- see
         ;; `cerebro-preview--format-probe'. That costs one short latex
         ;; run, so it waits for BUILD (i.e. for a real preview) rather
         ;; than happening at load; an unverified format is treated as
         ;; absent until then, which errs towards "slow", never towards
         ;; "broken".
         ((and build (file-readable-p fmt)
               (not (cerebro-preview-format-stale-p recorded wanted))
               (cerebro-preview--format-probe dir))
          (setq cerebro-preview--format fmt
                cerebro-preview--format-checked t
                cerebro-preview--format-note "cached"))
         ;; Not there, stale, unusable, or nobody has asked for a preview
         ;; yet: leave the decision open so the next call can still build.
         ((not build) nil)
         ((string-empty-p (or (ignore-errors
                                (string-trim (shell-command-to-string
                                              "kpsewhich mylatexformat.ltx")))
                              ""))
          (setq cerebro-preview--format-checked t
                cerebro-preview--format-note "mylatexformat.ltx not installed"))
         (t
          (setq cerebro-preview--format-checked t)
          (message "cerebro: precompiling the LaTeX preview preamble (once)...")
          (if-let* ((built (cerebro-preview--format-build dir)))
              (progn
                (with-temp-file stamp-file (insert wanted "\n"))
                (setq cerebro-preview--format built
                      cerebro-preview--format-note "built now")
                (message "cerebro: preview preamble precompiled -- fragments now render ~3x faster"))
            (setq cerebro-preview--format nil
                  cerebro-preview--format-note "dump or probe failed"))))))))
  (when cerebro-preview--format
    (setenv "TEXFORMATS"
            (format "%s:" (directory-file-name cerebro-preview-format-directory))))
  cerebro-preview--format)

;; -- Size ---------------------------------------------------------------
;; A rendered formula should be the same optical size as the sentence it
;; sits in. That is arithmetic, not taste, and getting it right needs one
;; fact about Org that is easy to miss. `org-create-formula-image'
;; computes
;;
;;     scale = image-size-adjust x :scale        ; adjust is per RENDERER
;;     dpi   = scale x display-dpi
;;
;; and then hands the converter *either* `%D' (that dpi) *or* `%S'
;; (that dpi / 140), depending on which the program takes. Two regimes,
;; so two expressions -- and the second one is where this module was
;; wrong for a long time, in a way worth recording because it hid so
;; well.
;;
;;   - dvipng gets `-D %D'. It rasterises base-point-size text at that
;;     resolution, so the fragment is (base/72 x dpi) pixels tall while
;;     the buffer's text is (body/72 x display-dpi). The display
;;     resolution CANCELS, and matching them is just scale = body/base.
;;
;;   - dvisvgm gets `--scale=%S', and `%S' is a pure magnification of a
;;     document dvisvgm emits in POINTS (verified: the SVG it writes
;;     carries `width=51.55pt', not pixels). So the fragment and the
;;     prose are both physical sizes, whatever pt->px chain Emacs then
;;     applies applies to both equally, and the scale we want is again a
;;     ratio of two point sizes:
;;
;;         %S = relative x body / base
;;
;;     The catch: Org has *already* multiplied by the display dpi on the
;;     way to `%S'. So the `:scale' handed to Org must divide it back
;;     out. The old code multiplied by it instead, which put display-dpi
;;     SQUARED into what dvisvgm received -- and dpi^2/(72x140) happens
;;     to be 0.91 at 96dpi, so it looked correct on the machine it was
;;     fitted on and grew quadratically everywhere else: 2.5x too large
;;     at 157dpi, 3.7x at 192dpi. That is the "previews are enormous on
;;     a HiDPI screen" bug, and it is why
;;     `cerebro-preview-converter-scale' below exists and is asserted by
;;     a test: the number the converter actually receives must be
;;     independent of the display, and no derivation of it can contain
;;     dpi twice.
;;
;; Both of Org's own numbers (the per-backend adjust, the 140) are read
;; from Org rather than copied, so a backend Org retunes is retuned here
;; with it.

(defconst cerebro-preview-base-point-size 10
  "Point size of the document fragments are rendered from.
`cerebro-preview-preamble' says \\documentclass{article}, whose default
is 10pt. Change one and change the other.")

(defconst cerebro-preview-fallback-dpi 96
  "Display resolution assumed when there is no frame to measure.
Only reachable before the first graphical frame exists (a daemon, a
terminal); `cerebro-theme-after-apply-hook' recomputes the scale once
there is one.")

(defcustom cerebro-preview-relative-size 1.0
  "How large a rendered formula is, relative to the body text.

1.0 means a fragment is typeset at the size of the prose around it,
which is what LaTeX itself does inside a document and what makes an
inline \\(x\\) sit on the line instead of pushing it apart. Raise it if
you want display formulas to stand out; it stays proportional either
way, so changing the body size (`C-c u +') keeps the relation."
  :type 'number
  :group 'cerebro-preview)

(defun cerebro-preview-process-info (process)
  "Org's own entry for the renderer PROCESS."
  (alist-get process org-preview-latex-process-alist))

(defun cerebro-preview-size-adjust (process)
  "Org's own size multiplier for the renderer PROCESS.
Read from `org-preview-latex-process-alist' rather than copied: the
number is Org's, it differs per backend (1.7 for dvisvgm, 1.0 for
dvipng), and a second copy here would be a constant that silently stops
matching the thing it describes."
  (or (car (plist-get (cerebro-preview-process-info process) :image-size-adjust))
      1.0))

(defun cerebro-preview-dpi-based-p (process)
  "Non-nil when PROCESS is handed a resolution rather than a scale.

Decided by what its own converter command asks for -- `%D' is the dpi,
`%S' is dpi/140 -- because that is the actual difference between the two
sizing regimes, and it is written down once, in Org, in the same table
that defines the command."
  (let ((converter (plist-get (cerebro-preview-process-info process)
                              :image-converter)))
    (and (string-match-p "%D" (mapconcat #'identity converter " ")) t)))

(defconst cerebro-preview-org-scale-divisor 140.0
  "The constant Org divides its computed dpi by to produce `%S'.
A literal in `org-create-formula-image' (\"(/ dpi 140.0)\"), not a
variable, so it has to be written down somewhere -- here, once, next to
the arithmetic that has to undo it.")

(defun cerebro-preview-scale (font-size &optional adjust dpi relative)
  "Preview `:scale' for a body FONT-SIZE in 1/10 pt. Pure.

ADJUST is the renderer's multiplier (`cerebro-preview-size-adjust').
DPI, when non-nil, says the renderer is the scale-based kind, and is
divided back out because Org multiplies by it again on the way to `%S'
\(see the commentary above); nil means the dpi-based kind, where the
display resolution cancels on its own. RELATIVE is the wanted size
relative to the prose."
  (let* ((relative (or relative cerebro-preview-relative-size))
         (adjust (or adjust 1.0))
         (points (/ font-size 10.0)))
    (if dpi
        (/ (* cerebro-preview-org-scale-divisor relative points)
           (* cerebro-preview-base-point-size adjust dpi))
      (/ (* relative points)
         (* cerebro-preview-base-point-size adjust)))))

(defun cerebro-preview-converter-scale (font-size &optional adjust dpi relative)
  "What the converter actually receives, given `cerebro-preview-scale'. Pure.

The composition of this module's arithmetic with Org's, written out so
it can be asserted rather than reasoned about: for a scale-based
renderer this is dvisvgm's `--scale=%S', for a dpi-based one it is the
`-D %D' resolution divided by the display's, and in *both* cases the
answer must be RELATIVE x body/base and must not depend on DPI. A test
pins exactly that -- it is the invariant the old formula violated."
  (let ((scale (cerebro-preview-scale font-size adjust dpi relative))
        (adjust (or adjust 1.0)))
    (if dpi
        (/ (* adjust scale dpi) cerebro-preview-org-scale-divisor)
      (* adjust scale))))

(defun cerebro-preview-display-dpi ()
  "This display's resolution, or `cerebro-preview-fallback-dpi'."
  (if (display-graphic-p)
      (condition-case nil (org--get-display-dpi)
        (error cerebro-preview-fallback-dpi))
    cerebro-preview-fallback-dpi))

(defun cerebro-preview-current-scale (&optional process)
  "The `:scale' to use here, for PROCESS (default the chosen one)."
  (let ((process (or process org-preview-latex-default-process)))
    (cerebro-preview-scale cerebro-theme-font-size
                           (cerebro-preview-size-adjust process)
                           (unless (cerebro-preview-dpi-based-p process)
                             (cerebro-preview-display-dpi)))))

;; -- Keeping the image cache across displays ----------------------------
;;
;; Org names a rendered image after a SHA-1 of what it was rendered from,
;; and `org-format-latex-options' is one of the inputs (org.el, the `hash'
;; binding in `org-format-latex'). `:scale' lives in that plist -- and for
;; a scale-based renderer `cerebro-preview-current-scale' above divides by
;; the display's dpi, on purpose, so that Org multiplying it back in
;; leaves the converter with a display-independent number.
;;
;; Which means the cache was keyed on a quantity engineered to cancel out
;; of the result. Measured on one note, everything else identical:
;;
;;     dpi 100 -> :scale 0.9882 -> image 46d358bba6a6.svg
;;     dpi  96 -> :scale 1.0294 -> image 949dde9ab44f.svg
;;     dvisvgm receives --scale=1.2 in BOTH cases: the files are identical
;;
;; So attaching a monitor, moving the frame between screens, or a daemon
;; whose first frame came up somewhere else, silently invalidated every
;; rendered formula in the archive -- 2236 fragments, about a second each,
;; paid a note at a time on the next visit to each one. `org--get-display-dpi'
;; derives dpi from `display-mm-height', which is exactly the value that
;; changes when the hardware does.
;;
;; The fix is to stop letting Org compute the number. `%S' is replaced in
;; the converter command by the display-independent scale we already
;; compute (`cerebro-preview-converter-scale', which a test pins as not
;; depending on the display), and `:scale' -- now read by nothing but the
;; hash -- becomes that same stable number.
;;
;; ONLY for the scale-based renderers. dvipng gets `-D %D' and writes a
;; RASTER image, whose pixel dimensions must track the display or a
;; formula is the wrong physical size on a HiDPI screen. There the
;; display-dependence of the key is not a bug, it is the point, so that
;; path is left exactly as Org shipped it.

(defconst cerebro-preview-scale-decimals 4
  "Decimal places the baked-in preview scale is rounded to.

Four is far past what any renderer can show -- a 0.0001 difference in
magnification is a fraction of a device pixel -- and the rounding is not
about the picture. It is about the *name* of the picture: this number
goes into Org's cache key, so two values that differ in the sixteenth
decimal are two full re-renders of the archive.")

(defun cerebro-preview-stable-scale (&optional process)
  "The display-independent scale for PROCESS: what dvisvgm receives.

`cerebro-preview-converter-scale' asked with NO dpi, which is the whole
point. Handed a dpi it computes the same number by dividing it out and
multiplying it back in -- mathematically an identity, in binary floating
point not quite one: the same 1.2 came back as 1.2 at 100dpi and as
1.1999999999999997 at 96dpi. That is a different SHA-1, so the residue
alone reproduced the entire bug this function exists to remove, just
less often and far harder to see. Asking for the dpi-free branch never
forms the quotient at all, and the rounding makes the guarantee hold
whatever arithmetic a future backend's `adjust' introduces."
  (let ((process (or process org-preview-latex-default-process)))
    (let ((scale (cerebro-preview-converter-scale
                  cerebro-theme-font-size
                  (cerebro-preview-size-adjust process)
                  nil))
          (factor (expt 10.0 cerebro-preview-scale-decimals)))
      (/ (fround (* scale factor)) factor))))

(defun cerebro-preview-cache-scale (&optional process)
  "The `:scale' to store in `org-format-latex-options', for PROCESS.

Display-independent for a vector renderer (nothing reads it but Org's
cache key, since the converter carries its own scale); Org's own
display-dependent number for a raster one, which still needs it."
  (let ((process (or process org-preview-latex-default-process)))
    (if (cerebro-preview-dpi-based-p process)
        (cerebro-preview-current-scale process)
      (cerebro-preview-stable-scale process))))

(defun cerebro-preview-converter-command (command scale)
  "COMMAND with Org's `%S' spec replaced by the literal SCALE. Pure.

Only `%S'. `%f', `%O' and `%o' are Org's file names and stay Org's to
fill in -- this substitutes the one spec whose value we can compute
better than Org can, and leaves the rest of the command untouched."
  (replace-regexp-in-string "%S" (number-to-string scale) command t t))

;; -- Generated figures are sized in columns of text ---------------------
;; A `#+begin_src latex :file fig.svg' block produces an ordinary inline
;; image, and Org sizes those in *pixels* -- a constant that means one
;; thing at 12pt and something else entirely at 18pt or on another
;; screen. A figure belongs to the measure of the text it interrupts, so
;; it is given a width in characters and the character width is asked of
;; the font in use. Recomputed on every theme/size change, like the
;; scale above.

(defcustom cerebro-preview-figure-columns 60
  "Width of an inline figure, in characters of body text.
Sixty is a little over half a comfortable measure -- large enough to
read a plot, small enough that the paragraph after it is still visible."
  :type 'integer
  :group 'cerebro-preview)

(defun cerebro-preview-figure-width (columns char-width)
  "Width in pixels of a figure COLUMNS characters wide. Pure."
  (max 1 (round (* columns char-width))))

(defun cerebro-preview--char-width ()
  "Width of one character of body text, in pixels.
Asked of the font when there is one to ask; estimated from the body size
otherwise (batch, a terminal frame), so this never fails in the places
that have no glyphs to measure."
  (if (and (display-graphic-p) (fboundp 'default-font-width))
      (default-font-width)
    ;; A monospace advance is ~0.6em, and an em is the body size in
    ;; points, at the 96dpi Emacs assumes for a nominal display.
    (max 1 (round (* 0.6 (/ cerebro-theme-font-size 10.0) (/ 96.0 72.0))))))

;; -- Wiring Org ---------------------------------------------------------

(defvar cerebro-preview--pristine-compilers nil
  "PROCESS -> the `:latex-compiler' Org shipped, before we touched it.
Kept so `cerebro-preview--install-compiler' always derives from Org's
own command rather than from its own previous output -- otherwise
re-applying (a theme switch, a second `require') would splice `-fmt='
in twice.")

(defvar cerebro-preview--pristine-converters nil
  "PROCESS -> the `:image-converter' Org shipped, before we touched it.
Same reason as `cerebro-preview--pristine-compilers': the rewrite must
always derive from Org's own command, never from its own previous
output, or re-applying it (a theme switch, a font-size change, a second
`require') would substitute into an already-substituted string.")

(defun cerebro-preview--install-converter (process)
  "Bake the display-independent scale into PROCESS's converter command.

The whole point of the exercise: with `%S' resolved here, Org's
`:scale' stops being read by anything except its own cache key, and can
therefore be a number that does not move when the display does. A
raster backend is left alone -- see the commentary above
`cerebro-preview-stable-scale'."
  (let* ((info (cerebro-preview-process-info process))
         (pristine (or (alist-get process cerebro-preview--pristine-converters)
                       (setf (alist-get process cerebro-preview--pristine-converters)
                             (plist-get info :image-converter)))))
    (plist-put info :image-converter
               (if (cerebro-preview-dpi-based-p process)
                   pristine
                 (let ((scale (cerebro-preview-stable-scale process)))
                   (mapcar (lambda (command)
                             (cerebro-preview-converter-command command scale))
                           pristine))))))

(defun cerebro-preview--install-compiler (process)
  "Make PROCESS compile through the precompiled format, when there is one."
  (let* ((info (cerebro-preview-process-info process))
         (pristine (or (alist-get process cerebro-preview--pristine-compilers)
                       (setf (alist-get process cerebro-preview--pristine-compilers)
                             (plist-get info :latex-compiler)))))
    (plist-put info :latex-compiler
               (if (cerebro-preview-ensure-format)
                   (mapcar (lambda (command)
                             (cerebro-preview-format-compiler
                              command cerebro-preview-format-name))
                           pristine)
                 pristine))))

(defun cerebro-preview-apply ()
  "Point Org's preview machinery at cerebro's preamble, backend and size.
Called at load and again from `cerebro-theme-after-apply-hook', because
previews bake the theme's foreground colour and the body size into the
image: after a theme switch the cached images are wrong, not stale."
  (setq org-format-latex-header cerebro-preview-preamble)
  (when-let* ((process (cerebro-preview-process)))
    (setq org-preview-latex-default-process process)
    (cerebro-preview--install-compiler process)
    ;; Before `:scale' is set below: the converter now carries the scale,
    ;; which is what lets that `:scale' be display-independent.
    (cerebro-preview--install-converter process))
  ;; Cache the generated images outside the notes tree. Org's default
  ;; ("ltximg/", relative to the note) drops a directory of derived files
  ;; into every notes subdirectory -- untracked litter in a repo whose
  ;; whole premise is that what is committed is the second brain.
  (setq org-preview-latex-image-directory
        (expand-file-name ".emacs.d/var/ltximg/" cerebro-root))
  (setq org-format-latex-options
        (plist-put (plist-put (copy-sequence org-format-latex-options)
                              :scale (cerebro-preview-cache-scale))
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
        (plist-put org-format-latex-options :matchers '("begin" "\\(" "\\[")))
  ;; ...and the generated figures, in characters of the same body text.
  (setq org-image-actual-width
        (list (cerebro-preview-figure-width cerebro-preview-figure-columns
                                            (cerebro-preview--char-width)))))

(cerebro-preview-apply)
(add-hook 'cerebro-theme-after-apply-hook #'cerebro-preview-apply)

;; -- The one-off format build, deferred to the first preview -------------

(defun cerebro-preview-prepare (&rest _)
  "Build the precompiled format if this is the first preview, and wire it in.
Advice on `org-latex-preview', so it covers every route to a rendered
fragment -- `C-c u p', Org's own `C-c C-x C-l', and org-fragtog
re-rendering as point leaves a formula -- rather than only the commands
this module happens to define. After the first call it is one variable
test."
  (unless cerebro-preview--format-checked
    (when (cerebro-preview-ensure-format t)
      (when-let* ((process (cerebro-preview-process)))
        (cerebro-preview--install-compiler process)))))

(advice-add 'org-latex-preview :before #'cerebro-preview-prepare)

;; -- Warming the cache, so navigating the archive is instant ------------
;;
;; With the key stable (see `cerebro-preview-stable-scale'), a rendered
;; formula is rendered once and then belongs to the archive: opening a
;; note whose fragments are all cached costs about 25ms for eighty of
;; them, because nothing runs LaTeX. What is left is the *first* visit,
;; and paying it a note at a time is exactly when it is most in the way
;; -- you opened the note to read it.
;;
;; So: pay it once, deliberately, for everything. This renders every
;; fragment in the archive that is not already cached; afterwards,
;; reading is cache hits all the way down. It needs a graphical frame
;; (Org refuses to build in-buffer previews without one) and it is
;; interruptible -- C-g stops it and keeps every image already written,
;; because the cache is a directory of files and not a transaction.

(defun cerebro-preview-cached-count ()
  "How many rendered images are in the cache directory."
  (let ((dir org-preview-latex-image-directory))
    (if (file-directory-p dir)
        (length (directory-files dir nil "\\.\\(svg\\|png\\)\\'" t))
      0)))

;;;###autoload
(defun cerebro-preview-warm (&optional files)
  "Render every uncached formula in the archive, so reading is instant.

FILES defaults to the whole archive (`cerebro-note-files'). Fragments
already in the cache are not re-rendered -- Org checks the file before
it runs LaTeX -- so this is cheap to repeat and is the thing to run
after `C-c u R', after a font-size change, or after writing a batch of
notes.

Interruptible: `C-g' stops after the note in hand, and everything
rendered so far stays rendered."
  (interactive)
  (unless (display-graphic-p)
    (user-error "cerebro-preview: warming needs a graphical frame"))
  (unless (cerebro-preview-process)
    (user-error "cerebro-preview: no renderer here -- see `C-c u P'"))
  ;; Build the format first, once, rather than discovering it is missing
  ;; on the first fragment of the first note.
  (cerebro-preview-prepare)
  (let* ((files (or files (cerebro-note-files)))
         (total (length files))
         (before (cerebro-preview-cached-count))
         (reporter (make-progress-reporter "cerebro: warming previews" 0 total))
         (done 0))
    (unwind-protect
        (with-temp-buffer
          (delay-mode-hooks (org-mode))
          (dolist (file files)
            (erase-buffer)
            (insert-file-contents file)
            ;; Exactly the call `org--latex-preview-region' makes, and
            ;; every argument of it is load-bearing:
            ;;
            ;;   - the image directory is part of the PREFIX, not the DIR
            ;;     argument. DIR is only what relative paths resolve
            ;;     against. Passing "org-ltximg" and the note's own
            ;;     directory -- which reads perfectly naturally -- writes
            ;;     the images *into notes/*, which is the litter this
            ;;     module moved the cache out of the tree to avoid.
            ;;   - `forbuffer' is one of the hash inputs, so a warm run
            ;;     must ask for it exactly as a real buffer does, or it
            ;;     fills the cache with entries nothing will ever look up
            ;;     and every note still renders from scratch on opening.
            (ignore-errors
              (org-format-latex
               (concat org-preview-latex-image-directory "org-ltximg")
               (point-min) (point-max)
               default-directory 'overlays nil 'forbuffer
               org-preview-latex-default-process))
            (org-clear-latex-preview (point-min) (point-max))
            (progress-reporter-update reporter (setq done (1+ done)))))
      (progress-reporter-done reporter))
    (message "cerebro: %d note%s, %d new image%s cached (%d total)"
             done (if (= done 1) "" "s")
             (- (cerebro-preview-cached-count) before)
             (if (= (- (cerebro-preview-cached-count) before) 1) "" "s")
             (cerebro-preview-cached-count))))

;;;###autoload
(defun cerebro-preview-rebuild-format ()
  "Throw away the precompiled preview format and build it again.
The repair for \"previews suddenly stopped compiling\" after a TeX
upgrade: a format written by a different engine is rejected wholesale,
and the stamp records what this repository put in, so it cannot know
that the engine underneath changed."
  (interactive)
  (setq cerebro-preview--format nil
        cerebro-preview--format-checked nil
        cerebro-preview--engine nil        ; re-ask: the TeX may be why
        cerebro-preview--format-note "not built yet")
  (when (file-directory-p cerebro-preview-format-directory)
    (delete-directory cerebro-preview-format-directory t))
  (cerebro-preview-ensure-format t)
  (cerebro-preview-apply)
  (message "cerebro: preview format -- %s" cerebro-preview--format-note))

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
(defun cerebro-preview-resize (step)
  "Change `cerebro-preview-relative-size' by STEP and re-render.

The arithmetic above targets \"a formula is the size of the prose\",
which is the right default and not everyone's taste -- a display
estimate one notices is worth a few percent. This is that adjustment,
live, instead of an edit to a defcustom and a restart: it goes through
`cerebro-preview-apply', so the new size reaches the figures and the
already-rendered fragments too."
  (interactive (list 0.1))
  (setq cerebro-preview-relative-size
        (max 0.2 (+ cerebro-preview-relative-size step)))
  (cerebro-preview-apply)
  (cerebro-preview-refresh)
  (message "cerebro: previews at %.0f%% of the body text"
           (* 100 cerebro-preview-relative-size)))

;;;###autoload
(defun cerebro-preview-enlarge ()
  "Render formulas 10% larger relative to the prose."
  (interactive)
  (cerebro-preview-resize 0.1))

;;;###autoload
(defun cerebro-preview-shrink ()
  "Render formulas 10% smaller relative to the prose."
  (interactive)
  (cerebro-preview-resize -0.1))

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

;; (There is no `cerebro-preview-live-by-default': which buffers get this
;; is `cerebro-study-default' plus the `:watch-point' column of
;; `cerebro-study-modes'. A second switch for the same decision is how
;; the two end up disagreeing.)

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

;; Nothing here turns the mode on by itself any more, and that is the
;; point: whether the formula at point un-renders is one of the things
;; that distinguishes *writing* a note from *reading* one, so it is
;; decided by `cerebro-study-modes' (cerebro-study.el) along with the
;; rendering, the markup and the column width -- one owner, one answer.
;;
;; It used to be switched on from `org-mode-hook' here, unconditionally,
;; which meant every note was read in the writing configuration: a timer
;; asking `org-element-context' on every command, at ~4ms a call, while
;; scrolling issues a hundred commands a second in which point never
;; moves. That was the scrolling lag, and it was not a bug in org-fragtog
;; -- it was a bug in having no mode where reading is what you are doing.

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
            (format "speed      : %s -- %s"
                    (if cerebro-preview--format
                        "precompiled format (~3x faster per fragment)"
                      "full preamble on every fragment")
                    cerebro-preview--format-note)
            (format "engine     : %s"
                    (replace-regexp-in-string "\0" "  " (cerebro-preview-engine-identity)))
            (format "scale      : :scale %.3f -> converter gets %.3f  (want %.3f)"
                    (cerebro-preview-current-scale process)
                    (cerebro-preview-converter-scale
                     cerebro-theme-font-size
                     (cerebro-preview-size-adjust process)
                     (unless (cerebro-preview-dpi-based-p process)
                       (cerebro-preview-display-dpi)))
                    (* cerebro-preview-relative-size
                       (/ (/ cerebro-theme-font-size 10.0)
                          (float cerebro-preview-base-point-size))))
            (format "             body %.1fpt x %.0f%%, base %dpt, %.0f dpi, %s (adjust %.1f)"
                    (/ cerebro-theme-font-size 10.0)
                    (* 100 cerebro-preview-relative-size)
                    cerebro-preview-base-point-size
                    (cerebro-preview-display-dpi)
                    (if (cerebro-preview-dpi-based-p process)
                        "resolution-based" "scale-based")
                    (cerebro-preview-size-adjust process))
            (format "cache      : %d image(s) in %s"
                    (cerebro-preview-cached-count)
                    (abbreviate-file-name org-preview-latex-image-directory))
            (format "             keyed on :scale %s the display -- %s"
                    (if (cerebro-preview-dpi-based-p process) "AND" "but NOT")
                    (if (cerebro-preview-dpi-based-p process)
                        "raster output: pixel size must track the screen"
                      "vector output: the same file on any screen (C-c u w warms it)"))
            (format "figures    : %d px (%d columns of body text)"
                    (cerebro-preview-figure-width cerebro-preview-figure-columns
                                                  (cerebro-preview--char-width))
                    cerebro-preview-figure-columns)
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
