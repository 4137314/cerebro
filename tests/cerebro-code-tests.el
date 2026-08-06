;;; cerebro-code-tests.el --- ERT tests for the editing surface -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-code-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; What is worth testing in an "editor features" module is the parts that
;; are *not* somebody else's package: the parser that turns this repo's
;; note linter into flymake diagnostics (a wrong regexp there means
;; either no diagnostics at all or an underline on the wrong line, both
;; silent), the breadcrumb assembly, and the tree-sitter grammar path --
;; which is a Guix-specific detail no upstream default gets right.

(require 'ert)
(require 'cerebro-code)

;; -- The note linter as diagnostics -------------------------------------

(ert-deftest cerebro-code-test-lint-parses-located-messages ()
  "A linter line with a file and a message becomes one diagnostic."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (let ((diagnostics
           (cerebro-code-parse-lint
            (concat "notes-lint: error: /repo/notes/math/x.org: naked `$' in math\n"
                    "notes-lint: info: /repo/notes/math/x.org: definition block has no #+NAME\n")
            (current-buffer))))
      (should (= (length diagnostics) 2))
      (should (eq (flymake-diagnostic-type (car diagnostics)) :error))
      (should (eq (flymake-diagnostic-type (cadr diagnostics)) :note))
      (should (string-match-p "naked" (flymake-diagnostic-text (car diagnostics)))))))

(ert-deftest cerebro-code-test-lint-ignores-summaries ()
  "Lines that are not about a file produce nothing to underline.
`notes-lint: ok' and the \"skipping tier-2 checks\" notices are status,
not defects -- turning them into diagnostics would put a permanent
warning on line 1 of every note."
  (with-temp-buffer
    (insert "one\n")
    (should-not (cerebro-code-parse-lint
                 (concat "notes-lint: ok\n"
                         "notes-lint: org-roam unavailable, skipping tier-2 graph checks\n")
                 (current-buffer)))))

(ert-deftest cerebro-code-test-lint-command-uses-the-repos-linter ()
  "Diagnostics come from bin/notes-lint.el -- the same linter the git
hook runs, so what you see while typing is what will block the push."
  (let ((command (cerebro-code--lint-command "/repo/notes/math/x.org")))
    (should (member "--batch" command))
    (should (seq-some (lambda (argument) (string-suffix-p "bin/notes-lint.el" argument))
                      command))
    (should (member "/repo/notes/math/x.org" command))))

;; -- Breadcrumbs --------------------------------------------------------

(ert-deftest cerebro-code-test-breadcrumb-joins-and-skips-empties ()
  "Only the components that exist appear, with one separator between."
  (let ((cerebro-code-breadcrumb-separator " > "))
    (should (equal (cerebro-code-breadcrumb-string '("Chapter" "Section")) "Chapter > Section"))
    (should (equal (cerebro-code-breadcrumb-string '("Chapter" nil "" "Leaf"))
                   "Chapter > Leaf"))
    (should (equal (cerebro-code-breadcrumb-string nil) ""))))

(ert-deftest cerebro-code-test-breadcrumb-in-an-org-note ()
  "In a note the crumb is the outline path of the heading point is under."
  (with-temp-buffer
    (org-mode)
    (insert "* Continuity\n** At a point\ntext here\n")
    (goto-char (point-max))
    (let ((crumb (cerebro-code-breadcrumb)))
      (should (string-match-p "Continuity" crumb))
      (should (string-match-p "At a point" crumb)))))

(ert-deftest cerebro-code-test-breadcrumb-mode-is-reversible ()
  "Turning it off leaves no header line behind."
  (with-temp-buffer
    (org-mode)
    (cerebro-code-breadcrumb-mode 1)
    (should header-line-format)
    (cerebro-code-breadcrumb-mode -1)
    (should-not header-line-format)))

;; -- Tree-sitter --------------------------------------------------------

(ert-deftest cerebro-code-test-treesit-path-is-the-guix-one ()
  "Grammars are looked for where Guix puts them, not in ~/.emacs.d.
A profile installs lib/tree-sitter/libtree-sitter-<lang>.so; Emacs'
default search path would never find it."
  (should (equal (cerebro-code-treesit-grammar-directories "/gnu/store/xyz-profile")
                 '("/gnu/store/xyz-profile/lib/tree-sitter")))
  ;; Outside the environment there is nothing to find, and saying so is
  ;; better than adding a path that does not exist. The variable is
  ;; unset explicitly rather than assumed absent: `make test' runs
  ;; *inside* the profile, where it is very much set.
  (let ((process-environment (copy-sequence process-environment)))
    (setenv "GUIX_ENVIRONMENT" nil)
    (should-not (cerebro-code-treesit-grammar-directories))))

(ert-deftest cerebro-code-test-treesit-modes-are-honest ()
  "Only languages with a real grammar are remapped.
Neither Org nor Emacs Lisp has an upstream tree-sitter grammar, so
neither may appear here -- claiming otherwise would remap a mode to one
that cannot start."
  (dolist (cell cerebro-code-treesit-modes)
    (should-not (memq (car cell) '(org-mode emacs-lisp-mode lisp-data-mode)))
    (should (string-suffix-p "-ts-mode" (symbol-name (cdr cell))))))

(provide 'cerebro-code-tests)
