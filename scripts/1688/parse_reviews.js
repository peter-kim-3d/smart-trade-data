#!/usr/bin/env node
/* =============================================================================
 * parse_reviews.js — 1688 리뷰(commentList) 파서 (범용/재사용)
 *
 * 리뷰는 mtop AJAX 전용이라 자동 서명이 불안정하다. 실전에서는 사람이 로그인
 * 브라우저에서 商品评价 섹션을 스크롤 → DevTools Network 필터 `rate` →
 * Response 를 통째로 복사해 reviews_raw.json 으로 저장한다.
 * 그 파일은 완전한 JSON 이 아니라 JSONP 껍데기이거나, `"model": {…` 같은
 * 조각(fragment)일 수 있다. 이 파서는 그 모든 경우에서 commentList 를 건져낸다.
 *
 * 사용법:
 *   node parse_reviews.js <reviews_raw.json> [--json]
 *     (기본) 사람이 읽는 마크다운 요약 출력
 *     --json  파싱된 리뷰 배열을 JSON 으로 출력
 *
 * 필드: content 본문, starLevel 별점, specInfo 규격, quantity 수량,
 *       raterUserNick 닉네임, buyerLevelTag 등급, gmtPublished(ms epoch),
 *       images, rateId. rateId(없으면 content 해시)로 중복 제거.
 *
 * ⚠️ 1688 리뷰 본문은 상투적(canned) 복붙 호평이 많아 본문 가치는 낮다.
 *    다만 메타데이터(구매 규격·수량)는 도매 단위 구매 확인용으로 유효하다.
 * ============================================================================= */
'use strict';
const fs = require('fs');
const crypto = require('crypto');

// 텍스트에서 `"<key>"` 뒤의 첫 배열을 괄호 균형 스캔으로 추출 (문자열 내부 무시)
function extractArrayAfter(s, key) {
  const idx = s.indexOf('"' + key + '"');
  if (idx < 0) return null;
  const b = s.indexOf('[', idx);
  if (b < 0) return null;
  let depth = 0, inStr = false, esc = false;
  for (let i = b; i < s.length; i++) {
    const c = s[i];
    if (inStr) { if (esc) esc = false; else if (c === '\\') esc = true; else if (c === '"') inStr = false; continue; }
    if (c === '"') inStr = true;
    else if (c === '[') depth++;
    else if (c === ']') { depth--; if (depth === 0) return s.slice(b, i + 1); }
  }
  return null;
}

// 완전 JSON, JSONP 래퍼, 조각 어느 것이든 commentList 를 배열로 반환
function extractCommentList(raw) {
  // 1) 완전 JSON 이면 재귀 탐색
  try {
    const obj = JSON.parse(raw);
    const found = deepFindArray(obj, 'commentList');
    if (found) return found;
  } catch (_) { /* fragment 일 수 있음 */ }
  // 2) JSONP 래퍼 벗기기: mtopjsonpN({...}) 형태
  const jm = raw.match(/^[^({]*\(([\s\S]*)\)\s*;?\s*$/);
  if (jm) {
    try {
      const obj = JSON.parse(jm[1]);
      const found = deepFindArray(obj, 'commentList');
      if (found) return found;
    } catch (_) { /* fall through */ }
  }
  // 3) 조각: 텍스트에서 commentList 배열만 괄호 균형 스캔
  const arrStr = extractArrayAfter(raw, 'commentList');
  if (arrStr) { try { return JSON.parse(arrStr); } catch (_) { /* noop */ } }
  return [];
}

function deepFindArray(obj, key, depth = 0) {
  if (!obj || typeof obj !== 'object' || depth > 8) return null;
  if (Array.isArray(obj[key])) return obj[key];
  for (const k of Object.keys(obj)) {
    const r = deepFindArray(obj[k], key, depth + 1);
    if (r) return r;
  }
  return null;
}

function normalize(list) {
  const seen = new Set();
  const out = [];
  for (const r of list) {
    const id = r.rateId != null ? String(r.rateId)
      : crypto.createHash('md5').update((r.content || '') + (r.gmtPublished || '')).digest('hex');
    if (seen.has(id)) continue;
    seen.add(id);
    out.push({
      rateId: id,
      content: r.content || '',
      starLevel: r.starLevel,
      specInfo: r.specInfo,
      quantity: r.quantity,
      unit: r.unit,
      raterUserNick: r.raterUserNick,
      buyerLevelTag: r.buyerLevelTag,
      gmtPublished: r.gmtPublished,
      date: r.gmtPublished ? new Date(Number(r.gmtPublished)).toISOString().slice(0, 10) : '',
      images: r.images || [],
    });
  }
  return out;
}

function main() {
  const file = process.argv[2];
  const asJson = process.argv.includes('--json');
  if (!file) { console.error('usage: node parse_reviews.js <reviews_raw.json> [--json]'); process.exit(2); }
  const raw = fs.readFileSync(file, 'utf8');
  const reviews = normalize(extractCommentList(raw));

  if (asJson) { process.stdout.write(JSON.stringify(reviews, null, 2)); return; }

  const L = [];
  L.push(`# 리뷰 (评价) — ${reviews.length}건 파싱`);
  L.push('');
  L.push('> ⚠️ 1688 리뷰 본문은 상투적(canned) 호평이 많음. 메타데이터(구매 규격·수량)가 실질 가치.');
  L.push('');
  L.push('| 별점 | 규격(specInfo) | 수량 | 구매자 | 작성일 | 본문 |');
  L.push('|---|---|---|---|---|---|');
  for (const r of reviews) {
    const body = (r.content || '').replace(/\s+/g, ' ').replace(/\|/g, '\\|').slice(0, 60);
    L.push(`| ${r.starLevel ?? ''} | ${(r.specInfo || '').replace(/\|/g, '\\|')} | ${r.quantity ?? ''} | ${r.raterUserNick || ''} | ${r.date} | ${body} |`);
  }
  process.stdout.write(L.join('\n'));
}

if (require.main === module) main();
module.exports = { extractCommentList, normalize };
