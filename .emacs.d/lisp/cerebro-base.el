;;; cerebro-base.el --- where things are, with nothing loaded to say so -*- lexical-binding: t; -*-

;; The paths of the archive, the list of what counts as a note, and the
;; one report buffer -- the handful of answers that every other module
;; needs and that none of them should have to load Org to get.
;;
;; This file exists because of a measurement. CLAUDE.md's invariant 4
;; says pure logic lives in modules that "need no Guix package, so it is
;; unit-testable and works outside Guix", and names cerebro-results.el
;; and cerebro-hash.el among them. Their *logic* was pure; their
;; *modules* were not, because both did `(require 'cerebro-org)' for a
;; directory name and a file lister -- and cerebro-org.el loads org,
;; org-agenda, org-id, org-refile and ispell. Measured:
;;
;;     (require 'cerebro-results)      384 ms
;;     the work it then does            33 ms cold, 4 ms cached
;;
;; So `cerebro results check' spent about ninety per cent of its life
;; loading an agenda in order to run a line-based string parser. Every
;; shell entry point paid it: `cerebro results', `cerebro note rehash',
;; and anything else reaching for the pure layer from outside Emacs.
;;
;; The split is along the line invariant 4 already draws. What is here
;; is what a *file path* is; what stays in cerebro-org.el is what an
;; *Org buffer* is. Nothing here requires org, and a test asserts that.

