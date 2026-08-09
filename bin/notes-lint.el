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
;;   org-tag-alist (see notes/README.org), and -- in notes/math/ -- a
;;   file whose name is no longer the digest of its own metadata.
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
(require 'cerebro-hash) ;; a note in notes/math/ is named by its metadata
(require 'cerebro-bib)  ;; the one bibliography every [cite:@key] must be in
(require 'cerebro-results) ;; the #+NAME/#+DEPENDS logical-dependency graph

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
            ;; `cerebro-results-provable-types', not a fourth copy of the
            ;; list: which blocks owe a proof is one decision, and it is
            ;; already made in cerebro-results.el (which this file
            ;; requires). Adding a result type there now teaches the
            ;; linter about it too, instead of leaving a type the
            ;; dependency graph tracks and the push gate ignores.
            (when (member type cerebro-results-provable-types)
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
      ;; This archive is theory: definitions, statements, proofs. An
      ;; example is a particular object, and a particular object is the
      ;; one thing a note cannot be reused as -- it cannot be cited, it
      ;; cannot be depended on, and it says nothing that survives being
      ;; generalised. A would-be example with real content *is* a
      ;; proposition and should be stated as one; an exercise is a proof
      ;; someone decided not to write down.
      ;;
      ;; An error, not advice: this is a convention about what the
      ;; archive *is*, and the whole point of putting it in the push gate
      ;; is that it cannot drift back one note at a time.
      ;;
      ;; Two element types, because Org parses these differently:
      ;; `#+begin_example' is an `example-block' (Org reserves the name
      ;; for verbatim text), while exercise/hint/solution are ordinary
      ;; special blocks.
      (org-element-map tree 'example-block
        (lambda (block)
          (cerebro-lint--err
           "%s: `#+begin_example' -- this archive holds no examples; state it as a proposition, or as prose"
           file)
          (ignore block)))
      (org-element-map tree 'special-block
        (lambda (block)
          (let ((type (downcase (or (org-element-property :type block) ""))))
            (when (member type '("exercise" "hint" "solution"))
              (cerebro-lint--err
               "%s: `#+begin_%s' -- this archive holds no exercises; write the proof out"
               file type)))))
      ;; A referenceable result block (cerebro-results.el's types) with no
      ;; #+NAME can't be cited in the dependency graph or the index -- a
      ;; rigorous archive names everything it might depend on. Advisory: a
      ;; freshly captured scratch statement need not be named yet.
      (org-element-map tree 'special-block
        (lambda (block)
          (let ((type (downcase (or (org-element-property :type block) ""))))
            (when (and (member type cerebro-results-types)
                       (not (org-element-property :name block)))
              (cerebro-lint--note
               "%s: %s block has no #+NAME (not referenceable in `make results')"
               file type)))))
      ;; A `proof' whose immediately preceding sibling is not a theorem-like
      ;; block is probably misplaced (a proof attaches to the statement just
      ;; above it -- the same adjacency the proof check above relies on).
      ;; Advisory.
      (org-element-map tree 'special-block
        (lambda (block)
          (when (equal (downcase (or (org-element-property :type block) "")) "proof")
            (let* ((parent (org-element-property :parent block))
                   (siblings (org-element-contents parent))
                   (idx (cl-position block siblings))
                   (prev (and idx (> idx 0) (nth (1- idx) siblings)))
                   (prev-type (and prev (eq (org-element-type prev) 'special-block)
                                   (downcase (or (org-element-property :type prev) "")))))
              ;; Same list, same reason: what a proof may attach to is
              ;; what a proof is expected for.
              (unless (member prev-type cerebro-results-provable-types)
                (cerebro-lint--note
                 "%s: proof block has no theorem-like block immediately before it" file))))))
      (org-element-map tree 'headline
        (lambda (h)
          (dolist (tag (org-element-property :tags h))
            (unless (member tag known-tags)
              (cerebro-lint--err "%s: heading `%s' uses undeclared tag `%s' (see notes/README.org)"
                                  file (org-element-property :raw-value h) tag)))))
      ;; MSC2020 classification (cerebro-msc.el): every code in a #+MSC:
      ;; line must be well-formed and name a real top-level class -- a
      ;; typo'd code silently mis-files a note and breaks \subjclass on a
      ;; note. Advisory-only nudge: an evergreen note with no MSC
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
          (cerebro-lint--err "%s: invalid MSC code `%s' (not MSC2020 -- see notes/README.org)"
                              file bad))
        (when (and filetags (string-match-p ":evergreen:" filetags) (null codes))
          (cerebro-lint--note "%s: evergreen note has no #+MSC: classification" file))))))

