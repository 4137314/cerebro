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

(ert-deftest cerebro-preview-test-scale-follows-the-body-size ()
  "Bigger text, bigger formulas -- proportionally, and always > 1."
  (should (> (cerebro-preview-scale 240) (cerebro-preview-scale 120)))
  (should (= (cerebro-preview-scale 240) (* 2 (cerebro-preview-scale 120))))
  (should (> (cerebro-preview-scale 100) 1.0)))

;; -- What Org ends up configured with -----------------------------------

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

(provide 'cerebro-preview-tests)
