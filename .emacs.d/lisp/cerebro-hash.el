;;; cerebro-hash.el --- a note is named by its own metadata -*- lexical-binding: t; -*-

;; A note in notes/math/ has no name in its file name. It is called
;; `a3f19c04b2e7.org', and that string is not random: it is the digest of
;; the note's own metadata -- ID, title, date, tags, classification --
;; recomputed every time the note is saved.
;;
;; Why a name that carries no meaning is the right name here:
;;
;;   - A file name is a second title, and a second title is a second
;;     source of truth. `20260806140000-supremum.org' said the note was
;;     about the supremum; then the note grew, was retitled "Least upper
;;     bound property", and the file name went on saying the old thing
;;     forever, because renaming a file is work nobody does. Nothing here
;;     resolves a note by name (links are `:ID:'), so the name was pure
;;     decay with no compensating use.
;;   - A digest, by contrast, is *checkable*. `cerebro lint' recomputes it
;;     and says so when a file's name and its contents have drifted apart,
;;     which no human-readable name can offer.
;;   - And it forces the metadata to be worth reading, since it is now the
;;     only description of the note that exists outside its own prose.
;;     Hence the strictly ordered, one-per-line front matter below: data a
;;     three-line shell script can parse, not prose a parser has to guess
;;     at.
;;
;; The digest is over METADATA, not over the mathematics. Rewriting a
;; proof does not rename the file; retitling the note does. That is the
;; intended reading of "the name follows the metadata": the name changes
;; exactly when what the note *is* changes, not when what it says does.
;;
;; The cost, stated plainly: `ls notes/math/' is unreadable. That is what
;; `cerebro note list' (title + file), the org-roam search and `C-c m f'
;; are for -- every one of which reads the title out of the file, which
;; is where a title belongs. And a renamed file is a new path in git,
;; which is why the rename happens at most once per save and only when
;; the metadata really moved.

(require 'cerebro-base) ;; cerebro-math-directory, cerebro-conjecture-directory
(require 'seq)
(require 'subr-x)

;; `org-id' is NOT required here, and that is deliberate. Everything this
;; module is *about* -- parsing the front matter, canonicalising it,
;; taking the digest, checking a file's name against it -- is pure string
;; work, and requiring org-id at the top pulls in the whole of Org for
;; it: 288ms against the 41ms this module otherwise costs. The one
;; function that needs org-id is the rename, which loads it there. So
;; `cerebro lint' and every caller that only *checks* names stays cheap,
;; and only the caller that actually moves a file pays for Org.
;;
;; The byte compiler cannot see a `require' that happens inside a
;; function, so it reports both of those calls as undefined functions.
;; They are declared here instead of being loaded: `make compile' gates
;; this module with warnings promoted to errors, and the difference
;; between "I know this comes from org-id" and "I misspelled a function
;; name" has to stay visible.
(declare-function org-id-add-location "org-id" (id file))
(declare-function org-id-locations-save "org-id" ())

(defgroup cerebro-hash nil
  "Content-addressed file names for the note archive."
  :group 'cerebro)

(defcustom cerebro-hash-length 12
  "How many hex characters of the digest name a note.

Twelve is 48 bits: for an archive of a few thousand notes the chance of
a collision is nil, and the name still fits in a terminal column. The
digest itself is SHA-256; this only says how much of it is used."
  :type 'integer
  :group 'cerebro-hash)

(defcustom cerebro-hash-rename-notes t
  "Whether saving a note in notes/math/ may rename its file.

Set to nil to keep the digest up to date in the file (the `#+HASH:'
line) without ever renaming -- `cerebro lint' will then report the drift
instead, and `cerebro-hash-rehash-directory' repairs it in one go."
  :type 'boolean
  :group 'cerebro-hash)

;; -- The metadata, as data ----------------------------------------------
;; One row per field, in the order they appear in a note and in the order
;; they are hashed. This list IS the format: adding a field to the front
;; matter means adding it here, and every note gets a new name the next
;; time it is saved (which is the honest consequence -- the name is a
;; function of the metadata, and the metadata changed).
;;
;; ID lives in the property drawer, everything else in a `#+KEY:' line.
;; Nothing else in the file is metadata: a note's prose is not part of
;; its identity.

(defconst cerebro-hash-fields
  '(("ID"       :where drawer)
    ("TITLE"    :where keyword)
    ("DATE"     :where keyword)
    ("FILETAGS" :where keyword)
    ("MSC"      :where keyword))
  "The metadata fields of a note, in canonical order.")

(defconst cerebro-hash-keyword "HASH"
  "The `#+HASH:' keyword recording a note's own digest.
Derived data, written into the file on purpose: it is what lets a
checker (or a person, or a script with no Emacs) confirm that the name
on disk still matches the contents, without recomputing anything.")

(defun cerebro-hash--field-value (text field)
  "The value of FIELD in the Org note TEXT, or \"\" when absent. Pure."
  (let* ((name (car field))
         (drawer (eq (plist-get (cdr field) :where) 'drawer))
         (regexp (if drawer
                     (format "^[ \t]*:%s:[ \t]*\\(.*\\)$" (regexp-quote name))
                   (format "^[ \t]*#\\+%s:[ \t]*\\(.*\\)$" (regexp-quote name)))))
    (if (string-match regexp text)
        ;; Internal whitespace collapsed: `#+TITLE:  A  B' and
        ;; `#+TITLE: A B' are the same title, and must not be two names.
        (string-trim (replace-regexp-in-string "[ \t]+" " " (match-string 1 text)))
      "")))

(defun cerebro-hash-parse (text)
  "The metadata of the Org note TEXT, as an alist of (FIELD . VALUE). Pure.

This is the whole parser, and it is deliberately this small: the front
matter of a note is a property drawer with an `:ID:' and a run of
one-line `#+KEY:' keywords, so reading it needs no Org, no parse tree
and no Emacs -- bin/cerebro-note does the same thing in sed."
  (mapcar (lambda (field)
            (cons (car field) (cerebro-hash--field-value text field)))
          cerebro-hash-fields))

(defun cerebro-hash-canonical (metadata)
  "The exact string that gets hashed, for METADATA. Pure.

`FIELD: value' per line, in `cerebro-hash-fields' order, every field
present even when empty, one trailing newline. Written out rather than
hashed field-by-field so that the shell can reproduce it byte for byte
-- a digest two implementations disagree about is worse than no digest."
  (mapconcat (lambda (field)
               (format "%s: %s\n" (car field)
                       (or (cdr (assoc (car field) metadata)) "")))
             cerebro-hash-fields ""))

(defun cerebro-hash-digest (metadata)
  "The digest naming a note with METADATA. Pure."
  (substring (secure-hash 'sha256 (cerebro-hash-canonical metadata))
             0 cerebro-hash-length))

(defun cerebro-hash-of-text (text)
  "The digest naming the note whose contents are TEXT. Pure."
  (cerebro-hash-digest (cerebro-hash-parse text)))

(defun cerebro-hash-file-name (hash)
  "The file name a note with digest HASH has. Pure."
  (concat hash ".org"))

(defun cerebro-hash--keyword-fields-regexp ()
  "A regexp matching a front-matter keyword line, built from the fields.
Only the *declared* fields, never `#+[A-Za-z]+:' in general: `#+NAME:'
is a keyword too, it lives in the body directly above the block it
names, and inserting a line after one would detach the name from its
block -- silently breaking the `single' export, which is precisely the
failure this repository warns about most loudly."
  (format "^[ \t]*#\\+\\(?:%s\\):.*$"
          (mapconcat (lambda (field) (regexp-quote (car field)))
                     (seq-remove (lambda (field)
                                   (eq (plist-get (cdr field) :where) 'drawer))
                                 cerebro-hash-fields)
                     "\\|")))

(defun cerebro-hash-set-line (text hash)
  "TEXT with its `#+HASH:' line set to HASH. Pure.

Placed last in the front matter, after the fields it is computed from,
because that is the order in which it is true: everything above is what
the note says about itself, and this line is what follows from it."
  (let ((line (format "#+%s: %s" cerebro-hash-keyword hash))
        (existing (format "^[ \t]*#\\+%s:.*$" cerebro-hash-keyword))
        (front-matter (cerebro-hash--keyword-fields-regexp)))
    (cond
     ((string-match existing text)
      (replace-match line t t text))
     ;; No line yet: after the last declared metadata keyword, which is
     ;; where a reader looks for it. A note with none of them (nothing
     ;; this repository writes) gets it at the top.
     ((string-match front-matter text)
      (let ((end (match-end 0)))
        ;; The *last* one, so the block stays together however the front
        ;; matter happens to be ordered.
        (while (string-match front-matter text (1+ end))
          (setq end (match-end 0)))
        (concat (substring text 0 end) "\n" line (substring text end))))
     (t (concat line "\n" text)))))

;; -- Keeping a file's name true -----------------------------------------

(defconst cerebro-hash-directories
  (list cerebro-math-directory cerebro-conjecture-directory)
  "The directories whose file names this module owns.

The two that hold *notes*: notes/math/ (the concept graph) and
notes/conjectures/ (the open questions). A course file and this
repository's own READMEs are named by a person, on purpose, and are left
alone -- as is anything else added to notes/ later, until it is listed
here.")

(defun cerebro-hash-note-p (file)
  "Non-nil when FILE is a note whose name this module owns.

`cerebro-note-file-p' first, and that clause is load-bearing rather than
tidy: a README inside one of these directories is *not* a note (it is
this repository talking about itself, and `cerebro-note-files' has always
excluded it), so its name is not this module's to derive. Without the
clause `cerebro-hash-rehash' renamed notes/conjectures/README.org to
e27569f8051f.org and wrote a `#+HASH:' line into it -- while `cerebro
note rehash', the shell twin that is supposed to be the same operation,
skipped it by name. Two tools disagreeing about which files exist is the
one thing a content-addressed archive cannot afford."
  (and (cerebro-note-file-p file)
       (let ((directory (file-name-directory (expand-file-name file))))
         (seq-some (lambda (owned)
                     (and (file-directory-p owned)
                          (file-equal-p directory (file-name-as-directory owned))))
                   cerebro-hash-directories))))

(defun cerebro-hash-buffer-text ()
  "This buffer's contents, without properties."
  (buffer-substring-no-properties (point-min) (point-max)))

(defun cerebro-hash-update-line ()
  "Write this buffer's own digest into its `#+HASH:' line.
Returns the digest. Cheap and idempotent: when the line is already
right, the buffer is not touched at all (so saving an unchanged note
does not mark it modified)."
  (let* ((text (cerebro-hash-buffer-text))
         (hash (cerebro-hash-of-text text))
         (updated (cerebro-hash-set-line text hash)))
    (unless (equal text updated)
      (let ((point (point)))
        (erase-buffer)
        (insert updated)
        (goto-char (min point (point-max)))))
    hash))

(defun cerebro-hash--rename (file hash)
  "Rename FILE to HASH.org in its own directory. Returns the new path, or
nil when nothing had to move.

The org-id location map is updated by hand afterwards: it is keyed by
path, and a note whose path moved is a note `id:' links stop resolving
to until something rescans -- which would be the next time you follow a
link, i.e. exactly the wrong moment to find out.

This is the only function in the module that needs Org, so this is where
Org gets loaded (see the note at the top): a caller that merely checks
names never pays for it."
  (require 'org-id)
  (let* ((directory (file-name-directory file))
         (target (expand-file-name (cerebro-hash-file-name hash) directory)))
    (cond
     ((equal (expand-file-name file) target) nil)
     ;; Two notes with byte-identical metadata, including their :ID:s,
     ;; cannot happen -- so this is a real anomaly and refuses rather
     ;; than overwrites.
     ((file-exists-p target)
      (message "cerebro-hash: %s is taken -- leaving %s alone"
               (file-name-nondirectory target) (file-name-nondirectory file))
      nil)
     (t
      (rename-file file target)
      (let ((id (cdr (assoc "ID" (cerebro-hash-parse
                                  (with-temp-buffer
                                    (insert-file-contents target)
                                    (buffer-string)))))))
        (when (and id (not (string-empty-p id)))
          (org-id-add-location id target)))
      target))))

(defun cerebro-hash-before-save ()
  "Keep the `#+HASH:' line true, on the way to disk."
  (when (cerebro-hash-note-p (buffer-file-name))
    (cerebro-hash-update-line)))

(defun cerebro-hash-after-save ()
  "Rename the file just saved when its metadata gave it a new name.

After the save, not before: the rename is a filesystem operation on a
file that must already contain what the new name is a digest of.
`set-visited-file-name' is then called with NO-QUERY *and*
ALONG-WITH-FILE non-nil -- the second says the old file has already been
renamed to this one, which is what keeps the buffer from being marked
modified and written out a second time."
  (when (and cerebro-hash-rename-notes
             (cerebro-hash-note-p (buffer-file-name)))
    (let* ((file (buffer-file-name))
           (hash (cerebro-hash-of-text (cerebro-hash-buffer-text)))
           (renamed (cerebro-hash--rename file hash)))
      (when renamed
        (set-visited-file-name renamed t t)
        (message "cerebro: renamed to %s" (file-name-nondirectory renamed))))))

;;;###autoload
(defun cerebro-hash-install ()
  "Keep every note in notes/math/ named after its own metadata."
  (add-hook 'before-save-hook #'cerebro-hash-before-save)
  (add-hook 'after-save-hook #'cerebro-hash-after-save))

;; -- Repairing a whole directory ----------------------------------------

(defun cerebro-hash-check-file (file)
  "What is wrong with FILE's name, as a plist, or nil when nothing is.
\(:file FILE :hash WANTED :name CURRENT\) -- the shape `cerebro lint'
and `cerebro-hash-rehash-directory' both report."
  (let* ((text (with-temp-buffer (insert-file-contents file) (buffer-string)))
         (hash (cerebro-hash-of-text text))
         (want (cerebro-hash-file-name hash))
         (have (file-name-nondirectory file))
         (recorded (cerebro-hash--field-value
                    text (list cerebro-hash-keyword :where 'keyword))))
    (unless (and (equal want have) (equal recorded hash))
      (list :file file :hash hash :name have))))

;;;###autoload
(defun cerebro-hash-rehash (&optional directories)
  "Give every note this module owns its true name. Returns how many moved.
DIRECTORIES defaults to `cerebro-hash-directories' -- all of them, so
the repair is never half-done because one was forgotten.

The id->path map is *written to disk* when anything moved, and that is
not a detail. `cerebro-hash--rename' updates it in memory, which is
enough inside a running Emacs and is nothing at all here: `cerebro note
rehash' is a batch process, it exits, and the next process reads the
map from `org-id-locations-file' -- still pointing at the names the
files had before the rename. The symptom is an export failing once with
`Cannot include file .../<old digest>.org', for a note whose title you
had just edited, and then succeeding on the retry once something else
happened to refresh the map. Observed exactly that way."
  (interactive)
  (let ((moved (apply #'+ (mapcar #'cerebro-hash-rehash-directory
                                  (or directories cerebro-hash-directories)))))
    (when (> moved 0)
      (require 'org-id)
      (org-id-locations-save))
    (when (called-interactively-p 'interactive)
      (message "cerebro: %d note%s renamed" moved (if (= moved 1) "" "s")))
    moved))

;;;###autoload
(defun cerebro-hash-rehash-directory (&optional directory)
  "Give every note in DIRECTORY (default notes/math/) its true name.

The repair operation, and the migration one: run it once over an archive
of hand-named files and they become digests; run it after editing notes
outside Emacs and any drift is undone. Idempotent -- a note already
correctly named is not touched, so this is safe to run at any time.
`cerebro-hash-rehash' does this for every owned directory at once."
  (interactive)
  (let ((directory (or directory cerebro-math-directory))
        (renamed 0))
    ;; `cerebro-note-file-p', not the raw listing: DIRECTORY is passed in,
    ;; so `cerebro-hash-note-p' (which also asks whether the directory is
    ;; one this module owns) would reject every caller that repairs a
    ;; directory by name. What has to be filtered here is the other half
    ;; -- the files in it that are not notes at all.
    (dolist (file (and (file-directory-p directory)
                       (seq-filter #'cerebro-note-file-p
                                   (directory-files directory t "\\.org\\'"))))
      (when-let* ((wrong (cerebro-hash-check-file file)))
        (with-temp-buffer
          (insert-file-contents file)
          (let ((text (cerebro-hash-set-line (buffer-string)
                                             (plist-get wrong :hash))))
            (erase-buffer)
            (insert text))
          (write-region (point-min) (point-max) file nil 'quiet))
        (when (cerebro-hash--rename file (plist-get wrong :hash))
          (setq renamed (1+ renamed)))))
    (when (called-interactively-p 'interactive)
      (message "cerebro: %d note%s renamed" renamed (if (= renamed 1) "" "s")))
    renamed))

(provide 'cerebro-hash)
