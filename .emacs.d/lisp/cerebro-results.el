;;; cerebro-results.el --- the logical-dependency layer over named results -*- lexical-binding: t; -*-

;; A theoretical mathematician's notes ARE a dependency structure: a
;; theorem rests on lemmas and definitions, which rest on axioms and
;; earlier definitions. cerebro already gives every result a stable key --
;; the `#+NAME:' on its special block (the same name the `single' export
;; and the linter's duplicate check use). This module turns those keys into
;; a queryable *directed acyclic graph* of results, with one added
;; convention and nothing else:
;;
;;     #+DEPENDS: def-compact, thm-bolzano-weierstrass
;;     #+NAME: thm-heine-borel
;;     #+begin_theorem
;;     ...
;;     #+end_theorem
;;
;; Order matters: #+DEPENDS goes ABOVE #+NAME, and #+NAME stays directly
;; on top of the #+begin_ line. #+DEPENDS is not an Org affiliated keyword,
;; so putting it *between* #+NAME and the block would detach the name in
;; org-element's eyes (breaking the `single' export); the parser enforces
;; the same rule so the two views never disagree.
;;
;; `#+DEPENDS:' is a sibling keyword listing the #+NAMEs
;; this result rests on (comma/space separated). It is invisible to every
;; LaTeX export profile -- Org drops unknown keywords, exactly as it does
;; #+MSC: (verified against a real export) -- so declaring dependencies
;; never changes a single PDF. It only builds the knowledge graph:
;;
;;   - "on what does this theorem rest?"        (transitive dependencies,
;;                                               foundations first)
;;   - "if I change this definition, what
;;      proofs are affected?"                   (transitive dependents --
;;                                               the impact/backlink view)
;;   - "where is every result I've stated?"     (the global index)
;;
;; and it lets the linter catch two mistakes that silently rot a lifelong
;; archive: a #+DEPENDS: pointing at a name that doesn't exist (a typo, or
;; a result you renamed and forgot), and a dependency *cycle* (a proof
;; that, transitively, rests on itself -- always a bug).
;;
;; Design mirrors cerebro-graph.el: the parsing and the graph algorithms
;; are PURE (strings and alists in, results out -- no Org, no Org-roam, no
;; Guix), so tests/cerebro-results-tests.el exercises them directly and
;; the whole feature works even outside the guix environment. Only the
;; handful of interactive commands at the bottom touch the filesystem and
;; the display, reusing `cerebro-note-files' and `cerebro-report' from
;; cerebro-org.el so the corpus and the report buffer match the rest of
;; the tooling.

