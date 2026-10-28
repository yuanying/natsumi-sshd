#!/usr/bin/env bash
# Prints the commits that keep a vulnerability fix from being released at once: those since the latest vX.Y.Z tag that
# change the given paths and were not made by Renovate or by the vuln-responder bot, one per line as
# "<sha> <author>\t<subject>". Prints nothing when every such commit is the bots'. Merge commits are not counted: a
# pull request's merge carries no change of its own. Fails when there is no vX.Y.Z tag, as next-version.sh does.
#
# Usage: blocking-commits.sh <path>...   (in a checkout with its tags)
set -euo pipefail

latest="$(git tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)"
if [ -z "$latest" ]; then
  echo "no vX.Y.Z tag" >&2
  exit 1
fi

git log --no-merges --reverse --format='%h %an%x09%s' "$latest..HEAD" -- "$@" |
  awk -F'\t' '{ author = substr($1, index($1, " ") + 1) }
    author != "renovate[bot]" && author != "fraction-vuln-responder[bot]"'
