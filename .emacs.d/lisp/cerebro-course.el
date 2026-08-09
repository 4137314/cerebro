;;; cerebro-course.el --- a course is one file: an index into notes/ -*- lexical-binding: t; -*-

;; A course is ONE file -- notes/courses/analysis-A.org -- and it owns no
;; mathematics at all. It is metadata, the course's own prose, and a
;; `* Programme' section that lists, in teaching order, `id:' links to
;; notes that already exist:
;;
;;     * Programme
;;     ** Continuity
;;     - [[id:...][Limits and continuity]]
;;     ** Inner product spaces
;;     - [[id:...][Inner product space]]
;;     - [[id:...][Cauchy--Schwarz inequality]]
;;
;; From that one file, four documents (see `cerebro-course-outputs'). The
;; syllabus *is* the file. The other three are the file with the notes
;; composed into it -- one Org `#+INCLUDE:' per programme entry, so
;; nothing is ever copied and correcting a proof corrects every course
;; that teaches it.
;;
;; There used to be a second, committed file: book.org, generated from
;; the programme, which you had to remember to regenerate. It is gone.
;; The composition now happens at *export time*, into `.build/' beside
;; the course (gitignored, like every other build product), which removes
;; three things at once: a generated file in git, a command to run before
;; compiling, and the failure mode where you compile a book that no
;; longer matches its programme. A course directory is not a thing any
;; more either -- one course, one file.
;;
;; What the composition adds, beyond the includes, is everything a book
;; has and a note does not, all of it from data in the same file:
;;
;;   - chapters, from the programme's own sub-headings;
;;   - appendices, from an `* Appendices' section written exactly like
;;     the programme (`\appendix' is emitted before them);
;;   - an analytical index, built from the notes' own `#+NAME's
;;     (cerebro-latex.el) -- nothing to write by hand;
;;   - the bibliography, from the shared bib/references.bib.
;;
;; The parsing and the composition are pure functions over strings, with
;; the one impure step (an ID -> file) injected -- so what the composer
;; writes is unit-tested without a note database.

(require 'cerebro-org) ;; cerebro-root, org-directory
(require 'cerebro-latex) ;; the profiles, and where a build goes
(require 'compile)
(require 'org-id)
(require 'seq)

;; Showing a built PDF is cerebro-pdf.el's job, and that module drags in
;; a viewer and a theme hook -- neither of which a batch export needs.
;; Loaded on use rather than required at the top, so
;; bin/org-export-latex.el can ask this module what a course compiles to
;; without materialising an editing surface it will never look at.
(declare-function cerebro-pdf-show-file "cerebro-pdf" (file))
(defun cerebro-course--show (pdf)
  "Show PDF, loading the viewer only now."
  (require 'cerebro-pdf)
  (cerebro-pdf-show-file pdf))

(defgroup cerebro-course nil
  "Courses as an index over the note graph."
  :group 'cerebro)

(defcustom cerebro-course-directory (expand-file-name "courses" org-directory)
  "Where courses live: one .org file each."
  :type 'directory
  :group 'cerebro-course)

(defcustom cerebro-course-programme-heading "Programme"
  "Heading whose subtree lists the course's notes, in order."
  :type 'string
  :group 'cerebro-course)

(defcustom cerebro-course-appendix-heading "Appendices"
  "Heading whose subtree lists the notes composed after `\\appendix'.
Optional: a course with no such section simply has no appendices."
  :type 'string
  :group 'cerebro-course)

;; -- Reading a section of the course (pure) -----------------------------

(defun cerebro-course-parse-programme (text &optional heading)
  "The ordered contents of the programme section of TEXT.

Returns a list of plists, in document order:
  (:kind heading :level N :text \"Continuity\")
  (:kind note    :level N :id \"...\" :title \"Limits and continuity\")

LEVEL is relative to the programme heading itself, so a `** Continuity'
under `* Programme' comes back at level 1 -- the composer then decides
what that means in the document, and the outline is free to live at any
depth in the course file.

Links are read wherever they appear (a list item, a paragraph, a table),
because the syllabus is prose a human writes: requiring one syntax for
the machine's benefit is how a manifest and a document drift apart."
  (let* ((heading (or heading cerebro-course-programme-heading))
         (lines (split-string text "\n"))
         (start-re (format "\\`\\(\\*+\\)[ \t]+%s[ \t]*\\'" (regexp-quote heading)))
         (base nil)      ; the level of the section heading
         (level 0)       ; current relative level
         (in-comment nil)
         (entries nil))
    ;; `catch' rather than a flag: the scan *stops* at the first heading
    ;; back at the section's own level, so a link in a later section
    ;; (a bibliography, an appendix) is never mistaken for part of it.
    (catch 'cerebro-course--end
      (dolist (line lines)
        (cond
         ;; Commentary is not the course. A `#+begin_comment' block is
         ;; where this project puts meta-text (CLAUDE.md), and the
         ;; scaffolded course explains the format with example links
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
         ;; A heading: either deeper (a chapter of the section) or the
         ;; end of it.
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
overrides the book's own title -- plus stray tags, IDs and the note's
`#+HASH:'. So the composed `#+INCLUDE:' starts below them, and this is
where."
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

;; -- Composing the document (pure, given a resolver) --------------------

(defun cerebro-course--front-matter (text)
  "The course file's own keyword lines, verbatim. Pure.

Everything above the first heading that is a `#+KEY:' line: the title,
the date, the subject, the classification. The composed document has to
carry them or it would be an untitled book by nobody -- and copying them
verbatim is what makes the course file the single place they are
written."
  (let (kept)
    (catch 'done
      (dolist (line (split-string text "\n"))
        (cond
         ((string-match-p "\\`\\*+[ \t]" line) (throw 'done nil))
         ((string-match-p "\\`[ \t]*#\\+[A-Za-z_]+:" line) (push line kept)))))
    (nreverse kept)))

(defun cerebro-course--section (entries resolve directory)
  "Compose ENTRIES (from `cerebro-course-parse-programme') into Org text.
RESOLVE turns an ID into a plist; DIRECTORY is where the composed file
will live, so the includes are relative to it.

Returns (TEXT . MISSING-IDS). The unresolved IDs come back as a value
rather than being pushed into a variable the caller names: this file is
lexically bound, so `set' on a passed-in symbol reaches a *dynamic*
binding that does not exist, and the composer died on the first missing
note -- which is precisely the case it exists to survive."
  (let ((missing nil))
    (cons
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
                  ;; and level 1 when the section has no chapters at all,
                  ;; so a flat reading list still makes a flat document.
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
      entries "")
     (nreverse missing))))

(defun cerebro-course-compose (text resolve directory)
  "The text of the composed document for the course file TEXT.

RESOLVE is called with a note ID and returns a plist (:file PATH :title
STRING :body-line N) or nil when the ID is unknown. DIRECTORY is where
the composed file will be written.

Returns a plist (:text STRING :missing IDS). Pure, given RESOLVE."
  (let* ((programme (cerebro-course--section
                     (cerebro-course-parse-programme text) resolve directory))
         (appendices (cerebro-course--section
                      (cerebro-course-parse-programme
                       text cerebro-course-appendix-heading)
                      resolve directory)))
    (list
     :text
     (concat
      "# -*- buffer-read-only: t -*-\n"
      "# COMPOSED at export time from the course file -- a build product,\n"
      "# like the .tex beside it. Nothing here is a source: the course's\n"
      "# own prose belongs in its .org file, the mathematics in the notes\n"
      "# this file includes.\n"
      (mapconcat #'identity (cerebro-course--front-matter text) "\n")
      "\n\n"
      (car programme)
      (unless (string-empty-p (car appendices))
        (concat
         ;; Everything after this is lettered, not numbered -- the one
         ;; line that turns a section of the document into an appendix,
         ;; and it is emitted because the course *said* so, not because
         ;; any note knows it is an appendix.
         "#+LATEX: \\appendix\n\n"
         (car appendices))))
     :missing (append (cdr programme) (cdr appendices)))))

;; -- The impure half ----------------------------------------------------

(defun cerebro-course-resolve-id (id)
  "Find the note with ID and report what the composer needs about it."
  (when-let* ((file (org-id-find-id-file id)))
    (let ((text (with-temp-buffer (insert-file-contents file) (buffer-string))))
      (list :file file
            :title (when (string-match "^#\\+TITLE:[ \t]*\\(.*\\)$" text)
                     (string-trim (match-string 1 text)))
            :body-line (cerebro-course-note-body-line text)))))

(defun cerebro-course-title (text fallback)
  "The course's title: its `#+COURSE_TITLE:', else FALLBACK."
  (if (string-match "^#\\+COURSE_TITLE:[ \t]*\\(.*\\)$" text)
      (string-trim (match-string 1 text))
    fallback))

(defun cerebro-course-file-p (&optional file)
  "Non-nil when FILE (default this buffer's) is a course file.

Being *in* notes/courses/ is not enough: notes/courses/README.org is in
it and is this repository explaining the directory, not a course. It
answered yes here, which made `C-c e c' offer to build four documents
out of the README -- and the first of them, the syllabus, would have
compiled, because a syllabus is just the file typeset."
  (let ((file (or file (buffer-file-name))))
    (and (cerebro-note-file-p file)
         (file-equal-p (or (file-name-directory (expand-file-name file)) "")
                       (file-name-as-directory cerebro-course-directory)))))

(defun cerebro-course-this-file ()
  "The course file this buffer is, or a user error."
  (or (and (cerebro-course-file-p) (buffer-file-name))
      (user-error "cerebro-course: not a course file (%s)"
                  (abbreviate-file-name (file-name-as-directory
                                         cerebro-course-directory)))))

(defun cerebro-course-slug (file)
  "The course's short name: its file name without the extension."
  (file-name-base file))

;; -- Where a composed document goes -------------------------------------

(defun cerebro-course-composed-file (file profile)
  "Path of the composed source for FILE under PROFILE.

In `.build/' beside the course, named per profile: `handbook' and
`slides' are composed differently (the content filters run later, but
the *build* must not collide), and a build directory is already what
this repository means by \"derived, gitignored, safe to delete\"."
  (expand-file-name (format "%s-%s.org" (cerebro-course-slug file) profile)
                    (cerebro-latex-build-dir file)))

(defun cerebro-course-compose-file (file profile)
  "Write the composed source for FILE under PROFILE; return its path.
Signals when the programme resolves to nothing at all -- a course that
lists no notes has no book, which is a normal state for a new course and
an error for a compile."
  (let* ((text (with-temp-buffer (insert-file-contents file) (buffer-string)))
         (target (cerebro-course-composed-file file profile))
         (directory (file-name-directory target))
         (result (progn (make-directory directory t)
                        (cerebro-course-compose text #'cerebro-course-resolve-id
                                                directory))))
    (unless (cerebro-course-parse-programme text)
      (user-error "cerebro-course: `* %s' in %s lists no notes yet"
                  cerebro-course-programme-heading
                  (file-relative-name file cerebro-root)))
    (with-temp-file target (insert (plist-get result :text)))
    (when (plist-get result :missing)
      (message "cerebro-course: %d unresolved id: link(s) in %s"
               (length (plist-get result :missing))
               (file-relative-name file cerebro-root)))
    target))

(defun cerebro-course-source (file profile)
  "What PROFILE actually compiles, for the course FILE.

The syllabus *is* the course file: it is the two pages a person wrote,
and composing twenty notes into it would be a different document. Every
other profile compiles the composition. This is the one place that
decides, and bin/org-export-latex.el asks it -- so `make export' on a
course and `C-c e c' cannot disagree."
  (if (eq profile 'syllabus)
      file
    (cerebro-course-compose-file file profile)))

;; -- The documents a course produces ------------------------------------
;; One file, four documents -- one per audience, and there are only four
;; audiences:
;;
;;   syllabus   whoever is deciding whether to take the course
;;   lecture    me, holding it at the board
;;   slides     the room, while I talk
;;   handbook   the student, at home, afterwards
;;
;; The table mirrors the one in bin/cerebro-course-export (which does the
;; work, so the CLI and the editor cannot diverge); this copy exists so
;; Emacs can *complete* over the outputs and say what each one is.
(defconst cerebro-course-outputs
  '((syllabus :what "the course description, a couple of pages")
    (lecture  :what "my notes for teaching: statements and proofs")
    (slides   :what "the deck: statements only, nothing else")
    (handbook :what "the textbook: everything, with appendices and an index"))
  "What `C-c e c' can build from a course.")

(defun cerebro-course-out-directory ()
  "Where the built documents of every course are collected."
  (expand-file-name "out" cerebro-course-directory))

(defun cerebro-course-output-file (file output)
  "Path of the built OUTPUT of the course FILE.
Named per output rather than per source: all four come from one file, so
one name would mean each overwriting the last."
  (expand-file-name (format "%s-%s.pdf" (cerebro-course-slug file) output)
                    (cerebro-course-out-directory)))

(defun cerebro-course--export-command (file output)
  "Shell command building OUTPUT (a symbol, or `all') of the course FILE."
  (format "%s %s %s"
          (shell-quote-argument (expand-file-name "bin/cerebro-course-export" cerebro-root))
          (shell-quote-argument (expand-file-name file))
          (shell-quote-argument (symbol-name output))))

(defun cerebro-course--compile (file output &optional then)
  "Build OUTPUT of the course FILE asynchronously; call THEN on success."
  (let* ((default-directory cerebro-root)
         (compilation-buffer-name-function (lambda (&rest _) "*cerebro-export*"))
         (buffer (compile (cerebro-course--export-command file output))))
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
  ;; Padded by hand: Emacs\=' `format' has no `%-*s' (that is C\='s
  ;; printf), and calling it with one signals `Invalid format operation'
  ;; -- which this did, every time, in the one code path a test never
  ;; reaches because it is a prompt.
  (let* ((width (apply #'max (mapcar (lambda (row) (length (symbol-name (car row))))
                                     cerebro-course-outputs)))
         (annotated (mapcar (lambda (row)
                              (let ((name (symbol-name (car row))))
                                (cons (concat name
                                              (make-string (- width (length name)) ?\s)
                                              "  " (plist-get (cdr row) :what))
                                      (car row))))
                            cerebro-course-outputs))
         (choice (completing-read "Build: " (mapcar #'car annotated) nil t)))
    (cdr (assoc choice annotated))))

;;;###autoload
(defun cerebro-course-export (output)
  "Build one document of this course and show it (`C-c e c').
The notes are composed in fresh every time, so \"compile the course\" can
never mean \"compile a book that no longer matches it\"."
  (interactive (list (cerebro-course--read-output)))
  (let ((file (cerebro-course-this-file)))
    (cerebro-course--compile
     file output
     (lambda ()
       (let ((pdf (cerebro-course-output-file file output)))
         (when (file-exists-p pdf) (cerebro-course--show pdf))
         (message "cerebro: %s" (file-relative-name pdf cerebro-root)))))))

;;;###autoload
(defun cerebro-course-export-all ()
  "Build *every* document of this course and zip them (`C-c e a').
The archive is the thing you hand over: syllabus, lecture notes, slides
and handbook, one file."
  (interactive)
  (let ((file (cerebro-course-this-file)))
    (cerebro-course--compile
     file 'all
     (lambda ()
       (message "cerebro: %s"
                (file-relative-name
                 (expand-file-name (format "%s.zip" (cerebro-course-slug file))
                                   (cerebro-course-out-directory))
                 cerebro-root))))))

;;;###autoload
(defun cerebro-course-preview ()
  "Open one of this course's built documents (`C-c e p').
Completes over what is actually in out/ -- so it answers \"what did I
build, and how did it come out?\" without rebuilding anything."
  (interactive)
  (let* ((file (cerebro-course-this-file))
         (out (cerebro-course-out-directory))
         (prefix (concat (cerebro-course-slug file) "-"))
         (pdfs (and (file-directory-p out)
                    (seq-filter (lambda (f) (string-prefix-p prefix f))
                                (directory-files out nil "\\.pdf\\'")))))
    (unless pdfs
      (user-error "cerebro-course: nothing built yet -- C-c e a builds everything"))
    (cerebro-course--show
     (expand-file-name (completing-read "Document: " pdfs nil t) out))))

;;;###autoload
(defun cerebro-course-find ()
  "Open a course (`C-c e o')."
  (interactive)
  (let ((courses (and (file-directory-p cerebro-course-directory)
                      (mapcar #'file-name-nondirectory
                              (seq-filter #'cerebro-course-file-p
                                          (directory-files
                                           cerebro-course-directory t "\\.org\\'"))))))
    (unless courses
      (user-error "cerebro-course: no courses in %s yet" cerebro-course-directory))
    (find-file (expand-file-name (completing-read "Course: " courses nil t)
                                 cerebro-course-directory))))

(provide 'cerebro-course)
