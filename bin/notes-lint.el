;;; notes-lint.el --- consistency checks for cerebro notes -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/notes-lint.el -- [file.org ...]
;; (default, no args: every .org file under notes/)
;;
;; Two tiers, matching how the rest of the tooling degrades, plus a
;; separate advisory-only spelling pass:
;; - Tier 1 (pure org-element, always runs): duplicate #+NAME labels
;;   (would silently break LaTeX compilation), a
;;   theorem/lemma/proposition/corollary block with no adjacent proof
;;   block *and* no conjecture/folklore/open_problem tag on its
;;   nearest enclosing heading, headings using tags not declared in
;;   org-tag-alist (see notes/TAGS.org).
;; - Tier 2 (needs the Org-roam DB, skipped with a message if
;;   unavailable): broken id: links, fully orphaned nodes
;;   (informational only -- normal for a fresh `seed' note, not an
;;   error).
;; - Spelling (needs aspell/hunspell on PATH, skipped with a message if
;;   neither is found): always informational, never fails the push --
;;   prose spell-checkers have false positives (proper nouns, jargon,
;;   the occasional stray bit of math notation) often enough that
;;   treating them as hard errors would just get the check ignored.

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (lisp-dir (expand-file-name "../.emacs.d/lisp" here)))
  (add-to-list 'load-path lisp-dir))
(require 'cl-lib)
(require 'org)
(require 'org-element)
(require 'flyspell)
(require 'cerebro-org)
(require 'cerebro-msc) ;; validate #+MSC: codes against MSC2020

(defvar cerebro-lint--errors nil)
(defvar cerebro-lint--info nil)

(defun cerebro-lint--err (fmt &rest args)
  (push (apply #'format fmt args) cerebro-lint--errors))
(defun cerebro-lint--note (fmt &rest args)
  (push (apply #'format fmt args) cerebro-lint--info))

(defun cerebro-lint--nearest-heading-tags (element)
  "Tags of the nearest enclosing headline of ELEMENT, or nil if none."
  (let ((el (org-element-property :parent element)))
    (while (and el (not (eq (org-element-type el) 'headline)))
      (setq el (org-element-property :parent el)))
    (when el (org-element-property :tags el))))

(defun cerebro-lint--tier1-file (file)
  (with-temp-buffer
    (insert-file-contents file)
    (org-mode)
    (let ((tree (org-element-parse-buffer))
          (seen-names (make-hash-table :test 'equal))
          (known-tags (cerebro-known-tags)))
      (org-element-map tree t
        (lambda (el)
          (let ((name (org-element-property :name el)))
            (when name
              (if (gethash name seen-names)
                  (cerebro-lint--err "%s: duplicate #+NAME `%s'" file name)
                (puthash name t seen-names))))))
      (org-element-map tree 'special-block
        (lambda (block)
          (let ((type (downcase (or (org-element-property :type block) ""))))
            (when (member type '("theorem" "lemma" "proposition" "corollary"))
              (let* ((parent (org-element-property :parent block))
                     (siblings (org-element-contents parent))
                     (idx (cl-position block siblings))
                     (next (nth (1+ idx) siblings))
                     (has-proof (and next
                                      (eq (org-element-type next) 'special-block)
                                      (equal (downcase (or (org-element-property :type next) ""))
                                             "proof")))
                     (exempt (cl-intersection
                              (cerebro-lint--nearest-heading-tags block)
                              '("conjecture" "folklore" "open_problem")
                              :test #'equal)))
                (unless (or has-proof exempt)
                  (cerebro-lint--err
                   "%s: %s `%s' has no adjacent proof block (tag its heading conjecture/folklore/open_problem if that's intentional)"
                   file type (or (org-element-property :name block) "(unnamed)"))))))))
      (org-element-map tree 'headline
        (lambda (h)
          (dolist (tag (org-element-property :tags h))
            (unless (member tag known-tags)
              (cerebro-lint--err "%s: heading `%s' uses undeclared tag `%s' (see notes/TAGS.org)"
                                  file (org-element-property :raw-value h) tag)))))
      ;; MSC2020 classification (cerebro-msc.el): every code in a #+MSC:
      ;; line must be well-formed and name a real top-level class -- a
      ;; typo'd code silently mis-files a note and breaks \subjclass on a
      ;; paper export. Advisory-only nudge: an evergreen note with no MSC
      ;; at all is worth classifying, but not an error.
      (let* ((msc-values (org-element-map tree 'keyword
                           (lambda (k) (and (equal (org-element-property :key k) "MSC")
                                            (org-element-property :value k)))))
             (filetags (org-element-map tree 'keyword
                         (lambda (k) (and (equal (org-element-property :key k) "FILETAGS")
                                          (org-element-property :value k)))
                         nil t))
             (codes (apply #'append (mapcar #'cerebro-msc-parse msc-values))))
        (dolist (bad (cerebro-msc-invalid codes))
          (cerebro-lint--err "%s: invalid MSC code `%s' (not MSC2020 -- see notes/TAGS.org)"
                              file bad))
        (when (and filetags (string-match-p ":evergreen:" filetags) (null codes))
          (cerebro-lint--note "%s: evergreen note has no #+MSC: classification" file))))))

(defvar cerebro-lint--ispell-program
  (or (executable-find "aspell") (executable-find "hunspell"))
  "Which spell-checker backend to use, if any. aspell (from guix.scm)
is preferred; hunspell is an acceptable fallback if that's what's on
PATH (e.g. testing outside the guix environment).")

(defun cerebro-lint--prose-only (file)
  "Best-effort prose extraction from FILE for spell-checking: drops
#+begin_.../#+end_... blocks and #+KEYWORD: lines, leaving running
text. Not a full Org parser -- e.g. inline $math$ isn't specially
stripped -- which is exactly why the spelling check this feeds is
informational only, never a hard failure."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((lines (split-string (buffer-string) "\n"))
          (in-block nil)
          kept)
      (dolist (line lines)
        (cond
         (in-block (when (string-match-p "\\`[ \t]*#\\+end_" line) (setq in-block nil)))
         ((string-match-p "\\`[ \t]*#\\+begin_" line) (setq in-block t))
         ((string-match-p "\\`[ \t]*#\\+[[:alpha:]_]+:" line)) ;; drop keyword lines
         (t (push line kept))))
      (mapconcat #'identity (nreverse kept) "\n"))))

(defun cerebro-lint--spelling-file (file)
  (when cerebro-lint--ispell-program
    (with-temp-buffer
      (insert (cerebro-lint--prose-only file))
      (text-mode)
      (let ((ispell-program-name cerebro-lint--ispell-program)
            (ispell-dictionary "en_US"))
        (condition-case err
            (progn
              (ispell-set-spellchecker-params)
              (flyspell-mode 1)
              (flyspell-buffer)
              (let (words)
                (dolist (ov (overlays-in (point-min) (point-max)))
                  (when (overlay-get ov 'flyspell-overlay)
                    (push (buffer-substring-no-properties (overlay-start ov) (overlay-end ov))
                          words)))
                (dolist (w (delete-dups words))
                  (cerebro-lint--note "%s: possible misspelling `%s'" file w))))
          (error
           (message "notes-lint: spelling check unavailable (%s)"
                     (error-message-string err))))))))

(defun cerebro-lint--tier2 ()
  (if (not (require 'org-roam nil t))
      (message "notes-lint: org-roam unavailable, skipping tier-2 graph checks")
    (if (not (and (boundp 'org-roam-db-location)
                  org-roam-db-location
                  (file-exists-p org-roam-db-location)))
        (message "notes-lint: no Org-roam database yet, skipping tier-2 graph checks")
      ;; Refresh the cache first: pre-push runs this from the CLI, where
      ;; no autosync Emacs is keeping it current, so broken-link / orphan
      ;; checks would otherwise run against a possibly stale DB. Best
      ;; effort -- fall back to the existing DB if the sync errors.
      (condition-case err
          (org-roam-db-sync)
        (error (message "notes-lint: org-roam-db-sync failed (%s), checking existing DB"
                        (error-message-string err))))
      (let* ((nodes (org-roam-db-query [:select [id title] :from nodes]))
             (titles (let ((h (make-hash-table :test 'equal)))
                       (dolist (n nodes) (puthash (nth 0 n) (nth 1 n) h))
                       h))
             (links (org-roam-db-query [:select [source dest] :from links :where (= type "id")]))
             (connected (make-hash-table :test 'equal)))
        (dolist (l links)
          (unless (gethash (nth 1 l) titles)
            (cerebro-lint--err "broken link: `%s' -> missing target %s"
                                (gethash (nth 0 l) titles) (nth 1 l)))
          (puthash (nth 0 l) t connected)
          (puthash (nth 1 l) t connected))
        (dolist (n nodes)
          (unless (gethash (nth 0 n) connected)
            (cerebro-lint--note "orphan (no links in or out): %s" (nth 1 n))))))))

(let ((files (delete "--" (copy-sequence command-line-args-left))))
  (unless files
    (setq files (directory-files-recursively
                 (expand-file-name "notes" cerebro-root) "\\.org\\'")))
  (dolist (f files) (cerebro-lint--tier1-file f))
  (if cerebro-lint--ispell-program
      (dolist (f files) (cerebro-lint--spelling-file f))
    (message "notes-lint: no aspell/hunspell on PATH, skipping the spelling pass")))
(cerebro-lint--tier2)

(dolist (i (reverse cerebro-lint--info)) (message "notes-lint: info: %s" i))
(dolist (e (reverse cerebro-lint--errors)) (message "notes-lint: ERROR: %s" e))
(if cerebro-lint--errors
    (progn (message "notes-lint: %d error(s)" (length cerebro-lint--errors)) (kill-emacs 1))
  (message "notes-lint: ok")
  (kill-emacs 0))
