;;; cerebro-dashboard-tests.el --- ERT tests for the start page's data -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-dashboard-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; The dashboard is split into pure data functions and a renderer exactly
;; so the data can be tested without emacs-dashboard (or Guix) present --
;; these tests run against the fallback path too. Two claims are worth
;; pinning down, because a regression in either would be silent and
;; misleading rather than loud:
;;
;;   1. "recently changed" means file mtime, so a note created by the
;;      shell CLI or pulled from git shows up, not just what this Emacs
;;      happened to visit;
;;   2. the issue ordering matches the agenda's (priority first, then
;;      DOING before TODO, unprioritised issues ranked at
;;      `org-default-priority') -- a start page that disagrees with
;;      `C-c a i' about what is urgent is worse than none.

(require 'ert)
(require 'cerebro-dashboard)

(defmacro cerebro-dashboard-tests--with-notes (&rest body)
  "Bind `dir' to a throwaway notes tree with known, distinct mtimes:
old.org (oldest), mid.org, new.org (newest), plus TAGS.org which is meta
and must never be listed as a note."
  (declare (indent 0) (debug t))
  `(let ((dir (make-temp-file "cerebro-dash-notes-" t)))
     (unwind-protect
         (progn
           (dolist (spec '(("old.org" . 100) ("mid.org" . 200)
                           ("new.org" . 300) ("TAGS.org" . 400)))
             (let ((f (expand-file-name (car spec) dir)))
               (with-temp-file f (insert "* x\n"))
               ;; Explicit mtimes: writing three files in the same
               ;; hundredth of a second would otherwise make the order
               ;; nondeterministic.
               (set-file-times f (time-convert (cdr spec) nil))))
           ,@body)
       (delete-directory dir t))))

(defmacro cerebro-dashboard-tests--with-issues (&rest body)
  "Bind `file' to a throwaway issue tracker with a known priority mix."
  (declare (indent 0) (debug t))
  `(let ((file (make-temp-file "cerebro-dash-issues-" nil ".org")))
     (unwind-protect
         (progn
           (with-temp-file file
             (insert "* TODO [#C] low priority\n:PROPERTIES:\n:ID: id-c\n:END:\n"
                     "* DONE [#A] already closed\n:PROPERTIES:\n:ID: id-done\n:END:\n"
                     "* TODO [#A] urgent todo :latex:\n:PROPERTIES:\n:ID: id-a\n:END:\n"
                     "* DOING [#A] urgent doing\n:PROPERTIES:\n:ID: id-a2\n:END:\n"
                     "* TODO unprioritised\n:PROPERTIES:\n:ID: id-none\n:END:\n"))
           (unwind-protect (progn ,@body)
             (let ((buf (find-buffer-visiting file)))
               (when buf (kill-buffer buf)))))
       (delete-file file))))

;; -- Recently changed notes --------------------------------------------

(ert-deftest cerebro-dashboard-test-recent-notes-are-mtime-ordered ()
  "Newest first, by file mtime -- not by visit history."
  (cerebro-dashboard-tests--with-notes
    (should (equal (mapcar #'file-name-nondirectory
                           (cerebro-dashboard-recent-notes 10 dir))
                   '("new.org" "mid.org" "old.org")))))

(ert-deftest cerebro-dashboard-test-recent-notes-excludes-meta-files ()
  "TAGS.org is the taxonomy, not a note: it must not appear even though
it is the most recently touched file in the tree."
  (cerebro-dashboard-tests--with-notes
    (should-not (member "TAGS.org"
                        (mapcar #'file-name-nondirectory
                                (cerebro-dashboard-recent-notes 10 dir))))))

(ert-deftest cerebro-dashboard-test-recent-notes-respects-limit ()
  (cerebro-dashboard-tests--with-notes
    (should (equal (length (cerebro-dashboard-recent-notes 2 dir)) 2))))

;; -- Open issues -------------------------------------------------------

(ert-deftest cerebro-dashboard-test-open-issues-excludes-done ()
  "Open means TODO or DOING; a closed issue is gone from the start page."
  (cerebro-dashboard-tests--with-issues
    (let ((ids (mapcar (lambda (i) (plist-get i :id))
                       (cerebro-dashboard-open-issues 10 file))))
      (should-not (member "id-done" ids))
      (should (equal (length ids) 4)))))

(ert-deftest cerebro-dashboard-test-open-issues-ordering ()
  "Priority first, then DOING before TODO at equal priority, and an
unprioritised issue ranks at `org-default-priority' (B) -- i.e. above
[#C], below [#A], exactly as the agenda sorts it."
  (cerebro-dashboard-tests--with-issues
    (should (equal (mapcar (lambda (i) (plist-get i :id))
                           (cerebro-dashboard-open-issues 10 file))
                   '("id-a2" "id-a" "id-none" "id-c")))))

(ert-deftest cerebro-dashboard-test-open-issues-respects-limit ()
  (cerebro-dashboard-tests--with-issues
    (should (equal (length (cerebro-dashboard-open-issues 2 file)) 2))))

(ert-deftest cerebro-dashboard-test-open-issues-missing-file ()
  "No tracker (a fresh clone before the first issue) is empty, not an error."
  (should-not (cerebro-dashboard-open-issues 5 "/nonexistent/issues.org")))

(ert-deftest cerebro-dashboard-test-issue-label-shows-state-and-priority ()
  (cerebro-dashboard-tests--with-issues
    (let ((label (cerebro-dashboard-issue-label
                  (car (cerebro-dashboard-open-issues 1 file)))))
      (should (string-match-p "DOING" label))
      (should (string-match-p "\\[#A\\]" label))
      (should (string-match-p "urgent doing" label)))))

;; -- The renderer ------------------------------------------------------

(ert-deftest cerebro-dashboard-test-fallback-renders-without-package ()
  "The fallback start page builds a real buffer with no emacs-dashboard
-- the degraded, outside-guix path has to work, since that is when you
most need to be told what is missing."
  (let ((buf (cerebro-dashboard--fallback)))
    (should (bufferp buf))
    (unwind-protect
        (with-current-buffer buf
          (should (string-match-p "Open issues:" (buffer-string)))
          (should (string-match-p "Recently changed notes:" (buffer-string))))
      (kill-buffer buf))))

(ert-deftest cerebro-dashboard-test-banner-is-a-committed-image ()
  "The start page's art is a real image, versioned in the repo.
Drawn by bin/cerebro-banner rather than downloaded: nothing here fetches
anything, and the script committed next to the file is what makes the
image editable instead of opaque."
  (should (string-suffix-p ".png" cerebro-dashboard-banner))
  (should (file-readable-p cerebro-dashboard-banner))
  (should (file-readable-p (expand-file-name "bin/cerebro-banner" cerebro-root))))

(ert-deftest cerebro-dashboard-test-banner-needs-image-support ()
  "A banner is used only when this Emacs can actually decode it.
On a terminal frame there is no PNG support, and pointing dashboard at
one would put a placeholder where the picture should be."
  (should (eq (cerebro-dashboard-banner-usable-p) (image-type-available-p 'png)))
  (should-not (cerebro-dashboard-banner-usable-p "/nonexistent/banner.png")))

(ert-deftest cerebro-dashboard-test-labels-are-truncated ()
  "No line on the start page is wider than the page allows.
dashboard centres a section by padding to its widest line, so one long
issue title shifts the whole block and then wraps it -- the page looks
broken rather than merely long. Short titles are left alone."
  (should (<= (string-width (cerebro-dashboard-truncate (make-string 200 ?x)))
              cerebro-dashboard-label-width))
  (should (equal (cerebro-dashboard-truncate "short") "short")))

;;; cerebro-dashboard-tests.el ends here
