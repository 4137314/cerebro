;;; cerebro-focus-tests.el --- ERT tests for the reading mode -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-focus-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; Focus mode is a toggle that changes several things at once in a buffer
;; you are in the middle of writing in. The property that matters is
;; therefore not what it turns on but what it puts *back*: a mode that
;; leaves line numbers off, or the status line hidden, after being
;; switched off is indistinguishable from a broken editor.
;;
;; They run in batch, with no window system. Note that `make test' runs
;; them *inside* the pinned environment, where olivetti and mixed-pitch
;; are present -- so the degraded path is exercised by stubbing
;; `cerebro-guix-soft-require', never by assuming a package is missing:
;; a test that asserted absence would pass only outside the environment
;; and would be checking the environment rather than the fallback.

(require 'ert)
(require 'cl-lib)
(require 'cerebro-focus)

;; -- The measure --------------------------------------------------------

(ert-deftest cerebro-focus-test-margin-centres-the-column ()
  "The text sits in the middle: equal margins, target width preserved."
  (should (= (cerebro-focus-margin 120 92) 14))
  ;; 120 - 2*14 = 92, the requested measure.
  (should (= (- 120 (* 2 (cerebro-focus-margin 120 92))) 92)))

(ert-deftest cerebro-focus-test-margin-never-negative ()
  "A window narrower than the column gets no margin, not a negative one.
`set-window-margins' with a negative value signals, and the window it
would signal in is the one you are writing in."
  (should (= (cerebro-focus-margin 60 92) 0))
  (should (= (cerebro-focus-margin 0 92) 0))
  (should (= (cerebro-focus-margin 92 92) 0)))

;; -- Turning it on and off ---------------------------------------------

(ert-deftest cerebro-focus-test-restores-line-numbers ()
  "Line numbers come back if they were on, stay off if they were not."
  (with-temp-buffer
    (display-line-numbers-mode 1)
    (cerebro-focus-mode 1)
    (should-not (bound-and-true-p display-line-numbers-mode))
    (cerebro-focus-mode -1)
    (should (bound-and-true-p display-line-numbers-mode)))
  (with-temp-buffer
    (cerebro-focus-mode 1)
    (cerebro-focus-mode -1)
    (should-not (bound-and-true-p display-line-numbers-mode))))

(ert-deftest cerebro-focus-test-restores-the-mode-line ()
  "With `cerebro-focus-hide-mode-line', the status line comes back intact."
  (with-temp-buffer
    (let ((cerebro-focus-hide-mode-line t)
          (marker '("test-mode-line")))
      (setq mode-line-format marker)
      (cerebro-focus-mode 1)
      (should-not mode-line-format)
      (cerebro-focus-mode -1)
      (should (equal mode-line-format marker)))))

(ert-deftest cerebro-focus-test-leaves-the-mode-line-alone-by-default ()
  "By default the status line is untouched -- hiding it is opt-in."
  (with-temp-buffer
    (let ((cerebro-focus-hide-mode-line nil)
          (marker '("test-mode-line")))
      (setq mode-line-format marker)
      (cerebro-focus-mode 1)
      (should (equal mode-line-format marker))
      (cerebro-focus-mode -1))))

(ert-deftest cerebro-focus-test-works-without-olivetti ()
  "The mode still toggles when its packages are missing (invariant 4).
Absence is *simulated* rather than assumed: `make test' runs inside the
pinned environment, where olivetti and mixed-pitch are both present, so a
test that asserted they were missing would only ever pass outside it --
and would be testing the environment instead of the fallback."
  (cl-letf (((symbol-function 'cerebro-guix-soft-require) (lambda (_feature) nil)))
    (with-temp-buffer
      (set-window-buffer (selected-window) (current-buffer))
      (cerebro-focus-mode 1)
      (should cerebro-focus-mode)
      ;; It took the fallback, not olivetti...
      (should-not (bound-and-true-p olivetti-mode))
      ;; ...and the fallback actually set margins (in a window wide
      ;; enough for the measure to leave any).
      (when (> (window-total-width) cerebro-focus-width)
        (should (> (or (car (window-margins)) 0) 0)))
      (cerebro-focus-mode -1)
      (should-not cerebro-focus-mode)
      (should (member (car (window-margins)) '(nil 0))))))

(ert-deftest cerebro-focus-test-is-buffer-local ()
  "Turning it on in one note does not centre every other buffer."
  (let ((other (generate-new-buffer " *cerebro-focus-test*")))
    (unwind-protect
        (with-temp-buffer
          (cerebro-focus-mode 1)
          (should cerebro-focus-mode)
          (with-current-buffer other
            (should-not (bound-and-true-p cerebro-focus-mode)))
          (cerebro-focus-mode -1))
      (kill-buffer other))))

(provide 'cerebro-focus-tests)
