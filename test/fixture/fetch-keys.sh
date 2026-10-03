#!/bin/sh
# Fetches the authorized keys, or falls back to a given file: fetch-keys.sh <URL> <fallback> <out>
set -u

url="$1"
fallback="$2"
out="$3"
tmp="${out}.tmp"

rm -f "$tmp"
if curl -fsS --proto =https --connect-timeout 5 --max-time 15 --max-filesize 65536 \
     -o "$tmp" "$url" \
   && count=$(ssh-keygen -l -f "$tmp" 2>/dev/null | wc -l) \
   && [ "$count" -gt 0 ]; then
  echo "authorized_keys: fetched ${count} key(s) from ${url}"
elif cp "$fallback" "$tmp" 2>/dev/null; then
  echo "authorized_keys: could not fetch keys from ${url}; using ${fallback}" >&2
else
  rm -f "$tmp"
  echo "authorized_keys: could not fetch keys from ${url}, and ${fallback} is unreadable; no authorized_keys" >&2
  exit 0
fi

chmod 0444 "$tmp"
mv -f "$tmp" "$out"
