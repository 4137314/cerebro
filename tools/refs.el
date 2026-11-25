;;; refs.el --- bibliography of a knowledge base -*- lexical-binding: t; -*-

;; A base cites the papers that first proved or found a result with org-cite,
;; [cite:@key] next to the statement; the entries are in refs.bib next to its
;; kb-config.el.  site.el shows them as "(Author Year)" with the full reference;
;; manual.el hands refs.bib to biblatex.

(require 'bibtex)
(require 'cl-lib)
(require 'subr-x)

(defconst refs--accents
  '(("\\\\\"{?\\([aeiouAEIOU]\\)}?" . "\\1\u0308") ("\\\\'{?\\([a-zA-Z]\\)}?" . "\\1\u0301")
    ("\\\\`{?\\([a-zA-Z]\\)}?" . "\\1\u0300") ("\\\\\\^{?\\([a-zA-Z]\\)}?" . "\\1\u0302")
    ("\\\\~{?\\([a-zA-Z]\\)}?" . "\\1\u0303") ("\\\\c{?\\([a-zA-Z]\\)}?" . "\\1\u0327")
    ("\\\\v{?\\([a-zA-Z]\\)}?" . "\\1\u030c") ("\\\\ss{}" . "ß") ("\\\\o{}" . "ø")
    ("--" . "–"))
  "LaTeX accents and dashes of BibTeX fields, as Unicode.")

(defun refs--detex (s)
  "S without TeX accents, braces or extra spaces."
  (let ((s (or s "")))
    (dolist (a refs--accents) (setq s (replace-regexp-in-string (car a) (cdr a) s t)))
    (string-trim (replace-regexp-in-string "[ \t\n]+" " " (replace-regexp-in-string "[{}]" "" s)))))

(defun refs-load (file)
  "Entries of the BibTeX FILE: hash key -> alist (FIELD . VALUE), with \"=type=\"."
  (let ((table (make-hash-table :test 'equal)))
    (when (and file (file-exists-p file))
      (with-temp-buffer
        (insert-file-contents file)
        (bibtex-mode)
        (bibtex-set-dialect 'biblatex t)
        (goto-char (point-min))
        (while (re-search-forward bibtex-entry-head nil t)
          (goto-char (match-beginning 0))
          (let ((e (bibtex-parse-entry t)))
            (puthash (cdr (assoc "=key=" e))
                     (mapcar (lambda (f) (cons (downcase (car f)) (cdr f))) e)
                     table)))))
    table))

(defun refs--field (entry name) (let ((v (cdr (assoc name entry)))) (and v (refs--detex v))))

(defun refs--names (entry)
  "Authors (or editors) of ENTRY as (LAST . FIRST) pairs."
  (mapcar (lambda (n)
            (let ((n (string-trim n)))
              (if (string-match "\\`\\([^,]+\\),\\(.*\\)\\'" n)
                  (cons (string-trim (match-string 1 n)) (string-trim (match-string 2 n)))
                (let ((w (split-string n)))
                  (cons (car (last w)) (string-join (butlast w) " "))))))
          (split-string (or (refs--field entry "author") (refs--field entry "editor") "Anonymous")
                        " and " t)))

(defun refs-short (entry)
  "\"Bohr 1913\", \"Aharonov and Bohm 1959\", \"Einstein et al. 1935\"."
  (let ((last (mapcar #'car (refs--names entry)))
        (year (or (refs--field entry "year")
                  (let ((d (refs--field entry "date"))) (and d (substring d 0 (min 4 (length d)))))
                  "n.d.")))
    (format "%s %s"
            (pcase (length last)
              (1 (car last))
              (2 (format "%s and %s" (car last) (cadr last)))
              (_ (format "%s et al." (car last))))
            year)))

(defun refs--initials (first)
  (mapconcat (lambda (w) (concat (substring w 0 1) "."))
             (split-string first "[ .~-]+" t) " "))

(defun refs--authors (entry)
  (let ((names (mapcar (lambda (n) (string-trim (concat (refs--initials (cdr n)) " " (car n))))
                       (refs--names entry))))
    (if (> (length names) 4)
        (concat (car names) " et al.")
      (pcase (length names)
        (1 (car names))
        (2 (format "%s and %s" (car names) (cadr names)))
        (_ (concat (string-join (butlast names) ", ") " and " (car (last names))))))))

(defun refs-full (entry)
  "The reference ENTRY as one line of text."
  (let* ((f (lambda (n) (refs--field entry n)))
         (type (downcase (cdr (assoc "=type=" entry))))
         (year (or (funcall f "year") (funcall f "date") "n.d.")))
    (if (member type '("book" "mvbook" "thesis" "phdthesis" "report" "techreport"))
        (format "%s, %s (%s)." (refs--authors entry) (funcall f "title")
                (string-join (delq nil (list (funcall f "publisher") (funcall f "address")
                                             (funcall f "institution") (funcall f "school") year))
                             ", "))
      (format "%s, “%s”, %s (%s)."
              (refs--authors entry) (funcall f "title")
              (concat (or (funcall f "journal") (funcall f "journaltitle") (funcall f "booktitle") "")
                      (if (funcall f "volume") (concat " " (funcall f "volume")) "")
                      (if (funcall f "pages") (concat ", " (funcall f "pages")) ""))
              year))))

(defun refs-url (entry)
  "DOI or URL of ENTRY, or nil."
  (let ((doi (refs--field entry "doi")) (url (cdr (assoc "url" entry))))
    (cond (doi (concat "https://doi.org/" doi)) (url (string-trim url)))))

(provide 'refs)
;;; refs.el ends here
