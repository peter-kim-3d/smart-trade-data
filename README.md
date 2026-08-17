# smart-trade-data

소스(1688 등)별 **상품 데이터**를 **수집 → 가공 → 생성** 3단계 파이프라인으로 쌓는 데이터+도구 repo다. 각 소스는 `scripts/{site}/` 수집 스크립트로 상품을 받아 `products/{site}/` 아래 표준 폴더에 산출물을 쌓고, 이후 가공·생성 단계가 그 위에 상세페이지 산출물을 얹는다. 이 repo 는 VPS 에 clone 되어 Hermes agent 가 자동 실행하는 기반이다. 모든 수집은 GET(읽기)만 하며 주문/결제/장바구니 변경은 없다.

## 파이프라인 3단계

| 단계 | 입력 | 출력 | 도구 | 상태 |
|---|---|---|---|---|
| **1. 수집(collect)** | 1688 offer URL/id | `05_원본데이터/summary.json` + `01~05/` | `scripts/1688/` + `skills/collect-1688` | 사용 중 |
| **2. 가공(process)** | `summary.json` | `06_가공/page_input.json` *(계약 정의 예정)* | `skills/process-product` *(미작성)* · `playbook/processing.md` | 준비 중 |
| **3. 생성(generate)** | `page_input.json` + `templates/` | `07_생성/` 초안 | `skills/generate-page` *(미작성)* · `playbook/page-generation.md` | 준비 중 |

- `06_가공/`·`07_생성/` 폴더는 **미리 만들지 않는다.** 각 단계가 첫 실행 때 생성하며, **폴더 존재 자체가 진행 상태 신호**다.
- 가공·생성 스킬은 `references/detail-pages/` 의 실제 사례를 리버스엔지니어링한 뒤 작성한다.

## 사용법 (수집)

```bash
bash scripts/1688/collect_auto.sh <offer_url_또는_id> products/1688
```

`collect_auto.sh` 는 접속 IP 로 데스크톱이 뚫리는지 실시간 프로브해 `collect.sh`(주거용 IP)↔`collect_mobile.sh`(데이터센터 IP)로 자동 분기한다(무인 구동 권장). 산출물은 `products/1688/{OFFER_ID}_{슬러그}/` 로 생성된다. 수동 경로·OS 별 실행법·트러블슈팅은 `playbook/1688-collection.md`, 스크립트 상세는 `scripts/1688/README.md` 참조.

- 요구사항: `bash` + `curl` + `node` (jq/python 불필요). `window.context`/`window.__INIT_DATA` 파싱은 반드시 node.
- 로그인 전용 데이터(도매/분소가·회사 상세·개별 리뷰)가 필요하면 `scripts/1688/collect_authed.sh`(사람 개입 필요).

## 커밋 컨벤션

| prefix | 대상 |
|---|---|
| `collect(1688):` | 수집 산출물 추가/갱신 |
| `process:` | 가공 산출물 |
| `generate:` | 생성 산출물 |
| `tune(단계):` | 스킬/플레이북/스크립트 튜닝 (예: `tune(collect):`) |
| `structure:` | repo 구조·계약·문서 골격 변경 |

## 소비 계약 v1 (수집 → 가공)

가공 단계가 의존하는 **불변 입력**. `summary.json` 은 데스크톱(`scripts/1688/parse_context.js`)·모바일(`scripts/1688/parse_mobile.js`) 두 수집 경로가 **동일한 객체 스키마**로 생성하며, 아래는 **두 경로가 공통으로 보장하는 필드**다(계약 v1).

### 불변 경로

- `products/{site}/{OFFER_ID}_{슬러그}/05_원본데이터/summary.json` — 정규화된 상품 요약.
- `products/{site}/{OFFER_ID}_{슬러그}/03_이미지/` — `01_메인이미지/`, `02_상세이미지/`, (커버 있으면) `03_동영상커버/`.

### 보장 필드 (present & non-null, 두 경로 공통)

- `offerId`(number), `title`(비어있지 않음), `slug`
- `saleNum`(string; 형식은 경로별로 다를 수 있음 — 데스크톱 `"2200+"` / 모바일 `"1597"`)
- `unit`(string)
- `price.display`, `price.min`, `price.max`(string), `price.moq`(number), `price.tiers[]`(각 `{price, beginAmount}`)
- `skus[]`(배열; 각 원소 `skuId` 보장)
- `attributes[]`(각 `{name, values[]}`)
- `images[]`(≥1, 원본 이미지 URL)
- `video`(object 또는 null; object 면 `videoUrl`·`videoId` 보장)
- `detailUrl`(대개 존재; 상세페이지 없으면 null), `leafCategoryId`(number)
- `shipping.location`, `shipping.logisticsText`, `shipping.unitWeight`
- `seller.companyName`, `seller.sellerMemberId`, `seller.sellerUserId`, `seller.shopUrl`, `seller.winportUrl`
- `rate`(object 존재; 값은 아래 약필드 참조)

### 약(弱)필드 — 계약 v1 미보장 (경로/오퍼 의존, null 가능)

가공은 이 필드들을 **없을 수 있다고 가정**해야 한다. 데스크톱은 `window.context` 에서 채우지만, **모바일 익명 페이로드에는 없어 null**(서명 mtop 지연로딩, 익명 불가):

