;;; cerebro-guix.el --- the pinned environment, visible from inside Emacs -*- lexical-binding: t; -*-

;; The whole point of guix.scm + guix/channels.scm is that the editor,
;; the note graph and the LaTeX toolchain are one pinned, reproducible
;; set. From *inside* Emacs that was invisible: nothing told you whether
;; the session you are typing in came out of the pinned profile or off
;; the host's PATH -- and the two behave very differently (org-roam,
;; org-ql, org-drill, aspell, latexmk and the UI packages only exist in
;; the former). "Why is C-c n f undefined today?" should be answerable
;; without reading three shell scripts.
;;
;; So this module makes the environment observable and drivable:
;;
;;   - `cerebro-guix-status' (C-c G s) answers "what am I inside, at
;;     which pin, and what is missing?" in one buffer;
;;   - `cerebro-guix-soft-require' is the *single* way the optional
;;     modules (cerebro-complete/ui/vc/dashboard) pull a package that
;;     comes from guix.scm, so an absent package is recorded as one datum
;;     instead of breaking a whole module (invariant 4: modules stay
;;     independently loadable);
;;   - the commands are thin wrappers over the CLI that already exists
;;     (bin/guix-run, guix describe), never a second implementation of
;;     "materialise the environment" or "re-pin the channels".
;;
;; Pure Elisp on Emacs core, deliberately: this module has to work
;; *outside* the guix environment, since that is exactly the situation it
;; exists to explain. It fetches nothing and starts no process at load.

