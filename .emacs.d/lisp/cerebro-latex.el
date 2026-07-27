;;; cerebro-latex.el --- parametric LaTeX export pipeline -*- lexical-binding: t; -*-

;; One Org source, several LaTeX/PDF variants -- controlled at export
;; time, never by duplicating content. Pairs with latex/cerebro.cls,
;; which defines the actual proofs/noproofs class option and the shared
;; theorem/definition/proof environments.
;;
;; Notes are written with special blocks (#+begin_theorem/definition/proof
;; ... #+end_...), which Org's LaTeX backend already turns into
;; \begin{theorem}...\end{theorem} etc. for free (any special block whose
;; name isn't otherwise recognized is exported as its own environment).
;; What this file adds is the ability to *drop* chosen block types
;; entirely from a given export -- e.g. proofs, for a "statements-only"
;; profile -- via a parse-tree filter, plus setting the matching
;; cerebro.cls class option so headings/numbering stay consistent.
;;
;; Convention for note authors: never set #+LATEX_CLASS_OPTIONS or
;; #+EXCLUDE_TAGS in a note file. Those are file-local export settings
;; and, per Org's own precedence rules, would silently win over the
;; per-export overrides this file installs -- which would make profile
;; selection stop doing anything, silently.

(require 'ox-latex)
(require 'org-element)
(require 'cerebro-org)

(defvar cerebro-latex-profiles
  '((full
     . (:latex-class-options "[proofs]" :exclude-blocks nil))
    (statements-only
     . (:latex-class-options "[noproofs]" :exclude-blocks ("proof"))))
  "Named parametric export profiles.
Each entry is (NAME . PLIST) with :latex-class-options (a string
passed as the cerebro.cls option) and :exclude-blocks (special block
names, lowercase, to strip from this export).")

(defvar cerebro-latex--exclude-blocks nil
  "Special block type names (strings) to strip from the current export.
Dynamically let-bound by `cerebro-latex-export-to-pdf'; read by
`cerebro-latex--strip-blocks'.")

(defun cerebro-latex--profile (name)
  "Return the plist for profile NAME (a symbol), or signal an error."
  (or (cdr (assq name cerebro-latex-profiles))
      (error "cerebro-latex: unknown export profile `%s' (known: %s)"
             name (mapcar #'car cerebro-latex-profiles))))

(defun cerebro-latex--strip-blocks (tree _backend _info)
  "Remove special blocks whose type is in `cerebro-latex--exclude-blocks'."
  (when cerebro-latex--exclude-blocks
    (org-element-map tree 'special-block
      (lambda (block)
        (when (member (downcase (or (org-element-property :type block) ""))
                      cerebro-latex--exclude-blocks)
          (org-element-extract-element block)))))
  tree)

(add-to-list 'org-export-filter-parse-tree-functions
             #'cerebro-latex--strip-blocks)

;; Register the shared class with Org's LaTeX backend. Sectioning mirrors
;; article's, since cerebro.cls is built on top of article.
(add-to-list 'org-latex-classes
             '("cerebro"
               "\\documentclass{cerebro}"
               ("\\section{%s}" . "\\section*{%s}")
               ("\\subsection{%s}" . "\\subsection*{%s}")
               ("\\subsubsection{%s}" . "\\subsubsection*{%s}")))

(defun cerebro-latex-export-to-pdf (file profile-name)
  "Export FILE to PDF using PROFILE-NAME (see `cerebro-latex-profiles').
Intended for batch use from bin/org-export-latex.el / `make export'."
  (let* ((profile (cerebro-latex--profile profile-name))
         (cerebro-latex--exclude-blocks (plist-get profile :exclude-blocks))
         (ext-plist (list :latex-class-options
                           (plist-get profile :latex-class-options)))
         ;; cerebro.cls lives in latex/, not next to the note being
         ;; compiled -- make sure pdflatex/latexmk can still find it.
         ;; Trailing bare ":" means "then the default search path".
         (process-environment
          (cons (format "TEXINPUTS=%s:"
                        (expand-file-name "latex" cerebro-root))
                process-environment)))
    (with-current-buffer (find-file-noselect file)
      (org-latex-export-to-pdf nil nil nil nil ext-plist))))

(provide 'cerebro-latex)
