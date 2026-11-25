;; The knowledge bases of the hub, in the order of the bases page.
;; :root is relative to the git superproject that contains cerebro (~/dev), or to this
;; file when it starts with "."; :notes and :config are relative to :root.
;; :publish t puts the base on the public site (tools/site.el, `make site`).
(("math" :title "Mathematics" :publish t :root "." :notes "kb" :config "kb-config.el")
 ("thesis" :title "Bachelor Thesis" :root "uni/bachelor-thesis"
  :notes "study/kb" :config "study/kb-config.el")
 ("remote-sensing" :title "Remote Sensing" :publish t :root "uni/remote-sensing"
  :notes "study/kb" :config "study/kb-config.el")
 ("computer-science" :title "Computer Science" :publish t :root "uni/computer-science"
  :notes "study/kb" :config "study/kb-config.el")
 ("business" :title "Business" :publish t :root "uni/business"
  :notes "study/kb" :config "study/kb-config.el")
 ("physics" :title "Physics" :publish t :root "uni/physics"
  :notes "study/kb" :config "study/kb-config.el"))
