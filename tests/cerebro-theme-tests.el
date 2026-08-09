;;; cerebro-theme-tests.el --- ERT tests for the look -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-theme-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; A theme is mostly taste, and taste is not testable. What *is* testable
;; -- and what breaks silently on a machine you did not configure it on --
;; is the reasoning underneath: does the font fall back correctly when the
;; preferred family is absent, does the heading scale stay a scale, does
;; toggling twice return where it started. Those are the three ways this
;; module can be wrong without anyone noticing until the day the config
;; is cloned somewhere new.
;;
;; Everything here runs in batch, where there is no window system and
;; `font-family-list' is empty -- which is exactly the degenerate case the
;; font selection has to survive.

(require 'ert)
(require 'cerebro-theme)

;; -- Font selection -----------------------------------------------------

(ert-deftest cerebro-theme-test-pick-font-prefers-earlier-candidate ()
  "The first *installed* candidate wins, not the first candidate.
This is the whole point of a preference list: a machine with both fonts
gets the better one, a machine with only the second still gets a font."
  (should (equal (cerebro-theme-pick-font '("Iosevka" "Fira Code" "Monospace")
                                          '("Fira Code" "Monospace"))
                 "Fira Code"))
  (should (equal (cerebro-theme-pick-font '("Iosevka" "Fira Code" "Monospace")
                                          '("Iosevka" "Fira Code"))
                 "Iosevka")))

(ert-deftest cerebro-theme-test-pick-font-nil-when-nothing-matches ()
  "No candidate installed returns nil, never a guess.
The callers treat nil as \"leave the face alone\"; returning the first
candidate anyway would ask Emacs for a font that does not exist and give
a fallback glyph box instead of the default face."
  (should-not (cerebro-theme-pick-font '("Iosevka" "Fira Code") '("DejaVu Sans")))
  (should-not (cerebro-theme-pick-font '("Iosevka") nil)))

(ert-deftest cerebro-theme-test-font-roles-are-defined ()
  "Every role the config asks for exists and ends in a generic family.
The last entry of each list is the safety net -- a family fontconfig
always resolves -- so a machine with none of the named fonts still gets a
sensible one. A role whose list ended in a brand name would be a config
that silently does nothing on a fresh install."
  (dolist (role '(mono variable serif))
    (let ((candidates (cdr (assq role cerebro-theme-font-families))))
      (should candidates)
      (should (member (car (last candidates))
                      '("Monospace" "Sans Serif" "Serif"))))))

(ert-deftest cerebro-theme-test-font-tolerates-no-window-system ()
  "In batch (no fonts at all) every role resolves to nil without erroring.
Batch is not a corner case here: `cerebro env', the linter and the
exporter all load this module with no display."
  (dolist (role '(mono variable serif))
    (should-not (cerebro-theme-font role nil))))

;; -- Headings -----------------------------------------------------------

