;;; cerebro-org-tests.el --- ERT tests for note-file discovery -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-org-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test'). cerebro-org.el sits on Emacs core only (org,
;; org-agenda, org-id, org-refile, ispell) plus the pure cerebro-taxonomy,
;; so it loads in batch without Org-roam or Guix -- and the two note-file
;; discovery helpers it exposes (`cerebro-note-directories',
;; `cerebro-note-files') are what make the agenda, the morning review,
;; org-drill, and org-ql all scan the *same, whole* notes tree. That
;; recursion is the fix these tests pin down: a plain org-agenda-files
;; directory entry does NOT recurse, so a regression here would silently
;; hide every nested note from the agenda again.

(require 'ert)
(require 'cl-lib)
(require 'cerebro-org)

(defmacro cerebro-org-tests--with-notes (&rest body)
  "Run BODY with `dir' bound to a throwaway notes tree:
  <dir>/top.org
  <dir>/README.org                  (meta, excluded from note *files*)
  <dir>/conjectures/c.org           (nested real note)
  <dir>/conjectures/README.org      (meta, excluded)
  <dir>/courses/.build/x-handbook.org (composed for an export, excluded)
The directory is deleted afterward."
  (declare (indent 0) (debug t))
  `(let ((dir (make-temp-file "cerebro-notes-" t)))
     (unwind-protect
         (progn
           (make-directory (expand-file-name "conjectures" dir) t)
           (make-directory (expand-file-name "courses/.build" dir) t)
           (dolist (rel '("top.org" "README.org"
                          "conjectures/c.org" "conjectures/README.org"
                          "courses/.build/x-handbook.org"))
             (with-temp-file (expand-file-name rel dir) (insert "* x\n")))
           ,@body)
       (delete-directory dir t))))

(ert-deftest cerebro-org-test-note-directories-recurse ()
  "`cerebro-note-directories' returns the root and every subdirectory --
this is what lets org-agenda-files reach nested notes."
  (cerebro-org-tests--with-notes
    (let ((dirs (mapcar #'file-name-as-directory (cerebro-note-directories dir))))
      (should (member (file-name-as-directory dir) dirs))
      (should (member (file-name-as-directory (expand-file-name "conjectures" dir)) dirs))
      (should (member (file-name-as-directory (expand-file-name "courses" dir)) dirs))
      ;; No plain files leak into the directory list.
      (should (cl-every #'file-directory-p (cerebro-note-directories dir))))))

(ert-deftest cerebro-org-test-note-files-recurse-and-exclude ()
  "`cerebro-note-files' recurses into subdirectories but drops what is
not a note: the READMEs, and anything derived.

The `.build/' case is the one that bites. A course composed for an
export is a real .org file full of #+INCLUDEs, sitting inside the notes
tree -- counted as a note, it would double every note it pulls in, in
the stats, in the results graph and in the linter's output."
  (cerebro-org-tests--with-notes
    (let ((files (mapcar #'file-name-nondirectory (cerebro-note-files dir))))
      (should (member "top.org" files))
      (should (member "c.org" files))                ; nested real note
      (should-not (member "x-handbook.org" files))   ; composed for export
      (should-not (member "README.org" files)))))    ; headingless meta

(provide 'cerebro-org-tests)
