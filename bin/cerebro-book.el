;;; cerebro-book.el --- regenerate a course book in batch -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/cerebro-book.el -- notes/courses/analysis-1
;; (what bin/cerebro-new-book runs; `cerebro course' calls that in turn).
;;
;; The shell twin of `M-x cerebro-course-build-book': same module, same
;; output, no second implementation of "what a book is". It needs Emacs
;; because resolving `id:' links to files is Org's job -- which is also
;; the point of using IDs, since a note can then be renamed or moved
;; without touching any course.

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (lisp-dir (expand-file-name "../.emacs.d/lisp" here)))
  (add-to-list 'load-path lisp-dir))

(require 'cerebro-course)

(let ((directory (car (last command-line-args-left))))
  (unless (and directory (file-directory-p directory))
    (princ "usage: emacs --batch -l bin/cerebro-book.el -- DIR\n")
    (kill-emacs 2))
  ;; The ID -> file map is a cache: a note created since the last scan
  ;; (very likely, since this runs right after writing notes) would
  ;; otherwise resolve to nothing and land in the book as MISSING.
  (org-id-update-id-locations (cerebro-note-files) t)
  (let ((missing
         ;; A course whose programme is still empty is a normal state (a
         ;; freshly scaffolded one), and `cerebro-course' calls this
         ;; unconditionally -- so report it as one line and a status
         ;; code, not as a batch backtrace.
         (condition-case err
             (cerebro-course-build-book (expand-file-name directory))
           (user-error
            (princ (format "%s\n" (error-message-string err)))
            (kill-emacs 3)))))
    (when missing
      (princ (format "cerebro-book: %d unresolved id: link(s):\n" (length missing)))
      (dolist (id missing) (princ (format "  id:%s\n" id)))
      ;; A book with a hole in it is a broken document, and this runs
      ;; from `make course' -- fail loudly rather than ship it.
      (kill-emacs 1))))
