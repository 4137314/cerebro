;;; cerebro-bib.el --- one bibliography, and the keys to feed it -*- lexical-binding: t; -*-

;; Citations were the last thing in this archive still done by hand: you
;; opened bib/references.bib in another window, typed a BibTeX entry from
;; memory, invented a key, went back and typed `[cite:@that-key]' -- and
;; found out whether the key matched at the next compile. Three chances
;; to be wrong, none of them checked.
;;
;; This module closes that loop, and it does it around one idea:
;;
;;   THERE IS EXACTLY ONE BIBLIOGRAPHY.
;;
;; bib/references.bib, for the whole archive -- every note, every course,
;; every conjecture. Not one per course, not one per paper. A reference
;; is a fact about the literature, not about the document that happens to
;; cite it, and the moment there are two files the same book acquires two
;; keys and the graph quietly stops being able to answer "what else did I
;; read this in?".
;;
;; On top of that single file:
;;
;;   - `C-c b i' inserts a citation with completion over the whole
;;     bibliography -- author, year and title, not a bare key. citar does
;;     this when the environment has it (guix.scm); org-cite's own
;;     `org-cite-insert' does it plainly when it does not.
;;   - `C-c b n' adds a NEW entry by asking for the fields that entry
;;     type actually needs (`cerebro-bib-entry-types' -- data), generating
;;     the key from author/year/title, refusing a duplicate, appending it
;;     to the one file, and offering to cite it right there.
;;   - `C-c b y' imports an entry you already have (from the kill ring, or
;;     a .bib file someone sent you), re-keyed to the house convention.
;;   - `C-c b o' opens what a citation points at; `C-c b f' opens the
;;     bibliography itself.
;;
;; And the check that makes the rest trustworthy: `cerebro lint' reads
;; every `[cite:@key]' in every note and fails on a key the bibliography
;; does not define (bin/notes-lint.el). A citation that would silently
;; typeset as a bold `[key?]' is now a push that does not happen.
;;
;; Deliberately offline. Nothing here fetches a DOI or searches a
;; database: this repository is offline by design (invariant 1), and a
;; reference you typed once, into one file, checked by the linter, is
;; worth more than one auto-fetched into three.

(require 'cerebro-org)  ;; cerebro-bib-file: THE bibliography
(require 'cerebro-guix) ;; cerebro-guix-soft-require
(require 'oc)
(require 'seq)
(require 'subr-x)

(defgroup cerebro-bib nil
  "The one bibliography, and how entries get into it."
  :group 'cerebro)

;; -- What an entry needs, as data ---------------------------------------
;; One row per BibTeX type: which fields are asked for, in order. Adding a
;; type is adding a row. The list is short on purpose -- these are the
;; things a mathematician actually cites -- and `misc' is the escape
;; hatch for everything else.

(defconst cerebro-bib-entry-types
  '(("article"       :fields ("author" "title" "journal" "year" "volume" "pages" "doi"))
    ("book"          :fields ("author" "title" "publisher" "year" "edition" "isbn"))
    ("incollection"  :fields ("author" "title" "booktitle" "publisher" "year" "pages"))
    ("inproceedings" :fields ("author" "title" "booktitle" "year" "pages"))
    ("phdthesis"     :fields ("author" "title" "school" "year"))
    ("misc"          :fields ("author" "title" "year" "howpublished" "url")))
  "BibTeX entry types this archive writes, and the fields each one asks
for. The first four are always asked; the rest may be left empty and are
then omitted from the entry rather than written blank.")

