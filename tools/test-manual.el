;;; test-manual.el --- tests of the PDF manuals -*- lexical-binding: t; -*-

(require 'ert)
(require 'manual)
(load (expand-file-name "test-site.el" (file-name-directory (or load-file-name buffer-file-name))))

(ert-deftest manual-test-note-latex ()
  (site-test--with-base '(("a" . "See [[id:b][the b note]] and [[id:zzz][gone]].\n\n#+begin_theorem\nTrue \\(x_1\\).\n#+end_theorem\n\n* Heading\nText my_file.\n")
                          ("b" . "B."))
    (let ((tex (manual--note-latex "a")))
      (should (string-match-p (regexp-quote "\\hyperref[note:b]{the b note}") tex))
      (should-not (string-match-p "zzz" tex))
      (should (string-match-p (regexp-quote "\\begin{theorem}") tex))
      (should (string-match-p (regexp-quote "\\(x_1\\)") tex))
      (should (string-match-p (regexp-quote "\\subsubsection*{Heading}") tex))
      (should (string-match-p (regexp-quote "\\label{note:a}") tex))
      (should (string-match-p (regexp-quote "my\\_file") tex)))))

(ert-deftest manual-test-ranges ()
  (let ((aux "\\zref@newlabel{kbdomain:d1}{\\default{1}\\page{1}\\abspage{3}}
\\zref@newlabel{kbarea:d1--a}{\\default{1.1}\\page{1}\\abspage{3}}
\\zref@newlabel{kbarea:d1--b}{\\default{1.2}\\page{3}\\abspage{5}}
\\zref@newlabel{kbother:d1}{\\default{1.3}\\page{4}\\abspage{6}}
\\zref@newlabel{kbdomain:d2}{\\default{2}\\page{6}\\abspage{8}}
\\zref@newlabel{kbarea:d2--d2}{\\default{2.1}\\page{6}\\abspage{8}}
"))
    (should (equal (manual--ranges aux 10)
                   '(("d1.pdf" 3 . 7) ("d1--a.pdf" 3 . 4) ("d1--b.pdf" 5 . 5)
                     ("d2.pdf" 8 . 10) ("d2--d2.pdf" 8 . 10))))))

(ert-deftest manual-test-preamble ()
  (let ((p (manual--preamble "T")))
    (should (string-match-p "\\\\documentclass\\[[^]]*\\]{book}" p))
    (should-not (string-match-p "pgfsys-dvisvgm\\|{preview}\\|PreviewBorder\\|documentclass{article}" p))
    (should (string-match-p "\\\\newtheorem{theorem}" p))
    (should (string-match-p "zref-abspage" p))))

;;; test-manual.el ends here
