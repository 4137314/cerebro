;;; cerebro-cli-tests.el --- ERT tests for the Emacs -> CLI bridge -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-cli-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; cerebro-cli.el is deliberately almost all I/O -- its whole point is
;; that a keybinding and a shell line reach the SAME implementation, so
;; it adds no logic of its own to go wrong. Two things can still go
;; wrong quietly, and they are what is checked here:
;;
;;   1. the one piece of parsing it does have (pulling an ID out of a
;;      line of `cerebro issue list'), now a pure function so it can be
;;      tested without a CLI, a database or a minibuffer;
;;   2. the claim itself. Every wrapper names a subcommand as a literal
;;      string, and nothing connected those strings to what bin/cerebro
;;      actually implements: rename a subcommand in the dispatcher and
;;      the Emacs side keeps calling the old name, failing only when
;;      someone presses the key. That is exactly the drift the module
;;      exists to prevent, so it is worth a test rather than a comment.

(require 'ert)
(require 'cerebro-cli)

;; -- Pulling an ID out of a listing line --------------------------------

(ert-deftest cerebro-cli-test-issue-id-timestamp-shape ()
  "The Org timestamp id, wherever it sits in the line."
  (should (equal (cerebro-cli-issue-id "TODO [#A] fix the exporter  20260807T120000")
                 "20260807T120000"))
  (should (equal (cerebro-cli-issue-id "20260807T120000  DONE something")
                 "20260807T120000")))

(ert-deftest cerebro-cli-test-issue-id-uuid-shape ()
  "The uuid shape, which the tracker also has in it."
  (should (equal (cerebro-cli-issue-id
                  "DOING  4d0d08b6-52bf-48b5-90c3-8b075bae3dcf  rewrite the linter")
                 "4d0d08b6-52bf-48b5-90c3-8b075bae3dcf")))

(ert-deftest cerebro-cli-test-issue-id-absent ()
  "No id is nil, not a match on something that merely looks like one.
The caller turns nil into a `user-error'; a wrong match would send the
CLI an id that does not exist, which fails much further from the cause."
  (should-not (cerebro-cli-issue-id "TODO  no identifier here at all"))
  (should-not (cerebro-cli-issue-id ""))
  (should-not (cerebro-cli-issue-id nil))
  ;; A date is not an id: eight digits, but no `T' and no time.
  (should-not (cerebro-cli-issue-id "closed on 20260807")))

;; -- The bridge really reaches the dispatcher ---------------------------

(ert-deftest cerebro-cli-test-program-is-executable ()
  "Every command in this module shells out to this one file."
  (should (file-exists-p cerebro-cli-program))
  (should (file-executable-p cerebro-cli-program)))

(ert-deftest cerebro-cli-test-subcommands-exist-in-the-dispatcher ()
  "Every subcommand the Emacs wrappers name is one bin/cerebro documents.

`cerebro help' is the dispatcher's own list of what it implements, so
asking it is asking the implementation rather than a second list kept
here. This is the anti-drift check the module's premise needs: renaming
a subcommand in bin/cerebro now fails a test instead of failing a
keystroke."
  (let ((help (with-temp-buffer
                (call-process cerebro-cli-program nil t nil "help")
                (buffer-string))))
    (should (> (length help) 0))
    (dolist (subcommand '("issue list" "issue report" "issue next" "issue scan"
                          "issue note" "issue new" "issue close" "issue start"
                          "issue reopen" "note new" "note find"
                          "today" "stats" "lint" "time" "task"))
      (should (string-match-p (regexp-quote subcommand) help)))))

(provide 'cerebro-cli-tests)
