;;; cerebro-crypt.el --- encrypted subtrees for private notes -*- lexical-binding: t; -*-

;; Built into Org core (org-crypt.el) -- no new Emacs package, just
;; GnuPG on PATH (added to guix.scm's propagated-inputs). Tag any
;; heading :crypt: (declared in cerebro-org.el's org-tag-alist) and its
;; body is encrypted on save; decrypt on demand with `org-decrypt-entry'
;; (C-c C-x C-d). Symmetric (passphrase) encryption by default --
;; org-crypt-key is nil, so no GPG keypair has to exist first; switch
;; to a real key ID later by setting org-crypt-key to it.

(require 'org-crypt)

(setq org-crypt-key nil) ;; nil = symmetric (passphrase) encryption
(setq org-crypt-disable-auto-save t) ;; don't let decrypted text leak into an autosave file mid-edit
(org-crypt-use-before-save-magic)

(provide 'cerebro-crypt)
