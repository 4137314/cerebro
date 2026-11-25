;;; manual.el --- PDF manuals of a knowledge base -*- lexical-binding: t; -*-

;; One LuaLaTeX book per base: a chapter per domain, a section per area (on a new page),
;; a subsection per note (\label{note:<id>}, links between notes are \hyperref), in the
;; reading order of the site.  The book is compiled twice; the absolute page of every
;; domain and area comes from its \zlabel in the .aux, and qpdf cuts one PDF per domain
;; and per area out of the book:
;;   <base>.pdf   <domain>.pdf   <domain>--<area>.pdf
;; Loaded by site.el (`site-build-base' with PDF) once the base is indexed.

(require 'kb)
(require 'ox-latex)
(require 'cl-lib)
(require 'subr-x)

(defvar site-url)
(defvar site--base)
(declare-function site--words "site")
(declare-function site--pdf-name "site")

(defconst manual--theorems
  '(("plain" ("theorem" . "Theorem") ("lemma" . "Lemma") ("proposition" . "Proposition")
     ("corollary" . "Corollary"))
    ("definition" ("definition" . "Definition") ("axiom" . "Axiom") ("example" . "Example"))
    ("remark" ("remark" . "Remark")))
  "Org special blocks of the notes as amsthm environments, by theorem style.")

(defconst manual--drop
  "\\`\\\\documentclass\\|pgfsysdriver\\|{preview}\\|PreviewBorder\\|\\\\setlength{\\\\textwidth}"
  "Lines of the reader's preamble that only serve its one-formula-per-page pictures.")

(defun manual--preamble (title)
  "LaTeX preamble of the book TITLE: the reader's packages and macros, as a book."
  (concat
   "\\documentclass[11pt,a4paper,openany]{book}\n"
   "\\usepackage[margin=2.4cm]{geometry}\n"
   "\\usepackage{fontspec}\n"
   ;; Latin Modern, with DejaVu for what it lacks (arrows, Greek, sub/superscripts in text).
   "\\directlua{luaotfload.add_fallback(\"kbfallback\", {\"DejaVuSerif:mode=harf;\", \"DejaVuSans:mode=harf;\"})}\n"
   "\\setmainfont{Latin Modern Roman}[RawFeature={fallback=kbfallback}]\n"
   "\\setmonofont{Latin Modern Mono}[RawFeature={fallback=kbfallback}]\n"
   (mapconcat (lambda (l) (if (string-match-p manual--drop l) "" (concat l "\n")))
              (split-string (replace-regexp-in-string "\\\\begin{document}\n*\\'" "" kb-latex-preamble)
                            "\n")
              "")
   "\\usepackage{amsthm}\n"
   (mapconcat (lambda (style)
                (concat (format "\\theoremstyle{%s}\n" (car style))
                        (mapconcat (lambda (th) (format "\\newtheorem{%s}{%s}[chapter]\n" (car th) (cdr th)))
                                   (cdr style) "")))
              manual--theorems "")
   "\\usepackage{zref-user,zref-abspage}\n"
   "\\usepackage[colorlinks,linkcolor=blue!45!black,urlcolor=blue!45!black,bookmarksnumbered]{hyperref}\n"
   "\\setcounter{tocdepth}{1}\n\\setcounter{secnumdepth}{2}\n"
   (format "\\title{%s}\n\\author{Mattia Fait}\n\\date{\\today}\n" title)))

;;;; Notes

