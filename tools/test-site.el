;;; test-site.el --- tests of the site exporter -*- lexical-binding: t; -*-

;; emacs --batch -Q -L <reader>/emacs -L tools -l tools/test-site.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'site)

(defmacro site-test--with-base (notes &rest body)
  "Run BODY with a temporary base of NOTES ((ID . TEXT) ...) and its state dir."
  (declare (indent 1))
  `(let* ((root (make-temp-file "site-test" t))
          (kb-dir (file-name-as-directory (expand-file-name "kb" root)))
          (kb-state-dir (file-name-as-directory (expand-file-name "state" root)))
          (site--used (make-hash-table :test 'equal)))
     (unwind-protect
         (progn
           (make-directory (expand-file-name "d" kb-dir) t)
           (dolist (n ,notes)
             (with-temp-file (expand-file-name (concat "d/" (car n) ".org") kb-dir)
               (insert ":PROPERTIES:\n:ID: " (car n) "\n:DOMAIN: d\n:END:\n#+title: "
                       (car n) "\n\n" (cdr n))))
           (kb-reload)
           (kb--load-meta)
           ,@body)
       (delete-directory root t))))

(defun site-test--fake-svg (text)
  "Put a fake SVG for fragment TEXT in the cache."
  (make-directory (kb--cache-dir) t)
  (with-temp-file (kb--svg (kb--hash text))
    (insert "<svg width='20pt' height='10pt' viewBox='0 0 20 10'></svg>"))
  (kb--load-meta))

(defun site-test--html (id)
  (site-note-html (expand-file-name (concat "d/" id ".org") kb-dir)))

(ert-deftest site-test-publish-filter ()
  (let* ((root (make-temp-file "site-test" t))
         (reg (expand-file-name "bases.el" root)))
    (unwind-protect
        (progn
          (with-temp-file reg
            (prin1 '(("a" :title "A" :root "." :notes "kb" :publish t)
                     ("secret" :title "S" :root "x" :notes "kb"))
                   (current-buffer)))
          (let ((bases (site-bases reg "/hub")))
            (should (equal (mapcar #'car bases) '("a")))
            (should (equal (plist-get (cdar bases) :title) "A"))
            (should (equal (plist-get (cdar bases) :dir)
                           (file-name-as-directory (expand-file-name "kb" root))))))
      (delete-directory root t))))

(ert-deftest site-test-math-img ()
  (site-test--with-base '(("a" . "Let \\(x^2\\) be."))
    (site-test--fake-svg "\\(x^2\\)")
    (let ((html (site-test--html "a")))
      (should (string-match-p (format "<img class=\"m\" src=\"m/%s.svg\""
                                      (kb--hash "\\(x^2\\)"))
                              html))
      (should (gethash (kb--hash "\\(x^2\\)") site--used)))))

(ert-deftest site-test-display-and-environment ()
  (site-test--with-base '(("a" . "Text\n\\[ a = b \\]\n\n\\begin{tikzpicture}\n\\draw (0,0) -- (1,1);\n\\end{tikzpicture}\n"))
    (site-test--fake-svg "\\[ a = b \\]")
    (site-test--fake-svg "\\begin{tikzpicture}\n\\draw (0,0) -- (1,1);\n\\end{tikzpicture}")
    (let ((html (site-test--html "a")))
      (should (string-match-p (kb--hash "\\[ a = b \\]") html))
      (should (string-match-p
               (kb--hash "\\begin{tikzpicture}\n\\draw (0,0) -- (1,1);\n\\end{tikzpicture}")
               html))
      (should (string-match-p "class=\"mb\"" html)))))

(ert-deftest site-test-missing-svg ()
  (site-test--with-base '(("a" . "Let \\(y<1\\) be."))
    (let ((html (site-test--html "a")))
      (should (string-match-p "<code class=\"tex\">\\\\(y&lt;1\\\\)</code>" html)))))

(ert-deftest site-test-link-known-id ()
  (site-test--with-base '(("a" . "See [[id:b][the b note]].") ("b" . "B."))
    (should (string-match-p "<a href=\"b.html\">the b note</a>" (site-test--html "a")))))

(ert-deftest site-test-link-unknown-id ()
  (site-test--with-base '(("a" . "See [[id:zzz][nothing]]."))
    (let ((html (site-test--html "a")))
      (should (string-match-p "nothing" html))
      (should-not (string-match-p "zzz" html)))))

(ert-deftest site-test-no-subscripts ()
  (site-test--with-base '(("a" . "The file my_file_name is here."))
    (should (string-match-p "my_file_name" (site-test--html "a")))))

(ert-deftest site-test-special-block ()
  (site-test--with-base '(("a" . "#+begin_theorem\nTrue.\n#+end_theorem\n"))
    (should (string-match-p "class=\"theorem\"" (site-test--html "a")))))

(ert-deftest site-test-no-local-paths ()
  (site-test--with-base '(("a" . "Plain."))
    (should-not (string-match-p (regexp-quote root) (site-test--html "a")))))

;;; test-site.el ends here
