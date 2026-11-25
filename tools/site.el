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
;;   emacs --batch -Q -L <reader>/emacs -l site.el -f site-main REGISTRY HUB-ROOT OUT [STATE]

(require 'kb)
(require 'ox-html)
(require 'cl-lib)
(require 'subr-x)

(defconst site--file (or load-file-name buffer-file-name))

;; Links are resolved from the reader's index: org-id must not read or write a file.
(setq org-id-locations-file null-device)

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
             (alt (if (string-match-p "\\`\\\\begin{\\(?:tikz\\|circuitikz\\)" text)
                      "figure"
                    (org-html-encode-plain-text text)))
             (alt (replace-regexp-in-string "\"" "&quot;" alt)))
        (if blockp
            (format "<div class=\"mb\"><img class=\"m\" src=\"m/%s.svg\" alt=\"%s\" style=\"width:%s\"></div>"
                    hash alt (site--em (car size)))
          (let* ((ascent (gethash hash kb--meta 'center))
                 (depth (if (numberp ascent)
                            (* (cdr size) (- 1 (/ ascent 100.0)))
                          (/ (cdr size) 2.0))))
            (format "<img class=\"m\" src=\"m/%s.svg\" alt=\"%s\" style=\"height:%s;vertical-align:-%s\">"
                    hash alt (site--em (cdr size)) (site--em depth))))))))

(defun site--latex-fragment (fragment _contents _info)
  (let ((v (org-element-property :value fragment)))
    (if (string-prefix-p "$" v)
        (org-html-encode-plain-text v)
      (site--math v (string-prefix-p "\\[" v)))))

(defun site--latex-environment (env _contents _info)
  (site--math (org-element-property :value env) t))

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
                     (link . site--link)))

(defconst site--export-options
  '(:with-toc nil :section-numbers nil :with-sub-superscript {} :with-broken-links t
    :with-drawers nil :with-properties nil :with-tags nil :with-smart-quotes nil
    :html-doctype "html5" :html-html5-fancy t)
  "Export settings of every note.")

(defun site--export-buffer ()
  (let ((org-export-use-babel nil))
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
    (site--export-buffer)))

;;;; Pages

(defun site--words (s) (if s (capitalize (replace-regexp-in-string "-" " " s)) ""))

