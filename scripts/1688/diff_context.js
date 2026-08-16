#!/usr/bin/env node
/* =============================================================================
 * diff_context.js — 익명 vs 로그인 context 의미차 리포트 (노이즈 필터링)
 *
 * 두 context JSON(익명/로그인)을 재귀 deep-diff 한다. 로그인으로 실제 추가되는
 * 데이터(도매/분소가·회원가·판매자 연락처 등)가 있는지 확인하는 용도.
 * 요청별 추적 ID·시간차 집계갱신 같은 "무의미한 차이"는 필터링한다.
 *
 * 사용법:
 *   node diff_context.js <anon_context.json> <authed_context.json>
 *   node diff_context.js <anon.json> <authed.json> --all   # 노이즈 포함 전체
 *
 * 입력은 parse_context.js 로 뽑은 context JSON (result.data 포함) 이어야 한다.
 * 로그인 HTML 밖에 없다면 먼저: node parse_context.js parse detail_authed.html > authed_context.json
 * ============================================================================= */
'use strict';
const fs = require('fs');

// 무시할 키(부분일치): 추적 ID / 시간차 집계 / 내부 태그 순서 등
const NOISE_KEYS = [
  'ipvId', 'exposeArgs', 'trackInfo', 'offerMemberTags', 'rn', 'traceId', 'eurl',
  'expectSendHour', 'saleNum', 'newSaleCount', 'saleCountDate', 'byrRepeatRate3m',
  'commonTagNodeList', 'impressionTagNodeList', 'goodRates', 'canBookCount',
  'canBookedAmountOriginal', 'systemParam', 'renderData', 'scrollInfo', 'timestamp',
  't', '_tb_token_', 'sign',
];
function isNoise(pathParts) {
  return pathParts.some(p => NOISE_KEYS.includes(p));
}

function diff(a, b, path, out) {
  if (a === b) return;
  const ta = typeof a, tb = typeof b;
  if (a === null || b === null || ta !== 'object' || tb !== 'object') {
    out.push({ path: path.join('.'), anon: preview(a), authed: preview(b) });
    return;
  }
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const k of keys) {
    const np = path.concat(k);
    if (isNoise(np) && !includeAll) continue;
    if (!(k in a)) { out.push({ path: np.join('.'), anon: '(없음)', authed: preview(b[k]) }); continue; }
    if (!(k in b)) { out.push({ path: np.join('.'), anon: preview(a[k]), authed: '(없음)' }); continue; }
    diff(a[k], b[k], np, out);
  }
}
function preview(v) {
  if (v === undefined) return '(undefined)';
  const s = typeof v === 'object' ? JSON.stringify(v) : String(v);
  return s.length > 80 ? s.slice(0, 80) + '…' : s;
}

let includeAll = false;
function main() {
  const args = process.argv.slice(2);
  includeAll = args.includes('--all');
  const files = args.filter(a => !a.startsWith('--'));
  if (files.length < 2) { console.error('usage: node diff_context.js <anon.json> <authed.json> [--all]'); process.exit(2); }
  const A = JSON.parse(fs.readFileSync(files[0], 'utf8'));
  const B = JSON.parse(fs.readFileSync(files[1], 'utf8'));
  // result.data 우선 비교(있으면), 없으면 전체
  const a = (A.result && A.result.data) || A;
  const b = (B.result && B.result.data) || B;
  const out = [];
  diff(a, b, [], out);

  console.log(`# 익명 vs 로그인 context diff (노이즈 ${includeAll ? '포함' : '필터링'})`);
  console.log('');
  if (out.length === 0) {
    console.log('의미 있는 차이 없음 — 로그인 전용 데이터가 상세페이지 context 에 없음.');
    console.log('(가격/속성이 익명과 동일. 도매/분소가·회원가 미지원 상품일 가능성.)');
    return;
  }
  console.log(`차이 ${out.length}건:`);
  console.log('');
  console.log('| path | 익명 | 로그인 |');
  console.log('|---|---|---|');
  for (const d of out.slice(0, 200)) {
    console.log(`| ${d.path} | ${String(d.anon).replace(/\|/g, '\\|')} | ${String(d.authed).replace(/\|/g, '\\|')} |`);
  }
  if (out.length > 200) console.log(`\n… 외 ${out.length - 200}건 (--all 로 전체 확인)`);
}
main();
