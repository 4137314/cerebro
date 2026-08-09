;;; cerebro-isolation.el --- this Emacs writes notes, and nothing else -*- lexical-binding: t; -*-

;; The environment is isolated *outside* Emacs -- guix.scm pins every
;; package, nothing is fetched at runtime, the profile is reproducible.
;; Inside Emacs it was not isolated at all: the same editor that writes a
;; theorem could just as easily rewrite cerebro-latex.el, the makefile or
;; guix.scm, and the difference between those two acts was a directory
;; nobody was checking.
;;
;; So there is a line, and it is the obvious one:
;;
;;     the archive is writable        notes/  issues/  bib/
;;     the machinery is read-only     everything else
;;
;; Opening cerebro-org.el still works -- reading the config is how you
;; understand it, and `C-c H' exists precisely to encourage that. Typing
;; into it does not. The point is not that editing the config is
;; forbidden; it is that it should be a *deliberate* act performed
;; knowingly, not something that happens because a buffer was open and
;; the cursor was in it.
;;
;; Said plainly, because overstating this would be worse than not having
;; it: THIS IS A GUARD RAIL, NOT A LOCK. `buffer-read-only' is one
;; `C-x C-q' away, on purpose, and `cerebro-isolation-unlock' is the
;; sanctioned version of that keystroke. Anyone who wants to edit the
;; config can, in one command; nobody will do it by accident. A second
;; brain that made its own configuration unreachable would be a second
;; brain you cannot fix.

(require 'cerebro-base) ;; cerebro-root, org-directory
(require 'seq)

(defgroup cerebro-isolation nil
  "What this Emacs is allowed to write."
  :group 'cerebro)

(defcustom cerebro-isolation-writable-directories
  '("notes" "issues" "bib")
  "Directories, relative to `cerebro-root', that this Emacs may write.

The archive and the two things that are *part of* the archive: the
committed issue tracker (`C-c c i' captures into it) and the one
bibliography (`C-c b n' writes entries to it). Everything else in the
repository -- the Elisp, the shell tools, the LaTeX classes, guix.scm,
the makefile, the tests -- is machinery, and machinery is read here.

This value is *set from the mode* at startup and on every switch
(`cerebro-mode-apply', cerebro-mode.el): it is `math' that says the
archive is the writable part, and `dev' that turns the whole policy off
by setting `cerebro-isolation-enabled' to nil. Customise it there --
`cerebro-modes' -- rather than here, or the mode will overwrite you the
next time it is applied."
  :type '(repeat string)
  :group 'cerebro-isolation)

(defcustom cerebro-isolation-enabled t
  "Whether files outside the archive open read-only.
Set to nil for a session spent working *on* cerebro rather than in it."
  :type 'boolean
  :group 'cerebro-isolation)

;; -- The decision, as a pure function -----------------------------------

(defun cerebro-isolation-writable-p (file &optional roots)
  "Non-nil when FILE is part of the archive and may be written. Pure.

ROOTS defaults to `cerebro-isolation-writable-directories', resolved
against `cerebro-root'. A file *outside the repository entirely* is
writable: this is a policy about not damaging cerebro by accident, not a
claim to own every buffer in the session -- an Emacs that opened your
shopping list read-only would just be broken."
  (when file
    (let* ((file (expand-file-name file))
           (root (file-name-as-directory (expand-file-name cerebro-root))))
      (or
       ;; Not in this repository at all.
       (not (string-prefix-p root file))
       ;; In it, and under one of the writable directories.
       (seq-some
        (lambda (dir)
          (string-prefix-p (file-name-as-directory (expand-file-name dir root))
                           file))
        (or roots cerebro-isolation-writable-directories))))))

;; -- Applying it --------------------------------------------------------

(defun cerebro-isolation-protect ()
  "Make this buffer read-only when it is machinery rather than archive.

On `find-file-hook', so it covers every route to a buffer -- a key, a
link, `C-c H b', a grep result -- rather than the commands this config
happens to define."
  (when (and cerebro-isolation-enabled
             buffer-file-name
             (not (cerebro-isolation-writable-p buffer-file-name)))
    (setq buffer-read-only t)))

;;;###autoload
(defun cerebro-isolation-unlock ()
  "Make this protected buffer writable, deliberately (`C-c H u').

The sanctioned way to edit the machinery from inside the archive's own
editor. It says what it is doing, because the value of the guard rail is
entirely in noticing that you crossed it."
  (interactive)
  (unless buffer-file-name
    (user-error "cerebro-isolation: this buffer is not a file"))
  (if (cerebro-isolation-writable-p buffer-file-name)
      (message "cerebro: %s is part of the archive -- already writable"
               (file-name-nondirectory buffer-file-name))
    (setq buffer-read-only nil)
    (message "cerebro: %s unlocked -- this is configuration, not a note"
             (file-relative-name buffer-file-name cerebro-root))))

;;;###autoload
(defun cerebro-isolation-status ()
  "Say what this Emacs may write, and whether this buffer is one of them."
  (interactive)
  (message "cerebro: writable = %s%s"
           (string-join cerebro-isolation-writable-directories ", ")
           (if buffer-file-name
               (format " · this buffer: %s"
                       (if (cerebro-isolation-writable-p buffer-file-name)
                           "writable" "read-only (C-c H u unlocks)"))
             "")))

(add-hook 'find-file-hook #'cerebro-isolation-protect)

(provide 'cerebro-isolation)
