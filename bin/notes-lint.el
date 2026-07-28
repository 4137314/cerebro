;;; notes-lint.el --- consistency checks for cerebro notes -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/notes-lint.el -- [file.org ...]
;; (default, no args: every .org file under notes/)
;;
;; Two tiers, matching how the rest of the tooling degrades:
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

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (lisp-dir (expand-file-name "../.emacs.d/lisp" here)))
  (add-to-list 'load-path lisp-dir))
(require 'cl-lib)
(require 'org)
(require 'org-element)
(require 'cerebro-org)

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
                                  file (org-element-property :raw-value h) tag))))))))

(defun cerebro-lint--tier2 ()
  (if (not (require 'org-roam nil t))
      (message "notes-lint: org-roam unavailable, skipping tier-2 graph checks")
    (if (not (and (boundp 'org-roam-db-location)
                  org-roam-db-location
                  (file-exists-p org-roam-db-location)))
        (message "notes-lint: no Org-roam database yet, skipping tier-2 graph checks")
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
  (dolist (f files) (cerebro-lint--tier1-file f)))
(cerebro-lint--tier2)

(dolist (i (reverse cerebro-lint--info)) (message "notes-lint: info: %s" i))
(dolist (e (reverse cerebro-lint--errors)) (message "notes-lint: ERROR: %s" e))
(if cerebro-lint--errors
    (progn (message "notes-lint: %d error(s)" (length cerebro-lint--errors)) (kill-emacs 1))
  (message "notes-lint: ok")
  (kill-emacs 0))
