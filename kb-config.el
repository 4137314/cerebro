;;; kb-config.el --- settings of the mathematics base -*- lexical-binding: t; -*-

;; Loaded by the reader before the notes are read.  Domains in study order; the area
;; named like its domain holds the note that presents the subject, so it comes first.

(setq kb-domains '("foundations" "algebra" "analysis" "topology" "geometry" "probability"
                   "physics")
      kb-areas '("overview" "foundations" "algebra" "analysis" "topology" "geometry"
                 "probability" "mathematical-physics"
                 ;; foundations
                 "logic" "set-theory" "model-theory" "proof-theory" "computability"
                 ;; algebra
                 "linear-algebra" "group-theory" "ring-theory" "field-theory"
                 "commutative-algebra"
                 ;; analysis
                 "real-analysis" "complex-analysis" "measure-theory" "functional-analysis"
                 "harmonic-analysis" "ordinary-differential-equations"
                 "partial-differential-equations" "calculus-of-variations"
                 "approximation-theory"
                 ;; topology, geometry
                 "general-topology" "algebraic-topology" "differential-topology"
                 "convex-geometry" "differential-geometry" "algebraic-geometry"
                 "symplectic-geometry"
                 ;; probability, physics
                 "probability-theory" "statistics" "classical-mechanics"
                 "dynamical-systems" "quantum-theory")
      kb-forbidden "\\b\\(?:TODO\\|FIXME\\)\\b")

;; The notation of the notes (\R, \abs, \norm, \inner, \dd, \Prob, ...): the macros of the
;; old cerebro LaTeX pipeline, kept as they were.
(kb-preamble-add
 (format "\\usepackage{%s}"
         (file-name-sans-extension
          (expand-file-name "latex/cerebro-macros.sty"
                            (file-name-directory (or load-file-name buffer-file-name))))))
