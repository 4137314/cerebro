% cerebro-beamer.cls -- slide deck class for cerebro math notes ("slides"
% profile). Structurally separate from cerebro.cls on purpose: beamer
% is not an article/book variant, and it manages \newtheorem itself
% (loading amsthm alongside it causes clashes), but it shares notation
% with every other output via cerebro-macros.sty.
%
% Driven by Org's own ox-beamer export backend, not the generic LaTeX
% backend -- see `cerebro-latex--beamer-plist' in
% .emacs.d/lisp/cerebro-latex.el, which also sets the frame level (one
% frame per note) and `allowframebreaks' (a note that does not fit is
% BROKEN across slides rather than allowed to run off the edge).
%
% Everything below is either "make it plain" or "make it fit". Those are
% the only two jobs a deck class has here: the mathematics is the same
% mathematics as in the handbook, and a slide that overflows is the one
% failure a reader cannot work around.

\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{cerebro-beamer}[2026/01/01 cerebro slide deck class]

\newif\ifcerebro@proofs      \cerebro@proofstrue
\newif\ifcerebro@solutions   \cerebro@solutionstrue
\DeclareOption{proofs}{\cerebro@proofstrue}
\DeclareOption{noproofs}{\cerebro@proofsfalse}
\DeclareOption{solutions}{\cerebro@solutionstrue}
\DeclareOption{nosolutions}{\cerebro@solutionsfalse}
% Any other option is passed straight through to beamer.
\DeclareOption*{\PassOptionsToClass{\CurrentOption}{beamer}}
\ProcessOptions\relax
\LoadClass{beamer}

\RequirePackage[T1]{fontenc}
\RequirePackage[english]{babel}
\RequirePackage{cerebro-macros}

% [cite:@key] works in slide content too (same bib/references.bib as
% cerebro.cls), but *not* auto-printed here: beamer requires all
% content inside \begin{frame}...\end{frame}, so an \AtEndDocument
% \printbibliography (fine for the article/handbook doctypes) would land
% outside any frame and produce nothing. Add a references frame by
% hand with a raw LaTeX export snippet if a deck needs one.
\RequirePackage[backend=biber,style=numeric]{biblatex}
\addbibresource{references.bib}

% ---------------------------------------------------------------------
% Plain
% ---------------------------------------------------------------------
% No theme, no colour theme, no navigation, no shadows, no rounded
% corners, no institute logo, no "part of the frame is furniture"
% -- there was a `seahorse' colour theme here and it painted a lilac
% gradient behind mathematics that is printed in black. What a deck
% needs is a title, a rule under it, the content, and the slide number.
\usetheme{default}
\setbeamertemplate{navigation symbols}{}
\setbeamertemplate{blocks}[default]      % square blocks, no shadow
\setbeamertemplate{itemize items}[square]
\setbeamertemplate{enumerate items}[default]
\setbeamercolor{structure}{fg=black}
\setbeamercolor{frametitle}{fg=black,bg=}
\setbeamercolor{title}{fg=black}
% All four block flavours, not just the plain one: beamer colours
% `example' green and `alerted' red out of the box, so a #+begin_example
% arrived on a slide in a colour nothing else in the archive uses.
\setbeamercolor{block title}{fg=black,bg=}
\setbeamercolor{block body}{fg=black,bg=}
\setbeamercolor{block title example}{fg=black,bg=}
\setbeamercolor{block body example}{fg=black,bg=}
\setbeamercolor{block title alerted}{fg=black,bg=}
\setbeamercolor{block body alerted}{fg=black,bg=}
\definecolor{cerebrorule}{HTML}{9AA0AA}

