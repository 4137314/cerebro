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

(ert-deftest manual-test-figure-and-listing ()
  (site-test--with-base '(("a" . "#+CAPTION: Energy levels.\n\\begin{tikzpicture}\n\\draw (0,0) -- (1,0);\n\\end{tikzpicture}\n\n#+CAPTION: Steps.\n\\begin{algorithmic}\n\\State x\n\\end{algorithmic}\n\n\\[ a = b \\]\n\n#+begin_src vhdl\nsignal a : std_logic;\n#+end_src\n\nCited [cite:@bohr1913;@x2].\n"))
    (let ((tex (manual--note-latex "a")))
      (should (string-match-p (regexp-quote "\\begin{figure}[H]\n\\centering\n\\adjustbox{max width=\\linewidth}{%\n\\begin{tikzpicture}") tex))
      (should (string-match-p (regexp-quote "\\caption{Energy levels.}\n\\end{figure}") tex))
      (should (string-match-p (regexp-quote "\\begin{algorithm}[H]\n\\caption{Steps.}\n\\begin{algorithmic}") tex))
      (should (string-match-p (regexp-quote "\\[ a = b \\]") tex))
      (should-not (string-match-p (regexp-quote "\\begin{figure}[H]\n\\centering\n\\adjustbox{max width=\\linewidth}{%\n\\[") tex))
      (should (string-match-p (regexp-quote "\\begin{lstlisting}[style=kb,language={VHDL},title={VHDL},rulecolor=\\color{kbvhdl}]\nsignal a : std_logic;\n\\end{lstlisting}") tex))
      (should (string-match-p (regexp-quote "Cited \\parencite{bohr1913,x2}.") tex)))))

(ert-deftest manual-test-ranges-before-bibliography ()
  (let ((aux "\\zref@newlabel{kbdomain:d1}{\\default{1}\\page{1}\\abspage{3}}
\\zref@newlabel{kbarea:d1--a}{\\default{1.1}\\page{1}\\abspage{3}}
\\zref@newlabel{kbend:bibliography}{\\default{1.1}\\page{9}\\abspage{9}}
"))
    (should (equal (manual--ranges aux 10) '(("d1.pdf" 3 . 8) ("d1--a.pdf" 3 . 8))))
    (should (equal (manual--bib-start aux) 9))))

;;; test-manual.el ends here
