#!/usr/bin/env bash
# =============================================================================
# collect_auto.sh — 1688 수집 자동 분기 래퍼 (데스크톱 ↔ 모바일)
#
# 접속 IP 로 데스크톱(detail.1688.com)이 뚫리는지 "실시간 프로브"해서 분기한다:
#   - 뚫림(주거용 IP/프록시)        → collect.sh        (데이터 최다: SKU 개별가/재고·리뷰 가능)
#   - baxia/TMD 챌린지(데이터센터 IP) → collect_mobile.sh (m.1688.com / window.__INIT_DATA)
#
# AI/Hermes 무인 구동용: curl·node·필수 스크립트·OS 를 점검하고, IP 유형을 자동
# 판별해 사람 개입 없이 올바른 경로로 수집한다. 출력 폴더 구조·소비 계약은
# 두 경로 모두 동일(05_원본데이터/summary.json + 03_이미지/ ...).
#
# 사용법:
#   bash collect_auto.sh <offer_url_또는_offer_id> [출력_기준폴더] [--desktop|--mobile]
#     --desktop / --mobile : 프로브 없이 경로를 강제
#   환경변수 https_proxy 를 주면 프로브·수집이 그 프록시로 나간다(주거용 프록시 우회).
#
# 요구사항: bash, curl, node. GET(읽기)만 한다.
# =============================================================================
set -uo pipefail

# ---- 인자 파싱 (플래그는 위치 무관) ----
FORCE=""
ARGS=()
for a in "$@"; do
  case "$a" in
    --desktop) FORCE=desktop ;;
    --mobile)  FORCE=mobile ;;
    -h|--help) echo "usage: bash collect_auto.sh <offer_url_또는_id> [출력_기준폴더] [--desktop|--mobile]"; exit 0 ;;
    *) ARGS+=("$a") ;;
  esac
done
# bash 3.2(macOS) 에서 빈 배열 + set -u 안전 처리
if [ ${#ARGS[@]} -gt 0 ]; then set -- "${ARGS[@]}"; else set --; fi

if [ $# -lt 1 ]; then
  echo "usage: bash collect_auto.sh <offer_url_또는_id> [출력_기준폴더] [--desktop|--mobile]" >&2
  exit 2
fi
INPUT="$1"
OUT_BASE="${2:-$PWD}"
OFFER="$(printf '%s' "$INPUT" | grep -oE '[0-9]{6,}' | head -1)"
if [ -z "$OFFER" ]; then echo "❌ offer id 를 찾지 못함: $INPUT" >&2; exit 2; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- 런타임 환경 점검 (무인 구동 대비) ----
command -v curl >/dev/null 2>&1 || { echo "❌ curl 이 없음." >&2; exit 3; }
command -v node >/dev/null 2>&1 || { echo "❌ node 가 없음 — window.context/__INIT_DATA 파싱에 필수. 설치 후 재시도." >&2; exit 3; }
for s in collect.sh collect_mobile.sh parse_context.js parse_mobile.js; do
  [ -f "$SCRIPT_DIR/$s" ] || { echo "❌ 필요한 스크립트 없음: $SCRIPT_DIR/$s" >&2; exit 3; }
done
OS="$(uname -s 2>/dev/null || echo unknown)"
echo "=== collect_auto: offer $OFFER  (OS:$OS, 출력:$OUT_BASE) ==="

run_desktop(){ echo "→ 데스크톱 경로: collect.sh";        bash "$SCRIPT_DIR/collect.sh"        "$OFFER" "$OUT_BASE"; }
run_mobile(){  echo "→ 모바일 경로: collect_mobile.sh";   bash "$SCRIPT_DIR/collect_mobile.sh" "$OFFER" "$OUT_BASE"; }

# ---- 경로 강제 플래그 ----
if [ "$FORCE" = desktop ]; then run_desktop; exit $?; fi
if [ "$FORCE" = mobile  ]; then run_mobile;  exit $?; fi

# ---- 자동 분기: 데스크톱 실시간 프로브 ----
UA_D="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
probe(){ # $1: 추가 curl 옵션 (빈문자열 | --http1.1)
  curl -sL $1 -A "$UA_D" \
    -H "Referer: https://www.1688.com/" \
    -H "Accept-Language: zh-CN,zh;q=0.9" \
    -o "$TMP/probe.html" -w "%{http_code}" --max-time 30 \
    "https://detail.1688.com/offer/${OFFER}.html"
}
CODE="$(probe '' || echo ERR)"
SIZE="$(wc -c < "$TMP/probe.html" 2>/dev/null | tr -d ' ')"
# 통과(window.context)도 차단(baxia 마커)도 아니면 HTTP/2 리셋 의심 → --http1.1 재시도
# (주거용 IP 에서 일시적 H2 글리치로 데스크톱을 놓치고 모바일로 오분기하는 것 방지)
if ! grep -q 'window.context' "$TMP/probe.html" 2>/dev/null \
   && ! grep -qE '_____tmd_____|x5secdata|baxia|滑块|punish' "$TMP/probe.html" 2>/dev/null; then
  CODE="$(probe --http1.1 || echo ERR)"
  SIZE="$(wc -c < "$TMP/probe.html" 2>/dev/null | tr -d ' ')"
fi
echo "데스크톱 프로브: HTTP:$CODE SIZE:${SIZE}B"

# 통과 판정: 200 + 최소크기 + window.context 존재 + 안티봇 마커 없음
DESK_OK=0
if [ "$CODE" = "200" ] && [ "${SIZE:-0}" -ge 5000 ] \
   && grep -q 'window.context' "$TMP/probe.html" \
   && ! grep -qE '_____tmd_____|x5secdata|baxia|滑块|punish' "$TMP/probe.html"; then
  DESK_OK=1
fi

if [ "$DESK_OK" = 1 ]; then
  echo "✅ 데스크톱 통과 가능(주거용 IP/프록시) — 데이터 풍부 경로 사용"
  if run_desktop; then exit 0; fi
  echo "⚠️  데스크톱 수집이 실패 → 모바일 폴백 시도" >&2
  run_mobile; exit $?
else
  ORG="$(curl -s --max-time 8 https://ipinfo.io/org 2>/dev/null | tr -d '\r\n')"
  echo "⚠️  데스크톱 차단 감지(데이터센터 IP 추정${ORG:+, 출구:$ORG}) — 모바일 경로로 폴백"
  run_mobile; exit $?
fi