(defun manual--link (link desc info)
  "Notes link to their subsection; web links stay; anything else keeps its text."
  (let ((type (org-element-property :type link))
        (path (org-element-property :path link)))
    (cond ((equal type "id")
           (if (kb--node path) (format "\\hyperref[note:%s]{%s}" path (or desc (kb--title path))) (or desc "")))
          ((member type '("http" "https" "mailto")) (org-latex-link link desc info))
          (t (or desc (org-latex-plain-text path info))))))

(org-export-define-derived-backend 'manual 'latex
  :translate-alist '((link . manual--link)))

(add-to-list 'org-latex-classes
             '("kbnote" "\\documentclass{book}"
               ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
               ("\\paragraph{%s}" . "\\paragraph*{%s}")
               ("\\subparagraph{%s}" . "\\subparagraph*{%s}")))

(defconst manual--export-options
  '(:latex-class "kbnote" :with-toc nil :section-numbers nil :with-sub-superscript {}
    :with-broken-links t :with-drawers nil :with-properties nil :with-tags nil
    :with-smart-quotes nil))

(defun manual--export (s)
  "LaTeX of the org text S (body only)."
  (with-temp-buffer
    (insert s)
    (org-mode)
    (let ((org-export-use-babel nil))
      (string-trim (org-export-as 'manual nil nil t manual--export-options)))))

(defun manual--note-latex (id)
  "Subsection of note ID: title, summary, link to its page, body."
  (let* ((file (kb--get id :file))
         (text (with-temp-buffer (insert-file-contents file) (buffer-string)))
         (summary (and (string-match "^#\\+summary:[ \t]*\\(.*\\)$" text) (match-string 1 text))))
    (concat
     (format "\\typeout{kbnote:%s}\n" id)
     (format "\\subsection{%s}\\label{note:%s}\n" (manual--export (kb--title id)) id)
     (if summary (format "\\noindent\\emph{%s}\\par\n" (manual--export summary)) "")
     (if (boundp 'site-url)
         (format "\\noindent{\\footnotesize\\url{%s%s/%s.html}}\\par\\medskip\n" site-url site--base id)
       "")
     (manual--export text)
     "\n")))

(defun manual--tex (title groups)
  "The whole book TITLE of GROUPS (see `site--groups')."
  (concat
   (manual--preamble title)
   "\\begin{document}\n\\frontmatter\n\\maketitle\n\\tableofcontents\n\\mainmatter\n"
   (mapconcat
    (lambda (g)
      (let ((domain (car g)) (first t))
        (concat
         (format "\\chapter{%s}\\zlabel{kbdomain:%s}\n" (site--words domain) domain)
         (mapconcat
          (lambda (a)
            (concat
             (if first (progn (setq first nil) "") "\\clearpage\n")
             (if (car a)
                 (format "\\section{%s}\\zlabel{kbarea:%s--%s}\n" (site--words (car a)) domain (car a))
               (format "\\section{Other notes}\\zlabel{kbother:%s}\n" domain))
             (mapconcat #'manual--note-latex (cdr a) "")))
          (cdr g) ""))))
    groups "")
   "\\end{document}\n"))

;;;; Pages

(defun manual--ranges (aux total)
  "Page ranges cut from the book: ((FILE FROM . TO)...), from the .aux text AUX and
the TOTAL number of pages.  A domain ends before the next domain, an area before the
next label of any kind."
  (let (labels (pos 0))
    (while (string-match "\\\\zref@newlabel{kb\\(domain\\|area\\|other\\):\\([^}]+\\)}{[^\n]*\\\\abspage{\\([0-9]+\\)}" aux pos)
      (push (list (match-string 1 aux) (match-string 2 aux) (string-to-number (match-string 3 aux))) labels)
      (setq pos (match-end 0)))
    (setq labels (nreverse labels))
    (cl-loop for rest on labels
             for (kind name from) = (car rest)
             unless (equal kind "other")
             collect (let ((next (cl-find-if (lambda (l) (or (equal kind "area") (equal (car l) "domain")))
                                             (cdr rest))))
                       (cons (concat name ".pdf") (cons from (if next (1- (nth 2 next)) total)))))))

(defun manual--run (dir &rest command)
  (let ((default-directory dir))
    (with-temp-buffer (apply #'call-process (car command) nil t nil (cdr command)))))

(defun manual--log-errors (log)
  "Errors of the LaTeX LOG text, each with the note it happened in."
  (let (errors (note "preamble"))
    (with-temp-buffer
      (insert log)
      (goto-char (point-min))
      (while (re-search-forward "^kbnote:\\(.*\\)$\\|^! \\(.*\\)$" nil t)
        (if (match-string 1) (setq note (match-string 1))
          (push (format "%s: %s" note (match-string 2)) errors))))
    (nreverse errors)))

(defun manual-build (name title groups dest)
  "Compile the manuals of base NAME (TITLE, GROUPS) into DEST; return their file names."
  (let* ((dir (make-temp-file "manual" t))
         (tex (expand-file-name (concat name ".tex") dir))
         (pdf (expand-file-name (concat name ".pdf") dir))
         (t0 (float-time)))
    (with-temp-file tex (insert (manual--tex title groups)))
    (dotimes (_ 2)
      (manual--run dir "lualatex" "-interaction=nonstopmode" "-halt-on-error=false" (file-name-nondirectory tex)))
    (let* ((log (with-temp-buffer (insert-file-contents (expand-file-name (concat name ".log") dir)) (buffer-string)))
           (errors (manual--log-errors log))
           (total (and (string-match "Output written on .*(\\([0-9]+\\) pages" log)
                       (string-to-number (match-string 1 log))))
           files)
      (dolist (e (seq-take errors 30)) (message "manual: %s: LaTeX %s" name e))
      (if (not (and total (file-exists-p pdf)))
          (progn (message "manual: %s: no PDF (%d errors)" name (length errors)) (delete-directory dir t) nil)
        (make-directory dest t)
        (copy-file pdf (expand-file-name (concat name ".pdf") dest) t)
        (push (concat name ".pdf") files)
        (dolist (r (manual--ranges (with-temp-buffer
                                     (insert-file-contents (expand-file-name (concat name ".aux") dir))
                                     (buffer-string))
                                   total))
          (manual--run dir "qpdf" "--empty" "--pages" pdf (format "%d-%d" (cadr r) (cddr r)) "--"
                       (expand-file-name (car r) dest))
          (when (file-exists-p (expand-file-name (car r) dest)) (push (car r) files)))
        (message "manual: %s: %d pages, %d PDF, %d LaTeX errors, %.0fs"
                 name total (length files) (length errors) (- (float-time) t0))
        (delete-directory dir t)
        (nreverse files)))))

(provide 'manual)
;;; manual.el ends here
