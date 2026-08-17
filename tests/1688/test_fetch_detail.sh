#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../scripts/1688/fetch_detail.sh
source "$ROOT/scripts/1688/fetch_detail.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAKE_CURL="$TMP/curl"
cat > "$FAKE_CURL" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$FAKE_CURL_LOG"
count=0
[ -f "$FAKE_CURL_COUNT" ] && count="$(<"$FAKE_CURL_COUNT")"
count=$((count + 1))
printf '%s' "$count" > "$FAKE_CURL_COUNT"

out=''
prev=''
for arg in "$@"; do
  if [ "$prev" = '-o' ]; then out="$arg"; fi
  prev="$arg"
done

if [ "${FAKE_CURL_MODE:-fallback-success}" = 'primary-success' ]; then
  printf '1234567890' > "$out"
  printf '200'
  exit 0
fi
if [ "${FAKE_CURL_MODE:-fallback-success}" = 'http-error-then-success' ]; then
  if [ "$count" -eq 1 ]; then
    printf 'http-error' > "$out"
    printf '503'
  else
    printf 'recovered' > "$out"
    printf '200'
  fi
  exit 0
fi
if [ "${FAKE_CURL_MODE:-fallback-success}" = 'final-http-error' ]; then
  printf 'error-body' > "$out"
  printf '503'
  exit 0
fi
if [ "${FAKE_CURL_MODE:-fallback-success}" = 'final-undersized' ]; then
  printf 'tiny' > "$out"
  printf '200'
  exit 0
fi
if [ "${FAKE_CURL_MODE:-fallback-success}" = 'fallback-success' ] && [ "$count" -eq 2 ]; then
  printf 'detail payload' > "$out"
  printf '200'
  exit 0
fi
if [ "${FAKE_CURL_MODE:-fallback-success}" = 'small-then-large' ]; then
  if [ "$count" -eq 1 ]; then printf 'tiny' > "$out"; else printf 'large-enough' > "$out"; fi
  printf '200'
  exit 0
fi

if [ "$count" -eq 1 ]; then
  [ "${FAKE_CURL_MODE:-fallback-success}" = 'always-fail' ] && [ -n "$out" ] && printf 'partial-primary' > "$out"
  printf 'primary transport failure\n' >&2
  printf '000'
  exit 7
fi
[ "${FAKE_CURL_MODE:-fallback-success}" = 'always-fail' ] && [ -n "$out" ] && printf 'partial-ipv4' > "$out"
printf 'ipv4 transport failure\n' >&2
printf '000'
exit 28
SH
chmod +x "$FAKE_CURL"

export FAKE_CURL_LOG="$TMP/curl.log"
export FAKE_CURL_COUNT="$TMP/curl.count"
CURL_BIN="$FAKE_CURL"
DEST="$TMP/detail.js"
ERR="$TMP/detail.err"
UA='test-agent'

fetch_detail "$DEST" 'https://itemcdn.tmall.com/example' "$UA" "$ERR"
[ "$DETAIL_PRIMARY_HTTP_CODE" = '000' ]
[ "$DETAIL_PRIMARY_CURL_RC" -eq 7 ]
[ "$DETAIL_IPV4_FALLBACK" -eq 1 ]
[ "$DETAIL_HTTP_CODE" = '200' ]
[ "$DETAIL_CURL_RC" -eq 0 ]
[ "$DETAIL_PRIMARY_SIZE" -eq 0 ]
[ "$DETAIL_SIZE" -eq "$(wc -c < "$DEST" | tr -d ' ')" ]
[ -s "$DEST" ]
[ "$(wc -l < "$FAKE_CURL_LOG" | tr -d ' ')" -eq 2 ]
mapfile -t CALLS < "$FAKE_CURL_LOG"
FIRST="${CALLS[0]}"
SECOND="${CALLS[1]}"
for required in '-sS' '--retry 3' '--retry-all-errors' '--retry-delay 2' '--connect-timeout 15' 'Referer: https://detail.1688.com/'; do
  [[ "$FIRST" == *"$required"* ]]
  [[ "$SECOND" == *"$required"* ]]
done
[[ "$FIRST" != *' -4 '* ]]
[[ " $SECOND " == *' -4 '* ]]

: > "$FAKE_CURL_LOG"
rm -f "$FAKE_CURL_COUNT" "$DEST" "$ERR"
export FAKE_CURL_MODE='always-fail'
fetch_detail "$DEST" 'https://itemcdn.tmall.com/example' "$UA" "$ERR"
[ "$DETAIL_HTTP_CODE" = '000' ]
[ "$DETAIL_CURL_RC" -eq 28 ]
[ "$DETAIL_IPV4_FALLBACK" -eq 1 ]
[ ! -e "$DEST" ]
[[ "$DETAIL_CURL_STDERR" == *'primary transport failure'* ]]
[[ "$DETAIL_CURL_STDERR" == *'ipv4 transport failure'* ]]

