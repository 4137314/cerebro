;;; cerebro-course.el --- a course is an index into notes/math/ -*- lexical-binding: t; -*-

;; A course used to be a directory with its own lecture notes in it
;; (01-limits.org, 02-series.org, ...). That quietly makes the same
;; mathematics live in two places: the atomic note about continuity in
;; notes/math/, and the paragraph about continuity inside the course. The
;; second copy is the one that rots.
;;
;; So a course here owns *no mathematics at all*. It is one file --
;; course.org -- whose `* Programme' section is an ordered list of links
;; to notes that already exist, and that is the whole course:
;;
;;     * Programme
;;     ** Continuity
;;     - [[id:...][Limits and continuity]]
;;     ** Inner product spaces
;;     - [[id:...][Inner product space]]
;;     - [[id:...][Cauchy--Schwarz inequality]]
;;
;; From that, `cerebro-course-build-book' generates book.org: the
;; programme's outline becomes the book's chapters, and every link becomes
;; an Org `#+INCLUDE:' of the note it points at. Nothing is copied -- the
;; book is a *view*, and re-running the generator after editing a note
;; changes the book with it.
;;
;; Consequences worth knowing:
;;
;;   - You write a book only once the atomic notes exist. The order is a
;;     teaching decision made in the syllabus, not a filing decision made
;;     in a directory.
;;   - Notes are referenced by `:ID:', so moving or renaming one does not
;;     touch any course.
;;   - One note can appear in several courses without being duplicated.
;;   - book.org is *generated*: never edit it (a header says so). Prose
;;     that belongs to the course goes in course.org, which the syllabus
;;     profile exports.
;;
;; The parsing and the generation are pure functions over strings, with
;; the one impure step (an ID -> file) injected -- so what the generator
;; writes is unit-tested without a note database.

