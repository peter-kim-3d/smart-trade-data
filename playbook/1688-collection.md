# 1688 상품 데이터 수집 플레이북 (에이전트 불문 / agent-agnostic)

> **이 문서의 사용법**: 이 플레이북은 1688(중국 도매) 상품 데이터를 수집·검증하는 **전 과정 방법론**이다.
> 아래 지시를 **어떤 AI 에이전트(Claude Code / OpenAI Codex / Hermes agent 등)에게도 그대로 붙여넣어** 실행시킬 수 있다.
> 어디서나 되는 도구는 **`curl` + `node`** 뿐이며, 재사용 스크립트는 `scripts/1688/` 폴더에 있다.
> 실제 작업 예시는 문서 끝의 **워크드 예제**(`889272226600_...`) 참조.

---

## 0. 복붙용 프롬프트 요약본 (다른 에이전트에게 이 한 단락만 줘도 됨)

> 1688 상품 `https://detail.1688.com/offer/{OFFER_ID}.html` 를 수집하라. **WebFetch 류는 빈 페이지를 주니 쓰지 말고 반드시 curl** 로 받되 헤더 `User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36`, `Referer: https://www.1688.com/`, `Accept-Language: zh-CN,zh;q=0.9` 를 붙여라(로그인·쿠키 불필요, HTTP 200 ~80KB). HTML 안 `window.context = (function(b,d){...})(window.contextPath, {거대객체})` 의 **2번째 인자 객체**가 전체 상품 데이터인데, 순수 JSON 이 아니라 JS 객체 리터럴이라 **Python json.loads 는 실패 → node 로 파싱**: `(window.contextPath,` 뒤 첫 `{` 부터 문자열 내부를 무시하며 괄호 균형 스캔 후 `eval('('+raw+')')`. 파싱 결과 `result.data` 아래 35개 모듈에서 제목(`productTitle.fields.title`)·SKU/가격/재고(`mainPrice.fields.finalPriceModel.tradeWithoutPromotion.skuMapOriginal`)·속성(`gallery.fields.CpvEnhance`)·이미지(`gallery.fields.offerImgList`)·동영상(`gallery.fields.video`)·상세URL(`description.fields.detailUrl`)·배송(`shippingServices.fields`)을 추출하라. 이미지는 `cbu01.alicdn.com`의 **원본 `-cib.jpg`만**(`.220x220`/`.310x310`/`.search`/`.summ` 썸네일 제외), Referer `https://detail.1688.com/`, **md5 중복제거**. 동영상은 `cloud.video.taobao.com` URL이 **302 리다이렉트** 라 `curl -sI`로 Location(서명 CDN URL)을 받아 직접 다운로드. 상세페이지는 detailUrl을 GET하면 `var offer_details={"content":"<html>"}` JSONP 라 접두사/`;` 제거 후 eval → `.content` HTML. **가장 빠른 길: `scripts/1688/collect.sh {OFFER_ID}` 실행.** 로그인 전용 데이터(도매/분소가·회사 상세·개별 리뷰)가 필요하면 사람이 브라우저 로그인 후 쿠키를 내보내 `scripts/1688/collect_authed.sh` 로 수집하고 `scripts/1688/diff_context.js` 로 익명본과 대조하라. **★데이터센터/클라우드 IP(VPS)에서는 데스크톱 detail.1688.com 이 IP 평판으로 차단(HTTP 200 + ~4.8KB baxia/TMD 챌린지, `window.context` 없음)되니, 모바일 `m.1688.com/offer/{OFFER_ID}.html` 을 iPhone UA 로 받아 `window.__INIT_DATA`(순수 JSON, JSON.parse) 를 파싱하라 — 가장 빠른 길은 `scripts/1688/collect_mobile.sh {OFFER_ID}`. 차단은 IP 문제라 TLS/HTTP2 지문 위장(curl-impersonate)으로는 안 뚫린다(실증). 자세한 IP·OS 별 판단은 §10.★**

---

## 1. 개요 / 목적