(require 'cl-lib)
(require 'cerebro-base)     ;; paths, the note lister, the report buffer
(require 'cerebro-taxonomy) ;; cerebro-proof-status-p -- data, 1ms, no Org

(defconst cerebro-results-types
  '("theorem" "lemma" "proposition" "corollary"
    "definition" "axiom" "conjecture")
  "Special-block types that name a *referenceable result*.
A `proof' is attached to its theorem, and remark/example/exercise/hint/
solution are apparatus, not results -- none of them are keys you would
declare a dependency on, so they are deliberately excluded here.")

;; -- Pure parsing ------------------------------------------------------
;; Line-based on purpose, like bin/notes-lint.el's prose scan and
;; cerebro-query.el's keyword scan: no org-element, so it is trivially
;; testable on a plain string and cannot pull in a heavy dependency.
;; Affiliated keywords (#+NAME:/#+DEPENDS:) attach to the block only when
;; contiguous with its #+begin_ line -- a blank line or prose between them
;; breaks the association, matching how Org itself binds affiliated
;; keywords to the following element.

(defun cerebro-results--split (value)
  "Split a raw #+DEPENDS: VALUE into a list of trimmed names.
Separators are commas and/or whitespace; empty pieces dropped (as
`cerebro-msc-parse' does for MSC codes)."
  (if (stringp value)
      (seq-remove #'string-empty-p (split-string value "[,[:space:]]+" t))
    nil))

(defun cerebro-results--strip-tags (heading)
  "HEADING text with any trailing Org `:tag:tag:' cluster removed."
  (if (string-match "[ \t]+:[[:alnum:]_@#%:]+:[ \t]*\\'" heading)
      (string-trim (substring heading 0 (match-beginning 0)))
    (string-trim heading)))

(defun cerebro-results-parse-string (text &optional file)
  "Parse note TEXT into a list of result plists.
Each is (:name :type :deps :status :file :line :heading) for one #+NAMEd
result block whose type is in `cerebro-results-types'. FILE is stored
verbatim (a display label); :line is 1-based, at the #+begin_ line;
:heading is the nearest preceding headline title (tags stripped), for
context. Unnamed result blocks are skipped -- naming a result is what
makes it a first-class, referenceable node.

:status is the proof status (see `cerebro-proof-statuses'): an explicit
`#+STATUS:' if the note gives one, else `proved' when a proof block
follows the statement directly -- this repo's own convention, and what
the `single' export profile already relies on -- else `open' for the
types a proof is expected for.

A tiny state machine rather than org-element: it must see the file as
*text*, because the mistakes it exists to catch (a `#+DEPENDS:' wedged
between `#+NAME:' and its block) are exactly the ones that make
org-element parse something different from what was meant."
  (let ((case-fold-search t)
        (line-no 0)
        heading pending-name pending-deps pending-status results
        in-block          ; the open blocks, innermost first
        awaiting-proof)   ; the record a proof could still attach to
    (dolist (line (split-string text "\n"))
      (setq line-no (1+ line-no))
      (cond
       ;; Inside a block: only nesting and its end matter.
       ;;
       ;; A stack, not a flag, and not a single type: this closed on the
       ;; first `#+end_' of ANY type, so one nested block inside a
       ;; statement ended the statement early --
       ;;
       ;;     #+NAME: thm-a
       ;;     #+begin_theorem
       ;;     #+begin_quote ... #+end_quote     <- closed the theorem
       ;;     #+end_theorem                     <- read as prose, which
       ;;     #+begin_proof                        cleared `awaiting-proof'
       ;;
       ;; -- and the proof directly below it was no longer that theorem's
       ;; proof. The result came out `open' forever, in `cerebro results
       ;; open' and on the start page, while bin/notes-lint.el (which
       ;; reads the same convention through org-element, and gets nesting
       ;; right) went on saying it was proved. Two views of one
       ;; convention, disagreeing -- which is the one thing the module
       ;; commentary above promises cannot happen.
       ;;
       ;; An `#+end_' naming a block that is open but not innermost
       ;; unwinds to it, so an inner block someone forgot to close cannot
       ;; swallow the rest of the file either.
       (in-block
        (cond
         ((string-match "\\`[ \t]*#\\+begin_\\([a-zA-Z]+\\)" line)
          (push (downcase (match-string 1 line)) in-block))
         ((string-match "\\`[ \t]*#\\+end_\\([a-zA-Z]+\\)" line)
          (let ((type (downcase (match-string 1 line))))
            (when (member type in-block)
              (while (not (equal (car in-block) type)) (pop in-block))
              (pop in-block))))))
       ;; A headline breaks everything: a proof under a different heading
       ;; is not this statement's proof.
       ((string-match "\\`\\*+[ \t]+\\(.*\\)\\'" line)
        (setq heading (cerebro-results--strip-tags (match-string 1 line))
              pending-name nil pending-deps nil pending-status nil
              awaiting-proof nil))
       ((string-match "\\`[ \t]*#\\+NAME:[ \t]*\\(.*\\)\\'" line)
        (setq pending-name (string-trim (match-string 1 line))))
       ;; `#+DEPENDS:' is NOT an Org affiliated keyword, so -- like any
       ;; non-affiliated line -- it detaches a `#+NAME' written *above*
       ;; it from the block below: org-element would then see no :name,
       ;; silently breaking the `single' export and the duplicate-name
       ;; check while this parser still saw the name. Clearing
       ;; pending-name here is what keeps the two from ever disagreeing.
       ;; The convention that follows: `#+DEPENDS:'/`#+STATUS:' go ABOVE
       ;; `#+NAME:', and `#+NAME:' stays directly on top of `#+begin_'.
       ((string-match "\\`[ \t]*#\\+DEPENDS:[ \t]*\\(.*\\)\\'" line)
        (setq pending-deps (cerebro-results--split (match-string 1 line))
              pending-name nil))
       ((string-match "\\`[ \t]*#\\+STATUS:[ \t]*\\(.*\\)\\'" line)
        (setq pending-status (downcase (string-trim (match-string 1 line)))
              pending-name nil))
       ((string-match "\\`[ \t]*#\\+begin_\\([a-zA-Z]+\\)" line)
        (let ((type (downcase (match-string 1 line))))
          (setq in-block (list type))
          (cond
           ;; A proof directly after a statement proves it, unless the
           ;; statement said otherwise itself.
           ((and (equal type "proof") awaiting-proof)
            (unless (plist-get awaiting-proof :status)
              (plist-put awaiting-proof :status "proved"))
            (setq awaiting-proof nil))
           ((and pending-name (member type cerebro-results-types))
            (let ((record (list :name pending-name :type type :deps pending-deps
                                :status (when (cerebro-proof-status-p pending-status)
                                          pending-status)
                                :file file :line line-no :heading heading)))
              (push record results)
              ;; The proof may follow after this block closes.
              (setq awaiting-proof record)))
           (t (setq awaiting-proof nil))))
        (setq pending-name nil pending-deps nil pending-status nil))
       ;; A blank line between a statement and its proof is normal, and
       ;; must not break the pair.
       ((string-match-p "\\`[ \t]*\\'" line)
        (setq pending-name nil pending-deps nil pending-status nil))
       ;; Any other content outside a block: prose has resumed, so
       ;; whatever comes later is no longer *this* statement's proof.
       (t (setq pending-name nil pending-deps nil pending-status nil
                awaiting-proof nil))))
    (mapcar #'cerebro-results--with-default-status (nreverse results))))

(defconst cerebro-results-provable-types
  '("theorem" "lemma" "proposition" "corollary")
  "Result types that a proof is *expected* for.
A definition or an example is not unproved -- it is not the kind of thing
that gets proved -- so leaving them out is what keeps
`cerebro-results-open' a list of real work rather than of every block in
the archive.

This is the one list of \"needs a proof\" in the repository:
bin/notes-lint.el reads it rather than repeating it, because a type
added here and forgotten there is a result the linter stops asking for a
proof of -- silently, which is the only kind of rot that matters in an
archive meant to last.

Necessarily a subset of `cerebro-results-types': a type the parser never
records cannot be reported unproved. It held a fifth entry, \"claim\",
for a while -- not in `cerebro-results-types', not an environment in
latex/cerebro-theorems.sty, so it could never match anything and a
`#+begin_claim' would have failed to compile anyway. A test now pins the
subset relation, which is what makes that mistake loud instead of
invisible.")

(defun cerebro-results--with-default-status (record)
  "RECORD with `:status' filled in when it can be inferred.
Explicit `#+STATUS:' always wins; a statement followed by a proof block
is `proved'; anything else that ought to have a proof is `open'; the
types that are not proved at all keep no status."
  (or (plist-get record :status)
      (plist-put record :status
                 (when (member (plist-get record :type) cerebro-results-provable-types)
                   "open")))
  record)

(defun cerebro-results-by-status (records status)
  "The RECORDS whose `:status' is STATUS. Pure."
  (seq-filter (lambda (r) (equal (plist-get r :status) status)) records))

(defun cerebro-results-unproved (records)
  "RECORDS that are `open' or `assumed', open first -- the work list.
`assumed' is included on purpose: something you decided to take for
granted is still something the archive owes an argument for, and it is
the thing you forget you decided."
  (append (cerebro-results-by-status records "open")
          (cerebro-results-by-status records "assumed")))

;; -- Pure graph algorithms (over parsed records) -----------------------

(defun cerebro-results-names (records)
  "Set (a list, order preserved, de-duplicated) of names RECORDS define."
  (delete-dups (mapcar (lambda (r) (plist-get r :name)) records)))

(defun cerebro-results-alist (records)
  "Adjacency alist NAME -> (dep ...) built from RECORDS.
If a name is defined by more than one record their dependency lists are
unioned; `cerebro-results-duplicate-names' is what flags that as an
error, this just stays well-defined in the meantime."
  (let (alist)
    (dolist (r records)
      (let* ((name (plist-get r :name))
             (cell (assoc name alist)))
        (if cell
            (setcdr cell (delete-dups (append (cdr cell) (plist-get r :deps))))
          (push (cons name (copy-sequence (plist-get r :deps))) alist))))
    (nreverse alist)))

(defun cerebro-results-duplicate-names (records)
  "Names defined by more than one record in RECORDS.
A result name is a global key (a dependency, the `single' export target,
a mental cross-reference); two results sharing one is ambiguous."
  (let ((counts (make-hash-table :test 'equal)) dups)
    (dolist (r records)
      (let ((n (plist-get r :name)))
        (puthash n (1+ (gethash n counts 0)) counts)))
    (maphash (lambda (n c) (when (> c 1) (push n dups))) counts)
    (nreverse dups)))

(defun cerebro-results-dangling (records)
  "List of (NAME . MISSING) where result NAME declares a dependency on
MISSING, but no record defines MISSING -- a typo or a stale reference."
  (let ((known (let ((h (make-hash-table :test 'equal)))
                 (dolist (n (cerebro-results-names records)) (puthash n t h))
                 h))
        dangling)
    (dolist (r records)
      (dolist (dep (plist-get r :deps))
        (unless (gethash dep known)
          (push (cons (plist-get r :name) dep) dangling))))
    (nreverse dangling)))

(defun cerebro-results--postorder (alist start)
  "Names reachable from START through ALIST, in dependency-first order
and excluding START. Cycle-safe (a visited set), so it terminates even
if the graph has a cycle."
  (let ((visited (make-hash-table :test 'equal)) out)
    (cl-labels ((visit (n)
                  (unless (gethash n visited)
                    (puthash n t visited)
                    (dolist (m (cdr (assoc n alist))) (visit m))
                    (push n out))))
      (dolist (m (cdr (assoc start alist))) (visit m)))
    (nreverse out)))

(defun cerebro-results-transitive-deps (records name)
  "Every result NAME rests on, directly or transitively, foundations
first. NAME itself is excluded."
  (cerebro-results--postorder (cerebro-results-alist records) name))

(defun cerebro-results-reverse-alist (records)
  "Reverse adjacency: NAME -> (results that depend on NAME ...)."
  (let (rev)
    (dolist (pair (cerebro-results-alist records))
      (let ((from (car pair)))
        (dolist (to (cdr pair))
          (let ((cell (assoc to rev)))
            (if cell (setcdr cell (cons from (cdr cell)))
              (push (cons to (list from)) rev))))))
    rev))

(defun cerebro-results-transitive-dependents (records name)
  "Every result that rests on NAME, directly or transitively (sorted).
This is the impact / backlink view: change NAME and these are affected."
  (sort (cerebro-results--postorder (cerebro-results-reverse-alist records) name)
        #'string<))

(defun cerebro-results-cycles (records)
  "Names that lie on a dependency cycle (a result reachable from itself,
self-loops included). A cycle among results is always a bug: a proof
cannot, even transitively, rest on itself."
  (let ((alist (cerebro-results-alist records)))
    (seq-filter
     (lambda (name)
       (member name (cerebro-results--postorder alist name)))
     (mapcar #'car alist))))

;; -- Interactive commands (the only part that does I/O) ----------------

(defun cerebro-results-scan (&optional dir)
  "Parse every note under DIR (default `org-directory') into one flat
list of result records -- the whole-corpus view the graph needs (a
dependency and its dependents commonly live in different files).

Memoised on the notes' mtimes (cerebro-cache.el): this reads and parses
every file in the archive, and the start page, the index and the
dependency queries all ask for it in the same second."
  (let* ((dir (or dir org-directory))
         (files (cerebro-note-files dir)))
    (cerebro-cache-get
     (list 'results-scan dir)
     (cerebro-cache-file-signature files)
     (lambda () (cerebro-results-scan--uncached dir)))))

(defun cerebro-results-scan--uncached (&optional dir)
  "The real work behind `cerebro-results-scan'."
  (let (all)
    (dolist (f (cerebro-note-files dir))
      (with-temp-buffer
        (insert-file-contents f)
        (setq all (nconc all (cerebro-results-parse-string
                              (buffer-string)
                              (file-relative-name f cerebro-root))))))
    all))

(defun cerebro-results--record-table (records)
  (let ((h (make-hash-table :test 'equal)))
    (dolist (r records) (puthash (plist-get r :name) r h))
    h))

(defun cerebro-results--line (r)
  "One display line for record R: `TYPE [status] name -- heading (file:line)'."
  (format "%-11s %-9s %s%s%s"
          (plist-get r :type)
          (let ((status (plist-get r :status))) (if status (format "[%s]" status) ""))
          (plist-get r :name)
          (let ((h (plist-get r :heading))) (if (and h (not (string-empty-p h)))
                                                 (format "  -- %s" h) ""))
          (let ((f (plist-get r :file)))
            (if f (format "  (%s:%d)" f (plist-get r :line)) ""))))

;;;###autoload
(defun cerebro-results-index ()
  "The global index of every #+NAMEd result across the notes, grouped by
type then name -- the answer to \"where did I state that?\"."
  (interactive)
  (let* ((records (cerebro-results-scan))
         (order (lambda (a b)
                  (let ((ta (cl-position (plist-get a :type) cerebro-results-types :test #'equal))
                        (tb (cl-position (plist-get b :type) cerebro-results-types :test #'equal)))
                    (if (eql ta tb)
                        (string< (plist-get a :name) (plist-get b :name))
                      (< (or ta 99) (or tb 99))))))
         (rows (sort (copy-sequence records) order)))
    (cerebro-report
     (format "Results index (%d named)" (length rows))
     rows #'cerebro-results--line "*cerebro-results*")))

(defun cerebro-results--read-name (records prompt)
  (completing-read prompt (cerebro-results-names records) nil t))

;;;###autoload
(defun cerebro-results-dependencies (name)
  "What result NAME rests on, transitively, foundations first."
  (interactive
   (let ((records (cerebro-results-scan)))
     (list (cerebro-results--read-name records "Dependencies of result: "))))
  (let* ((records (cerebro-results-scan))
         (table (cerebro-results--record-table records))
         (deps (cerebro-results-transitive-deps records name))
         (rows (mapcar (lambda (n) (or (gethash n table)
                                       (list :type "?" :name n)))
                       deps)))
    (cerebro-report
     (format "`%s' depends on (%d, foundations first)" name (length rows))
     rows #'cerebro-results--line "*cerebro-results*")))

;;;###autoload
(defun cerebro-results-dependents (name)
  "What rests on result NAME, transitively -- the impact of changing it."
  (interactive
   (let ((records (cerebro-results-scan)))
     (list (cerebro-results--read-name records "Dependents of result: "))))
  (let* ((records (cerebro-results-scan))
         (table (cerebro-results--record-table records))
         (deps (cerebro-results-transitive-dependents records name))
         (rows (mapcar (lambda (n) (or (gethash n table)
                                       (list :type "?" :name n)))
                       deps)))
    (cerebro-report
     (format "Depends on `%s' (%d affected if it changes)" name (length rows))
     rows #'cerebro-results--line "*cerebro-results*")))

;;;###autoload
(defun cerebro-results-check ()
  "Report dependency-graph problems across the corpus: names defined
twice, #+DEPENDS: on a missing result, and dependency cycles. The same
checks the linter enforces (bin/notes-lint.el) -- this is the
interactive view of them."
  (interactive)
  (let* ((records (cerebro-results-scan))
         (dups (cerebro-results-duplicate-names records))
         (dangling (cerebro-results-dangling records))
         (cycles (cerebro-results-cycles records))
         rows)
    (dolist (n dups) (push (format "duplicate name:   %s (defined more than once)" n) rows))
    (dolist (d dangling) (push (format "dangling depends: %s -> %s (no such result)" (car d) (cdr d)) rows))
    (dolist (c cycles) (push (format "in a cycle:       %s (rests on itself)" c) rows))
    (cerebro-report
     (if rows (format "Results check -- %d problem(s)" (length rows))
       "Results check -- clean")
     (nreverse rows) #'identity "*cerebro-results*")))


;;;###autoload
(defun cerebro-results-open ()
  "What the archive still owes a proof (`C-c r o').
Everything `open' first, then everything `assumed' -- the second list is
the one that goes unnoticed, because an assumption reads like a decision
rather than like a debt."
  (interactive)
  (let* ((records (cerebro-results-scan))
         (unproved (cerebro-results-unproved records)))
    (cerebro-report
     (format "cerebro results -- %d unproved of %d (%d open, %d assumed)"
             (length unproved) (length records)
             (length (cerebro-results-by-status records "open"))
             (length (cerebro-results-by-status records "assumed")))
     unproved
     #'cerebro-results--line
     "*cerebro-results*")))

(provide 'cerebro-results)
