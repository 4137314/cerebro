;;; cerebro-latex-tests.el --- ERT tests for the parametric export pipeline -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-latex-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test'). Deliberately does not exercise an actual LaTeX
;; compile -- that is what `make ci''s profile-matrix export does, and
;; needs a real TeX install. These tests are for the orchestration
;; logic itself: profile/doctype composition, the block-stripping and
;; single-target parse-tree filters, and error handling -- all
;; reachable without Org-roam or Guix.

(require 'ert)
(require 'cerebro-latex)

(ert-deftest cerebro-latex-test-known-profiles-resolve ()
  (dolist (name '(full statements statements-only report manual lecture slides single))
    (should (cerebro-latex--profile name))))

(ert-deftest cerebro-latex-test-unknown-profile-errors ()
  (should-error (cerebro-latex--profile 'no-such-profile)))

(ert-deftest cerebro-latex-test-unknown-content-mode-errors ()
  (should-error (cerebro-latex--content-mode 'no-such-mode)))

(ert-deftest cerebro-latex-test-unknown-doctype-errors ()
  (should-error (cerebro-latex--doctype 'no-such-doctype)))

(ert-deftest cerebro-latex-test-class-options-composition ()
  (should (equal (cerebro-latex--class-options 'article t) "[proofs,article]"))
  (should (equal (cerebro-latex--class-options 'article nil) "[noproofs,article]"))
  (should (equal (cerebro-latex--class-options 'report t) "[proofs,report]"))
  (should (equal (cerebro-latex--class-options 'manual t) "[proofs,book]"))
  ;; beamer's :class-options is "" -- no trailing comma/empty component.
  (should (equal (cerebro-latex--class-options 'beamer t) "[proofs]"))
  (should (equal (cerebro-latex--class-options 'beamer nil) "[noproofs]")))

(ert-deftest cerebro-latex-test-statements-only-is-an-alias ()
  (should (equal (cerebro-latex--profile 'statements)
                 (cerebro-latex--profile 'statements-only))))

(defmacro cerebro-latex-test--with-parsed-org (text &rest body)
  "Parse TEXT as Org and run BODY with TREE bound to the parse tree."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (org-mode)
     (let ((tree (org-element-parse-buffer)))
       ,@body)))

(ert-deftest cerebro-latex-test-strip-blocks-removes-only-named-types ()
  (cerebro-latex-test--with-parsed-org
      "#+begin_definition\nkeep\n#+end_definition\n\n#+begin_proof\ndrop\n#+end_proof\n"
    (let ((cerebro-latex--exclude-blocks '("proof")))
      (cerebro-latex--strip-blocks tree nil nil))
    (let ((types (org-element-map tree 'special-block
                   (lambda (b) (org-element-property :type b)))))
      (should (member "definition" types))
      (should-not (member "proof" types)))))

(ert-deftest cerebro-latex-test-strip-blocks-noop-when-nil ()
  (cerebro-latex-test--with-parsed-org
      "#+begin_proof\nkeep\n#+end_proof\n"
    (let ((cerebro-latex--exclude-blocks nil))
      (cerebro-latex--strip-blocks tree nil nil))
    (should (org-element-map tree 'special-block
              (lambda (b) (equal (org-element-property :type b) "proof"))))))

(ert-deftest cerebro-latex-test-extract-single-keeps-target-and-adjacent-proof ()
  (cerebro-latex-test--with-parsed-org
      (concat "#+begin_definition\ndrop me\n#+end_definition\n\n"
              "#+NAME: my-thm\n#+begin_theorem\nkeep\n#+end_theorem\n\n"
              "#+begin_proof\nkeep too\n#+end_proof\n\n"
              "#+begin_remark\ndrop me too\n#+end_remark\n")
    (let ((cerebro-latex--single-target "my-thm"))
      (cerebro-latex--extract-single tree nil nil))
    (let ((types (org-element-map tree 'special-block
                   (lambda (b) (org-element-property :type b)))))
      (should (equal (sort (copy-sequence types) #'string<) '("proof" "theorem"))))))

(ert-deftest cerebro-latex-test-extract-single-errors-on-missing-target ()
  (cerebro-latex-test--with-parsed-org
      "#+begin_theorem\nno name here\n#+end_theorem\n"
    (let ((cerebro-latex--single-target "does-not-exist"))
      (should-error (cerebro-latex--extract-single tree nil nil)))))

(ert-deftest cerebro-latex-test-export-requires-target-for-single ()
  (should-error
   (cerebro-latex-export-to-pdf "/nonexistent/does-not-matter.org" 'single nil)))

(provide 'cerebro-latex-tests)
