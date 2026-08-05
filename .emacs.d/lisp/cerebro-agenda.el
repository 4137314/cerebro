;;; cerebro-agenda.el --- agenda views (morning review, issues) -*- lexical-binding: t; -*-

;; The custom agenda commands, factored out of cerebro-org.el's base setup
;; into their own module. Data, not code: each view is an
;; `org-agenda-custom-commands' entry, and every block restricts
;; `org-agenda-files' to just what it needs rather than inventing a tag to
;; filter by. Bound to `C-c a' (see cerebro-keys.el); the same views are
;; reachable from the shell via the `cerebro' CLI (issue report / stats).

(require 'cerebro-org) ;; cerebro-root, cerebro-note-directories, org-agenda-files

;; `alltodo' (not `todo "TODO"') for issues, so an issue you have already
;; started -- state DOING -- still shows as open; `todo "TODO"' would
;; silently drop it. The generated Taskwarrior file only ever has
;; TODO/DONE, so `todo "TODO"' is exact there.
(setq org-agenda-custom-commands
      `(("m" "Morning review"
         ((agenda "" ((org-agenda-span 1)))
          (todo "TODO"
                ((org-agenda-overriding-header "Academic tasks (Taskwarrior, via bin/task-to-org)")
                 (org-agenda-files
                  (list (expand-file-name "agenda/taskwarrior.org" cerebro-root)))))
          (alltodo ""
                   ((org-agenda-overriding-header "Open issues")
                    (org-agenda-files (list (expand-file-name "issues/issues.org" cerebro-root)))))
          (tags "growing"
                ((org-agenda-overriding-header "Growing notes -- candidates to push toward evergreen")
                 (org-agenda-files (cerebro-note-directories))))
          (tags "seed"
                ((org-agenda-overriding-header "Seed notes -- still need a first real pass")
                 (org-agenda-files (cerebro-note-directories))))))
        ;; A focused, standalone issue tracker view (C-c a i): every open
        ;; issue (TODO and DOING), highest priority first. Complements the
        ;; morning review's one issue block and `C-c i' (open the file).
        ("i" "Open issues (by priority)"
         ((alltodo ""
                   ((org-agenda-overriding-header "Open issues -- issues/issues.org")
                    (org-agenda-files (list (expand-file-name "issues/issues.org" cerebro-root)))
                    (org-agenda-sorting-strategy '(priority-down timestamp-up))))))))

(provide 'cerebro-agenda)
