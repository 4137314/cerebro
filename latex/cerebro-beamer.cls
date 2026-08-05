% cerebro-beamer.cls -- slide deck class for cerebro math notes ("slides"
% profile). Structurally separate from cerebro.cls on purpose: beamer
% is not an article/report/book variant, and it manages \newtheorem
% itself (loading amsthm alongside it causes clashes), but it shares
% notation with every other output via cerebro-macros.sty.
%
% Driven by Org's own ox-beamer export backend, not the generic LaTeX
% backend -- see cerebro-latex--export-beamer in
% .emacs.d/lisp/cerebro-latex.el. Top-level (H1) Org headings become
% frames; that is ox-beamer's own default (org-beamer-frame-level),
% not something this class configures.

\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{cerebro-beamer}[2026/01/01 cerebro slide deck class]

\newif\ifcerebro@proofs      \cerebro@proofstrue
\newif\ifcerebro@solutions   \cerebro@solutionstrue
\DeclareOption{proofs}{\cerebro@proofstrue}
\DeclareOption{noproofs}{\cerebro@proofsfalse}
\DeclareOption{solutions}{\cerebro@solutionstrue}
\DeclareOption{nosolutions}{\cerebro@solutionsfalse}
% Any other option (notably `handout', the `handout' doctype in
% cerebro-latex.el, which renders the deck as a printable, overlay-free
% handout) is passed straight through to beamer.
\DeclareOption*{\PassOptionsToClass{\CurrentOption}{beamer}}
\ProcessOptions\relax
\LoadClass{beamer}

\RequirePackage[T1]{fontenc}
\RequirePackage[english]{babel}
\RequirePackage{cerebro-macros}

% [cite:@key] works in slide content too (same bib/references.bib as
% cerebro.cls), but *not* auto-printed here: beamer requires all
% content inside \begin{frame}...\end{frame}, so an \AtEndDocument
% \printbibliography (fine for article/report/manual) would land
% outside any frame and produce nothing. Add a references frame by
% hand with a raw LaTeX export snippet if a deck needs one.
\RequirePackage[backend=biber,style=numeric]{biblatex}
\addbibresource{references.bib}

\usetheme{default}
\usecolortheme{seahorse}
\setbeamertemplate{navigation symbols}{}

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
% the article/report/manual doctypes' shared [definition] counter chain.
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
% note is compiled to an article or to a slide deck / handout.
\RequirePackage{comment}
\ifcerebro@proofs\else
  \renewenvironment{proof}[1][]{\comment}{\endcomment}
\fi
\ifcerebro@solutions\else
  \renewenvironment{solution}[1][]{\comment}{\endcomment}
\fi