(defun site--page (title body &optional up)
  "A whole page: TITLE (plain text), BODY (HTML); UP is \"../\" for pages in a base."
  (format "<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>%s</title>
<link rel=\"stylesheet\" href=\"%sstyle.css\">
</head>
<body>
%s
</body>
</html>
" (org-html-encode-plain-text title) (or up "") body))

(defun site--raw-summary (file)
  (with-temp-buffer
    (insert-file-contents file)
    (and (re-search-forward "^#\\+summary:[ \t]*\\(.*\\)$" nil t) (match-string 1))))

(defun site--note-list (ids)
  (mapconcat (lambda (id) (format "<a href=\"%s.html\">%s</a>" id
                                  (site--org-inline (kb--title id))))
             ids ", "))

(defun site--note-page (id base-title)
  (let* ((file (kb--get id :file))
         (needs (seq-filter #'kb--node (kb--get id :requires)))
         (unlocks (sort (copy-sequence (gethash id kb--users)) #'kb--rank<))
         (meta (string-join (delq nil (list (kb--get id :kind)
                                            (site--words (kb--get id :domain))
                                            (and (kb--get id :area) (site--words (kb--get id :area)))))
                            " · ")))
    (site--page
     (format "%s · %s" (kb--title id) base-title)
     (concat
      (format "<nav><a href=\"../index.html\">cerebro</a> / <a href=\"index.html\">%s</a></nav>\n"
              (org-html-encode-plain-text base-title))
      "<header>\n"
      (format "<p class=\"meta\">%s</p>\n" (org-html-encode-plain-text meta))
      (format "<h1>%s</h1>\n" (site--org-inline (kb--title id)))
      (format "<p class=\"summary\">%s</p>\n" (site--org-inline (site--raw-summary file)))
      (if needs (format "<p class=\"rel\"><span>needs</span> %s</p>\n" (site--note-list needs)) "")
      (if unlocks (format "<p class=\"rel\"><span>unlocks</span> %s</p>\n" (site--note-list unlocks)) "")
      "</header>\n<main>\n"
      (site-note-html file)
      "</main>\n")
     "../")))

(defun site--index-page (base-title)
  (let ((ids (seq-filter #'kb--node kb--order)))
    (site--page
     base-title
     (concat
      "<nav><a href=\"../index.html\">cerebro</a></nav>\n"
      (format "<header><h1>%s</h1><p class=\"meta\">%d notes, in study order</p></header>\n<main>\n"
              (org-html-encode-plain-text base-title) (length ids))
      (mapconcat
       (lambda (domain)
         (let ((in-domain (seq-filter (lambda (i) (equal (kb--get i :domain) domain)) ids)))
           (concat
            (format "<h2>%s</h2>\n" (site--words domain))
            (mapconcat
             (lambda (area)
               (let ((notes (seq-filter (lambda (i) (equal (kb--get i :area) area)) in-domain)))
                 (if (null notes) ""
                   (concat
                    (format "<h3>%s</h3>\n<ul class=\"notes\">\n" (site--words area))
                    (mapconcat
                     (lambda (i)
                       (format "<li><a href=\"%s.html\">%s</a> <span class=\"kind\">%s</span><br><span class=\"summary\">%s</span></li>\n"
                               i (site--org-inline (kb--title i))
                               (or (kb--get i :kind) "")
                               (site--org-inline (site--raw-summary (kb--get i :file)))))
                     notes "")
                    "</ul>\n"))))
             (append (seq-filter (lambda (a) (seq-some (lambda (i) (equal (kb--get i :area) a)) in-domain))
                                 kb--areas)
                     (and (seq-some (lambda (i) (null (kb--get i :area))) in-domain) '(nil)))
             ""))))
       kb--domains "")
      "</main>\n")
     "../")))

(defun site-build-base (name title dir config out state)
  "Write the pages of base NAME (TITLE, notes in DIR, CONFIG) into OUT/NAME/.
STATE is the base's state directory (SVG cache), shared with the hub."
  (setq kb-dir (file-name-as-directory (expand-file-name dir))
        kb-state-dir (file-name-as-directory (expand-file-name state))
        site--used (make-hash-table :test 'equal))
  (make-directory kb-state-dir t)
  (when (and config (not (string-empty-p config)) (file-exists-p config))
    (load config nil t))
  (kb-reload)
  (message "site: %s: rendering formulas (%d new)" name (kb-render-all t))
  (dolist (e kb--render-errors)
    (message "site: %s: LaTeX: %s in %s" name (cdr e) (truncate-string-to-width (car e) 100)))
  (kb--load-meta)
  (let ((dest (file-name-as-directory (expand-file-name name out))))
    (when (file-directory-p dest) (delete-directory dest t))
    (make-directory (expand-file-name "m" dest) t)
    (let ((n 0))
      (dolist (id kb--order)
        (when (kb--node id)
          (with-temp-file (expand-file-name (concat id ".html") dest)
            (insert (site--note-page id title)))
          (setq n (1+ n))))
      (with-temp-file (expand-file-name "index.html" dest)
        (insert (site--index-page title)))
      (maphash (lambda (hash _) (copy-file (kb--svg hash) (expand-file-name (concat "m/" hash ".svg") dest) t))
               site--used)
      (message "site: %s: %d pages, %d pictures" name n (hash-table-count site--used)))))

(defun site-base-main ()
  "Command line: NAME TITLE DIR CONFIG OUT STATE."
  (apply #'site-build-base command-line-args-left)
  (setq command-line-args-left nil))

(defun site--home (bases)
  (site--page
   "cerebro"
   (concat
    "<header><h1>cerebro</h1><p class=\"meta\">knowledge bases: one concept per note, prerequisites first</p></header>\n<main>\n<ul class=\"bases\">\n"
    (mapconcat (lambda (b)
                 (format "<li><a href=\"%s/index.html\">%s</a> <span class=\"kind\">%d notes</span></li>\n"
                         (car b) (org-html-encode-plain-text (plist-get (cdr b) :title))
                         (length (directory-files-recursively (plist-get (cdr b) :dir) "\\.org\\'"))))
               bases "")
    "</ul>\n</main>\n")))

(defun site-main ()
  "Command line: REGISTRY HUB-ROOT OUT [STATE-ROOT]; builds every published base."
  (pcase-let* ((`(,registry ,hub ,out ,state) command-line-args-left)
               (out (expand-file-name out))
               (state (or state (getenv "SITE_STATE")
                          (expand-file-name "cerebro-emacs/bases"
                                            (or (getenv "XDG_STATE_HOME") "~/.local/state"))))
               (bases (seq-filter (lambda (b) (file-directory-p (plist-get (cdr b) :dir)))
                                  (site-bases registry hub)))
               (failed nil))
    (setq command-line-args-left nil)
    (make-directory out t)
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
                                       (expand-file-name (car b) state)))
            (push (car b) failed))
          (message "%s" (string-trim-right (buffer-string))))))
    (copy-file (expand-file-name "site.css" (file-name-directory site--file))
               (expand-file-name "style.css" out) t)
    (with-temp-file (expand-file-name ".nojekyll" out))
    (with-temp-file (expand-file-name "index.html" out) (insert (site--home bases)))
    (when failed
      (message "site: failed: %s" (string-join failed " "))
      (kill-emacs 1))
    (message "site: %d bases in %s" (length bases) out)))

(provide 'site)
;;; site.el ends here
