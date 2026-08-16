# smart-trade-data

소스(1688 등)별 **상품 데이터 수집 산출물**과 그 **수집 도구(플레이북 + 스크립트)** 를 함께 담는 데이터 repo다. 각 소스는 `scripts/{site}/` 의 수집 스크립트로 상품을 받아 `products/{site}/` 아래에 표준 폴더 구조로 산출물을 쌓는다. 이 repo 는 VPS 에 clone 되어 Hermes agent 가 수집을 자동 실행하는 기반이 된다. 모든 수집 스크립트는 GET(읽기)만 하며 주문/결제/장바구니 변경은 없다.

## 사용법

```bash
bash scripts/1688/collect.sh <offer_url_또는_id> products/1688
```

> **환경을 모르거나 자동화(Hermes/AI) 구동이면 `collect_auto.sh` 권장** — 접속 IP 로 데스크톱이 뚫리는지 실시간 프로브해 `collect.sh`(주거용 IP)↔`collect_mobile.sh`(데이터센터 IP)로 자동 분기한다:
>
> ```bash
> bash scripts/1688/collect_auto.sh <offer_url_또는_id> products/1688
> ```

- 첫 번째 인자: offer URL(`https://detail.1688.com/offer/{OFFER_ID}.html`) 또는 offer id 숫자.
- 두 번째 인자: 출력 기준폴더(위 예시는 `products/1688`). 산출물은 `products/1688/{OFFER_ID}_{슬러그}/` 로 생성된다.
- 요구사항: `bash` + `curl` + `node` (jq/python 불필요). `window.context` 파싱은 반드시 node.
- 로그인 전용 데이터(도매/분소가·회사 상세·개별 리뷰)가 필요하면 `scripts/1688/collect_authed.sh` + `scripts/1688/diff_context.js` 사용. 자세한 방법론은 `playbook/1688-collection.md` 참조.

### 데이터센터 IP(VPS) 에서는 모바일 경로

```bash
bash scripts/1688/collect_mobile.sh <offer_url_또는_id> products/1688
```

`detail.1688.com`(데스크톱) 은 **접속 IP 의 평판(ASN)** 으로 안티봇(baxia/TMD)을 건다. 집·사무실 같은 **주거용 IP** 는 위 `collect.sh` 로 통과되지만, **데이터센터/클라우드 IP(VPS: AWS·GCP·Vultr·Hetzner·OVH·Hostinger 등)** 는 HTTP 200 이어도 ~4.8KB 챌린지 페이지만 온다(→ `window.context` 없음). 이때는 **모바일 `m.1688.com` 경로(`collect_mobile.sh`)** 를 쓴다 — 같은 데이터센터 IP 에서도 익명으로 뚫린다(데이터는 `window.__INIT_DATA` JSON). 출력 폴더 구조·소비 계약은 `collect.sh` 와 동일. 단 모바일 익명 페이로드에는 SKU 별 개별가/재고·리뷰·판매자 인증정보가 없다(핵심 데이터는 모두 포함). **차단 원인은 IP 이지 OS 가 아니다**(TLS 지문 위장으로는 안 뚫림 — 실증됨). 자세한 판단 기준·OS 별 실행법은 `playbook/1688-collection.md` §10.

## 확장 규약 (새 소스 추가)

새 소스 `{site}` 를 추가하려면 아래 3가지를 갖춘다.

1. **수집 스크립트**: `scripts/{site}/collect.sh <url|id> <출력기준폴더>` 구현 (2번째 인자로 출력 기준폴더를 받는 계약을 지킨다).
2. **플레이북**: `playbook/{site}-collection.md` — 그 소스의 전 과정 수집·검증 방법론.
3. **인덱스**: `products/{site}/INDEX.md` — 수집 목록 테이블.

## 하위 소비 계약 (step 2 consumer contract)

다운스트림(상세페이지 생성 등 step 2 소비자)이 의존하는 아래 경로는 **불변**으로 유지한다. 폴더/파일명을 바꾸지 말 것:

