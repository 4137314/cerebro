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
;;   - a file name you never see: `<timestamp>-<slug>.org' in notes/math/,
;;     and for a note you do not want to *name* yet, `<timestamp>-<hash>'
;;     from its own ID. A nameless idea is still a node, still linkable,
;;     still findable; the name can come later, and renaming the file
;;     breaks nothing (links are by :ID:).
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
    (note        :block nil           :prefix nil    :proof nil :key "n"))
  "The kinds of note `C-c m' can make.
`note' is the plain one: prose with no environment, for something that is
not a single statement. Every other kind produces a named block, which is
what puts it in the results graph.")

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

(defun cerebro-math-file-name (title id &optional time)
  "File name for a note called TITLE with identifier ID, made at TIME.

Two cases, and the second is the point: a titled note is
`20260806093000-uniqueness-of-limits.org', but an *untitled* one --
the idea you want to write down before you know what it is called -- is
`20260806093000-a1b2c3d4.org', named from the first bytes of its own ID.
It is a real note immediately: unique, linkable, findable by content. Org
titles it \"untitled\" and you rename it (or not) later, because nothing
here resolves a note by file name."
  (format "%s-%s.org"
          (format-time-string "%Y%m%d%H%M%S" time)
          (or (cerebro-math-slug title)
              (substring (replace-regexp-in-string "[^a-z0-9]" "" (downcase id))
                         0 8))))

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
remember."
  (let* ((row (cdr (cerebro-math-kind kind)))
         (block (plist-get row :block))
         (name (cerebro-math-result-name kind title))
         (filetags (mapconcat #'identity
                              (cons "seed" (delq nil (copy-sequence tags)))
                              ":")))
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
  "Create a KIND note called TITLE in notes/math/ and open it.
TITLE may be empty -- the file is then named from the note's own ID (see
`cerebro-math-file-name') and can be renamed, or left, forever.

Interactively: `C-c m n' asks for the kind, `C-c m t'/`d'/`l'/... skip
straight to one. With an active region, the region becomes the body --
which is `C-c m e' (`cerebro-math-extract') without the link back."
  (interactive
   (list (cerebro-math--read-kind)
         (read-string "Title (empty = name it later): ")))
  (let* ((id (org-id-new))
         (directory (file-name-as-directory cerebro-math-directory))
         (file (expand-file-name (cerebro-math-file-name title id) directory)))
    (make-directory directory t)
    (with-temp-file file
      (insert (cerebro-math-note-string kind title id body nil tags)))
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
         (directory (file-name-as-directory cerebro-math-directory))
         (file (expand-file-name (cerebro-math-file-name title id) directory))
         (description (if (string-empty-p (string-trim title))
                          (truncate-string-to-width body 40 nil nil "…")
                        title)))
    (make-directory directory t)
    (with-temp-file file
      (insert (cerebro-math-note-string kind title id body)))
    (org-id-add-location id file)
    (delete-region beg end)
    (insert (format "[[id:%s][%s]]" id description))
    (find-file-other-window file)
    (cerebro-math--point-into-block)
    (message "cerebro: extracted into %s" (file-name-nondirectory file))
    file))

;;;###autoload
(defun cerebro-math-find ()
  "Open a note from notes/math/, by name."
  (interactive)
  (let* ((files (seq-filter (lambda (f) (string-suffix-p ".org" f))
                            (directory-files cerebro-math-directory t)))
         (names (mapcar #'file-name-nondirectory files)))
    (unless names (user-error "cerebro-math: no notes in %s yet" cerebro-math-directory))
    (find-file (expand-file-name (completing-read "Math note: " names nil t)
                                 cerebro-math-directory))))

(provide 'cerebro-math)