- **목적**: 1688 상품 1건의 정보(제목·SKU·가격·재고·속성·이미지·동영상·상세페이지·판매자·배송·리뷰)를 손실 없이 로컬에 수집.
- **입력**: offer URL `https://detail.1688.com/offer/{OFFER_ID}.html` 또는 offer id 숫자.
- **핵심 통찰**: "1688은 안티봇으로 fetch 불가"는 **오해**다. 브라우저 헤더를 붙인 일반 curl 로 **로그인 없이** HTTP 200 정상 수집된다. 대부분의 데이터가 HTML 안 `window.context` 에 임베디드돼 있다.
  - ⚠️ **단, 이는 접속 IP 가 주거용일 때.** detail.1688.com 은 접속 IP 의 ASN 을 점수화해 **데이터센터/클라우드 IP(VPS)** 는 안티봇으로 막는다(HTTP 200 이지만 챌린지). 이 경우 **모바일 `m.1688.com` 경로**(§2-0, `collect_mobile.sh`)를 쓴다 — 같은 VPS IP 에서도 익명으로 뚫리며 데이터는 `window.__INIT_DATA`(순수 JSON)에 있다. **차단은 IP 이지 OS/헤더/TLS 지문이 아니다**(§10 실증).
- **2단계 구조**: **Phase 1 익명 수집**(핵심, 거의 모든 것) → **Phase 2 로그인 수집(선택)**(도매/분소가·회사 상세·개별 리뷰가 필요할 때만) → **검증**.

### 출력 폴더 구조
```
{OFFER_ID}_{상품명슬러그}/
  README.md                         # 상품요약 + 수집방법 재현 + 참고사항
  01_상품정보/   상품정보_원본_중국어.md, 상품정보_한국어_번역.md, SKU_가격표.csv
  02_상세페이지/ 상세페이지_원본.html, 상세페이지_설명.md
  03_이미지/     01_메인이미지/, 02_상세이미지/, 03_동영상커버/
  04_동영상/     상품동영상.mp4
  05_원본데이터/ offer_{id}_페이지원본.html, context_상품데이터.json, summary.json, 상세페이지_원본응답.js, authed/(로그인분)
  06_수집스크립트/
```
> `scripts/1688/collect.sh` 가 이 구조를 자동 생성한다. 한국어 번역(`_한국어_번역.md`)·상세설명(`상세페이지_설명.md`)은 에이전트가 원문을 보고 추가 작성.

---

## 2. Phase 1 — 익명 수집 (로그인 불필요, 핵심 경로)

### 가장 빠른 길
```bash
bash scripts/1688/collect.sh https://detail.1688.com/offer/{OFFER_ID}.html [출력_기준폴더]
# 또는
bash scripts/1688/collect.sh {OFFER_ID}
```
이 한 줄이 아래 2-1~2-5 전부를 수행한다. 아래는 **수동 재현/디버깅용** 상세.

### 2-0. 데이터센터 IP / 데스크톱 차단 시 — 모바일 경로 (`collect_mobile.sh`)

```bash
bash scripts/1688/collect_mobile.sh {OFFER_ID} [출력_기준폴더]
```

**언제**: 접속 IP 가 데이터센터/클라우드(VPS)거나, 위 `collect.sh` 가 `window.context 없음`(≈4.8KB 챌린지)으로 실패할 때. **왜 되나**: detail.1688.com(데스크톱)은 IP 평판으로 막지만 **`m.1688.com`(모바일)** 은 같은 IP 에서도 익명 GET 으로 전체 상품 JSON 을 준다. **차이**: 데이터가 `window.context`(JS 리터럴, eval)가 아니라 **`window.__INIT_DATA`(순수 JSON → `JSON.parse`)** 에 있고, 모듈 ID 가 페이지마다 바뀌어 `parse_mobile.js` 는 `componentType` 으로 모듈을 찾는다. **출력 폴더 구조·소비 계약(summary.json + 03_이미지/)은 데스크톱과 동일.**

