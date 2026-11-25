#!/usr/bin/env bash
# Deploy keys of the site workflow (~/dev/.github/workflows/cerebro-site.yml).
# Read-only SSH keys on the private repos the build needs, one write key on cerebro
# for gh-pages; the private halves go only into the secrets of 4137314/dev and are
# deleted here.  Run once (again to rotate: remove the old deploy keys first).
set -euo pipefail
owner=4137314
read_repos=(computer-science remote-sensing knowledge-base)
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
for r in "${read_repos[@]}" cerebro; do
  ssh-keygen -q -t ed25519 -N '' -C "git@github.com:$owner/$r.git" -f "$r"
done
for r in "${read_repos[@]}"; do
  gh repo deploy-key add "$r.pub" --repo "$owner/$r" --title "dev: cerebro site (read)"
done
gh repo deploy-key add cerebro.pub --repo "$owner/cerebro" --title "dev: cerebro site (gh-pages)" --allow-write
cat "${read_repos[@]}" | gh secret set SITE_READ_KEYS --repo "$owner/dev"
gh secret set SITE_DEPLOY_KEY --repo "$owner/dev" < cerebro
gh secret list --repo "$owner/dev"
