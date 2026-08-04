#!/usr/bin/env bash
#
# Publish landing/ to the gh-pages branch.
#
# GitHub Pages can't serve an arbitrary subdirectory, and /docs is taken by the
# workstream documentation — hence a dedicated branch. Uses a temporary worktree
# so your working tree and current branch are never touched.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "${here}/.." && pwd)"
branch="gh-pages"
worktree="$(mktemp -d)"

cleanup() {
  git -C "$repo" worktree remove --force "$worktree" 2>/dev/null || true
  rm -rf "$worktree"
}
trap cleanup EXIT

cd "$repo"

if git show-ref --verify --quiet "refs/heads/${branch}"; then
  git worktree add "$worktree" "$branch" >/dev/null
else
  # Orphan: the site shares no history with main, so its commits don't clutter
  # the code log and vice versa.
  git worktree add --detach "$worktree" >/dev/null
  git -C "$worktree" checkout --orphan "$branch" >/dev/null 2>&1
  git -C "$worktree" rm -rf . >/dev/null 2>&1 || true
fi

find "$worktree" -maxdepth 1 ! -path "$worktree" ! -name '.git' -exec rm -rf {} +
cp -R "${here}/." "$worktree/"
rm -f "${worktree}/publish.sh"

# Skip Jekyll: it would otherwise ignore any file or directory starting with an
# underscore, and there's nothing here for it to build anyway.
touch "${worktree}/.nojekyll"

cd "$worktree"
git add -A
if git diff --cached --quiet; then
  echo "No changes to publish."
  exit 0
fi

git commit -q -m "site: publish landing page

Generated from landing/ by landing/publish.sh. Do not edit this branch
directly — changes here are overwritten on the next publish."
git push -q -u origin "$branch"

echo "Published to ${branch}."
echo
echo "If this is the first publish, enable it once:"
echo "  Settings -> Pages -> Source: Deploy from a branch -> ${branch} / (root)"
echo
echo "  https://andrewsb.github.io/FinanceKitSync/"