(defvar cerebro-lint--ispell-program
  (or (executable-find "aspell") (executable-find "hunspell"))
  "Which spell-checker backend to use, if any. aspell (from guix.scm)
is preferred; hunspell is an acceptable fallback if that's what's on
PATH (e.g. testing outside the guix environment).")

(defvar cerebro-lint--spelling-warned nil
  "Whether the \"spelling unavailable\" notice has been printed already.
Once per run, not once per note: the same message twelve times reads
like twelve problems.")

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
           ;; The usual cause is running outside the pinned environment:
           ;; aspell and its dictionary come from guix.scm, and whatever
           ;; the host happens to have (often hunspell with no matching
           ;; dictionary) then fails. That is not a defect in the notes,
           ;; so say what it is and how to get the check back -- once.
           (unless cerebro-lint--spelling-warned
             (setq cerebro-lint--spelling-warned t)
             (message "notes-lint: spelling check skipped -- %s"
                      (if (string-suffix-p "hunspell" (or cerebro-lint--ispell-program ""))
                          "hunspell has no usable dictionary here; run inside the pinned environment (aspell comes from guix.scm)"
                        (error-message-string err))))))))))

(defun cerebro-lint--naked-dollar (file)
  "Flag any unescaped `$' outside a src/example/export block. Notes use
\\(...\\) for inline math and \\[...\\] for display; a bare `$...$' is
fragile in Org -- next to punctuation (the classic `$x$--$y$') it
silently mis-parses, leaving a literal `$' that fails to compile (TeX's
`Missing $ inserted', a wrong PDF under nonstopmode). Raw line scan on
purpose: that broken case is exactly the one Org does NOT parse as a
latex-fragment, so an org-element check would miss it. A hard error --
this is the world-class-parsability convention, not a suggestion."
  (with-temp-buffer
    (insert-file-contents file)
    ;; src/example/export are verbatim (a $ there is literal text, not
    ;; math); comment blocks are never exported, so a $ in one can't cause
    ;; a compile error and may legitimately illustrate the very convention
    ;; this check enforces. Skip all four.
    (let ((in-verbatim nil) (lineno 0))
      (dolist (line (split-string (buffer-string) "\n"))
        (setq lineno (1+ lineno))
        (cond
         (in-verbatim
          (when (string-match-p "\\`[ \t]*#\\+end_\\(src\\|example\\|export\\|comment\\)" line)
            (setq in-verbatim nil)))
         ((string-match-p "\\`[ \t]*#\\+begin_\\(src\\|example\\|export\\|comment\\)" line)
          (setq in-verbatim t))
         ((string-match-p "\\(?:^\\|[^\\]\\)\\$" line)
          (cerebro-lint--err
           "%s:%d: naked `$' in math -- use \\(...\\) inline and \\[...\\] for display ($...$ mis-parses next to punctuation in Org)"
           file lineno)))))))

(defun cerebro-lint--hash-name (file)
  "In notes/math/, check that FILE is called what its metadata says.

The name is derived data (cerebro-hash.el), and derived data that
nothing checks is derived data that quietly stops being derived: an
editor other than Emacs, a `git checkout' of an older revision, or a
hand-written file all leave a note whose name no longer follows from its
contents. An error, not a nudge -- with a one-command repair, which is
what makes it fair to insist."
  (when (cerebro-hash-note-p file)
    (when-let* ((wrong (cerebro-hash-check-file file)))
      (cerebro-lint--err
       "%s: metadata says this note is `%s' (run `cerebro note rehash')"
       file (cerebro-hash-file-name (plist-get wrong :hash))))))

