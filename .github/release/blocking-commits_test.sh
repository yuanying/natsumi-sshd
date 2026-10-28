#!/usr/bin/env bash
# Checks blocking-commits.sh against throwaway repositories. Usage: .github/release/blocking-commits_test.sh
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/blocking-commits.sh"
failed=0
dirs=()
trap 'rm -rf "${dirs[@]}"' EXIT

renovate="renovate[bot] <29139614+renovate[bot]@users.noreply.github.com>"
responder="fraction-vuln-responder[bot] <348762456+fraction-vuln-responder[bot]@users.noreply.github.com>"
human="Someone <someone@example.com>"

# Makes an empty repository in the given directory.
repo() {
  local dir="$1"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
}
commit() { # commit <dir> <author> <file> <content>
  mkdir -p "$1/$(dirname "$3")"
  echo "$4" >"$1/$3"
  git -C "$1" add -A
  git -C "$1" commit -q --author="$2" -m "change $3"
}
# Merges a branch made of one commit by the given author, as a pull request's merge commit would.
merge() { # merge <dir> <author> <file> <content>
  git -C "$1" checkout -q -b topic
  commit "$@"
  git -C "$1" checkout -q main
  git -C "$1" merge -q --no-ff --no-edit topic
  git -C "$1" branch -q -D topic
}
# The authors of the commits the script prints, one per line: it prints "<sha> <author>\t<subject>".
expect() { # expect <description> <want> <dir>
  local got
  got="$(cd "$3" && "$script" Dockerfile 2>/dev/null | cut -f1 | cut -d' ' -f2-)" || got="(failed)"
  if [ "$got" = "$2" ]; then echo "ok   - $1"; else echo "FAIL - $1: want '$2', got '$got'" >&2; failed=1; fi
}

d="$(mktemp -d)"; dirs+=("$d"); repo "$d"
commit "$d" "$human" Dockerfile a; git -C "$d" tag v0.1.0
expect "nothing since the tag: nothing blocks" "" "$d"

commit "$d" "$responder" Dockerfile b
expect "a fix by the vuln-responder bot alone: nothing blocks" "" "$d"

commit "$d" "$renovate" Dockerfile c
expect "the vuln-responder bot and Renovate mixed: nothing blocks" "" "$d"

merge "$d" "$responder" Dockerfile d
expect "merge commits are not counted, whoever made them" "" "$d"

commit "$d" "$human" README.md a; commit "$d" "$human" .github/workflows/image.yml a
expect "a person's commits that leave the Dockerfile alone do not block" "" "$d"

commit "$d" "$human" Dockerfile e
expect "a person's commit to the Dockerfile blocks" "Someone" "$d"

commit "$d" "$responder" Dockerfile f
expect "a person's commit still blocks among the bots' commits" "Someone" "$d"

git -C "$d" tag v0.1.1 HEAD~1
expect "commits before the latest tag are not counted" "" "$d"

git -C "$d" tag v0.1.1.1; git -C "$d" tag v1.0.0-rc.1
commit "$d" "$human" Dockerfile g
expect "tags that are not vX.Y.Z are ignored" "Someone" "$d"

d="$(mktemp -d)"; dirs+=("$d"); repo "$d"; commit "$d" "$responder" Dockerfile a
expect "no version tag at all: fails" "(failed)" "$d"

exit "$failed"
