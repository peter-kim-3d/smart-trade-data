#!/usr/bin/env bash
# =============================================================================
# collect_mobile.sh — 1688 상품 데이터 익명 수집 (모바일 m.1688.com 경로)
#
# 데스크톱 detail.1688.com 이 datacenter IP 를 차단하는 환경에서, 모바일
# 엔드포인트 m.1688.com/offer/<id>.html 은 익명 GET 으로 전체 상품 JSON
# (window.__INIT_DATA, 순수 JSON) 을 내려준다. 이 스크립트는 scripts/1688/
# collect.sh 의 출력 계약(폴더 구조)을 그대로 따르되 모바일 경로로 수집한다.
#
# 사용법:
#   bash collect_mobile.sh <offer_url_또는_offer_id> [출력_기준폴더]
#
# 출력: <출력_기준폴더>/<offerId>_<상품명슬러그>/  (collect.sh 와 동일 구조)
# 요구사항: bash, curl, node. GET(읽기)만 한다.
# =============================================================================
set -uo pipefail

if [ $# -lt 1 ]; then
  echo "usage: bash collect_mobile.sh <offer_url_또는_offer_id> [출력_기준폴더]" >&2
  exit 2
fi
INPUT="$1"
OUT_BASE="${2:-$PWD}"

OFFER="$(printf '%s' "$INPUT" | grep -oE '[0-9]{6,}' | head -1)"
if [ -z "$OFFER" ]; then echo "❌ offer id 를 찾지 못함: $INPUT" >&2; exit 2; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parse_mobile.js"
if [ ! -f "$PARSER" ]; then echo "❌ parse_mobile.js 없음: $PARSER" >&2; exit 2; fi
DETAIL_FETCHER="$SCRIPT_DIR/fetch_detail.sh"
if [ ! -f "$DETAIL_FETCHER" ]; then echo "❌ fetch_detail.sh 없음: $DETAIL_FETCHER" >&2; exit 2; fi
# shellcheck source=fetch_detail.sh
source "$DETAIL_FETCHER"

# 모바일 페이지는 iPhone UA 로 받아야 __INIT_DATA 페이지가 나온다.
UA="Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
OFFER_URL="https://m.1688.com/offer/${OFFER}.html"
WARN=0
warn(){ echo "⚠️  $*" >&2; WARN=$((WARN+1)); }

if command -v md5sum >/dev/null 2>&1; then MD5(){ md5sum "$1" | awk '{print $1}'; }
elif command -v md5 >/dev/null 2>&1;   then MD5(){ md5 -q "$1"; }
else MD5(){ echo "nomd5-$RANDOM"; }; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== 1688 익명 수집 시작 (모바일 경로): offer $OFFER ==="

# ---- 1) 모바일 상품 페이지 fetch (HTTP/2 스트림 리셋 대비: 실패 시 --http1.1 재시도) ----
fetch_page(){ # $1: 추가 curl 옵션 (빈문자열 | --http1.1)
  curl -sL $1 -A "$UA" \
    -H "Referer: https://www.1688.com/" \
    -H "Accept-Language: zh-CN,zh;q=0.9" \
    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
    -o "$TMP/page.html" -w "%{http_code}" --max-time 40 "$OFFER_URL"
}
CODE="$(fetch_page '' || echo ERR)"
SIZE="$(wc -c < "$TMP/page.html" 2>/dev/null | tr -d ' ')"
# 일부 데이터센터에서 m.1688.com 이 HTTP/2 스트림을 리셋(curl 92, 2B 응답)한다 → HTTP/1.1 로 재시도
if [ "$CODE" != "200" ] || [ "${SIZE:-0}" -lt 2000 ] || ! grep -q 'window.__INIT_DATA' "$TMP/page.html"; then
  echo "페이지 1차 실패(HTTP:$CODE SIZE:${SIZE}B) — HTTP/2 리셋 가능, --http1.1 재시도"
  CODE="$(fetch_page --http1.1 || echo ERR)"
  SIZE="$(wc -c < "$TMP/page.html" 2>/dev/null | tr -d ' ')"
fi
echo "페이지 HTTP:$CODE SIZE:${SIZE}B"
if [ "$CODE" != "200" ] || [ "${SIZE:-0}" -lt 2000 ]; then
  echo "❌ 페이지 수집 실패 (HTTP:$CODE, SIZE:$SIZE). 네트워크/차단 확인." >&2
  exit 1
fi
if grep -qE '滑块|punish|_____tmd_____|x5secdata|baxia' "$TMP/page.html"; then
  echo "❌ 안티봇 마커 감지 — 차단 페이지." >&2
  exit 1
fi
if ! grep -q 'window.__INIT_DATA' "$TMP/page.html"; then
  echo "❌ window.__INIT_DATA 없음 — 빈 페이지/차단 페이지일 수 있음." >&2
  exit 1
fi

# ---- 2) __INIT_DATA 파싱 → summary ----
if ! node "$PARSER" parse "$TMP/page.html" > "$TMP/init.json" 2>"$TMP/parse.err"; then
  echo "❌ __INIT_DATA 파싱 실패:" >&2; cat "$TMP/parse.err" >&2; exit 1
fi
node "$PARSER" summary "$TMP/init.json" > "$TMP/summary.json" || { echo "❌ summary 생성 실패" >&2; exit 1; }

TITLE="$(node "$PARSER" get "$TMP/summary.json" title)"
SLUG="$(node "$PARSER" get "$TMP/summary.json" slug)"
[ -z "$SLUG" ] && SLUG="offer"
DETAIL_URL="$(node "$PARSER" get "$TMP/summary.json" detailUrl)"
VIDEO_URL="$(node "$PARSER" get "$TMP/summary.json" video.videoUrl)"
VIDEO_COVER="$(node "$PARSER" get "$TMP/summary.json" video.coverUrl)"
echo "제목: $TITLE"

# ---- 3) 폴더 구조 생성 (collect.sh 와 동일 계약) ----
OUTDIR="$OUT_BASE/${OFFER}_${SLUG}"
mkdir -p "$OUTDIR/01_상품정보" \
         "$OUTDIR/02_상세페이지" \
         "$OUTDIR/03_이미지/01_메인이미지" \
         "$OUTDIR/03_이미지/02_상세이미지" \
         "$OUTDIR/04_동영상" \
         "$OUTDIR/05_원본데이터"
# 03_동영상커버 는 커버 URL 이 있을 때만 생성 (모바일 페이로드에는 대개 없음)
[ -n "$VIDEO_COVER" ] && mkdir -p "$OUTDIR/03_이미지/03_동영상커버"
echo "출력 폴더: $OUTDIR"

# ---- 4) 원본데이터 저장 ----
cp "$TMP/page.html"    "$OUTDIR/05_원본데이터/offer_${OFFER}_페이지원본.html"
cp "$TMP/init.json"    "$OUTDIR/05_원본데이터/context_상품데이터.json"
cp "$TMP/summary.json" "$OUTDIR/05_원본데이터/summary.json"

# ---- 5) 상품정보 원문 md + SKU csv ----
node "$PARSER" productmd "$TMP/summary.json" > "$OUTDIR/01_상품정보/상품정보_원본_중국어.md"
node "$PARSER" skucsv    "$TMP/summary.json" > "$OUTDIR/01_상품정보/SKU_가격표.csv"

# ---- 6) 메인 이미지 다운로드 (원본만, md5 중복제거 — collect.sh 와 동일) ----
echo "--- 메인 이미지 다운로드 ---"
SEEN="$TMP/seen_md5"; : > "$SEEN"
SEEN_D="$TMP/seen_md5_detail"; : > "$SEEN_D"
dl_img(){ # $1 url  $2 dest
  fetch_resource "$2" "$1" "$UA" "$TMP/asset_curl.err" 40 1 --http1.1
}
i=0
node "$PARSER" images "$TMP/summary.json" | while IFS= read -r url || [ -n "$url" ]; do
  [ -z "$url" ] && continue
  i=$((i+1)); n="$(printf '%02d' "$i")"
  tmpf="$TMP/main_$n.jpg"
  dl_img "$url" "$tmpf"; code="$FETCH_HTTP_CODE"
  if [ "$FETCH_IPV4_FALLBACK" -eq 1 ]; then
    echo "  메인_$n 1차 실패 HTTP:$FETCH_PRIMARY_HTTP_CODE curl_rc:$FETCH_PRIMARY_CURL_RC SIZE:${FETCH_PRIMARY_SIZE}B — curl -4 --http1.1 폴백"
  fi
  if [ "$code" != "200" ] || [ "$FETCH_CURL_RC" -ne 0 ] || [ "$FETCH_SIZE" -lt 1 ]; then
    warn "메인_$n 실패(skip) URL:$url HTTP:$code curl_rc:$FETCH_CURL_RC SIZE:${FETCH_SIZE}B stderr:${FETCH_CURL_STDERR:-<없음>}"
    continue
  fi
  h="$(MD5 "$tmpf")"
  if grep -q "^$h$" "$SEEN"; then echo "  메인_$n 중복(md5) → skip"; continue; fi
  echo "$h" >> "$SEEN"
  mv "$tmpf" "$OUTDIR/03_이미지/01_메인이미지/메인_$n.jpg"
  echo "  메인_$n OK"
done

# ---- 7) 상세페이지 fetch + 상세 이미지 ----
if [ -n "$DETAIL_URL" ]; then
  echo "--- 상세페이지 다운로드 ---"
  fetch_detail "$OUTDIR/05_원본데이터/상세페이지_원본응답.js" "$DETAIL_URL" "$UA" "$TMP/detail_curl.err" --http1.1
  code="$DETAIL_HTTP_CODE"
  if [ "$DETAIL_IPV4_FALLBACK" -eq 1 ]; then
    echo "  상세페이지 1차 실패 HTTP:$DETAIL_PRIMARY_HTTP_CODE curl_rc:$DETAIL_PRIMARY_CURL_RC SIZE:${DETAIL_PRIMARY_SIZE}B — curl -4 --http1.1 폴백"
  fi
  echo "  상세페이지 요청 HTTP:$code curl_rc:$DETAIL_CURL_RC"
  if [ "$code" = "200" ] && [ "$DETAIL_CURL_RC" -eq 0 ] && [ "$DETAIL_SIZE" -ge 1 ]; then
    if node "$PARSER" detail-html "$OUTDIR/05_원본데이터/상세페이지_원본응답.js" \
         > "$OUTDIR/02_상세페이지/상세페이지_원본.html" 2>/dev/null; then
      echo "  상세 HTML 추출 OK"
    else warn "상세 HTML 파싱 실패"; fi
    j=0
    node "$PARSER" detail-images "$OUTDIR/05_원본데이터/상세페이지_원본응답.js" 2>/dev/null | while IFS= read -r url || [ -n "$url" ]; do
      [ -z "$url" ] && continue
      tmpf="$TMP/detail_dl.jpg"
      dl_img "$url" "$tmpf"; c="$FETCH_HTTP_CODE"
      if [ "$FETCH_IPV4_FALLBACK" -eq 1 ]; then
        echo "  상세 이미지 1차 실패 HTTP:$FETCH_PRIMARY_HTTP_CODE curl_rc:$FETCH_PRIMARY_CURL_RC SIZE:${FETCH_PRIMARY_SIZE}B — curl -4 --http1.1 폴백"
      fi
      if [ "$c" != "200" ] || [ "$FETCH_CURL_RC" -ne 0 ] || [ "$FETCH_SIZE" -lt 1 ]; then
        warn "상세 이미지 실패(skip) URL:$url HTTP:$c curl_rc:$FETCH_CURL_RC SIZE:${FETCH_SIZE}B stderr:${FETCH_CURL_STDERR:-<없음>}"
        continue
      fi
      h="$(MD5 "$tmpf")"
      if grep -q "^$h$" "$SEEN_D"; then echo "  상세 중복(md5) → skip"; continue; fi
      echo "$h" >> "$SEEN_D"
      j=$((j+1)); n="$(printf '%02d' "$j")"
      mv "$tmpf" "$OUTDIR/03_이미지/02_상세이미지/상세_$n.jpg"
      echo "  상세_$n OK"
    done
  else warn "상세페이지 실패(skip) URL:$DETAIL_URL HTTP:$code curl_rc:$DETAIL_CURL_RC SIZE:${DETAIL_SIZE}B stderr:${DETAIL_CURL_STDERR:-<없음>}"; fi
else
  echo "상세페이지 URL 없음 (detailUrl 비어있음)"
fi

# ---- 8) 동영상 커버 + 동영상 (302 → 서명 URL, collect.sh 와 동일) ----
if [ -n "$VIDEO_COVER" ]; then
  echo "--- 동영상 커버 ---"
  cover_file="$OUTDIR/03_이미지/03_동영상커버/동영상_커버.jpg"
  dl_img "$VIDEO_COVER" "$cover_file"; c="$FETCH_HTTP_CODE"
  if [ "$FETCH_IPV4_FALLBACK" -eq 1 ]; then
    echo "  커버 1차 실패 HTTP:$FETCH_PRIMARY_HTTP_CODE curl_rc:$FETCH_PRIMARY_CURL_RC SIZE:${FETCH_PRIMARY_SIZE}B — curl -4 --http1.1 폴백"
  fi
  if [ "$c" = "200" ] && [ "$FETCH_CURL_RC" -eq 0 ] && [ "$FETCH_SIZE" -ge 1 ]; then
    echo "  커버 OK"
  else
    warn "동영상 커버 실패(skip) URL:$VIDEO_COVER HTTP:$c curl_rc:$FETCH_CURL_RC SIZE:${FETCH_SIZE}B stderr:${FETCH_CURL_STDERR:-<없음>}"
  fi
fi
if [ -n "$VIDEO_URL" ]; then
  echo "--- 동영상 다운로드 (302 → 서명 URL) ---"
  # 302 Location 해석 (HEAD 도 H2 리셋 가능 → 비면 --http1.1 재시도)
  vid_loc(){ curl -sI $1 -A "$UA" -H "Referer: https://detail.1688.com/" --max-time 30 "$VIDEO_URL" \
             | tr -d '\r' | awk -F': ' 'tolower($1)=="location"{print $2}' | tail -1; }
  LOC="$(vid_loc '')"; [ -z "$LOC" ] && LOC="$(vid_loc --http1.1)"
  TARGET="${LOC:-$VIDEO_URL}"
  MP4="$OUTDIR/04_동영상/상품동영상.mp4"
  fetch_resource "$MP4" "$TARGET" "$UA" "$TMP/video_curl.err" 90 10001 --http1.1
  c="$FETCH_HTTP_CODE"; vs="$FETCH_SIZE"
  if [ "$FETCH_IPV4_FALLBACK" -eq 1 ]; then
    echo "  동영상 1차 실패 HTTP:$FETCH_PRIMARY_HTTP_CODE curl_rc:$FETCH_PRIMARY_CURL_RC SIZE:${FETCH_PRIMARY_SIZE}B — curl -4 --http1.1 폴백"
  fi
  if [ "$c" = "200" ] && [ "$FETCH_CURL_RC" -eq 0 ] && [ "${vs:-0}" -gt 10000 ]; then
    echo "  동영상 OK (${vs}B)"
  else
    warn "동영상 실패(skip) URL:$TARGET HTTP:$c curl_rc:$FETCH_CURL_RC SIZE:${vs}B stderr:${FETCH_CURL_STDERR:-<없음>}"
  fi
fi

# ---- 9) README.md ----
{
  echo "# 1688 상품 데이터 수집 (모바일 경로) — ${OFFER}"
  echo ""
  echo "- **상품명(原文)**: ${TITLE}"
  echo "- **URL**: ${OFFER_URL}"
  echo "- **수집일**: $(date +%Y-%m-%d)"
  echo "- **수집 방식**: 익명(로그인 불필요) — iPhone UA curl + window.__INIT_DATA(JSON) 파싱"
  echo "- **비고**: 데스크톱 detail.1688.com 이 IP 차단된 환경용 대체 경로."
  echo "  모바일 초기 페이로드에는 SKU 별 스펙/개별가/재고, 평가(评价), 판매자 인증정보가 없다."
  echo ""
  echo "## 폴더 구성"
  echo ""
  echo "| 폴더 | 내용 |"
  echo "|---|---|"
  echo "| 01_상품정보/ | 상품정보 원문(md) + SKU 가격표(csv) |"
  echo "| 02_상세페이지/ | 상세페이지 원본 HTML |"
  echo "| 03_이미지/ | 01_메인이미지 / 02_상세이미지 (03_동영상커버: 커버 URL 있을 때만) |"
  echo "| 04_동영상/ | 상품 동영상 mp4 |"
  echo "| 05_원본데이터/ | 페이지 원본 HTML, __INIT_DATA JSON, summary JSON, 상세 원본응답 |"
  echo ""
  echo "## 수집 방법 (재현)"
  echo ""
  echo "이 폴더는 \`collect_mobile.sh ${OFFER}\` 로 생성됨 (scripts/1688/collect.sh 의 모바일 변형)."
} > "$OUTDIR/README.md"

echo ""
echo "✅ 완료. 경고 ${WARN}건."
echo "   출력: $OUTDIR"