(require 'cerebro-org) ;; cerebro-root, cerebro-report
(require 'compile)     ;; the guix commands report into a compilation buffer

;; -- What the pinned profile is supposed to provide ---------------------
;; Data, not code paths (invariant 3): adding an Emacs package to guix.scm
;; means adding one line here, and it automatically shows up in the status
;; report, in the dashboard's package count, and in the warning printed
;; when the editor starts outside the environment.
(defconst cerebro-guix-optional-packages
  '((org-roam      . "note graph: capture, backlinks, the .org-roam.db (C-c n)")
    (org-ql        . "content/metadata queries and saved views (C-c v)")
    (org-drill     . "spaced repetition over :drill: headings")
    (vertico       . "vertical minibuffer completion")
    (orderless     . "space-separated, order-free matching")
    (marginalia    . "annotations next to completion candidates")
    (consult       . "live search/jump commands (M-s, M-g, C-x b)")
    (dashboard     . "the startup dashboard (C-c h)")
    (dired-sidebar . "the file tree sidebar (C-c t)")
    (dired-subtree . "expandable directories inside dired (TAB)")
    (magit         . "git porcelain for the notes repo (C-c g)")
    ;; The editing surface: how a note looks and reads (cerebro-theme.el,
    ;; -appearance.el, -focus.el, -preview.el, -complete.el, -ui.el).
    ;; Every one of them is a display or input affordance -- absent, the
    ;; note still opens, exports and lints exactly the same.
    (spacious-padding . "space between the text and the frame edge")
    (org-modern       . "headings, bullets, blocks and tags as shapes")
    (org-appear       . "hidden emphasis markers reappear at point")
    (org-fragtog      . "the formula at point turns back into source (C-c u l)")
    (olivetti         . "the centred reading column (C-c u f)")
    (mixed-pitch      . "proportional prose, monospace tables and code")
    (corfu            . "completion popup inside the buffer")
    (cape             . "what that popup can complete (words, paths, symbols)")
    (pulsar           . "the line you landed on lights up briefly")
    (avy              . "jump to any visible character (C-c j)")
    (hl-todo          . "TODO/FIXME/CEREBRO-ISSUE markers stand out in code")
    (pdf-tools        . "the compiled PDF, read inside Emacs (C-c e v)")
    ;; A modern editing surface (cerebro-code.el, -theme.el, -dashboard.el)
    (ef-themes        . "the pastel theme pair (C-c u c)")
    (nerd-icons       . "icons as font glyphs -- needs a Nerd Font too")
    (nerd-icons-completion . "...in the minibuffer")
    (nerd-icons-corfu . "...in the completion popup")
    (nerd-icons-dired . "...in the file tree")
    (tempel           . "templates through the completion popup")
    (tempel-collection . "templates for languages this repo does not write")
    (apheleia         . "format code on save, in a subprocess")
    (indent-bars      . "indentation made visible, in code only"))
  "Every Emacs package cerebro takes from guix.scm, and what it buys.
The feature symbol is what `require' wants; `dired-subtree' comes from
the emacs-dired-hacks package rather than one of its own, which is why
this maps *features* (what Emacs can check with `featurep') and not
package names.")

(defvar cerebro-guix-missing-packages nil
  "Features from `cerebro-guix-optional-packages' that failed to load.
Filled in by `cerebro-guix-soft-require' as the optional modules load;
empty on the normal path (inside the pinned environment).")

(defun cerebro-guix-soft-require (feature)
  "Load FEATURE if the environment provides it; return non-nil on success.
On failure record it in `cerebro-guix-missing-packages' and return nil,
so the caller can configure what it got and skip what it didn't. This is
the one place that decides what \"a guix.scm package is missing\" means:
never an error, always a datum the status report can show."
  (if (require feature nil t)
      feature
    (unless (memq feature cerebro-guix-missing-packages)
      (push feature cerebro-guix-missing-packages))
    nil))

;; -- Where am I running? -----------------------------------------------

(defun cerebro-guix-profile ()
  "The `guix shell' profile this Emacs runs in, or nil if there is none.
`guix shell' sets GUIX_ENVIRONMENT to the profile it built -- the one
honest, zero-cost signal that we are inside the pinned set rather than on
the host's PATH."
  (getenv "GUIX_ENVIRONMENT"))

(defun cerebro-guix-inside-p ()
  "Non-nil when this Emacs is running inside a `guix shell' profile."
  (and (cerebro-guix-profile) t))

(defun cerebro-guix-manifest-file ()
  (expand-file-name "guix.scm" cerebro-root))

(defun cerebro-guix-channels-file ()
  (expand-file-name "guix/channels.scm" cerebro-root))

(defun cerebro-guix-pinned-commit (&optional file)
  "The channel commit pinned in FILE (default `cerebro-guix-channels-file').
Nil when there is no usable pin -- both when the file is missing and
while it is still the REPLACE-WITH-REAL-COMMIT template shipped for
bootstrapping (the regexp only accepts a real hex sha, so the template
reads as \"no pin\", which is exactly what it means: not reproducible
yet). Only the *channel* commit matches: the introduction's
`openpgp-fingerprint'/commit pair is not preceded by `(commit'."
  (let ((f (or file (cerebro-guix-channels-file))))
    (when (file-readable-p f)
      (with-temp-buffer
        (insert-file-contents f)
        (goto-char (point-min))
        (when (re-search-forward "(commit[ \t\n]+\"\\([0-9a-f]\\{7,40\\}\\)\")" nil t)
          (match-string 1))))))

(defun cerebro-guix-available-packages ()
  "The features of `cerebro-guix-optional-packages' that are actually loaded."
  (seq-filter (lambda (cell) (featurep (car cell))) cerebro-guix-optional-packages))

(defun cerebro-guix-headline ()
  "One line summarising the environment, for a modeline/dashboard/echo area.
Kept short and pure so the dashboard can use it as its init-info without
knowing anything about Guix."
  (let ((commit (cerebro-guix-pinned-commit)))
    (format "%s · pin %s · %d/%d packages"
            (if (cerebro-guix-inside-p) "pinned guix env" "host PATH (degraded)")
            (if commit (substring commit 0 (min 7 (length commit))) "template")
            (length (cerebro-guix-available-packages))
            (length cerebro-guix-optional-packages))))

(defun cerebro-guix-status-lines ()
  "The full environment report as a list of plain strings.
Pure (reads only the environment and `featurep'), so it is unit-testable
and can be rendered anywhere -- `cerebro-guix-status' shows it in a
buffer, the CLI could print it verbatim."
  (let ((commit (cerebro-guix-pinned-commit)))
    (append
     (list
      (format "environment : %s"
              (or (cerebro-guix-profile)
                  "host PATH -- NOT isolated (launch with `cerebro', `make shell' or direnv)"))
      (format "pin         : %s"
              (or commit
                  "guix/channels.scm is still a template -- M-x cerebro-guix-repin"))
      (format "emacs       : %s (%s)" emacs-version (directory-file-name invocation-directory))
      (format "notes       : %s" org-directory)
      ""
      "packages (guix.scm):")
     (mapcar (lambda (cell)
               (format "  [%s] %-14s %s"
                       (if (featurep (car cell)) "ok" "--")
                       (car cell) (cdr cell)))
             cerebro-guix-optional-packages)
     (when cerebro-guix-missing-packages
       (list ""
             "Missing packages mean this Emacs was started outside the pinned"
             "environment (or guix.scm has drifted). Nothing is fetched at"
             "runtime on purpose -- see README.org \"Bootstrap\"."))
     ;; init.el records optional *modules* that failed to load outright;
     ;; surface them here too, so one command explains the whole degraded
     ;; state instead of a warning you scrolled past at startup.
     (when (bound-and-true-p cerebro-unavailable-modules)
       (cons ""
             (cons "modules that failed to load:"
                   (mapcar (lambda (m) (format "  %s: %s" (car m) (cdr m)))
                           cerebro-unavailable-modules)))))))

;;;###autoload
(defun cerebro-guix-status ()
  "Report the environment: profile, pin, and which guix.scm packages loaded."
  (interactive)
  (cerebro-report (format "cerebro environment -- %s" (cerebro-guix-headline))
                  (cerebro-guix-status-lines)
                  #'identity
                  "*cerebro-guix*"))

;; -- Driving the environment from Emacs --------------------------------

;;;###autoload
(defun cerebro-guix-find-manifest ()
  "Open guix.scm (the package set)."
  (interactive)
  (find-file (cerebro-guix-manifest-file)))

;;;###autoload
(defun cerebro-guix-find-channels ()
  "Open guix/channels.scm (the pin)."
  (interactive)
  (find-file (cerebro-guix-channels-file)))

(defun cerebro-guix--compile (command name)
  "Run COMMAND from the repo root in a compilation buffer called NAME.
Asynchronous on purpose: materialising the profile can take a very long
time the first time (texlive-scheme-full alone is several GB), and Emacs
must stay usable while it happens -- with the output visible, since that
is the only way to see a download stall."
  (let ((default-directory cerebro-root)
        (compilation-buffer-name-function (lambda (&rest _) name)))
    (compile command)))

;;;###autoload
(defun cerebro-guix-build ()
  "Materialise the pinned environment (bin/guix-run), showing the output.
The first run downloads/builds the whole profile and can take a long
time; afterwards it is a cheap no-op that just confirms the profile is
complete."
  (interactive)
  (cerebro-guix--compile "./bin/guix-run true && echo 'guix environment ready'"
                         "*cerebro-guix-build*"))

;;;###autoload
(defun cerebro-guix-run (command)
  "Run COMMAND inside the pinned environment (through bin/guix-run).
The Emacs-side equivalent of `make shell' for one-off commands, so you
never have to guess whether a tool you are about to run came from the pin
or from the host."
  (interactive (list (read-shell-command "guix-run: ")))
  (cerebro-guix--compile (concat "./bin/guix-run " command) "*cerebro-guix-run*"))

;;;###autoload
(defun cerebro-guix-repin ()
  "Re-pin guix/channels.scm to the Guix revision currently in use.
This is the documented bootstrap step (`guix describe -f channels >
guix/channels.scm') made one keystroke, and it rewrites a *tracked*
file -- so it confirms first, and refuses to write anything that does not
parse as a channel list with a real commit (a failed `guix describe'
must never leave the pin truncated)."
  (interactive)
  (unless (executable-find "guix")
    (user-error "guix is not on PATH -- see README.org \"Bootstrap\""))
  (let ((file (cerebro-guix-channels-file))
        (current (cerebro-guix-pinned-commit))
        ;; cerebro-ui.el turns on `use-short-answers' (y/n everywhere);
        ;; this one prompt is worth typing out, since it rewrites the
        ;; file that defines what "reproducible" means here.
        (use-short-answers nil))
    (when (yes-or-no-p (format "Re-pin %s (currently %s)? "
                               (file-relative-name file cerebro-root)
                               (or current "template")))
      (let ((new (with-temp-buffer
                   (if (zerop (call-process "guix" nil t nil "describe" "-f" "channels"))
                       (buffer-string)
                     (user-error "guix describe failed: %s" (string-trim (buffer-string)))))))
        (unless (string-match-p "(commit[ \t\n]+\"[0-9a-f]\\{7,40\\}\")" new)
          (user-error "guix describe produced no usable commit -- pin left untouched"))
        (with-temp-file file (insert new))
        (message "re-pinned to %s (commit the change to make it reproducible for others)"
                 (cerebro-guix-pinned-commit))))))

(provide 'cerebro-guix)
