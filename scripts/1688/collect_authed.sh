#!/usr/bin/env bash
# =============================================================================
# collect_authed.sh — 1688 로그인(쿠키) 전용 데이터 수집 (범용/재사용)
#
# 로그인은 자동화 불가(슬라이더 캡차 + 폰 SMS OTP + 디바이스 리스크).
# → 사람이 본인 브라우저에서 로그인(2FA) 후 세션 쿠키만 내보내 여기에 넘긴다.
#
# 사용법:
#   bash collect_authed.sh <offer_id> <cookies.txt> [출력폴더] [shopUrl] [memberId]
# 예:
#   bash collect_authed.sh 889272226600 ~/cookies.txt
#
# - shopUrl / memberId 를 생략하면, 같은 폴더의 익명 수집 결과
#   (…/05_원본데이터/summary.json 또는 context_상품데이터.json)에서 자동 추출한다.
#   자동 추출 실패 시 5~6번째 인자로 직접 지정하라.
# - cookies.txt 는 Netscape 파일 또는 `name=value; …` 한 줄 형식 모두 인식(curl -b).
#
# 이 스크립트는 GET(읽기)만 한다. 쿠키 값은 절대 출력하지 않는다.
# =============================================================================
set -uo pipefail

if [ $# -lt 2 ]; then
  echo "usage: bash collect_authed.sh <offer_id> <cookies.txt> [출력폴더] [shopUrl] [memberId]" >&2
  exit 2
fi
OFFER="$(printf '%s' "$1" | grep -oE '[0-9]{6,}' | head -1)"
COOKIE="$2"
OUTDIR_IN="${3:-}"
SHOP_IN="${4:-}"
MEMBER_IN="${5:-}"

if [ -z "$OFFER" ]; then echo "❌ offer id 이상: $1" >&2; exit 2; fi
if [ ! -f "$COOKIE" ]; then echo "❌ 쿠키 파일 없음: $COOKIE (scripts/1688/README.md 의 쿠키 내보내기 참고)" >&2; exit 2; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parse_context.js"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

# ---- 출력 폴더 결정 (없으면 현재 폴더 아래 익명 결과 폴더 탐색) ----
if [ -z "$OUTDIR_IN" ]; then
  # {OFFER}_* 폴더를 현재 디렉터리에서 찾는다
  OUTDIR_IN="$(find "$PWD" -maxdepth 1 -type d -name "${OFFER}_*" | head -1)"
  [ -z "$OUTDIR_IN" ] && OUTDIR_IN="$PWD/${OFFER}_authed"
fi
OUT="$OUTDIR_IN/05_원본데이터/authed"
mkdir -p "$OUT"

# ---- shopUrl / memberId 자동 추출 (익명 summary/context 에서) ----
SUM="$OUTDIR_IN/05_원본데이터/summary.json"
CTX="$OUTDIR_IN/05_원본데이터/context_상품데이터.json"
SHOP="$SHOP_IN"; MEMBER="$MEMBER_IN"
if [ -z "$SHOP" ] && [ -f "$SUM" ]; then SHOP="$(node "$PARSER" get "$SUM" seller.shopUrl 2>/dev/null)"; fi
if [ -z "$MEMBER" ] && [ -f "$SUM" ]; then MEMBER="$(node "$PARSER" get "$SUM" seller.sellerMemberId 2>/dev/null)"; fi
if [ -z "$SHOP" ] && [ -f "$CTX" ]; then SHOP="$(node -e 'const {deepFind}=require(process.argv[1]);const c=require(process.argv[2]);process.stdout.write(deepFind(c.result.data,"sellerWinportUrl")||"")' "$PARSER" "$CTX" 2>/dev/null)"; fi
if [ -z "$MEMBER" ] && [ -f "$CTX" ]; then MEMBER="$(node -e 'const {deepFind}=require(process.argv[1]);const c=require(process.argv[2]);process.stdout.write(deepFind(c.result.data,"sellerMemberId")||"")' "$PARSER" "$CTX" 2>/dev/null)"; fi

echo "=== 로그인 수집: offer $OFFER ==="
echo "저장 위치: $OUT"
[ -n "$SHOP" ]   && echo "shopUrl: $SHOP"     || echo "⚠️ shopUrl 미확인 (회사페이지 건너뜀). 5번째 인자로 지정 가능."
[ -n "$MEMBER" ] && echo "memberId: $MEMBER"  || echo "⚠️ memberId 미확인 (winport 건너뜀). 6번째 인자로 지정 가능."
echo ""

# ---- 공통 fetch: 이름, URL ----
fetch(){
  local name="$1" url="$2" code size flag=""
  code="$(curl -sL -b "$COOKIE" -A "$UA" \
    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
    -H "Accept-Language: zh-CN,zh;q=0.9,ko;q=0.8,en;q=0.7" \
    -H "Referer: https://detail.1688.com/offer/${OFFER}.html" \
    -o "$OUT/$name" -w "%{http_code}" --max-time 40 "$url" || echo ERR)"
  size="$(wc -c < "$OUT/$name" 2>/dev/null | tr -d ' ')"
  # 안티봇/로그인유도/캡차 탐지 (baxia/滑块/punish)
  if grep -qiE 'login\.1688|请登录|会员登录|nc_1_n1z|滑块|punish|baxia' "$OUT/$name" 2>/dev/null; then
    flag="  ⚠️ 로그인/캡차/안티봇 페이지 의심 (쿠키만료 또는 baxia 차단 → 사람이 브라우저에서 저장 필요)"
  fi
  printf "%-26s HTTP:%s  SIZE:%sB%s\n" "$name" "$code" "$size" "$flag"
}

# 1) 로그인 상태 상품 상세 (도매/분소가·수량별 티어가 등이 로그인 게이트일 수 있음)
fetch "detail_authed.html" "https://detail.1688.com/offer/${OFFER}.html"
# 2) 모바일 상품 페이지 (리뷰가 초기 렌더에 포함되는 경우 있음)
fetch "mobile_offer.html"  "https://m.1688.com/offer/${OFFER}.html"
# 3) 회사 개요/연락처/신용 (영업집조 등) — 종종 baxia 차단됨
if [ -n "$SHOP" ]; then
  fetch "company_index.html"   "${SHOP%/}/page/index.html"
  fetch "company_contact.html" "${SHOP%/}/page/contactinfo.html"
  fetch "company_credit.html"  "${SHOP%/}/page/creditdetail.html"
fi
# 4) Winport (공급사 명함) — 종종 baxia 차단됨
if [ -n "$MEMBER" ]; then
  fetch "winport.html" "https://winport.m.1688.com/page/index.html?memberId=${MEMBER}"
fi

echo ""
echo "✅ 완료. HTTP:200 이고 SIZE 가 충분히 크며 ⚠️ 없으면 정상."
echo "   ⚠️ 표시(안티봇/캡차)나 매우 작은 SIZE → 해당 페이지는 사람이 브라우저에서 저장해야 함."
echo "   리뷰 본문은 mtop AJAX 전용 → scripts/1688/README.md 의 'DevTools 리뷰 캡처' 참고해 reviews_raw.json 저장 후 parse_reviews.js."
echo "   익명본과 대조: node ${SCRIPT_DIR}/diff_context.js <익명 context.json> <로그인 context.json>"
