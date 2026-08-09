;;; cerebro-appearance-tests.el --- what the buffer is allowed to redraw -*- lexical-binding: t; -*-

;; cerebro-appearance.el is settings, not logic, so there is little here
;; that could be unit-tested and one thing that must be: whether Org is
;; permitted to substitute glyphs for the source of a note.
;;
;; `org-pretty-entities' is a one-symbol switch with a large consequence
;; -- turned on it draws `\in' and `\pi' as characters and `x_{1}' with a
;; raised baseline, while leaving `\eps', `\abs{x}' and every other
;; cerebro-macros.sty command as plain text beside them. The decision to
;; keep it off is argued in the module; this test is what stops it from
;; being flipped back by a stray `setq' in some later "make Org prettier"
;; commit, which is exactly how a display setting gets re-enabled without
;; anyone deciding to.

(require 'ert)
(require 'cerebro-appearance)

(ert-deftest cerebro-appearance-test-entities-are-not-redrawn ()
  "Mathematics stays the linear text the file contains."
  (should-not org-pretty-entities)
  (should-not org-pretty-entities-include-sub-superscripts))

(ert-deftest cerebro-appearance-test-org-appear-agrees-about-subscripts ()
  "org-appear must not offer to un-hide what nothing hid.
`org-appear-autosubmarkers' only has work to do when
`org-pretty-entities-include-sub-superscripts' is on; leaving it t while
that is nil is a setting that reads as a decision and is not one."
  (when (boundp 'org-appear-autosubmarkers)
    (should (eq (and org-pretty-entities-include-sub-superscripts t)
                (and org-appear-autosubmarkers t)))))

(ert-deftest cerebro-appearance-test-notes-soft-wrap ()
  "A display equation lives on one physical line, so Org buffers wrap.
Without this the only way to read a long derivation is to scroll
sideways (see the note conventions in notes/README.org)."
  (should (memq #'visual-line-mode org-mode-hook)))

(provide 'cerebro-appearance-tests)
