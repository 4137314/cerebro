;;; cerebro-mode.el --- the two things you sit down to do -*- lexical-binding: t; -*-

;; There are exactly two reasons to open this repository, and they want
;; opposite editors:
;;
;;   math -- study the archive, write a theorem, compile a document, and
;;           work the issues that are about *mathematics*. The machinery
;;           is read-only (cerebro-isolation.el), a note opens rendered,
;;           and the start page is about what the archive owes.
;;   dev  -- maintain the machinery itself: the modules, the shell tools,
;;           the LaTeX classes, the tests, guix.scm -- and work the issues
;;           that are about *those*. Every file in the repository is
;;           writable, a note opens as source (in dev you are checking the
;;           bytes, not reading the mathematics), and the start page is
;;           about the backlog.
;;
;; Until now that difference was a set of habits: you remembered to
;; `C-c H u' before editing a module, you filtered issues by eye, and
;; nothing on screen said which of the two jobs you were doing. This file
;; makes it one binary setting, held in one place, so switching is a
;; keystroke and so the state is *visible* (the status line and the start
;; page both say which mode is in force).
;;
;; Shape, deliberately the same as `cerebro-study-modes' one level down --
;; that one is "what am I doing to this note", this one is "what am I
;; doing in this repository":
;;
;;   - the modes are DATA (`cerebro-modes'): one row per mode, one key per
;;     thing that differs. Adding a *dimension* is adding a key here and a
;;     clause in `cerebro-mode-apply', which is the only function that
;;     knows how any of it is switched on.
;;   - applying a mode never *requires* the module it configures. It sets
;;     variables that may or may not be bound (`boundp'), and then runs
;;     `cerebro-mode-hook'. That is what keeps this file pure in the sense
;;     of CLAUDE.md's invariant 4 -- it loads no Org, so the shell tools
;;     (`cerebro mode', `cerebro issue list') can read the mode in ~50ms
;;     instead of paying 340ms to load an agenda they never use.
;;   - and there are exactly TWO of them. A third would not be a mode, it
;;     would be a preference; a test asserts the list, like the one that
;;     pins the four course profiles.
;;
;; Note on the name: there is deliberately no function or variable called
;; plain `cerebro-mode'. In Emacs that name means a minor mode, and this
;; is not one -- it is a session-wide setting. The commands are
;; `cerebro-mode-math', `cerebro-mode-dev', `cerebro-mode-toggle' and
;; `cerebro-mode-status' (`C-c M ...'), the CLI is `cerebro mode', and the
;; environment variable is CEREBRO_MODE. Same word everywhere.

(require 'cerebro-base)     ;; cerebro-root, cerebro-report
(require 'cerebro-taxonomy) ;; the area tags -- data, no Org
(require 'seq)

(defgroup cerebro-mode nil
  "Which of the two jobs this session is doing."
  :group 'cerebro)

;; -- The two modes, as data ---------------------------------------------
;; One row per mode; every key is something that genuinely differs. What
;; is NOT here is as deliberate as what is: the keys, the note format, the
;; export profiles and the results graph are the same in both modes,
;; because they are properties of the archive rather than of the person
;; sitting in front of it.

(defconst cerebro-modes
  '((math
     :describe "study the archive, write mathematics, compile documents"
     :sign     "∫"
     :ascii    "M"
     ;; The archive and the two things that are part of it. Handed
     ;; straight to `cerebro-isolation-writable-directories', so the
     ;; guard rail's policy and this mode's definition are one datum.
     :writable ("notes" "issues" "bib")
     ;; A note opens in the working mode: rendered, with the formula at
     ;; point turned back into source (see cerebro-study.el).
     :study    write
     ;; Issues about the mathematics rather than about the tooling. The
     ;; area taxonomy comes in through `:issue-tag-functions' below, so a
     ;; new area is mathematical work the day it is added and nobody has
     ;; to remember to repeat it here.
     :issue-tags ("math" "research" "rigor" "formal" "proof" "notes"
                  "course" "conjecture" "msc" "drill" "study")
     :issue-tag-functions (cerebro-taxonomy-all-tags)
     ;; nil = the start page's default rows (`cerebro-dashboard-key-rows'),
     ;; which are already the mathematician's keys -- writing a theorem,
     ;; reading it back, compiling it. The default *is* math, because that
     ;; is what this editor is for.
     :keys nil)
    (dev
     :describe "maintain the machinery: modules, tools, tests, classes"
     :sign     "λ"
     :ascii    "D"
     ;; Everything. `cerebro-mode-apply' reads this one value as "turn the
     ;; guard rail off" rather than as a list of directories: in dev the
     ;; machinery is exactly what you came to edit, and having to `C-c H u'
     ;; each file would be a ritual, not a safeguard.
     :writable :everything
     ;; Source, not `write': a note opened in dev mode is being opened
     ;; because the linter, the exporter or the hash disagreed with it,
     ;; and then the only useful view is the bytes.
     :study    source
     :issue-tags ("dev" "build" "ci" "test" "tests" "guix" "bootstrap"
                  "emacs" "elisp" "ui" "cli" "tooling" "latex" "export"
                  "graph" "viz" "results" "bib" "backup" "perf" "docs"
                  "caveat")
     :keys (("open"  ("C-c i"   . "issues")
                     ("C-c d x" . "next")
                     ("C-c h"   . "home"))
            ("work"  ("C-c g"   . "git")
                     ("C-c d I" . "new issue")
                     ("C-c d S" . "scan"))
            ("check" ("C-c d l" . "lint")
                     ("C-c d s" . "stats")
                     ("C-c G s" . "env"))
            ("find"  ("C-c f i" . "issues")
                     ("C-c f n" . "a note")
                     ("C-c f r" . "a result"))
            ("learn" ("C-c H m" . "modules")
                     ("C-c H k" . "keys")
                     ("C-c H b" . "the brief"))
            ("mode"  ("C-c M m" . "math")
                     ("C-c M t" . "toggle")
                     ("C-c M s" . "status")))))
  "The two macro-modes: NAME followed by a plist of what differs.

- `:describe'  one line, shown by `cerebro mode' and `C-c M s'
- `:sign'      the glyph for the status line, with `:ascii' as fallback
               (a missing glyph draws a box -- the lesson the start page
               already learned)
- `:writable'  the directories this Emacs may write, or `:everything'
- `:study'     the mode a note opens in (`cerebro-study-modes')
- `:issue-tags' the tags that mark an issue as this mode's work
- `:issue-tag-functions' functions contributing further such tags, so a
               vocabulary defined elsewhere (the area taxonomy) does not
               have to be copied here and kept in step
- `:keys'      start-page key rows, or nil for the default ones")

(defcustom cerebro-mode-default 'math
  "The mode a session starts in when nothing says otherwise.
`math' because that is what the archive is for: maintaining cerebro is
the exception, and the exception is the one you should have to ask for."
  :type '(choice (const math) (const dev))
  :group 'cerebro-mode)

(defvar cerebro-mode-current nil
  "The mode applied to this session, or nil before one has been.
Ask `cerebro-mode-active' rather than this variable: in a batch Emacs --
which is how the shell tools read the mode -- nothing has been applied,
and the answer is still well defined.")

;; -- Pure lookups -------------------------------------------------------

(defun cerebro-mode-names ()
  "Every mode name, in declaration order. Pure."
  (mapcar #'car cerebro-modes))

(defun cerebro-mode-spec (mode)
  "The plist for MODE, or nil if there is no such mode. Pure."
  (cdr (assq mode cerebro-modes)))

(defun cerebro-mode-p (mode)
  "Non-nil when MODE names one of `cerebro-modes'. Pure."
  (and (cerebro-mode-spec mode) t))

(defun cerebro-mode-get (mode key)
  "Property KEY of MODE. Pure."
  (plist-get (cerebro-mode-spec mode) key))

(defun cerebro-mode-other (mode)
  "The mode that is not MODE. Pure.
Binary on purpose: with exactly two modes, \"the other one\" is a
question with an answer, which is what makes `C-c M t' a toggle rather
than a menu."
  (car (seq-remove (lambda (name) (eq name mode)) (cerebro-mode-names))))

(defun cerebro-mode-parse (value)
  "VALUE (a string, symbol or nil) as a known mode name, or nil. Pure.
Whitespace and case are forgiven because this reads a state file and an
environment variable, both of which people type into."
  (let* ((text (cond ((null value) nil)
                     ((symbolp value) (symbol-name value))
                     ((stringp value) value)))
         (name (and text (string-trim (downcase text)))))
    (when (and name (not (string-empty-p name)))
      (let ((symbol (intern name)))
        (and (cerebro-mode-p symbol) symbol)))))

;; -- Which issues are this mode's work ----------------------------------
;; The tracker is one file for both jobs (invariant 2: one source of truth
;; per domain), so the split is by tag rather than by file.
;;
;; The rule has one subtlety, and it is the important part: an issue that
;; carries NO tag from either family belongs to BOTH modes. Filtering here
;; must never be able to lose work -- an issue you cannot see is an issue
;; you conclude you never filed, which is the same failure the note finder
;; refuses (cerebro-find.el). So the filter hides exactly the issues that
;; explicitly say they are the *other* job, and nothing else.

(defun cerebro-mode-tags (mode)
  "Every issue tag that marks an issue as MODE's work. Pure-ish.
The `:issue-tag-functions' are called, so a vocabulary owned elsewhere
\(the area taxonomy) is read rather than copied."
  (append (cerebro-mode-get mode :issue-tags)
          (apply #'append
                 (mapcar (lambda (fn)
                           (and (fboundp fn) (copy-sequence (funcall fn))))
                         (cerebro-mode-get mode :issue-tag-functions)))))

(defun cerebro-mode-claims-p (mode tags)
  "Non-nil when TAGS contain a tag MODE claims. Pure."
  (let ((mine (cerebro-mode-tags mode)))
    (and (seq-some (lambda (tag) (member tag mine)) tags) t)))

(defun cerebro-mode-issue-p (tags &optional mode)
  "Non-nil when an issue tagged TAGS is work for MODE (default: the
current one). Pure.

Three cases, and the third is the one that matters:
  - TAGS name this mode          -> yes
  - TAGS name only the other one -> no
  - TAGS name neither            -> yes, for every mode. An unclassified
    issue is everybody's; hiding it would quietly shrink the backlog."
  (let ((mode (or mode (cerebro-mode-active))))
    (or (cerebro-mode-claims-p mode tags)
        (not (seq-some (lambda (other)
                         (and (not (eq other mode))
                              (cerebro-mode-claims-p other tags)))
                       (cerebro-mode-names))))))

(defun cerebro-mode-of-tags (tags)
  "The single mode TAGS belong to, or nil when they belong to both. Pure.
Used to *report* a classification (`cerebro issue list' says what it
filtered); the decision itself is `cerebro-mode-issue-p'."
  (let ((owners (seq-filter (lambda (mode) (cerebro-mode-claims-p mode tags))
                            (cerebro-mode-names))))
    (and (= (length owners) 1) (car owners))))

;; -- Where the mode is remembered ---------------------------------------
;; A one-word file under the gitignored var/ directory: the mode is a
;; property of this checkout on this machine, not of the archive, so it is
;; not committed -- and it is plain text so that the shell tools and Emacs
;; read the same byte rather than each keeping their own idea.

(defconst cerebro-mode-file
  (expand-file-name ".emacs.d/var/mode" cerebro-root)
  "Where the chosen mode is remembered between sessions.
Under var/ with the rest of Emacs' generated state (cerebro-session.el),
and gitignored: which job you are doing today is not part of the second
brain. The format is one word -- `math' or `dev' -- so that reading it
needs no parser in either language.")

(defun cerebro-mode-stored ()
  "The mode remembered in `cerebro-mode-file', or nil.
An unreadable or nonsense file is nil rather than an error: a corrupt
scrap of session state must not be able to stop the editor starting."
  (when (file-readable-p cerebro-mode-file)
    (cerebro-mode-parse
     (with-temp-buffer
       (insert-file-contents cerebro-mode-file nil 0 64)
       (buffer-string)))))

(defun cerebro-mode-store (mode)
  "Remember MODE in `cerebro-mode-file' for the next session."
  (make-directory (file-name-directory cerebro-mode-file) t)
  (with-temp-file cerebro-mode-file
    (insert (symbol-name mode) "\n"))
  mode)

(defun cerebro-mode-from-environment ()
  "The mode named by CEREBRO_MODE, or nil.
Set by `cerebro dev' / `cerebro math', which start one session in a mode
without changing what the next one does."
  (cerebro-mode-parse (getenv "CEREBRO_MODE")))

(defun cerebro-mode-resolve ()
  "The mode this session should start in, and where the answer came from.
Returns (MODE . SOURCE) with SOURCE one of `environment', `stored' or
`default' -- reported by `C-c M s', because \"why am I in dev?\" is the
only question a persistent setting ever raises."
  (or (when-let* ((mode (cerebro-mode-from-environment))) (cons mode 'environment))
      (when-let* ((mode (cerebro-mode-stored))) (cons mode 'stored))
      (cons cerebro-mode-default 'default)))

(defun cerebro-mode-active ()
  "The mode in force: the applied one, or the one that would be applied."
  (or cerebro-mode-current (car (cerebro-mode-resolve))))

;; -- How it looks -------------------------------------------------------

(defvar cerebro-mode-lighter nil
  "The status-line label for `cerebro-mode-current'.
Computed once when a mode is applied rather than per redisplay: the
status line is drawn a hundred times a second while scrolling, and
`char-displayable-p' is not a question whose answer changes in between
\(the same argument cerebro-modeline.el makes for its bounded searches).")

(defun cerebro-mode-label (mode)
  "MODE's mark: its glyph when the font has one, else its ASCII letter.
Pure but for the font question, exactly like `cerebro-dashboard-sign' --
a glyph a font does not have is drawn as an empty box, which is worse
than a letter."
  (let ((sign (cerebro-mode-get mode :sign))
        (ascii (cerebro-mode-get mode :ascii)))
    (if (and sign (display-graphic-p)
             (char-displayable-p (string-to-char sign)))
        sign
      (or ascii (symbol-name mode)))))

;; -- Applying one -------------------------------------------------------

(defvar cerebro-mode-hook nil
  "Functions run with one argument, the mode, after it has been applied.

The seam. `cerebro-mode-apply' configures the modules it knows about by
setting variables *if they are bound*; anything else that wants to react
to the mode adds itself here instead of being named in this file. That is
what lets this module stay free of Org, of the dashboard and of the
optional packages while still switching them.")

(defun cerebro-mode--apply-isolation (mode)
  "Point cerebro-isolation.el at what MODE may write.
`:everything' switches the guard rail off wholesale -- in dev the
machinery IS the work. Guarded by `boundp' so this module never has to
require the one it configures."
  (let ((writable (cerebro-mode-get mode :writable)))
    (when (boundp 'cerebro-isolation-enabled)
      (setq cerebro-isolation-enabled (not (eq writable :everything))))
    (when (and (consp writable) (boundp 'cerebro-isolation-writable-directories))
      (setq cerebro-isolation-writable-directories writable))))

(defun cerebro-mode--reprotect-buffers ()
  "Re-apply the writability policy to files already open.

Without this, switching to dev leaves every module you had open still
read-only and switching back leaves them writable -- the setting would
apply to the future only, which for a guard rail is the wrong half.

Two asymmetries, both deliberate: a buffer is only *unlocked* when the
file is genuinely writable on disk (a checkout of someone else's tree
stays read-only), and a buffer outside the repository is never touched --
`cerebro-isolation-writable-p' already says so, and this is a policy
about not damaging cerebro, not a claim on the session."
  (when (fboundp 'cerebro-isolation-writable-p)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and buffer-file-name
                   (string-prefix-p (file-name-as-directory
                                     (expand-file-name cerebro-root))
                                    (expand-file-name buffer-file-name)))
          (let ((protect (and (bound-and-true-p cerebro-isolation-enabled)
                              (not (cerebro-isolation-writable-p buffer-file-name)))))
            (cond (protect (setq buffer-read-only t))
                  ((file-writable-p buffer-file-name)
                   (setq buffer-read-only nil)))))))))

;;;###autoload
(defun cerebro-mode-apply (&optional mode)
  "Put this session into MODE (default: `cerebro-mode-resolve').
The one function that knows how any of the switching is done. Returns the
mode applied."
  (interactive)
  (let ((mode (or mode (car (cerebro-mode-resolve)))))
    (unless (cerebro-mode-p mode)
      (user-error "cerebro-mode: unknown mode `%s' (know: %s)" mode
                  (mapconcat #'symbol-name (cerebro-mode-names) ", ")))
    (setq cerebro-mode-current mode)
    (setq cerebro-mode-lighter (cerebro-mode-label mode))
    (cerebro-mode--apply-isolation mode)
    (cerebro-mode--reprotect-buffers)
    ;; The note-level mode a file opens in. Set only when cerebro-study is
    ;; loaded; buffers already open keep the mode they are in, because
    ;; re-rendering every open note on a mode switch would be a surprise
    ;; that costs a LaTeX run per formula.
    (when (and (boundp 'cerebro-study-default) (cerebro-mode-get mode :study))
      (setq cerebro-study-default (cerebro-mode-get mode :study)))
    (run-hook-with-args 'cerebro-mode-hook mode)
    (force-mode-line-update t)
    mode))

;;;###autoload
(defun cerebro-mode-switch (mode &optional session-only)
  "Switch to MODE and remember it for the next session.
With a prefix argument (SESSION-ONLY), change this session only and leave
`cerebro-mode-file' alone -- for the ten minutes of maintenance in the
middle of a morning of mathematics."
  (interactive
   (list (intern (completing-read
                  "Mode: "
                  (mapcar (lambda (row)
                            (format "%s" (car row)))
                          cerebro-modes)
                  nil t))
         current-prefix-arg))
  (cerebro-mode-apply mode)
  (unless session-only (cerebro-mode-store mode))
  (message "cerebro: %s -- %s%s"
           mode (cerebro-mode-get mode :describe)
           (if session-only " (this session only)" ""))
  mode)

;;;###autoload
(defun cerebro-mode-math (&optional session-only)
  "Switch to `math': the archive is writable, the machinery is not."
  (interactive "P")
  (cerebro-mode-switch 'math session-only))

;;;###autoload
(defun cerebro-mode-dev (&optional session-only)
  "Switch to `dev': every file in the repository is writable."
  (interactive "P")
  (cerebro-mode-switch 'dev session-only))

;;;###autoload
(defun cerebro-mode-toggle (&optional session-only)
  "Switch to whichever mode this session is not in."
  (interactive "P")
  (cerebro-mode-switch (cerebro-mode-other (cerebro-mode-active)) session-only))

;; -- Saying where you are -----------------------------------------------

(defun cerebro-mode-report-lines (&optional mode)
  "MODE as report lines: what it is, what it lets you write, what it
shows. Pure (bar the resolution of where the current value came from), so
the shell report and `C-c M s' print the same words."
  (let* ((resolved (cerebro-mode-resolve))
         (mode (or mode (cerebro-mode-active)))
         (writable (cerebro-mode-get mode :writable)))
    (list (format "%s  %s" mode (cerebro-mode-get mode :describe))
          ""
          (format "  writable   %s"
                  (if (eq writable :everything)
                      "everything in the repository (the guard rail is off)"
                    (mapconcat (lambda (d) (concat d "/")) writable " ")))
          (format "  notes open %s" (or (cerebro-mode-get mode :study) "-"))
          (format "  issues     tagged %s"
                  (mapconcat #'identity (cerebro-mode-get mode :issue-tags) " "))
          (format "             plus %d area tags, and everything untagged"
                  (length (apply #'append
                                 (mapcar (lambda (fn) (and (fboundp fn) (funcall fn)))
                                         (cerebro-mode-get mode :issue-tag-functions)))))
          ""
          (format "  in force   %s (from the %s)" (car resolved) (cdr resolved))
          (format "  remembered %s"
                  (or (cerebro-mode-stored) "nothing yet -- the default applies"))
          ""
          (format "  the other  %s -- %s"
                  (cerebro-mode-other mode)
                  (cerebro-mode-get (cerebro-mode-other mode) :describe)))))

;;;###autoload
(defun cerebro-mode-status ()
  "Report the mode in force, what it permits, and where it came from."
  (interactive)
  (cerebro-report (format "cerebro mode -- %s" (cerebro-mode-active))
                  (cerebro-mode-report-lines)
                  #'identity
                  "*cerebro-mode*"))

(provide 'cerebro-mode)
