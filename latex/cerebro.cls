% cerebro.cls -- shared parametric LaTeX class for cerebro math notes.
%
% Two independent option groups, composed by
% .emacs.d/lisp/cerebro-latex.el (see cerebro-latex-doctypes /
% cerebro-latex-content-modes there) -- this class only needs to know
% about its own two axes, not about export "profiles" as a concept.
%
%   proofs    (default) -- \begin{proof}...\end{proof} blocks are typeset.
%   noproofs            -- proof blocks are silently dropped, so the same
%                           .tex (generated from the same .org source) can
%                           compile as a "statements-only" document
%                           without touching a single word of content.
%
%   article   (default) -- \LoadClass{scrartcl} (the `lecture' output)
%   book                -- \LoadClass{scrbook}  (the `handbook' output)
%   syllabus            -- scrartcl again, with the syllabus layout
%   index               -- build an analytical index (\printindex at the
%                          end); on for the handbook, off everywhere else
%
% Any option this class does not declare (`twocolumn', for the
% `conjecture' output) is passed straight through to the base class.
%
% Notation (\R, \abs, ...) lives in cerebro-macros.sty, shared with
% cerebro-beamer.cls, so it means the same thing in every output format.

\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{cerebro}[2026/01/01 cerebro parametric math notes class]

% Three independent option axes, all set by cerebro-latex.el as data:
%   proofs/noproofs        -- typeset or silently drop \begin{proof} bodies
%   solutions/nosolutions  -- typeset or silently drop \begin{solution} bodies
%   article/book/syllabus  -- which base class + layout
\newif\ifcerebro@proofs      \cerebro@proofstrue
\newif\ifcerebro@solutions   \cerebro@solutionstrue
\newif\ifcerebro@syllabus    \cerebro@syllabusfalse
% Whether the title block gets a page of its own. A handbook is a bound
% book and opens with one; a lecture sheet or a syllabus does not waste a
% sheet of paper on four lines of metadata.
\newif\ifcerebro@titlepage   \cerebro@titlepagefalse
% Whether the document ends with an analytical index.
\newif\ifcerebro@index       \cerebro@indexfalse
\def\cerebro@doctype{scrartcl}

\DeclareOption{proofs}{\cerebro@proofstrue}
\DeclareOption{noproofs}{\cerebro@proofsfalse}
\DeclareOption{solutions}{\cerebro@solutionstrue}
\DeclareOption{nosolutions}{\cerebro@solutionsfalse}
\DeclareOption{article}{\def\cerebro@doctype{scrartcl}}
\DeclareOption{book}{\def\cerebro@doctype{scrbook}\cerebro@titlepagetrue}
\DeclareOption{index}{\cerebro@indextrue}
% syllabus is an article-based layout with a distinct intent (a course
% handout, typeset from a course.org) -- same base class, its own flag.
\DeclareOption{syllabus}{\def\cerebro@doctype{scrartcl}\cerebro@syllabustrue}
\DeclareOption*{\PassOptionsToClass{\CurrentOption}{\cerebro@doctype}}
\ProcessOptions\relax
\LoadClass[11pt]{\cerebro@doctype}

% KOMA-Script classes already provide their own \captionof-equivalent
% (via tocbasic), which unconditionally clashes with Org's own default
% \usepackage{capt-of} ("! LaTeX Error: Command \captionof already
% defined.", verified against a real compile). Register capt-of as
% already loaded so Org's later \usepackage{capt-of} is a silent no-op
% and KOMA's own \captionof is used instead -- confirmed this still
% leaves \captionof working. Not needed (and not applied) in
% cerebro-beamer.cls: beamer does not define \captionof itself, so
% skipping capt-of there would leave it genuinely undefined instead.
%
% No \makeatletter/\makeatother needed or wanted here: @ is already
% catcode-letter throughout a .cls file, and calling \makeatother would
% prematurely flip @ back to "other" for the *rest* of this file --
% including \ifcerebro@proofs below -- which is exactly the bug that
% produced "Undefined control sequence \ifcerebro@proofs" the first
% time this fix was tried.
\@namedef{ver@capt-of.sty}{2009/12/29}

\RequirePackage[T1]{fontenc}
\RequirePackage[english]{babel}
\RequirePackage{amsthm}
\RequirePackage{cerebro-macros}
\RequirePackage{geometry}
\geometry{margin=2.5cm}

% Shared bibliography (bib/references.bib, found via BIBINPUTS -- see
% .emacs.d/lisp/cerebro-latex.el). [cite:@key] in Org becomes \autocite
% via org-cite's biblatex export processor. \printbibliography at the
% end is harmless when nothing was cited (confirmed against a real
% compile: biblatex/biber print an empty bibliography, not an error).
\RequirePackage[backend=biber,style=numeric]{biblatex}
\addbibresource{references.bib}
\AtEndDocument{\printbibliography}

% The theorem-like environments live in a shared package so amsart
% (paper/preprint) gets exactly the same ones -- see cerebro-theorems.sty.
\RequirePackage{cerebro-theorems}

% `comment' is used to drop proof and/or solution bodies when the
% matching toggle is off. Loaded once, unconditionally: \RequirePackage
% is idempotent, and it keeps the two independent switches below trivial.
\RequirePackage{comment}

% proofs/noproofs: redefine amsthm's proof environment to a no-op under
% noproofs, instead of asking every note to know which profile it is
% being exported under.
\ifcerebro@proofs\else
  \renewenvironment{proof}[1][]{\comment}{\endcomment}
\fi

% solutions/nosolutions: the same trick for \begin{solution} bodies, so
% one exercise sheet compiles with worked solutions (instructor copy) or
% without (student copy) from a single source. Independent of the proofs
% switch -- a statements-only lecture can still carry solutions.
\ifcerebro@solutions\else
  \renewenvironment{solution}[1][]{\comment}{\endcomment}
\fi

% syllabus: a course typeset as a lightweight handout. enumitem gives
% tidy schedule/objective lists; the theorem apparatus above stays
% defined but a syllabus simply does not use it.
\ifcerebro@syllabus
  \RequirePackage{enumitem}
\fi

% Two columns (the `conjecture' output) is a narrower measure than
% anything else here, and TeX's defaults are tuned for a full page: the
% same paragraph that sets cleanly at 16cm produces overfull lines at 8.
% Three settings, and no content change -- a conjecture is written once
% and typeset both ways.
\if@twocolumn
  \setlength{\columnsep}{1.6em}
  % Let TeX stretch a little further before it gives up and sticks a
  % word past the margin.
  \emergencystretch=1.5em
  % Verbatim text cannot wrap at all, so in a narrow column it is the
  % one thing that *will* run over. Smaller buys about a third more
  % characters per line, which is the difference for a citation key or a
  % file name -- the only verbatim a conjecture note usually has.
  \renewcommand{\verbatim@font}{\ttfamily\footnotesize}
\fi

% ---------------------------------------------------------------------
% The analytical index
% ---------------------------------------------------------------------
% A handbook is read by looking things up, so it ends with an index --
% and an index nobody has to *write*. Two sources feed it, neither of
% which is a second pass over the text:
%
%   - every named result: cerebro-latex.el emits an \index entry from a
%     block's own #+NAME (`def-supremum' -> "supremum"), so naming a
%     definition once puts it in the index of every document that
%     includes it, forever;
%   - `#+INDEX: entry' in a note, which Org already transcodes to
%     \index{entry} -- for the terms a name cannot express.
%
% latexmk runs makeindex by itself when it sees the .idx file, so this
% costs no extra step in the pipeline. This \AtEndDocument is registered
% after the bibliography's, above, and those hooks run in registration
% order -- so the index is the last thing in the book, where an index
% goes.
\ifcerebro@index
  \RequirePackage{makeidx}
  \makeindex
  \AtEndDocument{\cleardoublepage\printindex}
\else
  % Defined but inert everywhere else: a note carrying `#+INDEX:' must
  % still compile as a lecture sheet or a deck, where there is no index
  % to put it in.
  \renewcommand{\index}[1]{}
\fi

% ---------------------------------------------------------------------
% Links
% ---------------------------------------------------------------------
% Org loads hyperref itself, with no options, which gives the default:
% every internal reference, citation and URL boxed in a coloured
% rectangle. Those boxes are invisible on paper (they are not printed)
% and ugly on screen, which is the worst of both worlds -- and this
% archive is read on screen.
%
% Loading it here first, WITH options, is what makes the settings stick:
% Org's later \usepackage{hyperref} passes no options, so there is no
% option clash, and it becomes a no-op. Colours are muted on purpose: a
% reference is a signpost inside a mathematical text, not a hyperlink on
% a web page.
\RequirePackage{xcolor}
\definecolor{cerebrolink}{HTML}{2A5D9F}   % internal refs, ToC, theorems
\definecolor{cerebrocite}{HTML}{1F7A5C}   % citations
\definecolor{cerebrourl}{HTML}{8A4B9E}    % external URLs
\definecolor{cerebrorule}{HTML}{9AA0AA}   % the hairlines on the title page
\RequirePackage{hyperref}
\hypersetup{
  colorlinks=true,
  linkcolor=cerebrolink,
  citecolor=cerebrocite,
  urlcolor=cerebrourl,
  linktoc=all,
  pdfborder={0 0 0},
  bookmarksnumbered=true,
  bookmarksopen=true,
  pdfstartview={FitH},
}

% ---------------------------------------------------------------------
% Document metadata
% ---------------------------------------------------------------------
% Everything the exporter knows about the document, with a default that
% compiles on its own: cerebro-latex.el fills these in
% (\cerebroauthor from the configured author, \cerebroversion from
% `git describe'), and a .tex compiled by hand still works.
\newcommand{\cerebro@author}{}
\newcommand{\cerebro@version}{}
\newcommand{\cerebro@subject}{}
\newcommand{\cerebro@date}{}
\newcommand{\cerebroauthor}[1]{\renewcommand{\cerebro@author}{#1}}
\newcommand{\cerebroversion}[1]{\renewcommand{\cerebro@version}{#1}}
\newcommand{\cerebrosubject}[1]{\renewcommand{\cerebro@subject}{#1}}
% The date as a person writes it. Org exports `#+DATE:' as the timestamp
% it is -- brackets, weekday and all -- and a buffer keyword wins over
% anything the exporter passes, so the title page takes its date from
% here instead of from \@date when this is set.
\newcommand{\cerebrodate}[1]{\renewcommand{\cerebro@date}{#1}}

% ---------------------------------------------------------------------
% The title, as a header line
% ---------------------------------------------------------------------
% No mark, no ornament, no image: a rule, the title, and one line of
% machine-readable metadata, all flush left. There *was* a drawn emblem
% here (three TikZ orbits and a dot) and it was the only decoration in
% the design, which is exactly the argument against it -- a document
% whose one flourish is a logo is a document with a logo, not a minimal
% one. What identifies a build is the version string, and that is text.
%
% Flush left rather than centred because everything else in these
% documents is: a centred block on page one is a different typographic
% register from the mathematics below it.

\newcommand{\cerebro@rule}{{\color{cerebrorule}\rule{\linewidth}{0.4pt}}}

% The metadata line: `author | date | version', in the typewriter face,
% one line, in that order always. Written as a single \par so it wraps
% like a line of text and not like a table.
\newcommand{\cerebro@sep}{\hspace{0.6em}\textcolor{cerebrorule}{|}\hspace{0.6em}}
\newcommand{\cerebro@metaline}{%
  \ifx\cerebro@author\@empty\else \cerebro@author \cerebro@sep \fi
  \ifx\cerebro@date\@empty \@date \else \cerebro@date \fi
  \ifx\cerebro@version\@empty\else \cerebro@sep \cerebro@version \fi
}

% The block itself. Used either on its own page (the handbook, whose
% base class expects a title page) or at the top of page one (a lecture,
% a syllabus, a single result) -- the same eight lines in both cases, so
% every document of this archive opens the same way.
\newcommand{\cerebro@titleblock}{%
  \begingroup
  \raggedright
  \noindent\cerebro@rule\par
  \vspace{1.1em}
  {\ttfamily\bfseries\LARGE \@title \par}
  \ifx\cerebro@subject\@empty\else
    \vspace{0.45em}{\ttfamily\large\color{cerebrolink} \cerebro@subject \par}
  \fi
  \vspace{1.0em}
  {\ttfamily\footnotesize\color{cerebrorule} \cerebro@metaline \par}
  \vspace{0.5em}
  \noindent\cerebro@rule\par
  \endgroup
}

\newcommand{\cerebromaketitle}{%
  \ifcerebro@titlepage
    \begin{titlepage}
      \vspace*{\stretch{1}}
      \cerebro@titleblock
      \vspace*{\stretch{2}}
    \end{titlepage}%
  \else
    % In two columns (the `conjecture' output) the title has to span
    % both, or it is typeset inside the first one at a third of the
    % measure -- `\twocolumn[...]' is the only way to say that, and it
    % also starts the page, which is what a title should do.
    \if@twocolumn
      \twocolumn[\cerebro@titleblock\vspace{2.2em}]%
    \else
      \cerebro@titleblock
      \par\vspace{2.2em}
    \fi
  \fi
}

% Org emits \maketitle; make that mean the block above. The redefinition
% is deliberate and total: one title, one look, no way for a single note
% to end up with a different one.
\let\cerebro@oldmaketitle\maketitle
\renewcommand{\maketitle}{\cerebromaketitle}
