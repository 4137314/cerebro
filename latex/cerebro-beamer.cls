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

\newif\ifcerebro@proofs
\cerebro@proofstrue
\DeclareOption{proofs}{\cerebro@proofstrue}
\DeclareOption{noproofs}{\cerebro@proofsfalse}
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
% theorem/corollary/definition/example/lemma/proof itself (verified
% against a real compile: redefining them with \newtheorem fails with
% "already defined", cascading into broken numbering for everything
% declared to share their counter) -- only declare the ones beamer does
% NOT already provide, each with its own independent counter. A slide
% deck does not need cross-references numbered consistently with the
% article/report/manual doctypes' shared [definition] counter chain.
\newtheorem{proposition}{Proposition}
\newtheorem{remark}{Remark}
\newtheorem{axiom}{Axiom}
\newtheorem{conjecture}{Conjecture}
\newtheorem{exercise}{Exercise}
\newtheorem{notation}{Notation}

\ifcerebro@proofs\else
  \RequirePackage{comment}
  \renewenvironment{proof}[1][]{\comment}{\endcomment}
\fi
