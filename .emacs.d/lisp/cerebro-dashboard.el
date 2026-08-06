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
(require 'cerebro-guix)    ;; environment headline + soft require
(require 'cerebro-issues)  ;; cerebro-issues-file
(require 'cerebro-results) ;; cerebro-results-scan (the census)
(require 'cerebro-cli)     ;; the commands behind the navigator buttons
(require 'cerebro-theme)   ;; whether a Nerd Font is actually installed

;; -- Data ---------------------------------------------------------------

(defun cerebro-dashboard-recent-notes (limit &optional dir)
  "The LIMIT most recently modified note files under DIR (default notes/).
Modification time, not visit history: `recentf' knows what *this* Emacs
opened, which after a `cerebro note new' from the shell, a git pull or a
fresh clone is the wrong answer -- the file system knows what actually
changed."
  (let ((files (cerebro-note-files dir)))
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
   (format "%d notes · %d results · %d open issues"
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

;; -- Renderer: emacs-dashboard when present ----------------------------

(defvar cerebro-dashboard-buffer "*cerebro-dashboard*"
  "Buffer used by the fallback renderer (see `cerebro-dashboard--fallback').
Deliberately not `cerebro-report's default *cerebro*: that one is the
shared, overwritten-on-every-query report buffer, and it is the one
cerebro-ui.el confines to a small side window -- a start page needs a
window of its own, and needs to survive the next `C-c q h'.")

;; -- The banner ---------------------------------------------------------
;; A start page you open every day should look like somewhere you want to
;; be, so the top of it is a picture: .emacs.d/banner.png, a ringed
;; planet in the same pastel range as the theme, on a transparent
;; background so it sits on the dark or the light variant equally.
;;
;; It is *drawn*, not downloaded: bin/cerebro-banner builds it from
;; thirty lines of ImageMagick, offline, and is committed next to it --
;; so the image in the tree is not a mystery binary, and changing the
;; palette or the geometry is editing a script and re-running it. Point
;; `cerebro-dashboard-banner' somewhere else for your own image.

(defcustom cerebro-dashboard-banner
  (expand-file-name ".emacs.d/banner.png" cerebro-root)
  "Image shown at the top of the start page (see bin/cerebro-banner)."
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
it -- in a terminal frame there is no image support at all, and
emacs-dashboard would fall back to its own ASCII logo. Pure enough to
test."
  (let ((file (or file cerebro-dashboard-banner)))
    (and (stringp file)
         (file-readable-p file)
         (image-type-available-p 'png)
         t)))

(when (cerebro-guix-soft-require 'dashboard)
  (setq dashboard-startup-banner
        (if (cerebro-dashboard-banner-usable-p)
            cerebro-dashboard-banner
          ;; No image support (a terminal frame): dashboard's own text
          ;; logo, rather than a broken-image placeholder.
          'ascii)
        dashboard-image-banner-max-height cerebro-dashboard-banner-height
        dashboard-banner-ascii "cerebro"
        dashboard-banner-logo-title "cerebro · a second brain for pure mathematics"
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

  (defun cerebro-dashboard--insert-issues (list-size)
    "Dashboard section: the most urgent open issues."
    (dashboard-insert-section
     "Open issues:"
     (cerebro-dashboard-open-issues list-size)
     list-size
     'cerebro-issues
     "i"
     `(lambda (&rest _) (cerebro-dashboard-visit-issue ,(plist-get el :id)))
     (cerebro-dashboard-issue-label el)))

  (defun cerebro-dashboard--insert-notes (list-size)
    "Dashboard section: the notes that changed most recently."
    (dashboard-insert-section
     "Recently changed notes:"
     (cerebro-dashboard-recent-notes list-size)
     list-size
     'cerebro-notes
     "n"
     `(lambda (&rest _) (find-file-existing ,el))
     (cerebro-dashboard-note-label el)))

  (dolist (gen '((cerebro-issues . cerebro-dashboard--insert-issues)
                 (cerebro-notes  . cerebro-dashboard--insert-notes)))
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
          '((cerebro-issues . "nf-oct-issue_opened")
            (cerebro-notes  . "nf-oct-note")
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
  (setq dashboard-items '((cerebro-issues . 5)
                          (cerebro-notes  . 8)))

  ;; One row of buttons for the operations that start a session. Each is
  ;; an existing command -- no logic lives in the dashboard itself.
  ;; Quoted, not backquoted: dashboard funcalls each entry's action as a
  ;; plain list, and nothing here needs to close over a local.
  (setq dashboard-navigator-buttons
        '((("" "Morning review" "Today's agenda (C-c a m)"
            (lambda (&rest _) (org-agenda nil "m")))
           ("" "Find note" "Org-roam node find (C-c n f)"
            (lambda (&rest _) (call-interactively
                               (if (fboundp 'org-roam-node-find)
                                   #'org-roam-node-find #'cerebro-note-find))))
           ("" "New note" "Create a classified note (C-c d n)"
            (lambda (&rest _) (call-interactively #'cerebro-note-new)))
           ("" "New issue" "File an issue (C-c d I)"
            (lambda (&rest _) (call-interactively #'cerebro-issue-new)))
           ("" "Lint" "Note consistency checks (C-c d l)"
            (lambda (&rest _) (cerebro-lint)))
           ("" "Environment" "Guix profile, pin and packages (C-c G s)"
            (lambda (&rest _) (cerebro-guix-status)))
           ("" "Graph" "Draw the note graph (C-c q g)"
            (lambda (&rest _) (call-interactively #'cerebro-graph-view))))))
)

(defun cerebro-dashboard--fallback ()
  "Render the same information without emacs-dashboard, and return the buffer.
Used outside the pinned environment: a start page that only works inside
Guix would be a start page that vanishes exactly when you most need to
be told why things are missing."
  (cerebro-report
   (format "cerebro -- %s" (cerebro-dashboard-summary))
   (append '("Open issues:")
           (mapcar (lambda (i) (concat "  " (cerebro-dashboard-issue-label i)))
                   (cerebro-dashboard-open-issues 5))
           '("" "Recently changed notes:")
           (mapcar (lambda (f) (concat "  " (cerebro-dashboard-note-label f)))
                   (cerebro-dashboard-recent-notes 8))
           '("" "C-c h dashboard · C-c t tree · C-c a agenda · C-c G s environment"))
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

;; What a new frame opens onto. `initial-buffer-choice' (a function
;; returning a buffer) is the one hook that covers both launch paths this
;; project uses: `emacs --init-directory=...' from bin/emacs, and
;; `emacsclient -c' against the daemon (`cerebro' with a display).
;; dashboard's own `dashboard-setup-startup-hook' is NOT used: it only
;; arms itself when Emacs was started with no command-line arguments,
;; and every cerebro launcher passes --init-directory.
(setq initial-buffer-choice #'cerebro-dashboard)

(provide 'cerebro-dashboard)
