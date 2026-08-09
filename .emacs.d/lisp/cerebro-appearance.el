;;; cerebro-appearance.el --- how a note looks while you read it -*- lexical-binding: t; -*-

;; The colours and fonts live in cerebro-theme.el, the rendering of LaTeX
;; fragments in cerebro-preview.el; this file is about the *buffer*: what
;; an Org note looks like once it is open, and how close the screen gets
;; to the PDF the same file compiles to.
;;
;; Most of it is built into Org (entities, indentation, emphasis hiding).
;; Two small packages from guix.scm do the rest, both pulled through
;; `cerebro-guix-soft-require' so their absence costs a feature and never
;; the module:
;;
;;   org-modern -- draws headings, bullets, tags, blocks and timestamps
;;                 as shapes instead of markup, without touching the file
;;   org-appear -- shows the emphasis markers again when point walks into
;;                 the word, which is the one thing `org-hide-emphasis-
;;                 markers' (set in cerebro-org.el) otherwise makes
;;                 guesswork
;;
;; Nothing here changes a single byte of a note: every effect is display
;; only, which is the rule for a plain-text database you expect to read
;; with `cat' in twenty years.

(require 'cerebro-guix)  ;; cerebro-guix-soft-require
(require 'cerebro-theme) ;; the look these settings sit on top of
(require 'org)

;; -- Org's own presentation --------------------------------------------
;; `org-pretty-entities' is OFF, deliberately, and this is the one place
;; that decides it. Turned on, Org substitutes a glyph for the source of
;; every entity it recognises: `\in' is drawn as a character, `\pi' as
;; another, `x_{1}' with a raised/lowered baseline. That is a second,
;; lossy rendering of mathematics this repository already renders
;; properly -- and it renders exactly the wrong half.
;;
;;   - It is not the PDF. Only the entities in `org-entities' get a
;;     glyph, so `\eps', `\abs{x}' and every macro from
;;     latex/cerebro-macros.sty stay as source beside a `\in' that does
;;     not. A formula half-drawn is harder to read than one not drawn at
;;     all, and it hides the one thing worth checking on screen: whether
;;     what you typed is the LaTeX you meant.
;;   - The real preview already exists and is honest about being one:
;;     cerebro-preview.el compiles the fragment with the notes' own
;;     macros (`C-c u p'), so what you see is what latexmk will accept.
;;   - The substitution moves the point: a `\in' occupying one column and
;;     six characters makes editing inside `\(...\)' guesswork, and a
;;     subscript drawn small is unselectable text at a different height.
;;
;; So the buffer shows the file: linear, textual, the bytes that compile.
;; (Which `_' counts as a subscript at all is still decided once in
;; cerebro-org.el -- braced only -- because the batch exporter loads that
;; module and never this one, and the screen and the PDF must agree.)
(setq org-pretty-entities nil
      org-pretty-entities-include-sub-superscripts nil
      org-ellipsis " ▾"       ; "..." -> a small triangle, less noisy
      org-hide-leading-stars t
      org-fontify-quote-and-verse-blocks t
      org-fontify-whole-heading-line t)

;; Soft-wrap prose. Not cosmetic here: the note conventions require a
;; display equation to sit on ONE physical line (`\[...\]', see CLAUDE.md),
;; so without visual wrapping the only way to read a long derivation is to
;; scroll sideways.
(add-hook 'org-mode-hook #'visual-line-mode)

;; -- org-modern: the shapes --------------------------------------------
(when (cerebro-guix-soft-require 'org-modern)
  (setq org-modern-star 'replace     ; one bullet per level, not "***"
        org-modern-hide-stars 'leading
        org-modern-list '((?- . "–") (?+ . "▸") (?* . "•"))
        org-modern-checkbox nil      ; keep [ ]/[X] literal: they are data
        org-modern-table t
        org-modern-block-fringe 4    ; a quiet rule beside #+begin_ blocks
        org-modern-keyword t
        ;; The workflow is defined in cerebro-org.el; this only colours
        ;; it. Keeping the keywords in one alist here means adding a state
        ;; there is one line here, not a face hunt (invariant 3).
        org-modern-todo-faces
        '(("TODO"      :inherit org-todo)
          ("DOING"     :inherit org-todo :weight bold)
          ("DONE"      :inherit org-done)
          ("CANCELLED" :inherit shadow :strike-through t)))
  (global-org-modern-mode 1))

;; -- org-appear: markup that comes back when you need it ---------------
(when (cerebro-guix-soft-require 'org-appear)
  (setq org-appear-autoemphasis t
        org-appear-autolinks t
        ;; Nothing to bring back: `org-appear-autosubmarkers' un-hides a
        ;; subscript that `org-pretty-entities-include-sub-superscripts'
        ;; hid, and that is nil above. Left off so the two settings say
        ;; the same thing.
        org-appear-autosubmarkers nil
        ;; NOT 0.0. org-appear re-checks the element at point from
        ;; `post-command-hook', and a zero delay means every command pays
        ;; for it immediately -- including the ~100 commands a second a
        ;; trackpad generates under `pixel-scroll-precision-mode', in
        ;; none of which point has moved. A short delay lets a burst
        ;; collapse into one check, and is imperceptible when the command
        ;; really was a cursor movement.
        org-appear-delay 0.15))
;; Nothing enables org-appear here. Showing the markup around the word at
;; point is a *writing* affordance, so it is one column of
;; `cerebro-study-modes' (cerebro-study.el) rather than something every
;; Org buffer gets -- see that file for the measurement behind the
;; distinction.

;; -- Code buffers -------------------------------------------------------
;; This repo is also ~3000 lines of Elisp and shell that you edit in the
;; same session as the notes; the rules differ there. (Which of them get
;; line numbers is `cerebro-theme-line-number-modes', next to the rest of
;; the chrome decisions.)

(setq display-line-numbers-width-start t) ; no reflow as you scroll past 99

(show-paren-mode 1)
(setq show-paren-delay 0
      show-paren-context-when-offscreen 'overlay) ; the opening line, in place

;; `hl-todo' highlights the words that mean "unfinished" in comments. It
;; earns its place here for one project-specific reason: `CEREBRO-ISSUE:'
;; markers are a real, load-bearing convention -- `cerebro issue scan'
;; imports them into the committed tracker -- and until now they looked
;; like any other comment text, so the marker you left was invisible until
;; the scan found it.
;;
;; Faces, not hex colours: hl-todo takes either, and a literal `#d3b55f'
;; is a colour picked for one of the two theme variants and wrong in the
;; other. These four are standard Emacs faces that every theme defines --
;; and that modus defines with tested contrast in light *and* dark.
(when (cerebro-guix-soft-require 'hl-todo)
  (setq hl-todo-keyword-faces
        '(("TODO"          . (:inherit (bold warning)))
          ("FIXME"         . (:inherit (bold error)))
          ("NOTE"          . (:inherit (bold success)))
          ("CEREBRO-ISSUE" . (:inherit (bold link)))))
  (global-hl-todo-mode 1))

(provide 'cerebro-appearance)