% The frame title as a header line: typewriter face, a hairline under
% it, nothing else -- the same shape as the title block in cerebro.cls,
% so a slide and a handbook page are recognisably the same archive.
\setbeamerfont{frametitle}{family=\ttfamily,series=\bfseries,size=\large}
\setbeamerfont{title}{family=\ttfamily,series=\bfseries,size=\LARGE}
\setbeamerfont{subtitle}{family=\ttfamily,size=\normalsize}
\setbeamerfont{author}{family=\ttfamily,size=\small}
\setbeamerfont{date}{family=\ttfamily,size=\small}
\setbeamerfont{institute}{family=\ttfamily,size=\scriptsize}
\setbeamertemplate{frametitle}{%
  \vspace{0.6em}%
  \insertframetitle\par
  \vspace{0.2em}%
  {\color{cerebrorule}\rule{\linewidth}{0.4pt}}\par
}
% `allowframebreaks' splits an overlong frame; this is what the second
% and later pieces are called. Without it beamer appends roman numerals
% to the title, which is noise on a slide nobody is filing.
\setbeamertemplate{frametitle continuation}[from second]
% The only thing in the footer: which slide this is.
\setbeamertemplate{footline}{%
  \hfill{\ttfamily\tiny\color{cerebrorule}\insertframenumber/\inserttotalframenumber}%
  \hspace{1em}\vspace{0.6em}%
}

% The first slide, built like the title block in cerebro.cls: flush
% left, a rule above and below, one typewriter line of metadata. beamer's
% own centred title page is the only other candidate and it is a
% different document's design.
\setbeamertemplate{title page}{%
  \vfill
  \raggedright
  {\color{cerebrorule}\rule{\linewidth}{0.4pt}}\par
  \vspace{1.0em}
  {\usebeamerfont{title}\inserttitle\par}
  \ifx\insertsubtitle\@empty\else
    \vspace{0.4em}{\usebeamerfont{subtitle}\insertsubtitle\par}
  \fi
  \vspace{0.9em}
  {\ttfamily\footnotesize\color{cerebrorule}
    \insertauthor\hspace{0.6em}|\hspace{0.6em}\insertdate
    \ifx\insertinstitute\@empty\else\hspace{0.6em}|\hspace{0.6em}\insertinstitute\fi
    \par}
  \vspace{0.5em}
  {\color{cerebrorule}\rule{\linewidth}{0.4pt}}\par
  \vfill
}

% ---------------------------------------------------------------------
% Fit
% ---------------------------------------------------------------------
% A figure drawn for a 21cm page, dropped unchanged onto a 12.8cm slide,
% runs past the frame and is typeset ON TOP of whatever comes next --
% the single ugliest failure mode of reusing one source for both. Every
% graphic is therefore capped, here, once:
%
%   - pgfplots axes (what these notes actually plot) get slide-sized
%     defaults instead of page-sized ones;
%   - \includegraphics gets a default width;
%   - and every remaining LaTeX environment is wrapped in an adjustbox
%     that shrinks it -- proportionally, never enlarging -- until it fits
%     both the width and a little over half the height. That wrapper is
%     applied by the exporter (`cerebro-latex--beamer-fit-environment'),
%     which is the only place that knows an export is a deck.
%
% The result is a hard guarantee: on a slide, nothing is drawn outside
% the frame it belongs to.
\RequirePackage{adjustbox}
\RequirePackage{graphicx}
\setkeys{Gin}{width=0.75\textwidth,keepaspectratio}
\pgfplotsset{
  every axis/.append style={
    width=0.80\textwidth, height=0.52\textheight,
    label style={font=\footnotesize},
    tick label style={font=\scriptsize},
    legend style={font=\scriptsize, draw=none},
  },
}
% \cerebrofit{...} -- the wrapper the exporter puts around a figure.
% `max totalsize' only ever shrinks, so a small diagram is left alone.
\newcommand{\cerebrofit}[1]{%
  \begin{center}%
  \adjustbox{max width=\linewidth,max totalheight=0.62\textheight}{#1}%
  \end{center}%
}

% ---------------------------------------------------------------------
% The theorem environments
% ---------------------------------------------------------------------
% Same environment names as cerebro.cls, so #+begin_theorem etc. mean
% the same thing regardless of output format. beamer already predefines
% theorem/corollary/definition/example/lemma/proof itself (redefining
% them with \newtheorem fails with "already defined", cascading into
% broken numbering for everything declared to share their counter) -- so
% declare only what beamer lacks. Which environments beamer predefines
% has varied across TeX Live releases (e.g. some ship a `solution' too,
% which made `\newtheorem{solution}' clash), so guard EACH declaration
% with \@ifundefined: define an environment only when this beamer does
% not already provide it. Version-robust, and each gets its own counter.
% A slide deck does not need cross-references numbered consistently with
% the article/handbook doctypes' shared [definition] counter chain.
\newcommand{\cerebro@newtheorem}[2]{\@ifundefined{#1}{\newtheorem{#1}{#2}}{}}
\cerebro@newtheorem{proposition}{Proposition}
\cerebro@newtheorem{remark}{Remark}
\cerebro@newtheorem{axiom}{Axiom}
\cerebro@newtheorem{conjecture}{Conjecture}
\cerebro@newtheorem{exercise}{Exercise}
\cerebro@newtheorem{notation}{Notation}
\cerebro@newtheorem{solution}{Solution}
\cerebro@newtheorem{hint}{Hint}

% Same proofs/noproofs and solutions/nosolutions toggles as cerebro.cls,
% so a #+begin_proof / #+begin_solution means the same thing whether a
% note is compiled to a handbook or to a slide deck.
\RequirePackage{comment}

% ---------------------------------------------------------------------
% The same metadata macros as cerebro.cls
% ---------------------------------------------------------------------
% cerebro-latex.el injects \cerebroauthor / \cerebroversion /
% \cerebrosubject / \cerebrodate into the preamble of EVERY document of
% this family -- a deck included. Defining them only in cerebro.cls left
% beamer with an undefined control sequence and a failed compile, which
% is exactly what the profile matrix is for (it caught this on `slides').
%
% Here they map onto beamer's own title machinery rather than drawing a
% title page by hand: a deck's first slide is beamer's business, and the
% version rides in the institute line, small, where it belongs.
\newcommand{\cerebro@version}{}
\newcommand{\cerebroauthor}[1]{\author{#1}}
\newcommand{\cerebrosubject}[1]{\subtitle{#1}}
% \date last, not first. Org emits its own \date{...} from the note's
% `#+DATE:' keyword AFTER everything this class and the injected
% preamble do, so setting it here directly loses -- and the deck's title
% slide printed the raw Org timestamp, `[2026-08-06 Thu]', brackets and
% weekday included, while every other output printed `6 August 2026'.
% \AtBeginDocument runs after the whole preamble, which is the one place
% that wins without fighting Org for the keyword.
\newcommand{\cerebrodate}[1]{\AtBeginDocument{\date{#1}}}
\newcommand{\cerebroversion}[1]{%
  \renewcommand{\cerebro@version}{#1}%
  \institute{version #1}%
}
\ifcerebro@proofs\else
  \renewenvironment{proof}[1][]{\comment}{\endcomment}
\fi
\ifcerebro@solutions\else
  \renewenvironment{solution}[1][]{\comment}{\endcomment}
\fi
