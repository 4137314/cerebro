;;; cerebro-backup.el --- where a copy of the archive goes -*- lexical-binding: t; -*-

;; This repository is meant to hold a lifetime of mathematics, and until
;; now nothing in it said what happens when the disk dies. Git history is
;; not a backup while the only clone is on this machine.
;;
;; The answer here is deliberately *generic*: the project cannot know
;; whether you have a server, an encrypted external disk, a git forge or
;; a friend's NAS -- and picking one would be a decision about your life,
;; not about the software. So a backup is a **target**: a name, a
;; command, and whether it is switched on. Three ready-made kinds cover
;; almost every arrangement, and adding another is a plist:
;;
;;   git      push the repository to a remote you control
;;   mirror   rsync the working tree somewhere (a disk, a server, a share)
;;   archive  a single encrypted tarball per run, for cold storage
;;
;; Nothing runs until you configure it, and nothing is configured by
;; default: an editor that silently copies your notes somewhere is worse
;; than no backup at all. `cerebro-backup-status' (and `cerebro backup
;; status') tells you what is set up and when each target last ran, which
;; is the question a backup policy actually has to answer.
;;
;; The commands are thin: they build a shell command from data and run it
;; in a compilation buffer, the same way cerebro-guix.el drives guix.
;; That keeps the whole thing inspectable -- you can read exactly what
;; would be run, and run it by hand.

