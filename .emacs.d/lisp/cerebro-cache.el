;;; cerebro-cache.el --- read the tree once, not once per question -*- lexical-binding: t; -*-

;; Every "how many notes / which results / what changed" question in this
;; config walks notes/ and reads every file: the start page does it four
;; times per refresh, `make results' once per invocation, the linter,
;; org-ql. At a dozen notes that is free. At two thousand it is a second
;; of stat-and-parse per keystroke that opens the dashboard, and the fix
;; then is a rewrite rather than a knob.
;;
;; So: one small memo, keyed on what the answer actually depends on --
;; the files and their modification times. Recompute when the *signature*
;; changes, return the stored value otherwise. Two properties make this
;; safe to put under the whole config:
;;
;;   - it cannot go stale. The key is derived from the filesystem, not
;;     from a hook someone might forget to add: a note edited by `cerebro
;;     note new', by git pull, or by another Emacs changes the signature
;;     just the same.
;;   - it cannot hide a bug. `cerebro-cache-disable' (or a nil
;;     `cerebro-cache-enabled') turns every entry into a plain call, so
;;     "is this the cache?" is answerable in one command.
;;
;; Everything here is pure except the two `file-attributes' calls, which
;; is why the invalidation logic itself is unit-tested.

(require 'seq)

(defgroup cerebro-cache nil
  "Memoisation of the whole-tree scans."
  :group 'cerebro)

(defcustom cerebro-cache-enabled t
  "Whether the whole-tree scans are memoised.
Set to nil to make every cached function recompute -- the first thing to
try when a number on screen looks wrong."
  :type 'boolean
  :group 'cerebro-cache)

(defvar cerebro-cache--table (make-hash-table :test 'equal)
  "KEY -> (SIGNATURE . VALUE) for every memoised scan.")

(defvar cerebro-cache-statistics (list :hits 0 :misses 0)
  "Hit/miss counters, so \"is the cache working?\" has an answer.")

;; -- Signatures (pure, given the file list) -----------------------------

(defun cerebro-cache-file-signature (files)
  "A signature for FILES: their names and modification times.

Deliberately not a content hash: reading every file to decide whether to
read every file is a strange way to save work. Mtimes are what the
filesystem already knows, and the failure mode of an mtime -- two writes
inside one clock tick -- is the same one `make' has lived with for fifty
years.

Pure: FILES and their attributes in, one comparable value out."
  (mapcar (lambda (file)
            (cons file (file-attribute-modification-time
                        (file-attributes file))))
          (sort (copy-sequence files) #'string<)))

(defun cerebro-cache-directory-signature (directories)
  "A signature for DIRECTORIES themselves -- their mtimes.
A directory's mtime changes when a file is created, deleted or renamed
inside it, which is exactly when \"the list of notes\" changes. Much
cheaper than stat-ing every file, and the right key for a *listing*."
  (cerebro-cache-file-signature directories))

;; -- The memo -----------------------------------------------------------

(defun cerebro-cache-get (key signature thunk)
  "Value of THUNK for KEY, recomputed only when SIGNATURE changes.
SIGNATURE is any comparable value (see the two builders above); THUNK is
called with no arguments and its result stored."
  (if (not cerebro-cache-enabled)
      (funcall thunk)
    (let ((entry (gethash key cerebro-cache--table)))
      (if (and entry (equal (car entry) signature))
          (progn
            (cl-incf (plist-get cerebro-cache-statistics :hits))
            (cdr entry))
        (cl-incf (plist-get cerebro-cache-statistics :misses))
        (let ((value (funcall thunk)))
          (puthash key (cons signature value) cerebro-cache--table)
          value)))))

(defun cerebro-cache-invalidate (&optional key)
  "Forget KEY, or everything when KEY is nil."
  (if key
      (remhash key cerebro-cache--table)
    (clrhash cerebro-cache--table)))

;;;###autoload
(defun cerebro-cache-status ()
  "Report what is memoised, and whether it is being used (`C-c d C')."
  (interactive)
  (message "cerebro cache: %s, %d entries, %d hits / %d misses"
           (if cerebro-cache-enabled "on" "OFF")
           (hash-table-count cerebro-cache--table)
           (plist-get cerebro-cache-statistics :hits)
           (plist-get cerebro-cache-statistics :misses)))

;;;###autoload
(defun cerebro-cache-disable ()
  "Turn memoisation off for this session and drop what is stored."
  (interactive)
  (setq cerebro-cache-enabled nil)
  (cerebro-cache-invalidate)
  (message "cerebro cache: off -- every scan recomputes"))

;; A note saved in this Emacs is the one case where the mtime would be
;; right but the answer stale by a fraction of a second (the signature is
;; taken before the write completes on some filesystems). Dropping the
;; entry costs one rescan and removes the whole class of doubt.
(add-hook 'after-save-hook #'cerebro-cache-invalidate)

(provide 'cerebro-cache)
