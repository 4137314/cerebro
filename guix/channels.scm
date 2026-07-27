;; Pinned Guix channel(s) for a fully reproducible cerebro environment.
;;
;; TEMPLATE: there is no working Guix installation in the environment this
;; was authored in, so the commit below is a placeholder, not a real,
;; buildable revision. `guix time-machine -C guix/channels.scm` will fail
;; loudly on it -- that is intentional: better a loud failure than a
;; silently unpinned, unreproducible environment.
;;
;; Regenerate this file for real once Guix is installed and `guix pull`
;; has run at least once:
;;
;;   guix describe -f channels > guix/channels.scm
;;
;; then commit the result. Re-running that command (and committing again)
;; later is the entire "upgrade the environment on purpose" procedure.
;; Until you do, anyone -- including future-you, on a different machine,
;; years from now -- who runs
;;
;;   guix time-machine -C guix/channels.scm -- shell -- <command>
;;
;; gets bit-for-bit the same package set that produced whatever they are
;; looking at right now, regardless of what a plain `guix pull` would
;; fetch on that day.

(list (channel
       (name 'guix)
       (url "https://git.savannah.gnu.org/git/guix.git")
       (branch "master")
       (commit "REPLACE-WITH-REAL-COMMIT-FROM-guix-describe--f-channels")))
