#!/bin/sh
# POSIX-sh tests for the bin/ scripts, run in disposable temp dirs so
# they never touch the real repo content. See `make test`.
set -eu

pass=0
fail=0

ok() { pass=$((pass + 1)); echo "ok - $1"; }
bad() { fail=$((fail + 1)); echo "FAIL - $1"; }

repo_root=$(git rev-parse --show-toplevel)

# -- cerebro-issue: appends a well-formed heading in a temp repo -------
tmp=$(mktemp -d)
(
    cd "$tmp"
    git init -q
    mkdir -p issues
    printf '#+TITLE: test\n' > issues/issues.org
    cp "$repo_root/bin/cerebro-issue" ./cerebro-issue
    chmod +x ./cerebro-issue
    ./cerebro-issue "A test issue" tag1 tag2 >/dev/null
)
if grep -q '\* TODO A test issue' "$tmp/issues/issues.org" \
   && grep -q ':tag1:tag2:' "$tmp/issues/issues.org" \
   && grep -q ':ID:' "$tmp/issues/issues.org"; then
    ok "cerebro-issue appends a well-formed heading"
else
    bad "cerebro-issue appends a well-formed heading"
fi
rm -rf "$tmp"

# -- bootstrap-check: exits non-zero and names what's missing -----------
tmp=$(mktemp -d)
git -C "$tmp" init -q
mkdir -p "$tmp/guix"
printf '(commit "REPLACE-WITH-REAL-COMMIT-x")\n' > "$tmp/guix/channels.scm"
out=$(cd "$tmp" && sh "$repo_root/bin/bootstrap-check" 2>&1) || true
if printf '%s' "$out" | grep -q 'channels.scm is still a template'; then
    ok "bootstrap-check flags a template channels.scm"
else
    bad "bootstrap-check flags a template channels.scm"
fi
rm -rf "$tmp"

# -- guix-run: falls back to PATH when channels.scm is still a template -
tmp=$(mktemp -d)
git -C "$tmp" init -q
mkdir -p "$tmp/guix"
printf '(commit "REPLACE-WITH-REAL-COMMIT-x")\n' > "$tmp/guix/channels.scm"
out=$(cd "$tmp" && sh "$repo_root/bin/guix-run" echo "fallback-ran" 2>&1)
if printf '%s' "$out" | grep -q 'fallback-ran' \
   && printf '%s' "$out" | grep -q 'running unisolated'; then
    ok "guix-run falls back to PATH with a template channels.scm"
else
    bad "guix-run falls back to PATH with a template channels.scm"
fi
rm -rf "$tmp"

# -- cerebro-new-book: a course book is a *view* of notes/math/ --------
#    Run against the repo's own course (the generator resolves id: links
#    through Org, so it needs the real note database). It must be
#    idempotent -- it regenerates a tracked file, and a generator that
#    rewrites it differently every run would show up as noise in `git
#    status' forever.
if command -v emacs >/dev/null 2>&1; then
    book="$repo_root/notes/courses/analysis-1/book.org"
    before=$(cat "$book" 2>/dev/null || true)
    if sh "$repo_root/bin/cerebro-new-book" notes/courses/analysis-1 >/dev/null 2>&1 \
       && grep -q '^#+INCLUDE: "\.\./\.\./math/' "$book" \
       && ! grep -q 'begin_theorem' "$book" \
       && [ "$before" = "$(cat "$book")" ]; then
        ok "cerebro-new-book regenerates a course book of #+INCLUDEs, idempotently"
    else
        bad "cerebro-new-book regenerates a course book of #+INCLUDEs, idempotently"
    fi
else
    echo "skip - cerebro-new-book test (emacs not on PATH)"
fi

# -- cerebro-course: scaffolds a syllabus with an empty programme, and
#    generates no book until notes are actually listed ------------------
tmp=$(mktemp -d)
( cd "$repo_root" && sh bin/cerebro-course "$tmp/algebra" "Algebra I" >/dev/null )
if [ -f "$tmp/algebra/course.org" ] \
   && grep -q '#+COURSE_TITLE: Algebra I' "$tmp/algebra/course.org" \
   && grep -q '^\* Programme' "$tmp/algebra/course.org" \
   && [ ! -f "$tmp/algebra/book.org" ]; then
    ok "cerebro-course scaffolds a syllabus; no book until the programme lists notes"
else
    bad "cerebro-course scaffolds a syllabus; no book until the programme lists notes"
fi
rm -rf "$tmp"

# -- on-modify.cerebro: tag is auto-managed on the academic transition,
#    but a hand-added tag off-academic is left alone (needs jq) ---------
if command -v jq >/dev/null 2>&1; then
    hook="$repo_root/taskwarrior/hooks/on-modify.cerebro"

    out=$(printf '%s\n%s\n' \
        '{"project":"academic","tags":["cerebro"]}' \
        '{"project":"personal","tags":["cerebro"]}' | sh "$hook")
    if printf '%s' "$out" | jq -e '((.tags // []) | index("cerebro")) | not' >/dev/null; then
        ok "on-modify.cerebro drops the tag when a task leaves academic"
    else
        bad "on-modify.cerebro drops the tag when a task leaves academic"
    fi

    out=$(printf '%s\n%s\n' \
        '{"project":"personal","tags":["cerebro"]}' \
        '{"project":"personal","tags":["cerebro"],"priority":"H"}' | sh "$hook")
    if printf '%s' "$out" | jq -e '(.tags // []) | index("cerebro")' >/dev/null; then
        ok "on-modify.cerebro preserves a manual cerebro tag off-academic"
    else
        bad "on-modify.cerebro preserves a manual cerebro tag off-academic"
    fi