- fetch 는 **iPhone UA** 필수: `Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1`, Referer `https://www.1688.com/`. 이미지·동영상 처리(원본만·md5 dedup·동영상 302 서명 URL)는 데스크톱과 동일.
- ⚠️ **모바일 익명 초기 페이로드에 없는 것**(summary.json 에서 null): **SKU 별 개별가/재고**(`skuId` 만 확보), **리뷰 통계**(`rate.*`), **동영상 커버/제목**, **판매자 인증정보·재구매율**. 이들은 서명 mtop API 로 지연로딩되며 **익명으로는 못 채운다**(유일 API `mtop.alibaba.cbu.wireless.uniform.product.batchgetcomponentdata` 가 익명엔 빈 `{}` 반환, 전용 sku/rate API 부재 — 실증). 제목·계단가·이미지·동영상·속성·판매자 회사명·배송은 모두 포함.
- 수동 파싱: `node scripts/1688/parse_mobile.js parse page.html > init.json` → `node scripts/1688/parse_mobile.js summary init.json > summary.json` (서브커맨드는 `parse_context.js` 와 동일).
- 워크드 예제: `products/1688/647941709416_拍立得3寸…/` (이 경로로 실제 수집: 메인 11·상세 15 이미지, SKU 6, 동영상 6.14MB).

### 2-1. 상품 페이지 fetch (curl, 브라우저 헤더)
```bash
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
curl -sL -A "$UA" \
  -H "Referer: https://www.1688.com/" \
  -H "Accept-Language: zh-CN,zh;q=0.9" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
  -o page.html "https://detail.1688.com/offer/{OFFER_ID}.html"
```
- HTTP 200, 약 80KB HTML 이면 정상. `grep -q window.context page.html` 로 확인.
- ⚠️ **WebFetch/브라우저 없는 fetch 도구는 빈 페이지 반환 → 절대 쓰지 말 것.** 반드시 curl.

### 2-2. window.context 파싱 (반드시 node)
데이터는 HTML 안에 `window.context = (function(b,d){...})(window.contextPath, {거대한_JS객체})` 로 임베디드. **그 2번째 인자 객체**가 전체 상품 데이터.
- ⚠️ 순수 JSON 이 아니라 **JS 객체 리터럴** → `Python json.loads` 실패. **node 로 파싱**한다.
- 방법: `(window.contextPath,` 뒤의 첫 `{` 부터 **문자열 내부를 무시하며 괄호 균형 스캔** → `eval('('+raw+')')`.
```bash
node scripts/1688/parse_context.js parse   page.html    > context.json   # 전체
node scripts/1688/parse_context.js summary context.json > summary.json  # 정규화 요약
```

### 2-3. window.context 필드 맵 (`result.data` 아래 35개 모듈 중 핵심)

| 모듈.경로 | 필드 | 의미 |
|---|---|---|
| `productTitle.fields` | `.title` | 상품명(原文) |
| | `.saleNum` | 판매량(예 "2200+") |
| | `.shopInfo` | `companyName`/`authCompanyName` 회사명, `cardType`(factory=공장), `byrRepeatRate3m` 최근3개월 재구매율 |
| | `.rateInfo` | `goodRates` 긍정률, `goodsGrade` 별점, `impressionTagNodeList` 인상태그, `commonTagNodeList` 리뷰수(全部.count) |
| `gallery.fields` | `.offerImgList` / `.mainImage` | 메인이미지 URL 배열 |
| | `.subject` | 제목 |
| | `.video` | `{videoUrl, coverUrl, videoId, title}` |
| | `.CpvEnhance.decisionCpv` + `.normalCpv` | **상품속성**(款式/封面材质/内页页数/用途/品牌/货号/加印LOGO/加工定制/IP授权 등) |
| | `.offerId` | offer id |
| `mainPrice.fields.finalPriceModel.tradeWithoutPromotion` | `.skuMapOriginal[]` | 각 SKU `{skuId, specId, specAttrs, price, discountPrice, canBookCount 재고}` |
| | `.offerPriceDisplay` | 가격범위(예 "2.50-5.20") |
| | `.offerMinPrice` / `.offerMaxPrice` | 최저/최고가 |
| | `.offerBeginAmount` | MOQ(최소주문수량) |
| `mainPrice.fields.priceModel` | `.currentPrices` | 수량별 티어가 |
| `mainPrice.fields` | `.unit` | 판매단위(套 등) |
| `description.fields` | `.detailUrl` | 상세페이지 CDN URL |
| | `.leafCategoryId` | 카테고리ID |
| `shippingServices.fields` | `.location` | 발송지(예 浙江省温州市) |
| | `.freightInfo.logisticsText` | 물류(예 承诺48小时发货·常发圆通快递) |
| | `.unitWeight` | 개당 무게(kg) |
| `productAttributes` | (모듈 전체) | ⚠️ **서버 렌더 오류 잦음**(meta.errorMessage) → 속성은 위 `gallery.CpvEnhance` 에서 얻어라 |
| (위치 유동) | `sellerMemberId`(b2b-…), `sellerUserId`(숫자), `sellerWinportUrl`/`indexUrl`(shop 서브도메인), `winportUrl` | 판매자/회사 식별자 |

