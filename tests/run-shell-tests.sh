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

# -- cerebro-new-book: scaffolds one #+INCLUDE per note, skips itself --
tmp=$(mktemp -d)
mkdir -p "$tmp/course"
: > "$tmp/course/a.org"
: > "$tmp/course/b.org"
: > "$tmp/course/README.org"
sh "$repo_root/bin/cerebro-new-book" "$tmp/course" "Test Book" >/dev/null
includes=$(grep -c '^#+INCLUDE:' "$tmp/course/book.org")
if [ "$includes" = "2" ] && ! grep -q 'README.org' "$tmp/course/book.org"; then
    ok "cerebro-new-book includes notes but skips README.org/book.org"
else
    bad "cerebro-new-book includes notes but skips README.org/book.org"
fi
rm -rf "$tmp"

echo "-- $pass passed, $fail failed --"
[ "$fail" -eq 0 ]
