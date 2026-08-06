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