> 위 필드는 `parse_context.js summary` 가 정규화해 한 곳에 모아준다. 개별 값은 `node parse_context.js get summary.json <경로>` (예: `skus[0].price`, `seller.shopUrl`).

### 2-4. 상세페이지 본문
`description.fields.detailUrl`(예 `https://itemcdn.tmall.com/1688offer/icoss...`)을 GET 하면 응답이 JS: `var offer_details={"content":"<html>...img...</html>"}`.
- `var offer_details=` 접두사와 끝 `;` 제거 후 eval → `.content` 는 HTML(내부 `<img src>`).
```bash
curl -sL -A "$UA" -H "Referer: https://detail.1688.com/" -o 상세페이지_원본응답.js "$DETAIL_URL"
node scripts/1688/parse_context.js detail-html   상세페이지_원본응답.js > 상세페이지_원본.html
node scripts/1688/parse_context.js detail-images 상세페이지_원본응답.js            # 상세 이미지 URL
```
> 이 상품처럼 상세=메인 이미지와 동일하고 텍스트가 없을 수도, 다른 상품은 텍스트가 있을 수도 있다. 텍스트가 이미지로만 있으면 **필요시 OCR**.

### 2-5. 이미지 / 동영상 다운로드
**이미지**: URL 은 `https://cbu01.alicdn.com/img/ibank/...-cib.jpg`.
- **원본(`-cib.jpg`)만** 받고 **썸네일 변형(`.220x220.jpg`,`.310x310.jpg`,`.search.jpg`,`.summ.jpg`)은 제외**.
- 헤더: UA + `Referer: https://detail.1688.com/`.
- **md5 로 중복제거**(같은 파일을 2회 등록하는 경우 있음 — 예: 메인 6·7 동일).

**동영상**: `gallery.fields.video.videoUrl`(`https://cloud.video.taobao.com/play/u/.../{id}.mp4`)은 **302 리다이렉트** 를 반환, `Location:` 이 서명된 `caiyuanbao.alicdn.com/...mp4?auth_key=...`.
- `curl -L` 가 크로스호스트를 한 번에 안 따라갈 때가 있으니, **`curl -sI` 로 Location 을 얻어 그 서명 URL 을 직접 다운로드**하는 게 확실.
```bash
LOC=$(curl -sI -A "$UA" -H "Referer: https://detail.1688.com/" "$VIDEO_URL" | tr -d '\r' | awk -F': ' 'tolower($1)=="location"{print $2}' | tail -1)
curl -sL -A "$UA" -H "Referer: https://detail.1688.com/" -o 상품동영상.mp4 "${LOC:-$VIDEO_URL}"
```

---

## 3. Phase 2 — 로그인 수집 (선택, 쿠키 기반)

### 언제 필요한가
일부 데이터가 로그인 게이트일 수 있다: **铺货/分销가·회원가, 판매자 旺旺 연락처, 회사 영업집조, 개별 리뷰 본문.**
- ⚠️ 단, **워크드 예제 상품은 로그인해도 가격 등 상세 내용이 익명과 완전 동일**했다(`supportPuhuo=false`, `hasConsignReation=false` → 铺货/分销 미지원). → **반드시 §4 검증으로 확인**하고, 차이 없으면 로그인 수집은 불필요.

### 로그인은 자동화 불가 → 사람-쿠키 방식
1688 로그인은 **슬라이더 캡차(滑块) + 폰 SMS OTP + 디바이스 리스크** 라 헤드리스/curl 로그인이 안 된다.
→ 해결책: **사람이 본인 브라우저에서 로그인(2FA 처리) → 세션 쿠키만 내보내 curl 에 사용.**
> 에이전트가 브라우저 자동화(Playwright/MCP/claude-in-chrome)를 가졌다면 로그인도 직접 가능. 없으면 사람-쿠키 방식.

