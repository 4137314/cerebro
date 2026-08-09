;;; cerebro-dashboard.el --- what to open Emacs onto -*- lexical-binding: t; -*-

;; Opening the second brain used to land on the *scratch* buffer, which
;; says nothing about the second brain. This module replaces that with a
;; start page answering the three questions you actually have when you
;; sit down: what did I touch last, what is open, and what is scheduled.
;;
;; The split matters: the *data* below is pure Elisp over the plain-text
;; sources (the notes tree, issues/issues.org) and is unit-tested; the
;; renderer is `emacs-dashboard' from guix.scm, which only knows how to
;; draw sections. So:
;;
;;   - the numbers can never drift from the files, because they are read
;;     from the files at refresh time -- there is no cache to invalidate;
;;   - outside the pinned environment (no dashboard package) the same
;;     data still renders, in a plain `cerebro-report' buffer, and `C-c h'
;;     keeps working (invariant 4);
;;   - the issue section reads Org with `org-map-entries' rather than
;;     shelling out to `cerebro issue list' -- it only *reads*, so this is
;;     not a second implementation of the issue lifecycle (which stays in
;;     bin/cerebro-issues.el, the one thing allowed to write state).

(require 'cerebro-org)     ;; cerebro-root, cerebro-note-files, cerebro-report
(require 'cerebro-mode)    ;; math or dev -- which issues and which keys
(require 'cerebro-guix)    ;; environment headline + soft require
(require 'cerebro-issues)  ;; cerebro-issues-file
(require 'cerebro-results) ;; the census, and what still owes a proof
(require 'cerebro-taxonomy) ;; the maturity ladder
(require 'cerebro-cli)     ;; the commands behind the navigator buttons
(require 'cerebro-math)    ;; ...and the one that writes a theorem
(require 'cerebro-study)   ;; ...and the one that switches to reading
(require 'cerebro-theme)   ;; whether a Nerd Font is actually installed

;; -- Data ---------------------------------------------------------------

(defun cerebro-dashboard-recent-notes (limit &optional dir)
  "The LIMIT most recently modified note files under DIR (default notes/).
Modification time, not visit history: `recentf' knows what *this* Emacs
opened, which after a `cerebro note new' from the shell, a git pull or a
fresh clone is the wrong answer -- the file system knows what actually
changed."
  ;; `copy-sequence' because `cerebro-note-files' hands back the list that
  ;; IS the memo (cerebro-cache.el), and `sort' is destructive: sorting it
  ;; rewrites the archive's cached listing in place, for every later
  ;; caller in the session. On this Emacs that only reorders it -- Emacs
  ;; 30's `sort' reuses the cons cells and moves the values -- but on the
  ;; relinking `sort' of Emacs 29 and earlier the cached head ends up
  ;; partway down the sorted list, and `cerebro-note-files' starts
  ;; answering with a *truncated* archive: fewer notes in the census, in
  ;; the results graph, in the linter, in every query, until something
  ;; changes a directory's mtime. Nothing here is worth that.
  (let ((files (copy-sequence (cerebro-note-files dir))))
    (seq-take (sort files
                    (lambda (a b)
                      (time-less-p (file-attribute-modification-time (file-attributes b))
                                   (file-attribute-modification-time (file-attributes a)))))
              limit)))

(defun cerebro-dashboard--issue-rank (issue)
  "Sort key for ISSUE: priority first, then DOING before TODO.
Priority is Org's own char (?A < ?B < ?C); an issue with none is ranked
at `org-default-priority', exactly as the agenda ranks it, so the
dashboard and `C-c a i' can never disagree about what is most urgent."
  (list (or (plist-get issue :priority) org-default-priority)
        (if (equal (plist-get issue :todo) "DOING") 0 1)))

(defun cerebro-dashboard-open-issues (limit &optional file)
  "The LIMIT most urgent open issues in FILE (default issues/issues.org).
Open means TODO or DOING -- an issue you have already started is still
open. Each element is a plist (:id :todo :priority :title :tags)."
  (let ((f (or file (cerebro-issues-file))))
    (when (file-readable-p f)
      (let (issues)
        (with-current-buffer (find-file-noselect f)
          (org-with-wide-buffer
           (goto-char (point-min))
           (org-map-entries
            (lambda ()
              (let ((c (org-heading-components)))
                (when (member (nth 2 c) '("TODO" "DOING"))
                  (push (list :id (org-entry-get nil "ID")
                              :todo (nth 2 c)
                              :priority (nth 3 c)
                              :title (nth 4 c)
                              :tags (org-get-tags nil t))
                        issues)))))))
        (seq-take (sort (nreverse issues)
                        (lambda (a b)
                          (let ((ra (cerebro-dashboard--issue-rank a))
                                (rb (cerebro-dashboard--issue-rank b)))
                            (or (< (car ra) (car rb))
                                (and (= (car ra) (car rb))
                                     (< (cadr ra) (cadr rb)))))))
                  limit)))))

(defun cerebro-dashboard-mode-issues (limit &optional file mode)
  "The LIMIT most urgent open issues that are MODE's work (cerebro-mode.el).

A separate function rather than a filter inside
`cerebro-dashboard-open-issues': that one answers \"what is open\", which
is a fact about the tracker and is what the census line counts. This one
answers \"what is open *for me, today*\", which is the question the
section on the start page is asking. Keeping them apart is why the census
can say `9 open issues' while the list below shows six -- and why the
number never silently shrinks with the mode.

The filter only removes issues explicitly tagged for the other mode; an
untagged issue belongs to both (see `cerebro-mode-issue-p')."
  (let ((mode (or mode (cerebro-mode-active))))
    (seq-take
     (seq-filter (lambda (issue)
                   (cerebro-mode-issue-p (plist-get issue :tags) mode))
                 (cerebro-dashboard-open-issues most-positive-fixnum file))
     limit)))

(defconst cerebro-dashboard-label-width 62
  "Longest label the start page prints, in columns.
dashboard centres a section by padding every line to the widest one, so
a single long issue title pushes the whole block sideways and then wraps
-- which is how the page ends up looking broken rather than long.")

(defun cerebro-dashboard-truncate (label &optional width)
  "LABEL cut to WIDTH columns (default `cerebro-dashboard-label-width').
A start page lists what is open; it does not reproduce it."
  (truncate-string-to-width label (or width cerebro-dashboard-label-width)
                            nil nil "…"))

(defun cerebro-dashboard-note-maturity (file)
  "The maturity tag of note FILE, read from its `#+FILETAGS:' line.
Only the front matter is read -- a note is a long file and its tags are
always in the first few lines."
  (with-temp-buffer
    (insert-file-contents file nil 0 2000)
    (goto-char (point-min))
    (when (re-search-forward "^[ \t]*#\\+FILETAGS:[ \t]*\\(.*\\)$" nil t)
      (cerebro-taxonomy-maturity
       (split-string (string-trim (match-string 1)) ":" t)))))

(defun cerebro-dashboard-notes-by-maturity (maturity limit &optional dir)
  "The LIMIT oldest notes at MATURITY -- the ones that have sat there.
Oldest first on purpose: a seed written this morning is not a problem, a
seed from last term is the archive quietly not growing. Memoised with
the rest of the whole-tree scans (cerebro-cache.el)."
  ;; The memo wraps the *filter*, which is the expensive part: deciding a
  ;; note's maturity opens it and reads its front matter, so this is one
  ;; file read per note in the archive per maturity asked about. It used
  ;; to wrap `files' alone -- the thunk was `(lambda () files)', a memo
  ;; that recomputed nothing and stored a second alias to a list the
  ;; cache already held -- so every refresh of the start page reread the
  ;; whole archive while the docstring said it did not.
  (seq-take
   (sort (copy-sequence
          (let ((files (cerebro-note-files dir)))
            (cerebro-cache-get
             (list 'notes-by-maturity maturity dir)
             (cerebro-cache-file-signature files)
             (lambda ()
               (seq-filter (lambda (f)
                             (equal (cerebro-dashboard-note-maturity f) maturity))
                           files)))))
         (lambda (a b)
           (time-less-p (file-attribute-modification-time (file-attributes a))
                        (file-attribute-modification-time (file-attributes b)))))
   limit))

(defun cerebro-dashboard-unproved-results (limit)
  "The LIMIT results that still owe a proof (open first, then assumed)."
  (seq-take (cerebro-results-unproved (cerebro-results-scan)) limit))

(defun cerebro-dashboard-result-label (record)
  "One display line for an unproved RECORD."
  (cerebro-dashboard-truncate
   (format "%-8s %-9s %s"
           (plist-get record :type)
           (format "[%s]" (or (plist-get record :status) "?"))
           (plist-get record :name))))

(defun cerebro-dashboard-issue-label (issue)
  "One display line for ISSUE: state, priority and title."
  (cerebro-dashboard-truncate
   (format "%-5s %s%s"
           (plist-get issue :todo)
           (if (plist-get issue :priority)
               (format "[#%c] " (plist-get issue :priority))
             "")
           (plist-get issue :title))))

(defun cerebro-dashboard-note-label (file)
  "One display line for note FILE: its path relative to the notes tree."
  (cerebro-dashboard-truncate (file-relative-name file org-directory)))

(defun cerebro-dashboard-summary ()
  "One line under the banner: what is in the archive, and what is wrong.

Deliberately short. The environment (profile, pin, package count) is
appended *only* when this Emacs is not the pinned one -- on the normal
path it is noise on a page whose job is to say what to do next, and when
it is not the normal path it is the first thing you need to know. The
full report is always one key away (`C-c G s')."
  (concat
   ;; The mode first: it says what the rest of the page is showing you,
   ;; and in `dev' it says that every file in this repository is writable
   ;; (cerebro-mode.el). A setting that persists between sessions has to
   ;; be readable without being asked for.
   (format "%s · %d notes · %d results · %d open issues"
           (cerebro-mode-active)
           (length (cerebro-note-files))
           (length (cerebro-results-scan))
           (length (cerebro-dashboard-open-issues most-positive-fixnum)))
   (unless (cerebro-guix-inside-p)
     (format " · %s" (cerebro-guix-headline)))))

(defun cerebro-dashboard-visit-issue (id)
  "Open issues/issues.org at the issue with :ID: ID.
By ID rather than by buffer position: the dashboard may have been drawn
before the CLI (or a `cerebro issue close') rewrote the file."
  (find-file (cerebro-issues-file))
  (let ((pos (and id (org-find-property "ID" id))))
    (when pos
      (goto-char pos)
      (org-back-to-heading t)
      ;; `org-fold-show-entry' is the org 9.6+ name; `org-show-entry' is
      ;; only an obsolete alias for it now -- call whichever this org has,
      ;; like cerebro-org.el does for `org-fold-catch-invisible-edits'.
      (funcall (if (fboundp 'org-fold-show-entry) #'org-fold-show-entry #'org-show-entry)))))

;; -- The hermetic register ---------------------------------------------
;; The start page is titled in Greek and its sections are marked with the
;; classical planetary signs. That is not decoration for its own sake:
;; each sign is the one this tradition already attaches to the thing the
;; section is about, so the page can be read at a glance by shape before
;; it is read by word -- Saturn is what weighs on you, Mars is what is
;; still to be fought for, the Moon is what has just changed.
;;
;; Every glyph is checked against the font in use and falls back to a
;; plain-ASCII marker: this repo already learned that lesson with Nerd
;; Font icons (`cerebro-theme-nerd-icons-p'), and a row of empty boxes is
;; worse than a row of dashes.

(defconst cerebro-dashboard-title "κέρεβρο"
  "The start page's title: `cerebro', written in Greek.
The archive is a Greek idea before it is a Latin word -- and the name in
its own alphabet says what the page is without the sentence of
explanation that used to sit under it.")

(defface cerebro-dashboard-title-face
  '((t :inherit (bold link) :height 1.6))
  "Face for the Greek title over the start page.

`link' rather than a hex blue, on purpose and for the same reason
cerebro-appearance.el gives for hl-todo: a literal `#2fafff' is a colour
picked for one variant and wrong in the other, while `link' is blue in
every theme this config can load -- and stays blue after `C-c u t'.")

(defconst cerebro-dashboard-signs
  '((archive  "☿" "*")   ; Mercury -- Hermes, the whole archive
    (issues   "♄" "#")   ; Saturn -- what binds, what weighs
    (unproved "♂" "!")   ; Mars -- what is still to be fought for
    (recent   "☽" "~")   ; Luna -- what has just changed
    (seeds    "♃" "+")   ; Jupiter -- what should be growing and is not
    (keys     "☉" ">"))  ; Sol -- what you can do, made visible
  "Section -> (GLYPH ASCII-FALLBACK).
Data, so adding a section is adding a row rather than hunting for a
literal in a format string.")

(defun cerebro-dashboard-sign (section)
  "The mark for SECTION: its glyph when the font has one, else ASCII.
`char-displayable-p' is asked per character rather than once for the
set, because a font may carry Mercury and not Jupiter."
  (let ((row (assq section cerebro-dashboard-signs)))
    (cond
     ((null row) "")
     ((and (display-graphic-p)
           (char-displayable-p (string-to-char (nth 1 row))))
      (nth 1 row))
     (t (nth 2 row)))))

(defun cerebro-dashboard-heading (section text)
  "TEXT preceded by SECTION's hermetic mark."
  (format "%s  %s" (cerebro-dashboard-sign section) text))

;; -- What you can actually do ------------------------------------------
;; The complaint this answers: the page said what was in the archive and
;; nothing about how to work it, so the keys lived in README.org, which
;; is not where you are when you need them.
;;
;; Data, and the keys are the *real* ones (cerebro-keys.el). A row that
;; drifts from its binding is worse than no row, so a test checks every
;; key here is bound and every command exists.

(defconst cerebro-dashboard-key-rows
  '(("open"  ("C-c a m" . "review")
             ("C-c i"   . "issues")
             ("C-c h"   . "home"))
    ("write" ("C-c m t" . "theorem")
             ("C-c m d" . "definition")
             ("C-c m e" . "extract"))
    ("read"  ("C-c u s" . "mode")
             ("C-c u r" . "study")
             ("C-c u p" . "render"))
    ("find"  ("C-c f n" . "a note")
             ("C-c f c" . "a course")
             ("C-c f r" . "a result"))
    ("make"  ("C-c e e" . "note")
             ("C-c e c" . "course")
             ("C-c d l" . "lint"))
    ("learn" ("C-c H k" . "keys")
             ("C-c H v" . "settings")
             ("C-c H c" . "conventions")))
  "Groups of (KEY . WHAT) shown on the start page.
Five rows because there are five things one does here: open the day,
write mathematics, read it back, find something, and make a document.

Three keys per row and terse labels, both forced by the layout:
dashboard centres a section by padding every line to the widest one, so
one long line moves the whole page sideways and then wraps. The full
descriptions live in `C-c ?' and in README.org; this is a reminder, not
a manual.")

(defun cerebro-dashboard-mode-key-rows (&optional mode)
  "The key rows for MODE: its own `:keys', or the default ones.

The default rows above *are* the math rows -- writing a theorem, reading
it back, compiling it -- because that is what this editor is for, so
`math' declares no `:keys' of its own and there is one copy of them
rather than two. `dev' declares a different set (git, the backlog, the
gates), since a page offering `C-c m t' to someone about to edit
cerebro-latex.el is a page nobody reads twice."
  (or (cerebro-mode-get (or mode (cerebro-mode-active)) :keys)
      cerebro-dashboard-key-rows))

(defun cerebro-dashboard-key-lines (&optional mode)
  "The key rows for MODE as display lines, one per group. Pure.
Each line is truncated to `cerebro-dashboard-label-width', like every
other line on the page, so a row edited to be too long degrades to an
ellipsis instead of breaking the centring."
  (mapcar
   (lambda (row)
     (cerebro-dashboard-truncate
      (format "%-6s %s"
              (car row)
              (mapconcat (lambda (cell)
                           (format "%s %s" (car cell) (cdr cell)))
                         (cdr row)
                         " · "))))
   (cerebro-dashboard-mode-key-rows mode)))

;; -- Renderer: emacs-dashboard when present ----------------------------

(defvar cerebro-dashboard-buffer "*cerebro-dashboard*"
  "Buffer used by the fallback renderer (see `cerebro-dashboard--fallback').
Deliberately not `cerebro-report's default *cerebro*: that one is the
shared, overwritten-on-every-query report buffer, and it is the one
cerebro-ui.el confines to a small side window -- a start page needs a
window of its own, and needs to survive the next `C-c q h'.")

;; -- The banner ---------------------------------------------------------
;; A start page you open every day should look like somewhere you want to
;; be, so the top of it is a picture: .emacs.d/hermes.jpg, the engraving
;; of Hermes Trismegistus with an armillary sphere, pointing from the
;; instrument in his hand to the sun and moon it measures.
;;
;; bin/cerebro-banner is still here and still works: it draws a ringed
;; planet from thirty lines of ImageMagick, offline, as banner.png. Point
;; `cerebro-dashboard-banner' back at that file (and re-run the script)
;; for a generated banner rather than this one, or at any image of your
;; own -- the type is read from the file, so PNG or JPEG both work.

(defcustom cerebro-dashboard-banner
  (expand-file-name ".emacs.d/hermes.jpg" cerebro-root)
  "Image shown at the top of the start page.
Any format this Emacs can decode; `cerebro-dashboard-banner-usable-p'
checks the file's own type rather than assuming one."
  :type 'file
  :group 'cerebro)

(defcustom cerebro-dashboard-banner-height 260
  "How tall the banner is drawn, in pixels.
The file is bigger than this: it is scaled down, so the same image is
crisp on a HiDPI screen and does not fill a small frame."
  :type 'integer
  :group 'cerebro)

(defun cerebro-dashboard-banner-usable-p (&optional file)
  "Non-nil when FILE can actually be shown as the banner.
An image banner needs both a readable file and an Emacs that can decode
*that* image -- in a terminal frame there is no image support at all,
and emacs-dashboard would fall back to its own ASCII logo. Pure enough
to test.

The decodability question is asked about the file's own type, not about
PNG: this used to hardcode `png', which was true only for as long as the
banner happened to be one. A JPEG banner on an Emacs built without JPEG
support would have passed that check and then failed to draw -- the
banner is the first thing you see, so it fails to the ASCII logo
deliberately rather than to a broken image."
  (let ((file (or file cerebro-dashboard-banner)))
    (and (stringp file)
         (file-readable-p file)
         (when-let* ((type (ignore-errors (image-type file nil nil))))
           (image-type-available-p type))
         t)))

(when (cerebro-guix-soft-require 'dashboard)
  (setq dashboard-startup-banner
        (if (cerebro-dashboard-banner-usable-p)
            cerebro-dashboard-banner
          ;; No image support (a terminal frame): dashboard's own text
          ;; logo, rather than a broken-image placeholder.
          'ascii)
        dashboard-image-banner-max-height cerebro-dashboard-banner-height
        dashboard-banner-ascii cerebro-dashboard-title
        ;; The name, in Greek, in blue -- and nothing else. The sentence
        ;; that used to be here ("a second brain for pure mathematics")
        ;; explained the archive to someone who is not you, every single
        ;; morning, in the one place where the answer to "what is this?"
        ;; is already "I opened it".
        dashboard-banner-logo-title
        (propertize cerebro-dashboard-title 'face 'cerebro-dashboard-title-face)
        dashboard-center-content t
        dashboard-vertically-center-content nil
        dashboard-set-navigator t
        dashboard-set-footer nil
        ;; Icons come from the Nerd Font the theme already checked for
        ;; (cerebro-theme.el): a *glyph*, so this works in a terminal
        ;; frame too, and degrades to plain text when the font is absent.
        dashboard-icon-type (when (cerebro-theme-nerd-icons-p) 'nerd-icons)
        dashboard-set-heading-icons (and (cerebro-theme-nerd-icons-p) t)
        dashboard-set-file-icons (and (cerebro-theme-nerd-icons-p) t)
        ;; The census line replaces dashboard's default "N packages
        ;; loaded in X seconds", which is meaningless here -- nothing is
        ;; ever loaded from a package archive.
        dashboard-set-init-info t
        dashboard-init-info #'cerebro-dashboard-summary
        dashboard-week-agenda nil
        dashboard-agenda-release-buffers t) ; don't keep every agenda file open

  (defun cerebro-dashboard--insert-keys (_list-size)
    "Dashboard section: what you can do, with the keys that do it.
Which keys depends on the mode -- see `cerebro-dashboard-mode-key-rows'."
    (dashboard-insert-section
     (cerebro-dashboard-heading 'keys "To work:")
     (cerebro-dashboard-key-lines)
     (length (cerebro-dashboard-mode-key-rows))
     'cerebro-keys
     "w"
     `(lambda (&rest _) (cerebro-menu))
     el))

  (defun cerebro-dashboard--insert-issues (list-size)
    "Dashboard section: the most urgent open issues for this mode."
    (dashboard-insert-section
     (cerebro-dashboard-heading 'issues
                                (format "Open issues (%s):" (cerebro-mode-active)))
     (cerebro-dashboard-mode-issues list-size)
     list-size
     'cerebro-issues
     "i"
     `(lambda (&rest _) (cerebro-dashboard-visit-issue ,(plist-get el :id)))
     (cerebro-dashboard-issue-label el)))

  (defun cerebro-dashboard--insert-notes (list-size)
    "Dashboard section: the notes that changed most recently."
    (dashboard-insert-section
     (cerebro-dashboard-heading 'recent "Recently changed notes:")
     (cerebro-dashboard-recent-notes list-size)
     list-size
     'cerebro-notes
     "r"
     `(lambda (&rest _) (find-file-existing ,el))
     (cerebro-dashboard-note-label el)))

  (defun cerebro-dashboard--insert-unproved (list-size)
    "Dashboard section: results that still owe a proof."
    (dashboard-insert-section
     (cerebro-dashboard-heading 'unproved "Still to prove:")
     (cerebro-dashboard-unproved-results list-size)
     list-size
     'cerebro-unproved
     "u"
     `(lambda (&rest _) (cerebro-results-dependencies ,(plist-get el :name)))
     (cerebro-dashboard-result-label el)))

  (defun cerebro-dashboard--insert-seeds (list-size)
    "Dashboard section: the oldest notes still at `:seed:'."
    (dashboard-insert-section
     (cerebro-dashboard-heading 'seeds "Seeds, oldest first:")
     (cerebro-dashboard-notes-by-maturity "seed" list-size)
     list-size
     'cerebro-seeds
     "s"
     `(lambda (&rest _) (find-file-existing ,el))
     (cerebro-dashboard-note-label el)))

  (dolist (gen '((cerebro-keys     . cerebro-dashboard--insert-keys)
                 (cerebro-issues   . cerebro-dashboard--insert-issues)
                 (cerebro-notes    . cerebro-dashboard--insert-notes)
                 (cerebro-unproved . cerebro-dashboard--insert-unproved)
                 (cerebro-seeds    . cerebro-dashboard--insert-seeds)))
    (add-to-list 'dashboard-item-generators gen))

  ;; The whole icon table, not just the two custom sections. dashboard
  ;; computes its default at *its* load time, from a `dashboard-icon-type'
  ;; that is still nil then -- so the table is empty, and once heading
  ;; icons are switched on every section looks up nil and the render dies
  ;; half way, leaving a blank start page ("Unable to find icon with name
  ;; `nil\' in icon set `octicon\'", seen on screen before this line
  ;; existed). Setting it whole is also the only version of this that is
  ;; readable: these are the icons, here they are.
  (when (cerebro-theme-nerd-icons-p)
    (setq dashboard-heading-icons
          '((cerebro-keys   . "nf-oct-command_palette")
            (cerebro-issues . "nf-oct-issue_opened")
            (cerebro-notes  . "nf-oct-note")
            (cerebro-unproved . "nf-oct-shield")
            (cerebro-seeds    . "nf-oct-light_bulb")
            (agenda         . "nf-oct-calendar")
            (recents        . "nf-oct-history")
            (bookmarks      . "nf-oct-bookmark")
            (projects       . "nf-oct-rocket")
            (registers      . "nf-oct-database"))))

  ;; Order = the order you want to read them in: what is open, what you
  ;; were writing, what the calendar says.
  ;; Two sections, both computed from files in this repo. The agenda is
  ;; deliberately *not* one of them: rendering it here means scanning
  ;; every agenda file on every refresh -- slow, and the source of a
  ;; "Cache must be active" message from Org's element cache in buffers
  ;; opened and killed behind your back. It is one keystroke away
  ;; (`C-c a m', or the [Morning review] button above), which is where a
  ;; start page should put it.
  ;; Four sections, in the order the questions actually arrive: what is
  ;; open, what the archive owes a proof, what I was writing, and what
  ;; has been a seed for too long. All four are computed from files in
  ;; this repo through the memoised scans, so a refresh is cheap.
  (setq dashboard-items '((cerebro-keys     . 6)
                          (cerebro-issues   . 5)
                          (cerebro-unproved . 5)
                          (cerebro-notes    . 6)
                          (cerebro-seeds    . 4)))

  ;; One row of buttons for the operations that start a session. Each is
  ;; an existing command -- no logic lives in the dashboard itself.
  ;; Quoted, not backquoted: dashboard funcalls each entry's action as a
  ;; plain list, and nothing here needs to close over a local.
  (setq dashboard-navigator-buttons
        '((("" "Morning review" "Today's agenda (C-c a m)"
            (lambda (&rest _) (org-agenda nil "m")))
           ("" "New theorem" "A note that is a theorem (C-c m t)"
            (lambda (&rest _) (call-interactively #'cerebro-math-new-theorem)))
           ("" "Find note" "Org-roam node find (C-c n f)"
            (lambda (&rest _) (call-interactively
                               (if (fboundp 'org-roam-node-find)
                                   #'org-roam-node-find #'cerebro-note-find))))
           ("" "Study" "Render, centre, stop the timers (C-c u r)"
            (lambda (&rest _) (call-interactively #'cerebro-study-read)))
           ("" "New issue" "File an issue (C-c d I)"
            (lambda (&rest _) (call-interactively #'cerebro-issue-new)))
           ("" "Lint" "Note consistency checks (C-c d l)"
            (lambda (&rest _) (cerebro-lint))))))
)

;; -- Motion on the start page -------------------------------------------
;; emacs-dashboard binds `j' and `k' to move down and up -- vim's motion
;; keys, in an Emacs buffer where `n'/`p' and the arrows already do it.
;; They are switched off here.
;;
;; Not only as a preference: the section *shortcuts* live in the same
;; keymap, so a section whose shortcut was `k' and dashboard's `k' =
;; previous-line were the same key, and which one you got depended on
;; load order. The shortcuts above were moved off every motion letter
;; (`n p j k f b') for the same reason -- `w' work, `i' issues, `r'
;; recent, `u' unproved, `s' seeds -- so nothing on this page is
;; ambiguous.
;;
;; Done in a *buffer-local* map rather than by editing
;; `dashboard-mode-map': the section shortcuts are installed into that
;; map at render time, so anything unbound there could be quietly put
;; back. A buffer-local binding wins over the mode map whatever the
;; package does afterwards.

(defcustom cerebro-dashboard-disable-vim-motion t
  "Whether to switch off `j'/`k' as up/down on the start page.
`n'/`p' and the arrow keys keep working; this only removes the second,
vim-flavoured way to do the same thing."
  :type 'boolean
  :group 'cerebro)

(defun cerebro-dashboard--disable-vim-motion ()
  "Make `j' and `k' do nothing in this dashboard buffer."
  (when cerebro-dashboard-disable-vim-motion
    (let ((map (make-sparse-keymap)))
      (set-keymap-parent map (current-local-map))
      ;; `undefined', not nil: a nil binding in a child map falls through
      ;; to the parent, which is exactly what we are overriding. This
      ;; also gives an honest "j is undefined" rather than the read-only
      ;; complaint a fall-through to `self-insert-command' would produce.
      (define-key map (kbd "j") #'undefined)
      (define-key map (kbd "k") #'undefined)
      (use-local-map map))))

(add-hook 'dashboard-mode-hook #'cerebro-dashboard--disable-vim-motion)

(defun cerebro-dashboard--fallback ()
  "Render the same information without emacs-dashboard, and return the buffer.
Used outside the pinned environment: a start page that only works inside
Guix would be a start page that vanishes exactly when you most need to
be told why things are missing."
  (cerebro-report
   (format "%s -- %s" cerebro-dashboard-title (cerebro-dashboard-summary))
   (append (list (cerebro-dashboard-heading 'keys "To work:"))
           (mapcar (lambda (l) (concat "  " l)) (cerebro-dashboard-key-lines))
           (list "" (cerebro-dashboard-heading
                     'issues (format "Open issues (%s):" (cerebro-mode-active))))
           (mapcar (lambda (i) (concat "  " (cerebro-dashboard-issue-label i)))
                   (cerebro-dashboard-mode-issues 5))
           (list "" (cerebro-dashboard-heading 'recent "Recently changed notes:"))
           (mapcar (lambda (f) (concat "  " (cerebro-dashboard-note-label f)))
                   (cerebro-dashboard-recent-notes 8)))
   #'identity
   cerebro-dashboard-buffer)
  (get-buffer cerebro-dashboard-buffer))

;;;###autoload
(defun cerebro-dashboard ()
  "Open (or refresh) the cerebro start page.
Returns the buffer, so it can double as `initial-buffer-choice'."
  (interactive)
  (if (fboundp 'dashboard-open)
      (progn (dashboard-open) (get-buffer dashboard-buffer-name))
    (cerebro-dashboard--fallback)))

;; The start page is mode-dependent -- the issue list and the key panel
;; both are -- so a mode switch has to redraw it. Through
;; `cerebro-mode-hook' (the seam) rather than by naming the dashboard in
;; cerebro-mode.el, which must stay Org-free, and only when the page is
;; actually on screen: refreshing a buffer nobody is looking at would
;; re-scan the archive for nothing.
(defun cerebro-dashboard--on-mode-change (_mode)
  "Redraw the start page if it is displayed (see `cerebro-mode-hook')."
  (when-let* ((buffer (seq-find #'get-buffer-window
                                (delq nil (list (get-buffer cerebro-dashboard-buffer)
                                                (and (boundp 'dashboard-buffer-name)
                                                     (get-buffer dashboard-buffer-name)))))))
    (with-current-buffer buffer (cerebro-dashboard))))

(add-hook 'cerebro-mode-hook #'cerebro-dashboard--on-mode-change)

;; What a new frame opens onto. `initial-buffer-choice' (a function
;; returning a buffer) is the one hook that covers both launch paths this
;; project uses: `emacs --init-directory=...' from bin/emacs, and
;; `emacsclient -c' against the daemon (`cerebro' with a display).
;; dashboard's own `dashboard-setup-startup-hook' is NOT used: it only
;; arms itself when Emacs was started with no command-line arguments,
;; and every cerebro launcher passes --init-directory.
(setq initial-buffer-choice #'cerebro-dashboard)

(provide 'cerebro-dashboard)
