# scripts/1688/ — 1688 수집 범용 스크립트

로그인 불필요 익명 수집 + (선택) 로그인 수집 + 파싱/대조 유틸.
요구사항: **`bash` + `curl` + `node`** (jq/python 불필요). `window.context` 파싱은 반드시 node.
자세한 방법론은 상위 폴더의 `1688_수집_플레이북.md` 참고.

> 모든 스크립트는 GET(읽기)만 한다. 주문/결제/장바구니 변경 없음.
> 쿠키 값·비밀번호는 어떤 출력에도 노출하지 않는다.

---

## 1. collect.sh — 익명 수집 전체 자동화

```bash
bash collect.sh <offer_url_또는_offer_id> [출력_기준폴더]
# 예
bash collect.sh https://detail.1688.com/offer/889272226600.html
bash collect.sh 889272226600 /Users/me/work/how-to-capture
```

하는 일: 상품 페이지 fetch → `window.context` 파싱 → `<offerId>_<상품명슬러그>/` 폴더 생성
→ 메인 이미지(원본만, md5 중복제거)·상세페이지·상세 이미지·동영상 커버·동영상(302 서명 URL) 다운로드
→ `01_상품정보/상품정보_원본_중국어.md` + `SKU_가격표.csv` + `README.md` 생성.
출력 폴더 = `<출력_기준폴더>/<offerId>_<슬러그>/` (기준폴더 기본값 = 현재 디렉터리).

> ⚠️ **데이터센터 IP(VPS)** 에서는 이 스크립트가 ~4.8KB 챌린지 페이지만 받아 실패한다(아래 §1b). 원인은 IP 평판이며 curl 헤더/TLS 지문 문제가 아니다.

## 1b. collect_mobile.sh — 익명 수집 (모바일 m.1688.com, 데이터센터 IP 우회)

```bash
bash collect_mobile.sh <offer_url_또는_offer_id> [출력_기준폴더]
# 예
bash collect_mobile.sh 647941709416 products/1688
```

`detail.1688.com`(데스크톱)은 접속 IP 의 ASN(대역 소유자)을 점수화해 **데이터센터/클라우드 IP** 를 안티봇(baxia/TMD)으로 막는다(HTTP 200 이지만 챌린지 페이지). **모바일 `m.1688.com/offer/<id>.html`** 은 같은 데이터센터 IP 에서도 익명 GET 으로 전체 상품 JSON 을 준다. `collect.sh` 와 **동일한 폴더 구조/소비 계약**(`05_원본데이터/summary.json` + `03_이미지/`)을 만든다.

- 데이터는 `window.context`(JS 리터럴)가 아니라 **`window.__INIT_DATA`(순수 JSON → `JSON.parse`)** 에 들어 있다. 파싱은 `parse_mobile.js`(§2b).
- iPhone UA 로 fetch(모바일 페이지를 받으려면 필수). 이미지·동영상 다운로드는 `collect.sh` 와 동일(원본만·md5 중복제거·동영상 302 서명 URL).
- ⚠️ **모바일 익명 초기 페이로드에 없는 것**(→ summary.json 에서 null): SKU 별 개별가/재고(`skuId` 만), 리뷰 통계(`rate.*`), 동영상 커버/제목, 판매자 인증정보·재구매율. 서명 mtop API 로 지연로딩되며 익명으로는 못 채운다(실증). 제목·계단가·이미지·동영상·속성·판매자 회사명·배송은 모두 포함.
- **언제 쓰나**: 접속 IP 가 데이터센터일 때, 또는 `collect.sh` 가 `window.context 없음` 으로 실패할 때. 주거용 IP 라면 데이터가 더 풍부한 `collect.sh`(데스크톱)를 우선.

## 1c. collect_auto.sh — 자동 분기 래퍼 (데스크톱 ↔ 모바일, 무인 구동 권장)

```bash
bash collect_auto.sh <offer_url_또는_offer_id> [출력_기준폴더] [--desktop|--mobile]
# 예
bash collect_auto.sh 647941709416 products/1688          # 자동 분기
bash collect_auto.sh 647941709416 products/1688 --mobile  # 모바일 강제
```

