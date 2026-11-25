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
(defvar site--figure-kinds)
(defvar site--languages)
(defvar site-cite-latex-function)
(declare-function site--environment "site")
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

(defconst manual--listing-colours
  '(("cpp" . "1F5F99") ("c" . "1F5F99") ("java" . "B0602A") ("vhdl" . "2E7D32")
    ("python" . "3B6FB6") ("asm" . "6A4C93") ("sh" . "555555") ("elisp" . "7B3F99")
    ("text" . "888888"))
  "Colour of the rule and title of each language's listings.")

(defconst manual--listing-names
  '(("cpp" . "C++") ("c" . "C") ("java" . "Java") ("vhdl" . "VHDL") ("python" . "Python")
    ("asm" . "[x86masm]Assembler") ("sh" . "bash") ("elisp" . "Lisp"))
  "listings language of each CSS class of `site--languages'.")

(defun manual--listings-setup ()
  (concat
   "\\usepackage{listings}\n"
   (mapconcat (lambda (c) (format "\\definecolor{kb%s}{HTML}{%s}\n" (car c) (cdr c)))
              manual--listing-colours "")
   "\\lstdefinestyle{kb}{basicstyle=\\ttfamily\\small, columns=fullflexible, keepspaces=true,\n"
   "  breaklines=true, breakatwhitespace=false, showstringspaces=false, tabsize=4,\n"
   "  frame=leftline, framerule=2.5pt, framesep=6pt, xleftmargin=10pt, aboveskip=10pt, belowskip=8pt,\n"
   "  keywordstyle=\\color[HTML]{8B1E5B}\\bfseries, commentstyle=\\color[HTML]{6A737D}\\itshape,\n"
   "  stringstyle=\\color[HTML]{22863A}, identifierstyle=\\color[HTML]{1F2328},\n"
   "  ndkeywordstyle=\\color[HTML]{005CC5}, emphstyle=\\color[HTML]{6F42C1}}\n"
   ;; The title of a listing is a caption: its look comes from the caption package.
   "\\captionsetup[lstlisting]{font={small,sf,bf},singlelinecheck=false,skip=2pt}\n"
   "\\renewcommand{\\lstlistingname}{Listing}\n"))