else
    echo "skip - on-modify.cerebro tests (jq not on PATH)"
fi

# -- cerebro-issue -p: records an Org priority, uppercased --------------
tmp=$(mktemp -d)
( cd "$tmp" && git init -q && mkdir issues && printf '#+TITLE: t\n' > issues/issues.org \
    && "$repo_root/bin/cerebro-issue" -p a "Prioritised issue" latex >/dev/null )
if grep -q '^\* TODO \[#A\] Prioritised issue' "$tmp/issues/issues.org"; then
    ok "cerebro-issue -p records an uppercased priority"
else
    bad "cerebro-issue -p records an uppercased priority"
fi
rm -rf "$tmp"

# -- cerebro-issue-scan: creates from a marker, then is idempotent ------
tmp=$(mktemp -d)
mkdir -p "$tmp/bin" "$tmp/issues"
cp "$repo_root/bin/cerebro-issue" "$repo_root/bin/cerebro-issue-scan" "$tmp/bin/"
chmod +x "$tmp"/bin/*
printf '#+TITLE: t\n' > "$tmp/issues/issues.org"
printf ';; CEREBRO-ISSUE: wire up the frobnicator\n' > "$tmp/src.el"
( cd "$tmp" && git init -q && git add -A \
    && bin/cerebro-issue-scan >/dev/null \
    && bin/cerebro-issue-scan > scan2.out )
if grep -q 'wire up the frobnicator' "$tmp/issues/issues.org" \
   && grep -q '0 created, 1 skipped' "$tmp/scan2.out"; then
    ok "cerebro-issue-scan creates once, then is idempotent"
else
    bad "cerebro-issue-scan creates once, then is idempotent"
fi
rm -rf "$tmp"

# -- cerebro-issues next/note: pick the top issue, log a note (needs
#    emacs; CEREBRO_ISSUES_FILE keeps it off the real tracker) ----------
if command -v emacs >/dev/null 2>&1; then
    tmp=$(mktemp -d)
    cat > "$tmp/issues.org" <<'ISS'
#+TITLE: t
* TODO [#C] Low :x:
:PROPERTIES:
:ID: 20260101T000009
:END:
* TODO [#A] High :x:
:PROPERTIES:
:ID: 20260101T000008
:END:
ISS
    nxt=$(CEREBRO_ISSUES_FILE="$tmp/issues.org" emacs --batch \
              -l "$repo_root/bin/cerebro-issues.el" -- next 2>/dev/null)
    CEREBRO_ISSUES_FILE="$tmp/issues.org" emacs --batch \
        -l "$repo_root/bin/cerebro-issues.el" -- note 20260101T000008 "in progress" >/dev/null 2>&1 || true
    if printf '%s' "$nxt" | grep -q 'High' \
       && grep -q '^- \[.*\] in progress' "$tmp/issues.org"; then
        ok "cerebro-issues next picks [#A], note logs a timestamped line"
    else
        bad "cerebro-issues next picks [#A], note logs a timestamped line"
    fi
    rm -rf "$tmp"
else
    echo "skip - cerebro-issues next/note test (emacs not on PATH)"
fi

# -- cerebro-note new: writes a born-classified note (id, :seed:, msc) in
#    notes/math/ -- the concept-graph directory every way of making a note
#    now defaults to (cerebro-math-directory; the dir is created if
#    missing, so a fresh clone needs no setup step) ----------------------
tmp=$(mktemp -d)
( cd "$tmp" && git init -q && mkdir notes \
    && "$repo_root/bin/cerebro-note" new "Test Note" analysis,topology 54D30 >/dev/null )
f=$(ls "$tmp"/notes/math/*.org 2>/dev/null | head -1)
if [ -n "$f" ] && grep -q '^#+TITLE: Test Note' "$f" \
   && grep -q ':seed:analysis:topology:' "$f" \
   && grep -q '^:ID:' "$f" && grep -q '^#+MSC: 54D30' "$f"; then
    ok "cerebro-note new writes a born-classified note into notes/math/"
else
    bad "cerebro-note new writes a born-classified note into notes/math/"
fi
rm -rf "$tmp"

# -- cerebro dispatcher: help prints usage, unknown command errors -------
if "$repo_root/bin/cerebro" help 2>&1 | grep -q 'command-line workflow' \
   && ! "$repo_root/bin/cerebro" frobnicate >/dev/null 2>&1; then
    ok "cerebro dispatcher: help works, unknown command fails"
else
    bad "cerebro dispatcher: help works, unknown command fails"
fi

# -- cerebro-issues close: sets DONE on an isolated issue file (needs
#    emacs; CEREBRO_ISSUES_FILE redirects it off the real tracker) -------
if command -v emacs >/dev/null 2>&1; then
    tmp=$(mktemp -d)
    cat > "$tmp/issues.org" <<'ISS'
#+TITLE: t
* TODO Sample issue :x:
:PROPERTIES:
:ID: 20260101T000000
:CREATED: [2026-01-01 Mon 00:00]
:END:
ISS
    CEREBRO_ISSUES_FILE="$tmp/issues.org" emacs --batch \
        -l "$repo_root/bin/cerebro-issues.el" -- close 20260101T000000 >/dev/null 2>&1 || true
    if grep -q '^\* DONE Sample issue' "$tmp/issues.org"; then
        ok "cerebro-issues close sets an issue DONE"
    else
        bad "cerebro-issues close sets an issue DONE"
    fi
    rm -rf "$tmp"
else
    echo "skip - cerebro-issues close test (emacs not on PATH)"
fi

echo "-- $pass passed, $fail failed --"
[ "$fail" -eq 0 ]
