;;; cerebro-study-tests.el --- ERT tests for the reading/writing modes -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-study-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; The modes are a table (`cerebro-study-modes'), so what is worth
;; testing is the table's shape and the two claims made about it:
;;
;;   1. the modes really differ in the dimensions they exist to differ in
;;      -- a "study mode" that renders the same things and runs the same
;;      timers as the writing mode is a mode in name only;
;;   2. `study' runs no point-following timers. That is the whole
;;      performance argument: those modes ask `org-element-context' on
;;      every command, ~4ms a call, and a trackpad issues ~100 commands a
;;      second in which point never moves. If `:watch-point' ever became
;;      t there, scrolling would go back to being unusable and nothing
;;      else would say so.

(require 'ert)
(require 'cerebro-study)
(require 'cerebro-modeline) ;; the segment that makes the mode visible

;; -- The table ----------------------------------------------------------

(ert-deftest cerebro-study-test-every-mode-declares-every-dimension ()
  "No mode may leave a setting unstated.
A missing key reads as nil, which is a *decision* here (nil means \"off\")
-- so an omission would silently mean something rather than being caught."
  (dolist (name (cerebro-study-names))
    (dolist (key '(:describe :render :watch-point :markers :shapes :focus :numbers))
      (should (plist-member (cerebro-study-spec name) key)))))

(ert-deftest cerebro-study-test-the-modes-actually-differ ()
  "Distinct modes, distinct settings: no two rows may be the same."
  (let ((seen nil))
    (dolist (name (cerebro-study-names))
      (let ((settings (mapcar (lambda (key) (cerebro-study-get name key))
                              '(:render :watch-point :markers :shapes :focus :numbers))))
        (should-not (member settings seen))
        (push settings seen)))))

(ert-deftest cerebro-study-test-source-shows-the-file ()
  "`source' is the mode that shows what is actually in the file.
It is the one used to check a preview against the bytes that produced
it, so it must render nothing and hide nothing."
  (should-not (cerebro-study-get 'source :render))
  (should (cerebro-study-get 'source :markers))
  ;; ...and org-modern must be off, which is the half that was missing.
  ;; It is a GLOBAL mode, so `source' hid the emphasis markers and left
  ;; every leading star hidden, every `-' drawn as an en dash and every
  ;; `#+begin_' drawn as a shape -- a mode that promises the bytes and
  ;; shows a rendering of them is worse than no such mode, because it is
  ;; the one you reach for when you already distrust the screen.
  (should-not (cerebro-study-get 'source :shapes))
  ;; The reading modes keep the shapes: that is what they are for.
  (should (cerebro-study-get 'write :shapes))
  (should (cerebro-study-get 'study :shapes)))

(ert-deftest cerebro-study-test-study-watches-nothing ()
  "Reading runs no timers. The performance claim, pinned.
org-appear and org-fragtog both hang on `post-command-hook' and both ask
`org-element-context' where point is -- ~4ms per command, against the
~100 commands a second a trackpad generates while scrolling, none of
which move point. `study' is the mode in which that cost is not paid."
  (should-not (cerebro-study-get 'study :watch-point))
  (should (cerebro-study-get 'study :render))
  (should (cerebro-study-get 'study :focus)))

(ert-deftest cerebro-study-test-write-is-the-one-that-follows-point ()
  "Turning the formula at point back into source is a writing affordance.
Exactly one mode does it, and it is the one named for writing."
  (should (equal (seq-filter (lambda (name) (cerebro-study-get name :watch-point))
                             (cerebro-study-names))
                 '(write))))

;; -- Cycling ------------------------------------------------------------

(ert-deftest cerebro-study-test-cycle-visits-every-mode-and-wraps ()
  "`C-c u s' reaches all three and returns to where it started."
  (let ((visited nil) (name 'source))
    (dotimes (_ (length (cerebro-study-names)))
      (push name visited)
      (setq name (cerebro-study-next name)))
    (should (equal (nreverse visited) (cerebro-study-names)))
    (should (eq name 'source))))

(ert-deftest cerebro-study-test-cycle-from-nowhere-starts-at-the-beginning ()
  "A buffer that has never been put in a mode cycles into the first one,
rather than erroring on a nil it was never given."
  (should (eq (cerebro-study-next nil) (car (cerebro-study-names))))
  (should (eq (cerebro-study-next 'not-a-mode) (car (cerebro-study-names)))))

(ert-deftest cerebro-study-test-default-is-a-real-mode ()
  "The mode notes open in has to be one of the modes."
  (should (memq cerebro-study-default (cerebro-study-names))))

;; -- The status line says which one ------------------------------------

(ert-deftest cerebro-study-test-modeline-segment-is-registered ()
  "The mode is visible. A mode you cannot see is a mode that surprises you."
  (should (assq 'study cerebro-modeline-segment-alist))
  (should (memq 'study cerebro-modeline-left)))

(ert-deftest cerebro-study-test-modeline-segment-is-safe-outside-a-note ()
  "The segment must never error: it renders in every buffer there is.
It reads `cerebro-study-mode-name' through `bound-and-true-p' precisely
so that a buffer which predates this module -- or is not Org at all --
contributes nothing instead of taking the whole status line down."
  (with-temp-buffer
    (fundamental-mode)
    (should-not (cerebro-modeline-segment-study)))
  (with-temp-buffer
    (org-mode)
    (should-not (cerebro-modeline-segment-study))   ; no mode set yet
    (setq-local cerebro-study-mode-name 'study)
    (should (equal (substring-no-properties (cerebro-modeline-segment-study))
                   "study"))))

(provide 'cerebro-study-tests)
