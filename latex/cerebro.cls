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
%   article   (default) -- \LoadClass{scrartcl} (KOMA-Script article)
%   report               -- \LoadClass{scrreprt} ("report" output)
%   book                  -- \LoadClass{scrbook}  ("manual" output)
%
% Notation (\R, \abs, ...) lives in cerebro-macros.sty, shared with
% cerebro-beamer.cls, so it means the same thing in every output format.

\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{cerebro}[2026/01/01 cerebro parametric math notes class]

% Three independent option axes, all set by cerebro-latex.el as data:
%   proofs/noproofs        -- typeset or silently drop \begin{proof} bodies
%   solutions/nosolutions  -- typeset or silently drop \begin{solution} bodies
%   article/report/book/syllabus -- which base class + layout
\newif\ifcerebro@proofs      \cerebro@proofstrue
\newif\ifcerebro@solutions   \cerebro@solutionstrue
\newif\ifcerebro@syllabus    \cerebro@syllabusfalse
\def\cerebro@doctype{scrartcl}

\DeclareOption{proofs}{\cerebro@proofstrue}
\DeclareOption{noproofs}{\cerebro@proofsfalse}
\DeclareOption{solutions}{\cerebro@solutionstrue}
\DeclareOption{nosolutions}{\cerebro@solutionsfalse}
\DeclareOption{article}{\def\cerebro@doctype{scrartcl}}
\DeclareOption{report}{\def\cerebro@doctype{scrreprt}}
\DeclareOption{book}{\def\cerebro@doctype{scrbook}}
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

\theoremstyle{definition}
\newtheorem{definition}{Definition}[section]
\newtheorem{example}[definition]{Example}
\newtheorem{exercise}[definition]{Exercise}
\newtheorem{notation}[definition]{Notation}

\theoremstyle{plain}
\newtheorem{theorem}[definition]{Theorem}
\newtheorem{lemma}[definition]{Lemma}
\newtheorem{proposition}[definition]{Proposition}
\newtheorem{corollary}[definition]{Corollary}
\newtheorem{axiom}[definition]{Axiom}
\newtheorem{conjecture}[definition]{Conjecture}

\theoremstyle{remark}
\newtheorem{remark}[definition]{Remark}
% Pedagogical apparatus for exercise sheets / handouts. Unnumbered
% (starred), remark-styled: a Hint or Solution attached to the preceding
% Exercise, not a numbered result in its own right.
\newtheorem*{hint}{Hint}
\newtheorem*{solution}{Solution}

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

% syllabus: a course.org typeset as a lightweight handout. enumitem gives
% tidy schedule/objective lists; the theorem apparatus above stays
% defined but a syllabus simply does not use it.
\ifcerebro@syllabus
  \RequirePackage{enumitem}
\fi
