#!/usr/bin/env bash
# Runs the image the way its user runs it and checks that the tools work:
#   - an init step, as nobody with a read-only root, puts the authorized keys in place (fetch-keys.sh)
#   - sshd runs as UID 1001 with a read-only root, no capabilities, and passwd/group/sshd_config from a mount
#   - a client logs in with a key and uses the tools
#
# Usage: test/run.sh [image]
#   CONFIG_DIR  the directory with sshd_config, shell, passwd, group and fetch-keys.sh (default: test/fixture)
#   FETCH_URL   also fetch the keys from this URL with the host network (default: skip)
set -euo pipefail

image="${1:-natsumi-sshd:test}"
here="$(cd "$(dirname "$0")" && pwd)"
config="$(cd "${CONFIG_DIR:-$here/fixture}" && pwd)"
name="natsumi-sshd-test-$$"
work="$(mktemp -d)"
failed=0

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  # Files written by the containers belong to other UIDs.
  docker run --rm -u 0 -v "$work:/w" --entrypoint sh "$image" -c 'rm -rf /w/*' >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1" >&2; failed=1; }
check() {
  local desc="$1"; shift
  if "$@"; then pass "$desc"; else fail "$desc"; fi
}

# Runs a command in the image as an unprivileged user with a read-only root.
in_image() {
  docker run --rm --network none --read-only -u 1001:1001 --cap-drop ALL \
    --security-opt no-new-privileges "$image" "$@"
}

echo "# image $image, config $config"

# --- the tools -------------------------------------------------------------------------------------------
for cmd in sshd ssh ssh-keygen curl vim git less jq rg rsync ps bash; do
  check "has $cmd" in_image sh -c "command -v $cmd >/dev/null || test -x /usr/sbin/$cmd"
done
check "has no sudo" in_image sh -c '! command -v sudo >/dev/null'
check "has no host keys baked in" in_image sh -c '! ls /etc/ssh/ssh_host_* >/dev/null 2>&1'
check "has CA certificates" in_image test -s /etc/ssl/certs/ca-certificates.crt
check "has no apt lists" in_image sh -c '[ -z "$(ls -A /var/lib/apt/lists 2>/dev/null | grep -v -e ^lock$ -e ^partial$)" ]'

# --- keys for the test ------------------------------------------------------------------------------------
mkdir -p "$work/hostkeys" "$work/client" "$work/fallback" "$work/authorized"
# ssh-keygen needs a user in passwd, so make them as root. The host key stays root's and readable by all,
# as a mounted Secret is: sshd refuses a key of its own UID that others can read.
docker run --rm --network none -u 0 -v "$work:/w" "$image" sh -c "
  ssh-keygen -q -t ed25519 -N '' -C test-host -f /w/hostkeys/ssh_host_ed25519_key &&
  chmod 0444 /w/hostkeys/ssh_host_ed25519_key &&
  ssh-keygen -q -t ed25519 -N '' -C test-client -f /w/client/id_ed25519 &&
  chown -R $(id -u):$(id -g) /w/client"
cp "$work/client/id_ed25519.pub" "$work/fallback/authorized_keys"
chmod 0444 "$work/fallback/authorized_keys"
chmod 0777 "$work/authorized"

# --- fetch-keys.sh, as the init step runs it ---------------------------------------------------------------
fetch_keys() {
  local network="$1" url="$2"
  docker run --rm --network "$network" --read-only -u 65534:65534 --cap-drop ALL \
    --security-opt no-new-privileges \
    -v "$config:/etc/natsumi-sshd:ro" \
    -v "$work/fallback:/etc/natsumi-sshd-fallback:ro" \
    -v "$work/authorized:/etc/natsumi-sshd-authorized" \
    "$image" sh /etc/natsumi-sshd/fetch-keys.sh "$url" \
      /etc/natsumi-sshd-fallback/authorized_keys /etc/natsumi-sshd-authorized/authorized_keys
}

if [ -n "${FETCH_URL:-}" ]; then
  out="$(fetch_keys host "$FETCH_URL" 2>&1)" || true
  echo "$out" | sed 's/^/#   /'
  check "fetch-keys.sh fetches the keys from $FETCH_URL" grep -q 'fetched [1-9][0-9]* key' <<<"$out"
fi

