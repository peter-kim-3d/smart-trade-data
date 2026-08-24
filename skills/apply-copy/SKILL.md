---
name: apply-copy
description: 클린 이미지에 한국어 카피(A/B 두 톤)를 얹은 최종 상세페이지 이미지 생성
---

# apply-copy

## 작업 위치
smart-trade-data repo 루트. 경로 모르면 이 SKILL.md 위치를 realpath로 확인해 루트 찾기.

## 언제 사용
process 채널에서 "카피"/"최종본"/"final" 요청 + offer id일 때.
전제: 06_가공/text_extract.json (copy_a/copy_b 포함) 과 06_가공/clean/ 이 이미 있어야 함
(process-images + clean-images 먼저). 없으면 뭐가 빠졌는지 보고 후 중단.

## 접근 원칙
클린 이미지 위에 한국어 카피를 얹는다. Codex CLI image_generation(referenced_image_paths).
한글 렌더링은 검증됨(획 깨짐·오탈자 없이 나옴). 카피는 text_extract.json 의
copy_a(깔끔·미니멀), copy_b(감성·생활제안)를 사용 — 새로 만들지 말고 그걸 쓴다.
(카피 생성은 process-images 담당. 이 스킬은 얹기만.)

## 절차 (offer id 하나당)
1. cd 리포루트 && git pull --rebase
2. text_extract.json 읽어 이미지별 has_text / copy_a / copy_b 확인.
3. 06_가공/final_A/ 와 06_가공/final_B/ 디렉토리 생성.
4. 각 이미지 처리:
   - has_text:true → clean/{파일명} 을 입력으로 Codex image_generation 편집:
     * final_A: 지시="클린 이미지 위 원래 텍스트가 있던 위치쯤에 다음 한국어 카피를 얹어라:
       [copy_a 내용]. 원래와 비슷한 위치·크기·색(진회색). 제품/배경은 그대로.
       카피 외 다른 문구는 넣지 마라." → 06_가공/final_A/{파일명}
     * final_B: 같은 방식으로 copy_b 사용 → 06_가공/final_B/{파일명}
   - has_text:false → clean/{파일명} 을 final_A/ 와 final_B/ 에 그대로 복사(얹을 카피 없음).
   → final_A/, final_B/ 각각 전체 이미지 세트가 다 있어야 함.
5. 각 결과를 view로 확인: 한글이 깨끗한지(깨짐/오탈자/누락), 지정한 카피가 정확히 들어갔는지,
   불필요한 추가 문구 없는지, 제품 크게 안 망가졌는지. 문제면 1회 재시도, 그래도 문제면 보고.
6. INDEX.md 의 해당 상품 "생성"(또는 최종) 표시.
7. git add 06_가공/final_A + final_B + INDEX.md && commit "copy(1688): {id} 최종본 A/B" push.
8. Slack 보고: 처리 이미지 수 / A·B 각각 카피 적용 수 / 쿼터 소모(codex /status 전후) /
   문제 있던 이미지 명시.

## 금지 / 범위
- 카피 문구를 새로 창작하지 않는다 — text_extract.json 의 copy_a/copy_b 사용.
  (톤 수정이 필요하면 process-images 로 돌아가 카피를 고친다.)
- 원본(03_이미지)·clean/ 은 수정 안 함. final_A/, final_B/ 에만 쓴다.
- 쿼터: has_text 이미지 1장당 A/B 2회 생성. 많으면 규모 알리고 진행.

## 변경 관리
- 스킬 수정은 별도 커밋. 승인 범위 벗어난 개선은 BACKLOG 기록 후 별도 승인.
- 독립 리뷰는 최종 diff 기준 1회 원칙.