(defconst cerebro-bib-required-fields 4
  "How many of a type's `:fields' are asked for insistently.
The rest are offered and may be skipped: an entry with no DOI is a fine
entry, an entry with no author is a mistake.")

(defun cerebro-bib-type-fields (type)
  "The fields entry TYPE asks for."
  (plist-get (cdr (or (assoc type cerebro-bib-entry-types)
                      (user-error "cerebro-bib: unknown entry type `%s'" type)))
             :fields))

;; -- Keys (pure) --------------------------------------------------------

(defun cerebro-bib--slug (string)
  "STRING reduced to lowercase ASCII letters and digits. Pure.
A BibTeX key travels through TeX, a shell script and a file name;
anything that is not [a-z0-9] in one is a quoting bug in another."
  (replace-regexp-in-string "[^a-z0-9]" "" (downcase (or string ""))))

(defun cerebro-bib-surname (author)
  "The first author's surname, in lowercase ASCII. Pure.

BibTeX author fields come in two shapes -- `Rudin, Walter' and `Walter
Rudin' -- and a key generator that only understands one of them produces
`walter1976' for half the library."
  ;; `or ""' twice, not once: `split-string' on an empty author returns
  ;; an empty LIST, so `car' is nil and the match below dies on it.
  ;; "an entry with no author" is exactly the half-filled state this
  ;; function has to survive -- it is what produces the visible `anon'
  ;; key rather than a backtrace in the middle of adding a reference.
  (let* ((first (or (car (split-string (or author "") " and " t "[ \t\n]+")) ""))
         (surname (if (string-match "\\`\\([^,]+\\)," first)
                      (match-string 1 first)
                    (car (last (split-string (string-trim first) "[ \t]+" t))))))
    (cerebro-bib--slug (or surname ""))))

(defun cerebro-bib-key (author year title)
  "The citation key for a work. Pure: `rudin1976principles'.

Surname, year, and the first word of the title that carries meaning --
the convention every bibliography style guesses at, made explicit so two
entries typed a year apart get keys of the same shape."
  (let* ((surname (cerebro-bib-surname author))
         (year (replace-regexp-in-string "[^0-9]" "" (or year "")))
         (stop '("a" "an" "the" "on" "of" "in" "to" "and" "for" "with"))
         (words (seq-remove
                 (lambda (w) (or (string-empty-p w) (member w stop)))
                 (split-string (downcase (or title "")) "[^a-z0-9]+" t)))
         (word (cerebro-bib--slug (car words))))
    (concat (if (string-empty-p surname) "anon" surname)
            (if (string-empty-p year) "" year)
            word)))

(defun cerebro-bib-format-entry (type key fields)
  "A BibTeX entry as text. Pure.

FIELDS is an alist of (NAME . VALUE); empty values are dropped rather
than written as `field = {}', because an empty field is a claim that the
work has none. Braced values, one per line, two-space indent: the shape
`biber' and every human reader expect."
  (concat (format "@%s{%s,\n" type key)
          (mapconcat
           (lambda (field)
             (format "  %s = {%s}," (car field) (string-trim (cdr field))))
           (seq-remove (lambda (field)
                         (string-empty-p (string-trim (or (cdr field) ""))))
                       fields)
           "\n")
          "\n}\n"))

(defun cerebro-bib-parse-keys (text)
  "Every citation key defined in the BibTeX TEXT. Pure.
Line-based, like every other parser here: a full BibTeX grammar is not
needed to answer \"which keys exist\", and not having one means this
works on a file `parsebib' would refuse."
  (let ((keys nil) (start 0))
    (while (string-match "^[ \t]*@[A-Za-z]+[ \t]*[{(][ \t]*\\([^ \t,\n]+\\)[ \t]*,"
                         text start)
      (push (match-string 1 text) keys)
      (setq start (match-end 0)))
    (nreverse keys)))

(defun cerebro-bib-entry-type (text)
  "The BibTeX type of the entry in TEXT, downcased, or nil. Pure."
  (when (string-match "\\`[ \t\n]*@\\([A-Za-z]+\\)[ \t]*[{(]" text)
    (downcase (match-string 1 text))))

(defun cerebro-bib-field (text field)
  "The value of FIELD in the BibTeX entry TEXT, or nil. Pure.
Handles one level of nested braces, which is what a title with a
`{TeX}'-protected word needs and all that a hand-written entry has."
  (when (string-match (format "^[ \t]*%s[ \t]*=[ \t]*[{\"]\\(\\(?:[^{}]\\|{[^{}]*}\\)*\\)[}\"]"
                              (regexp-quote field))
                      text)
    (string-trim (match-string 1 text))))

(defun cerebro-bib-rekey (text key)
  "The BibTeX entry TEXT with its key replaced by KEY. Pure."
  (if (string-match "\\(\\`[ \t\n]*@[A-Za-z]+[ \t]*[{(][ \t]*\\)\\([^ \t,\n]+\\)" text)
      (concat (substring text 0 (match-end 1)) key
              (substring text (match-end 2)))
    text))

;; -- The one file (impure) ----------------------------------------------

(defun cerebro-bib-text ()
  "The bibliography's contents, or \"\" when it does not exist yet."
  (if (file-readable-p cerebro-bib-file)
      (with-temp-buffer (insert-file-contents cerebro-bib-file) (buffer-string))
    ""))

(defun cerebro-bib-keys ()
  "Every key the bibliography defines."
  (cerebro-bib-parse-keys (cerebro-bib-text)))

(defun cerebro-bib-unique-key (key taken)
  "KEY, suffixed a/b/c... until it is not in TAKEN. Pure.
Two papers by the same author in the same year on the same first word is
rare and real; silently overwriting one of them is not acceptable. TAKEN
is passed in rather than read here so that an empty list means \"nothing
is taken\" -- `(or existing (cerebro-bib-keys))' read the whole file when
the caller said the list was empty, which is a different question."
  (let ((candidate key)
        (suffix ?a))
    (while (member candidate taken)
      (setq candidate (format "%s%c" key suffix)
            suffix (1+ suffix)))
    candidate))

(defun cerebro-bib--append (entry)
  "Append ENTRY (text) to the bibliography, and save. Returns its key."
  (with-current-buffer (find-file-noselect cerebro-bib-file)
    (goto-char (point-max))
    (unless (or (bobp) (looking-back "\n\n" (max (point-min) (- (point) 2))))
      (insert (if (looking-back "\n" (max (point-min) (1- (point)))) "\n" "\n\n")))
    (insert entry)
    (save-buffer))
  (car (cerebro-bib-parse-keys entry)))

;; -- Adding a reference -------------------------------------------------

;;;###autoload
(defun cerebro-bib-new (&optional insert)
  "Add a new reference to the bibliography (`C-c b n').

Asks for the entry type, then for the fields that type needs -- the
first `cerebro-bib-required-fields' insistently, the rest optionally --
generates the key, refuses to shadow an existing one, appends the entry
to the single bibliography and reports the key. With a prefix argument
\(or INSERT non-nil), also inserts `[cite:@key]' at point, which is
usually why you were adding it."
  (interactive "P")
  (let* ((type (completing-read "Entry type: "
                                (mapcar #'car cerebro-bib-entry-types)
                                nil t nil nil "article"))
         (names (cerebro-bib-type-fields type))
         (fields
          (let ((index 0) collected)
            (dolist (name names (nreverse collected))
              (let* ((required (< index cerebro-bib-required-fields))
                     (value (read-string
                             (format "%s%s: " name (if required "" " (optional)")))))
                (when (and required (string-empty-p (string-trim value)))
                  (user-error "cerebro-bib: `%s' is not optional" name))
                (setq index (1+ index))
                (push (cons name value) collected)))))
         (key (cerebro-bib-unique-key
               (cerebro-bib-key (cdr (assoc "author" fields))
                                (cdr (assoc "year" fields))
                                (cdr (assoc "title" fields)))
               (cerebro-bib-keys)))
         (entry (cerebro-bib-format-entry type key fields)))
    (cerebro-bib--append entry)
    (when insert (insert (format "[cite:@%s]" key)))
    (message "cerebro: added @%s to %s" key
             (file-relative-name cerebro-bib-file cerebro-root))
    key))

;;;###autoload
(defun cerebro-bib-yank (&optional text)
  "Import a BibTeX entry from the kill ring into the bibliography
\(`C-c b y'), re-keyed to the house convention.

The other way references arrive: someone sends you an entry, or a
publisher's page gives you one. It is added with a key generated from
its own author/year/title exactly like a typed one, so the bibliography
has one naming convention rather than one per source."
  (interactive)
  (let* ((text (or text (current-kill 0)))
         (type (or (cerebro-bib-entry-type text)
                   (user-error "cerebro-bib: that is not a BibTeX entry")))
         (key (cerebro-bib-unique-key
               (cerebro-bib-key (cerebro-bib-field text "author")
                                (cerebro-bib-field text "year")
                                (cerebro-bib-field text "title"))
               (cerebro-bib-keys)))
         (entry (concat (string-trim (cerebro-bib-rekey text key)) "\n")))
    (cerebro-bib--append entry)
    (message "cerebro: imported @%s (%s)" key type)
    key))

;;;###autoload
(defun cerebro-bib-find ()
  "Open the bibliography (`C-c b f')."
  (interactive)
  (find-file cerebro-bib-file))

;;;###autoload
(defun cerebro-bib-insert ()
  "Insert a citation at point (`C-c b i').

`org-cite-insert' is the door: with citar installed it completes over
author/year/title and can insert several keys at once; without it, Org's
own basic processor completes over the keys. Either way the citation is
`[cite:@key]' in the file -- the syntax is Org's, not a package's, which
is why the archive keeps working when the package is not there."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "cerebro-bib: citations go in Org notes"))
  (call-interactively #'org-cite-insert))

;;;###autoload
(defun cerebro-bib-open ()
  "Open what the citation at point refers to (`C-c b o').
citar's job -- the PDF, the URL, the note -- and a plain message saying
so when the environment has no citar."
  (interactive)
  (if (fboundp 'citar-open)
      (call-interactively #'citar-open)
    (message "cerebro: citar is not in this environment -- C-c b f opens the .bib")))

;; -- The powerful half, when the environment has it ---------------------
;; citar is the completion/annotation front end for org-cite: candidates
;; are shown as author, year and title, with an indicator for which ones
;; have a PDF or a note. It is a guix.scm package and therefore optional
;; (invariant 4): configured when present, and every command above still
;; works when it is not.

(when (cerebro-guix-soft-require 'citar)
  (setq citar-bibliography (list cerebro-bib-file))
  ;; org-cite has three processors and citar implements all three: the
  ;; one that inserts a citation, the one that makes it clickable, and
  ;; the one that fontifies it in the buffer so a wrong key is visible
  ;; while you type rather than at the next compile.
  (setq org-cite-insert-processor 'citar
        org-cite-follow-processor 'citar
        org-cite-activate-processor 'citar)
  ;; Notes about a reference are notes: they live in notes/math/ like
  ;; everything else, and citar finds them by the citation key recorded
  ;; in a `:ROAM_REFS:'/`#+KEY:' property rather than by a parallel
  ;; directory of its own.
  (setq citar-notes-paths (list cerebro-math-directory))
  (when (cerebro-guix-soft-require 'citar-embark)
    (citar-embark-mode 1)))

(provide 'cerebro-bib)
