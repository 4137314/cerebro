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

(defmacro site-test--with-notes (notes &rest body)
  "Like `site-test--with-base' with NOTES as (ID AREA REQUIRES TEXT), all in domain d."
  (declare (indent 1))
  `(site-test--with-base
       (mapcar (lambda (n)
                 (cons (nth 0 n)
                       (concat (if (nth 1 n) (format "#+begin_comment\n#+end_comment\n") "")
                               (nth 3 n))))
               ,notes)
     ;; Areas and prerequisites go in the drawer: rewrite the files, then reindex.
     (dolist (n ,notes)
       (let ((f (expand-file-name (concat "d/" (nth 0 n) ".org") kb-dir)))
         (with-temp-file f
           (insert ":PROPERTIES:\n:ID: " (nth 0 n) "\n:DOMAIN: d\n"
                   (if (nth 1 n) (concat ":AREA: " (nth 1 n) "\n") "")
                   (if (nth 2 n) (concat ":REQUIRES: " (nth 2 n) "\n") "")
                   ":END:\n#+title: Note " (nth 0 n) "\n#+summary: About " (nth 0 n) ".\n\n"
                   (nth 3 n)))))
     (setq kb-areas '("x" "y") site--base "base")
     (kb-reload)
     ,@body))

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

(ert-deftest site-test-page-seo ()
  (let ((site-url "https://example.org/kb/"))
    (let ((html (site--page "The \\(L^2\\) space" "<p>x</p>" "../" "math/l2.html"
                            "Square-integrable \\(f\\) with \"quotes\" and <tags>.")))
      (should (string-match-p "<link rel=\"canonical\" href=\"https://example.org/kb/math/l2.html\">" html))
      (should (string-match-p "<title>The L\\^2 space</title>" html))
      (should (string-match-p "<meta name=\"description\" content=\"Square-integrable f with &quot;quotes&quot; and &lt;tags&gt;.\">" html))
      (should (string-match-p "<meta property=\"og:url\" content=\"https://example.org/kb/math/l2.html\">" html)))))

(ert-deftest site-test-plain-drops-markup ()
  (should (equal (site--plain "An /abelian group/ is *the* =x= -- of [[id:g][groups]] \\(a\\).")
                 "An abelian group is the x – of groups a."))
  (should (equal (site--plain "a/b and 3*4") "a/b and 3*4")))

(ert-deftest site-test-sitemap ()
  (let ((out (make-temp-file "site-test" t)) (site-url "https://example.org/kb/"))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "math" out))
          (dolist (f '("index.html" "math/index.html" "math/group.html"))
            (with-temp-file (expand-file-name f out)))
          (site--write-sitemap out)
          (let ((xml (with-temp-buffer (insert-file-contents (expand-file-name "sitemap.xml" out))
                                       (buffer-string))))
            (should (string-match-p "<loc>https://example.org/kb/</loc>" xml))
            (should (string-match-p "<loc>https://example.org/kb/math/</loc>" xml))
            (should (string-match-p "<loc>https://example.org/kb/math/group.html</loc>" xml))
            (should-not (string-match-p "index.html" xml))))
      (delete-directory out t))))

(ert-deftest site-test-groups ()
  (site-test--with-notes '(("a" "y" nil "A.") ("b" "x" nil "B.") ("c" nil nil "C.")
                           ("e" "x" "b" "E."))
    (should (equal (site--groups) '(("d" ("x" "b" "e") ("y" "a") (nil "c")))))))

(ert-deftest site-test-note-nav ()
  (site-test--with-notes '(("a" "x" nil "A.") ("b" "x" "a" "B.") ("c" "x" "b" "C.")
                           ("z" "y" nil "Uses [[id:b][b]]."))
    (setq site--sequence (site--reading-order))
    (let ((first (site--note-page "a" "Base"))
          (mid (site--note-page "b" "Base"))
          (last (site--note-page "c" "Base")))
      (should-not (string-match-p "rel=\"prev\"" first))
      (should (string-match-p "rel=\"prev\" href=\"a.html\"" mid))
      (should (string-match-p "rel=\"next\" href=\"c.html\"" mid))
      (should (string-match-p "rel=\"up\" href=\"index.html#a-d--x\"" mid))
      (should (string-match-p "href=\"index.html#d-d\"" mid))
      ;; Learning path of c: a then b; b is mentioned in z.
      (should (string-match-p "<details class=\"path\">.*2 notes" last))
      (should (string-match-p "a.html.*b.html" (substring last (string-match "class=\"path\"" last))))
      (should (string-match-p "mentioned in</span> <a href=\"z.html\"" mid)))))

(ert-deftest site-test-search-entries ()
  (site-test--with-notes '(("a" "x" nil "A."))
    (let ((entries (site--search-entries "Base")))
      (should (equal (alist-get 'u (car entries)) "base/a.html"))
      (should (equal (alist-get 't (car entries)) "Note a"))
      (should (equal (alist-get 's (car entries)) "About a."))
      (should (seq-some (lambda (e) (equal (alist-get 'u e) "base/index.html#a-d--x")) entries)))))

(ert-deftest site-test-args ()
  (should (equal (site--parse-args '("r.el" "/hub" "out" "--base" "math" "--pdf" "--base" "physics"))
                 '(:registry "r.el" :hub "/hub" :out "out" :bases ("math" "physics") :pdf t
                   :build t :index t)))
  (should (equal (plist-get (site--parse-args '("r.el" "/hub" "out" "--index-only")) :build) nil))
  (should (equal (plist-get (site--parse-args '("r.el" "/hub" "out" "--no-index")) :index) nil)))

(defconst site-test--bib "@article{bohr1913,
  author = {Bohr, Niels},
  title = {On the constitution of atoms and molecules},
  journal = {Philosophical Magazine},
  volume = {26}, pages = {1--25}, year = {1913},
  doi = {10.1080/14786441308634955}}
@book{dirac1930,
  author = {Dirac, Paul Adrien Maurice},
  title = {The Principles of Quantum Mechanics},
  publisher = {Clarendon Press}, address = {Oxford}, year = {1930}}
@article{epr1935,
  author = {Einstein, Albert and Podolsky, Boris and Rosen, Nathan},
  title = {Can quantum-mechanical description of physical reality be considered complete?},
  journal = {Physical Review}, volume = {47}, pages = {777--780}, year = {1935},
  doi = {10.1103/PhysRev.47.777}}
@article{ab1959,
  author = {Aharonov, Yakir and Bohm, David},
  title = {Significance of electromagnetic potentials in the quantum theory},
  journal = {Physical Review}, volume = {115}, pages = {485--491}, year = {1959}}
")

(defmacro site-test--with-bib (&rest body)
  `(let ((bib (make-temp-file "refs" nil ".bib" site-test--bib)))
     (unwind-protect
         (progn (setq site--refs (refs-load bib) site--cited (make-hash-table :test 'equal)) ,@body)
       (delete-file bib) (setq site--refs nil))))

(ert-deftest site-test-refs-format ()
  (site-test--with-bib
   (should (equal (refs-short (gethash "bohr1913" site--refs)) "Bohr 1913"))
   (should (equal (refs-short (gethash "ab1959" site--refs)) "Aharonov and Bohm 1959"))
   (should (equal (refs-short (gethash "epr1935" site--refs)) "Einstein et al. 1935"))
   (should (equal (refs-full (gethash "bohr1913" site--refs))
                  "N. Bohr, “On the constitution of atoms and molecules”, Philosophical Magazine 26, 1–25 (1913)."))
   (should (equal (refs-full (gethash "dirac1930" site--refs))
                  "P. A. M. Dirac, The Principles of Quantum Mechanics (Clarendon Press, Oxford, 1930)."))))

(ert-deftest site-test-citation ()
  (site-test--with-bib
   (site-test--with-base '(("a" . "Atoms are quantised [cite:@bohr1913; @epr1935], see [cite:@nokey]."))
     (let ((html (site-test--html "a")))
       (should (string-match-p "quantised <span class=\"cite\">(<a class=\"ref\" href=\"https://doi.org/10.1080/14786441308634955\"" html))
       (should (string-match-p ">Bohr 1913</a>; <a class=\"ref\"[^>]*>Einstein et al. 1935</a>)</span>" html))
       (should (string-match-p "data-full=\"N. Bohr, “On the constitution" html))
       (should (string-match-p "<span class=\"ref missing\">nokey</span>" html))
       (should (equal (gethash "bohr1913" site--cited) '("a")))))))

(ert-deftest site-test-figure-caption ()
  (site-test--with-base '(("a" . "#+CAPTION: Energy levels of \\(H\\).\n\\begin{tikzpicture}\n\\draw (0,0) -- (1,0);\n\\end{tikzpicture}\n\n#+CAPTION: Second.\n\\begin{tikzpicture}\n\\draw (0,0) -- (2,0);\n\\end{tikzpicture}\n\n#+CAPTION: Steps.\n\\begin{algorithmic}\n\\State x\n\\end{algorithmic}\n"))
    (dolist (f '("\\begin{tikzpicture}\n\\draw (0,0) -- (1,0);\n\\end{tikzpicture}"
                 "\\begin{tikzpicture}\n\\draw (0,0) -- (2,0);\n\\end{tikzpicture}"
                 "\\begin{algorithmic}\n\\State x\n\\end{algorithmic}"))
      (site-test--fake-svg f))
    (site-test--fake-svg "\\(H\\)")
    (let ((html (site-test--html "a")))
      (should (string-match-p "<figure class=\"fig\"><img class=\"m\"" html))
      (should (string-match-p "<figcaption><span class=\"fl\">Figure 1.</span> Energy levels of <img" html))
      (should (string-match-p "<span class=\"fl\">Figure 2.</span> Second." html))
      (should (string-match-p "<span class=\"fl\">Algorithm 1.</span> Steps." html)))))

(ert-deftest site-test-src-highlight ()
  (site-test--with-base '(("a" . "#+begin_src c++\nint main() { return 0; } // hi <b>\n#+end_src\n"))
    (let ((html (site-test--html "a")))
      (should (string-match-p "<figure class=\"listing lang-cpp\"><figcaption><span class=\"lang\">C\\+\\+</span></figcaption>" html))
      (should (string-match-p "<span class=\"t\">int</span>" html))
      (should (string-match-p "<span class=\"k\">return</span>" html))
      (should (string-match-p "<span class=\"c\">// hi &lt;b&gt;</span>" html)))))

;;; test-site.el ends here