- `skus[].specId`, `skus[].specAttrs`, `skus[].price`, `skus[].discountPrice`, `skus[].canBookCount`
- `video.coverUrl`, `video.title`
- `seller.authCompanyName`, `seller.cardType`, `seller.byrRepeatRate3m`
- `rate.goodRates`, `rate.goodsGrade`, `rate.reviewCount`, `rate.impressionTags`

> **대조 근거**: repo 내 실측 `summary.json`(모바일 수집분 1건: `647941709416`) + `parse_context.js`/`parse_mobile.js` 의 `buildSummary()`. 데스크톱 수집분 `summary.json` 은 아직 repo 에 없어 스키마는 코드로 대조함. 두 파서의 출력 키 집합은 동일하며, 위 약필드만 모바일에서 null 이다.

## page_input.json 계약 (가공 → 생성)

*(정의 예정)* — `06_가공/page_input.json` 의 필드 계약은 `references/` 분석 및 가공 스킬 작성 시 확정한다.

## 확장 규약 (새 소스 추가)

새 소스 `{site}` 를 추가하려면 아래 3가지를 갖춘다.

1. **수집 스크립트**: `scripts/{site}/collect.sh <url|id> <출력기준폴더>` (2번째 인자로 출력 기준폴더를 받는 계약을 지킨다).
2. **플레이북**: `playbook/{site}-collection.md`.
3. **인덱스**: `products/{site}/INDEX.md`.

## 저장소 구조

```
README.md
.gitignore
skills/                          # 에이전트 스킬 (repo 가 원본, Hermes 엔 심링크)
  README.md
  collect-1688/SKILL.md          # 수집 스킬 (사용 중)
  (process-product/ · generate-page/ — references 분석 후 작성 예정)
references/detail-pages/         # 상세페이지 레퍼런스 (리버스엔지니어링 원료 + 품질 기준)
  README.md
templates/                       # 상세페이지 생성 템플릿 (references 분석 후 채움)
  README.md
playbook/
  1688-collection.md             # 1688 수집 방법론
  processing.md                  # 가공 플레이북 (골격)
  page-generation.md             # 생성 플레이북 (골격)
scripts/1688/                    # 1688 수집 도구 (bash + curl + node)
  collect_auto.sh                # 자동 분기 래퍼 (데스크톱↔모바일, 무인 구동 권장)
  collect.sh / collect_mobile.sh / collect_authed.sh
  parse_context.js / parse_mobile.js / parse_reviews.js / diff_context.js
  README.md
products/1688/
  INDEX.md                       # 수집·가공·생성 진행 목록
  {OFFER_ID}_{슬러그}/
    01_상품정보/ 02_상세페이지/ 03_이미지/ 04_동영상/ 05_원본데이터/   # 수집(불변)
    06_가공/                     # 가공 단계가 첫 실행 때 생성 (미리 만들지 않음)
    07_생성/                     # 생성 단계가 첫 실행 때 생성 (미리 만들지 않음)
```

## 복붙용 프롬프트 요약본 (플레이북 §0 인용)

> 아래는 `playbook/1688-collection.md` §0 을 그대로 인용한 것이다(스크립트 경로는 이 repo 구조 = `scripts/1688/` 기준). 다른 에이전트에게 이 한 단락만 줘도 된다. 데이터센터 IP(VPS)에서는 데스크톱이 IP 차단되니 `scripts/1688/collect_auto.sh {OFFER_ID}` 로 실행하면 모바일 경로로 자동 폴백한다.

> 1688 상품 `https://detail.1688.com/offer/{OFFER_ID}.html` 를 수집하라. **WebFetch 류는 빈 페이지를 주니 쓰지 말고 반드시 curl** 로 받되 헤더 `User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36`, `Referer: https://www.1688.com/`, `Accept-Language: zh-CN,zh;q=0.9` 를 붙여라(로그인·쿠키 불필요, HTTP 200 ~80KB). HTML 안 `window.context = (function(b,d){...})(window.contextPath, {거대객체})` 의 **2번째 인자 객체**가 전체 상품 데이터인데, 순수 JSON 이 아니라 JS 객체 리터럴이라 **Python json.loads 는 실패 → node 로 파싱**한다. 데이터센터 IP 라 데스크톱이 baxia/TMD 로 차단되면 모바일 `https://m.1688.com/offer/{OFFER_ID}.html` 을 iPhone UA 로 받아 `window.__INIT_DATA`(순수 JSON) 를 파싱하라. **가장 빠른 길: `scripts/1688/collect_auto.sh {OFFER_ID}` 실행**(데스크톱 프로브 → 자동 분기). 로그인 전용 데이터가 필요하면 사람이 브라우저 로그인 후 쿠키를 내보내 `scripts/1688/collect_authed.sh` 로 수집하고 `scripts/1688/diff_context.js` 로 익명본과 대조하라.

## 보안 수칙

- `cookies.txt` 와 로그인 산출물(`05_원본데이터/authed/`)은 git 에 넣지 않는다(`.gitignore` 로 차단). 작업 후 삭제.
- 쿠키/토큰/비밀번호를 채팅·로그·문서·커밋에 붙여넣지 말 것.
