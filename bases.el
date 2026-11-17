;; The knowledge bases of the hub, in the order of the bases page.
;; :root is relative to the git superproject that contains cerebro (~/dev), or to this
;; file when it starts with "."; :notes and :config are relative to :root.
(("math" :title "Matematica" :root "." :notes "kb" :config "kb-config.el")
 ("thesis" :title "Tesi" :root "uni/bachelor-thesis"
  :notes "study/kb" :config "study/kb-config.el")
 ("remote-sensing" :title "Remote Sensing" :root "uni/remote-sensing"
  :notes "study/kb" :config "study/kb-config.el")
 ("computer-science" :title "Computer Science" :root "uni/computer-science"
  :notes "study/kb" :config "study/kb-config.el"))
