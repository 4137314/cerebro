;;; cerebro-mode-tests.el --- ERT tests for the two macro-modes -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-mode-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; Two properties are worth more than all the rest here, and both are
;; silent when they break:
;;
;;   1. the issue filter cannot lose work. An issue tagged for neither
;;      mode has to be visible from both, or the backlog quietly shrinks
;;      and nobody is told which half went missing;
;;   2. applying a mode really does move the writable line. `dev' that
;;      forgets to switch the guard rail off is a mode that pretends,
;;      and `math' that forgets to switch it back on is worse.
;;
;; Everything here is pure but for the state file, which every test that
;; touches it redirects into a temp file: these must never write the real
;; .emacs.d/var/mode, or running the suite would change what the next
;; session opens as.

(require 'ert)
(require 'cerebro-mode)

(defmacro cerebro-mode-tests--with-state (&rest body)
  "Run BODY with the state file redirected and the environment cleared."
  (declare (indent 0) (debug t))
  `(let* ((file (make-temp-file "cerebro-mode-"))
          (cerebro-mode-file file)
          (cerebro-mode-current nil)
          (process-environment (cons "CEREBRO_MODE" process-environment)))
     (unwind-protect (progn ,@body)
       (when (file-exists-p file) (delete-file file)))))

;; -- The list is a decision --------------------------------------------

(ert-deftest cerebro-mode-test-there-are-exactly-two ()
  "Two modes, math and dev -- pinned like the four course profiles.

A third would not be a mode, it would be a preference: the point of the
setting is that `the other one' is a question with an answer, which is
what makes the toggle and the issue filter well defined."
  (should (equal (cerebro-mode-names) '(math dev)))
  (should (cerebro-mode-p 'math))
  (should (cerebro-mode-p 'dev))
  (should-not (cerebro-mode-p 'writing)))

(ert-deftest cerebro-mode-test-every-mode-declares-every-dimension ()
  "A mode missing a key is a mode that silently keeps the other one's
setting, which is exactly the confusion this file exists to remove."
  (dolist (mode (cerebro-mode-names))
    (dolist (key '(:describe :sign :ascii :writable :study :issue-tags))
      (should (cerebro-mode-get mode key)))))

(ert-deftest cerebro-mode-test-other-is-an-involution ()
  (dolist (mode (cerebro-mode-names))
    (should-not (eq (cerebro-mode-other mode) mode))
    (should (eq (cerebro-mode-other (cerebro-mode-other mode)) mode))))

;; -- Reading a mode name ------------------------------------------------

(ert-deftest cerebro-mode-test-parse-forgives-what-people-type ()
  "The name arrives from a file and from an environment variable."
  (should (eq (cerebro-mode-parse "math") 'math))
  (should (eq (cerebro-mode-parse " DEV\n") 'dev))
  (should (eq (cerebro-mode-parse 'math) 'math))
  (should-not (cerebro-mode-parse "both"))
  (should-not (cerebro-mode-parse ""))
  (should-not (cerebro-mode-parse nil)))

;; -- Whose work is this issue ------------------------------------------

(ert-deftest cerebro-mode-test-each-mode-claims-its-own ()
  (should (cerebro-mode-issue-p '("guix" "ci") 'dev))
  (should-not (cerebro-mode-issue-p '("guix" "ci") 'math))
  (should (cerebro-mode-issue-p '("research") 'math))
  (should-not (cerebro-mode-issue-p '("research") 'dev)))

(ert-deftest cerebro-mode-test-area-tags-are-mathematics-without-being-listed ()
  "The area taxonomy is read, not copied (`:issue-tag-functions'), so an
area added to cerebro-taxonomy.el is mathematical work the same day."
  (dolist (tag '("analysis" "functional_analysis" "algebraic_geometry"))
    (should (cerebro-mode-issue-p (list tag) 'math))
    (should-not (cerebro-mode-issue-p (list tag) 'dev))))

(ert-deftest cerebro-mode-test-an-unclassified-issue-belongs-to-both ()
  "The property that makes the filter safe: it hides only what says it is
the other job. An issue tagged with nothing either mode knows is shown in
both, because an issue you cannot see is an issue you conclude you never
filed."
  (dolist (tags '(nil ("wishlist") ("someday" "maybe")))
    (should (cerebro-mode-issue-p tags 'math))
    (should (cerebro-mode-issue-p tags 'dev))))

(ert-deftest cerebro-mode-test-an-issue-in-both-families-is-in-both-modes ()
  "`:bib:research:' is a feature request that came out of doing
mathematics; it is genuinely both people's problem."
  (should (cerebro-mode-issue-p '("bib" "research") 'math))
  (should (cerebro-mode-issue-p '("bib" "research") 'dev))
  ;; ...and then it is nobody's *exclusively*.
  (should-not (cerebro-mode-of-tags '("bib" "research")))
  (should (eq (cerebro-mode-of-tags '("guix")) 'dev))
  (should (eq (cerebro-mode-of-tags '("research")) 'math)))

(ert-deftest cerebro-mode-test-no-tag-set-is-invisible-from-every-mode ()
  "Over every tag either mode knows, plus unknown ones and the empty set:
some mode always shows it. This is the invariant the whole filter rests
on, so it is checked exhaustively rather than by example."
  (let ((tags (append (cerebro-mode-tags 'math) (cerebro-mode-tags 'dev)
                      '("no-such-tag"))))
    (dolist (tag tags)
      (should (seq-some (lambda (mode) (cerebro-mode-issue-p (list tag) mode))
                        (cerebro-mode-names))))))

;; -- Where the mode is remembered --------------------------------------

(ert-deftest cerebro-mode-test-state-file-round-trips ()
  (cerebro-mode-tests--with-state
    (should-not (cerebro-mode-stored))
    (cerebro-mode-store 'dev)
    (should (eq (cerebro-mode-stored) 'dev))
    (cerebro-mode-store 'math)
    (should (eq (cerebro-mode-stored) 'math))))

(ert-deftest cerebro-mode-test-a-corrupt-state-file-is-not-fatal ()
  "A scrap of session state must never be able to stop the editor
starting: nonsense reads as `nothing remembered'."
  (cerebro-mode-tests--with-state
    (with-temp-file cerebro-mode-file (insert "\0not a mode\n"))
    (should-not (cerebro-mode-stored))
    (should (eq (car (cerebro-mode-resolve)) cerebro-mode-default))))

(ert-deftest cerebro-mode-test-resolution-order ()
  "CEREBRO_MODE beats the remembered mode beats the default -- and the
report says which, because \"why am I in dev?\" is the only question a
persistent setting ever raises."
  (cerebro-mode-tests--with-state
    (should (equal (cerebro-mode-resolve) (cons cerebro-mode-default 'default)))
    (cerebro-mode-store 'dev)
    (should (equal (cerebro-mode-resolve) '(dev . stored)))
    (let ((process-environment (cons "CEREBRO_MODE=math" process-environment)))
      (should (equal (cerebro-mode-resolve) '(math . environment))))
    ;; An unknown CEREBRO_MODE is ignored rather than fatal.
    (let ((process-environment (cons "CEREBRO_MODE=nonsense" process-environment)))
      (should (equal (cerebro-mode-resolve) '(dev . stored))))))

;; -- Applying one -------------------------------------------------------

(ert-deftest cerebro-mode-test-apply-moves-the-writable-line ()
  "The whole feature, in both directions -- and tested the way it is
actually experienced: by opening a file and seeing whether you can type
into it. cerebro-isolation.el is loaded for real rather than mocked,
because this is the one place where the two modules meet, and its
`find-file-hook' is what a person meets first."
  (require 'cerebro-isolation)
  (cerebro-mode-tests--with-state
    (let ((cerebro-isolation-enabled t)
          (cerebro-isolation-writable-directories '("nowhere"))
          (module (expand-file-name ".emacs.d/lisp/cerebro-org.el" cerebro-root))
          (note (expand-file-name "notes/math/abc.org" cerebro-root)))
      ;; dev: the machinery is the work, so it opens writable.
      (cerebro-mode-apply 'dev)
      (should-not cerebro-isolation-enabled)
      (with-temp-buffer
        (setq buffer-file-name module)
        (cerebro-isolation-protect)
        (should-not buffer-read-only))
      ;; math: the archive is writable and the machinery is not -- and the
      ;; directories are the mode's own datum, not a second copy of them.
      (cerebro-mode-apply 'math)
      (should cerebro-isolation-enabled)
      (should (equal cerebro-isolation-writable-directories
                     (cerebro-mode-get 'math :writable)))
      (with-temp-buffer
        (setq buffer-file-name module)
        (cerebro-isolation-protect)
        (should buffer-read-only))
      (with-temp-buffer
        (setq buffer-file-name note)
        (cerebro-isolation-protect)
        (should-not buffer-read-only)))))

;; `cerebro-study-default' belongs to a module this file does not load
;; (cerebro-study.el pulls in Org and the preview machinery). Declaring it
;; special here is what lets the test bind it dynamically -- under lexical
;; binding a plain `let' would create a local that `cerebro-mode-apply'
;; could never see, and the test would fail while the code was right.
(defvar cerebro-study-default)

(ert-deftest cerebro-mode-test-apply-sets-how-a-note-opens ()
  "math opens a note in the working mode, dev in source: in dev a note is
opened because something disagreed with it, and then you want the bytes."
  (cerebro-mode-tests--with-state
    (let ((cerebro-study-default 'write))
      (cerebro-mode-apply 'dev)
      (should (eq cerebro-study-default 'source))
      (cerebro-mode-apply 'math)
      (should (eq cerebro-study-default 'write)))))

(ert-deftest cerebro-mode-test-apply-runs-the-hook-and-rejects-nonsense ()
  "`cerebro-mode-hook' is the seam everything else reacts through, so it
has to fire with the mode that was applied."
  (cerebro-mode-tests--with-state
    (let* ((seen nil)
           (cerebro-mode-hook (list (lambda (mode) (push mode seen)))))
      (cerebro-mode-apply 'dev)
      (cerebro-mode-apply 'math)
      (should (equal (reverse seen) '(dev math))))
    (should-error (cerebro-mode-apply 'sideways) :type 'user-error)))

(ert-deftest cerebro-mode-test-switch-remembers-unless-told-not-to ()
  "`C-u C-c M d' is the ten minutes of maintenance in the middle of a
morning of mathematics: this session only, and tomorrow is unchanged."
  (cerebro-mode-tests--with-state
    (cerebro-mode-switch 'dev)
    (should (eq (cerebro-mode-stored) 'dev))
    (cerebro-mode-switch 'math t)
    (should (eq (cerebro-mode-active) 'math))
    (should (eq (cerebro-mode-stored) 'dev))))

(ert-deftest cerebro-mode-test-lighter-degrades-to-ascii ()
  "A glyph the font does not have is drawn as an empty box -- the lesson
the start page already learned. In batch there is no graphic display, so
this is also what the label looks like in a terminal frame."
  (dolist (mode (cerebro-mode-names))
    (should (equal (cerebro-mode-label mode) (cerebro-mode-get mode :ascii)))))

;; -- Saying where you are ----------------------------------------------

(ert-deftest cerebro-mode-test-report-says-what-changes ()
  "The report is what both `cerebro mode' and `C-c M s' print, so it has
to name the things a mode actually moves."
  (cerebro-mode-tests--with-state
    (let ((report (string-join (cerebro-mode-report-lines 'dev) "\n")))
      (should (string-match-p "dev" report))
      (should (string-match-p "guard rail is off" report))
      (should (string-match-p "in force" report))
      (should (string-match-p "the other  math" report)))
    (let ((report (string-join (cerebro-mode-report-lines 'math) "\n")))
      (should (string-match-p "notes/ issues/ bib/" report)))))

(provide 'cerebro-mode-tests)
