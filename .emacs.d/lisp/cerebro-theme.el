;;; cerebro-theme.el --- colour and typography, as data -*- lexical-binding: t; -*-

;; What the editor *looks* like, kept in one place and expressed as data:
;; two theme variants, one table of font candidates per role, one table of
;; heading sizes, one list of palette overrides. Changing the look means
;; changing a datum here -- never a face override scattered across the
;; modules (invariant 3).
;;
;; Three decisions worth stating, because they are the reason this file is
;; short:
;;
;;   1. The theme is `modus-operandi'/`modus-vivendi', which ship *inside
;;      Emacs* (since 28) -- no guix.scm line, no pinning, no bit-rot, and
;;      they are the only widely used themes designed to meet WCAG AAA
;;      contrast. A second brain is read for decades; legibility is not a
;;      matter of taste here.
;;   2. Fonts are a *preference list*, not a setting. A hardcoded family
;;      is a config that breaks on the next machine (or the next year);
;;      `cerebro-theme-font-families' lists candidates per role and the
;;      first one actually installed wins. If none is, Emacs keeps its
;;      default and nothing errors -- same degradation policy as the
;;      optional guix packages.
;;   3. One number drives scale. `cerebro-theme-font-size' sets the body
;;      size; heading sizes are factors of it, and anything else that must
;;      follow (the LaTeX preview scale, cerebro-preview.el) hangs off
;;      `cerebro-theme-after-apply-hook' instead of reading faces.
;;
;; Pure Emacs core: this module must work outside the pinned environment,
;; since a broken theme would be the most visible possible failure.

(require 'seq)
(require 'cerebro-guix) ;; cerebro-guix-soft-require (spacious-padding is optional)

(defgroup cerebro-theme nil
  "Colour and typography for the cerebro editor."
  :group 'cerebro)

;; -- The two variants ---------------------------------------------------
;; Dark by default because notes are read at length and mostly at night,
;; but the pair is deliberate: `cerebro-theme-toggle' (C-c u t) switches
;; to the light one for a bright room or a projector, and the two are
;; palette-compatible, so every face keeps its meaning.
(defconst cerebro-theme-variants
  '(;; The hermetic pair, and the default: ink and aged paper. `ef-autumn'
    ;; is warm browns and golds on near-black -- iron gall ink by
    ;; candlelight; `ef-eagle' is the sepia parchment side of the same
    ;; register. Chosen to sit under the engraving on the start page
    ;; rather than fight it.
    (hermes       . ef-autumn)
    (hermes-light . ef-eagle)
    ;; The pastel pair: coloured, cooler, no particular period.
    (pastel       . ef-dream)
    (pastel-light . ef-spring)
    ;; The two that ship *inside* Emacs, and therefore the floor: these
    ;; are what you get when ef-themes is not installed.
    (dark   . modus-vivendi)
    (light  . modus-operandi))
  "Map of variant name -> Emacs theme, the only place a theme is named.
`dark'/`light' ship inside Emacs; the hermetic and pastel pairs need
ef-themes (guix.scm), and `cerebro-theme-apply' falls back to the dark
built-in when it is absent rather than leaving you with no theme at all.")

(defcustom cerebro-theme-variant 'hermes
  "Which entry of `cerebro-theme-variants' is active."
  :type '(choice (const hermes) (const hermes-light)
                 (const pastel) (const pastel-light)
                 (const dark) (const light))
  :group 'cerebro-theme)

(defcustom cerebro-theme-pairs
  '((hermes . hermes-light) (hermes-light . hermes)
    (dark . light) (light . dark)
    (pastel . pastel-light) (pastel-light . pastel))
  "Which variant `cerebro-theme-toggle' switches to, from each one.
A pair, not a cycle: the toggle is for the room you are in (a bright
one, a dark one), so it moves between the light and dark version of the
look you chose -- it does not walk you through every theme installed."
  :type '(alist :key-type symbol :value-type symbol)
  :group 'cerebro-theme)

