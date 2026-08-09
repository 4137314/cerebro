;;; cerebro-dashboard-tests.el --- ERT tests for the start page's data -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-dashboard-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; The dashboard is split into pure data functions and a renderer exactly
;; so the data can be tested without emacs-dashboard (or Guix) present --
;; these tests run against the fallback path too. Two claims are worth
;; pinning down, because a regression in either would be silent and
;; misleading rather than loud:
;;
;;   1. "recently changed" means file mtime, so a note created by the
;;      shell CLI or pulled from git shows up, not just what this Emacs
;;      happened to visit;
;;   2. the issue ordering matches the agenda's (priority first, then
;;      DOING before TODO, unprioritised issues ranked at
;;      `org-default-priority') -- a start page that disagrees with
;;      `C-c a i' about what is urgent is worse than none.

(require 'ert)
(require 'cerebro-dashboard)

(defmacro cerebro-dashboard-tests--with-notes (&rest body)
  "Bind `dir' to a throwaway notes tree with known, distinct mtimes:
old.org (oldest), mid.org, new.org (newest), plus README.org which is meta
and must never be listed as a note."
  (declare (indent 0) (debug t))
  `(let ((dir (make-temp-file "cerebro-dash-notes-" t)))
     (unwind-protect
         (progn
           (dolist (spec '(("old.org" . 100) ("mid.org" . 200)
                           ("new.org" . 300) ("README.org" . 400)))
             (let ((f (expand-file-name (car spec) dir)))
               (with-temp-file f (insert "* x\n"))
               ;; Explicit mtimes: writing three files in the same
               ;; hundredth of a second would otherwise make the order
               ;; nondeterministic.
               (set-file-times f (time-convert (cdr spec) nil))))
           ,@body)
       (delete-directory dir t))))

(defmacro cerebro-dashboard-tests--with-issues (&rest body)
  "Bind `file' to a throwaway issue tracker with a known priority mix."
  (declare (indent 0) (debug t))
  `(let ((file (make-temp-file "cerebro-dash-issues-" nil ".org")))
     (unwind-protect
         (progn
           (with-temp-file file
             (insert "* TODO [#C] low priority\n:PROPERTIES:\n:ID: id-c\n:END:\n"
                     "* DONE [#A] already closed\n:PROPERTIES:\n:ID: id-done\n:END:\n"
                     "* TODO [#A] urgent todo :latex:\n:PROPERTIES:\n:ID: id-a\n:END:\n"
                     "* DOING [#A] urgent doing\n:PROPERTIES:\n:ID: id-a2\n:END:\n"
                     "* TODO unprioritised\n:PROPERTIES:\n:ID: id-none\n:END:\n"))
           (unwind-protect (progn ,@body)
             (let ((buf (find-buffer-visiting file)))
               (when buf (kill-buffer buf)))))
       (delete-file file))))

;; -- Recently changed notes --------------------------------------------

(ert-deftest cerebro-dashboard-test-recent-notes-are-mtime-ordered ()
  "Newest first, by file mtime -- not by visit history."
  (cerebro-dashboard-tests--with-notes
    (should (equal (mapcar #'file-name-nondirectory
                           (cerebro-dashboard-recent-notes 10 dir))
                   '("new.org" "mid.org" "old.org")))))

(ert-deftest cerebro-dashboard-test-recent-notes-excludes-meta-files ()
  "README.org is the manual, not a note: it must not appear even though
it is the most recently touched file in the tree."
  (cerebro-dashboard-tests--with-notes
    (should-not (member "README.org"
                        (mapcar #'file-name-nondirectory
                                (cerebro-dashboard-recent-notes 10 dir))))))

(ert-deftest cerebro-dashboard-test-recent-notes-respects-limit ()
  (cerebro-dashboard-tests--with-notes
    (should (equal (length (cerebro-dashboard-recent-notes 2 dir)) 2))))

(ert-deftest cerebro-dashboard-test-recent-notes-leaves-the-memo-alone ()
  "Drawing the start page must not rewrite the archive's cached listing.

`cerebro-note-files' hands back the list that IS the memo
\(cerebro-cache.el) and `sort' is destructive, so sorting it by mtime
here reordered the cache for every later caller in the session. On this
Emacs that is only a reordering -- Emacs 30's `sort' reuses the cons
cells and moves the values -- but on the relinking `sort' of Emacs 29
and earlier the cached head lands partway down the sorted list and
`cerebro-note-files' starts answering with a truncated archive: fewer
notes in the census, the results graph, the linter and every query.

Both properties are asserted, because only one of them fails loudly."
  (cerebro-dashboard-tests--with-notes
    (let* ((before (cerebro-note-files dir))
           (snapshot (copy-sequence before)))
      (cerebro-dashboard-recent-notes 10 dir)
      (let ((after (cerebro-note-files dir)))
        (should (= (length after) (length snapshot)))
        (should (equal after snapshot))))))

;; -- Open issues -------------------------------------------------------

(ert-deftest cerebro-dashboard-test-open-issues-excludes-done ()
  "Open means TODO or DOING; a closed issue is gone from the start page."
  (cerebro-dashboard-tests--with-issues
    (let ((ids (mapcar (lambda (i) (plist-get i :id))
                       (cerebro-dashboard-open-issues 10 file))))
      (should-not (member "id-done" ids))
      (should (equal (length ids) 4)))))

(ert-deftest cerebro-dashboard-test-open-issues-ordering ()
  "Priority first, then DOING before TODO at equal priority, and an
unprioritised issue ranks at `org-default-priority' (B) -- i.e. above
[#C], below [#A], exactly as the agenda sorts it."
  (cerebro-dashboard-tests--with-issues
    (should (equal (mapcar (lambda (i) (plist-get i :id))
                           (cerebro-dashboard-open-issues 10 file))
                   '("id-a2" "id-a" "id-none" "id-c")))))

(ert-deftest cerebro-dashboard-test-open-issues-respects-limit ()
  (cerebro-dashboard-tests--with-issues
    (should (equal (length (cerebro-dashboard-open-issues 2 file)) 2))))

(ert-deftest cerebro-dashboard-test-open-issues-missing-file ()
  "No tracker (a fresh clone before the first issue) is empty, not an error."
  (should-not (cerebro-dashboard-open-issues 5 "/nonexistent/issues.org")))

(ert-deftest cerebro-dashboard-test-mode-issues-hide-only-the-other-job ()
  "The start page lists this mode's work, and the census still counts all
of it: `cerebro-dashboard-open-issues' is what is open, this is what is
open *for me today* (cerebro-mode.el).

The fixture's only classified issue is tagged `:latex:', which is
machinery -- so it goes in dev and not in math, and every untagged issue
stays in both. Nothing is filtered into invisibility."
  (cerebro-dashboard-tests--with-issues
    (let ((in-math (mapcar (lambda (i) (plist-get i :id))
                           (cerebro-dashboard-mode-issues 10 file 'math)))
          (in-dev (mapcar (lambda (i) (plist-get i :id))
                          (cerebro-dashboard-mode-issues 10 file 'dev))))
      (should-not (member "id-a" in-math))
      (should (member "id-a" in-dev))
      (dolist (id '("id-a2" "id-none" "id-c"))
        (should (member id in-math))
        (should (member id in-dev)))
      ;; The count under the banner is not the filtered one.
      (should (= (length (cerebro-dashboard-open-issues 10 file)) 4)))))

(ert-deftest cerebro-dashboard-test-issue-label-shows-state-and-priority ()
  (cerebro-dashboard-tests--with-issues
    (let ((label (cerebro-dashboard-issue-label
                  (car (cerebro-dashboard-open-issues 1 file)))))
      (should (string-match-p "DOING" label))
      (should (string-match-p "\\[#A\\]" label))
      (should (string-match-p "urgent doing" label)))))

;; -- The renderer ------------------------------------------------------

(ert-deftest cerebro-dashboard-test-fallback-renders-without-package ()
  "The fallback start page builds a real buffer with no emacs-dashboard
-- the degraded, outside-guix path has to work, since that is when you
most need to be told what is missing."
  (let ((buf (cerebro-dashboard--fallback)))
    (should (bufferp buf))
    (unwind-protect
        (with-current-buffer buf
          ;; The issue heading names the mode it is filtered by: a list
          ;; that shows a subset without saying so is a list you mistake
          ;; for the whole backlog (cerebro-mode.el).
          (should (string-match-p (format "Open issues (%s):" (cerebro-mode-active))
                                  (buffer-string)))
          (should (string-match-p "Recently changed notes:" (buffer-string))))
      (kill-buffer buf))))

;; -- The hermetic surface ----------------------------------------------

(ert-deftest cerebro-dashboard-test-title-is-the-name-in-greek ()
  "The page is titled with the name, in Greek, and nothing else.
The explanatory sentence that used to sit under the banner is gone on
purpose: it described the archive to someone who is not the person
opening it."
  (should (equal cerebro-dashboard-title "κέρεβρο"))
  (should (string-match-p "\\`[[:nonascii:]]+\\'" cerebro-dashboard-title))
  ;; No prose, no separator, no tagline -- one word.
  (should-not (string-match-p "[ ·]" cerebro-dashboard-title)))

(ert-deftest cerebro-dashboard-test-title-face-is-a-face-not-a-colour ()
  "Blue by inheriting `link', so it stays blue after `C-c u t'.
A literal hex is a colour chosen for one variant and wrong in the other
-- the same argument cerebro-appearance.el makes for hl-todo."
  (should (facep 'cerebro-dashboard-title-face))
  (let ((spec (face-attribute 'cerebro-dashboard-title-face :inherit nil t)))
    (should (memq 'link (if (listp spec) spec (list spec))))))

(ert-deftest cerebro-dashboard-test-every-sign-has-an-ascii-fallback ()
  "A glyph the font lacks draws an empty box, which is worse than a dash.
Every section therefore declares a plain-ASCII marker as well, and
`cerebro-dashboard-sign' returns one or the other -- never nothing."
  (dolist (row cerebro-dashboard-signs)
    (should (= (length row) 3))
    (should (stringp (nth 1 row)))
    (should (stringp (nth 2 row)))
    (should (string-match-p "\\`[[:ascii:]]+\\'" (nth 2 row))))
  (dolist (section (mapcar #'car cerebro-dashboard-signs))
    (should (> (length (cerebro-dashboard-sign section)) 0)))
  ;; An unknown section is empty, not an error: the heading still renders.
  (should (equal (cerebro-dashboard-sign 'no-such-section) "")))

(ert-deftest cerebro-dashboard-test-key-lines-fit-the-layout ()
  "dashboard centres by padding to the widest line, so one long line
moves the whole page sideways and then wraps. Every key row must fit --
in both modes, since each may bring its own rows (cerebro-mode.el)."
  (dolist (mode (cerebro-mode-names))
    (dolist (line (cerebro-dashboard-key-lines mode))
      (should (<= (string-width line) cerebro-dashboard-label-width))
      ;; ...and must not have *been* truncated to fit: an ellipsis in the
      ;; middle of a key reminder is the one thing this section cannot do.
      (should-not (string-match-p "…" line)))))

(ert-deftest cerebro-dashboard-test-advertised-keys-are-really-bound ()
  "Every key the start page advertises must actually do something.

A start page that lists a key nobody bound is worse than one that lists
nothing: it is checked once, believed, and then quietly wrong.

Two things make the check less obvious than it looks.

Keys like `C-c a m' are a *prefix command* plus a character the command
reads itself (org-agenda's dispatcher), so a binding is looked for on
progressively shorter prefixes.

And the question is whether the key is *bound*, not whether the command
is currently `commandp': cerebro-keys.el binds command symbols from
optional modules deliberately (\"it only references command symbols, so
binding a key to a command from an optional module that didn't load is
harmless\"), and in batch org-roam, cerebro-pdf and cerebro-course are
not loaded. Asking `commandp' here would fail on four keys that are
perfectly well bound in a real session -- it would be testing this
subprocess, not the configuration."
  (require 'cerebro-keys)
  (dolist (row (append cerebro-dashboard-key-rows
                       ;; ...and the rows each mode brings of its own, so
                       ;; a key advertised only in dev is checked too.
                       (apply #'append
                              (mapcar #'cerebro-dashboard-mode-key-rows
                                      (cerebro-mode-names)))))
    (dolist (cell (cdr row))
      (let* ((key (car cell))
             (parts (split-string key " " t))
             (binding nil))
        (while (and parts (not binding))
          (let ((found (key-binding (kbd (string-join parts " ")))))
            (when (and found (not (eq found 'undefined)))
              (setq binding found)))
          (setq parts (butlast parts)))
        (should binding)
        ;; A symbol, i.e. a command name -- not a stray keymap left over
        ;; from a prefix that never got a binding of its own.
        (should (symbolp binding))))))

(ert-deftest cerebro-dashboard-test-section-shortcuts-avoid-motion-keys ()
  "No section shortcut may be a key the dashboard also moves with.

The shortcuts and emacs-dashboard's own motion live in the same keymap,
so a section whose shortcut was `k' and `k' = previous-line were one
key, and which behaviour you got depended on load order. `n p j k f b'
are all motion; the shortcuts stay off them."
  (let ((motion '("n" "p" "j" "k" "f" "b"))
        (shortcuts nil))
    (with-temp-buffer
      (insert-file-contents
       (expand-file-name ".emacs.d/lisp/cerebro-dashboard.el" cerebro-root))
      (goto-char (point-min))
      ;; The shortcut is the bare one-letter string argument each
      ;; `dashboard-insert-section' call passes on its own line.
      (while (re-search-forward "^     \"\\([a-z]\\)\"$" nil t)
        (push (match-string 1) shortcuts)))
    (should shortcuts)
    (dolist (shortcut shortcuts)
      (should-not (member shortcut motion)))
    ;; ...and each section has its own.
    (should (equal shortcuts (delete-dups (copy-sequence shortcuts))))))

(ert-deftest cerebro-dashboard-test-vim-motion-is-switched-off ()
  "`j'/`k' do not move on the start page; `n'/`p' and the arrows do.

Installed into a *buffer-local* map, because the section shortcuts are
written into `dashboard-mode-map' at render time -- anything unbound
there could be put back without warning."
  (should (memq #'cerebro-dashboard--disable-vim-motion dashboard-mode-hook))
  (with-temp-buffer
    (use-local-map (make-sparse-keymap))
    ;; Stand in for dashboard's own binding, then run the hook function.
    (define-key (current-local-map) (kbd "j") #'next-line)
    (define-key (current-local-map) (kbd "k") #'previous-line)
    (cerebro-dashboard--disable-vim-motion)
    (should (eq (key-binding (kbd "j")) #'undefined))
    (should (eq (key-binding (kbd "k")) #'undefined))))

(ert-deftest cerebro-dashboard-test-banner-is-a-committed-image ()
  "The start page's art is a real image file, versioned in the repo.
Nothing here fetches anything: the picture is in the tree, next to the
config that points at it. The format is deliberately not asserted --
that was the bug this test used to encode."
  (should (file-readable-p cerebro-dashboard-banner))
  (should (image-type cerebro-dashboard-banner nil nil))
  ;; The generator stays available for a drawn banner instead of a
  ;; supplied one (`bin/cerebro-banner' writes .emacs.d/banner.png).
  (should (file-readable-p (expand-file-name "bin/cerebro-banner" cerebro-root))))

(ert-deftest cerebro-dashboard-test-banner-needs-support-for-its-own-type ()
  "A banner is used only when this Emacs can decode *that* image.
The check used to ask about PNG, which was right only for as long as the
banner happened to be one: a JPEG banner on an Emacs built without JPEG
would have passed and then drawn a placeholder where the picture should
be. On a terminal frame there is no image support at all, and the start
page falls back to its ASCII logo."
  (should (eq (cerebro-dashboard-banner-usable-p)
              (and (image-type-available-p
                    (image-type cerebro-dashboard-banner nil nil))
                   t)))
  (should-not (cerebro-dashboard-banner-usable-p "/nonexistent/banner.png"))
  ;; A readable file that is not an image at all must not pass.
  (should-not (cerebro-dashboard-banner-usable-p
               (expand-file-name "README.org" cerebro-root))))

(ert-deftest cerebro-dashboard-test-labels-are-truncated ()
  "No line on the start page is wider than the page allows.
dashboard centres a section by padding to its widest line, so one long
issue title shifts the whole block and then wraps it -- the page looks
broken rather than merely long. Short titles are left alone."
  (should (<= (string-width (cerebro-dashboard-truncate (make-string 200 ?x)))
              cerebro-dashboard-label-width))
  (should (equal (cerebro-dashboard-truncate "short") "short")))

;;; cerebro-dashboard-tests.el ends here
