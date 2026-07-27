% cerebro.cls -- shared parametric LaTeX class for cerebro math notes.
%
% Class options:
%   proofs    (default) -- \begin{proof}...\end{proof} blocks are typeset.
%   noproofs            -- proof blocks are silently dropped, so the same
%                           .tex (generated from the same .org source) can
%                           compile as a "statements-only" document
%                           without touching a single word of content.
%
% This is the one place notation/theorem numbering is defined, so every
% exported note shares it instead of redefining it per file. Driven from
% Org via .emacs.d/lisp/cerebro-latex.el, which sets this class option
% per export profile and strips #+begin_proof blocks to match.

\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{cerebro}[2026/01/01 cerebro parametric math notes class]

\newif\ifcerebro@proofs
\cerebro@proofstrue

\DeclareOption{proofs}{\cerebro@proofstrue}
\DeclareOption{noproofs}{\cerebro@proofsfalse}
\DeclareOption*{\PassOptionsToClass{\CurrentOption}{article}}
\ProcessOptions\relax
\LoadClass[11pt]{article}

\RequirePackage[T1]{fontenc}
\RequirePackage[english]{babel}
\RequirePackage{amsmath,amssymb,amsthm}
\RequirePackage{geometry}
\geometry{margin=2.5cm}

\theoremstyle{definition}
\newtheorem{definition}{Definition}[section]
\newtheorem{example}[definition]{Example}

\theoremstyle{plain}
\newtheorem{theorem}[definition]{Theorem}
\newtheorem{lemma}[definition]{Lemma}
\newtheorem{proposition}[definition]{Proposition}
\newtheorem{corollary}[definition]{Corollary}

\theoremstyle{remark}
\newtheorem{remark}[definition]{Remark}

% The actual proofs/noproofs switch: redefine amsthm's proof environment
% to a no-op when noproofs is selected, instead of asking every note to
% know which profile it is being exported under.
\ifcerebro@proofs\else
  \RequirePackage{comment}
  \renewenvironment{proof}[1][]{\comment}{\endcomment}
\fi
