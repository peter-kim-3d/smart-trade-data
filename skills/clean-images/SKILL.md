---
name: clean-images
description: 상품 이미지에서 중국어 텍스트를 제거한 클린 이미지 생성 (gpt-image 편집)
---

# clean-images

## 작업 위치
smart-trade-data repo 루트. 경로 모르면 이 SKILL.md 위치를 realpath로 확인해 루트 찾기.

## 언제 사용
process 채널에서 "클린"/"clean"/"이미지 정리" 요청 + offer id일 때.
전제: 해당 상품에 06_가공/text_extract.json 이 이미 있어야 함(process-images 먼저).
없으면 "텍스트 추출 먼저 필요" 보고 후 중단.

## 접근 원칙
중국어 제거는 결정론 도구(OpenCV inpaint)로는 복잡 배경에서 번짐이 심해 부적합.
Codex CLI 내장 image_generation(referenced_image_paths)으로 편집한다.
ChatGPT 구독으로 작동하며 별도 API 키 불필요. 마스크 파라미터는 없음(전체 재생성).
크기·크롭이 원본과 달라질 수 있으나 '준비 재료'로는 허용됨(사용자 승인 사항).

## 절차 (offer id 하나당)
1. cd 리포루트 && git pull --rebase
2. text_extract.json 을 읽어 이미지 목록과 has_text 확인.
3. 06_가공/clean/ 디렉토리 생성.
4. 각 이미지 처리:
   - has_text:true → Codex image_generation으로 편집:
     지시="이미지의 모든 중국어 텍스트를 자연스럽게 제거하고 그 자리를 주변 배경/재질과
     같게 채워라. 제품·구도·색감은 최대한 원본과 동일하게 유지하라."
     결과를 06_가공/clean/{원본파일명} 으로 저장.
   - has_text:false → 원본을 06_가공/clean/{파일명} 으로 그대로 복사(편집 안 함, 쿼터 절약).
   → 결과적으로 clean/ 에는 전체 이미지 세트가 다 있어야 함.
5. 각 편집 결과를 view로 다시 확인: 중국어가 남아있지 않은지, 제품이 크게 망가지지 않았는지.
   중국어 잔존이나 심한 왜곡이면 1회 재시도. 그래도 문제면 그 파일 보고하고 계속.
6. INDEX.md 의 해당 상품에 클린 완료 표시(가능하면 별도 열 또는 비고).
7. git add 06_가공/clean + INDEX.md && commit "clean(1688): {id} 클린이미지" push.
8. Slack 보고: 처리 이미지 수 / 편집한 수 vs 복사한 수 / 쿼터 소모(codex /status 전후) /
   문제 있던 이미지 있으면 명시.

## 금지 / 범위
- 카피 얹기(한국어)는 이 스킬 범위 밖 (apply-copy 담당).
- 원본(03_이미지)은 절대 수정/삭제 안 함. clean/ 에만 쓴다.
- 쿼터 관리: 한 번에 처리할 이미지가 아주 많으면(수십 장) 사용자에게 규모 알리고 진행.

## 변경 관리
- 스킬 수정은 별도 커밋. 승인 범위 벗어난 개선은 BACKLOG 기록 후 별도 승인.
- 독립 리뷰는 최종 diff 기준 1회 원칙.
