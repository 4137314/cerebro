;;; cerebro-ql.el --- content/metadata queries and saved views -*- lexical-binding: t; -*-

;; emacs-org-ql, from guix.scm -- not available outside the guix
;; environment (no MELPA/straight.el fallback, on purpose, as with
;; org-roam). This is the *second* query surface, complementary to
;; cerebro-query.el, and the two are deliberately different tools:
;;
;;   cerebro-query.el (org-roam DB)  -- graph STRUCTURE: backlinks, hubs,
;;       orphans, co-citation. "How is the corpus wired together."
;;   cerebro-ql.el (org-ql)          -- CONTENT and METADATA: tags, TODO
;;       state, timestamps, properties, across every note. "Which entries
;;       match these criteria right now."
;;
;; The saved views below are data (`org-ql-views' entries): adding one is
;; a single alist line, browsed with `org-ql-view' (C-c v v). No
;; org-super-agenda dependency is used, so nothing here needs a Guix
;; package beyond org-ql itself.

(require 'cerebro-org)
(require 'cerebro-taxonomy)
(require 'org-ql)
(require 'org-ql-search)
(require 'org-ql-view)

(defun cerebro-ql-files ()
  "The search surface for org-ql: every real note (recursively, via the
shared `cerebro-note-files', so notes/courses/*/ is included) plus the
issue tracker. Sharing `cerebro-note-files' with the agenda's directory
list (cerebro-org.el) is deliberate: the two query surfaces are then
provably scanning the same corpus, never one recursive and one not."
  (append (cerebro-note-files)
          (let ((issues (expand-file-name "issues/issues.org" cerebro-root)))
            (and (file-exists-p issues) (list issues)))))

;; Curated, cerebro-specific saved views. `org-ql-view' (C-c v v) lists
;; them; each is one (NAME . PLIST) entry -- add a view by adding a line.
(setq org-ql-views
      (list
       (cons "Cerebro: seeds & growing (to mature)"
             (list :buffers-files #'cerebro-ql-files
                   :query '(or (tags "seed") (tags "growing"))
                   :title "Seeds & growing"
                   :sort '(date)))
       (cons "Cerebro: drill cards"
             (list :buffers-files #'cerebro-ql-files
                   :query '(tags "drill")
                   :title "Drill cards"))
       (cons "Cerebro: conjectures & open problems"
             (list :buffers-files #'cerebro-ql-files
                   :query '(or (tags "conjecture") (tags "folklore") (tags "open_problem"))
                   :title "Conjectures & open problems"))
       (cons "Cerebro: hard notes"
             (list :buffers-files #'cerebro-ql-files
                   :query '(tags "hard")
                   :title "Hard notes"))
       (cons "Cerebro: active work (TODO/DOING)"
             (list :buffers-files #'org-agenda-files
                   :query '(todo "TODO" "DOING")
                   :title "Active work"
                   :sort '(todo priority)))
       (cons "Cerebro: touched in the last 14 days"
             (list :buffers-files #'cerebro-ql-files
                   :query '(ts :from -14)
                   :title "Recently touched"
                   :sort '(date)))))

;;;###autoload
(defun cerebro-ql-area (supertag)
  "Show every entry in area SUPERTAG. The area is expanded to its whole
tag family (`cerebro-taxonomy-family'), because org-ql matches literal
tags -- so querying `analysis' also catches `functional_analysis' etc.,
matching the group-tag behaviour the agenda gets for free."
  (interactive (list (completing-read "Area: " (cerebro-taxonomy-supertags) nil t)))
  (let ((family (cerebro-taxonomy-family supertag)))
    (unless family (error "cerebro-ql: `%s' is not an area supertag" supertag))
    (org-ql-search (cerebro-ql-files)
      `(tags ,@family)
      :title (format "Area: %s" supertag)
      :sort '(date))))
;; (MSC classification is a file-level keyword, not a heading property,
;; so "which notes are unclassified" is answered by bin/cerebro-lint's
;; advisory nudge and `make query Q=by-msc', not by org-ql here.)

(provide 'cerebro-ql)
