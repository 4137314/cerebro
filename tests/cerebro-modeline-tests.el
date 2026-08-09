;;; cerebro-modeline-tests.el --- ERT tests for the status line -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-modeline-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; A mode line runs on every redisplay, in every buffer, forever. That
;; makes its failure mode unusually nasty: a segment that errors turns
;; into an error message drawn dozens of times a second, in a buffer you
;; cannot then use to fix it. So the tests here are less about formatting
;; than about robustness --
;;
;;   - every segment must return a string or nil in an *arbitrary* buffer
;;     (no file, no org, no clock, no repository);
;;   - the segment names listed in the two data variables must exist;
;;   - the layout arithmetic must be total: any width, including widths
;;     too small for the content (the 30-column sidebar).
;;
;; All of it is pure string work, so it runs in batch with no frame.

(require 'ert)
(require 'cl-lib)
(require 'cerebro-modeline)
(require 'cerebro-mode) ;; the `work' segment reads it (defensively, so it
                        ;; is not required *by* cerebro-modeline.el)

;; -- The data holds together -------------------------------------------

(ert-deftest cerebro-modeline-test-configured-segments-exist ()
  "Every name in the left/right lists is a segment that exists.
A typo there is invisible: `cerebro-modeline-compose' skips unknown
names, so the indicator simply never appears and nothing is reported."
  (dolist (name (append cerebro-modeline-left cerebro-modeline-right))
    (let ((fn (cdr (assq name cerebro-modeline-segment-alist))))
      (should fn)
      (should (fboundp fn)))))

(ert-deftest cerebro-modeline-test-segments-are-safe-in-any-buffer ()
  "No segment errors, or returns a non-string, in a bare temp buffer.
This is the redisplay-safety test: a buffer with no file, no major mode
of interest, no VC and no clock is what *Completions*, *Messages* and
every transient report buffer look like."
  (with-temp-buffer
    (dolist (cell cerebro-modeline-segment-alist)
      (let ((value (funcall (cdr cell))))
        (should (or (null value) (stringp value)))))))

;; -- Composition --------------------------------------------------------

(ert-deftest cerebro-modeline-test-compose-skips-empty-segments ()
  "Segments with nothing to say leave no separator behind."
  (cl-letf (((symbol-function 'cerebro-modeline-tests--a) (lambda () "a"))
            ((symbol-function 'cerebro-modeline-tests--nil) (lambda () nil))
            ((symbol-function 'cerebro-modeline-tests--empty) (lambda () ""))
            ((symbol-function 'cerebro-modeline-tests--b) (lambda () "b")))
    (let ((cerebro-modeline-segment-alist
           '((a . cerebro-modeline-tests--a)
             (none . cerebro-modeline-tests--nil)
             (empty . cerebro-modeline-tests--empty)
             (b . cerebro-modeline-tests--b))))
      (should (equal (cerebro-modeline-compose '(a none empty b)) "a b"))
      (should (equal (cerebro-modeline-compose '(none empty)) ""))
      ;; An unknown name is skipped rather than signalling: a mode line
      ;; must not break because a segment was renamed.
      (should (equal (cerebro-modeline-compose '(a nosuch b)) "a b")))))

;; -- Layout -------------------------------------------------------------

(ert-deftest cerebro-modeline-test-render-right-aligns ()
  "RIGHT ends flush against the edge, LEFT stays where it is."
  (let ((line (cerebro-modeline-render "left" "right" 40)))
    (should (string-prefix-p "left" line))
    (should (string-suffix-p "right" line))
    ;; One column of slack, deliberately (see the docstring).
    (should (= (string-width line) 39))))

(ert-deftest cerebro-modeline-test-render-handles-narrow-windows ()
  "In a window too narrow for both, RIGHT is dropped and LEFT truncated.
The 30-column sidebar is the real case: there, the file you are looking
at is the only thing worth the space."
  (let ((line (cerebro-modeline-render "a-very-long-buffer-name.org" "org 12:0" 12)))
    (should (<= (string-width line) 12))
    (should-not (string-match-p "org 12:0" line)))
  ;; Degenerate widths must not signal (a window can be one column wide
  ;; mid-split).
  (should (stringp (cerebro-modeline-render "left" "right" 1)))
  (should (stringp (cerebro-modeline-render "" "" 0))))

(ert-deftest cerebro-modeline-test-render-tolerates-missing-halves ()
  "Nil for either half is treated as empty, not as an error."
  (should (stringp (cerebro-modeline-render nil "right" 20)))
  (should (stringp (cerebro-modeline-render "left" nil 20))))

;; -- Individual segments ------------------------------------------------

(ert-deftest cerebro-modeline-test-state-segment ()
  "The state glyph appears only when there is state to report."
  (with-temp-buffer
    (set-buffer-modified-p nil)
    (should-not (cerebro-modeline-segment-state))
    (insert "x")
    (should (cerebro-modeline-segment-state))
    (set-buffer-modified-p nil)
    (setq buffer-read-only t)
    (should (cerebro-modeline-segment-state))))

(ert-deftest cerebro-modeline-test-percent-signs-are-escaped ()
  "A `%' in a name never reaches redisplay as a format specification.
The string these segments return is processed by `format-mode-line', so
an unescaped `%b' or `%f' coming out of a buffer name or a clocked
heading would print something else entirely."
  (with-temp-buffer
    (rename-buffer "95%-bound.org" t)
    (should (string-match-p "95%%-bound"
                            (substring-no-properties
                             (cerebro-modeline-segment-buffer)))))
  (cl-letf (((symbol-function 'org-clocking-p) (lambda () t))
            ((symbol-function 'org-clock-get-clocked-time) (lambda () 5))
            (org-clock-heading "95% of the proof")
            (cerebro-modeline-clock-width 40))
    (should (string-match-p "95%%" (cerebro-modeline-clock-string)))))

(ert-deftest cerebro-modeline-test-narrow-segment ()
  "A narrowed buffer says so -- it is invisible state that changes what
you see, and the commonest cause of \"my note lost half its content\"."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (should-not (cerebro-modeline-segment-narrow))
    (narrow-to-region (point-min) (+ (point-min) 3))
    (should (cerebro-modeline-segment-narrow))))

(ert-deftest cerebro-modeline-test-buffer-context-is-notes-relative ()
  "The context is the note's directory *inside* notes/, or nothing.
A note in notes/ itself gets no prefix (the name already says it all);
one in notes/courses/analysis-1/ gets the course, which is exactly what
distinguishes it from the twenty other `compactness.org's."
  (let* ((root (file-name-as-directory (make-temp-file "cerebro-notes-" t)))
         (org-directory (directory-file-name root))
         (course (expand-file-name "courses/analysis-1/" root)))
    (unwind-protect
        (progn
          (make-directory course t)
          (with-temp-buffer
            (setq buffer-file-name (expand-file-name "compactness.org" course))
            (should (equal (cerebro-modeline-buffer-context) "courses/analysis-1/"))
            (setq buffer-file-name (expand-file-name "compactness.org" root))
            (should-not (cerebro-modeline-buffer-context))
            ;; A file outside the notes tree entirely: no context, no error.
            (setq buffer-file-name "/etc/passwd")
            (should-not (cerebro-modeline-buffer-context))))
      (delete-directory root t))))

(ert-deftest cerebro-modeline-test-clock-string-keeps-the-time ()
  "When the heading has to be cut, the elapsed time survives whole.
\"Which task\" is guessable from the first words; \"how long\" is not
guessable at all, and it is the number that gets mirrored into
Timewarrior."
  (cl-letf (((symbol-function 'org-clocking-p) (lambda () t))
            ((symbol-function 'org-clock-get-clocked-time) (lambda () 95))
            (org-clock-heading "a very long theorem heading that will not fit")
            (cerebro-modeline-clock-width 20))
    (let ((clock (cerebro-modeline-clock-string)))
      (should (string-suffix-p "95m" clock))
      (should (<= (string-width clock) 20))))
  (cl-letf (((symbol-function 'org-clocking-p) (lambda () nil)))
    (should-not (cerebro-modeline-clock-string))))

(ert-deftest cerebro-modeline-test-vc-segment-strips-the-backend ()
  "Only the branch is shown, not Emacs' \" Git:\" prefix."
  (with-temp-buffer
    (setq-local vc-mode " Git:feature/emacs-ui")
    (should (equal (substring-no-properties (cerebro-modeline-segment-vc))
                   "feature/emacs-ui"))
    (setq-local vc-mode nil)
    (should-not (cerebro-modeline-segment-vc))))

(ert-deftest cerebro-modeline-test-mode-segment-uses-short-names ()
  "The modes seen daily get a short name; anything else falls back."
  (with-temp-buffer
    (emacs-lisp-mode)
    (should (equal (substring-no-properties (cerebro-modeline-segment-mode)) "elisp")))
  (with-temp-buffer
    (fundamental-mode)
    (should (stringp (cerebro-modeline-segment-mode)))))

;; -- What you are inside ------------------------------------------------

(defconst cerebro-modeline-tests--note
  "#+TITLE: t
#+FILETAGS: :growing:analysis:real_analysis:

Prose before anything is named.

#+NAME: thm-first
#+begin_theorem
A.
#+end_theorem

#+begin_proof
Because.
#+end_proof
"
  "A note with front matter and one named result.")

(ert-deftest cerebro-modeline-test-result-segment-names-what-you-are-in ()
  "Inside a proof, the segment names the statement it belongs to.
That is the question with no other cheap answer while reading: a proof
three screens below its statement looks exactly like a proof of whatever
is above it."
  (with-temp-buffer
    (insert cerebro-modeline-tests--note)
    (org-mode)
    (goto-char (point-min))
    (search-forward "Because.")
    (should (equal (substring-no-properties (cerebro-modeline-segment-result))
                   "thm-first"))
    ;; Above every name there is nothing to say, rather than the first one.
    (goto-char (point-min))
    (search-forward "Prose before")
    (should-not (cerebro-modeline-segment-result))))

(ert-deftest cerebro-modeline-test-result-segment-is-org-only ()
  "The status line renders in buffers of every kind and must not guess."
  (with-temp-buffer
    (fundamental-mode)
    (insert "#+NAME: thm-x\n")
    (should-not (cerebro-modeline-segment-result))))

(ert-deftest cerebro-modeline-test-maturity-segment-reads-the-filetags ()
  "The rung is shown so it can be reconsidered.
A state nobody can see is a state nobody updates -- the same argument the
ladder makes for `C-c m +'."
  (with-temp-buffer
    (insert cerebro-modeline-tests--note)
    (org-mode)
    (should (equal (substring-no-properties (cerebro-modeline-segment-maturity))
                   "growing")))
  ;; A note with no maturity tag says nothing, rather than guessing one.
  (with-temp-buffer
    (insert "#+TITLE: t\n#+FILETAGS: :analysis:\n")
    (org-mode)
    (should-not (cerebro-modeline-segment-maturity))))

(ert-deftest cerebro-modeline-test-note-segments-are-bounded ()
  "Both searches stop after `cerebro-modeline-search-limit' characters.

Not a micro-optimisation: a segment runs on every redisplay, which under
`pixel-scroll-precision-mode' is ~100 times a second while scrolling. An
unbounded backward search in a long note is the exact shape of the bug
that made scrolling unusable before (cerebro-study.el). Here: a name far
above the bound is deliberately *not* found."
  (with-temp-buffer
    (insert "#+NAME: thm-far-away\n#+begin_theorem\nA.\n#+end_theorem\n")
    (insert (make-string (* 3 cerebro-modeline-search-limit) ?x))
    (insert "\nprose\n")
    (org-mode)
    (goto-char (point-max))
    (should-not (cerebro-modeline-segment-result))))

(ert-deftest cerebro-modeline-test-new-segments-are-registered ()
  "All three are in the table and on the left group, or they draw nothing."
  (dolist (segment '(result maturity work))
    (should (assq segment cerebro-modeline-segment-alist))
    (should (memq segment cerebro-modeline-left))))

(ert-deftest cerebro-modeline-test-work-segment-follows-the-mode ()
  "The macro-mode is shown, and shown *differently* in dev.

Silence before a mode is applied is deliberate: a batch Emacs or a
buffer that existed before cerebro-mode.el loaded has no answer, and an
indicator that guesses is worse than one that waits. The face matters
because it is the whole point of the segment -- in dev every file in the
repository is writable, and that is the state you must not forget you
are in."
  (let ((cerebro-mode-current nil) (cerebro-mode-lighter nil))
    (should-not (cerebro-modeline-segment-work)))
  (dolist (mode '(math dev))
    (let ((cerebro-mode-current mode)
          (cerebro-mode-lighter (cerebro-mode-label mode)))
      (let ((shown (cerebro-modeline-segment-work)))
        (should (equal (substring-no-properties shown)
                       (cerebro-mode-label mode)))
        (should (eq (get-text-property 0 'face shown)
                    (if (eq mode 'dev)
                        'cerebro-modeline-alert
                      'cerebro-modeline-dim)))))))

;; -- The mode itself ----------------------------------------------------

(ert-deftest cerebro-modeline-test-mode-is-reversible ()
  "Turning the mode off restores the previous `mode-line-format'.
It is a global replacement of a core variable; not being able to undo it
would mean the only way back is restarting Emacs."
  ;; The module turns itself on when it loads, so start from a known-off
  ;; state rather than from whatever this session happens to be in.
  (cerebro-modeline-mode -1)
  (let ((before (default-value 'mode-line-format)))
    (cerebro-modeline-mode 1)
    (should (equal (default-value 'mode-line-format) cerebro-modeline-format))
    (cerebro-modeline-mode -1)
    (should (equal (default-value 'mode-line-format) before))
    ;; Leave the session as the module found it (init.el turns it on).
    (cerebro-modeline-mode 1)))

(provide 'cerebro-modeline-tests)
