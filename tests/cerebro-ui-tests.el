;;; cerebro-ui-tests.el --- ERT tests for the window discipline -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-ui-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; cerebro-ui.el is mostly `setq' against packages that may not be here,
;; so what is testable is the one decision it makes on its own: which
;; buffers open in the bottom side window instead of splitting whatever
;; you were reading. That was hand-written as a regexp alternation and
;; had drifted out of step with the buffers cerebro actually creates.

(require 'ert)
(require 'cerebro-ui)
(require 'cerebro-base)

(defun cerebro-ui-tests--side-window-regexp ()
  "The regexp cerebro-ui.el installed in `display-buffer-alist'."
  (concat "\\`" (regexp-opt cerebro-ui-side-window-buffers) "\\'"))

(ert-deftest cerebro-ui-test-every-report-buffer-gets-the-side-window ()
  "The reports cerebro pops up all land in one predictable place.

The rule's own comment said it covered \"everything cerebro pops up\"
and the alternation left out *cerebro-results* -- which is `C-c r o',
the results index and both dependency views, i.e. the reports actually
read most often. They split whichever window was in front, which is the
single behaviour this rule exists to prevent."
  (let ((regexp (cerebro-ui-tests--side-window-regexp)))
    (dolist (buffer '("*cerebro*" "*cerebro-results*" "*cerebro-cli*"
                      "*cerebro-guix*" "*cerebro-export*" "*Help*"))
      (should (string-match-p regexp buffer)))))

(ert-deftest cerebro-ui-test-the-places-you-work-keep-the-frame ()
  "A side window is for glancing at, so the start page is not one.
Nor is the agenda, which manages its own windows."
  (let ((regexp (cerebro-ui-tests--side-window-regexp)))
    (should-not (string-match-p regexp "*cerebro-dashboard*"))
    (should-not (string-match-p regexp "*Org Agenda*"))
    ;; Anchored at both ends: a note called `*cerebro*.org' or a buffer
    ;; merely containing the name must not be captured.
    (should-not (string-match-p regexp "my *cerebro* notes"))))

(ert-deftest cerebro-ui-test-the-rule-is-actually-installed ()
  "The entry is in `display-buffer-alist', not merely defined."
  (should (seq-find (lambda (entry)
                      (and (stringp (car entry))
                           (string-match-p (car entry) "*cerebro-results*")
                           (assq 'side (cdr entry))))
                    display-buffer-alist)))

(ert-deftest cerebro-ui-test-report-buffers-are-declared ()
  "Every buffer name `cerebro-report' is called with is in the list.

The list is the fix for a hand-kept alternation, so it has to be kept
by something other than hand: this reads the actual call sites out of
the sources and fails when a new report is added without a window rule."
  (let ((declared cerebro-ui-side-window-buffers)
        (used nil))
    (dolist (file (directory-files (expand-file-name ".emacs.d/lisp" cerebro-root)
                                   t "\\.el\\'"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        ;; The last argument of `cerebro-report' is the buffer name.
        (while (re-search-forward "\"\\(\\*cerebro[a-z-]*\\*\\)\"" nil t)
          (cl-pushnew (match-string 1) used :test #'equal))))
    (dolist (buffer used)
      ;; Two deliberate absences (see `cerebro-ui-side-window-buffers'):
      ;; the dashboard is a place you work, and the PDF viewer displays
      ;; itself on the right -- listing it here would override that,
      ;; because `display-buffer-alist' beats the ACTION argument.
      (unless (member buffer '("*cerebro-dashboard*" "*cerebro-pdf*"))
        (should (member buffer declared))))))

(ert-deftest cerebro-ui-test-the-pdf-keeps-its-own-window ()
  "The PDF viewer is not captured by the bottom rule.

cerebro-pdf.el asks for a side window on the RIGHT, beside the note it
compiled. `display-buffer-alist' has precedence over the ACTION passed
to `display-buffer', so putting *cerebro-pdf* in the list above would
silently move the PDF to a third of the frame at the bottom -- an entry
that reads like an addition and behaves like an override."
  (should-not (string-match-p (cerebro-ui-tests--side-window-regexp) "*cerebro-pdf*")))

(provide 'cerebro-ui-tests)