(ert-deftest cerebro-theme-test-heading-scale-is-decreasing ()
  "Deeper headings are never larger than shallower ones.
The scale is the only thing making the outline readable as a hierarchy;
an inverted pair would look like a mistake in the note, not in the
config."
  (let ((heights (mapcar #'cdr cerebro-theme-heading-scale)))
    (should (equal heights (reverse (sort (copy-sequence heights) #'<))))
    ;; And every one of them is an enlargement, not a shrink.
    (should (seq-every-p (lambda (h) (>= h 1.0)) heights))))

(ert-deftest cerebro-theme-test-heading-spec-shape ()
  "The spec handed to modus has one entry per level plus a `t' default.
`t' is what covers levels 5-8; without it Org's deeper headings inherit
whatever the theme happens to do, which is the one case nobody looks at."
  (let ((spec (cerebro-theme-heading-spec nil)))
    (should (assq t spec))
    (dolist (level (mapcar #'car cerebro-theme-heading-scale))
      (should (assq level spec)))))

(ert-deftest cerebro-theme-test-heading-spec-only-asks-for-variable-pitch-when-available ()
  "`variable-pitch' is requested only when a proportional font was found.
Asking for it with none installed renders headings in the default family
at the wrong weight -- worse than leaving them alone."
  (should-not (memq 'variable-pitch (cdr (assq 1 (cerebro-theme-heading-spec nil)))))
  (should (memq 'variable-pitch (cdr (assq 1 (cerebro-theme-heading-spec "Cantarell"))))))

;; -- Variants -----------------------------------------------------------

(ert-deftest cerebro-theme-test-built-in-variants-are-real-themes ()
  "The built-in pair names themes this Emacs always has.
modus has shipped since Emacs 28, which is why the config can promise a
working look with no package installed at all -- a typo here would break
that promise at startup, in the dark. The pastel pair comes from a
package, so it is only checked when that package is loaded (below):
asserting it unconditionally would make this test pass or fail depending
on which environment ran it, rather than on the config."
  (dolist (variant '(dark light))
    (should (memq (cdr (assq variant cerebro-theme-variants))
                  (custom-available-themes)))))

(ert-deftest cerebro-theme-test-hermetic-pair-is-declared-and-paired ()
  "The hermetic look is a pair, like every other, and it is the default.
`C-c u t' has to move between a dark and a light version of the look you
chose -- a variant with no partner would toggle you into a different
look entirely."
  (should (assq 'hermes cerebro-theme-variants))
  (should (assq 'hermes-light cerebro-theme-variants))
  (should (eq (cerebro-theme-other-variant 'hermes) 'hermes-light))
  (should (eq (cerebro-theme-other-variant 'hermes-light) 'hermes))
  ;; The *declared* default, evaluated: `standard-value' holds the
  ;; defcustom's init form, not its value. Asking `cerebro-theme-variant'
  ;; instead would test the environment rather than the config --
  ;; `cerebro-theme-apply' has already rewritten it to whatever actually
  ;; loaded here, which is `dark' wherever ef-themes is absent.
  (should (eq (eval (car (get 'cerebro-theme-variant 'standard-value)) t)
              'hermes)))

(ert-deftest cerebro-theme-test-both-theme-families-are-configured ()
  "Typography is applied to whichever family the active variant is from.

Every option in `cerebro-theme--configure-modus' is named
`modus-themes-...', so under `hermes' or `pastel' -- which are
ef-themes -- it did nothing at all: four of the six variants had no
heading scale and, worse, no `mixed-fonts', which is what keeps Org
tables and aligned mathematics monospaced under a proportional heading
font. Both configure functions now run on every apply."
  (should (fboundp 'cerebro-theme--configure-modus))
  (should (fboundp 'cerebro-theme--configure-ef))
  (cerebro-theme--configure-ef)
  (should (bound-and-true-p ef-themes-mixed-fonts))
  (should (bound-and-true-p ef-themes-headings))
  ;; Same shape as the modus one: it is one decision, expressed twice
  ;; only because two packages name it differently.
  (should (equal (bound-and-true-p ef-themes-headings)
                 (cerebro-theme-heading-spec (cerebro-theme-font 'variable)))))

(ert-deftest cerebro-theme-test-no-deferred-drawing ()
  "No redisplay setting whose mechanism is \"draw now, correct later\".

Regression test, for a problem this configuration caused itself. These
three were added to make scrolling cheaper, and all three do the same
thing: they let redisplay paint text before it is fontified and repaint
it a moment later. On a keypress that is invisible; under a trackpad,
where input is pending for the whole gesture, it is a continuous stream
of repaints -- text appearing unstyled and then recolouring, tens of
times a second. That is what `flickering while scrolling' *is*.

They also bought nothing: the measured cost of scrolling a note was the
point-following modes (cerebro-study.el), and these were measured after
that fix and moved nothing. Smooth means every frame is right, not that
frames are cheap -- so they stay at Emacs' own defaults."
  (should-not jit-lock-defer-time)
  (should-not redisplay-skip-fontification-on-input)
  (should-not fast-but-imprecise-scrolling)
  ;; ...while the mode that actually makes scrolling smooth stays on.
  (should (bound-and-true-p pixel-scroll-precision-mode)))

(ert-deftest cerebro-theme-test-no-scroll-margin ()
  "`scroll-margin' is 0, and that is a fix rather than a preference.

Regression test. A margin asks redisplay to keep point some lines from
the window edge; under `pixel-scroll-precision-mode' a gesture moves the
window by sub-line amounts, and whenever that brings point inside the
margin redisplay corrects it by pulling the window *back* -- so scrolling
steadily downwards jumps upwards every so often. Measured in a graphical
frame over 240 sub-line steps: margin 3 gave 6 backwards jumps, margin 0
gave none, and `scroll-conservatively', `scroll-preserve-screen-position',
`global-hl-line-mode' and `line-spacing' each left it at 6."
  (should (= scroll-margin 0))
  ;; ...and the setting that prevents the *big* jump stays on: without it
  ;; redisplay recentres, which is a worse version of the same problem.
  (should (> scroll-conservatively 100)))

(ert-deftest cerebro-theme-test-scroll-trace-is-reversible ()
  "The scroll tracer must add exactly one hook and take it away again.
It is a diagnostic left switched off; one that leaked a
`post-command-hook' would itself slow down the thing it measures."
  (cerebro-scroll-trace-mode 1)
  (should (memq #'cerebro-scroll--watch (default-value 'post-command-hook)))
  (cerebro-scroll-trace-mode -1)
  (should-not (memq #'cerebro-scroll--watch (default-value 'post-command-hook))))

(ert-deftest cerebro-theme-test-cursor-has-width ()
  "The cursor must be wide enough to find.

Regression test. It was plain `bar' -- *one pixel* -- with blinking off
and `global-hl-line-mode' putting a background under the line it sits
on. Three settings that are each defensible and together produce a
cursor you cannot see; reported as exactly that. One pixel was never a
chosen number, it is the default of `bar'."
  (let ((type cerebro-theme-cursor-type))
    (should (or (eq type 'box)
                (and (consp type) (integerp (cdr type)) (>= (cdr type) 2))))))

(ert-deftest cerebro-theme-test-cursor-is-reapplied-on-every-theme ()
  "`cursor' is a face, so every `load-theme' replaces it.

Setting the colour once at startup would put it back to the theme's own
accent at the first `C-c u t' -- the bug returning, silently, on a
keystroke whose whole purpose is to change the palette."
  (should (memq #'cerebro-theme--apply-cursor cerebro-theme-after-apply-hook))
  ;; And applying a theme really does leave the shape in place.
  (cerebro-theme-apply)
  (should (equal (default-value 'cursor-type) cerebro-theme-cursor-type)))

(ert-deftest cerebro-theme-test-cursor-colour-is-derived-not-fixed ()
  "Visibility must not depend on which theme is loaded.
The body-text colour is readable on the background by definition, and on
the current-line highlight because themes are built that way -- so the
cursor is visible by construction, in variants added later too."
  (should cerebro-theme-cursor-follows-text)
  ;; No hex literal anywhere in the cursor code: that would be a colour
  ;; picked for one variant and wrong in the others.
  (should-not (string-match-p
               "#[0-9a-fA-F]\\{6\\}"
               (with-temp-buffer
                 (insert-file-contents
                  (expand-file-name ".emacs.d/lisp/cerebro-theme.el" cerebro-root))
                 (buffer-substring
                  (progn (goto-char (point-min))
                         (search-forward "defun cerebro-theme--apply-cursor")
                         (point))
                  (progn (search-forward "(blink-cursor-mode -1)") (point)))))))

(ert-deftest cerebro-theme-test-package-variants-load-when-present ()
  "When ef-themes is here, the pastel variants name real themes of it."
  (when (featurep 'ef-themes)
    (dolist (variant '(pastel pastel-light))
      (should (memq (cdr (assq variant cerebro-theme-variants))
                    (custom-available-themes))))))

(ert-deftest cerebro-theme-test-falls-back-when-a-theme-is-absent ()
  "Asking for a variant whose package is missing still leaves a theme on.
Refusing to start because a *colour scheme* is unavailable would be the
silliest possible way to lose an editor."
  (let ((cerebro-theme-variants '((dark . modus-vivendi)
                                  (nosuch . cerebro-no-such-theme))))
    (cerebro-theme-apply 'nosuch)
    (should (eq cerebro-theme-variant 'dark))
    (should custom-enabled-themes)))

(ert-deftest cerebro-theme-test-toggle-is-an-involution ()
  "Switching twice comes back to where it started."
  (dolist (variant '(dark light))
    (should (eq (cerebro-theme-other-variant (cerebro-theme-other-variant variant))
                variant))))

(ert-deftest cerebro-theme-test-palette-overrides-are-pairs ()
  "Each override is a (KEY VALUE) list, as modus expects.
A stray cons cell here is accepted silently by `setq' and then ignored by
the theme, so the intended tweak just never happens."
  (dolist (entry cerebro-theme-palette-overrides)
    (should (listp entry))
    (should (= (length entry) 2))
    (should (symbolp (car entry)))))

(provide 'cerebro-theme-tests)
