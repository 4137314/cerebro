;;; cerebro-find.el --- reaching a file by what it is -*- lexical-binding: t; -*-

;; A file tree answers "what is in this directory?". That is not the
;; question anyone has here. The questions are "which note was that",
;; "which course", "which conjecture" -- questions about *kinds of
;; writing*, and the archive already knows the kinds: notes/math/ is the
;; concept graph, notes/conjectures/ is what is mine and unproved,
;; notes/courses/ is one file per course. So the tree is gone
;; (cerebro-ui.el kept it in a side window for a while) and this is what
;; replaced it: one prefix, `C-c f', one key per kind.
;;
;;   C-c f n   any note, anywhere in the archive
;;   C-c f m   a note in notes/math/
;;   C-c f j   a conjecture
;;   C-c f c   a course
;;   C-c f r   a named result (jumps *into* the file, cerebro-nav.el)
;;   C-c f i   the issue tracker
;;   C-c f b   the bibliography
;;
;; Everything completes over *titles*, never over file names, and that is
;; forced rather than chosen: a note in notes/math/ is called
;; `a3f19c04b2e7.org' (cerebro-hash.el), so a file-name completion here
;; would be completion over noise. The title is read out of each file,
;; which is the only place it was ever true.
;;
;; Reading 47 files to build one completion list would be slow if it
;; happened per keystroke; it happens once per invocation and is memoised
;; on the files' mtimes with every other whole-tree scan
;; (cerebro-cache.el), so the second call in a session is free.

(require 'cerebro-base)  ;; the archive's directories, the note lister
(require 'cerebro-cache) ;; memoised on mtimes, like every other tree scan
(require 'seq)
(require 'subr-x)

(defgroup cerebro-find nil
  "Opening a file by what kind of writing it is."
  :group 'cerebro)

;; -- Titles -------------------------------------------------------------

(defun cerebro-find-title (file)
  "The `#+TITLE:' of FILE, or its file name when it has none. Pure enough.
Only the front matter is read: a note is a long file and its title is
always in the first few lines."
  (with-temp-buffer
    (insert-file-contents file nil 0 2048)
    (goto-char (point-min))
    (if (re-search-forward "^[ \t]*#\\+TITLE:[ \t]*\\(.*\\)$" nil t)
        (string-trim (match-string 1))
      (file-name-nondirectory file))))

(defun cerebro-find--qualifier (file)
  "How to tell FILE apart from another note of the same title. Pure.

Its path inside the archive (`math/a3f19c04b2e7.org'), which is unique
by construction and is what the reader would have looked at anyway. A
file outside notes/ -- which in practice means a test -- falls back to
its own path rather than to a run of `../..' climbing out of the tree."
  (let ((root (file-name-as-directory (expand-file-name org-directory))))
    (if (string-prefix-p root (expand-file-name file))
        (file-relative-name file org-directory)
      (abbreviate-file-name file))))

(defun cerebro-find--rows (files)
  "Alist of (TITLE . FILE) for FILES, memoised on their mtimes.

Two titles can collide -- nothing stops two notes being called
\"Continuity\" -- so a repeated title is disambiguated by its directory,
and a repeat *within* a directory by its path (`cerebro-find--qualifier'),
rather than silently shadowing what came before. Losing a note from a
picker because something else shares its name is the kind of failure you
do not notice."
  (cerebro-cache-get
   (list 'find-rows files)
   (cerebro-cache-file-signature files)
   (lambda ()
     (let ((seen (make-hash-table :test 'equal))
           rows)
       (dolist (file files)
         (let* ((title (cerebro-find-title file))
                (label (if (gethash title seen)
                           (format "%s  (%s)" title
                                   (file-name-nondirectory
                                    (directory-file-name
                                     (file-name-directory file))))
                         title)))
           ;; A directory separates two notes; it does not separate three.
           ;; The second and third "Continuity" in notes/math/ both came
           ;; back labelled `Continuity  (math)', `assoc' answered with
           ;; the second for both, and the third was unreachable from the
           ;; picker -- the exact failure the disambiguation above exists
           ;; to prevent, one note further along. A path is unique by
           ;; construction, so this ends the ladder rather than extending
           ;; it.
           (when (gethash label seen)
             (setq label (format "%s  (%s)" title (cerebro-find--qualifier file))))
           (puthash title t seen)
           (puthash label t seen)
           (push (cons label file) rows)))
       (nreverse rows)))))

(defun cerebro-find--read (prompt files)
  "Completing-read a file among FILES, by title, and return it."
  (let ((rows (cerebro-find--rows files)))
    (unless rows (user-error "cerebro-find: nothing to open yet"))
    (cdr (assoc (completing-read prompt (mapcar #'car rows) nil t) rows))))

(defun cerebro-find--in-directory (prompt directory)
  "Open a note from DIRECTORY, chosen by title.

Filtered through `cerebro-note-file-p', like `cerebro-find-note' above
gets for free by going through `cerebro-note-files'. Without it these
per-kind pickers listed the directory raw and so disagreed with the
archive's own definition of a note inside one module: `C-c f j' offered
notes/conjectures/README.org -- and, there being no conjectures written
yet, offered *nothing else*, so the one command for reaching a
conjecture could only ever open the file that is not one."
  (unless (file-directory-p directory)
    (user-error "cerebro-find: %s does not exist yet" directory))
  (let ((files (seq-filter #'cerebro-note-file-p
                           (directory-files directory t "\\.org\\'"))))
    (unless files (user-error "cerebro-find: nothing in %s yet" directory))
    (find-file (cerebro-find--read prompt files))))

;; -- One command per kind of writing ------------------------------------

;;;###autoload
(defun cerebro-find-note ()
  "Open any note in the archive, by title (`C-c f n').
The whole tree -- math, conjectures, courses -- when you know what you
wrote and not where it went."
  (interactive)
  (find-file (cerebro-find--read "Note: " (cerebro-note-files))))

;;;###autoload
(defun cerebro-find-math ()
  "Open a note from notes/math/, by title (`C-c f m')."
  (interactive)
  (cerebro-find--in-directory "Math note: " cerebro-math-directory))

;;;###autoload
(defun cerebro-find-conjecture ()
  "Open a conjecture, by title (`C-c f j').
Mine, unproved, and kept apart from the concept graph on purpose -- so
\"what have I actually conjectured?\" is a question with an answer."
  (interactive)
  (cerebro-find--in-directory "Conjecture: " cerebro-conjecture-directory))

;;;###autoload
(defun cerebro-find-course ()
  "Open a course, by title (`C-c f c').
A course is ONE file: metadata, prose, and a programme of id: links."
  (interactive)
  (cerebro-find--in-directory
   "Course: " (expand-file-name "courses" org-directory)))

;;;###autoload
(defun cerebro-find-issues ()
  "Open the committed issue tracker (`C-c f i')."
  (interactive)
  (find-file (expand-file-name "issues/issues.org" cerebro-root)))

;;;###autoload
(defun cerebro-find-bibliography ()
  "Open the one bibliography (`C-c f b')."
  (interactive)
  (find-file cerebro-bib-file))

(provide 'cerebro-find)
