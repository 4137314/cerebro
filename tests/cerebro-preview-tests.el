;;; cerebro-preview-tests.el --- ERT tests for in-buffer rendering -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-preview-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; The claim this module makes is strong -- "a fragment that previews is a
;; fragment that will compile" -- and it rests on three mechanisms that
;; fail quietly if they drift:
;;
;;   1. TEXINPUTS must *gain* the project's latex/ directory, never
;;      replace the search path (a replaced path loses every standard
;;      package, and the error you get is about amsmath, not about this);
;;   2. the renderer must be chosen from what is installed, degrading
;;      dvisvgm -> dvipng -> nothing rather than failing per fragment;
;;   3. the fragment delimiters must stay the ones the linter allows --
;;      previewing `$...$' would render exactly the notation
;;      bin/notes-lint.el rejects, teaching the wrong habit.
;;
;; All three are checked here as pure functions, with no LaTeX toolchain
;; and no display.

(require 'ert)
(require 'cerebro-preview)

;; -- TEXINPUTS ----------------------------------------------------------

(ert-deftest cerebro-preview-test-texinputs-prepends-and-keeps-the-path ()
  "The project directory goes first, and what was there is kept."
  (let ((result (cerebro-preview-texinputs "/repo/latex" "/other:")))
    (should (string-prefix-p "/repo/latex/:" result))
    (should (string-suffix-p "/other:" result))))

(ert-deftest cerebro-preview-test-texinputs-is-idempotent ()
  "Re-running never grows the variable.
This module is re-applied on every theme change, so a non-idempotent
version would append the same directory dozens of times in one session."
  (let* ((once (cerebro-preview-texinputs "/repo/latex" "/other:"))
         (twice (cerebro-preview-texinputs "/repo/latex" once)))
    (should (equal once twice))))

(ert-deftest cerebro-preview-test-texinputs-handles-empty-environment ()
  "An unset TEXINPUTS is the normal case, not an error."
  (let ((result (cerebro-preview-texinputs "/repo/latex" nil)))
    (should (string-prefix-p "/repo/latex/:" result))))

;; -- Choosing a renderer ------------------------------------------------

(ert-deftest cerebro-preview-test-select-process-prefers-vector ()
  "With everything installed, the vector renderer wins."
  (should (eq (car (cerebro-preview-select-process
                    cerebro-preview-processes
                    (lambda (_type) t)
                    (lambda (_program) t)))
              'dvisvgm)))

(ert-deftest cerebro-preview-test-select-process-degrades ()
  "A missing program drops that backend, it does not disable previews."
  (should (eq (car (cerebro-preview-select-process
                    cerebro-preview-processes
                    (lambda (_type) t)
                    (lambda (program) (not (equal program "dvisvgm")))))
              'dvipng))
  ;; No SVG support in this Emacs build: same fallback, different reason.
  (should (eq (car (cerebro-preview-select-process
                    cerebro-preview-processes
                    (lambda (type) (not (eq type 'svg)))
                    (lambda (_program) t)))
              'dvipng)))

(ert-deftest cerebro-preview-test-select-process-nil-without-latex ()
  "No LaTeX at all returns nil -- the caller then says so instead of
pointing Org at a program that does not exist."
  (should-not (cerebro-preview-select-process
               cerebro-preview-processes
               (lambda (_type) t)
               (lambda (_program) nil))))

(ert-deftest cerebro-preview-test-processes-are-known-to-org ()
  "Every candidate names a backend Org actually implements.
The symbols are handed to `org-preview-latex-default-process'; an invented
one fails at render time, in a message about a missing key."
  (dolist (entry cerebro-preview-processes)
    (should (assq (car entry) org-preview-latex-process-alist))
    (should (plist-get (cdr entry) :programs))
    (should (plist-get (cdr entry) :why))))

;; -- Size ---------------------------------------------------------------

