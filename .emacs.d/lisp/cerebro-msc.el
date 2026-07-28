;;; cerebro-msc.el --- Mathematics Subject Classification (MSC2020) -*- lexical-binding: t; -*-

;; The paper-grade half of cerebro's two-dimensional subject taxonomy
;; (the other being the coarse area supertags in cerebro-taxonomy.el):
;; the AMS Mathematics Subject Classification, 2020 revision. It is the
;; plain-text standard for "what is this piece of mathematics about",
;; spans the whole of the field (logic and foundations through quantum
;; theory and relativity), and is what journals require on a submission
;; -- so the same `#+MSC:' keyword that files a note into the lifelong
;; database also fills in \subjclass[2020]{...} on a publishable paper
;; (see the `paper'/`preprint' doctypes in cerebro-latex.el).
;;
;; Only the 63 top-level (two-digit) classes are hard-coded here: that
;; list is small, fixed, and complete, and validating the two-digit
;; prefix already catches the mistakes that matter (a typo'd or
;; nonexistent class). The full five-character codes (47A75, 35Q41, ...)
;; are validated structurally, by shape, not against the ~6000-entry
;; leaf table -- deliberately, so this stays a single readable file with
;; no generated data blob to keep in sync with each MSC revision.
;;
;; Pure: requires nothing beyond Emacs core, so tests/cerebro-msc-tests.el
;; exercises it directly, no Org-roam or Guix needed (see `make test').

(defconst cerebro-msc-classes
  '(("00" . "General and overarching topics; collections")
    ("01" . "History and biography")
    ("03" . "Mathematical logic and foundations")
    ("05" . "Combinatorics")
    ("06" . "Order, lattices, ordered algebraic structures")
    ("08" . "General algebraic systems")
    ("11" . "Number theory")
    ("12" . "Field theory and polynomials")
    ("13" . "Commutative algebra")
    ("14" . "Algebraic geometry")
    ("15" . "Linear and multilinear algebra; matrix theory")
    ("16" . "Associative rings and algebras")
    ("17" . "Nonassociative rings and algebras")
    ("18" . "Category theory; homological algebra")
    ("19" . "K-theory")
    ("20" . "Group theory and generalizations")
    ("22" . "Topological groups, Lie groups")
    ("26" . "Real functions")
    ("28" . "Measure and integration")
    ("30" . "Functions of a complex variable")
    ("31" . "Potential theory")
    ("32" . "Several complex variables and analytic spaces")
    ("33" . "Special functions")
    ("34" . "Ordinary differential equations")
    ("35" . "Partial differential equations")
    ("37" . "Dynamical systems and ergodic theory")
    ("39" . "Difference and functional equations")
    ("40" . "Sequences, series, summability")
    ("41" . "Approximations and expansions")
    ("42" . "Harmonic analysis on Euclidean spaces")
    ("43" . "Abstract harmonic analysis")
    ("44" . "Integral transforms, operational calculus")
    ("45" . "Integral equations")
    ("46" . "Functional analysis")
    ("47" . "Operator theory")
    ("49" . "Calculus of variations and optimal control; optimization")
    ("51" . "Geometry")
    ("52" . "Convex and discrete geometry")
    ("53" . "Differential geometry")
    ("54" . "General topology")
    ("55" . "Algebraic topology")
    ("57" . "Manifolds and cell complexes")
    ("58" . "Global analysis, analysis on manifolds")
    ("60" . "Probability theory and stochastic processes")
    ("62" . "Statistics")
    ("65" . "Numerical analysis")
    ("68" . "Computer science")
    ("70" . "Mechanics of particles and systems")
    ("74" . "Mechanics of deformable solids")
    ("76" . "Fluid mechanics")
    ("78" . "Optics, electromagnetic theory")
    ("80" . "Classical thermodynamics, heat transfer")
    ("81" . "Quantum theory")
    ("82" . "Statistical mechanics, structure of matter")
    ("83" . "Relativity and gravitational theory")
    ("85" . "Astronomy and astrophysics")
    ("86" . "Geophysics")
    ("90" . "Operations research, mathematical programming")
    ("91" . "Game theory, economics, social and behavioral sciences")
    ("92" . "Biology and other natural sciences")
    ("93" . "Systems theory; control")
    ("94" . "Information and communication, circuits")
    ("97" . "Mathematics education"))
  "MSC2020 top-level (two-digit) classes, as (code . name).
The complete, fixed list of primary subject classes -- fine-grained
codes are validated by shape (see `cerebro-msc-valid-code-p'), not
against this table.")

(defconst cerebro-msc-code-regexp
  "\\`[0-9][0-9]\\(-XX\\|-[0-9][0-9]\\|[A-Z][0-9Xx][0-9Xx]\\)\\'"
  "Structural shape of an MSC code.
Matches a whole class (=46-XX=), a bibliographic subclass (=46-06=),
and a five-character code (=47A75=, =35Q41=, wildcards =46Axx=).")

(defun cerebro-msc-class-of (code)
  "The two-digit top-level class of CODE (a string), or nil if CODE is
too short to have one. Does not check that the class exists -- see
`cerebro-msc-class-name' for that."
  (when (and (stringp code) (>= (length code) 2))
    (substring code 0 2)))

(defun cerebro-msc-class-name (code)
  "Human-readable name of CODE's top-level class, or nil if that
two-digit class is not a real MSC class. CODE may be a full code
(=47A75=) or just the two-digit prefix (=47=)."
  (cdr (assoc (cerebro-msc-class-of code) cerebro-msc-classes)))

(defun cerebro-msc-valid-code-p (code)
  "Non-nil if CODE is a well-formed MSC code whose top-level class
actually exists in `cerebro-msc-classes'."
  ;; case-fold-search must be nil: MSC letters are case-significant (an
  ;; uppercase primary letter, a lowercase `x' wildcard), and it defaults
  ;; to t in batch, which would let [A-Z] match a stray lowercase letter.
  (let ((case-fold-search nil))
    (and (stringp code)
         (string-match-p cerebro-msc-code-regexp code)
         (assoc (cerebro-msc-class-of code) cerebro-msc-classes)
         t)))

(defun cerebro-msc-parse (value)
  "Split a raw =#+MSC:= keyword VALUE into a list of trimmed codes.
Separators are commas and/or whitespace; empty pieces are dropped."
  (when (stringp value)
    (seq-remove #'string-empty-p
                (split-string value "[,[:space:]]+" t))))

(defun cerebro-msc-primary (codes)
  "The primary (first) code of a CODES list, or nil."
  (car codes))

(defun cerebro-msc-invalid (codes)
  "The subset of CODES that are not valid MSC codes (for the linter)."
  (seq-remove #'cerebro-msc-valid-code-p codes))

(provide 'cerebro-msc)
