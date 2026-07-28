;;; cerebro-latex.el --- parametric LaTeX export pipeline -*- lexical-binding: t; -*-

;; One Org source, many LaTeX/PDF variants -- controlled at export
;; time, never by duplicating content. Two independent, orthogonal axes,
;; composed as data (this IS the "parametric macro system": adding a new
;; export configuration is one alist line, not new code):
;;
;;   content mode   -- which blocks survive the export (full, statements,
;;                     lecture, single)
;;   doctype        -- which class/class-option combination typesets it
;;                     (article/report/manual all use latex/cerebro.cls;
;;                     beamer uses latex/cerebro-beamer.cls via Org's own
;;                     ox-beamer backend)
;;
;; Named profiles below are just (content . doctype) pairs. Pairs with
;; latex/cerebro.cls and latex/cerebro-beamer.cls, which define the
;; actual proofs/noproofs and article/report/book switches, and with
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
(require 'cerebro-msc) ;; #+MSC: -> \subjclass[2020]{...} on paper/preprint

;; Citations: [cite:@key] in Org -> \autocite{key} via org-cite's own
;; biblatex export processor (built into Org core since 9.5, no new
;; package). One shared bib/references.bib, like the notation in
;; cerebro-macros.sty.
(setq org-cite-global-bibliography
      (list (expand-file-name "bib/references.bib" cerebro-root)))
(setq org-cite-export-processors '((latex biblatex) (t basic)))

(defvar cerebro-latex-content-modes
  '((full        . (:exclude-blocks nil))
    (statements  . (:exclude-blocks ("proof")))
    (lecture     . (:exclude-blocks ("proof" "remark" "example")))
    ;; publishable body: drop the pedagogical apparatus (exercises,
    ;; their solutions, hints), keep the mathematics and its proofs.
    (paper-body  . (:exclude-blocks ("exercise" "solution" "hint")))
    ;; the inverse filter (:only-blocks): keep ONLY these block types --
    ;; a problem sheet, with (`exercises') or without (`problems') the
    ;; worked solutions. See `cerebro-latex--keep-only-blocks'.
    (exercises   . (:only-blocks ("exercise" "solution" "hint")))
    (problems    . (:only-blocks ("exercise" "hint")))
    (single      . (:exclude-blocks nil :single t)))
  "Which special blocks survive an export, as `:exclude-blocks' (drop
these types) or `:only-blocks' (keep only these). `single' is
special-cased: see `cerebro-latex--extract-single'.")

(defvar cerebro-latex-doctypes
  ;; :family is `cerebro' (the parametric cerebro.cls / cerebro-beamer.cls
  ;; family, which understands the proofs/solutions toggles) or `amsart'
  ;; (the standard AMS article class, submission-ready -- its own options
  ;; only, plus \subjclass/\keywords injected from #+MSC:/#+KEYWORDS:).
  '((article  . (:class "cerebro"         :class-options "article"  :family cerebro))
    (report   . (:class "cerebro"         :class-options "report"   :family cerebro))
    (manual   . (:class "cerebro"         :class-options "book"     :family cerebro))
    (syllabus . (:class "cerebro"         :class-options "syllabus" :family cerebro))
    (beamer   . (:class "cerebro-beamer"  :class-options ""         :family cerebro))
    (handout  . (:class "cerebro-beamer"  :class-options "handout"  :family cerebro))
    (paper    . (:class "amsart"          :class-options ""         :family amsart))
    (preprint . (:class "amsart"          :class-options "preprint" :family amsart)))
  "Which class/class-options combination typesets an export.")

(defvar cerebro-latex-profiles
  '((full            . (:content full       :doctype article))
    (statements      . (:content statements :doctype article))
    (statements-only . (:content statements :doctype article)) ; alias
    (report          . (:content full       :doctype report))
    (manual          . (:content full       :doctype manual))
    (dispensa        . (:content full       :doctype manual))   ; a course handbook (alias of manual, for courses)
    (lecture         . (:content lecture    :doctype article))
    (slides          . (:content lecture    :doctype beamer))
    (handout         . (:content lecture    :doctype handout))  ; slides as a printable handout
    (syllabus        . (:content full       :doctype syllabus)) ; typeset a course.org
    (paper           . (:content paper-body :doctype paper))    ; publishable, amsart
    (preprint        . (:content paper-body :doctype preprint)) ; amsart [preprint]
    (exercises       . (:content exercises  :doctype article))  ; problem sheet, with solutions
    (problems        . (:content problems   :doctype article))  ; problem sheet, no solutions
    (single          . (:content single     :doctype article)))
  "Named presets: what the user passes as PROFILE=... to `make export'.
Each entry composes one entry from `cerebro-latex-content-modes' with
one from `cerebro-latex-doctypes' -- adding a new named preset is a
one-line addition here, not new code.")

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

(defvar cerebro-latex--strip-abstract nil
  "When non-nil, remove `abstract' special blocks from the body. Set for
the amsart doctypes, whose abstract must precede \\maketitle -- so the
export emits it there via :latex-title-command and drops the body copy
to avoid it appearing twice. See `cerebro-latex-export-to-pdf'.")

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
For the `cerebro' family, prepend the proofs/solutions toggles that
cerebro.cls / cerebro-beamer.cls understand; for `amsart', pass only the
class's own options (an empty result yields no brackets at all)."
  (let* ((doctype (cerebro-latex--doctype doctype-name))
         (extra (plist-get doctype :class-options))
         (family (plist-get doctype :family))
         (parts (append
                 (when (eq family 'cerebro)
                   (list (if has-proofs "proofs" "noproofs")
                         (if has-solutions "solutions" "nosolutions")))
                 (unless (string-empty-p extra) (list extra))))
         (inner (mapconcat #'identity parts ",")))
    (if (string-empty-p inner) "" (format "[%s]" inner))))

(defun cerebro-latex--strip-blocks (tree _backend _info)
  "Remove special blocks whose type is in `cerebro-latex--exclude-blocks'."
  (when cerebro-latex--exclude-blocks
    (org-element-map tree 'special-block
      (lambda (block)
        (when (member (downcase (or (org-element-property :type block) ""))
                      cerebro-latex--exclude-blocks)
          (org-element-extract-element block)))))
  tree)

(defun cerebro-latex--keep-only-blocks (tree _backend _info)
  "Remove every special block whose type is NOT in
`cerebro-latex--only-blocks' -- the inverse of `cerebro-latex--strip-blocks'.
Prose and headings are left untouched (a problem sheet keeps its
section structure); only unrelated special blocks are pruned."
  (when cerebro-latex--only-blocks
    (org-element-map tree 'special-block
      (lambda (block)
        (unless (member (downcase (or (org-element-property :type block) ""))
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

(defun cerebro-latex--strip-abstract-block (tree _backend _info)
  "Remove `abstract' special blocks when `cerebro-latex--strip-abstract'
is set (amsart doctypes emit the abstract before \\maketitle instead)."
  (when cerebro-latex--strip-abstract
    (org-element-map tree 'special-block
      (lambda (block)
        (when (equal (downcase (or (org-element-property :type block) "")) "abstract")
          (org-element-extract-element block)))))
  tree)

(add-to-list 'org-export-filter-parse-tree-functions #'cerebro-latex--strip-blocks)
(add-to-list 'org-export-filter-parse-tree-functions #'cerebro-latex--keep-only-blocks)
(add-to-list 'org-export-filter-parse-tree-functions #'cerebro-latex--strip-abstract-block)
(add-to-list 'org-export-filter-parse-tree-functions #'cerebro-latex--extract-single)

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

(add-to-list 'org-latex-classes
             '("cerebro-beamer"
               "\\documentclass{cerebro-beamer}"
               ("\\section{%s}" . "\\section*{%s}")
               ("\\subsection{%s}" . "\\subsection*{%s}")))

;; amsart -- the standard AMS article class, for the `paper'/`preprint'
;; doctypes. Not a cerebro.cls variant: it is what journals expect, so a
;; finished note can be submitted with the class it was drafted in. The
;; shared notation (cerebro-macros.sty) and the paper metadata
;; (\subjclass from #+MSC:, \keywords from #+KEYWORDS:) are injected as
;; :latex-header-extra by `cerebro-latex-export-to-pdf', so this entry
;; only needs the document skeleton. amsart numbers sections itself.
(add-to-list 'org-latex-classes
             '("amsart"
               "\\documentclass{amsart}"
               ("\\section{%s}" . "\\section*{%s}")
               ("\\subsection{%s}" . "\\subsection*{%s}")
               ("\\subsubsection{%s}" . "\\subsubsection*{%s}")))

(defun cerebro-latex--abstract-text ()
  "Verbatim text of the current buffer's first #+begin_abstract block,
or nil. amsart requires the abstract before \\maketitle, so the paper
export lifts it out of the body and into :latex-title-command. The text
is handed to LaTeX as-is -- write paper abstracts in LaTeX-compatible
prose (plain text and $math$), not heavy Org markup."
  (org-with-wide-buffer
   (goto-char (point-min))
   (let ((case-fold-search t))
     (when (re-search-forward "^[ \t]*#\\+begin_abstract[ \t]*$" nil t)
       (let ((start (line-beginning-position 2)))
         (when (re-search-forward "^[ \t]*#\\+end_abstract[ \t]*$" nil t)
           (string-trim
            (buffer-substring-no-properties start (line-beginning-position)))))))))

(defun cerebro-latex--paper-header-extra ()
  "For the `amsart' doctypes, build the \\usepackage/\\subjclass/\\keywords
lines from the current buffer's #+MSC: and #+KEYWORDS: keywords. amsart
does not \\RequirePackage cerebro-macros itself (cerebro.cls does), so it
is added here; \\subjclass[2020]{...} and \\keywords{...} are what a
journal submission needs. Returns nil when there is nothing to add."
  (let* ((kw (org-collect-keywords '("MSC" "KEYWORDS")))
         (msc (cerebro-msc-parse (cadr (assoc "MSC" kw))))
         (keywords (cadr (assoc "KEYWORDS" kw))))
    (concat "\\usepackage{cerebro-macros}\n"
            (when msc
              (format "\\subjclass[2020]{%s}\n" (mapconcat #'identity msc ", ")))
            (when (and keywords (not (string-empty-p (string-trim keywords))))
              (format "\\keywords{%s}\n" (string-trim keywords))))))

(defun cerebro-latex-export-to-pdf (file profile-name &optional target)
  "Export FILE to PDF using PROFILE-NAME (see `cerebro-latex-profiles').
TARGET is the #+NAME of the block to keep, required only for the
`single' content mode. Intended for batch use from
bin/org-export-latex.el / `make export'."
  (let* ((profile (cerebro-latex--profile profile-name))
         (content (cerebro-latex--content-mode (plist-get profile :content)))
         (doctype-name (plist-get profile :doctype))
         (doctype (cerebro-latex--doctype doctype-name))
         (class (plist-get doctype :class))
         (family (plist-get doctype :family))
         (exclude-blocks (plist-get content :exclude-blocks))
         (only-blocks (plist-get content :only-blocks))
         (single-p (plist-get content :single))
         (cerebro-latex--exclude-blocks (unless single-p exclude-blocks))
         (cerebro-latex--only-blocks (unless single-p only-blocks))
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
         ;; beamer doctypes (slides, handout) go through ox-beamer; the
         ;; rest through the generic LaTeX backend.
         (export-fn (if (equal class "cerebro-beamer")
                        #'org-beamer-export-to-pdf
                      #'org-latex-export-to-pdf)))
    (with-current-buffer (find-file-noselect file)
      (let* ((abstract (and (eq family 'amsart) (cerebro-latex--abstract-text)))
             ;; Strip the body copy of the abstract for amsart (it is
             ;; re-emitted before \maketitle, below); dynamic, read by the
             ;; parse-tree filter during the export just below.
             (cerebro-latex--strip-abstract (and abstract t))
             (ext-plist
              (append (list :latex-class class
                            :latex-class-options class-options)
                      (when (eq family 'amsart)
                        (append
                         ;; cerebro-macros + \subjclass + \keywords (cerebro.cls
                         ;; provides its own); and no table of contents -- a
                         ;; paper has none, and amsart breaks outright on a
                         ;; \tableofcontents near the abstract.
                         (list :latex-header-extra (cerebro-latex--paper-header-extra)
                               :with-toc nil)
                         ;; amsart's abstract MUST precede \maketitle (after it,
                         ;; the abstract environment fails to close under the
                         ;; full hyperref/biblatex preamble). Org's own
                         ;; :latex-title-command is used verbatim (no %s), so we
                         ;; emit the abstract there, then \maketitle.
                         (when abstract
                           (list :latex-title-command
                                 (concat "\\begin{abstract}\n" abstract
                                         "\n\\end{abstract}\n\\maketitle"))))))))
        (funcall export-fn nil nil nil nil ext-plist)))))

(provide 'cerebro-latex)
