#!/usr/bin/env bash
# Checks next-version.sh against throwaway repositories. Usage: .github/release/next-version_test.sh
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/next-version.sh"
failed=0
dirs=()
trap 'rm -rf "${dirs[@]}"' EXIT

# Makes an empty repository in the given directory.
repo() {
  local dir="$1"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
}
commit() { # commit <dir> <file> <content>
  mkdir -p "$1/$(dirname "$2")"
  echo "$3" >"$1/$2"
  git -C "$1" add -A
  git -C "$1" commit -qm "$2"
}
expect() { # expect <description> <want> <dir>
  local got
  got="$(cd "$3" && "$script" Dockerfile 2>/dev/null)" || got="(failed)"
  if [ "$got" = "$2" ]; then echo "ok   - $1"; else echo "FAIL - $1: want '$2', got '$got'" >&2; failed=1; fi
}

d="$(mktemp -d)"; dirs+=("$d"); repo "$d"; commit "$d" Dockerfile a; git -C "$d" tag v0.1.0
expect "no change since the tag: nothing" "" "$d"

commit "$d" .github/workflows/image.yml a; commit "$d" renovate.json a; commit "$d" test/run.sh a; commit "$d" README.md a
expect "only workflows, renovate.json, tests and docs changed: nothing" "" "$d"

commit "$d" Dockerfile b
expect "the Dockerfile changed: the next patch" "v0.1.1" "$d"

git -C "$d" tag v0.10.0 HEAD~1; git -C "$d" tag v0.9.3 HEAD~1
expect "the latest tag is compared as a version, not as text" "v0.10.1" "$d"

git -C "$d" tag v0.11.0.1; git -C "$d" tag v1.0.0-rc.1; git -C "$d" tag latest
expect "tags that are not vX.Y.Z are ignored" "v0.10.1" "$d"

git -C "$d" tag v0.10.1
expect "HEAD already carries the latest tag: nothing" "" "$d"

d="$(mktemp -d)"; dirs+=("$d"); repo "$d"; commit "$d" Dockerfile a
expect "no version tag at all: fails" "(failed)" "$d"

exit "$failed"