(require 'cerebro-org) ;; cerebro-root, org-directory
(require 'cerebro-pdf) ;; one place that puts a document on screen
(require 'compile)
(require 'org-id)
(require 'seq)

(defgroup cerebro-course nil
  "Courses as an index over the note graph."
  :group 'cerebro)

(defcustom cerebro-course-programme-heading "Programme"
  "Heading in course.org whose subtree lists the course's notes, in order."
  :type 'string
  :group 'cerebro-course)

;; -- Reading the programme (pure) ---------------------------------------

(defun cerebro-course-parse-programme (text &optional heading)
  "The ordered contents of the programme section of TEXT.

Returns a list of plists, in document order:
  (:kind heading :level N :text \"Continuity\")
  (:kind note    :level N :id \"...\" :title \"Limits and continuity\")

LEVEL is relative to the programme heading itself, so a `** Continuity'
under `* Programme' comes back at level 1 -- the generator then decides
what that means in the book, and the syllabus outline is free to live at
any depth in course.org.

Links are read wherever they appear (a list item, a paragraph, a table),
because the syllabus is prose a human writes: requiring one syntax for
the machine's benefit is how a manifest and a document drift apart."
  (let* ((heading (or heading cerebro-course-programme-heading))
         (lines (split-string text "\n"))
         (start-re (format "\\`\\(\\*+\\)[ \t]+%s[ \t]*\\'" (regexp-quote heading)))
         (base nil)      ; the level of the programme heading
         (level 0)       ; current relative level
         (in-comment nil)
         (entries nil))
    ;; `catch' rather than a flag: the scan *stops* at the first heading
    ;; back at the programme's own level, so a link in a later section
    ;; (a bibliography, an assessment note) is never mistaken for part of
    ;; the course.
    (catch 'cerebro-course--end
      (dolist (line lines)
        (cond
         ;; Commentary is not the course. A `#+begin_comment' block is
         ;; where this project puts meta-text (CLAUDE.md), and the
         ;; scaffolded course.org explains the format with example links
         ;; in one -- which would otherwise become three chapters of
         ;; every new course.
         (in-comment
          (when (string-match-p "\\`[ \t]*#\\+end_comment[ \t]*\\'" (downcase line))
            (setq in-comment nil)))
         ((string-match-p "\\`[ \t]*#\\+begin_comment" (downcase line))
          (setq in-comment t))
         ((string-match-p "\\`[ \t]*#[ \t]" line) nil) ; an Org line comment
         ;; Not in the section yet: look for its heading.
         ((null base)
          (when (string-match start-re line)
            (setq base (length (match-string 1 line)))))
         ;; A heading: either deeper (a chapter of the programme) or the
         ;; end of the section.
         ((string-match "\\`\\(\\*+\\)[ \t]+\\(.*?\\)[ \t]*\\'" line)
          (let ((depth (length (match-string 1 line)))
                (title (match-string 2 line)))
            (when (<= depth base)
              (throw 'cerebro-course--end nil))
            (setq level (- depth base))
            (push (list :kind 'heading :level level :text title) entries)))
         ;; Anything else: collect every id: link on the line.
         (t
          (let ((pos 0))
            (while (string-match "\\[\\[id:\\([^]]+\\)\\]\\[\\([^]]*\\)\\]\\]" line pos)
              (push (list :kind 'note
                          :level level
                          :id (match-string 1 line)
                          :title (match-string 2 line))
                    entries)
              (setq pos (match-end 0))))))))
    (nreverse entries)))

(defun cerebro-course-note-body-line (text)
  "First line of TEXT that is note *content*, 1-based.

An Org note starts with a `:PROPERTIES:' drawer and `#+KEYWORD:' lines.
Including those in a book would splice a second `#+TITLE:' into the
middle of the document -- which Org happily accepts and which then
overrides the book's own title -- plus stray tags and IDs. So the
generated `#+INCLUDE:' starts below them, and this is where."
  (let ((lines (split-string text "\n"))
        (line 0)
        (in-drawer nil)
        (result nil))
    (while (and lines (not result))
      (let ((current (car lines)))
        (setq line (1+ line))
        (cond
         (in-drawer (when (string-match-p "\\`[ \t]*:END:[ \t]*\\'" current)
                      (setq in-drawer nil)))
         ((string-match-p "\\`[ \t]*:PROPERTIES:[ \t]*\\'" current) (setq in-drawer t))
         ((string-match-p "\\`[ \t]*#\\+[A-Za-z_]+:" current) nil) ; a keyword line
         ((string-match-p "\\`[ \t]*\\'" current) nil)             ; blank
         (t (setq result line)))
        (setq lines (cdr lines))))
    ;; A note with nothing but front matter still yields a valid include.
    (or result (1+ line))))

;; -- Writing the book (pure, given a resolver) --------------------------

(defun cerebro-course-book-string (title entries resolve directory)
  "The text of book.org for a course called TITLE.

ENTRIES comes from `cerebro-course-parse-programme'. RESOLVE is called
with a note ID and returns a plist (:file PATH :title STRING :body-line
N) or nil when the ID is unknown. DIRECTORY is where book.org will be
written, so the includes can be relative to it -- a book that moves with
its course.

Every note gets a heading of its own (its `#+TITLE:', which is the
authoritative name) and the include below it is pushed one level deeper,
so a note that has internal headings nests underneath instead of
breaking out of its chapter."
  (let ((missing nil))
    (list
     :text
     (concat
      "# -*- buffer-read-only: t -*-\n"
      "# GENERATED by `cerebro-course-build-book' from course.org --\n"
      "# every edit here is lost on the next build. The course's own\n"
      "# prose belongs in course.org; the mathematics belongs in the\n"
      "# notes this file includes.\n"
      (format "#+TITLE: %s\n\n" title)
      (mapconcat
       (lambda (entry)
         (pcase (plist-get entry :kind)
           ('heading
            (format "%s %s\n\n"
                    (make-string (plist-get entry :level) ?*)
                    (plist-get entry :text)))
           ('note
            (let* ((id (plist-get entry :id))
                   (note (funcall resolve id))
                   ;; One level below the chapter it was listed under --
                   ;; and level 1 when the programme has no chapters at
                   ;; all, so a flat reading list still makes a flat book.
                   (level (max 1 (1+ (plist-get entry :level)))))
              (if (not note)
                  (progn (push id missing)
                         (format "# MISSING NOTE: id:%s (%s)\n\n"
                                 id (plist-get entry :title)))
                (format "%s %s\n#+INCLUDE: \"%s\" :lines \"%d-\" :minlevel %d\n\n"
                        (make-string level ?*)
                        (or (plist-get note :title) (plist-get entry :title))
                        (file-relative-name (plist-get note :file) directory)
                        (plist-get note :body-line)
                        (1+ level)))))))
       entries ""))
     :missing (nreverse missing))))

;; -- The impure half ----------------------------------------------------

(defun cerebro-course-resolve-id (id)
  "Find the note with ID and report what the generator needs about it."
  (when-let* ((file (org-id-find-id-file id)))
    (let ((text (with-temp-buffer (insert-file-contents file) (buffer-string))))
      (list :file file
            :title (when (string-match "^#\\+TITLE:[ \t]*\\(.*\\)$" text)
                     (string-trim (match-string 1 text)))
            :body-line (cerebro-course-note-body-line text)))))

(defun cerebro-course-file (directory)
  "The course.org of DIRECTORY."
  (expand-file-name "course.org" directory))

(defun cerebro-course-title (text fallback)
  "The course's title: its `#+COURSE_TITLE:', else FALLBACK."
  (if (string-match "^#\\+COURSE_TITLE:[ \t]*\\(.*\\)$" text)
      (string-trim (match-string 1 text))
    fallback))

;;;###autoload
(defun cerebro-course-build-book (directory)
  "Regenerate DIRECTORY/book.org from the programme in its course.org.
Returns the list of unresolved IDs, which is also what makes this safe to
run blind: a link to a note that no longer exists leaves a visible
`# MISSING NOTE' line in the book and is reported, rather than silently
dropping a chapter."
  (interactive
   (list (read-directory-name "Course: "
                              (expand-file-name "courses" org-directory))))
  (let* ((course (cerebro-course-file directory))
         (_ (unless (file-readable-p course)
              (user-error "cerebro-course: no course.org in %s" directory)))
         (text (with-temp-buffer (insert-file-contents course) (buffer-string)))
         (title (cerebro-course-title text (file-name-nondirectory
                                            (directory-file-name directory))))
         (entries (cerebro-course-parse-programme text))
         (result (cerebro-course-book-string title entries
                                             #'cerebro-course-resolve-id
                                             directory))
         (book (expand-file-name "book.org" directory)))
    (unless entries
      (user-error "cerebro-course: `* %s' in %s lists no notes yet"
                  cerebro-course-programme-heading
                  (file-relative-name course cerebro-root)))
    (with-temp-file book (insert (plist-get result :text)))
    (message "cerebro: wrote %s (%d notes%s)"
             (file-relative-name book cerebro-root)
             (seq-count (lambda (e) (eq (plist-get e :kind) 'note)) entries)
             (if (plist-get result :missing)
                 (format ", %d MISSING" (length (plist-get result :missing)))
               ""))
    (plist-get result :missing)))

;; -- The documents a course produces ------------------------------------
;; One course.org, seven documents. The table mirrors the one in
;; bin/cerebro-course-export (which does the work, so the CLI and the
;; editor cannot diverge); this copy exists so Emacs can *complete* over
;; the outputs and say what each one is.
(defconst cerebro-course-outputs
  '((syllabus  :source course :what "the course description, a couple of pages")
    (dispensa  :source book   :what "the bound handbook: everything, with proofs")
    (manual    :source book   :what "the same, in the manual doctype")
    (slides    :source book   :what "a minimal presentation deck")
    (handout   :source book   :what "those slides, printable")
    (problems  :source book   :what "problem sheet, solutions withheld")
    (exercises :source book   :what "problem sheet, solutions included"))
  "What `C-c e c' can build from a course, and out of which file.")

(defun cerebro-course-directory (&optional from)
  "The course directory FROM (default this buffer) belongs to, or nil."
  (locate-dominating-file (or from (buffer-file-name) default-directory)
                          "course.org"))

(defun cerebro-course-out-directory (directory)
  "Where the built documents of DIRECTORY go."
  (expand-file-name "out" directory))

(defun cerebro-course-output-file (directory output)
  "Path of the built OUTPUT of the course in DIRECTORY.
Named per output rather than per source: `dispensa' and `slides' are
both compiled from book.org, so one name would mean each overwriting the
last."
  (expand-file-name (format "%s-%s.pdf"
                            (file-name-nondirectory (directory-file-name directory))
                            output)
                    (cerebro-course-out-directory directory)))

(defun cerebro-course--export-command (directory output)
  "Shell command building OUTPUT (a symbol, or `all') of DIRECTORY."
  (format "%s %s %s"
          (shell-quote-argument (expand-file-name "bin/cerebro-course-export" cerebro-root))
          (shell-quote-argument (directory-file-name (expand-file-name directory)))
          (shell-quote-argument (symbol-name output))))

(defun cerebro-course--compile (directory output &optional then)
  "Build OUTPUT of DIRECTORY asynchronously; call THEN on success."
  (let* ((default-directory cerebro-root)
         (compilation-buffer-name-function (lambda (&rest _) "*cerebro-export*"))
         (buffer (compile (cerebro-course--export-command directory output))))
    (with-current-buffer buffer
      (add-hook 'compilation-finish-functions
                (lambda (_buffer status)
                  (if (string-prefix-p "finished" status)
                      (when then (funcall then))
                    (message "cerebro: course export failed -- read *cerebro-export*")))
                nil t))
    buffer))

(defun cerebro-course--read-output ()
  "Ask which document to build, showing what each one is."
  (let* ((width (apply #'max (mapcar (lambda (row) (length (symbol-name (car row))))
                                     cerebro-course-outputs)))
         (annotated (mapcar (lambda (row)
                              (cons (format "%-*s  %s" width (car row)
                                            (plist-get (cdr row) :what))
                                    (car row)))
                            cerebro-course-outputs))
         (choice (completing-read "Build: " (mapcar #'car annotated) nil t)))
    (cdr (assoc choice annotated))))

;;;###autoload
(defun cerebro-course-export (output)
  "Build one document of this course and show it (`C-c e c').
The book is regenerated from the programme first, so \"compile the
course\" can never mean \"compile a book that no longer matches it\"."
  (interactive (list (cerebro-course--read-output)))
  (let ((directory (or (cerebro-course-directory)
                       (user-error "cerebro-course: not inside a course"))))
    (cerebro-course--compile
     directory output
     (lambda ()
       (let ((pdf (cerebro-course-output-file directory output)))
         (when (file-exists-p pdf) (cerebro-pdf-show-file pdf))
         (message "cerebro: %s" (file-relative-name pdf cerebro-root)))))))

;;;###autoload
(defun cerebro-course-export-all ()
  "Build *every* document of this course and zip them (`C-c e a').
The archive is the thing you hand over: syllabus, handbook, slides,
problem sheets, one file."
  (interactive)
  (let ((directory (or (cerebro-course-directory)
                       (user-error "cerebro-course: not inside a course"))))
    (cerebro-course--compile
     directory 'all
     (lambda ()
       (message "cerebro: %s"
                (file-relative-name
                 (expand-file-name (format "%s.zip"
                                           (file-name-nondirectory
                                            (directory-file-name directory)))
                                   (cerebro-course-out-directory directory))
                 cerebro-root))))))

;;;###autoload
(defun cerebro-course-preview ()
  "Open one of this course's built documents (`C-c e p').
Completes over what is actually in out/ -- so it answers \"what did I
build, and how did it come out?\" without rebuilding anything."
  (interactive)
  (let* ((directory (or (cerebro-course-directory)
                        (user-error "cerebro-course: not inside a course")))
         (out (cerebro-course-out-directory directory))
         (pdfs (and (file-directory-p out)
                    (directory-files out nil "\\.pdf\\'"))))
    (unless pdfs
      (user-error "cerebro-course: nothing built yet -- C-c e a builds everything"))
    (cerebro-pdf-show-file
     (expand-file-name (completing-read "Document: " pdfs nil t) out))))

;;;###autoload
(defun cerebro-course-build-book-here ()
  "Rebuild the book of the course this buffer belongs to (`C-c e b')."
  (interactive)
  (let ((directory (locate-dominating-file (or (buffer-file-name) default-directory)
                                           "course.org")))
    (unless directory
      (user-error "cerebro-course: no course.org above %s"
                  (abbreviate-file-name (or (buffer-file-name) default-directory))))
    (cerebro-course-build-book directory)))

(provide 'cerebro-course)
