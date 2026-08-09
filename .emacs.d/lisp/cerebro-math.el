;;; cerebro-math.el --- a note per result, made in one keystroke -*- lexical-binding: t; -*-

;; The unit of this second brain is one *result* per note: a definition, a
;; theorem, a lemma. That only works if making one costs nothing -- the
;; moment "I should write this down as its own node" involves choosing a
;; file name, a location and a template, the idea gets appended to
;; whatever buffer is open instead, and the graph stops growing.
;;
;; So: `C-c m t' and you are typing a theorem. Everything the note needs
;; to be a first-class citizen here is filled in without asking --
;;
;;   - a file name you never see, and could not have chosen: the digest of
;;     the note's own metadata (cerebro-hash.el), `a3f19c04b2e7.org'. You
;;     are never asked what to call the file, because the file has no name
;;     to give: an untitled fragment and a finished theorem are named the
;;     same way, and retitling one later renames it by itself.
;;   - a file-level `:ID:', so it is an Org-roam node with backlinks the
;;     instant it exists (org-roam not required: this module is pure Org);
;;   - `:seed:' maturity, an empty `#+MSC:' -- born classified, exactly
;;     like the capture templates and `cerebro note new';
;;   - the right block (`#+begin_theorem' ...) with a `#+NAME:' *above*
;;     it, generated with the prefix the results layer expects
;;     (`thm-'/`def-'/...), so the note is part of the logical-dependency
;;     graph (`C-c r i') from the start rather than after you remember to
;;     add a name.
;;
;; The other half is extraction (`C-c m e'): select a statement buried in
;; a longer note, and it becomes its own note, with a link left behind
;; where it was. That is the operation that actually grows a Zettelkasten
;; out of prose you already wrote.
;;
;; The note *content* is built by pure functions (no buffer, no file), so
;; what these commands produce is unit-tested against the same conventions
;; bin/notes-lint.el enforces.

(require 'cerebro-org) ;; cerebro-math-directory, org-directory
(require 'cerebro-taxonomy) ;; the maturity ladder, as data
(require 'cerebro-hash) ;; what a note in notes/math/ is called
(require 'org-id)
(require 'seq)

(defgroup cerebro-math nil
  "Making one note per mathematical result."
  :group 'cerebro)

;; -- What kinds of note there are, as data ------------------------------
;; One row per kind: the Org block to open, the `#+NAME:' prefix the
;; results layer reads, whether a proof block follows, and the key it gets
;; under `C-c m'. Adding a kind is adding a row (invariant 3).
(defconst cerebro-math-kinds
  '((theorem     :block "theorem"     :prefix "thm"  :proof t   :key "t")
    (definition  :block "definition"  :prefix "def"  :proof nil :key "d")
    (lemma       :block "lemma"       :prefix "lem"  :proof t   :key "l")
    (proposition :block "proposition" :prefix "prop" :proof t   :key "p")
    (corollary   :block "corollary"   :prefix "cor"  :proof t   :key "c")
    (example     :block "example"     :prefix "ex"   :proof nil :key "x")
    (remark      :block "remark"      :prefix "rem"  :proof nil :key "r")
    ;; A conjecture is the one kind that does not live in notes/math/:
    ;; it is not a result, it is a claim of mine that nothing supports
    ;; yet, and it goes to notes/conjectures/ with the `conjecture' tag
    ;; already on it (the tag the linter reads to know a statement is
    ;; unproved on purpose).
    (conjecture  :block "conjecture"  :prefix "conj" :proof nil :key "j"
                 :directory conjecture :tags ("conjecture"))
    (note        :block nil           :prefix nil    :proof nil :key "n"))
  "The kinds of note `C-c m' can make.
`note' is the plain one: prose with no environment, for something that is
not a single statement. Every other kind produces a named block, which is
what puts it in the results graph. `:directory' says where the note goes
when that is not notes/math/, and `:tags' what it is born carrying.")

(defun cerebro-math-kind-directory (kind)
  "Where a KIND note is written."
  (pcase (plist-get (cdr (cerebro-math-kind kind)) :directory)
    ('conjecture cerebro-conjecture-directory)
    (_ cerebro-math-directory)))

(defun cerebro-math-kind-tags (kind &optional extra)
  "The `#+FILETAGS' a new KIND note carries, plus EXTRA."
  (append (plist-get (cdr (cerebro-math-kind kind)) :tags) extra))

(defun cerebro-math-kind (name)
  "The row of `cerebro-math-kinds' called NAME (a symbol)."
  (or (assq name cerebro-math-kinds)
      (user-error "cerebro-math: unknown kind `%s'" name)))

;; -- Naming (pure) ------------------------------------------------------

(defun cerebro-math-slug (title)
  "TITLE as a kebab-case slug, or nil when nothing survives.
Same shape as the slugs bin/cerebro-note writes, so a note made from the
shell and one made here are indistinguishable afterwards."
  (let ((slug (string-trim
               (replace-regexp-in-string
                "-+" "-"
                (replace-regexp-in-string
                 "[^a-z0-9]+" "-" (downcase (or title ""))))
               "-" "-")))
    (unless (string-empty-p slug) slug)))

(defun cerebro-math-file-name (text)
  "File name for the note whose contents are TEXT. Pure.

The digest of its metadata (cerebro-hash.el) and nothing else. There is
one case, not two: an untitled fragment and a finished theorem are named
identically, so writing something down never involves naming it, and
titling it afterwards renames the file with no work from you."
  (cerebro-hash-file-name (cerebro-hash-of-text text)))

(defun cerebro-math-result-name (kind title)
  "The `#+NAME:' for a KIND note called TITLE, or nil if it needs none.
`thm-uniqueness-of-limits' -- the prefix is what tells the results layer
and a human reader what kind of thing is being cited."
  (let ((prefix (plist-get (cdr (cerebro-math-kind kind)) :prefix))
        (slug (cerebro-math-slug title)))
    (when (and prefix slug) (concat prefix "-" slug))))

;; -- The note itself (pure) ---------------------------------------------

(defun cerebro-math-note-string (kind title id &optional body time tags msc)
  "The complete text of a new KIND note. Pure: no buffer, no file.

BODY is the statement to put inside the block (empty when starting from
scratch), TAGS extra `#+FILETAGS' beyond `:seed:', MSC the classification
if it is already known.

The layout is not free: `#+DEPENDS:' would go above `#+NAME:', and
`#+NAME:' goes *directly* above the `#+begin_' line -- putting anything
between them detaches the name and silently breaks the `single' export
(see CLAUDE.md). Generating it is how that stops being something to
remember.

The front matter closes with the `#+HASH:' line the file is named after
(cerebro-hash.el). It is written here, at birth, rather than on the first
save, so that a note is never on disk under a name that is not its own."
  (let* ((row (cdr (cerebro-math-kind kind)))
         (block (plist-get row :block))
         (name (cerebro-math-result-name kind title))
         (filetags (mapconcat #'identity
                              (cons "seed" (delq nil (copy-sequence tags)))
                              ":"))
         (text
          (concat
           ":PROPERTIES:\n"
           (format ":ID:       %s\n" id)
           ":END:\n"
           (format "#+TITLE: %s\n" (if (and title (not (string-empty-p title)))
                                       title
                                     "untitled"))
           (format "#+DATE: %s\n" (format-time-string "[%Y-%m-%d %a %H:%M]" time))
           (format "#+FILETAGS: :%s:\n" filetags)
           (format "#+MSC: %s\n\n" (or msc ""))
           (when block
             (concat (when name (format "#+NAME: %s\n" name))
                     (format "#+begin_%s\n%s\n#+end_%s\n" block (or body "") block)
                     (when (plist-get row :proof)
                       "\n#+begin_proof\n\n#+end_proof\n")))
           (unless block (concat (or body "") "\n")))))
    ;; The digest covers the metadata only, so adding the line it is
    ;; recorded on cannot change it -- the note names itself, in one pass.
    (cerebro-hash-set-line text (cerebro-hash-of-text text))))

;; -- Making one ---------------------------------------------------------

(defun cerebro-math--read-kind ()
  "Ask which kind of note to make, by name."
  (intern (completing-read "Kind: "
                           (mapcar (lambda (row) (symbol-name (car row)))
                                   cerebro-math-kinds)
                           nil t nil nil "theorem")))

(defun cerebro-math--point-into-block ()
  "Put point where you are about to type: inside the block, or at the end."
  (goto-char (point-min))
  (if (re-search-forward "^#\\+begin_[a-z]+\n" nil t)
      (goto-char (match-end 0))
    (goto-char (point-max))))

;;;###autoload
(defun cerebro-math-new (kind &optional title body tags)
  "Create a KIND note called TITLE and open it.
It goes to notes/math/, or wherever the kind says (`C-c m j', a
conjecture, goes to notes/conjectures/).
TITLE may be empty -- the file is then named from the note's own ID (see
`cerebro-math-file-name') and can be renamed, or left, forever.

Interactively: `C-c m n' asks for the kind, `C-c m t'/`d'/`l'/... skip
straight to one. With an active region, the region becomes the body --
which is `C-c m e' (`cerebro-math-extract') without the link back."
  (interactive
   (list (cerebro-math--read-kind)
         (read-string "Title (empty = name it later): ")))
  (let* ((id (org-id-new))
         (directory (file-name-as-directory (cerebro-math-kind-directory kind)))
         (text (cerebro-math-note-string kind title id body nil
                                         (cerebro-math-kind-tags kind tags)))
         (file (expand-file-name (cerebro-math-file-name text) directory)))
    (make-directory directory t)
    (with-temp-file file (insert text))
    ;; Register the ID now: a note nothing has visited yet is invisible to
    ;; `id:' link resolution until org rescans, which is exactly when you
    ;; are about to link to it.
    (org-id-add-location id file)
    (find-file file)
    (cerebro-math--point-into-block)
    (message "cerebro: %s -- %s" kind (file-name-nondirectory file))
    file))

(defun cerebro-math--kind-command (kind)
  "Build the interactive command that makes a KIND note."
  (lambda (title)
    (interactive (list (read-string (format "%s title (empty = name it later): "
                                            (capitalize (symbol-name kind))))))
    (let ((body (when (use-region-p)
                  (prog1 (string-trim (buffer-substring-no-properties
                                       (region-beginning) (region-end)))
                    (delete-region (region-beginning) (region-end))))))
      (cerebro-math-new kind title body))))

;; One command per kind, named `cerebro-math-new-theorem' and so on, so
;; each is a real `M-x' command with its own key -- generated from the
;; table rather than written out eight times.
(dolist (row cerebro-math-kinds)
  (defalias (intern (format "cerebro-math-new-%s" (car row)))
    (cerebro-math--kind-command (car row))
    (format "Create a %s note in notes/math/ and open it.
With an active region, the region becomes the statement (and is removed
from this buffer -- use `cerebro-math-extract' to leave a link behind)."
            (car row))))

;;;###autoload
(defun cerebro-math-extract (beg end kind title)
  "Move the region into its own KIND note and leave a link behind.
The Zettelkasten operation: a statement written inside a longer note
becomes a node of its own -- citable, dependable-on, with backlinks --
and the place it came from keeps an `id:' link, so nothing is lost from
either side."
  (interactive
   (progn
     (unless (use-region-p)
       (user-error "cerebro-math-extract: select the statement first"))
     (list (region-beginning) (region-end)
           (cerebro-math--read-kind)
           (read-string "Title (empty = name it later): "))))
  (let* ((body (string-trim (buffer-substring-no-properties beg end)))
         (id (org-id-new))
         (directory (file-name-as-directory (cerebro-math-kind-directory kind)))
         (text (cerebro-math-note-string kind title id body nil
                                         (cerebro-math-kind-tags kind)))
         (file (expand-file-name (cerebro-math-file-name text) directory))
         (description (if (string-empty-p (string-trim title))
                          (truncate-string-to-width body 40 nil nil "…")
                        title)))
    (make-directory directory t)
    (with-temp-file file (insert text))
    (org-id-add-location id file)
    (delete-region beg end)
    (insert (format "[[id:%s][%s]]" id description))
    (find-file-other-window file)
    (cerebro-math--point-into-block)
    (message "cerebro: extracted into %s" (file-name-nondirectory file))
    file))

(defun cerebro-math--title (file)
  "The `#+TITLE:' of FILE, or its file name when it has none.
Reads the front matter only: the title is on line four of every note
here, and a note is not worth loading whole to find out what it is
called."
  (with-temp-buffer
    (insert-file-contents file nil 0 2048)
    (goto-char (point-min))
    (if (re-search-forward "^#\\+TITLE:[ \t]*\\(.*\\)$" nil t)
        (string-trim (match-string 1))
      (file-name-nondirectory file))))

;;;###autoload
(defun cerebro-math-find ()
  "Open a note from notes/math/, by title.

By *title*, because the file names are digests (cerebro-hash.el) and
completing over them would be completing over noise. The title is read
out of each file, which is the only place it was ever true."
  (interactive)
  (let* ((files (directory-files cerebro-math-directory t "\\.org\\'"))
         (rows (mapcar (lambda (f) (cons (cerebro-math--title f) f)) files)))
    (unless rows (user-error "cerebro-math: no notes in %s yet" cerebro-math-directory))
    (find-file
     (cdr (assoc (completing-read "Math note: " (mapcar #'car rows) nil t) rows)))))


;; -- The maturity ladder, as an operation -------------------------------
;; `:seed:' -> `:growing:' -> `:evergreen:' is a state, and a state you
;; cannot change with a keystroke is a state nobody updates. The tag
;; itself stays what it always was -- one word in `#+FILETAGS:' -- so
;; nothing else in the config has to learn a new mechanism.

(defun cerebro-math-parse-filetags (line)
  "The tags in a `#+FILETAGS:' LINE, as a list of strings. Pure."
  (when (and line (string-match "\\`[ \t]*#\\+FILETAGS:[ \t]*\\(.*\\)\\'" line))
    (seq-remove #'string-empty-p
                (split-string (string-trim (match-string 1 line)) ":" t))))

(defun cerebro-math-filetags-line (tags)
  "A `#+FILETAGS:' line for TAGS. Pure; the inverse of the parser above."
  (if tags
      (format "#+FILETAGS: :%s:" (mapconcat #'identity tags ":"))
    "#+FILETAGS:"))

(defun cerebro-math--replace-filetags (tags)
  "Rewrite this buffer's `#+FILETAGS:' line to TAGS."
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "^[ \t]*#\\+FILETAGS:.*$" nil t)
        (replace-match (cerebro-math-filetags-line tags) t t)
      ;; No line yet: put one where the front matter is, under #+TITLE.
      (goto-char (point-min))
      (if (re-search-forward "^#\\+TITLE:.*$" nil t)
          (progn (end-of-line) (insert "\n" (cerebro-math-filetags-line tags)))
        (insert (cerebro-math-filetags-line tags) "\n")))))

;;;###autoload
(defun cerebro-math-set-maturity (maturity)
  "Set this note's maturity tag to MATURITY (`C-c m s').
Completes over `cerebro-maturity-ladder' and leaves every other tag
alone -- area, `crypt', `drill' and the rest are not this command's
business."
  (interactive
   (list (completing-read "Maturity: " cerebro-maturity-ladder nil t)))
  (unless (derived-mode-p 'org-mode)
    (user-error "cerebro-math: not an Org note"))
  (let* ((line (save-excursion
                 (goto-char (point-min))
                 (when (re-search-forward "^[ \t]*#\\+FILETAGS:.*$" nil t)
                   (match-string 0))))
         (tags (cerebro-math-parse-filetags line)))
    (cerebro-math--replace-filetags
     (cerebro-taxonomy-set-maturity tags maturity))
    (message "cerebro: %s" maturity)))

;;;###autoload
(defun cerebro-math-promote ()
  "Move this note one rung up the maturity ladder (`C-c m +').
seed -> growing -> evergreen, and no further: a note at the top is a
note you would hand to someone else, and there is nothing above that."
  (interactive)
  (let* ((line (save-excursion
                 (goto-char (point-min))
                 (when (re-search-forward "^[ \t]*#\\+FILETAGS:.*$" nil t)
                   (match-string 0))))
         (tags (cerebro-math-parse-filetags line))
         (current (cerebro-taxonomy-maturity tags))
         (next (cerebro-taxonomy-next-maturity current)))
    (if (not next)
        (message "cerebro: already %s -- the top of the ladder" current)
      (cerebro-math-set-maturity next))))

(provide 'cerebro-math)
