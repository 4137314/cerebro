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

# -- guix-run: two branches, and the fast one is the point --------------
#    (a) outside a guix environment with a template channels.scm: run the
#        command anyway, loudly. GUIX_ENVIRONMENT is unset explicitly --
#        this suite is normally run from *inside* the environment, which
#        is the other branch.
#    (b) inside one: run the command straight away. `guix time-machine'
#        costs ~90s even when every package is already on PATH, which is
#        what used to make `make test' and the git hooks unbearable.
tmp=$(mktemp -d)
git -C "$tmp" init -q
mkdir -p "$tmp/guix"
printf '(commit "REPLACE-WITH-REAL-COMMIT-x")\n' > "$tmp/guix/channels.scm"
out=$(cd "$tmp" && env -u GUIX_ENVIRONMENT sh "$repo_root/bin/guix-run" echo "fallback-ran" 2>&1)
inside=$(cd "$tmp" && GUIX_ENVIRONMENT=/gnu/store/pretend-profile \
             sh "$repo_root/bin/guix-run" echo "direct-ran" 2>&1)
if printf '%s' "$out" | grep -q 'fallback-ran' \
   && printf '%s' "$out" | grep -q 'running unisolated' \
   && [ "$inside" = "direct-ran" ]; then
    ok "guix-run: warns outside the environment, runs directly inside it"
else
    bad "guix-run: warns outside the environment, runs directly inside it"
fi
rm -rf "$tmp"

# -- cerebro-course: a course is ONE file that indexes notes ----------
#    Scaffolded into notes/courses/<slug>.org, with a programme section
#    and no second, generated file to keep in step with it.
tmp=$(mktemp -d)
( cd "$tmp" && git init -q && mkdir -p notes/courses \
    && sh "$repo_root/bin/cerebro-course" algebra-I "Algebra I" >/dev/null )
course="$tmp/notes/courses/algebra-I.org"
if [ -f "$course" ] \
   && grep -q '#+COURSE_TITLE: Algebra I' "$course" \
   && grep -q '^\* Programme' "$course" \
   && grep -q '^\* Appendices' "$course" \
   && [ ! -e "$tmp/notes/courses/algebra-I" ] \
   && [ ! -e "$tmp/notes/courses/algebra-I/book.org" ] \
   && ! grep -qi 'assessment\|examination' "$course"; then
    ok "cerebro-course scaffolds ONE file: programme, appendices, no exam section"
else
    bad "cerebro-course scaffolds ONE file: programme, appendices, no exam section"
fi
rm -rf "$tmp"

# -- the composition is a *view*: every note enters the composed document
#    as an #+INCLUDE, never as a copy, and it lands in .build/ rather
#    than in the repository. Run against the repo's own course, since
#    resolving id: links needs the real note database.
if command -v emacs >/dev/null 2>&1; then
    composed="$repo_root/notes/courses/.build/analysis-A-handbook.org"
    rm -f "$composed"
    if ( cd "$repo_root" && emacs --batch -L .emacs.d/lisp -l cerebro-course \
            --eval '(progn (org-id-update-id-locations (cerebro-note-files) t)
                           (princ (cerebro-course-source
                                   (expand-file-name "notes/courses/analysis-A.org")
                                   (quote handbook))))' >/dev/null 2>&1 ) \
       && grep -q '^#+INCLUDE: "\.\./\.\./math/' "$composed" \
       && grep -q '^#+LATEX: .appendix' "$composed" \
       && ! grep -q 'begin_theorem' "$composed"; then
        ok "a course composes into .build/ as #+INCLUDEs, with appendices"
    else
        bad "a course composes into .build/ as #+INCLUDEs, with appendices"
    fi
else
    echo "skip - course composition test (emacs not on PATH)"
fi

# -- cerebro-course-export: refuses politely on something that is not a
#    course. The happy path (four LaTeX compiles) belongs to
#    `make export-matrix', not to a gate that must stay in seconds.
if [ -x "$repo_root/bin/cerebro-course-export" ]; then
    tmp=$(mktemp -d)
    printf '#+TITLE: not a course\n' > "$tmp/plain.org"
    if ! sh "$repo_root/bin/cerebro-course-export" "$tmp/plain.org" >/dev/null 2>&1 \
       && ! sh "$repo_root/bin/cerebro-course-export" "$tmp/nonexistent.org" >/dev/null 2>&1; then
        ok "cerebro-course-export refuses a file with no '* Programme'"
    else
        bad "cerebro-course-export refuses a file with no '* Programme'"
    fi
    rm -rf "$tmp"