(defcustom cerebro-theme-font-size 120
  "Body text size in 1/10 pt (120 = 12pt), the one number scale derives from."
  :type 'integer
  :group 'cerebro-theme)

(defvar cerebro-theme-after-apply-hook nil
  "Run after the theme, fonts and faces have been (re)applied.
The seam for anything that caches something colour- or size-dependent --
LaTeX previews are rendered at the body size and in the foreground colour
of the active theme, so cerebro-preview.el refreshes them from here
rather than this module knowing that previews exist.")

;; -- Typography ---------------------------------------------------------
;; Roles, not families. `mono' is the body font (code, math source, notes:
;; alignment matters in a file full of \(...\)); `variable' is for prose
;; in focus mode and for headings; `serif' is unused by default and left
;; as a hook for anyone who wants a book-like reading mode.
;;
;; The lists go from "best for this job" to "certainly present": the last
;; entry of each is a generic family Emacs resolves everywhere, so the
;; worst case is the default font, never a missing-font error.
(defconst cerebro-theme-font-families
  '((mono     "JetBrainsMono Nerd Font" "JetBrains Mono" "Iosevka"
              "Fira Code" "Source Code Pro" "DejaVu Sans Mono"
              "Liberation Mono" "Monospace")
    (variable "Adwaita Sans" "IBM Plex Sans" "Source Sans Pro" "Cantarell"
              "Noto Sans" "DejaVu Sans" "Liberation Sans" "Sans Serif")
    (serif    "Libertinus Serif" "IBM Plex Serif" "Source Serif 4"
              "Noto Serif" "DejaVu Serif" "Liberation Serif" "Serif"))
  "Ordered font candidates per role; the first installed family wins.")

(defun cerebro-theme-pick-font (candidates available)
  "First family of CANDIDATES present in AVAILABLE, or nil.
Split out from `cerebro-theme-font' so the choice is a pure function of
two lists -- unit-testable without a window system, where no font exists
at all."
  (seq-find (lambda (family) (member family available)) candidates))

(defun cerebro-theme-available-fonts ()
  "Font families this Emacs can actually use, or nil in batch/tty.
`font-family-list' needs a display; on a terminal frame it returns nil
and every role then resolves to nil, which is exactly right: leave the
terminal's own font alone."
  (and (display-graphic-p) (font-family-list)))

(defun cerebro-theme-font (role &optional available)
  "The family chosen for ROLE (`mono', `variable', `serif'), or nil."
  (cerebro-theme-pick-font
   (cdr (assq role cerebro-theme-font-families))
   (or available (cerebro-theme-available-fonts))))

;; -- Headings -----------------------------------------------------------
;; Factors of the body size, not absolute sizes, so the whole hierarchy
;; follows `cerebro-theme-font-size'. Kept shallow on purpose: a note is a
;; mathematical text, and a section title three times the body size is
;; decoration, not structure. Levels beyond 4 stay at body size.
(defconst cerebro-theme-heading-scale
  '((1 . 1.30) (2 . 1.20) (3 . 1.10) (4 . 1.05))
  "Alist of Org/outline heading level -> height factor.")

(defun cerebro-theme-heading-spec (&optional variable-font)
  "Build the `modus-themes-headings' value from `cerebro-theme-heading-scale'.
With VARIABLE-FONT non-nil the headings also switch to the proportional
family -- only requested when one was actually found, since asking for
`variable-pitch' with no proportional font installed just renders the
heading in the default font at the wrong weight."
  (append
   (mapcar (lambda (cell)
             (cons (car cell)
                   (append (when variable-font '(variable-pitch))
                           (list 'semibold (cdr cell)))))
           cerebro-theme-heading-scale)
   ;; Everything deeper: same size as the body, still distinguishable by
   ;; weight and colour.
   '((t . (semibold 1.0)))))

;; -- Palette overrides --------------------------------------------------
;; The minimalist half of "beautiful": remove the boxes, borders and
;; stripes Emacs draws by default, so the *text* is the only thing with
;; contrast. Each entry is one visual decision.
(defconst cerebro-theme-palette-overrides
  '(;; A modeline that is a line of text, not a raised 3D button: no box
    ;; border, and a background barely distinct from the buffer.
    (border-mode-line-active unspecified)
    (border-mode-line-inactive unspecified)
    ;; The fringe is structural whitespace here (no flycheck, no diff
    ;; markers in the margin); tinting it just draws two vertical stripes.
    (fringe unspecified)
    ;; Line numbers exist for code, not for prose: same background as the
    ;; buffer, and the inactive ones dimmed well below the text.
    (bg-line-number-active unspecified)
    (bg-line-number-inactive unspecified)
    (fg-line-number-inactive "gray45")
    ;; Comments are half the content in this repo's Elisp -- readable, not
    ;; shouting.
    (comment fg-dim))
  "Modus palette overrides; see `modus-themes-common-palette-overrides'.")

;; -- Applying it --------------------------------------------------------

(defun cerebro-theme--configure-modus ()
  "Set the modus options that must exist *before* the theme is loaded.
Modus reads its options at load-theme time, so ordering matters: setting
them afterwards is a silent no-op until the next reload."
  (let ((variable-font (cerebro-theme-font 'variable)))
    ;; `mixed-fonts' is what makes a proportional heading safe: code
    ;; blocks, tables and inline verbatim stay monospaced, so an aligned
    ;; matrix or a #+begin_src block does not shear.
    (dolist (cell `((modus-themes-mixed-fonts . t)
                    (modus-themes-italic-constructs . t)
                    (modus-themes-bold-constructs . nil)
                    ;; The minibuffer and the modeline keep the fixed
                    ;; font: they are dense, aligned UI, not prose.
                    (modus-themes-variable-pitch-ui . nil)
                    (modus-themes-completions . ((matches . (extrabold))
                                                 (selection . (semibold))))
                    (modus-themes-prompts . (bold))
                    (modus-themes-headings . ,(cerebro-theme-heading-spec variable-font))
                    (modus-themes-common-palette-overrides
                     . ,cerebro-theme-palette-overrides)
                    (modus-themes-to-toggle . (modus-operandi modus-vivendi))))
      ;; `boundp' guard: these are defined by the theme library, which is
      ;; only loaded on the first `load-theme'. Setting an option modus
      ;; ever renames must not break startup.
      (when (or (boundp (car cell)) (not (featurep 'modus-themes)))
        (set (car cell) (cdr cell))))))

(defun cerebro-theme--configure-ef ()
  "The same decisions, for the ef-themes variants.

Every option above is named `modus-themes-...' and therefore did nothing
at all under `hermes' or `pastel' -- which are ef-themes. So four of the
five variants had no heading scale and, worse, no `mixed-fonts': a
proportional heading font applied to *everything*, shearing Org tables
and aligned mathematics. ef-themes exposes the same two decisions under
its own names, and this is them, so the look does not depend on which
family the chosen variant happens to come from.

Guarded exactly like the modus half: an option this ef-themes does not
define is skipped, never an error at startup."
  (let ((variable-font (cerebro-theme-font 'variable)))
    (dolist (cell `((ef-themes-mixed-fonts . t)
                    (ef-themes-variable-pitch-ui . nil)
                    (ef-themes-headings . ,(cerebro-theme-heading-spec variable-font))
                    (ef-themes-to-toggle . (ef-autumn ef-eagle))))
      (when (or (boundp (car cell)) (not (featurep 'ef-themes)))
        (set (car cell) (cdr cell))))))

(defun cerebro-theme--apply-fonts (&optional frame)
  "Set the default/fixed/variable faces from `cerebro-theme-font-families'.
Does nothing without a window system (a terminal has one font, chosen by
the terminal). FRAME defaults to all frames, so this also serves as an
`after-make-frame-functions' hook for the daemon case, where the first
frame appears long after startup."
  (let* ((available (and (or (null frame) (display-graphic-p frame))
                         (cerebro-theme-available-fonts)))
         (mono (cerebro-theme-font 'mono available))
         (variable (cerebro-theme-font 'variable available)))
    (when mono
      (set-face-attribute 'default frame
                          :family mono :height cerebro-theme-font-size)
      ;; fixed-pitch must track the body font, or `modus-themes-mixed-fonts'
      ;; renders code blocks in a *different* monospace family.
      (set-face-attribute 'fixed-pitch frame :family mono :height 1.0))
    (when variable
      (set-face-attribute 'variable-pitch frame :family variable :height 1.0))))

;;;###autoload
(defun cerebro-theme-apply (&optional variant)
  "Load VARIANT (default `cerebro-theme-variant') with cerebro's settings.
The single entry point: it disables whatever theme was active first, so
switching never leaves two palettes half-applied, and runs
`cerebro-theme-after-apply-hook' when everything is in place."
  (interactive)
  (let* ((variant (or variant cerebro-theme-variant))
         (theme (or (cdr (assq variant cerebro-theme-variants))
                    (user-error "cerebro-theme: unknown variant `%s'" variant))))
    ;; A variant from a package (the hermetic and pastel pairs) is only
    ;; loadable if the package is here. Falling back to the built-in dark
    ;; theme is the right failure: a config that refuses to start because
    ;; a *colour scheme* is missing would be the silliest possible way to
    ;; lose an editor.
    (unless (memq theme (custom-available-themes))
      (setq theme (cdr (assq 'dark cerebro-theme-variants))
            variant 'dark))
    (mapc #'disable-theme custom-enabled-themes)
    ;; Both families, unconditionally: each function only sets options its
    ;; own package defines, and the variant that is about to load reads
    ;; whichever set belongs to it. Configuring only the family we think
    ;; we are loading is how the ef variants ended up unconfigured.
    (cerebro-theme--configure-modus)
    (cerebro-theme--configure-ef)
    (load-theme theme t)
    (setq cerebro-theme-variant variant)
    (cerebro-theme--apply-fonts)
    (run-hooks 'cerebro-theme-after-apply-hook)))

(defun cerebro-theme-other-variant (&optional variant)
  "The variant `cerebro-theme-toggle' would switch VARIANT to."
  (let ((variant (or variant cerebro-theme-variant)))
    (or (cdr (assq variant cerebro-theme-pairs))
        (if (eq variant 'dark) 'light 'dark))))

;;;###autoload
(defun cerebro-theme-choose (variant)
  "Load VARIANT, completing over every one this Emacs can actually load."
  (interactive
   (list (intern (completing-read
                  "Look: "
                  (mapcar (lambda (cell) (symbol-name (car cell)))
                          (seq-filter (lambda (cell)
                                        (memq (cdr cell) (custom-available-themes)))
                                      cerebro-theme-variants))
                  nil t))))
  (cerebro-theme-apply variant))

;; -- Icons --------------------------------------------------------------
;; Nerd Fonts put a few thousand glyphs (file types, git states, tools)
;; into the private-use area of a normal monospace font. That makes icons
;; *text*: they render in a terminal frame, they scale with the font, and
;; they cost no image support. But they are only there if such a font is
;; installed, and a missing glyph is a visible box -- so nothing turns
;; icons on until both the font and the package are present.

(defconst cerebro-theme-nerd-fonts
  '("Symbols Nerd Font Mono" "JetBrainsMono Nerd Font" "FiraCode Nerd Font"
    "Iosevka Nerd Font" "Hack Nerd Font" "BlexMono Nerd Font")
  "Fonts that carry the Nerd Font glyph range, best first.")

(defun cerebro-theme-nerd-font ()
  "The installed Nerd Font, or nil."
  (cerebro-theme-pick-font cerebro-theme-nerd-fonts (cerebro-theme-available-fonts)))

(defun cerebro-theme-nerd-icons-p ()
  "Non-nil when icons can be drawn: the package *and* a font for them."
  (and (featurep 'nerd-icons) (cerebro-theme-nerd-font) t))

(cerebro-guix-soft-require 'ef-themes) ;; the pastel pair, if it is here

(when (cerebro-guix-soft-require 'nerd-icons)
  (when-let* ((font (cerebro-theme-nerd-font)))
    (setq nerd-icons-font-family font)))

;;;###autoload
(defun cerebro-theme-toggle ()
  "Switch between the dark and the light variant."
  (interactive)
  (cerebro-theme-apply (cerebro-theme-other-variant))
  (message "cerebro: %s theme" cerebro-theme-variant))

;;;###autoload
(defun cerebro-theme-set-font-size (size)
  "Set the body font size to SIZE (in 1/10 pt) everywhere.
Unlike `text-scale-adjust' this is global and persistent for the session:
it moves headings, previews and every window at once, which is what you
want when the screen changes (a projector, a second monitor), not when
one buffer needs a closer look."
  (interactive (list (read-number "Body size (1/10 pt): " cerebro-theme-font-size)))
  (setq cerebro-theme-font-size (max 60 (min 400 size)))
  (cerebro-theme-apply))

;;;###autoload
(defun cerebro-theme-increase-font-size ()
  "Make the body text one point bigger (headings and previews follow)."
  (interactive)
  (cerebro-theme-set-font-size (+ cerebro-theme-font-size 10)))

;;;###autoload
(defun cerebro-theme-decrease-font-size ()
  "Make the body text one point smaller (headings and previews follow)."
  (interactive)
  (cerebro-theme-set-font-size (- cerebro-theme-font-size 10)))

;; -- Frame chrome -------------------------------------------------------
;; Everything that is not text, turned off or quieted. The toolbar and
;; menubar are discoverability aids for an editor you use occasionally --
;; this one is used every day, and `M-x' plus which-key cover discovery
;; without spending a centimetre of vertical space forever.
(menu-bar-mode -1)
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))
(when (fboundp 'horizontal-scroll-bar-mode) (horizontal-scroll-bar-mode -1))

(setq inhibit-startup-screen t
      initial-scratch-message nil
      ;; The frame is titled by what you are actually looking at, plus
      ;; whether this Emacs is the pinned one -- the same question
      ;; `cerebro-guix-status' answers, visible without asking.
      frame-title-format '("cerebro · " (:eval (buffer-name))
                           (:eval (if (getenv "GUIX_ENVIRONMENT") "" " [host]")))
      ;; Frames are resized in pixels: with an internal border and a
      ;; proportional font, character-cell resizing leaves a ragged edge.
      frame-resize-pixelwise t
      window-resize-pixelwise t)

;; Breathing room. `spacious-padding' (guix.scm) does this properly --
;; it re-derives the padding faces on every theme change -- but the
;; effect is mostly `internal-border-width' + fringes, so the degraded
;; path below is nearly as good and needs nothing.
(defconst cerebro-theme-frame-padding 12
  "Pixels of empty space between the frame edge and the text.")

(defun cerebro-theme--apply-padding ()
  (if (and (cerebro-guix-soft-require 'spacious-padding)
           (fboundp 'spacious-padding-mode))
      (progn
        (setq spacious-padding-widths
              `( :internal-border-width ,cerebro-theme-frame-padding
                 :header-line-width 4
                 :mode-line-width 4
                 :tab-width 4
                 :right-divider-width 20
                 :scroll-bar-width 8
                 :fringe-width 8))
        (spacious-padding-mode 1))
    (add-to-list 'default-frame-alist
                 (cons 'internal-border-width cerebro-theme-frame-padding))
    (dolist (frame (frame-list))
      (set-frame-parameter frame 'internal-border-width
                           cerebro-theme-frame-padding))
    ;; A left fringe still marks continued lines and images; the right one
    ;; carries nothing in this config.
    (when (fboundp 'fringe-mode) (fringe-mode '(8 . 0)))))

;; Window dividers instead of the default hairline: with a padded frame,
;; two side-by-side notes need a visible-but-quiet seam.
(setq window-divider-default-places t
      window-divider-default-right-width 1
      window-divider-default-bottom-width 1)
(when (fboundp 'window-divider-mode) (window-divider-mode 1))

;; -- The cursor ---------------------------------------------------------
;; A bar that does not blink, because blinking is motion in the corner of
;; the eye while reading a proof, and a bar sits *between* characters,
;; which reads as "insert here" rather than covering the glyph.
;;
;; Both of those are still true and both nearly cost the cursor. It was
;; `bar' -- one pixel wide -- and not blinking, so it had no width and no
;; motion; `global-hl-line-mode' puts a background under the line it is
;; on; and the cursor's *colour* comes from whichever theme is loaded. On
;; the palette this configuration defaults to, those four facts add up to
;; a cursor you cannot find. Reported, and reproduced from the settings.
;;
;; The two decisions that fix it, and neither gives up the reasoning
;; above:
;;
;;   - width. A three-pixel bar is still between characters and still
;;     does not cover the glyph; it is simply visible. One pixel was
;;     never a considered number, it was the default of `bar'.
;;   - colour. `cerebro-theme-cursor-follows-text' paints the cursor in
;;     the *body text* colour, which is the one colour guaranteed to
;;     contrast with the background -- that is what makes it text -- and
;;     which every theme also keeps readable against its own hl-line.
;;     So the cursor is visible by construction rather than by whichever
;;     accent the theme happened to choose, in every variant, including
;;     ones added later.

(defcustom cerebro-theme-cursor-type '(bar . 3)
  "Shape of the insertion cursor.

`(bar . N)' is an N-pixel vertical bar; plain `bar' is one pixel, which
is what made it disappear. `box' covers the glyph and is the most
visible of all -- worth setting on a very dense screen, at the cost of
hiding the character you are on."
  :type '(choice (const :tag "Thin bar (1px)" bar)
                 (cons :tag "Bar, N pixels wide" (const bar) integer)
                 (const :tag "Box over the glyph" box)
                 (const :tag "Underline" hbar))
  :group 'cerebro-theme)

(defcustom cerebro-theme-cursor-follows-text t
  "Whether the cursor takes the colour of the body text.

The point is contrast that cannot depend on the theme: the foreground
colour is readable on the background by definition, and readable on the
current-line highlight because themes are built that way. A theme's own
`cursor' colour is an accent, chosen to look right, not to be found."
  :type 'boolean
  :group 'cerebro-theme)

(defun cerebro-theme--apply-cursor ()
  "Set the cursor's shape and, optionally, its colour.

Hung on `cerebro-theme-after-apply-hook' rather than run once: `cursor'
is a *face*, so every `load-theme' replaces it, and a colour set at
startup would quietly go back to the theme's own at the first `C-c u t'."
  (setq-default cursor-type cerebro-theme-cursor-type)
  (when (and cerebro-theme-cursor-follows-text (display-graphic-p))
    (when-let* ((fg (face-attribute 'default :foreground nil t)))
      (unless (eq fg 'unspecified)
        (set-face-attribute 'cursor nil :background fg)))))

(blink-cursor-mode -1)
(setq x-stretch-cursor nil)
(cerebro-theme--apply-cursor)
(add-hook 'cerebro-theme-after-apply-hook #'cerebro-theme--apply-cursor)

;; Reading comfort in every buffer: a little air between lines (dense
;; mathematical prose is unreadable at Emacs' default leading), smooth
;; scrolling, and no line wrapping surprises.
(setq-default line-spacing 0.15)
(global-hl-line-mode 1)
(setq-default truncate-lines nil)
;; `scroll-margin' is 0, and that is a fix rather than a preference.
;;
;; A margin asks redisplay to keep point some lines away from the window
;; edge. Under `pixel-scroll-precision-mode' a gesture moves the window
;; by *sub-line* amounts, and each time the scroll brings point within
;; the margin redisplay corrects it by pulling the window back -- so a
;; steady downward scroll occasionally jumps upwards. Measured, scrolling
;; a real note in a graphical frame, 240 sub-line steps:
;;
;;     scroll-margin 3    6 backwards jumps
;;     scroll-margin 0    0
;;
;; and every other candidate left it at 6: `scroll-conservatively',
;; `scroll-preserve-screen-position', `global-hl-line-mode', and
;; `line-spacing' (fractional or not). Stock `emacs -Q' -- which has no
;; margin -- shows none at all, which is what said the fault was here and
;; not upstream.
;;
;; The margin is worth something when moving by keyboard, and nothing
;; like enough to pay for that: a window that walks backwards while you
;; read is the most distracting thing an editor can do.
(setq scroll-conservatively 101      ; scroll a line at a time, never recentre
      scroll-margin 0
      scroll-preserve-screen-position t)
(when (fboundp 'pixel-scroll-precision-mode)
  (pixel-scroll-precision-mode 1))

;; Redisplay under a trackpad, and one setting rather than four -- the
;; other three were removed, having caused the problem they were meant to
;; solve.
;;
;; `fast-but-imprecise-scrolling', `redisplay-skip-fontification-on-input'
;; and `jit-lock-defer-time' were added here to make scrolling cheaper.
;; Read together, all three do the *same* thing: they let redisplay draw
;; text before it has been fontified and repaint it a moment later. On a
;; keypress that is invisible. Under a trackpad -- a continuous stream of
;; input events, so "input is pending" is true for the whole gesture --
;; it is a continuous stream of repaints: text appears unstyled, then
;; recolours, forty times a second. That is exactly what "flickering
;; while scrolling" is, and it was self-inflicted.
;;
;; They also bought nothing. The measured cost of scrolling a note was
;; never fontification: it was the point-following modes asking
;; `org-element-context' on every command (~4ms each, ~100 commands a
;; second), which is fixed in cerebro-study.el by not running them while
;; reading. These four were measured *after* that change and moved
;; nothing -- which was recorded here at the time and should have been
;; read as "so remove them" rather than "so keep them".
;;
;; What is left is the one that defers no drawing: `auto-window-vscroll'
;; makes Emacs compute a per-line vertical scroll position it does not
;; need here, and turning it off costs nothing and changes nothing about
;; when pixels are painted.
;;
;; The rule this leaves behind: a redisplay setting whose mechanism is
;; "draw now, correct later" does not belong in a config for reading
;; mathematics. Smooth means every frame is right, not that frames are
;; cheap.
(setq auto-window-vscroll nil)

;; -- Watching the window jump -------------------------------------------
;; "I scroll down and every so often it goes back up" is a report about
;; *window-start* moving backwards, and the useful question is what moved
;; it. Five experiments in a real graphical frame under Xvfb -- with and
;; without rendered formulas, with `scroll-margin' at 3 and at 0, and
;; with a keystroke after the gesture -- failed to reproduce it here, so
;; rather than guess again this makes the thing observable in the session
;; where it actually happens.
;;
;; It records every backwards move of `window-start' together with the
;; command that was running, which is the pair that identifies the cause:
;; a scroll command doing it means a pixel-scroll problem, any other
;; command means something is pulling the window back to point.

(defvar cerebro-scroll-trace-log nil
  "Backwards `window-start' movements, newest first: (COMMAND FROM TO).")

(defvar cerebro-scroll--last-start nil)

(defun cerebro-scroll--watch ()
  "Record a backwards jump of `window-start' in this window."
  (when (eq (window-buffer) (current-buffer))
    (let ((start (window-start)))
      (when (and cerebro-scroll--last-start (< start cerebro-scroll--last-start))
        (push (list this-command cerebro-scroll--last-start start)
              cerebro-scroll-trace-log))
      (setq cerebro-scroll--last-start start))))

;;;###autoload
(define-minor-mode cerebro-scroll-trace-mode
  "Log every backwards jump of the window while scrolling.

Turn it on, scroll until it misbehaves, then `M-x
cerebro-scroll-trace-report'. What you want from the report is the
command column: a `pixel-scroll-...' there means the scrolling itself is
at fault; anything else -- a self-insert, a timer's command, an Org
function -- means that command is pulling the window back to point, and
names the culprit.

Read the log knowing what it cannot tell apart: scrolling *up* moves
`window-start' backwards legitimately, and is recorded like anything
else. The signal is a backwards move that breaks the sequence -- one
entry out of order in an otherwise monotonic run -- which is exactly how
the `scroll-margin' fault above was found."
  :global t
  :group 'cerebro-theme
  (if cerebro-scroll-trace-mode
      (progn (setq cerebro-scroll-trace-log nil
                   cerebro-scroll--last-start nil)
             (add-hook 'post-command-hook #'cerebro-scroll--watch))
    (remove-hook 'post-command-hook #'cerebro-scroll--watch)))

;;;###autoload
(defun cerebro-scroll-trace-report ()
  "Show what has been pulling the window backwards (`cerebro-scroll-trace-mode')."
  (interactive)
  (cerebro-report
   (format "Backwards window jumps (%d)" (length cerebro-scroll-trace-log))
   (or (mapcar (lambda (row)
                 (format "%-38s %8d -> %8d" (car row) (nth 1 row) (nth 2 row)))
               cerebro-scroll-trace-log)
       (list "nothing recorded -- is cerebro-scroll-trace-mode on?"))
   #'identity "*cerebro-scroll*"))

;; Line numbers where they are information (code, LaTeX sources) and
;; nowhere else -- a note is prose, and a column of grey digits next to a
;; theorem is pure noise. Data: add a mode, get the numbers.
(defconst cerebro-theme-line-number-modes
  '(emacs-lisp-mode-hook lisp-data-mode-hook sh-mode-hook
    latex-mode-hook tex-mode-hook conf-mode-hook scheme-mode-hook)
  "Mode hooks that get `display-line-numbers-mode'.")

(dolist (hook cerebro-theme-line-number-modes)
  (add-hook hook #'display-line-numbers-mode))

(cerebro-theme--apply-padding)
(cerebro-theme-apply)

;; The daemon (bin/cerebro starts one) creates its first *graphical* frame
;; long after this file runs, when `font-family-list' finally has answers.
(add-hook 'after-make-frame-functions #'cerebro-theme--apply-fonts)

(provide 'cerebro-theme)
