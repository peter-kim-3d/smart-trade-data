#!/usr/bin/env bash
# curl 기반 자산 요청 공용 헬퍼.
# 호출 후 FETCH_* 전역값으로 1차/최종 HTTP 코드, curl 종료코드, 크기를 제공한다.

fetch_resource(){ # $1 dest  $2 url  $3 user-agent  $4 stderr log  $5 max-time  $6 minimum bytes  $7 IPv4 fallback option
  local dest="$1" url="$2" ua="$3" stderr_log="$4"
  local max_time="${5:-40}" min_bytes="${6:-1}"
  local fallback_opt="${7:-}"
  local primary_err="${stderr_log}.primary" ipv4_err="${stderr_log}.ipv4"
  local code rc size
  local curl_bin="${CURL_BIN:-curl}"
  local fallback_args=(-sS -L -4)
  [ -n "$fallback_opt" ] && fallback_args+=("$fallback_opt")

  FETCH_PRIMARY_HTTP_CODE='000'
  FETCH_PRIMARY_CURL_RC=0
  FETCH_PRIMARY_SIZE=0
  FETCH_HTTP_CODE='000'
  FETCH_CURL_RC=0
  FETCH_SIZE=0
  FETCH_CURL_STDERR=''
  FETCH_IPV4_FALLBACK=0
  : > "$primary_err"
  : > "$ipv4_err"
  rm -f "$dest"

  if code="$("$curl_bin" -sS -L -A "$ua" \
      -H "Referer: https://detail.1688.com/" \
      --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 15 \
      -o "$dest" -w "%{http_code}" --max-time "$max_time" "$url" 2>"$primary_err")"; then
    rc=0
  else
    rc=$?
  fi
  if [ -f "$dest" ]; then size="$(wc -c < "$dest" | tr -d ' ')"; else size=0; fi
  FETCH_PRIMARY_HTTP_CODE="${code:-000}"
  FETCH_PRIMARY_CURL_RC=$rc
  FETCH_PRIMARY_SIZE="${size:-0}"

  if [ "$rc" -eq 0 ] && [ "$FETCH_PRIMARY_HTTP_CODE" = '200' ] && [ "$FETCH_PRIMARY_SIZE" -ge "$min_bytes" ]; then
    FETCH_HTTP_CODE="$FETCH_PRIMARY_HTTP_CODE"
    FETCH_CURL_RC=$rc
    FETCH_SIZE="$FETCH_PRIMARY_SIZE"
    cp "$primary_err" "$stderr_log"
    FETCH_CURL_STDERR="$(<"$stderr_log")"
    return 0
  fi

  FETCH_IPV4_FALLBACK=1
  rm -f "$dest"
  if code="$("$curl_bin" "${fallback_args[@]}" -A "$ua" \
      -H "Referer: https://detail.1688.com/" \
      --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 15 \
      -o "$dest" -w "%{http_code}" --max-time "$max_time" "$url" 2>"$ipv4_err")"; then
    rc=0
  else
    rc=$?
  fi
  if [ -f "$dest" ]; then size="$(wc -c < "$dest" | tr -d ' ')"; else size=0; fi
  FETCH_HTTP_CODE="${code:-000}"
  FETCH_CURL_RC=$rc
  FETCH_SIZE="${size:-0}"

  {
    if [ -s "$primary_err" ]; then
      printf '%s\n' '[일반 요청 stderr]'
      while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line"; done < "$primary_err"
    fi
    if [ -s "$ipv4_err" ]; then
      printf '%s\n' '[IPv4 폴백 stderr]'
      while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line"; done < "$ipv4_err"
    fi
  } > "$stderr_log"
  FETCH_CURL_STDERR="$(<"$stderr_log")"
  if [ "$FETCH_CURL_RC" -ne 0 ] || [ "$FETCH_HTTP_CODE" != '200' ] || [ "$FETCH_SIZE" -lt "$min_bytes" ]; then
    rm -f "$dest"
  fi
  return 0
}

fetch_detail(){ # $1 dest  $2 url  $3 user-agent  $4 stderr log  $5 IPv4 fallback option
  fetch_resource "$1" "$2" "$3" "$4" 40 1 "${5:-}"
  DETAIL_PRIMARY_HTTP_CODE="$FETCH_PRIMARY_HTTP_CODE"
  DETAIL_PRIMARY_CURL_RC="$FETCH_PRIMARY_CURL_RC"
  DETAIL_PRIMARY_SIZE="$FETCH_PRIMARY_SIZE"
  DETAIL_HTTP_CODE="$FETCH_HTTP_CODE"
  DETAIL_CURL_RC="$FETCH_CURL_RC"
  DETAIL_SIZE="$FETCH_SIZE"
  DETAIL_CURL_STDERR="$FETCH_CURL_STDERR"
  DETAIL_IPV4_FALLBACK="$FETCH_IPV4_FALLBACK"
}