(defun manual--preamble (title &optional bib)
  "LaTeX preamble of the book TITLE: the reader's packages and macros, as a book.
BIB is the bibliography file given to biblatex."
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
   "\\usepackage{float,adjustbox,algorithm}\n"
   "\\usepackage[font=small,labelfont=bf,labelsep=period,margin=1cm]{caption}\n"
   (manual--listings-setup)
   (if bib
       (format "\\usepackage[style=authoryear-comp,backend=biber,maxcitenames=2,uniquelist=false,doi=true,url=false,isbn=false,giveninits=true]{biblatex}\n\\addbibresource{%s}\n"
               (file-name-nondirectory bib))
     "")
   "\\usepackage{amsthm}\n"
   (mapconcat (lambda (style)
                (concat (format "\\theoremstyle{%s}\n" (car style))
                        (mapconcat (lambda (th) (format "\\newtheorem{%s}{%s}[chapter]\n" (car th) (cdr th)))
                                   (cdr style) "")))
              manual--theorems "")
   "\\usepackage{zref-user,zref-abspage}\n"
   "\\usepackage[colorlinks,linkcolor=blue!45!black,urlcolor=blue!45!black,citecolor=blue!45!black,bookmarksnumbered]{hyperref}\n"
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

(defun manual--latex-environment (env _contents info)
  "Pictures in a centred figure scaled to the page, algorithms in an algorithm float,
both with their caption; other environments unchanged."
  (let* ((text (string-trim (org-element-property :value env)))
         (word (cdr (assoc (site--environment text) site--figure-kinds)))
         (caption (org-export-get-caption env))
         (cap (if caption (format "\\caption{%s}\n" (org-export-data caption info)) "")))
    (cond ((equal word "Figure")
           (format "\\begin{figure}[H]\n\\centering\n\\adjustbox{max width=\\linewidth}{%%\n%s}\n%s\\end{figure}" text cap))
          ((equal word "Algorithm")
           (format "\\begin{algorithm}[H]\n%s%s\n\\end{algorithm}" cap text))
          (t text))))

(defun manual--src-block (block _contents info)
  "A listing coloured for its language, with a rule and title in the language's colour."
  (let* ((lang (or (org-element-property :language block) "text"))
         (l (or (assoc lang site--languages) (list lang "text" lang nil)))
         (class (nth 1 l))
         (caption (org-export-get-caption block))
         (code (string-trim-right (car (org-export-unravel-code block)))))
    (format "\\begin{lstlisting}[style=kb,%stitle={%s},rulecolor=\\color{kb%s}]\n%s\n\\end{lstlisting}"
            (let ((n (cdr (assoc class manual--listing-names)))) (if n (format "language={%s}," n) ""))
            (concat (nth 2 l) (if caption (concat ": " (org-export-data caption info)) ""))
            (if (assoc class manual--listing-colours) class "text")
            code)))

(defun manual--citation (citation)
  (format "\\parencite{%s}"
          (mapconcat (lambda (r) (org-element-property :key r)) (org-cite-get-references citation) ",")))

(setq site-cite-latex-function #'manual--citation)

(org-export-define-derived-backend 'manual 'latex
  :translate-alist '((link . manual--link)
                     (latex-environment . manual--latex-environment)
                     (src-block . manual--src-block)))

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
    (let ((org-export-use-babel nil) (org-cite-export-processors '((t kb))))
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

(defun manual--tex (title groups &optional bib)
  "The whole book TITLE of GROUPS (see `site--groups'), citing from BIB."
  (concat
   (manual--preamble title bib)
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
   (if bib "\\backmatter\n\\clearpage\\zlabel{kbend:bibliography}\n\\printbibliography[heading=bibintoc]\n" "")
   "\\end{document}\n"))

;;;; Pages

(defun manual--labels (aux)
  "(KIND NAME PAGE) of the kb labels of the .aux text AUX, in document order."
  (let (labels (pos 0))
    (while (string-match "\\\\zref@newlabel{kb\\(domain\\|area\\|other\\|end\\):\\([^}]+\\)}{[^\n]*\\\\abspage{\\([0-9]+\\)}" aux pos)
      (push (list (match-string 1 aux) (match-string 2 aux) (string-to-number (match-string 3 aux))) labels)
      (setq pos (match-end 0)))
    (nreverse labels)))

(defun manual--ranges (aux total)
  "Page ranges cut from the book: ((FILE FROM . TO)...), from the .aux text AUX and
the TOTAL number of pages.  A domain ends before the next domain or the bibliography,
an area before the next label of any kind."
  (let ((labels (manual--labels aux)))
    (cl-loop for rest on labels
             for (kind name from) = (car rest)
             when (member kind '("domain" "area"))
             collect (let ((next (cl-find-if (lambda (l) (or (equal kind "area") (member (car l) '("domain" "end"))))
                                             (cdr rest))))
                       (cons (concat name ".pdf") (cons from (if next (1- (nth 2 next)) total)))))))

(defun manual--bib-start (aux)
  "First page of the bibliography in the .aux text AUX, or nil."
  (nth 2 (cl-find "end" (manual--labels aux) :key #'car :test #'equal)))

(defun manual--run (dir &rest command)
  "Run COMMAND in DIR; return its output."
  (let ((default-directory dir))
    (with-temp-buffer (apply #'call-process (car command) nil t nil (cdr command)) (buffer-string))))

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

(defun manual-build (name title groups dest &optional bib)
  "Compile the manuals of base NAME (TITLE, GROUPS, citing from BIB) into DEST;
return their file names.  Every domain and area PDF ends with the bibliography."
  (let* ((dir (make-temp-file "manual" t))
         (tex (expand-file-name (concat name ".tex") dir))
         (pdf (expand-file-name (concat name ".pdf") dir))
         (bib (and bib (file-exists-p bib) (progn (copy-file bib (expand-file-name "refs.bib" dir) t)
                                                  (expand-file-name "refs.bib" dir))))
         (latex (lambda () (manual--run dir "lualatex" "-interaction=nonstopmode" (file-name-nondirectory tex))))
         (t0 (float-time)))
    (with-temp-file tex (insert (manual--tex title groups bib)))
    (funcall latex)
    (when bib
      (let ((out (manual--run dir "biber" name)))
        (dolist (l (split-string out "\n"))
          (when (string-match-p "^\\(ERROR\\|WARN\\) " l) (message "manual: %s: biber %s" name l)))))
    (funcall latex)
    (funcall latex)
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
        (let* ((aux (with-temp-buffer (insert-file-contents (expand-file-name (concat name ".aux") dir))
                                      (buffer-string)))
               (bib-start (manual--bib-start aux)))
          (dolist (r (manual--ranges aux total))
            (manual--run dir "qpdf" "--empty" "--pages" pdf
                         (concat (format "%d-%d" (cadr r) (cddr r))
                                 (if bib-start (format ",%d-%d" bib-start total) ""))
                         "--" (expand-file-name (car r) dest))
            (when (file-exists-p (expand-file-name (car r) dest)) (push (car r) files))))
        (message "manual: %s: %d pages, %d PDF, %d LaTeX errors, %.0fs"
                 name total (length files) (length errors) (- (float-time) t0))
        (delete-directory dir t)
        (nreverse files)))))

(provide 'manual)
;;; manual.el ends here