# Without a network the fetch fails and the fallback is used; the login below uses it.
out="$(fetch_keys none https://github.com/nobody.keys 2>&1)" || true
echo "$out" | sed 's/^/#   /'
check "fetch-keys.sh falls back without a network" grep -q 'using /etc/natsumi-sshd-fallback' <<<"$out"
check "fetch-keys.sh puts the fallback keys in place" cmp -s "$work/fallback/authorized_keys" "$work/authorized/authorized_keys"

# --- sshd -----------------------------------------------------------------------------------------------
docker run -d --name "$name" --network none --read-only -u 1001:1001 --group-add 2000 --cap-drop ALL \
  --security-opt no-new-privileges \
  -v "$config:/etc/natsumi-sshd:ro" \
  -v "$config/passwd:/etc/passwd:ro" \
  -v "$config/group:/etc/group:ro" \
  -v "$work/hostkeys:/etc/natsumi-sshd-keys:ro" \
  -v "$work/authorized:/etc/natsumi-sshd-authorized:ro" \
  --tmpfs /tmp:mode=1777 \
  --tmpfs /home/owner:uid=1001,gid=1001,mode=0700 \
  "$image" /usr/sbin/sshd -D -e -f /etc/natsumi-sshd/sshd_config >/dev/null

# Runs the client in the image, in sshd's network namespace.
client() {
  docker run --rm -i --network "container:$name" -u 0 -v "$work/client:/client:ro" "$image" \
    ssh -p 2222 -i /client/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$@"
}

up=0
for _ in $(seq 1 30); do
  if [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" != true ]; then break; fi
  if client -o ConnectTimeout=1 natsumi@127.0.0.1 true </dev/null >/dev/null 2>&1; then up=1; break; fi
  sleep 1
done
if [ "$up" = 1 ]; then
  pass "sshd starts as 1001 with a read-only root and accepts the key"
else
  fail "sshd starts as 1001 with a read-only root and accepts the key"
  docker logs "$name" 2>&1 | sed 's/^/#   /'
  exit 1
fi

remote() { client natsumi@127.0.0.1 "$@" </dev/null; }

git_works() { remote 'git --version' | grep -q '^git version'; }
other_tools_run() {
  remote 'less --version >/dev/null && echo "{\"a\":1}" | jq -e .a >/dev/null && rg --version >/dev/null &&
    rsync --version >/dev/null && ps -e >/dev/null'
}
login_shell() {
  echo 'echo "login:$0"; exit' | client -T natsumi@127.0.0.1 2>/dev/null | grep -qx 'login:-.*bash'
}
sftp_umask() {
  # The uploaded file keeps its own mode less the umask, so start from 0666.
  docker run --rm --network "container:$name" -u 0 -v "$work/client:/client:ro" "$image" sh -c '
    umask 000 && echo test > /tmp/sftp.txt && echo "put /tmp/sftp.txt /tmp/sftp.txt" |
      sftp -P 2222 -i /client/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -b - natsumi@127.0.0.1' \
    >/dev/null &&
    test "$(remote 'stat -c %a /tmp/sftp.txt')" = 660
}
rejects_unknown_key() {
  ! docker run --rm --network "container:$name" -u 0 "$image" sh -c '
    ssh-keygen -q -t ed25519 -N "" -f /tmp/k &&
    ssh -p 2222 -i /tmp/k -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      natsumi@127.0.0.1 true' >/dev/null 2>&1
}

check "logs in as 1001 with the shared group" test "$(remote 'id -u; id -G | tr " " "\n" | grep -x 2000')" = "1001
2000"
check "the login shell sets umask 007" test "$(remote umask)" = 0007
check "git works" git_works
check "git commits in a new repository" test "$(remote 'cd /tmp && git init -q r && cd r &&
  git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m テスト && git log --format=%s')" = "テスト"
check "vim edits Japanese text with LANG=C.UTF-8" test "$(remote 'printf "こんにちは\n" > /tmp/v.txt &&
  LANG=C.UTF-8 vim -Es -n -u NONE -c "normal! \$x" -c wq /tmp/v.txt; cat /tmp/v.txt')" = "こんにち"
check "counts Japanese characters with LANG=C.UTF-8" test "$(remote 'printf こんにちは | LANG=C.UTF-8 wc -m')" = 5
check "less, jq, rg, rsync, ps run" other_tools_run
check "an interactive login runs the login shell" login_shell
check "sftp writes with umask 007" sftp_umask
check "rejects an unknown key" rejects_unknown_key

if [ "$failed" != 0 ]; then
  docker logs "$name" 2>&1 | sed 's/^/#   /'
  echo "# some checks failed" >&2
  exit 1
fi
echo "# all checks passed"
