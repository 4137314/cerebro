;;; cerebro-help-tests.el --- ERT tests for the help surface -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-help-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; Two of the three things this module shows are *derived* -- the key
;; reference from the keymap, the module map from the modules' own header
;; lines -- and that is the whole design: a hand-written reference goes
;; stale the first time something moves, silently, and documentation that
;; is quietly wrong is worse than documentation that is missing.
;;
;; So the tests are mostly about derivation: that the documents named
;; really exist in the checkout, that the module map parses real headers,
;; and that the settings list is generated rather than enumerated.

(require 'ert)
(require 'cerebro-help)

;; -- The written documents ----------------------------------------------

(ert-deftest cerebro-help-test-every-document-exists ()
  "A menu entry for a file that is not in the checkout is a dead end.
These are this repository's own documents, so their absence is a real
error rather than an environment difference."
  (dolist (row cerebro-help-documents)
    (should (characterp (nth 0 row)))
    (should (file-readable-p (cerebro-help--path (nth 1 row))))
    (should (> (length (nth 2 row)) 0))))

(ert-deftest cerebro-help-test-document-keys-are-unique ()
  "One key, one document."
  (let ((keys (mapcar #'car cerebro-help-documents)))
    (should (equal keys (delete-dups (copy-sequence keys))))))

(ert-deftest cerebro-help-test-openers-are-commands ()
  "The three documents worth a key of their own have one."
  (dolist (command '(cerebro-help-manual cerebro-help-conventions
                     cerebro-help-brief cerebro-help-document))
    (should (commandp command))))

(ert-deftest cerebro-help-test-unknown-document-is-refused ()
  "Asking for a file that is not here says so instead of visiting nothing."
  (should-error (cerebro-help-document "no/such/file.org") :type 'user-error))

;; -- The module map, read from the modules ------------------------------

(ert-deftest cerebro-help-test-module-map-covers-the-modules ()
  "Every cerebro-*.el is in the map, because the map is the directory."
  (let ((files (cerebro-help--module-files)))
    (should (> (length files) 20))
    (should (seq-find (lambda (f) (equal (file-name-nondirectory f) "cerebro-org.el"))
                      files))))

(ert-deftest cerebro-help-test-module-lines-carry-a-summary ()
  "Each line is `file -- what it is', taken from the file's header.

Every module here opens with the standard Elisp header
\(`;;; cerebro-x.el --- what it is'), so an empty summary means either a
module that broke the convention or a parser that stopped matching it.
Both are worth failing on."
  (dolist (file (cerebro-help--module-files))
    (let ((line (cerebro-help-module-line file)))
      (should (string-prefix-p (file-name-nondirectory file) line))
      ;; Something after the file name, and not the `-*- lexical-binding'
      ;; cookie leaking in from the same line.
      (should (> (length (string-trim (substring line 26))) 3))
      (should-not (string-match-p "lexical-binding" line)))))

;; -- The settings, generated ---------------------------------------------

(ert-deftest cerebro-help-test-settings-are-generated-not-listed ()
  "The settings list is `apropos'-built, so it finds what is loaded now.
A defcustom added later must appear without being registered anywhere."
  (let ((settings (cerebro-help-settings)))
    ;; This module's own dependencies are loaded, so at least these exist.
    (should (memq 'cerebro-cache-enabled settings))
    (should (seq-every-p (lambda (s) (string-prefix-p "cerebro-" (symbol-name s)))
                         settings))
    (should (equal settings (sort (copy-sequence settings) #'string<)))))

(ert-deftest cerebro-help-test-settings-exclude-generated-mode-hooks ()
  "`define-minor-mode' makes a `...-mode-hook' defcustom per mode.
They are customizable and they are not settings; a configuration browser
full of them is one you scroll past instead of read."
  (should-not (seq-find (lambda (s) (string-suffix-p "-hook" (symbol-name s)))
                        (cerebro-help-settings))))

(ert-deftest cerebro-help-test-setting-line-shows-name-value-and-doc ()
  "One line, three columns, and a long value truncated rather than wrapped."
  (let ((line (cerebro-help-setting-line 'cerebro-cache-enabled)))
    (should (string-prefix-p "cerebro-cache-enabled" line))
    (should (string-match-p "Whether" line))))

;; -- The key reference, read from the keymap ----------------------------

(ert-deftest cerebro-help-test-prefixes-are-described ()
  "Every prefix in the reference says what that family of keys is for."
  (dolist (cell cerebro-help-prefixes)
    (should (stringp (car cell)))
    (should (string-prefix-p "C-c " (car cell)))
    (should (> (length (cdr cell)) 3))))

(ert-deftest cerebro-help-test-key-rows-come-from-the-keymap ()
  "Bindings are discovered, never listed.

`cerebro-keys' is loaded here on purpose: with it, real bindings appear;
the point of the test is that the function reads them from the keymap
rather than from a table in this file, so a key that moved is reported
where it moved to."
  (require 'cerebro-keys)
  (let ((rows (cerebro-help-key-rows)))
    (should rows)
    (dolist (row rows)
      (should (= (length row) 3))
      (should (string-prefix-p (nth 0 row) (nth 1 row)))
      (should (symbolp (nth 2 row))))
    ;; One row per key: an alias must not produce two.
    (let ((keys (mapcar (lambda (r) (nth 1 r)) rows)))
      (should (equal keys (delete-dups (copy-sequence keys)))))))

(provide 'cerebro-help-tests)