접속 IP 로 데스크톱(detail.1688.com)이 뚫리는지 **실시간 프로브**한 뒤 분기한다: 통과(주거용 IP/프록시)면 `collect.sh`(데이터 최다), baxia/TMD 챌린지(데이터센터 IP)면 `collect_mobile.sh`. **환경을 추측하지 않고 현재 IP 를 직접 테스트**하므로 Mac/VPS 혼용·Hermes 무인 구동에 적합하다.

- 무인 구동 대비: 실행 전 `curl`·`node`·필수 스크립트·OS 를 점검하고, 폴백 시 출구 IP 의 ASN 을 로깅한다.
- `https_proxy` 를 존중한다 → 주거용 프록시를 걸면 VPS 에서도 데스크톱 경로가 자동 선택된다.
- `--desktop`/`--mobile` 로 프로브 없이 경로 강제 가능.
- 견고성: 일부 데이터센터에서 1688/CDN 이 HTTP/2 스트림을 리셋(`curl 92`, 2B 응답)하면 **자동으로 `--http1.1` 재시도** — 데스크톱 프로브, 모바일 **페이지·상세페이지·이미지(메인/상세/커버) 다운로드** 전부. H2 리셋은 http_code 200 을 찍고도 파일을 자르므로 `dl_img` 는 curl 종료코드·파일크기까지 검사해 깨진 파일을 저장하지 않는다. 데스크톱 경로가 프로브 통과 후에도 실패하면 모바일로 최종 폴백.

## 2. parse_context.js — window.context 파서 (핵심 재사용 모듈)

```bash
node parse_context.js parse   <page.html>              # 전체 context → JSON
node parse_context.js summary <page.html|context.json> # 정규화 요약 JSON
node parse_context.js get     <*.json> <dotted.path>   # 스칼라 (예: skus[0].price, seller.shopUrl)
node parse_context.js images  <page.html|context.json> # 메인 원본 이미지 URL(썸네일 제외)
node parse_context.js skucsv  <page.html|context.json> # SKU 가격표 CSV
node parse_context.js attrs   <page.html|context.json> # 속성 마크다운(名: 값)
node parse_context.js productmd <page.html|context.json> # 상품정보 원문 마크다운
node parse_context.js detail-html   <detail_response.js> # 상세 content(HTML)
node parse_context.js detail-images <detail_response.js> # 상세 원본 이미지 URL
```

`require('./parse_context.js')` 로 `extractContext / buildSummary / parseDetail / deepFind / slugify` 도 사용 가능.

## 2b. parse_mobile.js — window.__INIT_DATA 파서 (모바일)

```bash
node parse_mobile.js parse   <page.html>                 # __INIT_DATA → JSON
node parse_mobile.js summary <page.html|init.json>       # 정규화 요약 (parse_context 와 동일 스키마)
node parse_mobile.js get     <*.json> <dotted.path>      # 스칼라
node parse_mobile.js images  <page.html|init.json>       # 메인 원본 이미지 URL
node parse_mobile.js skucsv  <page.html|init.json>       # SKU 가격표 CSV (동일 컬럼)
node parse_mobile.js attrs   <page.html|init.json>       # 속성 마크다운
node parse_mobile.js productmd <page.html|init.json>     # 상품정보 원문 마크다운
node parse_mobile.js detail-html   <detail_response.js>  # 상세 content(HTML)
node parse_mobile.js detail-images <detail_response.js>  # 상세 원본 이미지 URL
```

`parse_context.js` 와 **출력 스키마·서브커맨드가 동일**해 다운스트림이 두 경로를 구분 없이 소비할 수 있다. 차이는 입력뿐: `window.__INIT_DATA`(순수 JSON, `JSON.parse`)를 읽고, 모듈 ID 가 페이지마다 바뀌므로 `componentType` 으로 모듈을 찾는다. `require('./parse_mobile.js')` 로 `extractInitData / buildSummary / parseDetail / slugify / isThumb / moduleData` 사용 가능.

## 3. collect_authed.sh — 로그인(쿠키) 수집

```bash
bash collect_authed.sh <offer_id> <cookies.txt> [출력폴더] [shopUrl] [memberId]
# 예 (shopUrl·memberId 는 같은 폴더 익명 summary/context 에서 자동 추출)
bash collect_authed.sh 889272226600 ~/cookies.txt
```

로그인 상세·모바일·회사 개요/연락처/신용·winport 를 쿠키로 fetch.
`baxia/滑块/punish/请登录` 등 안티봇/캡차 페이지는 `⚠️` 로 표시(자동 돌파 불가 → 사람이 브라우저에서 저장).