### 쿠키 내보내기
- **방법 A (권장)**: Chrome 확장 **"Get cookies.txt LOCALLY"** → 1688 탭에서 Export → Netscape `cookies.txt`.
- **방법 B**: DevTools → Network → 아무 **`detail.1688.com` 요청**(트래커 mmstat.com/`.gif`/track 아님) → Request Headers 의 `cookie:` 값 복사.
- `curl -b cookies.txt` 로 사용(파일/`name=value; …` 한 줄 형식 자동 인식).

### 수집 실행
```bash
bash scripts/1688/collect_authed.sh {OFFER_ID} /경로/cookies.txt
# shopUrl·memberId 는 같은 폴더의 익명 summary/context 에서 자동 추출(없으면 4·5번째 인자로 지정)
```
수집 대상: 로그인 상세(`detail.1688.com/offer/{id}.html`), 모바일(`m.1688.com/offer/{id}.html`), 회사페이지(`{shop}.1688.com/page/{index,contactinfo,creditdetail}.html`), winport(`winport.m.1688.com/page/index.html?memberId={memberId}`).

### ⚠️ 안티봇(baxia/滑块/punish)
shop 하위 3페이지(contactinfo/creditdetail)·winport 는 **HTTP 200 이어도 실제로는 캡차 챌린지 페이지**가 온다.
- 탐지: 본문에 `请登录|会员登录|滑块|punish|login.1688|nc_1_n1z|baxia` grep(스크립트가 자동 `⚠️` 표시).
- curl 로 못 뚫는다 → **사람이 브라우저에서 해당 페이지를 저장**해야 함.
- 실제 확보 가능(company_index): 설립일, 주소, 诚信通 연차, companyId, 主营, 서비스지표(재구매율·물류정시율), 旺旺 연락계정. **차단되어 미확보**: 영업집조 번호·등록자본·법인대표·유선전화.

### 리뷰 본문 (mtop AJAX 전용)
리뷰는 페이지에 안 박혀 있고 서명 AJAX 로 불러온다. 엔드포인트 패턴 `https://h5api.m.1688.com/h5/mtop.../1.0/?jsv=2.7.4&appKey=12574478&t=...&sign=...&data=...`, 서명은 `_m_h5_tk` 쿠키 토큰 + `md5(token&t&appKey&data)`. api명/파라미터가 자주 변해 자동화가 불안정.
- **실전(권장)**: 사람이 로그인 브라우저에서 **商品评价** 스크롤 → DevTools Network 필터 `rate` → Response 에 `model.commentList[]` 있는 요청 우클릭 → Copy → **Copy response** → `05_원본데이터/authed/reviews_raw.json` 저장.
- 파싱: `node scripts/1688/parse_reviews.js reviews_raw.json` → `content`·`starLevel`·`specInfo` 규격·`quantity` 수량·`raterUserNick`·`buyerLevelTag`·`gmtPublished`(ms epoch)·`images`·`rateId`.
- ⚠️ **1688 리뷰는 상투적(canned) 복붙 호평이 많아 본문 가치 낮음** — 단 메타데이터(**구매 규격·수량**)는 유효(도매 단위 구매 확인 가능).

---

## 4. 검증 (익명 vs 로그인 차이 확인)

두 context JSON 을 재귀 deep-diff 해 **로그인 전용 의미차**를 확인한다.
```bash
# 로그인 HTML 만 있으면 먼저 context 로 변환
node scripts/1688/parse_context.js parse 05_원본데이터/authed/detail_authed.html > authed_context.json
node scripts/1688/diff_context.js 05_원본데이터/context_상품데이터.json authed_context.json
```
- **노이즈 자동 무시**: `offerMemberTags`(내부 태그 순서), `ipvId`/`exposeArgs`/`trackInfo`(요청별 추적ID), 시간차 집계갱신(리뷰수·재구매율·`expectSendHour`).
- 워크드 예제는 상세페이지에 **로그인 전용 의미차 0** 이었다.
- **이미지 무결성**: `file *.jpg` 로 타입 확인, md5 중복제거 확인.