- `products/{site}/{OFFER_ID}_{슬러그}/05_원본데이터/summary.json` — 정규화된 상품 요약(제목·SKU·가격·이미지·동영상·판매자 등).
- `products/{site}/{OFFER_ID}_{슬러그}/03_이미지/` — `01_메인이미지/`, `02_상세이미지/`, `03_동영상커버/` 하위 구조 포함.

## 복붙용 프롬프트 요약본 (플레이북 §0 인용)

> 아래는 `playbook/1688-collection.md` §0 을 그대로 인용한 것이다(스크립트 경로는 이 repo 구조 = `scripts/1688/` 기준으로 반영됨). 다른 에이전트에게 이 한 단락만 줘도 된다.

> 1688 상품 `https://detail.1688.com/offer/{OFFER_ID}.html` 를 수집하라. **WebFetch 류는 빈 페이지를 주니 쓰지 말고 반드시 curl** 로 받되 헤더 `User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36`, `Referer: https://www.1688.com/`, `Accept-Language: zh-CN,zh;q=0.9` 를 붙여라(로그인·쿠키 불필요, HTTP 200 ~80KB). HTML 안 `window.context = (function(b,d){...})(window.contextPath, {거대객체})` 의 **2번째 인자 객체**가 전체 상품 데이터인데, 순수 JSON 이 아니라 JS 객체 리터럴이라 **Python json.loads 는 실패 → node 로 파싱**: `(window.contextPath,` 뒤 첫 `{` 부터 문자열 내부를 무시하며 괄호 균형 스캔 후 `eval('('+raw+')')`. 파싱 결과 `result.data` 아래 35개 모듈에서 제목(`productTitle.fields.title`)·SKU/가격/재고(`mainPrice.fields.finalPriceModel.tradeWithoutPromotion.skuMapOriginal`)·속성(`gallery.fields.CpvEnhance`)·이미지(`gallery.fields.offerImgList`)·동영상(`gallery.fields.video`)·상세URL(`description.fields.detailUrl`)·배송(`shippingServices.fields`)을 추출하라. 이미지는 `cbu01.alicdn.com`의 **원본 `-cib.jpg`만**(`.220x220`/`.310x310`/`.search`/`.summ` 썸네일 제외), Referer `https://detail.1688.com/`, **md5 중복제거**. 동영상은 `cloud.video.taobao.com` URL이 **302 리다이렉트** 라 `curl -sI`로 Location(서명 CDN URL)을 받아 직접 다운로드. 상세페이지는 detailUrl을 GET하면 `var offer_details={"content":"<html>"}` JSONP 라 접두사/`;` 제거 후 eval → `.content` HTML. **가장 빠른 길: `scripts/1688/collect.sh {OFFER_ID}` 실행.** 로그인 전용 데이터(도매/분소가·회사 상세·개별 리뷰)가 필요하면 사람이 브라우저 로그인 후 쿠키를 내보내 `scripts/1688/collect_authed.sh` 로 수집하고 `scripts/1688/diff_context.js` 로 익명본과 대조하라.

## 저장소 구조

```
README.md
.gitignore
playbook/1688-collection.md      # 1688 수집 전 과정 방법론
scripts/1688/                    # 1688 수집 도구 (bash + curl + node)
  collect_auto.sh                # 자동 분기 래퍼 (데스크톱↔모바일, 무인 구동 권장)
  collect.sh                     # 익명 수집 (데스크톱 detail.1688.com — 주거용 IP)
  collect_mobile.sh              # 익명 수집 (모바일 m.1688.com — 데이터센터 IP 우회)
  collect_authed.sh              # 로그인(쿠키) 수집 (선택)
  parse_context.js               # window.context 파서 (데스크톱)
  parse_mobile.js                # window.__INIT_DATA 파서 (모바일)
  parse_reviews.js               # 리뷰 파서
  diff_context.js                # 익명 vs 로그인 의미차
  README.md                      # 스크립트 상세 사용법
products/1688/INDEX.md           # 수집 목록
```

## 보안 수칙

- `cookies.txt` 와 로그인 산출물(`05_원본데이터/authed/`)은 git 에 넣지 않는다(`.gitignore` 로 차단). 작업 후 삭제.
- 쿠키/토큰/비밀번호를 채팅·로그·문서·커밋에 붙여넣지 말 것.