### 쿠키 내보내기 (사람이 하는 부분)
1688 로그인은 **슬라이더 캡차 + 폰 SMS OTP** 라 자동화 불가. 사람이 브라우저에서 로그인 후:
- **방법 A (권장)**: Chrome 확장 **"Get cookies.txt LOCALLY"** 설치 → 1688 탭에서 Export(Netscape) → `cookies.txt`.
- **방법 B**: F12 → Network → 아무 **`detail.1688.com` 요청**(트래커 mmstat.com/.gif/track 말고) 클릭 → Request Headers 의 `cookie:` 값 전체 복사 → 텍스트 파일로 저장.
- `curl -b` 가 Netscape 파일과 `name=value; …` 한 줄 형식 모두 인식.
- ⚠️ `cookies.txt` 는 로그인 세션 그 자체 → git 금지, 작업 후 삭제, 채팅에 붙여넣지 말 것.

### 리뷰 본문 DevTools 캡처 (mtop AJAX 전용)
리뷰는 서명(`_m_h5_tk` 토큰 기반)이 필요해 자동화 불안정. 확실한 방법:
1. 로그인 브라우저에서 상품 페이지 → **商品评价** 섹션까지 스크롤
2. F12 → Network → 필터 **`rate`**
3. Response 에 `model.commentList[]` 있는 요청 우클릭 → Copy → **Copy response**
4. `05_원본데이터/authed/reviews_raw.json` 으로 저장 (여러 페이지면 스크롤하며 반복)

## 4. parse_reviews.js — 리뷰 파서

```bash
node parse_reviews.js <reviews_raw.json>        # 마크다운 요약
node parse_reviews.js <reviews_raw.json> --json # 파싱 배열 JSON
```

완전 JSON·JSONP 껍데기·`"model": {…` 조각 모두에서 `commentList` 를 건져내고 `rateId`(없으면 content 해시)로 중복제거.
필드: content·starLevel·specInfo·quantity·raterUserNick·buyerLevelTag·gmtPublished·images.
⚠️ 1688 리뷰 본문은 상투적(canned) 호평이 많음 — 메타데이터(구매 규격·수량)가 실질 가치.

## 5. diff_context.js — 익명 vs 로그인 의미차

```bash
# 로그인 HTML 만 있으면 먼저 context 로 변환
node parse_context.js parse detail_authed.html > authed_context.json
node diff_context.js <익명 context.json> <authed context.json>        # 노이즈 필터링
node diff_context.js <익명 context.json> <authed context.json> --all  # 노이즈 포함
```

추적 ID(`ipvId`,`exposeArgs`,`trackInfo`)·시간차 집계갱신(리뷰수·재구매율 등)·내부 태그 순서를 무시하고
**로그인 전용 의미차**만 리포트. 차이 없으면 "로그인 전용 데이터 없음"으로 확정.

---

## 트러블슈팅 (핵심 함정)
- **WebFetch 류 = 빈 페이지** → 반드시 `curl`. 페이지에 `window.context` 없으면 차단/빈 페이지 의심.
- **Python `json.loads` 실패** → context 는 JS 객체 리터럴. node 로만 파싱(`parse_context.js`).
- **동영상 302** → `cloud.video.taobao.com` 은 302 로 서명 URL(`caiyuanbao.alicdn.com/...?auth_key=`)을 준다. `collect.sh` 는 `curl -sI` 로 Location 을 받아 직접 다운로드.
- **썸네일 제외** → `.220x220.jpg`/`.310x310.jpg`/`.search.jpg`/`.summ.jpg` 는 변형. 원본 `-cib.jpg` 만.
- **md5 중복제거** → 같은 파일이 2회 등록되는 경우 있음(예: 메인 6·7 동일).
- **productAttributes 서버 오류** → 속성은 `gallery.fields.CpvEnhance`(decisionCpv+normalCpv)에서.
- **baxia 차단** → shop 하위 contactinfo/creditdetail·winport 는 HTTP 200 이어도 캡차 페이지일 수 있음. curl 로 못 뚫음.

## 워크드 예제
`../889272226600_ins6인치_포토카드_콜렉트북_수납앨범/` — 이 방법론으로 실제 수집·검증한 참조 결과.
