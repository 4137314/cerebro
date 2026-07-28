;;; cerebro-appearance.el --- a lighter look, no heavy plugins -*- lexical-binding: t; -*-

;; Everything here is built into Emacs itself (modus-themes have shipped
;; in Emacs core since 28; hl-line, prettify-symbols and Org's own
;; org-pretty-entities need nothing external either) -- no new package
;; in guix.scm just to make the editor nicer to look at.

(load-theme 'modus-vivendi t)

(menu-bar-mode -1)
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))
(global-hl-line-mode 1)
(setq-default line-spacing 0.15)
(setq inhibit-startup-screen t)

;; Math-heavy notes read better with entities/sub/superscripts rendered
;; directly (e.g. \alpha, x_1) instead of shown as raw markup -- built
;; into Org, not a plugin.
(setq org-pretty-entities t)
(setq org-pretty-entities-include-sub-superscripts t)
(setq org-ellipsis " ▾") ; "..." -> a small triangle, less noisy
(setq org-hide-leading-stars t)

;; Not enabled by default here since it's a matter of taste for
;; math-heavy prose (alignment in in-line calculations can matter):
;;   (add-hook 'org-mode-hook #'variable-pitch-mode)

(provide 'cerebro-appearance)