---

## 5. 트러블슈팅 / 함정 (반드시 숙지)

| 증상 | 원인 | 대응 |
|---|---|---|
| 빈 페이지 / `window.context` 없음 | WebFetch 류 도구 사용 or 차단 | **curl + 브라우저 헤더**. 그래도 없으면 차단 의심 |
| `json.loads` 실패 | context 는 **JS 객체 리터럴**(순수 JSON 아님) | **node** 로 괄호 균형 스캔 후 eval (`parse_context.js`) |
| 동영상 0바이트 / 실패 | `cloud.video.taobao.com` 302 크로스호스트 | `curl -sI` 로 Location(서명 URL) 받아 직접 다운로드 |
| 이미지에 썸네일 섞임 | `.220x220`/`.310x310`/`.search`/`.summ` 변형 | 원본 `-cib.jpg` 만, 나머지 제외 |
| 같은 이미지 중복 | 같은 파일 2회 등록 | **md5 중복제거** |
| 상세 이미지가 다른 URL로 중복(내용 동일) | 같은 이미지가 여러 CDN 객체명(`O1CN…`)으로 게시 → URL uniq 만으로는 못 거름 | 상세 이미지에도 **메인과 동일한 md5 중복제거** 적용(647941709416: 22 URL → 15 유니크). `collect.sh` 상세 루프에 `SEEN_D` md5 스킵 추가 |
| SKU에 개별 가격 없음 | offer가 SKU별가 아닌 **수량 티어가**(`priceModel.currentPrices`)만 제공 → `skuMapOriginal`에 `price` 필드 자체 부재 | 정상 케이스. SKU csv 가격열은 빈칸, 가격은 `offerPriceDisplay` 범위 + summary `price.tiers` 로 확인 |
| 속성이 비어있음/오류 | `productAttributes` 서버 렌더 오류 | `gallery.fields.CpvEnhance`(decisionCpv+normalCpv) 사용 |
| 리뷰 본문이 다 비슷 | 1688 canned 리뷰 | 본문보다 **규격·수량 메타데이터** 활용 |
| 회사 상세/winport 가 캡차 | baxia/滑块/punish 안티봇 | curl 로 불가 → 사람이 브라우저에서 저장 |
| `while read` 가 마지막 줄 누락 | 목록 마지막 줄 개행 없음 | 루프에 `|| [ -n "$url" ]` 가드(스크립트에 적용됨) |
| 데스크톱이 ~4.8KB 챌린지만(`window.context` 없음) | **데이터센터/클라우드 IP** 평판 차단(baxia/TMD) — OS·헤더·TLS 지문 무관(실증) | **모바일 `collect_mobile.sh`** 사용(m.1688.com + `window.__INIT_DATA`). 주거용 IP·주거용 프록시면 데스크톱도 통과 (§2-0·§10) |
| Windows 에서 스크립트가 안 돌아감 | cmd/PowerShell 엔 bash 없음 | **WSL2**(권장) 또는 **Git Bash**(bash+md5sum+curl 포함)에서 실행. node 는 크로스플랫폼 설치 (§10) |

---

## 6. 보안 수칙
- 쿠키/비밀번호를 **채팅·로그·문서에 붙여넣지 말 것.** 수집 에이전트는 쿠키 값을 **echo 하지 말 것**.
- `cookies.txt` 와 authed HTML(계정 정보 포함 가능)은 **git 제외**(작업 폴더가 repo 면 `.gitignore`), 작업 후 삭제.
- 모든 수집 스크립트는 **GET(읽기)만** — 주문/결제/장바구니 변경 없음.
- 로그인 페이지에는 회원 계정 정보(상단 내비 등)가 섞일 수 있음 → 문서에는 상품/판매자/회사/리뷰 데이터만 남기고 계정 정보는 넣지 않는다.

---

## 7. 에이전트-불문 도구 매핑 (범용성)
- **어디서나 되는 것: `curl` + `node`** (Claude Code / Codex / Hermes 셸 모두 보유). Python 도 되지만 **`window.context` 파싱만은 node** 필수(json.loads 실패).
- 에이전트가 **브라우저 자동화(Playwright/MCP/claude-in-chrome)** 를 가졌다면 Phase 2 로그인도 직접 가능. 없으면 사람-쿠키 방식.
- **WebFetch 류는 1688 에서 신뢰 불가(빈 페이지) → 사용 금지.**

