;;; cerebro-focus.el --- a reading/writing mode for long prose -*- lexical-binding: t; -*-

;; A maximised Emacs window is 200+ columns wide; a line of mathematical
;; prose is comfortable at 70-90. Left alone, a note is either written in
;; a narrow window (and the rest of the screen wasted) or read as
;; full-width text, where the eye loses the line it was on -- the classic
;; measure problem, and the reason every typeset page has margins.
;;
;; `cerebro-focus-mode' is the answer for one buffer: centre a column of
;; `cerebro-focus-width', and take away everything that is there for
;; *editing* rather than *reading* (the current-line highlight, line
;; numbers, optionally the status line). Prose can also switch to a
;; proportional font while code, tables and inline LaTeX stay monospaced.
;;
;; It is deliberately a toggle, not a default: a note being edited against
;; a PDF or a second note wants the full window, and this project's whole
;; approach is that layout is the user's to choose (see the window rules
;; in cerebro-ui.el).
;;
;; `olivetti' (guix.scm) does the centring properly -- it tracks window
;; splits and resizes -- but the fallback below (buffer-local margins,
;; recomputed on window changes) is a dozen lines and keeps the feature
;; working outside the pinned environment, so the mode never simply
;; refuses.

(require 'cerebro-guix) ;; cerebro-guix-soft-require
(require 'cerebro-theme) ;; the variable-pitch family, if any

(defgroup cerebro-focus nil
  "Distraction-free reading and writing."
  :group 'cerebro)

(defcustom cerebro-focus-width 92
  "Width, in columns, of the centred text column."
  :type 'integer
  :group 'cerebro-focus)

(defcustom cerebro-focus-variable-pitch t
  "Whether focus mode renders prose in the proportional font.
Only applies when a proportional family was actually found (see
`cerebro-theme-font') -- and never to code, tables or verbatim text,
which `mixed-pitch' keeps monospaced. Set to nil if you write heavily
aligned plain-text mathematics, where a fixed advance width is the point."
  :type 'boolean
  :group 'cerebro-focus)

(defcustom cerebro-focus-hide-mode-line nil
  "Whether focus mode also hides the status line."
  :type 'boolean
  :group 'cerebro-focus)

;; Declared at load time, not on first toggle. `cerebro-guix-status' (and
;; `cerebro env') answer "what did this session get?" by reading
;; `featurep', so a package first required when the mode is switched on
;; would be reported as missing until someone happened to press C-c u f --
;; a report that is wrong in the one direction that matters.
(cerebro-guix-soft-require 'olivetti)
(cerebro-guix-soft-require 'mixed-pitch)

(defvar-local cerebro-focus--saved nil
  "Buffer state to restore when focus mode is switched off.")

(defun cerebro-focus-margin (window-width text-width)
  "Columns of margin that centre TEXT-WIDTH inside WINDOW-WIDTH.
Never negative: in a window narrower than the target column the text
simply fills it. Pure, so the arithmetic is testable without a frame."
  (max 0 (/ (- window-width text-width) 2)))

(defun cerebro-focus--apply-margins ()
  "Centre the text with buffer-local margins (the no-olivetti fallback)."
  (when cerebro-focus-mode
    (let ((margin (cerebro-focus-margin (window-total-width) cerebro-focus-width)))
      (set-window-margins nil margin margin))))

(defun cerebro-focus--set-width (enable)
  "Turn the centred column ENABLE on or off, with olivetti or margins."
  (if (cerebro-guix-soft-require 'olivetti)
      (progn
        (setq-local olivetti-body-width cerebro-focus-width)
        (olivetti-mode (if enable 1 -1)))
    (if enable
        (progn
          (add-hook 'window-configuration-change-hook
                    #'cerebro-focus--apply-margins nil t)
          (cerebro-focus--apply-margins))
      (remove-hook 'window-configuration-change-hook
                   #'cerebro-focus--apply-margins t)
      (set-window-margins nil 0 0))))

(defun cerebro-focus--set-pitch (enable)
  "Turn proportional prose ENABLE on or off, if a proportional font exists."
  (when (and cerebro-focus-variable-pitch (cerebro-theme-font 'variable))
    (cond
     ;; mixed-pitch is the one that knows which faces must stay
     ;; monospaced (org tables, src blocks, verbatim, LaTeX fragments).
     ((cerebro-guix-soft-require 'mixed-pitch)
      (mixed-pitch-mode (if enable 1 -1)))
     ;; Without it, only switch whole-buffer prose in modes that have no
     ;; alignment to lose. In org that would shear tables, so it is
     ;; skipped rather than approximated.
     ((derived-mode-p 'text-mode)
      (variable-pitch-mode (if enable 1 -1))))))

;;;###autoload
(define-minor-mode cerebro-focus-mode
  "Centre this buffer's text and strip the editing chrome.
Toggling it off restores exactly what was on before -- the mode records
the previous state of each thing it changes instead of assuming defaults."
  :lighter nil
  :group 'cerebro-focus
  (if cerebro-focus-mode
      (progn
        (setq cerebro-focus--saved
              (list (cons 'hl-line (bound-and-true-p hl-line-mode))
                    (cons 'line-numbers (bound-and-true-p display-line-numbers-mode))
                    (cons 'mode-line mode-line-format)))
        (when (bound-and-true-p hl-line-mode) (hl-line-mode -1))
        (when (bound-and-true-p display-line-numbers-mode) (display-line-numbers-mode -1))
        (when cerebro-focus-hide-mode-line (setq mode-line-format nil))
        (cerebro-focus--set-width t)
        (cerebro-focus--set-pitch t))
    (cerebro-focus--set-width nil)
    (cerebro-focus--set-pitch nil)
    (when (alist-get 'hl-line cerebro-focus--saved) (hl-line-mode 1))
    (when (alist-get 'line-numbers cerebro-focus--saved) (display-line-numbers-mode 1))
    (when cerebro-focus-hide-mode-line
      (setq mode-line-format (alist-get 'mode-line cerebro-focus--saved)))
    (setq cerebro-focus--saved nil))
  (force-mode-line-update))

(provide 'cerebro-focus)
