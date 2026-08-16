#!/usr/bin/env bash
# =============================================================================
# collect_1688.sh — 1688 상품 데이터 익명 수집 전체 자동화 (범용/재사용)
#
# 로그인·쿠키 불필요. 브라우저 헤더를 붙인 curl 로 상품 페이지를 받아
#   window.context 임베디드 데이터를 파싱하고, 폴더 구조를 만들고,
#   이미지/동영상/상세페이지를 내려받는다.
#
# 사용법:
#   bash collect_1688.sh <offer_url_또는_offer_id> [출력_기준폴더]
# 예:
#   bash collect_1688.sh https://detail.1688.com/offer/889272226600.html
#   bash collect_1688.sh 889272226600 /Users/me/work/how-to-capture
#
# 출력: <출력_기준폴더>/<offerId>_<상품명슬러그>/  (기본 기준폴더 = 현재 디렉터리)
#
# 요구사항: bash, curl, node  (jq/python 불필요). node 로만 window.context 파싱.
# 이 스크립트는 GET(읽기)만 한다. 주문/결제/장바구니 변경 없음.
# =============================================================================
set -uo pipefail

# ---- 인자 ----
if [ $# -lt 1 ]; then
  echo "usage: bash collect_1688.sh <offer_url_또는_offer_id> [출력_기준폴더]" >&2
  exit 2
fi
INPUT="$1"
OUT_BASE="${2:-$PWD}"

# ---- offer id 추출 (URL 이면 숫자만) ----
OFFER="$(printf '%s' "$INPUT" | grep -oE '[0-9]{6,}' | head -1)"
if [ -z "$OFFER" ]; then echo "❌ offer id 를 찾지 못함: $INPUT" >&2; exit 2; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parse_context.js"
if [ ! -f "$PARSER" ]; then echo "❌ parse_context.js 없음: $PARSER" >&2; exit 2; fi

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
OFFER_URL="https://detail.1688.com/offer/${OFFER}.html"
WARN=0
warn(){ echo "⚠️  $*" >&2; WARN=$((WARN+1)); }

# ---- md5 도구 (macOS: md5 -q, Linux: md5sum) ----
if command -v md5sum >/dev/null 2>&1; then MD5(){ md5sum "$1" | awk '{print $1}'; }
elif command -v md5 >/dev/null 2>&1;   then MD5(){ md5 -q "$1"; }
else MD5(){ echo "nomd5-$RANDOM"; }; fi

# ---- 작업용 임시 폴더 ----
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== 1688 익명 수집 시작: offer $OFFER ==="

# ---- 1) 상품 페이지 fetch ----
CODE="$(curl -sL -A "$UA" \
  -H "Referer: https://www.1688.com/" \
  -H "Accept-Language: zh-CN,zh;q=0.9" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
  -o "$TMP/page.html" -w "%{http_code}" --max-time 40 "$OFFER_URL" || echo ERR)"
SIZE="$(wc -c < "$TMP/page.html" 2>/dev/null | tr -d ' ')"
echo "페이지 HTTP:$CODE SIZE:${SIZE}B"
if [ "$CODE" != "200" ] || [ "${SIZE:-0}" -lt 2000 ]; then
  echo "❌ 페이지 수집 실패 (HTTP:$CODE, SIZE:$SIZE). 네트워크/차단 확인." >&2
  exit 1
fi
if ! grep -q 'window.context' "$TMP/page.html"; then
  echo "❌ window.context 없음 — 빈 페이지/차단 페이지일 수 있음 (WebFetch 아닌 curl 로 받았는지 확인)." >&2
  exit 1
fi

# ---- 2) context 파싱 → summary ----
if ! node "$PARSER" parse "$TMP/page.html" > "$TMP/context.json" 2>"$TMP/parse.err"; then
  echo "❌ context 파싱 실패:" >&2; cat "$TMP/parse.err" >&2; exit 1
fi
node "$PARSER" summary "$TMP/context.json" > "$TMP/summary.json" || { echo "❌ summary 생성 실패" >&2; exit 1; }