(require 'seq)
(require 'subr-x)
(require 'cerebro-cache) ;; the tree is walked once, not once per question

;; `org-directory' is Org's variable and is set here, before Org is
;; loaded, on purpose: `defcustom' leaves an already-bound value alone,
;; so Org picks this up when it eventually loads, and the modules that
;; never load Org still get an answer. Declared first so setting it is
;; not a free-variable assignment.
(defvar org-directory)

(defvar cerebro-root
  (expand-file-name "../.." (file-name-directory (or load-file-name buffer-file-name)))
  "Root of the cerebro repository.")

(defconst cerebro-pure-modules
  '(cerebro-base cerebro-cache cerebro-results cerebro-hash
    cerebro-graph cerebro-msc cerebro-taxonomy cerebro-mode)
  "The modules that must stay free of Org and of every Guix package.

CLAUDE.md's invariant 4 in one datum, rather than in three copies of the
same list. Two things read it and would otherwise each keep their own:
`cerebro-base-test-pure-modules-do-not-load-org', which loads each in a
subprocess and checks Org did not come with it, and `make compile', which
byte-compiles exactly these with warnings promoted to errors -- a
free-variable warning in a module that claims to depend on nothing is the
first symptom of the dependency creeping back in.

The rest of the config is not listed here and is not compiled strictly:
outside the pinned environment those modules legitimately reference
variables of packages that are not installed (invariant 4's other half --
they degrade rather than fail), and a gate that fires on that would be a
gate that is always red.

`cerebro-org-free-modules' below is the weaker, wider tier: may use a
Guix package, still must not load Org.")

(defconst cerebro-org-free-modules
  (append cerebro-pure-modules
          '(cerebro-guix cerebro-theme cerebro-focus cerebro-help
            cerebro-find cerebro-isolation cerebro-keys cerebro-crypt
            cerebro-backup cerebro-cli cerebro-session cerebro-vc))
  "Every module that must load without pulling in Org.

The tier between `cerebro-pure-modules' and the rest. A module here may
use a Guix package and may draw on the display -- what it may not do is
load Org, because it has nothing to do with Org and Org is expensive:
cerebro-org.el pulls org, org-agenda, org-id, org-refile and ispell,
about 340ms, and it pulls them for *everything downstream*.

This list exists because a comment could not hold the line. cerebro-guix
requires only `cerebro-root', `cerebro-report' and `org-directory' --
all defined here -- and its own header says it is \"pure Elisp on Emacs
core, deliberately\", because it has to work outside the environment it
exists to explain. It nevertheless did `(require \\='cerebro-org)', with
a comment naming the three base symbols beside it: the symbols had moved
down a layer and the `require' never followed. Nothing noticed, because
nothing was looking.

The cost was not paid by cerebro-guix. `cerebro-guix-soft-require' is
the one way any module may reach a guix.scm package, so fourteen modules
require it -- and the whole presentation layer, which never mentions
Org, was loading an agenda and a spell-checker to draw a modeline.
Measured cold, one process per module:

    cerebro-guix     375ms -> 72ms      cerebro-focus  446ms -> 175ms
    cerebro-theme    485ms -> 169ms

Three others said `;; cerebro-root' on the same wrong `require' and were
freed with it: cerebro-backup, cerebro-cli, cerebro-session, cerebro-vc.

What is deliberately NOT here, though a symbol-level reading says it
could be: cerebro-latex, cerebro-course and cerebro-preview. They use no
symbol from cerebro-org, but they depend on what it *configures* --
`org-use-sub-superscripts' decides how a subscript is typeset, and
`org-id-locations-file' is how the course composer resolves every `id:'
link. Dropping the require there would not fail; it would quietly change
a PDF, which is worse. A dependency on configuration is still a
dependency.")

(setq org-directory (expand-file-name "notes" cerebro-root))

(defconst cerebro-math-directory (expand-file-name "math" org-directory)
  "Where mathematical notes live: notes/math/.

The notes tree has one directory per *kind* of writing, because they have
different lifecycles: `math/' is the permanent concept graph (a note per
definition, theorem, construction -- the thing this repo exists for),
`courses/' is one file per course (an index into this one), and
`conjectures/' is `cerebro-conjecture-directory' below. Only this one is
a default anywhere: it is where a new note goes
unless you say otherwise (`C-c m ...', `cerebro note new', the org-roam
capture templates -- and bin/cerebro-note mirrors this path, deliberately
duplicated there so the shell tools need no Emacs).

Nothing *requires* a note to be here: `cerebro-note-files' walks the whole
tree, so the graph, the agenda, the linter and every query keep seeing a
note wherever it sits.")

(defconst cerebro-conjecture-directory (expand-file-name "conjectures" org-directory)
  "Where conjectures live: notes/conjectures/.

A conjecture is a different *kind* of writing from a result, not a
result with a tag: it is mine, it is unproved, and its lifecycle is
\"argue with it for years\" rather than \"state it and move on\". Keeping
them in their own directory is what makes `what have I actually
conjectured?' a question with an answer -- and what lets the whole
directory be typeset as one two-column article (the `conjecture' export
profile) without picking through the concept graph for the ones that
qualify.

Named notes all the same: a conjecture is hash-named exactly like a note
in math/ (cerebro-hash.el owns both directories), it carries an `:ID:',
and the results graph reads its `#+NAME'd blocks -- so a theorem
elsewhere may cite it, and `cerebro results open' counts it among what
the archive owes.")

(defconst cerebro-bib-file (expand-file-name "bib/references.bib" cerebro-root)
  "THE bibliography: one file, for the whole archive.

Singular on purpose. A reference is a fact about the literature, not
about the document that happens to cite it, and the moment there are two
.bib files the same book acquires two keys and the archive stops being
able to answer \"where else did I read this?\". Defined here, in the base
module, because three layers need the same answer and none of them
should own it: the exporter (`org-cite-global-bibliography'), the
editing surface (cerebro-bib.el, citar) and the linter, which fails a
push on a `[cite:@key]' this file does not define.

latex/cerebro.cls finds the same file through BIBINPUTS.")

;; -- What counts as a note ----------------------------------------------

(defun cerebro-note-directories (&optional dir)
  "DIR (default `org-directory') plus every subdirectory under it.
`org-agenda-files' expands a *directory* entry only to the .org files
directly inside it -- it does NOT recurse -- so a lifelong tree like
notes/courses/ and notes/conjectures/ is invisible to the agenda,
the morning review, and org-drill (whose scope is `agenda') unless
every subdirectory is listed. Listing directories rather than a frozen
file list keeps Org's own re-scan: a note dropped into any known dir
shows up in the agenda with no reload.

`.build/' is excluded, for the same reason `cerebro-not-a-note-regexp'
excludes it from `cerebro-note-files': what is in there is *derived* --
a course composed for export, full of `#+INCLUDE' lines pointing at the
notes it was made from. Leaving it in was a real bug, and an
extraordinarily confusing one: this list feeds `org-agenda-files', so a
composition left over from a previous export was scanned like a note,
and the first export after any note was renamed died with `Cannot
include file .../<the previous digest>.org' -- naming a file that had
just ceased to exist, from a stale artefact nobody had thought of as
input. The sibling function excluded build output and this one did not;
one of them was wrong."
  (let ((root (or dir org-directory)))
    (cons root
          (seq-remove
           (lambda (d) (string-match-p "/\\.build\\'\\|/\\.build/" d))
           (seq-filter #'file-directory-p
                       (directory-files-recursively root "" t))))))

(defconst cerebro-not-a-note-regexp
  "/\\(\\.build/\\|README\\.org\\'\\)"
  "Paths under notes/ that are not notes.

Two kinds, and the first is the one that bites: anything inside a
`.build/' directory is *derived* -- a course composed for export is a
real .org file full of #+INCLUDEs, and counting it would double every
note it pulls in, in the stats, in the graph and in the linter. The
second is this repository talking about itself.")

(defun cerebro-note-file-p (file)
  "Non-nil when FILE is a real note rather than a build product or a README.

`cerebro-not-a-note-regexp' as a *predicate*, because a regexp nobody can
apply is a definition three callers will each re-derive -- and each of
them got it wrong. Every one listed a directory itself
\(`directory-files') instead of asking here, so the archive's own answer
to \"what is a note\" stopped at the edge of `cerebro-note-files':

  - `cerebro-hash-rehash-directory' renamed notes/conjectures/README.org
    to a digest and wrote a `#+HASH:' line into it -- while the shell
    twin, `cerebro note rehash', skipped it. Two implementations of one
    operation, disagreeing about a file.
  - `C-c f j' offered that same README as the only conjecture there is.
  - `cerebro-course-file-p' called notes/courses/README.org a course, so
    `C-c e c' would try to build four documents out of it.

The file name is expanded first: the regexp is anchored on the `/' before
the name, so a bare \"README.org\" would otherwise pass."
  (and file
       (string-suffix-p ".org" file)
       (not (string-match-p cerebro-not-a-note-regexp (expand-file-name file)))))

(defun cerebro-note-files--uncached (dir)
  "The real work behind `cerebro-note-files'."
  (seq-filter #'cerebro-note-file-p
              (directory-files-recursively dir "\\.org\\'")))

(defun cerebro-note-files (&optional dir)
  "Every real note file under DIR (default `org-directory'), recursively.
All .org files minus the non-note ones (`cerebro-not-a-note-regexp':
build products and the headingless READMEs). This
is the single definition of \"where the prose notes are\" -- reused by the
org-ql search surface (cerebro-ql.el) so it can't drift out of sync with
the agenda's directory entries.

Memoised on the *directories'* mtimes (cerebro-cache.el): a file created,
deleted or renamed changes the mtime of the directory holding it, which
is exactly when this listing changes -- and it is one stat per directory
instead of a full recursive walk per caller."
  (let ((dir (or dir org-directory)))
    (cerebro-cache-get
     (list 'note-files dir)
     (cerebro-cache-directory-signature (cerebro-note-directories dir))
     (lambda () (cerebro-note-files--uncached dir)))))

;; -- The one report buffer ----------------------------------------------

(defun cerebro-report (title rows format-row &optional buffer-name)
  "Show ROWS (already sorted/filtered) in a simple read-only report
buffer. TITLE heads it, FORMAT-ROW turns one row into a line,
BUFFER-NAME defaults to *cerebro*. The one report primitive shared by
cerebro-query.el (graph structure) and cerebro-results.el (the results
layer), so every cerebro report looks and behaves the same -- `q' buries
it (special-mode)."
  (let ((buf (get-buffer-create (or buffer-name "*cerebro*"))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%s\n%s\n\n" title (make-string (length title) ?=)))
        (if (not rows)
            (insert "(nothing found)\n")
          (dolist (r rows) (insert (funcall format-row r) "\n"))))
      (goto-char (point-min))
      (special-mode))
    (display-buffer buf)))

(provide 'cerebro-base)