(require 'cerebro-base)  ;; cerebro-root, cerebro-report -- no Org here
(require 'compile)
(require 'seq)

(defgroup cerebro-backup nil
  "Copies of the archive, off this machine."
  :group 'cerebro)

;; -- What a target is ---------------------------------------------------

(defcustom cerebro-backup-targets
  '((git
     :enabled nil
     :what "push every branch and tag to a remote you control"
     :command "git push --all %s && git push --tags %s"
     :needs ("git")
     :parameter "remote"
     :value "origin")
    (mirror
     :enabled nil
     :what "rsync the working tree to a disk, a server or a share"
     :command "rsync -a --delete --exclude .git/ ./ %s"
     :needs ("rsync")
     :parameter "destination (path or user@host:path)"
     :value "")
    (archive
     :enabled nil
     :what "one encrypted tarball per run, for cold storage"
     :command "tar -c --exclude-vcs . | gpg --symmetric --cipher-algo AES256 -o %s/cerebro-$(date +%%Y%%m%%d-%%H%%M).tar.gpg"
     :needs ("tar" "gpg")
     :parameter "directory to write the tarball into"
     :value ""))
  "Backup targets: what a copy of this archive is, and where it goes.

Each entry is (NAME . PLIST) with

  :enabled    whether `cerebro-backup' runs it
  :what       one line, shown by `cerebro-backup-status'
  :command    a shell command; every %s is replaced by :value
  :needs      programs that must exist for it to work
  :parameter  what :value means, for the prompt
  :value      the remote, path or directory you configured

Deliberately a defcustom of *commands*: a backup you cannot read is a
backup you cannot trust, and every one of these is a line you could have
typed yourself. Set them through Customize, or in the custom file that
cerebro-session.el already keeps out of git -- your server names are not
this repository's business."
  :type '(alist :key-type symbol :value-type plist)
  :group 'cerebro-backup)

(defcustom cerebro-backup-log
  (expand-file-name ".emacs.d/var/backup-log" cerebro-root)
  "File recording when each target last ran successfully.
Plain text, one line per run, because \"when did this last work?\" should
be answerable with `cat' on a machine where Emacs no longer starts."
  :type 'file
  :group 'cerebro-backup)

;; -- Pure helpers (unit-tested) -----------------------------------------

(defun cerebro-backup-target (name)
  "The target called NAME, or nil."
  (cdr (assq name cerebro-backup-targets)))

(defun cerebro-backup-enabled-targets (&optional targets)
  "Names of the targets that are switched on."
  (mapcar #'car
          (seq-filter (lambda (cell) (plist-get (cdr cell) :enabled))
                      (or targets cerebro-backup-targets))))

(defun cerebro-backup-command (target)
  "The shell command TARGET (a plist) would run, or nil if unconfigured.
Nil rather than a half-built command: `rsync -a ./ ' with an empty
destination is not a backup, it is a mistake with a progress bar."
  (let ((command (plist-get target :command))
        (value (plist-get target :value)))
    (when (and command (stringp value) (not (string-empty-p (string-trim value))))
      (replace-regexp-in-string "%s" (string-trim value) command t t))))

(defun cerebro-backup-missing-programs (target)
  "Programs TARGET needs that are not on PATH."
  (seq-remove #'executable-find (plist-get target :needs)))

(defun cerebro-backup-problems (name target)
  "Why TARGET (called NAME) cannot run, as a list of strings. Empty is good."
  (append
   (unless (plist-get target :enabled)
     (list "not enabled"))
   (unless (cerebro-backup-command target)
     (list (format "no %s configured" (or (plist-get target :parameter) "value"))))
   (mapcar (lambda (program) (format "%s is not installed" program))
           (cerebro-backup-missing-programs target))))

(defun cerebro-backup-log-line (name &optional time)
  "The line recorded for a successful run of NAME at TIME."
  (format "%s %s\n" (format-time-string "[%Y-%m-%d %a %H:%M]" time) name))

(defun cerebro-backup-last-run (name &optional log)
  "When NAME last ran successfully, as a string, or nil.
Reads the log backwards -- the last line about a target is the one that
matters, and the file is append-only."
  (let ((log (or log cerebro-backup-log)))
    (when (file-readable-p log)
      (with-temp-buffer
        (insert-file-contents log)
        (goto-char (point-max))
        (when (re-search-backward (format "^\\(\\[[^]]+\\]\\) %s$" (regexp-quote (symbol-name name))) nil t)
          (match-string 1))))))

;; -- Running one --------------------------------------------------------

(defun cerebro-backup--record (name)
  "Note that NAME just ran."
  (make-directory (file-name-directory cerebro-backup-log) t)
  (write-region (cerebro-backup-log-line name) nil cerebro-backup-log 'append 0))

;;;###autoload
(defun cerebro-backup-run (name)
  "Run one backup target by NAME, in a compilation buffer.
Asynchronous and visible: a backup that runs silently is one you cannot
tell has been failing for a month."
  (interactive
   (list (intern (completing-read
                  "Target: "
                  (mapcar (lambda (cell) (symbol-name (car cell))) cerebro-backup-targets)
                  nil t))))
  (let* ((target (or (cerebro-backup-target name)
                     (user-error "cerebro-backup: no target `%s'" name)))
         (problems (cerebro-backup-problems name target)))
    (when problems
      (user-error "cerebro-backup: %s cannot run -- %s (M-x cerebro-backup-status)"
                  name (string-join problems "; ")))
    (let ((default-directory cerebro-root)
          (compilation-buffer-name-function (lambda (&rest _) "*cerebro-backup*")))
      (with-current-buffer (compile (cerebro-backup-command target))
        (add-hook 'compilation-finish-functions
                  (lambda (_buffer status)
                    (if (string-prefix-p "finished" status)
                        (progn (cerebro-backup--record name)
                               (message "cerebro: backup `%s' ok" name))
                      (message "cerebro: backup `%s' FAILED -- read *cerebro-backup*" name)))
                  nil t)))))

;;;###autoload
(defun cerebro-backup ()
  "Run every enabled backup target (`C-c b b').
Nothing is enabled by default: an editor that copies your notes somewhere
without being told to is a worse problem than no backup."
  (interactive)
  (let ((names (cerebro-backup-enabled-targets)))
    (if (not names)
        (user-error "cerebro-backup: no target is enabled -- M-x cerebro-backup-status")
      (dolist (name names) (cerebro-backup-run name)))))

;;;###autoload
(defun cerebro-backup-status ()
  "What is configured, what it would run, and when it last worked (`C-c b s')."
  (interactive)
  (cerebro-report
   (format "cerebro backup -- %d of %d target(s) enabled"
           (length (cerebro-backup-enabled-targets)) (length cerebro-backup-targets))
   (apply
    #'append
    (mapcar
     (lambda (cell)
       (let* ((name (car cell))
              (target (cdr cell))
              (problems (cerebro-backup-problems name target)))
         (list
          (format "%-8s %s" name (plist-get target :what))
          (format "         state : %s"
                  (if problems (string-join problems "; ") "ready"))
          (format "         last  : %s" (or (cerebro-backup-last-run name) "never"))
          (format "         runs  : %s"
                  (or (cerebro-backup-command target)
                      (format "<set :value to the %s>" (plist-get target :parameter))))
          "")))
     cerebro-backup-targets))
   #'identity
   "*cerebro-backup-status*"))

(provide 'cerebro-backup)