fi

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

# -- cerebro-note names a note by the digest of its metadata, and gets
#    the SAME digest as the Elisp implementation. Two programs compute
#    this name (bin/cerebro-note in sh, cerebro-hash.el in Emacs); if
#    they ever disagreed, one would rename every note the other had just
#    named, forever. So both are pinned to one literal constant --
#    `cerebro-hash-test-digest-is-pinned' asserts the same string.
tmp=$(mktemp -d)
mkdir -p "$tmp/notes/math"
cat > "$tmp/notes/math/fixture.org" <<'NOTE'
:PROPERTIES:
:ID:       abc-123
:END:
#+TITLE: Supremum and infimum
#+DATE: [2026-08-06 Thu]
#+FILETAGS: :seed:analysis:
#+MSC: 26A03

Body text, which is not part of the note's identity.
NOTE
( cd "$tmp" && git init -q && "$repo_root/bin/cerebro-note" rehash >/dev/null 2>&1 )
if [ -f "$tmp/notes/math/a4e650150324.org" ] \
   && grep -q '^#+HASH: a4e650150324' "$tmp/notes/math/a4e650150324.org" \
   && grep -q '^#+MSC: 26A03' "$tmp/notes/math/a4e650150324.org"; then
    ok "cerebro-note rehash agrees with cerebro-hash.el on the digest"
else
    bad "cerebro-note rehash agrees with cerebro-hash.el on the digest"
fi
rm -rf "$tmp"

# -- cerebro dispatcher: help prints usage, unknown command errors -------
if "$repo_root/bin/cerebro" help 2>&1 | grep -q 'command-line workflow' \
   && ! "$repo_root/bin/cerebro" frobnicate >/dev/null 2>&1; then
    ok "cerebro dispatcher: help works, unknown command fails"
else
    bad "cerebro dispatcher: help works, unknown command fails"
fi

# -- cerebro export: PROFILE is required, and every profile the help
#    advertises is one cerebro-latex.el actually knows.
#
#    The default used to be `full', which is not a profile and has not
#    been one since the fourteen presets became six -- it is a *content
#    mode*, the internal half of a profile. So the obvious way to try the
#    command, `cerebro export notes/x.org', failed with "unknown export
#    profile `full'": a name the user never typed and could not find in
#    the help. A default nobody can use is worse than a required
#    argument, and this is what keeps the help and the alist in step.
out=$("$repo_root/bin/cerebro" export notes/README.org 2>&1) || true
if printf '%s' "$out" | grep -q 'export needs a profile' \
   && ! printf '%s' "$out" | grep -q 'full'; then
    ok "cerebro export: a missing profile is refused by name"
else
    bad "cerebro export: a missing profile is refused by name"
fi

if command -v emacs >/dev/null 2>&1; then
    advertised=$("$repo_root/bin/cerebro" help \
        | sed -n 's/.*(\(syllabus[^)]*\)).*/\1/p' | tr '|' ' ')
    known=$(emacs --batch -L "$repo_root/.emacs.d/lisp" --eval \
        '(progn (require (quote cerebro-latex))
                (princ (mapconcat (function symbol-name)
                                  (mapcar (function car) cerebro-latex-profiles) " ")))' \
        2>/dev/null)
    missing=""
    for p in $advertised; do
        case " $known " in *" $p "*) ;; *) missing="$missing $p" ;; esac
    done
    for p in $known; do
        case " $advertised " in *" $p "*) ;; *) missing="$missing $p" ;; esac
    done
    if [ -n "$advertised" ] && [ -z "$missing" ]; then
        ok "cerebro help advertises exactly the export profiles that exist"
    else
        bad "cerebro help advertises exactly the export profiles that exist ($missing)"
    fi
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

