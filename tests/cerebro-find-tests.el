;;; cerebro-find-tests.el --- ERT tests for reaching a file by kind -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-find-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; This module replaced the file tree, so what it has to get right is the
;; thing a tree got right for free: never losing a file. A picker that
;; silently drops a note because something else shares its title is worse
;; than a tree, and it fails invisibly -- you simply do not find the note
;; and conclude you never wrote it.

(require 'ert)
(require 'cerebro-find)

;; -- Titles, because file names are digests -----------------------------

(ert-deftest cerebro-find-test-title-comes-from-the-file ()
  "Completion is over titles: the file name is a digest, not a name."
  (let ((file (make-temp-file "cerebro-find" nil ".org"
                              "#+TITLE: The mean value theorem\n#+FILETAGS: :growing:\n")))
    (unwind-protect
        (should (equal (cerebro-find-title file) "The mean value theorem"))
      (delete-file file))))

(ert-deftest cerebro-find-test-title-falls-back-to-the-file-name ()
  "A file with no `#+TITLE:' is still reachable, under its own name.
Dropping it would be the one failure this module cannot afford."
  (let ((file (make-temp-file "cerebro-find" nil ".org" "no front matter\n")))
    (unwind-protect
        (should (equal (cerebro-find-title file) (file-name-nondirectory file)))
      (delete-file file))))

;; -- Never lose a file ---------------------------------------------------

(ert-deftest cerebro-find-test-duplicate-titles-are-disambiguated ()
  "Two notes with the same title both stay reachable.

An alist keyed by title would let the second shadow the first, and
`completing-read' would offer one entry for two files -- a note that has
quietly become unreachable. Here the repeat is qualified by its
directory, so the count of choices equals the count of files."
  (let* ((dir-a (make-temp-file "cerebro-find-a" t))
         (dir-b (make-temp-file "cerebro-find-b" t))
         (file-a (expand-file-name "one.org" dir-a))
         (file-b (expand-file-name "two.org" dir-b)))
    (unwind-protect
        (progn
          (with-temp-file file-a (insert "#+TITLE: Continuity\n"))
          (with-temp-file file-b (insert "#+TITLE: Continuity\n"))
          (let* ((rows (cerebro-find--rows (list file-a file-b)))
                 (labels (mapcar #'car rows)))
            (should (= (length rows) 2))
            (should (= (length (delete-dups (copy-sequence labels))) 2))
            ;; Both files are still on the other side of the mapping.
            (should (equal (sort (mapcar #'cdr rows) #'string<)
                           (sort (list file-a file-b) #'string<)))))
      (delete-directory dir-a t)
      (delete-directory dir-b t))))

(ert-deftest cerebro-find-test-rows-cover-the-real-archive ()
  "Every note in the tree appears exactly once in the picker."
  (let* ((files (cerebro-note-files))
         (rows (cerebro-find--rows files)))
    (should (= (length rows) (length files)))
    (should (= (length (delete-dups (mapcar #'car rows))) (length files)))))

(ert-deftest cerebro-find-test-three-notes-share-a-title-in-one-directory ()
  "A directory separates two notes; it does not separate three.

The qualifier the test above checks is the note's *directory*, so three
notes called \"Continuity\" in notes/math/ produced the labels
`Continuity', `Continuity  (math)' and `Continuity  (math)' -- `assoc'
answered with the second for both of the last two, and the third note
was unreachable from the picker. Exactly the failure the disambiguation
exists to prevent, one note further along."
  (let ((dir (make-temp-file "cerebro-find-three" t)))
    (unwind-protect
        (let ((files (mapcar (lambda (name)
                               (let ((file (expand-file-name name dir)))
                                 (with-temp-file file (insert "#+TITLE: Continuity\n"))
                                 file))
                             '("a.org" "b.org" "c.org"))))
          (let* ((rows (cerebro-find--rows files))
                 (labels (mapcar #'car rows)))
            (should (= (length rows) 3))
            ;; Three distinct choices...
            (should (= (length (delete-dups (copy-sequence labels))) 3))
            ;; ...and each one still reaches its own file.
            (should (equal (sort (mapcar (lambda (l) (cdr (assoc l rows))) labels)
                                 #'string<)
                           (sort (copy-sequence files) #'string<)))))
      (delete-directory dir t))))

(ert-deftest cerebro-find-test-pickers-do-not-offer-non-notes ()
  "A per-kind picker lists notes, not whatever .org is in the directory.

`cerebro-find-note' gets this for free by going through
`cerebro-note-files'; the per-kind pickers listed their directory raw,
so `C-c f j' offered notes/conjectures/README.org -- and, no conjecture
being written yet, offered nothing else, making the one command for
reaching a conjecture able to open only the file that is not one."
  (dolist (directory (list cerebro-conjecture-directory
                           cerebro-math-directory
                           (expand-file-name "courses" org-directory)))
    (when (file-directory-p directory)
      (dolist (file (seq-filter #'cerebro-note-file-p
                                (directory-files directory t "\\.org\\'")))
        (should-not (string-match-p "README\\.org\\'" file))))))

;; -- The commands --------------------------------------------------------

(ert-deftest cerebro-find-test-one-command-per-kind ()
  "The kinds of writing the archive has, each reachable by its own key."
  (dolist (command '(cerebro-find-note cerebro-find-math cerebro-find-conjecture
                     cerebro-find-course cerebro-find-issues
                     cerebro-find-bibliography))
    (should (commandp command))))

(ert-deftest cerebro-find-test-missing-directory-is-refused-clearly ()
  "A kind with no directory yet says so rather than opening nothing."
  (should-error (cerebro-find--in-directory "x: " "/nonexistent/dir")
                :type 'user-error))

(ert-deftest cerebro-find-test-there-is-no-file-tree ()
  "The tree is gone, and nothing may quietly bring it back.

It was replaced rather than merely unbound: leaving the command around
would leave a second, browsing-shaped way to reach files, which is the
thing this archive decided it does not want."
  (should-not (fboundp 'cerebro-ui-toggle-tree))
  (should-not (featurep 'dired-sidebar))
  ;; ...and it is out of the manifest too, not just out of the config.
  (with-temp-buffer
    (insert-file-contents (expand-file-name "guix.scm" cerebro-root))
    (should-not (string-match-p "emacs-dired-sidebar" (buffer-string)))))

(provide 'cerebro-find-tests)
