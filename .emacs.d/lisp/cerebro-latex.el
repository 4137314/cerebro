;;; cerebro-latex.el --- parametric LaTeX export pipeline -*- lexical-binding: t; -*-

;; One Org source, four documents -- controlled at export time, never by
;; duplicating content. Two independent, orthogonal axes, composed as
;; data (this IS the "parametric macro system": adding a new export
;; configuration is one alist line, not new code):
;;
;;   content mode   -- which blocks survive the export (full, lecture,
;;                     slides, single)
;;   doctype        -- which class/class-option combination typesets it
;;                     (article/book/syllabus all use latex/cerebro.cls;
;;                     beamer uses latex/cerebro-beamer.cls via Org's own
;;                     ox-beamer backend)
;;
;; There are exactly four course documents, because a course has exactly
;; four audiences, and every extra variant was a document nobody read.
;; All four come from the ONE file that is the course
;; (notes/courses/<slug>.org, see cerebro-course.el):
;;
;;   syllabus   what the course is        <- the course file itself
;;   lecture    what I say at the board   <- + the notes it indexes
;;   slides     what the room sees        <- + the notes it indexes
;;   handbook   what the students keep    <- + the notes, appendices, index
;;
;; and two profiles that are not course documents at all: `conjecture'
;; (notes/conjectures/, two-column) and `single' (one #+NAME'd result on
;; its own page, `C-c e r', for reading one theorem).
;;
;; Named profiles below are just (content . doctype) pairs. Pairs with
;; latex/cerebro.cls and latex/cerebro-beamer.cls, which define the
;; actual proofs/noproofs and article/book switches, and with
;; latex/cerebro-macros.sty, the single source of truth for notation
;; shared by both classes.
;;
;; Convention for note authors: never set #+LATEX_CLASS,
;; #+LATEX_CLASS_OPTIONS or #+EXCLUDE_TAGS in a note file. Those are
;; file-local export settings and, per Org's own precedence rules,
;; would silently win over the per-export overrides this file installs
;; -- which would make profile selection stop doing anything, silently.
;; For the `single' content mode: give the target block a #+NAME and
;; export with an explicit target (see `cerebro-latex-export-to-pdf');
;; only an immediately following sibling `proof' block is kept with it
;; -- not a general dependency graph.

(require 'cl-lib)
(require 'ox-latex)
(require 'ox-beamer)
(require 'org-element)
(require 'oc)
(require 'oc-biblatex)
(require 'cerebro-org)
(require 'cerebro-results) ;; cerebro-results-types: what counts as a result

;; Citations: [cite:@key] in Org -> \autocite{key} via org-cite's own
;; biblatex export processor (built into Org core since 9.5, no new
;; package). The one bibliography (`cerebro-bib-file', cerebro-org.el),
;; like the notation in cerebro-macros.sty -- and the same file the
;; linter checks every citation key against.
(setq org-cite-global-bibliography (list cerebro-bib-file))
(setq org-cite-export-processors '((latex biblatex) (t basic)))

;; Compile strictly and correctly. `latexmk' drives the whole
;; pdflatex/biber/pdflatex loop by itself -- so citations ([cite:@key])
;; and cross-references (cleveref) resolve in a single `make export',
;; with no hand-counted passes -- and it auto-detects biber from the
;; biblatex .bcf. Crucially, `-halt-on-error' makes a *real* LaTeX error
;; FAIL the export (no PDF -> Org signals an error) instead of Org's
;; default `-interaction=nonstopmode' alone, under which TeX "inserts a $
;; and proceeds", shipping a malformed PDF the pipeline would wrongly
;; treat as success. That silent-failure mode is exactly what the
;; naked-`$' linter check (bin/notes-lint.el) now prevents at the source;
;; this makes the compile itself honest as a second line of defence. Both
;; the generic LaTeX backend and ox-beamer share `org-latex-pdf-process'.
(setq org-latex-pdf-process
      (list (concat "latexmk -pdf -halt-on-error "
                    "-interaction=nonstopmode -output-directory=%o %f")))

(defvar cerebro-latex-content-modes
  '((full     . (:exclude-blocks nil))
    ;; What I say at the board: the statements and the proofs, and
    ;; nothing that is an aside. A remark, a worked example or an
    ;; exercise is an `approfondimento' -- it belongs in the handbook the
    ;; students read at home, not in the notes I hold while teaching.
    (lecture  . (:exclude-blocks ("remark" "example" "exercise" "hint" "solution")))
    ;; What the room sees. Two filters, because a slide overflows for two
    ;; different reasons: `:only-blocks' keeps the *statements* alone (no
    ;; proof, no aside), and `:prune-prose' drops the connecting prose
    ;; around them -- the paragraphs that make a note readable are exactly
    ;; what makes a slide unreadable. Say the prose; project the statement.
    (slides   . (:only-blocks ("definition" "theorem" "lemma" "proposition"
                               "corollary" "axiom" "notation" "conjecture")
                 :prune-prose t))
    (single   . (:exclude-blocks nil :single t)))
  "Which special blocks survive an export, as `:exclude-blocks' (drop
these types) or `:only-blocks' (keep only these), plus `:prune-prose'
(drop the paragraphs between them). `single' is special-cased: see
`cerebro-latex--extract-single'.")

(defvar cerebro-latex-doctypes
  '((article   . (:class "cerebro"           :class-options "article"))
    ;; The handbook loads scrbook, which has \chapter -- so it uses the
    ;; chaptered sectioning map below. A course book is the case that made
    ;; this visible: its top level is a *chapter* of the programme, and
    ;; mapping it to \section numbered every result "0.1.1" (sections
    ;; before a chapter that never comes). `index' turns on the analytical
    ;; index (makeidx) that only a bound book has a use for.
    (book      . (:class "cerebro-chaptered" :class-options "book,index"))
    (syllabus  . (:class "cerebro"           :class-options "syllabus"))
    ;; Two columns, for conjectures: a page of open questions is a page of
    ;; short, self-contained statements, which is exactly what the
    ;; narrow measure of a two-column article is for. `twocolumn' is
    ;; KOMA's own option and reaches scrartcl through cerebro.cls's
    ;; \DeclareOption* passthrough.
    (twocolumn . (:class "cerebro"           :class-options "article,twocolumn"))
    (beamer    . (:class "cerebro-beamer"    :class-options "")))
  "Which class/class-options combination typesets an export.")

(defvar cerebro-latex-profiles
  '((syllabus   . (:content full    :doctype syllabus))  ; typeset a course
    (lecture    . (:content lecture :doctype article))   ; my notes for teaching
    (slides     . (:content slides  :doctype beamer))    ; the minimal deck
    (handbook   . (:content full    :doctype book))      ; the course textbook
    (conjecture . (:content full    :doctype twocolumn)) ; notes/conjectures/
    (single     . (:content single  :doctype article)))  ; one result, on its own
  "Named presets: what the user passes as PROFILE=... to `make export'.
Each entry composes one entry from `cerebro-latex-content-modes' with
one from `cerebro-latex-doctypes' -- adding a new named preset is a
one-line addition here, not new code.

Deliberately short. This used to carry fourteen entries (report, manual,
dispensa, handout, paper, preprint, exercises, problems, and two
aliases), which is thirteen documents to keep compiling and four a
course actually hands to anyone. What is here is one document per
*audience*, plus two that are not course documents at all: `conjecture'
(a page of open questions of my own, two-column) and `single' (one
result, for reading).")

(defvar cerebro-latex--exclude-blocks nil
  "Special block type names (strings) to strip from the current export.
Dynamically let-bound by `cerebro-latex-export-to-pdf'.")

(defvar cerebro-latex--only-blocks nil
  "When non-nil, a list of special-block type names (strings); every
special block whose type is NOT in the list is stripped. The inverse of
`cerebro-latex--exclude-blocks' (a profile sets one or the other, never
both). Dynamically let-bound by `cerebro-latex-export-to-pdf'.")

(defvar cerebro-latex--single-target nil
  "When non-nil, keep only the #+NAME'd block matching this string (plus
an immediately following sibling `proof' block), discarding every
other sibling. Dynamically let-bound by `cerebro-latex-export-to-pdf'.")

(defvar cerebro-latex--prune-prose nil
  "When non-nil, drop the note's connecting prose (see
`cerebro-latex--prune-prose-paragraphs'). Set by the `slides' content
mode; dynamically let-bound by `cerebro-latex-export-to-pdf'.")

(defun cerebro-latex--alist-get (key alist what)
  (or (cdr (assq key alist))
      (error "cerebro-latex: unknown %s `%s' (known: %s)"
             what key (mapcar #'car alist))))

(defun cerebro-latex--profile (name)
  (cerebro-latex--alist-get name cerebro-latex-profiles "export profile"))

(defun cerebro-latex--content-mode (name)
  (cerebro-latex--alist-get name cerebro-latex-content-modes "content mode"))

(defun cerebro-latex--doctype (name)
  (cerebro-latex--alist-get name cerebro-latex-doctypes "doctype"))

(defun cerebro-latex--class-options (doctype-name has-proofs has-solutions)
  "The [class-options] string for DOCTYPE-NAME.
The proofs/solutions toggles cerebro.cls and cerebro-beamer.cls
understand, then the doctype's own option (beamer has none, and an empty
component would be a trailing comma LaTeX chokes on)."
  (let* ((doctype (cerebro-latex--doctype doctype-name))
         (extra (plist-get doctype :class-options))
         (parts (append
                 (list (if has-proofs "proofs" "noproofs")
                       (if has-solutions "solutions" "nosolutions"))
                 (unless (string-empty-p extra) (list extra))))
         (inner (mapconcat #'identity parts ",")))
    (if (string-empty-p inner) "" (format "[%s]" inner))))

(defun cerebro-latex--block-type (element)
  "The cerebro block type of ELEMENT, as the content modes name it.

`#+begin_theorem' is an Org *special block* and answers with its own
type. `#+begin_example' is not: Org owns that name and parses it as an
`example-block' (verbatim text), which this pipeline reinterprets as the
theorem suite's `example' environment -- see
`cerebro-latex-example-filter'. Both halves of that convention have to
agree, or a profile that says it drops examples drops only some of them:
`lecture' excluded \"example\" for months and every `#+begin_example' in
the archive sailed straight through it, because nothing here had asked
Org what it thought the element was."
  (pcase (org-element-type element)
    ('special-block (downcase (or (org-element-property :type element) "")))
    ('example-block "example")))

(defconst cerebro-latex--block-element-types '(special-block example-block)
  "The element types a content mode's block filters act on.")

(defun cerebro-latex--strip-blocks (tree _backend _info)
  "Remove blocks whose type is in `cerebro-latex--exclude-blocks'."
  (when cerebro-latex--exclude-blocks
    (org-element-map tree cerebro-latex--block-element-types
      (lambda (block)
        (when (member (cerebro-latex--block-type block)
                      cerebro-latex--exclude-blocks)
          (org-element-extract-element block)))))
  tree)

(defun cerebro-latex--keep-only-blocks (tree _backend _info)
  "Remove every block whose type is NOT in `cerebro-latex--only-blocks'
-- the inverse of `cerebro-latex--strip-blocks'. Headings are left
untouched (a deck keeps its section structure); only unrelated blocks
are pruned."
  (when cerebro-latex--only-blocks
    (org-element-map tree cerebro-latex--block-element-types
      (lambda (block)
        (unless (member (cerebro-latex--block-type block)
                        cerebro-latex--only-blocks)
          (org-element-extract-element block)))))
  tree)

(defun cerebro-latex--extract-single (tree _backend _info)
  "Keep only the block named `cerebro-latex--single-target' plus an
immediately following sibling `proof' block; discard every other
sibling within its immediate parent. See the module commentary for
what this convention does and does not handle."
  (when cerebro-latex--single-target
    (let ((target (org-element-map tree 'special-block
                    (lambda (b)
                      (when (equal (org-element-property :name b)
                                   cerebro-latex--single-target)
                        b))
                    nil t)))
      (unless target
        (error "cerebro-latex: no block named `%s' for the `single' profile"
               cerebro-latex--single-target))
      (let* ((parent (org-element-property :parent target))
             (siblings (org-element-contents parent))
             (idx (cl-position target siblings))
             (next (nth (1+ idx) siblings))
             (keep (if (and next
                            (eq (org-element-type next) 'special-block)
                            (equal (downcase (or (org-element-property :type next) ""))
                                   "proof"))
                       (list target next)
                     (list target))))
        (dolist (sib siblings)
          (unless (memq sib keep)
            (org-element-extract-element sib)))
        ;; Also prune unrelated top-level content -- an intro paragraph
        ;; before the first heading, or sibling headings elsewhere in
        ;; the file -- so a "single theorem to study" export doesn't
        ;; drag along the whole file's front matter. Walk up from the
        ;; target to whichever ancestor is a direct child of the tree
        ;; root, and keep only that.
        (let ((ancestor target))
          (while (not (eq (org-element-type (org-element-property :parent ancestor))
                          'org-data))
            (setq ancestor (org-element-property :parent ancestor)))
          (dolist (top (org-element-contents tree))
            (unless (eq top ancestor)
              (org-element-extract-element top)))))))
  tree)

(defun cerebro-latex--prune-prose-paragraphs (tree _backend _info)
  "Remove the note's connecting prose when `cerebro-latex--prune-prose'.

A note is written to be *read*: a paragraph of motivation, the
statement, a paragraph saying what it is good for. Projected, that is a
wall of text nobody reads while someone is talking over it -- and the
single commonest cause of a frame overflowing its slide and colliding
with whatever comes next.

Only paragraphs whose parent is a `section' go: that is body prose,
sitting directly under a heading. A paragraph inside a list item, a
table cell or a special block has a different parent and stays, so the
statements themselves and any bulleted summary survive intact."
  (when cerebro-latex--prune-prose
    (org-element-map tree 'paragraph
      (lambda (paragraph)
        (when (eq (org-element-type (org-element-property :parent paragraph))
                  'section)
          (org-element-extract-element paragraph)))))
  tree)

;; -- The index nobody has to write --------------------------------------
;; A handbook ends with an analytical index (latex/cerebro.cls, `index'
;; class option), and the entries come from names that already exist: a
;; result called `def-supremum' indexes "supremum". Naming a definition
;; is something the archive already requires -- for the results graph and
;; for `single' exports -- so the index costs nothing to maintain and
;; cannot fall out of date. `#+INDEX: term' still works for the terms a
;; name cannot express; Org transcodes that itself.
;;
;; Emitted unconditionally, for every doctype. Whether there *is* an
;; index is the class's decision (it makes \index inert when there is
;; not), which is the same division of labour as proofs/noproofs: the
;; exporter says what the document contains, the class says how much of
;; it is typeset.

(defun cerebro-latex-index-entry (name)
  "The index entry a result called NAME contributes, or nil. Pure.
`def-supremum' -> \"supremum\", `thm-monotone-convergence' -> \"monotone
convergence\": the kind prefix is how the *graph* reads a name and is
noise in an index, and hyphens are how a file writes a space."
  (when (and name (string-match "\\`[a-z]\\{2,4\\}-\\(.+\\)\\'" name))
    (let ((entry (replace-regexp-in-string "-" " " (match-string 1 name))))
      (unless (string-empty-p entry) entry))))

(defun cerebro-latex--index-named-results (tree _backend _info)
  "Add an \\index entry for every named result block in TREE.

Collected first and inserted afterwards: `org-element-map' is walking
the tree, and adding siblings underneath it while it does is how you get
an element visited twice or not at all."
  (let (pending)
    (org-element-map tree cerebro-latex--block-element-types
      (lambda (block)
        (when-let* ((_ (member (cerebro-latex--block-type block)
                               cerebro-results-types))
                    (entry (cerebro-latex-index-entry
                            (org-element-property :name block))))
          (push (cons block entry) pending))))
    (dolist (row pending)
      (org-element-insert-before
       (org-element-create 'export-block
                           (list :type "LATEX"
                                 :value (format "\\index{%s}\n" (cdr row))
                                 :post-blank 0))
       (car row))))
  tree)

(add-to-list 'org-export-filter-parse-tree-functions #'cerebro-latex--strip-blocks)
(add-to-list 'org-export-filter-parse-tree-functions #'cerebro-latex--keep-only-blocks)
(add-to-list 'org-export-filter-parse-tree-functions #'cerebro-latex--prune-prose-paragraphs)
(add-to-list 'org-export-filter-parse-tree-functions #'cerebro-latex--extract-single)
;; Appended, not prepended: `add-to-list' puts a filter at the FRONT, and
;; this one has to see the tree the others left behind -- an \index entry
;; for a statement that the `slides' filter already removed is an entry
;; pointing at a page the term does not appear on.
(add-to-list 'org-export-filter-parse-tree-functions
             #'cerebro-latex--index-named-results t)

;; cleveref must load after hyperref. hyperref is one of Org's own
;; default export packages and is added to the preamble *after*
;; \documentclass processing (and hence after anything \RequirePackage'd
;; by latex/cerebro.cls / cerebro-beamer.cls) -- org-latex-packages-alist
;; entries are emitted after Org's defaults, which puts this after
;; hyperref too. Verified against a real compile, not assumed.
(add-to-list 'org-latex-packages-alist '("" "cleveref" nil) t)

(add-to-list 'org-latex-classes
             '("cerebro"
               "\\documentclass{cerebro}"
               ("\\section{%s}" . "\\section*{%s}")
               ("\\subsection{%s}" . "\\subsection*{%s}")
               ("\\subsubsection{%s}" . "\\subsubsection*{%s}")))

;; Same class file, chaptered: for the doctype whose base class (scrbook)
;; provides \chapter. Org maps outline level N to the Nth entry, so this
;; is the whole difference -- one datum per doctype in
;; `cerebro-latex-doctypes' chooses between the two.
(add-to-list 'org-latex-classes
             '("cerebro-chaptered"
               "\\documentclass{cerebro}"
               ("\\chapter{%s}" . "\\chapter*{%s}")
               ("\\section{%s}" . "\\section*{%s}")
               ("\\subsection{%s}" . "\\subsection*{%s}")
               ("\\subsubsection{%s}" . "\\subsubsection*{%s}")))

(add-to-list 'org-latex-classes
             '("cerebro-beamer"
               "\\documentclass{cerebro-beamer}"
               ("\\section{%s}" . "\\section*{%s}")
               ("\\subsection{%s}" . "\\subsection*{%s}")))


;; -- Who wrote it, and which version --------------------------------------
;; Two pieces of metadata every document should carry and no note should
;; have to repeat: the author, and where this copy came from in the
;; repository's history. Both are computed once, here, and injected into
;; the preamble of every cerebro-family export -- so a syllabus printed
;; today and a handbook printed next year can be told apart by looking at
;; them, which is the whole point of a version.

(defcustom cerebro-latex-author "Mattia Fait"
  "Name printed on the title page of every export.

A person's name, not an account handle: these documents are handed to
other people. Set to nil to fall back to git's `user.name' (which in this
repository is the forge account, `4137314' -- exactly the wrong thing on
a title page) and then to `user-full-name'."
  :type '(choice (const :tag "ask git" nil) string)
  :group 'cerebro)

(defun cerebro-latex--git (&rest args)
  "Run git with ARGS in the repository; return trimmed output or nil."
  (let ((default-directory cerebro-root))
    (with-temp-buffer
      (when (zerop (apply #'call-process "git" nil t nil args))
        (let ((output (string-trim (buffer-string))))
          (unless (string-empty-p output) output))))))

(defun cerebro-latex-author ()
  "The author name for a title page."
  (or cerebro-latex-author
      (cerebro-latex--git "config" "user.name")
      user-full-name))

(defun cerebro-latex-version ()
  "A version string for the title page, from git.

`git describe --tags --always --dirty' is exactly the right shape: the
last tag when there is one (`v2-14-g8a3f21'), the short commit when there
is not, and a `-dirty' suffix when the working tree has uncommitted
changes -- which is the honest thing to print on a PDF built from an
edit you have not committed."
  (or (cerebro-latex--git "describe" "--tags" "--always" "--dirty")
      "uncommitted"))

(defun cerebro-latex-metadata-header (&optional author version subject date)
  "The preamble lines carrying author, version, subject and date. Pure.

Every class in this family -- cerebro.cls and cerebro-beamer.cls alike
-- defines the \\cerebro... macros, which is the reason they are safe to
emit unconditionally. They were not always: a class that did not define
them met an injected \\cerebroauthor with `Undefined control sequence',
and the profile matrix (not a test) is what caught it. Adding a class to
this family means defining the four macros in it.

Empty strings are omitted rather than passed as empty macros, so a
document with no subject has no blank line where one would be."
  (concat
   (when (and author (not (string-empty-p author)))
     (format "\\cerebroauthor{%s}\n" author))
   (when (and version (not (string-empty-p version)))
     (format "\\cerebroversion{%s}\n" version))
   (when (and subject (not (string-empty-p subject)))
     (format "\\cerebrosubject{%s}\n" subject))
   (when (and date (not (string-empty-p date)))
     (format "\\cerebrodate{%s}\n" date))))

(defun cerebro-latex-format-date (raw &optional now)
  "A title-page date from RAW, the note's `#+DATE:'. Pure.

Org writes timestamps as `[2026-07-29 Wed 13:55]', which is exactly
right in a file and wrong on a title page: brackets, a weekday and a
time nobody needs. Anything that is not a timestamp is passed through
untouched (a note may well say `Autumn 2026'), and a note with no date
gets today's."
  (let ((raw (and raw (string-trim raw))))
    (cond
     ((and raw (string-match "\\`[[<]\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)" raw))
      (format-time-string
       "%e %B %Y"
       (encode-time 0 0 12
                    (string-to-number (match-string 3 raw))
                    (string-to-number (match-string 2 raw))
                    (string-to-number (match-string 1 raw)))))
     ((and raw (not (string-empty-p raw))) raw)
     (t (format-time-string "%e %B %Y" now)))))

(defun cerebro-latex--date ()
  "The current buffer's date, formatted for a title page."
  (cerebro-latex-format-date
   (cadr (assoc "DATE" (org-collect-keywords '("DATE"))))))

(defun cerebro-latex--subject ()
  "A subtitle for the title page, from the buffer's own keywords.
A course document says which course; a note says nothing, and gets no
subtitle rather than an invented one."
  (let* ((keywords (org-collect-keywords '("COURSE_TITLE" "SUBTITLE" "TERM")))
         (course (cadr (assoc "COURSE_TITLE" keywords)))
         (subtitle (cadr (assoc "SUBTITLE" keywords)))
         (term (cadr (assoc "TERM" keywords))))
    (string-trim
     (or subtitle
         (cond ((and course term) (format "%s -- %s" course term))
               (course course)
               (t ""))))))

;; -- Where the build happens ---------------------------------------------
;; LaTeX produces a dozen files per compile (.aux, .log, .fls, .fdb, the
;; .tex itself) and until now they landed next to the note. They are
;; gitignored, but a directory of mathematics should contain mathematics:
;; `ls notes/math/' answering with build rubbish is how a source tree
;; stops being readable.
;;
;; So every build happens in a `.build/' directory beside the source, and
;; the PDF stays there too. Nothing else in the config has to know: the
;; one function below is what everything asks (cerebro-pdf.el,
;; bin/cerebro-course-export).

(defconst cerebro-latex-build-directory ".build"
  "Directory name, relative to a source file, holding everything a
compile produces -- including the PDF.")

(defun cerebro-latex-build-dir (file)
  "The build directory for FILE -- which is FILE's own, when it is
already in one.

A composed course document (cerebro-course.el) is itself written into
`.build/' and then compiled, and without this rule its own build would
go to `.build/.build/' -- one directory deeper for every generation of
derived file. Build output is flat: one directory, per source
directory, holding everything derived from it."
  (let ((directory (file-name-directory (expand-file-name file))))
    (if (equal (file-name-nondirectory (directory-file-name directory))
               cerebro-latex-build-directory)
        (directory-file-name directory)
      (expand-file-name cerebro-latex-build-directory directory))))

(defun cerebro-latex-output-file (file &optional extension)
  "Where the compile of FILE puts its EXTENSION (default \"pdf\") output."
  (expand-file-name (concat (file-name-base file) "." (or extension "pdf"))
                    (cerebro-latex-build-dir file)))

(defun cerebro-latex--tidy-build (file)
  "Move what the compile of FILE produced into its build directory.

Org insists on finding the PDF next to the .tex it generated -- it is
how it decides the compile succeeded -- so the move happens afterwards
rather than by pointing LaTeX somewhere else. Returns the PDF's new
path."
  (let* ((build (cerebro-latex-build-dir file))
         (base (file-name-base file))
         (source-dir (file-name-directory (expand-file-name file)))
         (pdf (expand-file-name (concat base ".pdf") source-dir))
         (target (expand-file-name (concat base ".pdf") build)))
    (make-directory build t)
    (when (file-exists-p pdf) (rename-file pdf target t))
    ;; The .tex is generated too, and just as much build output as the
    ;; rest -- keeping it is useful (it is what you read when LaTeX
    ;; complains), keeping it *here* is not.
    ;; `idx'/`ind'/`ilg' are makeindex's (the handbook's analytical
    ;; index): missing from this list, they were the two files that
    ;; appeared in `git status' next to the notes after every handbook
    ;; build -- which is exactly the mess .build/ exists to prevent.
    (dolist (extension '("tex" "log" "aux" "out" "toc" "fls" "fdb_latexmk"
                         "bbl" "bcf" "blg" "run.xml" "nav" "snm" "vrb"
                         "idx" "ind" "ilg" "synctex.gz"))
      (let ((produced (expand-file-name (concat base "." extension) source-dir)))
        (when (file-exists-p produced)
          (rename-file produced (expand-file-name (concat base "." extension) build) t))))
    target))


;; -- `#+begin_example' means a mathematical example here -----------------
;; Org reserves `example' for *verbatim* text, so a note writing
;;
;;   #+begin_example
;;   The Taylor polynomials of \(\sin\) at \(0\) are ...
;;   #+end_example
;;
;; exported as a \begin{verbatim} block: the LaTeX printed literally,
;; backslashes and all, in a typewriter face. That is not a plausible
;; reading of what anyone meant -- and the theorem suite defines a real
;; `example' environment (cerebro-theorems.sty), numbered with the
;; definitions, which is obviously the intent.
;;
;; So the transcoded block has its wrapper swapped: same content, an
;; `example' environment instead of `verbatim'. Org emits the body
;; unescaped inside verbatim, which is exactly what a LaTeX environment
;; wants -- the maths simply starts working.
;;
;; The cost, stated plainly: a note cannot use `#+begin_example' for
;; literal text any more. Code goes in `#+begin_src' (which is untouched),
;; a quotation in `#+begin_quote'. In this archive nothing was using it
;; verbatim, and the two notes that did use it meant mathematics.

(defun cerebro-latex-example-filter (output _backend _info)
  "Turn a transcoded Org example block into the `example' environment."
  (when output
    ;; Literal replacements (the trailing t t), and explicit character
    ;; classes rather than `\s-': the syntax table in a batch export
    ;; buffer does not necessarily call a newline whitespace, which is
    ;; how the first version of this silently replaced nothing.
    ;; Unanchored: this filter only ever sees one example block, and Org
    ;; is free to put a label or a caption around the environment -- an
    ;; anchored match then silently rewrote the end and not the
    ;; beginning, which left TeX scanning for a `\end{verbatim}' that no
    ;; longer existed ("File ended while scanning use of \@xverbatim").
    (replace-regexp-in-string
     "\\\\begin{verbatim}" "\\begin{example}"
     (replace-regexp-in-string "\\\\end{verbatim}" "\\end{example}" output t t)
     t t)))

(add-to-list 'org-export-filter-example-block-functions
             #'cerebro-latex-example-filter)

;; -- What keeps a deck from colliding with itself -----------------------
;; A slide goes wrong in two ways, and neither of them is about content:
;; too much of it lands on one frame, and a figure drawn for a page is
;; drawn again, unchanged, on a canvas a third of the size. The second is
;; the class's business (cerebro-beamer.cls scales every picture down);
;; the first is settled here, because it is a property of the *export*,
;; not of the note -- no note should have to know it may be projected.

(defun cerebro-latex--beamer-fit-environment (output backend _info)
  "On a deck, wrap a LaTeX environment in \\cerebrofit{} so it fits.

A tikzpicture or a pgfplots axis written for a 21cm page is, on a
12.8cm slide, drawn straight through the bottom of the frame and over
whatever beamer puts there -- the overlapping figures. \\cerebrofit
(cerebro-beamer.cls) is an adjustbox that shrinks its content to the
frame and never enlarges it, so a small diagram is untouched and a large
one is made to fit rather than allowed to collide.

Only for beamer: the same figure in the handbook is meant to be page
sized, and wrapping it there would shrink it for no reason."
  (if (and output (org-export-derived-backend-p backend 'beamer))
      (format "\\cerebrofit{%%\n%s}\n" (string-trim-right output))
    output))

(add-to-list 'org-export-filter-latex-environment-functions
             #'cerebro-latex--beamer-fit-environment)

(defun cerebro-latex--beamer-plist ()
  "The ox-beamer settings the `slides' profile exports under."
  (list
   ;; One frame per NOTE, not one per chapter. A composed course nests
   ;; each note's heading (level 2) under its programme chapter (level
   ;; 1), and ox-beamer turns headlines at `:headline-levels' into frames
   ;; -- so at the default 1 a whole chapter, every note in it, became a
   ;; single frame. That is the pile-up: ten theorems typeset on top of
   ;; each other, in the space of one.
   :headline-levels 2
   ;; And when one note still does not fit, beamer breaks the frame into
   ;; as many slides as it needs, rather than letting the overflow run
   ;; off the bottom edge and across the frame's own footer. There are no
   ;; overlays in these decks, which is what makes `allowframebreaks'
   ;; (which cannot combine with them) the right default rather than a
   ;; per-frame decision.
   :beamer-frame-default-options "allowframebreaks"
   ;; No table of contents: a deck of bare statements is the minimum, and
   ;; a contents slide is the first thing that is not it.
   :with-toc nil))

(defun cerebro-latex-export-to-pdf (file profile-name &optional target)
  "Export FILE to PDF using PROFILE-NAME (see `cerebro-latex-profiles').
TARGET is the #+NAME of the block to keep, required only for the
`single' content mode. Intended for batch use from
bin/org-export-latex.el / `make export'."
  ;; Absolute from here on: the export runs inside the note's own buffer,
  ;; where `default-directory' is the note's directory -- expanding a
  ;; relative FILE later would resolve it against that, and the build
  ;; would be tidied into notes/math/notes/math/. (It did, once.)
  (setq file (expand-file-name file))
  (let* ((profile (cerebro-latex--profile profile-name))
         (content (cerebro-latex--content-mode (plist-get profile :content)))
         (doctype-name (plist-get profile :doctype))
         (doctype (cerebro-latex--doctype doctype-name))
         (class (plist-get doctype :class))
         (exclude-blocks (plist-get content :exclude-blocks))
         (only-blocks (plist-get content :only-blocks))
         (single-p (plist-get content :single))
         (cerebro-latex--exclude-blocks (unless single-p exclude-blocks))
         (cerebro-latex--only-blocks (unless single-p only-blocks))
         (cerebro-latex--prune-prose (plist-get content :prune-prose))
         (cerebro-latex--single-target
          (when single-p
            (or target
                (error "cerebro-latex: profile `%s' needs a TARGET (make export ... TARGET=name)"
                       profile-name))))
         ;; A block only counts as "present" if it survives content
         ;; filtering: excluded, or (when :only-blocks is in force) not
         ;; kept. This drives the proofs/solutions class toggles.
         (has-proofs (and (not (member "proof" exclude-blocks))
                          (or (null only-blocks) (member "proof" only-blocks))))
         (has-solutions (and (not (member "solution" exclude-blocks))
                             (or (null only-blocks) (member "solution" only-blocks))))
         (class-options (cerebro-latex--class-options
                          doctype-name has-proofs has-solutions))
         ;; cerebro*.cls/cerebro-macros.sty live in latex/, not next to
         ;; the note being compiled -- make sure pdflatex/latexmk can
         ;; still find them. Trailing bare ":" = "then the default
         ;; search path".
         (process-environment
          (append (list (format "TEXINPUTS=%s:" (expand-file-name "latex" cerebro-root))
                        (format "BIBINPUTS=%s:" (expand-file-name "bib" cerebro-root)))
                  process-environment))
         (beamer-p (equal class "cerebro-beamer"))
         ;; The `slides' doctype goes through ox-beamer; the rest through
         ;; the generic LaTeX backend.
         (export-fn (if beamer-p
                        #'org-beamer-export-to-pdf
                      #'org-latex-export-to-pdf)))
    (with-current-buffer (find-file-noselect file)
      (let* (;; Author and version reach the title page as preamble
             ;; macros, not as Org keywords: a note should not have to
             ;; carry them, and every document should have them.
             (metadata (cerebro-latex-metadata-header
                        (cerebro-latex-author)
                        (cerebro-latex-version)
                        (cerebro-latex--subject)
                        ;; Not `:date' in the plist: a `#+DATE:' keyword
                        ;; in the buffer wins over anything the exporter
                        ;; passes, and every note has one.
                        (cerebro-latex--date)))
             (ext-plist
              (append (list :latex-class class
                            :latex-class-options class-options
                            :latex-header-extra metadata
                            ;; Org\='s own \\author{}: unused by the
                            ;; cerebro title page, which reads
                            ;; \\cerebroauthor.
                            :author (cerebro-latex-author))
                      (when beamer-p (cerebro-latex--beamer-plist)))))
        (funcall export-fn nil nil nil nil ext-plist)
        ;; Everything the compile produced, out of the notes tree.
        (cerebro-latex--tidy-build file)))))

(provide 'cerebro-latex)
