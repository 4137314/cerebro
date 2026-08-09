;;; cerebro-cache-tests.el --- ERT tests for the scan memo -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-cache-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; A cache under the whole config has exactly one way to be a disaster:
;; returning yesterday's answer. Everything here is about invalidation --
;; that the signature changes when the archive does, and that turning the
;; cache off really does turn it off.

(require 'ert)
(require 'cerebro-cache)

(defmacro cerebro-cache-tests--with-temp-dir (&rest body)
  "Run BODY with `dir' bound to a fresh directory, cleaned up after."
  (declare (indent 0) (debug t))
  `(let ((dir (make-temp-file "cerebro-cache-" t)))
     (unwind-protect (progn ,@body)
       (delete-directory dir t))))

;; -- Signatures ---------------------------------------------------------

(ert-deftest cerebro-cache-test-signature-follows-content ()
  "Touching a file changes its signature; nothing else does."
  (cerebro-cache-tests--with-temp-dir
    (let ((file (expand-file-name "note.org" dir)))
      (with-temp-file file (insert "one"))
      (let ((before (cerebro-cache-file-signature (list file))))
        (should (equal before (cerebro-cache-file-signature (list file))))
        ;; A write a second later is a different signature.
        (set-file-times file (time-add (current-time) 5))
        (should-not (equal before (cerebro-cache-file-signature (list file))))))))

(ert-deftest cerebro-cache-test-signature-ignores-order ()
  "The same files in a different order are the same signature.
Callers get their lists from `directory-files-recursively', whose order
is not something to depend on."
  (cerebro-cache-tests--with-temp-dir
    (let ((a (expand-file-name "a.org" dir))
          (b (expand-file-name "b.org" dir)))
      (with-temp-file a (insert "a"))
      (with-temp-file b (insert "b"))
      (should (equal (cerebro-cache-file-signature (list a b))
                     (cerebro-cache-file-signature (list b a)))))))

(ert-deftest cerebro-cache-test-directory-signature-sees-new-files ()
  "A file appearing in a directory changes that directory's signature.
This is what makes the *listing* of notes safe to memoise: a note created
by `cerebro note new', by git pull or by another Emacs shows up."
  (cerebro-cache-tests--with-temp-dir
    (let ((before (cerebro-cache-directory-signature (list dir))))
      (with-temp-file (expand-file-name "new.org" dir) (insert "x"))
      (should-not (equal before (cerebro-cache-directory-signature (list dir)))))))

;; -- The memo -----------------------------------------------------------

(ert-deftest cerebro-cache-test-recomputes-only-when-the-signature-changes ()
  "The thunk runs once per signature, and again when it changes."
  (cerebro-cache-invalidate)
  (let ((runs 0))
    (cl-flet ((count-run () (cl-incf runs) runs))
      (should (= (cerebro-cache-get 'test "sig-1" #'count-run) 1))
      (should (= (cerebro-cache-get 'test "sig-1" #'count-run) 1))
      (should (= runs 1))
      (should (= (cerebro-cache-get 'test "sig-2" #'count-run) 2))
      (should (= runs 2)))))

(ert-deftest cerebro-cache-test-invalidate-forgets ()
  "Invalidation drops the stored value, by key and wholesale."
  (cerebro-cache-invalidate)
  (let ((runs 0))
    (cl-flet ((count-run () (cl-incf runs)))
      (cerebro-cache-get 'a "sig" #'count-run)
      (cerebro-cache-get 'b "sig" #'count-run)
      (should (= runs 2))
      (cerebro-cache-invalidate 'a)
      (cerebro-cache-get 'a "sig" #'count-run)   ; recomputed
      (cerebro-cache-get 'b "sig" #'count-run)   ; still stored
      (should (= runs 3))
      (cerebro-cache-invalidate)
      (cerebro-cache-get 'b "sig" #'count-run)
      (should (= runs 4)))))

(ert-deftest cerebro-cache-test-can-be-switched-off ()
  "With the cache disabled every call recomputes.
This is the escape hatch that makes \"is the cache lying to me?\" a
question you can answer in one command instead of by reasoning."
  (cerebro-cache-invalidate)
  (let ((runs 0)
        (cerebro-cache-enabled nil))
    (cl-flet ((count-run () (cl-incf runs)))
      (cerebro-cache-get 'test "sig" #'count-run)
      (cerebro-cache-get 'test "sig" #'count-run)
      (should (= runs 2)))))

(ert-deftest cerebro-cache-test-note-files-are-memoised ()
  "`cerebro-note-files' answers from the memo, and notices a new note."
  (require 'cerebro-org)
  (cerebro-cache-tests--with-temp-dir
    (with-temp-file (expand-file-name "one.org" dir) (insert "#+TITLE: one\n"))
    (should (= (length (cerebro-note-files dir)) 1))
    (with-temp-file (expand-file-name "two.org" dir) (insert "#+TITLE: two\n"))
    ;; The directory's mtime changed, so the listing is recomputed --
    ;; without any hook having been told about the new file.
    (should (= (length (cerebro-note-files dir)) 2))))

(provide 'cerebro-cache-tests)