# -- cerebro mode: the two macro-modes, from the shell ------------------
#    Read, set, and remembered in a plain one-word file -- redirected to a
#    temp HOME-less checkout would need the whole repo, so instead the
#    real state file is saved and restored around the test. Running the
#    suite must not change which mode the next session opens in.
if command -v emacs >/dev/null 2>&1; then
    state="$repo_root/.emacs.d/var/mode"
    saved=$(cat "$state" 2>/dev/null || true)

    report=$("$repo_root/bin/cerebro" mode 2>&1)
    set_dev=$("$repo_root/bin/cerebro" mode dev 2>&1)
    stored=$(cat "$state" 2>/dev/null || true)
    # An unknown mode is refused, and refused *loudly* -- a typo must not
    # silently leave the session in whichever mode it was in.
    if "$repo_root/bin/cerebro" mode sideways >/dev/null 2>&1; then bad_mode=yes; else bad_mode=no; fi
    # CEREBRO_MODE wins over the remembered mode, for one command.
    env_mode=$(CEREBRO_MODE=math "$repo_root/bin/cerebro" mode 2>&1)

    # Restore whatever was there before (or nothing).
    if [ -n "$saved" ]; then printf '%s\n' "$saved" > "$state"; else rm -f "$state"; fi

    if printf '%s' "$report" | grep -q 'writable' \
       && printf '%s' "$set_dev" | grep -q 'guard rail is off' \
       && [ "$stored" = "dev" ] \
       && [ "$bad_mode" = "no" ] \
       && printf '%s' "$env_mode" | grep -q 'in force   math (from the environment)'; then
        ok "cerebro mode: reports, sets, remembers, and CEREBRO_MODE wins"
    else
        bad "cerebro mode: reports, sets, remembers, and CEREBRO_MODE wins"
    fi
else
    echo "skip - cerebro mode tests (emacs not on PATH)"
fi

# -- cerebro issue list is filtered by the mode, and says so ------------
#    The filter may only hide the *other* mode's explicit work: an issue
#    tagged for neither belongs to both, or the backlog quietly shrinks.
if command -v emacs >/dev/null 2>&1; then
    tmp=$(mktemp -d)
    cat > "$tmp/issues.org" <<'ISS'
#+TITLE: t
* TODO Build the exporter :guix:ci:
:PROPERTIES:
:ID: 20260101T000001
:END:
* TODO Prove the thing :research:
:PROPERTIES:
:ID: 20260101T000002
:END:
* TODO Something unclassified
:PROPERTIES:
:ID: 20260101T000003
:END:
ISS
    in_math=$(cd "$repo_root" && CEREBRO_MODE=math CEREBRO_ISSUES_FILE="$tmp/issues.org" \
        emacs --batch -l "$repo_root/bin/cerebro-issues.el" -- list 2>/dev/null)
    in_dev=$(cd "$repo_root" && CEREBRO_MODE=dev CEREBRO_ISSUES_FILE="$tmp/issues.org" \
        emacs --batch -l "$repo_root/bin/cerebro-issues.el" -- list 2>/dev/null)
    every=$(cd "$repo_root" && CEREBRO_MODE=math CEREBRO_ISSUES_FILE="$tmp/issues.org" \
        emacs --batch -l "$repo_root/bin/cerebro-issues.el" -- list --all-modes 2>/dev/null)
    if printf '%s' "$in_math" | grep -q 'Prove the thing' \
       && ! printf '%s' "$in_math" | grep -q 'Build the exporter' \
       && printf '%s' "$in_dev" | grep -q 'Build the exporter' \
       && ! printf '%s' "$in_dev" | grep -q 'Prove the thing' \
       && printf '%s' "$in_math" | grep -q 'unclassified' \
       && printf '%s' "$in_dev" | grep -q 'unclassified' \
       && [ "$(printf '%s\n' "$every" | grep -c 'TODO')" -eq 3 ]; then
        ok "cerebro issue list shows this mode's work, and --all-modes shows all"
    else
        bad "cerebro issue list shows this mode's work, and --all-modes shows all"
    fi
    rm -rf "$tmp"
fi

# -- make help is derived from the makefile, and covers every target ----
#    `make help' reads the `##' comment off each target line, so a
#    renamed target renames its own help line. What that cannot catch is
#    a target added with no comment at all -- it simply never appears --
#    so every .PHONY target is checked to be documented.
if command -v make >/dev/null 2>&1; then
    helptext=$(cd "$repo_root" && make help 2>/dev/null)
    phony=$(sed -n '/^\.PHONY:/,/[^\\]$/p' "$repo_root/makefile" \
                | tr ' \t' '\n\n' | sed 's/\\$//' | grep -v '^\.PHONY:$' | grep -v '^$')
    missing=""
    for target in $phony; do
        printf '%s\n' "$helptext" | grep -qE "^  $target " || missing="$missing $target"
    done
    if [ -z "$missing" ]; then
        ok "make help documents every phony target"
    else
        bad "make help documents every phony target (missing:$missing)"
    fi
fi

echo "-- $pass passed, $fail failed --"
[ "$fail" -eq 0 ]
