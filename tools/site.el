;;; site.el --- static site of the published knowledge bases -*- lexical-binding: t; -*-

;; The bases of bases.el marked `:publish t' become a static site:
;;   OUT/index.html                 the bases
;;   OUT/<base>/index.html          notes by domain and area, in study order
;;   OUT/<base>/<id>.html           one page per note
;;   OUT/<base>/m/<hash>.svg        formulas and pictures, rendered by the reader's engine
;; Each base is built in its own batch Emacs (`site-main' starts them), so the LaTeX
;; preamble of one base never leaks into the next, and the SVG hashes are the hub's:
;; a local build reuses the hub's cache.
;;
;;   OUT/<base>/pdf/*.pdf          manuals: the base, each domain, each area (manual.el)
;;   OUT/search.json, sitemap.xml   for site.js and the crawlers
;;
;;   emacs --batch -Q -L <reader>/emacs -l site.el -f site-main REGISTRY HUB-ROOT OUT
;;         [--base NAME]... [--pdf] [--no-index | --index-only]
;; The SVG cache of base NAME is $SITE_STATE/NAME (default: the hub's state).

(require 'kb)
(require 'ox-html)
(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'oc)

(defconst site--file (or load-file-name buffer-file-name))
(add-to-list 'load-path (file-name-directory site--file))

;; Links are resolved from the reader's index: org-id must not read or write a file.
(setq org-id-locations-file null-device
      ;; Source blocks stay plain (no htmlize): styled by the stylesheet.
      org-html-htmlize-output-type nil)

(require 'refs)

(defvar site--base nil "Name of the base being built (its directory in the site).")

(defvar site--used (make-hash-table :test 'equal) "SVG hashes used by the pages written.")

(defconst site--em-per-pt 0.11 "Size in em of one LaTeX point (10pt text = 1.1em).")

;;;; Registry

(defun site-bases (registry hub-root)
  "Published bases of REGISTRY: (NAME :title T :dir D :config C).
Roots are relative to HUB-ROOT, or to REGISTRY when they start with \".\" (as in
`kb-hub-read')."
  (let ((entries (with-temp-buffer (insert-file-contents registry) (read (current-buffer)))))
    (cl-loop
     for (name . p) in entries
     when (plist-get p :publish)
     collect
     (let* ((r (or (plist-get p :root) "."))
            (root (expand-file-name r (if (string-match-p "\\`\\.\\(?:/\\|\\'\\)" r)
                                          (file-name-directory (expand-file-name registry))
                                        hub-root))))
       (list name
             :title (or (plist-get p :title) name)
             :dir (file-name-as-directory (expand-file-name (or (plist-get p :notes) ".") root))
             :config (and (plist-get p :config)
                          (expand-file-name (plist-get p :config) root)))))))

;;;; Formulas and pictures

(defun site--svg-size (file)
  "(WIDTH . HEIGHT) in pt of the SVG FILE."
  (with-temp-buffer
    (insert-file-contents file nil 0 2000)
    (cl-flet ((attr (a) (and (re-search-forward (format "%s=['\"]\\([0-9.]+\\)pt" a) nil t)
                             (prog1 (string-to-number (match-string 1))
                               (goto-char (point-min))))))
      (cons (or (attr "width") 10) (or (attr "height") 10)))))

(defun site--em (pt) (format "%.3fem" (* pt site--em-per-pt)))

(defconst site--figure-kinds
  '(("tikzpicture" . "Figure") ("circuitikz" . "Figure") ("algorithmic" . "Algorithm"))
  "Environments shown as numbered figures, with the word of their label.")

(defvar site--counters nil "Figure numbers of the note being exported: (WORD . N)...")

(defun site--math (text blockp)
  "HTML of the fragment TEXT: the image of its SVG, or the TeX itself if not rendered."
  (let* ((text (string-trim text))
         (hash (kb--hash text))
         (file (kb--svg hash)))
    (if (not (file-exists-p file))
        (progn (message "site: not rendered: %s" (truncate-string-to-width text 100))
               (format "<code class=\"tex\">%s</code>" (org-html-encode-plain-text text)))
      (puthash hash t site--used)
      (let* ((size (site--svg-size file))
             (alt (if (assoc (site--environment text) site--figure-kinds)
                      "figure"
                    (org-html-encode-plain-text text)))
             (alt (replace-regexp-in-string "\"" "&quot;" alt)))
        (if blockp
            (format "<img class=\"m\" src=\"m/%s.svg\" alt=\"%s\" style=\"width:%s\">"
                    hash alt (site--em (car size)))
          (let* ((ascent (gethash hash kb--meta 'center))
                 (depth (if (numberp ascent)
                            (* (cdr size) (- 1 (/ ascent 100.0)))
                          (/ (cdr size) 2.0))))
            (format "<img class=\"m\" src=\"m/%s.svg\" alt=\"%s\" style=\"height:%s;vertical-align:-%s\">"
                    hash alt (site--em (cdr size)) (site--em depth))))))))

(defun site--environment (text)
  "Name of the LaTeX environment TEXT starts with, or nil."
  (and (string-match "\\`[ \t]*\\\\begin{\\([a-zA-Z*]+\\)}" text) (match-string 1 text)))

(defun site--latex-fragment (fragment _contents _info)
  (let ((v (org-element-property :value fragment)))
    (if (string-prefix-p "$" v)
        (org-html-encode-plain-text v)
      (let ((img (site--math v (string-prefix-p "\\[" v))))
        (if (string-prefix-p "\\[" v) (format "<div class=\"mb\">%s</div>" img) img)))))

(defun site--latex-environment (env _contents info)
  "Displayed environment: a numbered figure with its caption for pictures and algorithms."
  (let* ((text (org-element-property :value env))
         (word (cdr (assoc (site--environment text) site--figure-kinds)))
         (img (site--math text t)))
    (if (not word)
        (format "<div class=\"mb\">%s</div>" img)
      (let* ((n (1+ (or (cdr (assoc word site--counters)) 0)))
             (caption (org-export-get-caption env)))
        (setf (alist-get word site--counters nil nil #'equal) n)
        (format "<figure class=\"fig\">%s%s</figure>" img
                (if caption
                    (format "<figcaption><span class=\"fl\">%s %d.</span> %s</figcaption>"
                            word n (org-export-data caption info))
                  ""))))))

;;;; Listings

(defconst site--languages
  '(("c++" "cpp" "C++" c++-mode) ("cpp" "cpp" "C++" c++-mode) ("c" "c" "C" c-mode)
    ("java" "java" "Java" java-mode) ("vhdl" "vhdl" "VHDL" vhdl-mode)
    ("python" "python" "Python" python-mode) ("asm" "asm" "Assembly" asm-mode)
    ("sh" "sh" "Shell" sh-mode) ("bash" "sh" "Shell" sh-mode)
    ("emacs-lisp" "elisp" "Emacs Lisp" emacs-lisp-mode) ("text" "text" "Text" nil))
  "Org language -> (CSS class, label, Emacs mode used to colour it).")

(defconst site--face-classes
  '((font-lock-keyword-face . "k") (font-lock-type-face . "t") (font-lock-string-face . "s")
    (font-lock-doc-face . "s") (font-lock-comment-face . "c") (font-lock-comment-delimiter-face . "c")
    (font-lock-function-name-face . "f") (font-lock-function-call-face . "f")
    (font-lock-variable-name-face . "v") (font-lock-constant-face . "n") (font-lock-number-face . "n")
    (font-lock-builtin-face . "b") (font-lock-preprocessor-face . "p") (font-lock-warning-face . "k")
    (font-lock-negation-char-face . "k"))
  "Token classes of the listings (colours in site.css).")

(defun site--face-class (face)
  (cl-some (lambda (f) (cdr (assq f site--face-classes))) (if (listp face) face (list face))))

(defun site--highlight (code mode)
  "CODE as HTML, its tokens in spans coloured as MODE's font-lock sees them."
  (with-temp-buffer
    (insert code)
    (when (and mode (fboundp mode))
      (let ((inhibit-message t)) (delay-mode-hooks (funcall mode)) (font-lock-ensure)))
    (let ((pos (point-min)) (out nil) (run "") (class nil))
      (cl-flet ((flush () (unless (string-empty-p run)
                            (push (if class (format "<span class=\"%s\">%s</span>" class run) run) out))))
        (while (< pos (point-max))
          (let* ((next (next-single-property-change pos 'face nil (point-max)))
                 (c (site--face-class (get-text-property pos 'face)))
                 (text (org-html-encode-plain-text (buffer-substring-no-properties pos next))))
            (if (equal c class)
                (setq run (concat run text))
              (flush)
              (setq run text class c))
            (setq pos next)))
        (flush))
      (apply #'concat (nreverse out)))))

(defun site--src-block (block _contents info)
  (let* ((lang (or (org-element-property :language block) "text"))
         (l (or (assoc lang site--languages) (list lang lang lang nil)))
         (code (car (org-export-unravel-code block)))
         (caption (org-export-get-caption block)))
    (format "<figure class=\"listing lang-%s\"><figcaption><span class=\"lang\">%s</span>%s</figcaption><pre class=\"src\"><code>%s</code></pre></figure>"
            (nth 1 l) (nth 2 l)
            (if caption (concat " " (org-export-data caption info)) "")
            (site--highlight (string-trim-right code) (nth 3 l)))))

;;;; Citations

(defvar site--refs nil "Bibliography of the base being built (`refs-load').")
(defvar site--cited (make-hash-table :test 'equal) "Key -> ids of the notes citing it.")
(defvar site--note nil "Id of the note being exported.")

(defun site--cite (key)
  (let ((e (and site--refs (gethash key site--refs))))
    (if (not e)
        (progn (message "site: %s: unknown reference %s" (or site--note "?") key)
               (format "<span class=\"ref missing\">%s</span>" (org-html-encode-plain-text key)))
      (when site--note (cl-pushnew site--note (gethash key site--cited) :test #'equal))
      (format "<a class=\"ref\" href=\"%s\" data-full=\"%s\" aria-label=\"%s\">%s</a>"
              (or (refs-url e) (format "references.html#ref-%s" key))
              (site--attr (refs-full e)) (site--attr (refs-full e))
              (org-html-encode-plain-text (refs-short e))))))

(defun site--citation-html (citation)
  "(Author Year; Author Year) for [cite:@a;@b], each linked to the paper."
  (format "<span class=\"cite\">(%s)</span>"
          (mapconcat (lambda (r) (site--cite (org-element-property :key r)))
                     (org-cite-get-references citation) "; ")))

(defvar site-cite-latex-function nil
  "Function of a citation that writes it for LaTeX (set by manual.el).")

;; The notes' own citation processor: HTML here, LaTeX in manual.el.
(org-cite-register-processor 'kb
  :export-citation
  (lambda (citation _style backend _info)
    (org-export-raw-string
     (if (org-export-derived-backend-p backend 'latex)
         (funcall site-cite-latex-function citation)
       (site--citation-html citation)))))

;;;; Links

(defun site--link (link desc info)
  "Notes link to their sibling pages; web links stay; anything else keeps its text."
  (let ((type (org-element-property :type link))
        (path (org-element-property :path link)))
    (cond ((equal type "id")
           (if (kb--node path)
               (format "<a href=\"%s.html\">%s</a>" path
                       (or desc (org-html-encode-plain-text (kb--title path))))
             (or desc "")))
          ((member type '("http" "https" "mailto")) (org-html-link link desc info))
          (t (or desc (org-html-encode-plain-text path))))))

(org-export-define-derived-backend 'site 'html
  :translate-alist '((latex-fragment . site--latex-fragment)
                     (latex-environment . site--latex-environment)
                     (src-block . site--src-block)
                     (link . site--link)))

(defconst site--export-options
  '(:with-toc nil :section-numbers nil :with-sub-superscript {} :with-broken-links t
    :with-drawers nil :with-properties nil :with-tags nil :with-smart-quotes nil
    :html-doctype "html5" :html-html5-fancy t)
  "Export settings of every note.")

(defun site--export-buffer ()
  (let ((org-export-use-babel nil) (org-cite-export-processors '((t kb))))
    (org-export-as 'site nil nil t site--export-options)))

(defun site--org-inline (s)
  "HTML of the org string S, without the paragraph around it."
  (if (or (null s) (string-empty-p s))
      ""
    (with-temp-buffer
      (insert s)
      (org-mode)
      (let ((html (string-trim (site--export-buffer))))
        (if (string-match "\\`<p>\n?\\(\\(?:.\\|\n\\)*?\\)\n?</p>\\'" html)
            (match-string 1 html)
          html)))))

(defun site-note-html (file)
  "HTML body of the note FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (org-mode)
    ;; Deterministic ids of headlines and blocks: a rebuild changes only what changed.
    (random (concat "site:" file))
    (let ((site--counters nil)
          (site--note (file-name-base file)))
      (site--export-buffer))))

;;;; Text

(defun site--words (s) (if s (capitalize (replace-regexp-in-string "-" " " s)) ""))

(defvar site-url (or (getenv "SITE_URL") "https://4137314.github.io/cerebro/")
  "Public address of the site root, ending in /: canonical links and the sitemap.")

(defconst site-home-url "https://4137314.github.io/" "The author's site, linked from the pages.")

(defun site--plain (s)
  "S as plain text: no links, emphasis markers or TeX delimiters, single spaces."
  (let ((s (replace-regexp-in-string "\\\\[][()]" "" (kb--clean (or s "")))))
    ;; Again until nothing changes: neighbouring markers share the space between them.
    (let (prev)
      (while (not (equal prev s))
        (setq prev s
              s (replace-regexp-in-string
                 "\\(^\\|[[:space:](\"']\\)\\([/*=~+_]\\)\\([^[:space:]]\\(?:.*?[^[:space:]]\\)?\\)\\2\\([[:space:].,;:!?)\"']\\|$\\)"
                 "\\1\\3\\4" s))))
    (replace-regexp-in-string " -- " " – " s)))

(defun site--attr (s) (replace-regexp-in-string "\"" "&quot;" (org-html-encode-plain-text s)))

(defun site--raw-summary (file)
  (with-temp-buffer
    (insert-file-contents file)
    (and (re-search-forward "^#\\+summary:[ \t]*\\(.*\\)$" nil t) (match-string 1))))

;;;; Structure of a base

(defvar site--sequence nil "Ids of the base in reading order (index, prev/next, manuals).")
(defvar site--pdfs nil "Names of the PDF manuals of the base being built.")

(defun site--groups ()
  "Notes by domain and area, each list in study order: ((DOMAIN (AREA ID...)...)...).
Domains and areas follow the base's configuration; AREA is nil for notes without one."
  (let ((ids (seq-filter #'kb--node kb--order)))
    (delq nil
          (mapcar
           (lambda (domain)
             (let* ((in (seq-filter (lambda (i) (equal (kb--get i :domain) domain)) ids))
                    (areas (append (seq-filter (lambda (a) (seq-some (lambda (i) (equal (kb--get i :area) a)) in))
                                               kb--areas)
                                   (and (seq-some (lambda (i) (null (kb--get i :area))) in) '(nil)))))
               (and in
                    (cons domain
                          (mapcar (lambda (a) (cons a (seq-filter (lambda (i) (equal (kb--get i :area) a)) in)))
                                  areas)))))
           kb--domains))))

(defun site--reading-order ()
  (apply #'append (mapcar (lambda (g) (apply #'append (mapcar #'cdr (cdr g)))) (site--groups))))

(defun site--anchor (domain &optional area)
  (if area (format "a-%s--%s" domain area) (format "d-%s" domain)))

(defun site--pdf-name (domain &optional area)
  (if area (format "%s--%s.pdf" domain area) (format "%s.pdf" domain)))

(defun site--pdf-link (file label)
  "Link to the manual FILE (relative to the base directory) when it was built."
  (if (member file site--pdfs)
      (format "<a class=\"pdf\" href=\"pdf/%s\" title=\"PDF manual\">%s</a>" file label)
    ""))

;;;; Pages

(defun site--topbar (crumbs)
  "Navigation bar: breadcrumbs CRUMBS (HTML) and the search field."
  (concat "<nav class=\"top\"><span class=\"crumbs\">" crumbs "</span>"
          "<input id=\"q\" type=\"search\" placeholder=\"Search all notes   /\" aria-label=\"Search all notes\" autocomplete=\"off\" spellcheck=\"false\">"
          "</nav>\n"))

(defun site--page (title body &optional up path description)
  "A whole page: TITLE, BODY (HTML); UP is \"../\" for pages in a base.
PATH is the page's address relative to `site-url' (canonical link), DESCRIPTION its
summary for search engines and link previews."
  (let* ((title (site--plain title))
         (url (concat site-url (or path "")))
         (desc (truncate-string-to-width (site--plain description) 300 nil nil "…")))
    (format "<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>%s</title>
<meta name=\"description\" content=\"%s\">
<link rel=\"canonical\" href=\"%s\">
<meta property=\"og:type\" content=\"article\">
<meta property=\"og:site_name\" content=\"cerebro\">
<meta property=\"og:title\" content=\"%s\">
<meta property=\"og:description\" content=\"%s\">
<meta property=\"og:url\" content=\"%s\">
<link rel=\"stylesheet\" href=\"%sstyle.css\">
<script src=\"%ssite.js\" defer></script>
</head>
<body data-root=\"%s\">
%s
<footer><a href=\"%s\">Mattia Fait</a> · <a href=\"https://github.com/4137314/cerebro\">source</a> · <span class=\"keys\">press <kbd>?</kbd> for keyboard shortcuts</span></footer>
</body>
</html>
" (org-html-encode-plain-text title) (site--attr desc) url (site--attr title) (site--attr desc) url
  (or up "") (or up "") (or up "") body site-home-url)))

(defun site--note-link (id)
  (format "<a href=\"%s.html\">%s</a>" id (site--org-inline (kb--title id))))

(defun site--note-list (ids) (mapconcat #'site--note-link ids ", "))

(defun site--rel (label ids)
  (if ids (format "<p class=\"rel\"><span>%s</span> %s</p>\n" label (site--note-list ids)) ""))

(defun site--note-page (id base-title)
  (let* ((file (kb--get id :file))
         (domain (kb--get id :domain))
         (area (kb--get id :area))
         (pos (seq-position site--sequence id))
         (prev (and pos (> pos 0) (nth (1- pos) site--sequence)))
         (next (and pos (nth (1+ pos) site--sequence)))
         (needs (seq-filter #'kb--node (kb--get id :requires)))
         (unlocks (sort (copy-sequence (gethash id kb--users)) #'kb--rank<))
         (see (seq-filter #'kb--node (kb--get id :see)))
         (mentioned (sort (seq-remove (lambda (r) (or (member r unlocks) (member r needs)))
                                      (copy-sequence (gethash id kb--refs)))
                          #'kb--rank<))
         (path (kb--closure id))
         (up (concat "index.html#" (site--anchor domain area)))
         (meta (string-join (delq nil (list (kb--get id :kind) (site--words domain)
                                            (and area (site--words area))))
                            " · "))
         (pdfs (string-join
                (seq-remove #'string-empty-p
                            (list (if area (site--pdf-link (site--pdf-name domain area) (site--words area)) "")
                                  (site--pdf-link (site--pdf-name domain) (site--words domain))
                                  (site--pdf-link (concat site--base ".pdf") (concat "whole " base-title))))
                " · ")))
    (site--page
     (format "%s · %s" (kb--title id) base-title)
     (concat
      (site--topbar
       (concat "<a href=\"../index.html\">cerebro</a> / "
               (format "<a href=\"index.html\">%s</a> / " (org-html-encode-plain-text base-title))
               (format "<a href=\"index.html#%s\">%s</a>" (site--anchor domain) (site--words domain))
               (if area (format " / <a rel=\"up\" href=\"%s\">%s</a>" up (site--words area))
                 (format "<a rel=\"up\" href=\"%s\" hidden></a>" up))))
      "<header>\n"
      (format "<p class=\"meta\">%s</p>\n" (org-html-encode-plain-text meta))
      (format "<h1>%s</h1>\n" (site--org-inline (kb--title id)))
      (format "<p class=\"summary\">%s</p>\n" (site--org-inline (site--raw-summary file)))
      (site--rel "needs" needs)
      (site--rel "unlocks" unlocks)
      (site--rel "see also" see)
      (site--rel "mentioned in" mentioned)
      (if path
          (format "<details class=\"path\"><summary>Learning path: %d %s here, in study order</summary><ol>%s</ol></details>\n"
                  (length path) (if (= (length path) 1) "note leads" "notes lead")
                  (mapconcat (lambda (p) (concat "<li>" (site--note-link p) "</li>")) path ""))
        "")
      "</header>\n<main class=\"note\">\n"
      (site-note-html file)
      "</main>\n"
      "<nav class=\"pn\">"
      (if prev (format "<a rel=\"prev\" href=\"%s.html\"><span>← previous</span>%s</a>" prev (site--org-inline (kb--title prev))) "<span></span>")
      (if next (format "<a rel=\"next\" href=\"%s.html\"><span>next →</span>%s</a>" next (site--org-inline (kb--title next))) "<span></span>")
      "</nav>\n"
      (if (string-empty-p pdfs) "" (format "<p class=\"dl\"><span>PDF</span> %s</p>\n" pdfs)))
     "../" (format "%s/%s.html" site--base id) (kb--get id :summary))))

(defun site--index-page (base-title)
  (let* ((groups (site--groups))
         (n (length site--sequence)))
    (site--page
     (format "%s notes" base-title)
     (concat
      (site--topbar (format "<a href=\"../index.html\">cerebro</a> / %s" (org-html-encode-plain-text base-title)))
      (format "<header><h1>%s</h1><p class=\"meta\">%d notes, in study order</p>\n" (org-html-encode-plain-text base-title) n)
      (format "<p class=\"rel\">%s%s<a rel=\"next\" href=\"%s.html\">start reading →</a></p>\n"
              (let ((l (site--pdf-link (concat site--base ".pdf") (format "%s manual (PDF)" base-title))))
                (if (string-empty-p l) "" (concat l " · ")))
              (if (> (hash-table-count site--cited) 0)
                  (format "<a href=\"references.html\">references (%d)</a> · " (hash-table-count site--cited))
                "")
              (car site--sequence))
      "<a rel=\"up\" href=\"../index.html\" hidden></a>"
      "<details class=\"toc\" open><summary>Contents</summary><ol>"
      (mapconcat (lambda (g)
                   (format "<li><a href=\"#%s\">%s</a> <span class=\"kind\">%d</span></li>"
                           (site--anchor (car g)) (site--words (car g))
                           (apply #'+ (mapcar (lambda (a) (length (cdr a))) (cdr g)))))
                 groups "")
      "</ol></details></header>\n<main>\n"
      (mapconcat
       (lambda (g)
         (let ((domain (car g)))
           (concat
            (format "<h2 id=\"%s\">%s %s</h2>\n" (site--anchor domain) (site--words domain)
                    (site--pdf-link (site--pdf-name domain) "PDF"))
            (mapconcat
             (lambda (a)
               (concat
                (if (car a)
                    (format "<h3 id=\"%s\">%s %s</h3>\n" (site--anchor domain (car a)) (site--words (car a))
                            (site--pdf-link (site--pdf-name domain (car a)) "PDF"))
                  "<h3>Other notes</h3>\n")
                "<ul class=\"notes\">\n"
                (mapconcat
                 (lambda (i)
                   (format "<li><a href=\"%s.html\">%s</a> <span class=\"kind\">%s</span><br><span class=\"summary\">%s</span></li>\n"
                           i (site--org-inline (kb--title i)) (or (kb--get i :kind) "")
                           (site--org-inline (site--raw-summary (kb--get i :file)))))
                 (cdr a) "")
                "</ul>\n"))
             (cdr g) ""))))
       groups "")
      "</main>\n")
     "../" (concat site--base "/")
     (format "%s: %d notes on %s, one concept per note, in study order with their prerequisites."
             base-title n
             (string-join (mapcar (lambda (g) (downcase (site--words (car g)))) groups) ", ")))))

(defun site--references-page (base-title)
  "Every paper cited in the base, with the notes that cite it."
  (let ((keys (sort (hash-table-keys site--cited)
                    (lambda (a b) (string< (refs-short (gethash a site--refs))
                                           (refs-short (gethash b site--refs)))))))
    (site--page
     (format "References · %s" base-title)
     (concat
      (site--topbar (format "<a href=\"../index.html\">cerebro</a> / <a rel=\"up\" href=\"index.html\">%s</a> / references"
                            (org-html-encode-plain-text base-title)))
      (format "<header><h1>References</h1><p class=\"summary\">The %d papers and books cited in the %s notes: where each result was first proved, measured or proposed.</p></header>\n<main>\n<ol class=\"refs\">\n"
              (length keys) (org-html-encode-plain-text base-title))
      (mapconcat
       (lambda (k)
         (let* ((e (gethash k site--refs)) (url (refs-url e)))
           (format "<li id=\"ref-%s\"><b>%s</b> %s%s<br><span class=\"rel\"><span>cited in</span> %s</span></li>\n"
                   k (org-html-encode-plain-text (refs-short e)) (org-html-encode-plain-text (refs-full e))
                   (if url (format " <a href=\"%s\">%s</a>" url (org-html-encode-plain-text (replace-regexp-in-string "\\`https://\\(doi.org/\\)?" "" url))) "")
                   (site--note-list (sort (copy-sequence (gethash k site--cited)) #'kb--rank<)))))
       keys "")
      "</ol>\n</main>\n")
     "../" (concat site--base "/references.html")
     (format "Original papers cited in the %s notes." base-title))))

;;;; Search index and base summary

(defun site--search-entries (base-title)
  "Entries of the base for site.js: notes, then areas."
  (append
   (mapcar (lambda (id)
             (let ((al (kb--get id :aliases)))
               `((t . ,(site--plain (kb--title id)))
                 (s . ,(truncate-string-to-width (site--plain (kb--get id :summary)) 240 nil nil "…"))
                 (u . ,(format "%s/%s.html" site--base id))
                 (b . ,base-title)
                 (d . ,(site--words (kb--get id :domain)))
                 (a . ,(site--words (kb--get id :area)))
                 (k . ,(or (kb--get id :kind) ""))
                 ,@(and al `((al . ,al))))))
           site--sequence)
   (apply #'append
          (mapcar (lambda (g)
                    (mapcar (lambda (a)
                              `((t . ,(site--words (car a)))
                                (s . ,(format "%d notes" (length (cdr a))))
                                (u . ,(format "%s/index.html#%s" site--base (site--anchor (car g) (car a))))
                                (b . ,base-title) (d . ,(site--words (car g))) (a . "") (k . "area")))
                            (seq-filter #'car (cdr g))))
                  (site--groups)))))

(defun site--write-json (file data)
  (with-temp-file file
    (set-buffer-multibyte t)
    (insert (let ((json-encoding-pretty-print nil)) (json-encode data)))))

;;;; Building

(defun site--bib-file (config)
  "refs.bib next to the base's CONFIG, if there is one."
  (and config (not (string-empty-p config))
       (let ((f (expand-file-name "refs.bib" (file-name-directory config))))
         (and (file-exists-p f) f))))

(defun site-build-base (name title dir config out state &optional pdf)
  "Write the pages of base NAME (TITLE, notes in DIR, CONFIG) into OUT/NAME/.
STATE is the base's state directory (SVG cache), shared with the hub; PDF non-empty
also builds the manuals (manual.el)."
  (setq kb-dir (file-name-as-directory (expand-file-name dir))
        kb-state-dir (file-name-as-directory (expand-file-name state))
        site--base name
        site--used (make-hash-table :test 'equal))
  (make-directory kb-state-dir t)
  (when (and config (not (string-empty-p config)) (file-exists-p config))
    (load config nil t))
  (kb-reload)
  (setq site--sequence (site--reading-order)
        site--cited (make-hash-table :test 'equal)
        site--refs (refs-load (site--bib-file config)))
  (message "site: %s: rendering formulas (%d new)" name (kb-render-all t))
  (dolist (e kb--render-errors)
    (message "site: %s: LaTeX: %s in %s" name (cdr e) (truncate-string-to-width (car e) 100)))
  (kb--load-meta)
  (let ((dest (file-name-as-directory (expand-file-name name out))))
    (when (file-directory-p dest) (delete-directory dest t))
    (make-directory (expand-file-name "m" dest) t)
    (setq site--pdfs
          (and pdf (not (string-empty-p pdf))
               (progn (require 'manual)
                      (manual-build name title (site--groups) (expand-file-name "pdf" dest)
                                    (site--bib-file config)))))
    (dolist (id site--sequence)
      (with-temp-file (expand-file-name (concat id ".html") dest)
        (insert (site--note-page id title))))
    (when (> (hash-table-count site--cited) 0)
      (with-temp-file (expand-file-name "references.html" dest)
        (insert (site--references-page title))))
    (with-temp-file (expand-file-name "index.html" dest)
      (insert (site--index-page title)))
    (maphash (lambda (hash _) (copy-file (kb--svg hash) (expand-file-name (concat "m/" hash ".svg") dest) t))
             site--used)
    (site--write-json (expand-file-name "search.json" dest) (vconcat (site--search-entries title)))
    (site--write-json (expand-file-name "base.json" dest)
                      `((name . ,name) (title . ,title) (notes . ,(length site--sequence))
                        (pdf . ,(if (member (concat name ".pdf") site--pdfs) (concat name ".pdf") ""))))
    (message "site: %s: %d pages, %d pictures, %d PDF" name (length site--sequence)
             (hash-table-count site--used) (length site--pdfs))))

(defun site-base-main ()
  "Command line: NAME TITLE DIR CONFIG OUT STATE PDF."
  (apply #'site-build-base command-line-args-left)
  (setq command-line-args-left nil))

(defun site--home (bases)
  "Home page of BASES: (base.json alist ...)."
  (site--page
   "cerebro"
   (concat
    (site--topbar "cerebro")
    (format "<header><h1>cerebro</h1><p class=\"summary\">Study notes as a small specialist encyclopedia: %d notes, one concept per note, each with its prerequisites, the notes it unlocks and the path that leads to it. Every base is also a PDF manual, whole or by domain and area.</p></header>\n<main>\n<ul class=\"bases\">\n"
            (apply #'+ (mapcar (lambda (b) (alist-get 'notes b)) bases)))
    (mapconcat (lambda (b)
                 (let ((name (alist-get 'name b)) (pdf (alist-get 'pdf b)))
                   (format "<li><a href=\"%s/index.html\">%s</a> <span class=\"kind\">%d notes</span>%s</li>\n"
                           name (org-html-encode-plain-text (alist-get 'title b)) (alist-get 'notes b)
                           (if (string-empty-p pdf) ""
                             (format " <a class=\"pdf\" href=\"%s/pdf/%s\">PDF</a>" name pdf)))))
               bases "")
    "</ul>\n"
    "<p class=\"keys\">Search with <kbd>/</kbd>; on a note, <kbd>j</kbd>/<kbd>k</kbd> move along the study order, <kbd>u</kbd> goes up to its area, <kbd>l</kbd> opens its learning path, <kbd>r</kbd> picks a random note, <kbd>?</kbd> lists every key.</p>\n"
    "</main>\n")
   nil "" (format "Study notes by Mattia Fait: %s. One concept per note, formulas and figures rendered from LaTeX, prerequisites linked, PDF manuals."
                  (string-join (mapcar (lambda (b) (alist-get 'title b)) bases) ", "))))

(defun site--write-sitemap (out)
  "Write OUT/sitemap.xml with every page under OUT (index.html as its directory)."
  (let ((pages (sort (directory-files-recursively out "\\.html\\'") #'string<)))
    (with-temp-file (expand-file-name "sitemap.xml" out)
      (insert "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
              "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n")
      (dolist (f pages)
        (let ((rel (file-relative-name f out)))
          (insert "<url><loc>" site-url
                  (replace-regexp-in-string "\\(?:\\`\\|/\\)index\\.html\\'"
                                            (lambda (m) (if (string-prefix-p "/" m) "/" "")) rel)
                  "</loc></url>\n")))
      (insert "</urlset>\n"))))

(defun site-index (registry out)
  "Home, assets, search index and sitemap of the bases already built in OUT,
in the order of REGISTRY."
  (let* ((tools (file-name-directory site--file))
         (bases (delq nil (mapcar (lambda (b)
                                    (let ((f (expand-file-name (concat (car b) "/base.json") out)))
                                      (and (file-exists-p f) (json-read-file f))))
                                  (site-bases registry "/")))))
    ;; Contents, not the files: a copy from the Nix store would stay read-only.
    (dolist (f '(("site.css" . "style.css") ("site.js" . "site.js")))
      (with-temp-file (expand-file-name (cdr f) out)
        (insert-file-contents (expand-file-name (car f) tools))))
    (with-temp-file (expand-file-name ".nojekyll" out))
    (with-temp-file (expand-file-name "index.html" out) (insert (site--home bases)))
    (site--write-json (expand-file-name "search.json" out)
                      (apply #'vconcat
                             (mapcar (lambda (b)
                                       (json-read-file (expand-file-name (concat (alist-get 'name b) "/search.json") out)))
                                     bases)))
    (site--write-sitemap out)
    (message "site: %d bases in %s" (length bases) out)))

(defun site--parse-args (args)
  "Options of `site-main' from the command-line ARGS."
  (let (pos bases pdf (build t) (index t))
    (while args
      (pcase (pop args)
        ("--base" (push (pop args) bases))
        ("--pdf" (setq pdf t))
        ("--no-index" (setq index nil))
        ("--index-only" (setq build nil))
        (a (push a pos))))
    (setq pos (nreverse pos))
    (list :registry (nth 0 pos) :hub (nth 1 pos) :out (nth 2 pos) :bases (nreverse bases)
          :pdf pdf :build build :index index)))

(defun site-main ()
  "Command line: REGISTRY HUB-ROOT OUT [--base NAME]... [--pdf] [--no-index|--index-only]."
  (let* ((o (site--parse-args command-line-args-left))
         (out (expand-file-name (plist-get o :out)))
         (state (or (getenv "SITE_STATE")
                    (expand-file-name "cerebro-emacs/bases" (or (getenv "XDG_STATE_HOME") "~/.local/state"))))
         (bases (seq-filter (lambda (b) (and (file-directory-p (plist-get (cdr b) :dir))
                                             (or (null (plist-get o :bases)) (member (car b) (plist-get o :bases)))))
                            (site-bases (plist-get o :registry) (plist-get o :hub))))
         (failed nil))
    (setq command-line-args-left nil)
    (make-directory out t)
    (when (plist-get o :build)
      (dolist (b bases)
        (let ((p (cdr b)))
          (message "== %s" (car b))
          (with-temp-buffer
            (unless (eql 0 (call-process (expand-file-name invocation-name invocation-directory)
                                         nil '(t t) nil
                                         "--batch" "-Q" "-L" (file-name-directory (locate-library "kb"))
                                         "-l" site--file "-f" "site-base-main"
                                         (car b) (plist-get p :title) (plist-get p :dir)
                                         (or (plist-get p :config) "") out
                                         (expand-file-name (car b) state)
                                         (if (plist-get o :pdf) "1" "")))
              (push (car b) failed))
            (message "%s" (string-trim-right (buffer-string)))))))
    (when (plist-get o :index) (site-index (plist-get o :registry) out))
    (when failed
      (message "site: failed: %s" (string-join failed " "))
      (kill-emacs 1))))

(provide 'site)
;;; site.el ends here
