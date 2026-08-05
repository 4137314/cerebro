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
;; hide every nested course/daily note from the agenda again.

(require 'ert)
(require 'cl-lib)
(require 'cerebro-org)

(defmacro cerebro-org-tests--with-notes (&rest body)
  "Run BODY with `dir' bound to a throwaway notes tree:
  <dir>/top.org
  <dir>/TAGS.org            (meta, excluded from note *files*)
  <dir>/courses/a/lec.org   (nested real note)
  <dir>/courses/a/book.org  (generated aggregator, excluded)
  <dir>/daily/2026-01-01.org (nested real note)
The directory is deleted afterward."
  (declare (indent 0) (debug t))
  `(let ((dir (make-temp-file "cerebro-notes-" t)))
     (unwind-protect
         (progn
           (make-directory (expand-file-name "courses/a" dir) t)
           (make-directory (expand-file-name "daily" dir) t)
           (dolist (rel '("top.org" "TAGS.org" "courses/a/lec.org"
                          "courses/a/book.org" "daily/2026-01-01.org"))
             (with-temp-file (expand-file-name rel dir) (insert "* x\n")))
           ,@body)
       (delete-directory dir t))))

(ert-deftest cerebro-org-test-note-directories-recurse ()
  "`cerebro-note-directories' returns the root and every subdirectory --
this is what lets org-agenda-files reach nested notes."
  (cerebro-org-tests--with-notes
    (let ((dirs (mapcar #'file-name-as-directory (cerebro-note-directories dir))))
      (should (member (file-name-as-directory dir) dirs))
      (should (member (file-name-as-directory (expand-file-name "courses/a" dir)) dirs))
      (should (member (file-name-as-directory (expand-file-name "daily" dir)) dirs))
      ;; No plain files leak into the directory list.
      (should (cl-every #'file-directory-p (cerebro-note-directories dir))))))

(ert-deftest cerebro-org-test-note-files-recurse-and-exclude ()
  "`cerebro-note-files' recurses into subdirectories but drops the
non-note files (book.org aggregators, README.org, TAGS.org)."
  (cerebro-org-tests--with-notes
    (let ((files (mapcar #'file-name-nondirectory (cerebro-note-files dir))))
      (should (member "top.org" files))
      (should (member "lec.org" files))            ; nested real note
      (should (member "2026-01-01.org" files))     ; nested daily note
      (should-not (member "book.org" files))       ; generated aggregator
      (should-not (member "TAGS.org" files)))))    ; headingless meta

(provide 'cerebro-org-tests)
