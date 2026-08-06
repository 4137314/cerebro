;;; cerebro-pdf-tests.el --- ERT tests for the in-Emacs PDF view -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-pdf-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; Nothing here opens a PDF -- batch has no display and no viewer. What is
;; worth pinning down is the reasoning around it:
;;
;;   - the PDF path must be exactly where the exporter puts it, or the
;;     module shows a stale file (or none) while `make export' happily
;;     writes another one somewhere else;
;;   - the viewer choice must degrade: pdf-tools needs a helper *binary*,
;;     and a half-built profile has the Elisp without it -- which must
;;     mean "use doc-view", not "error on the first page";
;;   - the compile must go through the same batch entry point as `make
;;     export', with the file name quoted (a note called `Gödel's
;;     theorem.org' is legal here).

(require 'ert)
(require 'cerebro-pdf)

;; -- Where the PDF is ---------------------------------------------------

(ert-deftest cerebro-pdf-test-file-for-note ()
  "The PDF sits next to the note, same name -- where Org writes it."
  (should (equal (cerebro-pdf-file-for "/repo/notes/math/limits.org")
                 "/repo/notes/math/limits.pdf"))
  ;; A name with dots keeps everything but the extension.
  (should (equal (cerebro-pdf-file-for "/repo/notes/math/l1.p.org")
                 "/repo/notes/math/l1.p.pdf")))

(ert-deftest cerebro-pdf-test-staleness ()
  "Missing or older than the note = stale; newer = current."
  (let* ((note (make-temp-file "cerebro-note-" nil ".org"))
         (pdf (concat (file-name-sans-extension note) ".pdf")))
    (unwind-protect
        (progn
          (should (cerebro-pdf-stale-p note pdf))     ; not compiled yet
          (with-temp-file pdf (insert "%PDF"))
          ;; Written after the note, so it is up to date...
          (should-not (cerebro-pdf-stale-p note pdf))
          ;; ...until the note is touched again.
          (set-file-times note (time-add (current-time) 10))
          (should (cerebro-pdf-stale-p note pdf)))
      (delete-file note)
      (when (file-exists-p pdf) (delete-file pdf)))))

;; -- Which viewer -------------------------------------------------------

(ert-deftest cerebro-pdf-test-viewer-preference ()
  "pdf-tools when it can really render, doc-view otherwise, nil if neither."
  (should (eq (cerebro-pdf-pick-viewer t t t) 'pdf-tools))
  ;; The half-built case: package present, helper binary absent.
  (should (eq (cerebro-pdf-pick-viewer t nil t) 'doc-view))
  (should (eq (cerebro-pdf-pick-viewer nil nil t) 'doc-view))
  ;; Nothing to render with: the commands say so instead of failing later.
  (should-not (cerebro-pdf-pick-viewer nil nil nil))
  (should-not (cerebro-pdf-pick-viewer t nil nil)))

;; -- The compile --------------------------------------------------------

(ert-deftest cerebro-pdf-test-command-uses-the-shared-entry-point ()
  "The compile is the same one `make export' runs, not a second recipe."
  (let ((command (cerebro-pdf--command "/repo/notes/math/limits.org" "full")))
    (should (string-match-p "bin/org-export-latex\\.el" command))
    (should (string-match-p "--profile=full" command))
    (should (string-match-p "limits\\.org" command))
    ;; No target unless one was asked for: passing an empty --target= to
    ;; a non-`single' profile would be a silent argument error.
    (should-not (string-match-p "--target" command))))

(ert-deftest cerebro-pdf-test-command-quotes-its-arguments ()
  "A note whose name has a space or a quote still compiles.
Asserted by parsing the command back the way a shell would, rather than
by matching a quoting style -- `shell-quote-argument' is free to escape
however it likes, as long as the argument survives the round trip."
  (let* ((note "/repo/notes/math/Gödel's theorem.org")
         (words (split-string-shell-command (cerebro-pdf--command note "full"))))
    (should (equal (car (last words)) note))))

(ert-deftest cerebro-pdf-test-command-passes-the-single-target ()
  "The `single' profile gets the result name it requires."
  (let ((command (cerebro-pdf--command "/repo/notes/math/limits.org" "single"
                                       "thm-uniqueness-of-limits")))
    (should (string-match-p "--profile=single" command))
    (should (string-match-p "--target=thm-uniqueness-of-limits" command))))

;; -- Finding the result at point ---------------------------------------

(ert-deftest cerebro-pdf-test-name-at-point ()
  "The `#+NAME:' above point is what `single' compiles."
  (with-temp-buffer
    (insert "#+TITLE: t\n\n"
            "#+NAME: thm-uniqueness-of-limits\n"
            "#+begin_theorem\n"
            "A convergent sequence has one limit.\n"
            "#+end_theorem\n")
    (goto-char (point-max))
    (should (equal (cerebro-pdf-name-at-point) "thm-uniqueness-of-limits")))
  ;; Nothing named above point: the command must ask for a name rather
  ;; than compile the wrong result.
  (with-temp-buffer
    (insert "#+TITLE: t\n\nplain prose\n")
    (goto-char (point-max))
    (should-not (cerebro-pdf-name-at-point))))

(provide 'cerebro-pdf-tests)
