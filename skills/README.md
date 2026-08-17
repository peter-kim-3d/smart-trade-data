# skills/ — 에이전트 스킬 (버전관리 원본)

이 폴더의 스킬들은 **이 repo 가 원본(single source of truth)** 이다. Hermes(또는 다른 에이전트 런타임)에는 **심링크로 연결**해 쓴다 — 런타임에서 직접 수정하지 말고 항상 이 repo 에서 고쳐 커밋한다.

## Hermes 연결

각 스킬을 심링크로 건다:

```bash
ln -s {repo}/skills/{이름} ~/.hermes/skills/{이름}
# 예
ln -s /home/coder/workspaces/smart-trade-data/skills/collect-1688 ~/.hermes/skills/collect-1688
```

## 변경 관리

- 스킬 수정은 **별도 커밋**으로 한다: `tune(collect): …` 처럼 어떤 스킬을 왜 고쳤는지 남긴다.
- 커밋 전에 각 스킬 문서(`SKILL.md`)의 **변경 관리 게이트(셀프테스트 등)를 통과**한다.

## 현재 스킬

| 스킬 | 단계 | 상태 |
|---|---|---|
| `collect-1688/` | 수집 | 사용 중 |
| `process-product/` | 가공 | **미작성** — `references/` 리버스엔지니어링 후 에이전트가 작성 예정 |
| `generate-page/` | 생성 | **미작성** — `references/` 리버스엔지니어링 후 에이전트가 작성 예정 |

> `process-product`·`generate-page` 는 **지금 만들지 않는다.** `references/detail-pages/` 의 실제 사례를 분석한 뒤 그 지식으로 작성한다.
