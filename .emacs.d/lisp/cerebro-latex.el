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
    (single      . (:exclude-blocks nil :single t)))
  "Which special blocks survive an export.
`single' is special-cased: see `cerebro-latex--extract-single'.")

(defvar cerebro-latex-doctypes
  '((article . (:class "cerebro" :class-options "article"))
    (report  . (:class "cerebro" :class-options "report"))
    (manual  . (:class "cerebro" :class-options "book"))
    (beamer  . (:class "cerebro-beamer" :class-options "")))
  "Which class/class-options combination typesets an export.")

(defvar cerebro-latex-profiles
  '((full            . (:content full       :doctype article))
    (statements      . (:content statements :doctype article))
    (statements-only . (:content statements :doctype article)) ; alias
    (report          . (:content full       :doctype report))
    (manual          . (:content full       :doctype manual))
    (lecture         . (:content lecture    :doctype article))
    (slides          . (:content lecture    :doctype beamer))
    (single          . (:content single     :doctype article)))
  "Named presets: what the user passes as PROFILE=... to `make export'.
Each entry composes one entry from `cerebro-latex-content-modes' with
one from `cerebro-latex-doctypes' -- adding a new named preset is a
one-line addition here, not new code.")

(defvar cerebro-latex--exclude-blocks nil
  "Special block type names (strings) to strip from the current export.
Dynamically let-bound by `cerebro-latex-export-to-pdf'.")

(defvar cerebro-latex--single-target nil
  "When non-nil, keep only the #+NAME'd block matching this string (plus
an immediately following sibling `proof' block), discarding every
other sibling. Dynamically let-bound by `cerebro-latex-export-to-pdf'.")

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

(defun cerebro-latex--class-options (doctype-name has-proofs)
  (let* ((doctype (cerebro-latex--doctype doctype-name))
         (extra (plist-get doctype :class-options))
         (proofs-opt (if has-proofs "proofs" "noproofs")))
    (format "[%s]" (if (string-empty-p extra)
                       proofs-opt
                     (concat proofs-opt "," extra)))))

(defun cerebro-latex--strip-blocks (tree _backend _info)
  "Remove special blocks whose type is in `cerebro-latex--exclude-blocks'."
  (when cerebro-latex--exclude-blocks
    (org-element-map tree 'special-block
      (lambda (block)
        (when (member (downcase (or (org-element-property :type block) ""))
                      cerebro-latex--exclude-blocks)
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

(add-to-list 'org-export-filter-parse-tree-functions #'cerebro-latex--strip-blocks)
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

(defun cerebro-latex-export-to-pdf (file profile-name &optional target)
  "Export FILE to PDF using PROFILE-NAME (see `cerebro-latex-profiles').
TARGET is the #+NAME of the block to keep, required only for the
`single' content mode. Intended for batch use from
bin/org-export-latex.el / `make export'."
  (let* ((profile (cerebro-latex--profile profile-name))
         (content (cerebro-latex--content-mode (plist-get profile :content)))
         (doctype-name (plist-get profile :doctype))
         (doctype (cerebro-latex--doctype doctype-name))
         (exclude-blocks (plist-get content :exclude-blocks))
         (single-p (plist-get content :single))
         (cerebro-latex--exclude-blocks (unless single-p exclude-blocks))
         (cerebro-latex--single-target
          (when single-p
            (or target
                (error "cerebro-latex: profile `%s' needs a TARGET (make export ... TARGET=name)"
                       profile-name))))
         (class-options (cerebro-latex--class-options
                          doctype-name (not (member "proof" exclude-blocks))))
         (ext-plist (list :latex-class (plist-get doctype :class)
                           :latex-class-options class-options))
         ;; cerebro*.cls/cerebro-macros.sty live in latex/, not next to
         ;; the note being compiled -- make sure pdflatex/latexmk can
         ;; still find them. Trailing bare ":" = "then the default
         ;; search path".
         (process-environment
          (append (list (format "TEXINPUTS=%s:" (expand-file-name "latex" cerebro-root))
                        (format "BIBINPUTS=%s:" (expand-file-name "bib" cerebro-root)))
                  process-environment))
         (export-fn (if (eq doctype-name 'beamer)
                        #'org-beamer-export-to-pdf
                      #'org-latex-export-to-pdf)))
    (with-current-buffer (find-file-noselect file)
      (funcall export-fn nil nil nil nil ext-plist))))

(provide 'cerebro-latex)
