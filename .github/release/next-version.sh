#!/usr/bin/env bash
# Prints the next patch version (v1.2.4 after v1.2.3) when the given paths changed between the latest vX.Y.Z tag and
# HEAD, and prints nothing when they did not. Tags of another shape (v0.1.0.1, v1.0.0-rc.1) are not versions here.
# Fails when there is no vX.Y.Z tag: the first version is chosen by hand.
#
# Usage: next-version.sh <path>...   (in a checkout with its tags)
set -euo pipefail

latest="$(git tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)"
if [ -z "$latest" ]; then
  echo "no vX.Y.Z tag" >&2
  exit 1
fi

if git diff --quiet "$latest" HEAD -- "$@"; then
  echo "no change in $* since $latest" >&2
  exit 0
fi

IFS=. read -r major minor patch <<<"${latest#v}"
echo "v$major.$minor.$((patch + 1))"
