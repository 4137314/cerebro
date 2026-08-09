;;; cerebro-taxonomy.el --- coarse subject-area hierarchy -*- lexical-binding: t; -*-

;; The browse-grade half of cerebro's two-dimensional subject taxonomy
;; (the paper-grade half is MSC2020, in cerebro-msc.el): a small,
;; two-level tree of area tags. MSC answers "exactly what leaf of
;; mathematics is this" for a paper; these answer "roughly what shelf
;; does it live on" for day-to-day navigation and agenda filtering.
;;
;; It is *data*: an alist of (SUPERTAG SUBTAG...). cerebro-org.el turns
;; it into Org's native "group tags" (:startgrouptag/:grouptag/
;; :endgrouptag), so a supertag stands for all of its members --
;; searching or filtering the agenda by `analysis' matches a note tagged
;; only `functional_analysis', with no extra machinery. Adding an area
;; is one line here; the linter's vocabulary (cerebro-known-tags) and
;; the agenda grouping both update from it automatically.
;;
;; Pure: cl-lib only. Tested by tests/cerebro-graph-tests.el's sibling
;; expectations indirectly, and kept free of Org so the data can be read
;; from anywhere.

(defconst cerebro-area-taxonomy
  '((analysis        real_analysis complex_analysis functional_analysis
                     harmonic_analysis measure_theory operator_theory
                     ordinary_differential_equations
                     partial_differential_equations calculus_of_variations)
    (algebra         group_theory ring_theory field_theory
                     commutative_algebra linear_algebra
                     representation_theory homological_algebra
                     lie_theory)
    (geometry        differential_geometry algebraic_geometry
                     riemannian_geometry symplectic_geometry
                     convex_geometry)
    (topology        general_topology algebraic_topology
                     differential_topology)
    (number_theory   analytic_number_theory algebraic_number_theory)
    (foundations     logic set_theory model_theory proof_theory
                     computability category_theory)
    (combinatorics   graph_theory)
    (probability     probability_theory stochastic_processes statistics)
    (dynamics        dynamical_systems ergodic_theory)
    (numerics        numerical_analysis approximation_theory optimization)
    (mathematical_physics quantum_theory statistical_mechanics
                     relativity classical_mechanics fluid_mechanics
                     thermodynamics))
  "Two-level area hierarchy, as (SUPERTAG SUBTAG...).
The SUPERTAGs are the coarse shelves; SUBTAGs the finer ones. See
`cerebro-taxonomy-org-group-tags' for how this becomes Org group tags.
`logic' lives under `foundations' but is kept as a member so the older
`logic' tag stays valid.")

(defun cerebro-taxonomy-supertags ()
  "List of area supertag strings."
  (mapcar (lambda (g) (symbol-name (car g))) cerebro-area-taxonomy))

(defun cerebro-taxonomy-all-tags ()
  "Flat list of every area tag string -- supertags and subtags."
  (let (tags)
    (dolist (group cerebro-area-taxonomy)
      (dolist (sym group)
        (push (symbol-name sym) tags)))
    (nreverse tags)))

(defun cerebro-taxonomy-area-of (tag)
  "The supertag (string) whose group TAG belongs to, or nil.
A supertag is considered to belong to itself."
  (let ((sym (intern tag)) hit)
    (dolist (group cerebro-area-taxonomy hit)
      (when (memq sym group)
        (setq hit (symbol-name (car group)))))))

(defun cerebro-taxonomy-family (supertag)
  "SUPERTAG plus all its subtags, as a list of strings, or nil if
SUPERTAG is not an area supertag. This is the set of literal tags an
area query should match: Org expands a group tag itself in the agenda
and in searches, but org-ql (cerebro-ql.el) matches literal tags, so an
area query there has to expand the family by hand."
  (let ((group (assq (intern supertag) cerebro-area-taxonomy)))
    (when group (mapcar #'symbol-name group))))

(defun cerebro-taxonomy-org-group-tags ()
  "Render `cerebro-area-taxonomy' as `org-tag-alist' group-tag entries.
Each supertag becomes a group whose members are its subtags, so Org
expands the supertag to all of them in searches and agenda filters.
Keyless on purpose: with this many tags, per-tag fast-select letters
would collide -- select an area by name (completion) instead."
  (let (entries)
    (dolist (group cerebro-area-taxonomy)
      (let ((super (symbol-name (car group)))
            (subs (mapcar #'symbol-name (cdr group))))
        (push '(:startgrouptag) entries)
        (push (list super) entries)
        (push '(:grouptag) entries)
        (dolist (sub subs) (push (list sub) entries))
        (push '(:endgrouptag) entries)))
    (nreverse entries)))


;; -- States ------------------------------------------------------------
;; Two vocabularies that are *ordered*, unlike the area tags above, and
;; that is what makes them states rather than labels: a note climbs the
;; maturity ladder, a result moves towards being proved. Ordered data
;; means the tooling can say "promote", "what is still at the bottom",
;; "what rests on something unproved" -- none of which a flat tag can
;; answer.
;;
;; Both live here, with the rest of the controlled vocabulary, so the
;; linter (which rejects any tag not in `cerebro-known-tags'), the
;; capture templates and the reports read one definition.

(defconst cerebro-maturity-ladder '("seed" "growing" "evergreen")
  "How much a note can be trusted, in increasing order.
`seed' is written down, `growing' is being worked out, `evergreen' is
something you would hand to someone else. Exactly one applies at a time
-- Org enforces that through the mutually exclusive tag group in
cerebro-org.el.")

(defun cerebro-taxonomy-maturity (tags)
  "The maturity tag among TAGS, or nil. Pure."
  (seq-find (lambda (tag) (member tag cerebro-maturity-ladder)) tags))

(defun cerebro-taxonomy-next-maturity (tag)
  "The rung above TAG, or nil at the top (and `seed' from nothing).
Promotion is one-way on purpose: a note that has been rewritten from
scratch is demoted by editing the tag, which is a deliberate act, not a
keystroke."
  (cond ((null tag) (car cerebro-maturity-ladder))
        ((equal tag (car (last cerebro-maturity-ladder))) nil)
        (t (nth (1+ (seq-position cerebro-maturity-ladder tag))
                cerebro-maturity-ladder))))

(defun cerebro-taxonomy-set-maturity (tags maturity)
  "TAGS with its maturity tag replaced by MATURITY (nil removes it).
Order is preserved and nothing else is touched: the area tags, `crypt',
`drill' and the rest are none of this function's business. Pure."
  (let ((rest (seq-remove (lambda (tag) (member tag cerebro-maturity-ladder)) tags)))
    (if maturity (cons maturity rest) rest)))

(defconst cerebro-proof-statuses
  '(("proved"  . "there is a proof, here or cited")
    ("assumed" . "taken as given on purpose -- an axiom, a hypothesis, a black box")
    ("open"    . "no proof yet, and none assumed"))
  "What a result's `#+STATUS:' can say, and what each value means.

The point is `assumed': a second brain accumulates results used before
they are proved, and the difference between proving something, choosing
to assume it, and simply not having got to it is the difference between
mathematics and wishful thinking. Recording it makes
`cerebro-results-open' possible, and with it the only question that
matters at scale: what rests on something I have not proved?")

(defun cerebro-proof-status-p (value)
  "Non-nil when VALUE is one of `cerebro-proof-statuses'."
  (and (stringp value) (assoc value cerebro-proof-statuses) t))

(provide 'cerebro-taxonomy)
