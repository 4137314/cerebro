;;; cerebro-compile.el --- byte-compilation as a gate -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/cerebro-compile.el -- [--all] [module...]
;;   (no argument)   compile `cerebro-pure-modules' strictly -- the gate
;;   --all           ...then every other module, warnings printed, counted
;;                   and NOT fatal
;;   module...       compile exactly these, strictly
;; (see `make compile' and `make compile-all'.)
;;
;; Twelve thousand lines of Elisp were never once handed to the byte
;; compiler, which is the one tool that reads all of them and objects. It
;; catches exactly the class of mistake this config is most exposed to and
;; that no test here can see: a variable name mistyped in a `setq'
;; (a "free variable" -- the setting silently does nothing), a function
;; called with the wrong number of arguments, a `let' binding nobody uses,
;; an obsolete Org function that still works today.
;;
;; But it cannot be a gate over everything, and the reason is invariant 4.
;; Outside the pinned environment the soft modules legitimately mention
;; variables of packages that are not installed -- that is what "degrade
;; feature by feature" *means* -- so promoting their warnings to errors
;; would give a gate that is red on every machine without Guix, i.e. a
;; gate nobody can use. So there are two passes:
;;
;;   strict   `cerebro-pure-modules' (cerebro-base.el): the modules that
;;            claim to need no package at all. A warning there is a real
;;            defect -- most often the dependency creeping back in -- and
;;            it fails the build. This is `make compile', and it is what
;;            `make check' runs: a second and a half, and silent when
;;            there is nothing wrong.
;;   report   `--all' adds every other module: warnings printed and
;;            counted, exit status unaffected. A number to look at
;;            deliberately, not a wall of text on the path of every push
;;            -- outside the pinned environment most of those warnings
;;            say "this optional package is not installed", which is the
;;            design working.
;;
;; The .elc files go to a temp directory and are thrown away. That is not
;; tidiness: Emacs loads a .elc in preference to its .el, so a stale one
;; left in .emacs.d/lisp/ would shadow the source you are editing and the
;; config would keep running code you had already deleted. Nothing in this
;; repository is compiled at load time, and this file must not change that.

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (lisp-dir (expand-file-name "../.emacs.d/lisp" here)))
  (add-to-list 'load-path lisp-dir))
(require 'cerebro-base) ;; cerebro-root, cerebro-pure-modules
(require 'bytecomp)
(require 'seq)

(defvar cerebro-compile-directory
  (make-temp-file "cerebro-compile-" t)
  "Throwaway directory the .elc files are written to. See the top.")

(setq byte-compile-dest-file-function
      (lambda (source)
        (expand-file-name (concat (file-name-base source) ".elc")
                          cerebro-compile-directory))
      ;; The compiler's own noise, off: what is being reported here is the
      ;; module's problems, not the compiler's progress.
      byte-compile-verbose nil
      byte-compile-warnings t)

(defun cerebro-compile-source (module)
  "The .el file MODULE (a symbol or string) lives in."
  (expand-file-name (format ".emacs.d/lisp/%s.el" module) cerebro-root))

(defun cerebro-compile-all-modules ()
  "Every cerebro module, as symbols, in load order-ish (alphabetical)."
  (mapcar (lambda (file) (intern (file-name-base file)))
          (directory-files (expand-file-name ".emacs.d/lisp" cerebro-root)
                           t "\\`cerebro-.*\\.el\\'")))

(defun cerebro-compile-one (module strict)
  "Compile MODULE. Returns non-nil when it compiled without objection.
STRICT promotes every warning to an error, which is what makes this a
gate rather than a report."
  (let ((byte-compile-error-on-warn strict)
        (source (cerebro-compile-source module)))
    (and (file-readable-p source)
         (condition-case err
             (byte-compile-file source)
           ;; With `byte-compile-error-on-warn' a warning is signalled
           ;; rather than printed, and the signal has to be caught here or
           ;; the first offending module ends the run before the others
           ;; are looked at -- one problem at a time is exactly what makes
           ;; a gate feel arbitrary.
           (error (princ (format "  %s: %s\n" module (error-message-string err)))
                  nil)))))

(defun cerebro-compile-warning-count ()
  "How many warnings the compile log holds."
  (let ((buffer (get-buffer byte-compile-log-buffer)))
    (if (not buffer)
        0
      (with-current-buffer buffer
        (count-matches "^.*Warning:" (point-min) (point-max))))))

(let* ((args (delete "--" (copy-sequence command-line-args-left)))
       (report-all (and (member "--all" args) t))
       (requested (mapcar #'intern (delete "--all" args)))
       (strict-set (or requested cerebro-pure-modules))
       (loose-set (when (and report-all (null requested))
                    (seq-difference (cerebro-compile-all-modules)
                                    cerebro-pure-modules)))
       (failed '()))

  (princ (format "compile: %d pure module(s), warnings are errors\n"
                 (length strict-set)))
  (dolist (module strict-set)
    (unless (cerebro-compile-one module t)
      (push module failed)))

  (when loose-set
    (princ (format "compile: %d other module(s), warnings reported\n"
                   (length loose-set)))
    (dolist (module loose-set)
      (cerebro-compile-one module nil))
    ;; Printed, not enforced: outside the pinned environment most of these
    ;; are "this optional package is not installed", which is the design.
    (princ (format "compile: %d warning(s) in the non-pure modules%s\n"
                   (cerebro-compile-warning-count)
                   (if (getenv "GUIX_ENVIRONMENT") ""
                     " (outside guix: most will be absent packages)"))))

  (delete-directory cerebro-compile-directory t)

  (if failed
      (progn
        (princ (format "compile: FAILED -- %s\n"
                       (mapconcat #'symbol-name (nreverse failed) " ")))
        (princ "compile: a module that claims to depend on nothing must compile clean\n")
        (kill-emacs 1))
    (princ "compile: ok\n")
    (kill-emacs 0)))