## 8. 재사용 스크립트 (scripts/1688/)
`scripts/1688/README.md` 에 각 스크립트 상세 사용법. 요약:
- `collect.sh <offer_url_또는_id> [출력폴더]` — 익명 수집(데스크톱 detail.1688.com, 주거용 IP).
- `collect_mobile.sh <offer_url_또는_id> [출력폴더]` — 익명 수집(모바일 m.1688.com, 데이터센터 IP 우회). 출력 계약 동일.
- `parse_context.js <parse|summary|get|images|skucsv|attrs|productmd|detail-html|detail-images>` — window.context 파서(데스크톱).
- `parse_mobile.js <동일 서브커맨드>` — window.__INIT_DATA 파서(모바일). 출력 스키마 동일.
- `collect_authed.sh <offer_id> <cookies.txt> [출력폴더] [shopUrl] [memberId]` — 로그인 수집.
- `parse_reviews.js <reviews_raw.json> [--json]` — commentList 파서(조각/JSONP 허용, rateId 중복제거).
- `diff_context.js <anon.json> <authed.json> [--all]` — 노이즈 필터링된 의미차 리포트.

---

## 9. 워크드 예제
`889272226600_ins6인치_포토카드_콜렉트북_수납앨범/` — 이 방법론으로 **실제 수집·검증**한 참조 결과.
- 상품: `ins6寸相册明信片书签混合按扣收纳册...` (포토카드/인생네컷 콜렉트북), ¥2.50~5.20, SKU 8종, MOQ 1套, 판매 2,200+.
- 익명 수집: 메인 이미지 7장(6·7 md5 동일), 상세 이미지 5장, 동영상 1.67MB, SKU 8종·속성 전체(CpvEnhance) 확보.
- 로그인 수집·검증: 가격 **익명과 완전 동일**(铺货/分销 미지원), 회사 개요 일부 확보, contactinfo/creditdetail/winport 는 baxia 차단, 개별 리뷰는 DevTools 캡처로 확보.
- 이 플레이북/스크립트는 그 폴더를 대상으로 `collect.sh 889272226600` 셀프테스트를 통과했다(제목·SKU·이미지·동영상 정상 추출).
- `647941709416_拍立得3寸…/` — **모바일 경로**(`collect_mobile.sh`) 워크드 예제. 데이터센터 VPS 에서 데스크톱이 차단된 상태로 수집(메인 11·상세 15 이미지, SKU 6, 동영상 6.14MB).

---

## 10. 실행 환경 가이드 (OS / IP 유형)

> 자주 헷갈리는 지점: "OS 따라 수집법이 달라지나?" → **아니다.** 무엇이 뚫리느냐는 **접속 IP 유형**이 정하고, OS 는 **스크립트를 어떻게 돌리느냐(툴·셸)** 만 정한다. 이 둘은 독립 축이다.

### 축 1 — 접속 IP 유형이 "어떤 엔드포인트가 되느냐"를 정한다 (핵심)

| IP 유형 | 데스크톱 `collect.sh` | 권장 |
|---|---|---|
| **주거용/사무실 ISP**(집 Mac, 집 Linux, 주거용 프록시) | ✅ 통과(≈80KB, `window.context`) — 데이터 가장 풍부(SKU 개별가/재고·리뷰까지 가능) | `collect.sh`(데스크톱) |
| **데이터센터/클라우드**(VPS: AWS·GCP·Vultr·Hetzner·OVH·Hostinger 등) | ❌ 차단(HTTP 200 + ~4.8KB baxia/TMD 챌린지, `window.context` 없음) | `collect_mobile.sh`(모바일) |