TITLE="$(node "$PARSER" get "$TMP/summary.json" title)"
SLUG="$(node "$PARSER" get "$TMP/summary.json" slug)"
[ -z "$SLUG" ] && SLUG="offer"
DETAIL_URL="$(node "$PARSER" get "$TMP/summary.json" detailUrl)"
VIDEO_URL="$(node "$PARSER" get "$TMP/summary.json" video.videoUrl)"
VIDEO_COVER="$(node "$PARSER" get "$TMP/summary.json" video.coverUrl)"
echo "제목: $TITLE"

# ---- 3) 폴더 구조 생성 ----
OUTDIR="$OUT_BASE/${OFFER}_${SLUG}"
mkdir -p "$OUTDIR/01_상품정보" \
         "$OUTDIR/02_상세페이지" \
         "$OUTDIR/03_이미지/01_메인이미지" \
         "$OUTDIR/03_이미지/02_상세이미지" \
         "$OUTDIR/03_이미지/03_동영상커버" \
         "$OUTDIR/04_동영상" \
         "$OUTDIR/05_원본데이터" \
         "$OUTDIR/06_수집스크립트"
echo "출력 폴더: $OUTDIR"

# ---- 4) 원본데이터 저장 ----
cp "$TMP/page.html"    "$OUTDIR/05_원본데이터/offer_${OFFER}_페이지원본.html"
cp "$TMP/context.json" "$OUTDIR/05_원본데이터/context_상품데이터.json"
cp "$TMP/summary.json" "$OUTDIR/05_원본데이터/summary.json"

# ---- 5) 상품정보 원문 md + SKU csv ----
node "$PARSER" productmd "$TMP/summary.json" > "$OUTDIR/01_상품정보/상품정보_원본_중국어.md"
node "$PARSER" skucsv    "$TMP/summary.json" > "$OUTDIR/01_상품정보/SKU_가격표.csv"

# ---- 6) 메인 이미지 다운로드 (원본만, md5 중복제거) ----
echo "--- 메인 이미지 다운로드 ---"
SEEN="$TMP/seen_md5"; : > "$SEEN"
SEEN_D="$TMP/seen_md5_detail"; : > "$SEEN_D"
dl_img(){ # url dest
  curl -sL -A "$UA" -H "Referer: https://detail.1688.com/" \
    -o "$2" -w "%{http_code}" --max-time 40 "$1"
}
i=0
node "$PARSER" images "$TMP/summary.json" | while IFS= read -r url || [ -n "$url" ]; do
  [ -z "$url" ] && continue
  i=$((i+1)); n="$(printf '%02d' "$i")"
  tmpf="$TMP/main_$n.jpg"
  code="$(dl_img "$url" "$tmpf")"
  if [ "$code" != "200" ]; then echo "  메인_$n HTTP:$code (skip)"; continue; fi
  h="$(MD5 "$tmpf")"
  if grep -q "^$h$" "$SEEN"; then echo "  메인_$n 중복(md5) → skip"; continue; fi
  echo "$h" >> "$SEEN"
  mv "$tmpf" "$OUTDIR/03_이미지/01_메인이미지/메인_$n.jpg"
  echo "  메인_$n OK"
done

# ---- 7) 상세페이지 fetch + 상세 이미지 ----
if [ -n "$DETAIL_URL" ]; then
  echo "--- 상세페이지 다운로드 ---"
  code="$(curl -sL -A "$UA" -H "Referer: https://detail.1688.com/" \
    -o "$OUTDIR/05_원본데이터/상세페이지_원본응답.js" -w "%{http_code}" --max-time 40 "$DETAIL_URL")"
  if [ "$code" = "200" ]; then
    if node "$PARSER" detail-html "$OUTDIR/05_원본데이터/상세페이지_원본응답.js" \
         > "$OUTDIR/02_상세페이지/상세페이지_원본.html" 2>/dev/null; then
      echo "  상세 HTML 추출 OK"
    else warn "상세 HTML 파싱 실패"; fi
    j=0
    node "$PARSER" detail-images "$OUTDIR/05_원본데이터/상세페이지_원본응답.js" 2>/dev/null | while IFS= read -r url || [ -n "$url" ]; do
      [ -z "$url" ] && continue
      tmpf="$TMP/detail_dl.jpg"
      c="$(dl_img "$url" "$tmpf")"
      if [ "$c" != "200" ]; then echo "  상세 HTTP:$c (skip)"; continue; fi
      # 상세 이미지도 md5 중복제거: 같은 내용이 다른 CDN URL 로 중복 게시되는 경우가 있다.
      h="$(MD5 "$tmpf")"
      if grep -q "^$h$" "$SEEN_D"; then echo "  상세 중복(md5) → skip"; continue; fi
      echo "$h" >> "$SEEN_D"
      j=$((j+1)); n="$(printf '%02d' "$j")"
      mv "$tmpf" "$OUTDIR/03_이미지/02_상세이미지/상세_$n.jpg"
      echo "  상세_$n OK"
    done
  else warn "상세페이지 HTTP:$code"; fi
