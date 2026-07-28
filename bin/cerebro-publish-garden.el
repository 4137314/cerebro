;;; cerebro-publish-garden.el --- batch entry point for the digital garden -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/cerebro-publish-garden.el -- STAGING-DIR OUTPUT-DIR
;; Called by bin/cerebro-publish-garden, which builds STAGING-DIR as a
;; symlink farm of exactly the notes that qualify. ox-publish is core
;; Org, so this needs nothing from guix.scm beyond Emacs itself.

(require 'ox-publish)

(let* ((args (delete "--" (copy-sequence command-line-args-left)))
       (staging (nth 0 args))
       (output (nth 1 args)))
  (unless (and staging output)
    (message "usage: STAGING-DIR OUTPUT-DIR")
    (kill-emacs 1))
  (setq org-publish-project-alist
        `(("cerebro-garden"
           :base-directory ,staging
           :base-extension "org"
           :publishing-directory ,output
           :publishing-function org-html-publish-to-html
           :with-toc t
           :section-numbers nil
           :html-postamble nil)))
  (condition-case err
      (progn
        (org-publish-project "cerebro-garden" t)
        (kill-emacs 0))
    (error
     (message "cerebro-publish-garden failed: %s" (error-message-string err))
     (kill-emacs 1))))