: > "$FAKE_CURL_LOG"
rm -f "$FAKE_CURL_COUNT" "$DEST" "$ERR"
export FAKE_CURL_MODE='small-then-large'
fetch_resource "$DEST" 'https://cdn.example/asset' "$UA" "$ERR" 90 10 --http1.1
[ "$FETCH_PRIMARY_HTTP_CODE" = '200' ]
[ "$FETCH_PRIMARY_CURL_RC" -eq 0 ]
[ "$FETCH_PRIMARY_SIZE" -eq 4 ]
[ "$FETCH_IPV4_FALLBACK" -eq 1 ]
[ "$FETCH_HTTP_CODE" = '200' ]
[ "$FETCH_CURL_RC" -eq 0 ]
[ "$FETCH_SIZE" -eq 12 ]
[ "$(<"$DEST")" = 'large-enough' ]
mapfile -t RESOURCE_CALLS < "$FAKE_CURL_LOG"
[[ " ${RESOURCE_CALLS[0]} " != *' --http1.1 '* ]]
[[ " ${RESOURCE_CALLS[1]} " == *' -4 '* ]]
[[ " ${RESOURCE_CALLS[1]} " == *' --http1.1 '* ]]

: > "$FAKE_CURL_LOG"
rm -f "$FAKE_CURL_COUNT" "$DEST" "$ERR"
export FAKE_CURL_MODE='primary-success'
fetch_resource "$DEST" 'https://cdn.example/primary' "$UA" "$ERR" 40 10
[ "$FETCH_HTTP_CODE" = '200' ]
[ "$FETCH_CURL_RC" -eq 0 ]
[ "$FETCH_SIZE" -eq 10 ]
[ "$FETCH_IPV4_FALLBACK" -eq 0 ]
[ "$(wc -l < "$FAKE_CURL_LOG" | tr -d ' ')" -eq 1 ]

: > "$FAKE_CURL_LOG"
rm -f "$FAKE_CURL_COUNT" "$DEST" "$ERR"
export FAKE_CURL_MODE='http-error-then-success'
fetch_resource "$DEST" 'https://cdn.example/http-error' "$UA" "$ERR" 40 1
[ "$FETCH_PRIMARY_HTTP_CODE" = '503' ]
[ "$FETCH_PRIMARY_CURL_RC" -eq 0 ]
[ "$FETCH_IPV4_FALLBACK" -eq 1 ]
[ "$FETCH_HTTP_CODE" = '200' ]
[ "$FETCH_CURL_RC" -eq 0 ]
[ "$(<"$DEST")" = 'recovered' ]

: > "$FAKE_CURL_LOG"
rm -f "$FAKE_CURL_COUNT" "$DEST" "$ERR"
export FAKE_CURL_MODE='final-http-error'
fetch_resource "$DEST" 'https://cdn.example/final-http-error' "$UA" "$ERR" 40 1
[ "$FETCH_PRIMARY_HTTP_CODE" = '503' ]
[ "$FETCH_HTTP_CODE" = '503' ]
[ "$FETCH_CURL_RC" -eq 0 ]
[ "$FETCH_IPV4_FALLBACK" -eq 1 ]
[ ! -e "$DEST" ]

: > "$FAKE_CURL_LOG"
rm -f "$FAKE_CURL_COUNT" "$DEST" "$ERR"
export FAKE_CURL_MODE='final-undersized'
fetch_resource "$DEST" 'https://cdn.example/final-undersized' "$UA" "$ERR" 40 10
[ "$FETCH_PRIMARY_HTTP_CODE" = '200' ]
[ "$FETCH_HTTP_CODE" = '200' ]
[ "$FETCH_CURL_RC" -eq 0 ]
[ "$FETCH_SIZE" -eq 4 ]
[ "$FETCH_IPV4_FALLBACK" -eq 1 ]
[ ! -e "$DEST" ]

for collector in "$ROOT/scripts/1688/collect.sh" "$ROOT/scripts/1688/collect_mobile.sh"; do
  source_text="$(<"$collector")"
  for required_source in \
    'source "$DETAIL_FETCHER"' \
    'fetch_detail "$OUTDIR/05_원본데이터/상세페이지_원본응답.js"' \
    'fetch_resource "$2" "$1"' \
    'fetch_resource "$MP4" "$TARGET"' \
    'URL:$DETAIL_URL' \
    'URL:$url' \
    'URL:$TARGET'; do
    [[ "$source_text" == *"$required_source"* ]]
  done
  [[ "$source_text" != *'safe_output.js'* ]]
done
mobile_source="$(<"$ROOT/scripts/1688/collect_mobile.sh")"
[[ "$mobile_source" == *'fetch_resource "$2" "$1" "$UA" "$TMP/asset_curl.err" 40 1 --http1.1'* ]]
[[ "$mobile_source" == *'fetch_detail "$OUTDIR/05_원본데이터/상세페이지_원본응답.js" "$DETAIL_URL" "$UA" "$TMP/detail_curl.err" --http1.1'* ]]

printf 'PASS: resilient fetch retry, IPv4 fallback, size validation, partial cleanup, and stderr capture\n'