- **왜 IP 인가**: detail.1688.com 은 접속 IP 의 ASN(대역 소유자)을 봇 점수로 쓴다. **실증**: 완벽한 Chrome 지문(curl-impersonate: TLS+HTTP2+헤더 전부 Chrome)으로 VPS 에서 받아도 **바이트 단위 동일한 4.8KB 챌린지** → 지문/헤더/OS 문제가 아니라 **IP 평판 문제**. 쿠키 워밍은 오히려 `punish` 로 악화.
- **IP 유형 확인**: `curl -s https://ipinfo.io/json` → `org`/`asn` 이 hosting/datacenter 면 데스크톱은 막힌다고 보면 된다.
- **주거용 프록시**를 쓰면 VPS 에서도 데스크톱을 통과시킬 수 있다: 코드 수정 없이 `https_proxy=http://user:pass@host:port` 환경변수만 export 하고 `collect.sh` 실행(유료). 데스크톱의 풍부한 데이터가 꼭 필요할 때만.

### 축 2 — OS 가 "스크립트를 어떻게 돌리느냐"를 정한다

공통 요구: **`bash` + `curl` + `node`**(GET 만, jq/python 불필요). 스크립트는 GNU 전용 구문을 쓰지 않고 md5 도 `md5sum`(Linux)/`md5 -q`(macOS) 를 자동 감지하므로 **Mac/Linux 는 수정 없이 그대로** 동작한다.

| OS | curl | md5 | 셸 | node 설치 | 비고 |
|---|---|---|---|---|---|
| **macOS** | 내장(LibreSSL) | `md5 -q`(자동) | bash(3.2+; 최신은 `brew install bash`) | `brew` 또는 `nvm` | 보통 주거용 IP → 데스크톱 경로 |
| **Linux(데스크톱/서버/WSL)** | 내장(OpenSSL) | `md5sum`(자동) | bash 내장 | 배포판 패키지 / `nvm` / 공식 바이너리(`~/.local`, root 불필요) | VPS 면 데이터센터 IP → 모바일 경로 |
| **Windows** | `curl.exe` 내장(Win10+) | — | **cmd/PowerShell 엔 bash 없음** | 크로스플랫폼 설치 | 아래 방법 필요 |

**Windows 실행법**(택 1):
- **(A) WSL2 — 권장.** 우분투를 깔면 사실상 Linux 다. 스크립트가 그대로 돌고 node 설치도 Linux 와 동일. 파일 I/O 는 `\\wsl$` 대신 WSL 내부 경로(`~/…`)에서 하는 게 성능·인코딩상 유리.
- **(B) Git Bash.** Git for Windows 에 bash + coreutils(`md5sum`) + curl 이 포함돼 스크립트가 그대로 실행된다. node 는 별도 설치.
- **(C) PowerShell 재작성** — 비권장(공수 큼). 필요하면 curl.exe + node 로 포팅 가능하나 유지보수 부담.
- 파일명에 한중일 문자가 들어가므로 UTF-8 터미널을 쓰고, git 에서 경로가 깨져 보이면 `git config core.quotepath false`.

### 의사결정 플로우 (한눈에)

1. `bash scripts/1688/collect.sh {ID} products/1688` 실행.
2. **성공**(≈80KB, `window.context` 있음) → 끝. (주거용 IP)
3. **~4.8KB 챌린지 / `window.context 없음`** → IP 차단 → `bash scripts/1688/collect_mobile.sh {ID} products/1688`. (데이터센터 IP)
4. 데스크톱 수준의 **SKU 개별가/재고·리뷰**가 꼭 필요 → 주거용 프록시로 `collect.sh`, 또는 사람-쿠키 로그인 경로(§3).

### 권장 아키텍처 (이 repo 의 VPS/Hermes 기준)

- VPS(데이터센터 IP)에서 자동 수집하는 Hermes 는 **`collect_mobile.sh` 를 기본 경로**로 삼는다(데스크톱은 이 IP 에서 계속 막힌다).
- SKU 개별가/재고·리뷰 등 모바일에 없는 데이터가 필요한 상품만, 주거용 프록시(데스크톱 `collect.sh`) 또는 로그인 경로로 **선택 보강**.
- (선택) 두 경로를 자동 전환하고 싶으면 얇은 래퍼(`collect_auto.sh`: 데스크톱 시도 → 챌린지 감지 시 모바일 폴백)를 두면 되지만, IP 유형이 고정된 환경에서는 경로를 직접 지정하는 편이 단순하다.