(ert-deftest cerebro-preview-test-scale-matches-the-body-text ()
  "A formula comes out the size of the prose beside it, on both backends.

The quantity that matters is what the *converter* is handed, not what
this module returns: Org multiplies our `:scale' by the renderer's
adjust and by the display dpi before passing `%D'/`%S' on. Composed,
that must magnify the `base'-point document to the body size -- a ratio
of two point sizes, on either backend."
  (let* ((body 120)                            ; 12pt body, 10pt base
         (want (/ (/ body 10.0) (float cerebro-preview-base-point-size))))
    (should (< (abs (- (cerebro-preview-converter-scale body 1.0 nil 1.0) want))
               0.001))
    (should (< (abs (- (cerebro-preview-converter-scale body 1.7 100 1.0) want))
               0.001))))

(ert-deftest cerebro-preview-test-scale-does-not-depend-on-the-display ()
  "The magnification the converter receives is the same at every dpi.

This is the regression test for the bug that made previews unusable on
a HiDPI screen. Org forms `%S' as (adjust x :scale x display-dpi)/140,
so a `:scale' that *multiplies* by the display dpi puts it in twice --
and dpi^2/(72x140) is 0.91 at 96dpi, which is why it looked correct on
the machine it was fitted on and was 2.5x too large at 157dpi and 3.7x
at 192dpi. No correct derivation contains the display resolution twice;
this pins that it contains it zero times."
  (let ((sizes (mapcar (lambda (dpi) (cerebro-preview-converter-scale 120 1.7 dpi 1.0))
                       '(96 110 130 157 192 218))))
    (dolist (size sizes)
      (should (< (abs (- size (car sizes))) 0.0001)))))

;; -- The cache key, which is a different question from the size --------
;;
;; The test above pins that the rendered formula is the same at every
;; dpi. That was necessary and not sufficient: Org names the image after
;; a SHA-1 that includes `org-format-latex-options', `:scale' and all, so
;; the archive could -- and did -- re-render every fragment on a display
;; whose dpi differed, to produce byte-identical files under new names.

(ert-deftest cerebro-preview-test-stable-scale-is-exactly-equal-across-dpi ()
  "The baked-in scale is `equal', not merely close, at every dpi.

`<0.0001' is the right tolerance for a picture and the wrong one for a
file name. `cerebro-preview-stable-scale' feeds a SHA-1, so 1.2 and
1.1999999999999997 are as different as 1.2 and 7 -- and that pair is
real: it is what the dpi-cancelling arithmetic returned at 100dpi and at
96dpi respectively, before this function stopped forming the quotient
and started rounding."
  (let ((values (mapcar (lambda (dpi)
                          (let ((scale (cerebro-preview-converter-scale 120 1.7 dpi 1.0))
                                (factor (expt 10.0 cerebro-preview-scale-decimals)))
                            (/ (fround (* scale factor)) factor)))
                        '(96 100 141 157 192 218))))
    (dolist (value values)
      (should (equal value (car values))))))

(ert-deftest cerebro-preview-test-converter-command-substitutes-only-the-scale ()
  "`%S' is replaced by a literal; Org's file specs are left to Org.
Substituting `%f'/`%O'/`%o' would hand the converter a file name chosen
before there was a file."
  (let ((out (cerebro-preview-converter-command
              "dvisvgm %f --no-fonts --exact-bbox --scale=%S --output=%O" 1.2)))
    (should (equal out "dvisvgm %f --no-fonts --exact-bbox --scale=1.2 --output=%O"))
    (should-not (string-match-p "%S" out))
    (should (string-match-p "%f" out))
    (should (string-match-p "%O" out)))
  ;; A raster command has no `%S' and must come through untouched.
  (should (equal (cerebro-preview-converter-command "dvipng -D %D -T tight -o %O %f" 1.2)
                 "dvipng -D %D -T tight -o %O %f")))

(ert-deftest cerebro-preview-test-baking-the-scale-is-idempotent ()
  "Re-applying does not substitute into an already-substituted command.

`cerebro-preview-apply' runs again on every theme switch and font-size
change, so this is reached constantly. The guard is that the rewrite
always starts from Org's pristine command -- the same reason
`cerebro-preview--pristine-compilers' exists for the `-fmt=' splice."
  (let ((once (cerebro-preview-converter-command "dvisvgm --scale=%S -o %O" 1.2)))
    (should (equal (cerebro-preview-converter-command once 1.2) once))))

(ert-deftest cerebro-preview-test-only-the-vector-backend-loses-the-dpi ()
  "A raster backend keeps the display in its cache key, on purpose.

dvipng writes PNG: its pixel dimensions *must* track the display or the
formula is the wrong physical size on a HiDPI screen, so there the
display-dependence of the key is the point rather than a defect. Only
dvisvgm, whose SVG carries points and is resolution-independent, has a
key that should not move."
  (should (cerebro-preview-dpi-based-p 'dvipng))
  (should-not (cerebro-preview-dpi-based-p 'dvisvgm)))

(ert-deftest cerebro-preview-test-scale-follows-the-body-size ()
  "Doubling the body size doubles the scale on either backend: the
relation is kept, so `C-c u +' moves formulas and prose together."
  (should (= (cerebro-preview-scale 240 1.0 nil 1.0)
             (* 2 (cerebro-preview-scale 120 1.0 nil 1.0))))
  (should (= (cerebro-preview-scale 240 1.7 100 1.0)
             (* 2 (cerebro-preview-scale 120 1.7 100 1.0)))))

(ert-deftest cerebro-preview-test-scale-accounts-for-the-renderer ()
  "Which regime a backend is in is read from its own converter command,
and the multiplier from Org's table -- not from constants here.

A hand-fitted constant for every backend drew formulas at 1.7x on
dvisvgm (twice the text); reading the multiplier from Org is what keeps
the two backends from needing two hand-fitted constants."
  (should (cerebro-preview-dpi-based-p 'dvipng))        ; -D %D
  (should (cerebro-preview-dpi-based-p 'imagemagick))   ; -density %D
  (should-not (cerebro-preview-dpi-based-p 'dvisvgm))   ; --scale=%S
  (should (= (cerebro-preview-size-adjust 'dvisvgm) 1.7))
  (should (= (cerebro-preview-size-adjust 'dvipng) 1.0))
  ;; An unknown backend must not divide by nil.
  (should (= (cerebro-preview-size-adjust 'no-such-renderer) 1.0))
  ;; A denser display needs a *smaller* `:scale', because Org multiplies
  ;; by the dpi on the way to `%S' and the result must not move.
  (should (< (cerebro-preview-scale 120 1.7 200 1.0)
             (cerebro-preview-scale 120 1.7 100 1.0))))

(ert-deftest cerebro-preview-test-relative-size-is-a-multiplier ()
  "Wanting formulas half again as large is one number, still proportional."
  ;; `<' on a difference, not `=': these are floats.
  (should (< (abs (- (cerebro-preview-scale 120 1.0 nil 1.5)
                     (* 1.5 (cerebro-preview-scale 120 1.0 nil 1.0))))
             0.0001)))

(ert-deftest cerebro-preview-test-figures-are-sized-in-columns ()
  "A generated figure is as wide as N characters of body text, so it
scales with the font instead of being a pixel constant that means one
thing at 12pt and another at 18."
  (should (= (cerebro-preview-figure-width 60 10) 600))
  (should (= (cerebro-preview-figure-width 60 15) 900))
  ;; Never zero: a width of 0 is an image Emacs refuses to draw.
  (should (>= (cerebro-preview-figure-width 1 0.1) 1)))

(ert-deftest cerebro-preview-test-matchers-exclude-dollars ()
  "`$...$' is never previewed: the linter rejects it in notes.
Org's default matcher list includes \"$\" and \"$$\"; leaving them in
would render the one notation this project forbids (see CLAUDE.md: a `$'
next to punctuation mis-parses silently)."
  (cerebro-preview-apply)
  (let ((matchers (plist-get org-format-latex-options :matchers)))
    (should (member "\\(" matchers))
    (should (member "\\[" matchers))
    (should-not (member "$" matchers))
    (should-not (member "$$" matchers))))

(ert-deftest cerebro-preview-test-background-is-transparent ()
  "Previews are rendered on no background at all.
Not a preference: asking for one makes Org emit `\\pagecolor', which
dvisvgm turns into a `<rect>' with no `fill' attribute -- and Emacs
paints an unattributed SVG shape in the *foreground* colour, so the
backing rectangle comes out the same colour as the glyphs and every
formula renders as an opaque block. Observed, isolated, and pinned here
so it cannot come back as a well-meaning \"make previews match the
theme\" change."
  (cerebro-preview-apply)
  (should (equal (plist-get org-format-latex-options :background) "Transparent"))
  ;; The foreground, by contrast, must stay tied to the theme: that is
  ;; what puts a real colour on the glyphs in the generated file.
  (should (eq (plist-get org-format-latex-options :foreground) 'default)))

(ert-deftest cerebro-preview-test-preamble-uses-the-projects-macros ()
  "Previews load cerebro-macros.sty, and only that.
Sharing the exporter's macro file is what makes a preview predictive of
the PDF; listing packages here as well would be a second list to drift."
  (should (string-match-p "usepackage{cerebro-macros}" cerebro-preview-preamble))
  (should (string-match-p "NO-DEFAULT-PACKAGES" cerebro-preview-preamble))
  ;; The file it depends on is really in the repo.
  (should (file-readable-p (expand-file-name "cerebro-macros.sty"
                                             cerebro-preview-latex-dir))))

(ert-deftest cerebro-preview-test-refresh-drops-stale-previews ()
  "A theme change removes the images rendered in the previous palette.
They are bitmaps: nothing about them updates by itself, and Org's cache
hashes the resolved colours into the file name, so the wrong image would
otherwise sit there until someone pressed a key."
  (with-temp-buffer
    (org-mode)
    (insert "\\(x\\)\n")
    (let ((overlay (make-overlay (point-min) (point-max))))
      (overlay-put overlay 'org-overlay-type 'org-latex-overlay)
      (should (cerebro-preview-buffer-previewed-p))
      (let ((cerebro-preview-on-theme-change 'clear))
        (cerebro-preview-refresh))
      (should-not (cerebro-preview-buffer-previewed-p))))
  ;; ...and nil means "leave them alone", for the person who would rather
  ;; keep looking at slightly-wrong colours than lose the rendering.
  (with-temp-buffer
    (org-mode)
    (insert "\\(x\\)\n")
    (overlay-put (make-overlay (point-min) (point-max))
                 'org-overlay-type 'org-latex-overlay)
    (let ((cerebro-preview-on-theme-change nil))
      (cerebro-preview-refresh))
    (should (cerebro-preview-buffer-previewed-p))))

(ert-deftest cerebro-preview-test-refresh-runs-after-apply ()
  "On a theme change the options are updated *before* previews refresh.
The other order re-renders with the palette that just went away."
  (let ((hook cerebro-theme-after-apply-hook))
    (should (memq 'cerebro-preview-apply hook))
    (should (memq 'cerebro-preview-refresh hook))
    (should (< (seq-position hook 'cerebro-preview-apply)
               (seq-position hook 'cerebro-preview-refresh)))))

(ert-deftest cerebro-preview-test-images-are-cached-outside-the-notes ()
  "Generated images never land in notes/.
Org's default is a `ltximg/' directory beside the note -- untracked
derived files scattered through a repository whose premise is that what
is committed is the second brain."
  (cerebro-preview-apply)
  (should-not (string-prefix-p (file-name-as-directory (expand-file-name org-directory))
                               (expand-file-name org-preview-latex-image-directory))))

;; -- The precompiled format ---------------------------------------------
;; Org runs LaTeX once per fragment, and this preamble loads 33 packages,
;; so the dump is what makes previews usable at all (663ms -> 202ms per
;; fragment, measured). The pure parts are what decide *when* it is
;; rebuilt and *how* it is spliced into Org's command; getting either
;; wrong is silent -- a stale format renders yesterday's macros, and a
;; doubled `-fmt=' makes every preview fail at once.

(ert-deftest cerebro-preview-test-format-signature-follows-its-inputs ()
  "The signature changes when the preamble changes, and when a file does.
Editing cerebro-macros.sty must invalidate the format as surely as
editing the preamble string: neither is visible from the .fmt itself, so
a signature that ignored the .sty would serve a format built from the
old macros forever."
  (let ((inputs '(("/repo/latex/cerebro-macros.sty" . "stamp-1"))))
    (should (equal (cerebro-preview-format-signature "A" inputs)
                   (cerebro-preview-format-signature "A" inputs)))
    (should-not (equal (cerebro-preview-format-signature "A" inputs)
                       (cerebro-preview-format-signature "B" inputs)))
    (should-not (equal (cerebro-preview-format-signature "A" inputs)
                       (cerebro-preview-format-signature
                        "A" '(("/repo/latex/cerebro-macros.sty" . "stamp-2")))))))

(ert-deftest cerebro-preview-test-format-signature-includes-the-engine ()
  "A format built by one TeX must not be offered to another.

This is a regression test for a real breakage, not a hypothetical. A
.fmt is a binary artefact of the engine that wrote it: one dumped by the
system TeX Live and then loaded by the pinned Guix one is rejected
outright, latex aborts producing nothing, and Org reports \"File ...
wasn't produced. Please adjust `dvisvgm'\" -- naming the one component
that is not at fault. Since the engine is invisible in the preamble and
in cerebro-macros.sty, it has to be an input to the signature, or the
stamp says `fresh' about a format this TeX cannot read."
  (should-not (equal (cerebro-preview-format-signature
                      "P" '(("engine" . "/usr/bin/latex TeX Live 2026")))
                     (cerebro-preview-format-signature
                      "P" '(("engine" . "/gnu/store/xxx/bin/latex TeX Live 2024")))))
  ;; ...and the real input list actually carries it.
  (should (assoc "engine" (cerebro-preview--format-inputs))))

(ert-deftest cerebro-preview-test-format-staleness ()
  "A matching stamp is fresh; anything else -- including none -- is stale.
The missing case is what makes the very first preview build a format
rather than silently running without one."
  (should-not (cerebro-preview-format-stale-p "abc" "abc"))
  (should (cerebro-preview-format-stale-p "abc" "def"))
  (should (cerebro-preview-format-stale-p nil "abc")))

(ert-deftest cerebro-preview-test-format-compiler-splice ()
  "`-fmt=' goes after the engine and keeps every flag Org chose.
Rebuilding the command instead would silently drop whatever a later Org
adds to it; and the engine token is `%l' in some of Org's entries, so
the splice cannot assume the literal `latex'."
  (should (equal (cerebro-preview-format-compiler
                  "latex -interaction nonstopmode -output-directory %o %f" "F")
                 "latex -fmt=F -interaction nonstopmode -output-directory %o %f"))
  (should (equal (cerebro-preview-format-compiler "%l -foo %f" "F")
                 "%l -fmt=F -foo %f")))

(ert-deftest cerebro-preview-test-format-is-not-built-at-load-time ()
  "Loading the module must not run LaTeX.
Dumping the format takes about a second, and a second of frozen Emacs at
startup -- to speed up something this session may never do -- is the
wrong trade. Asked without BUILD and with nothing cached, the answer is
`no format' and *nothing is written*; the decision is left open
\(`cerebro-preview--format-checked' stays nil) so the first actual
preview can still make one."
  (let* ((dir (make-temp-file "cerebro-fmt-test" t))
         (cerebro-preview-format-directory dir)
         (cerebro-preview--format nil)
         (cerebro-preview--format-checked nil))
    (unwind-protect
        (progn
          (should-not (cerebro-preview-ensure-format))
          (should-not cerebro-preview--format-checked)
          (should-not (directory-files dir nil "\\.fmt\\'")))
      (delete-directory dir t))))

(ert-deftest cerebro-preview-test-a-cached-format-is-verified-not-trusted ()
  "A .fmt on disk with a matching stamp is still not used until it works.

The stamp records what this repository put *in*; it cannot notice that
the file was truncated, or that the TeX reading it is not the TeX that
wrote it. So the cached path probes too, and a format that fails the
probe is treated as absent -- erring towards `slow', never towards
`every preview in the buffer fails'. Here: a valid-looking stamp beside
a .fmt that is not a format at all."
  (let* ((dir (make-temp-file "cerebro-fmt-test" t))
         (cerebro-preview-format-directory dir)
         (cerebro-preview--format nil)
         (cerebro-preview--format-checked nil)
         (cerebro-preview-use-format t))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name
                           (concat cerebro-preview-format-name ".fmt") dir)
            (insert "this is not a TeX format file"))
          (with-temp-file (expand-file-name "stamp" dir)
            (insert (cerebro-preview-format-signature
                     cerebro-preview-preamble (cerebro-preview--format-inputs))
                    "\n"))
          ;; It must not come back as "cached": either the rebuild
          ;; succeeded (a real format, note "built now") or nothing is
          ;; used at all -- never the broken file that was there.
          (cerebro-preview-ensure-format t)
          (should-not (equal cerebro-preview--format-note "cached")))
      (delete-directory dir t))))

(ert-deftest cerebro-preview-test-format-is-prepared-from-org-itself ()
  "Every route to a rendered fragment goes through the build check.
Hanging it on `org-latex-preview' rather than on this module's own
commands is what covers Org's `C-c C-x C-l' and org-fragtog's
re-render-on-leaving, neither of which calls anything defined here."
  (should (advice-member-p #'cerebro-preview-prepare 'org-latex-preview)))

(provide 'cerebro-preview-tests)