(defun cerebro-lint--citations (file keys)
  "Flag every `[cite:@key]' in FILE whose key is not in KEYS.

The one thing about a citation that used to fail silently: a mistyped or
renamed key compiles into a bold `[key?]' in the middle of a paragraph,
and biber says so in a .blg nobody reads. Checking it here, against the
single bibliography, is what makes `C-c b i' worth trusting -- and what
makes a wrong key a push that does not happen rather than a PDF you hand
someone."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((lineno 0)
          (bib (file-relative-name cerebro-bib-file cerebro-root)))
      (dolist (line (split-string (buffer-string) "\n"))
        (setq lineno (1+ lineno))
        ;; `[cite:@a;@b]' and `[cite/t:@a]' both scan: the keys are what
        ;; matters, not which citation style asked for them.
        ;;
        ;; Both loops read `match-end' into a local BEFORE doing anything
        ;; else, because reporting an error runs `format' and `push' and
        ;; those leave the match data as whatever they last matched. Read
        ;; afterwards, the position went backwards on exactly the inputs
        ;; this function exists to catch -- a wrong key -- and the scan
        ;; looped forever on them. (It did. That is why this is written
        ;; out rather than inlined.)
        (dolist (key (cerebro-lint--citation-keys line))
          (unless (member key keys)
            (cerebro-lint--err "%s:%d: [cite:@%s] -- no such entry in %s"
                               file lineno key bib)))))))

(defun cerebro-lint--citation-keys (line)
  "Every citation key referenced in LINE. Pure."
  (let ((keys nil) (pos 0))
    (while (string-match "\\[cite[^]:]*:\\([^]]*\\)\\]" line pos)
      (let ((body (match-string 1 line))
            (end (match-end 0))
            (inner 0))
        (while (string-match "@\\([^];, \t]+\\)" body inner)
          (setq inner (match-end 0))
          (push (match-string 1 body) keys))
        (setq pos end)))
    (nreverse keys)))

(defun cerebro-lint--results ()
  "Corpus-level checks on the #+NAME/#+DEPENDS results graph
(cerebro-results.el): a result name defined twice (an ambiguous global
key), a #+DEPENDS: pointing at a result that no note defines (a typo or a
stale rename), and a dependency cycle (a result that rests, transitively,
on itself -- always a bug). These need the *whole* corpus, since a
dependency and its dependents routinely live in different files, so --
like the tier-2 graph checks -- they always scan all of notes/,
independent of the file arguments. Pure Elisp: no Org-roam, no Guix."
  (let ((records (cerebro-results-scan)))
    (dolist (n (cerebro-results-duplicate-names records))
      (cerebro-lint--err
       "result #+NAME `%s' is defined more than once (a result name is a global key)" n))
    (dolist (d (cerebro-results-dangling records))
      (cerebro-lint--err
       "result `%s' #+DEPENDS on `%s', which no note defines (typo or stale rename)"
       (car d) (cdr d)))
    (dolist (c (cerebro-results-cycles records))
      (cerebro-lint--err
       "result `%s' is on a dependency cycle -- it rests transitively on itself" c))))

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
    ;; `cerebro-note-files' rather than a raw walk: it is the single
    ;; definition of "which .org files are notes", and it knows that a
    ;; course composed into .build/ for an export is a build product, not
    ;; something to lint (and to report twice, once per included note).
    (setq files (cerebro-note-files)))
  (let ((keys (cerebro-bib-keys)))
    (dolist (f files)
      (cerebro-lint--tier1-file f)
      (cerebro-lint--naked-dollar f)
      (cerebro-lint--hash-name f)
      (cerebro-lint--citations f keys)))
  (if cerebro-lint--ispell-program
      (dolist (f files) (cerebro-lint--spelling-file f))
    (message "notes-lint: no aspell/hunspell on PATH, skipping the spelling pass")))
(cerebro-lint--results)
(cerebro-lint--tier2)

(dolist (i (reverse cerebro-lint--info)) (message "notes-lint: info: %s" i))
(dolist (e (reverse cerebro-lint--errors)) (message "notes-lint: ERROR: %s" e))
(if cerebro-lint--errors
    (progn (message "notes-lint: %d error(s)" (length cerebro-lint--errors)) (kill-emacs 1))
  (message "notes-lint: ok")
  (kill-emacs 0))