else
  echo "상세페이지 URL 없음 (detailUrl 비어있음)"
fi

# ---- 8) 동영상 커버 + 동영상 ----
if [ -n "$VIDEO_COVER" ]; then
  echo "--- 동영상 커버 ---"
  c="$(dl_img "$VIDEO_COVER" "$OUTDIR/03_이미지/03_동영상커버/동영상_커버.jpg")"
  [ "$c" = "200" ] && echo "  커버 OK" || echo "  커버 HTTP:$c"
fi
if [ -n "$VIDEO_URL" ]; then
  echo "--- 동영상 다운로드 (302 → 서명 URL) ---"
  # cloud.video.taobao.com 은 302 로 서명된 CDN URL 을 준다. Location 을 직접 받는다.
  LOC="$(curl -sI -A "$UA" -H "Referer: https://detail.1688.com/" --max-time 30 "$VIDEO_URL" \
        | tr -d '\r' | awk -F': ' 'tolower($1)=="location"{print $2}' | tail -1)"
  TARGET="${LOC:-$VIDEO_URL}"
  c="$(curl -sL -A "$UA" -H "Referer: https://detail.1688.com/" \
        -o "$OUTDIR/04_동영상/상품동영상.mp4" -w "%{http_code}" --max-time 90 "$TARGET")"
  vs="$(wc -c < "$OUTDIR/04_동영상/상품동영상.mp4" 2>/dev/null | tr -d ' ')"
  if [ "$c" = "200" ] && [ "${vs:-0}" -gt 10000 ]; then echo "  동영상 OK (${vs}B)"; else warn "동영상 실패 HTTP:$c SIZE:$vs"; fi
fi

# ---- 9) README.md ----
{
  echo "# 1688 상품 데이터 수집 — ${OFFER}"
  echo ""
  echo "- **상품명(原文)**: ${TITLE}"
  echo "- **URL**: ${OFFER_URL}"
  echo "- **수집일**: $(date +%Y-%m-%d)"
  echo "- **수집 방식**: 익명(로그인 불필요) — 브라우저 헤더 curl + window.context 파싱"
  echo ""
  echo "## 폴더 구성"
  echo ""
  echo "| 폴더 | 내용 |"
  echo "|---|---|"
  echo "| 01_상품정보/ | 상품정보 원문(md) + SKU 가격표(csv) |"
  echo "| 02_상세페이지/ | 상세페이지 원본 HTML |"
  echo "| 03_이미지/ | 01_메인이미지 / 02_상세이미지 / 03_동영상커버 |"
  echo "| 04_동영상/ | 상품 동영상 mp4 |"
  echo "| 05_원본데이터/ | 페이지 원본 HTML, context JSON, summary JSON, 상세 원본응답 |"
  echo "| 06_수집스크립트/ | (선택) 로그인 수집용 |"
  echo ""
  echo "## 수집 방법 (재현)"
  echo ""
  echo "이 폴더는 \`scripts/1688/collect.sh ${OFFER}\` 로 생성됨."
  echo "자세한 방법론은 상위의 \`1688_수집_플레이북.md\` 참조."
  echo ""
  echo "## 로그인 수집(선택)"
  echo ""
  echo "일부 데이터(도매/분소가·회사 상세·개별 리뷰)는 로그인이 필요할 수 있다."
  echo "\`scripts/1688/collect_authed.sh ${OFFER} <cookies.txt>\` 로 수집 후 \`scripts/1688/diff_context.js\` 로 익명본과 대조하라."
} > "$OUTDIR/README.md"

echo ""
echo "✅ 완료. 경고 ${WARN}건."
echo "   출력: $OUTDIR"
