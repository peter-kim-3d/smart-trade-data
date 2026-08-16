#!/usr/bin/env node
/* =============================================================================
 * parse_context.js — 1688 상품 페이지의 window.context 임베디드 데이터 파서 (범용)
 *
 * 1688 상품 상세 HTML 안에는 아래 형태로 전체 상품 데이터가 박혀 있다:
 *   window.context = (function(b,d){...})(window.contextPath, { ...거대한 JS객체... })
 * 이 2번째 인자 객체가 상품 데이터 전체다. 순수 JSON이 아니라 JS 객체 리터럴이라
 * Python json.loads 로는 파싱 못 한다 → Node 로 괄호 균형 스캔 후 eval 한다.
 *
 * 사용법:
 *   node parse_context.js parse   <page.html>              # 전체 context 를 JSON 으로 출력
 *   node parse_context.js summary <page.html|context.json> # 정규화 요약 JSON 출력
 *   node parse_context.js get     <*.json> <dotted.path>   # 스칼라 값 하나 출력 (예: skus[0].price)
 *   node parse_context.js images  <page.html|context.json> # 메인 원본 이미지 URL(썸네일 제외) 줄단위
 *   node parse_context.js skucsv  <page.html|context.json> # SKU 가격표 CSV
 *   node parse_context.js attrs   <page.html|context.json> # 상품 속성 마크다운(名: 값) 줄단위
 *   node parse_context.js detail-html   <detail_response.js>  # 상세페이지 content(HTML) 출력
 *   node parse_context.js detail-images <detail_response.js>  # 상세페이지 내 원본 이미지 URL 줄단위
 *
 * 모듈로도 사용 가능:  const { extractContext, buildSummary } = require('./parse_context.js')
 * ============================================================================= */
'use strict';
const fs = require('fs');

/* ---- 썸네일/변형 이미지 판별 (원본만 남기기 위함) --------------------------- */
// 1688/alicdn 원본은 보통 `..._!!..-0-cib.jpg` 형태. 아래 변형 접미사는 제외한다.
function isThumb(u) {
  if (!u) return true;
  return /\.\d+x\d+(xz)?\.(jpg|jpeg|png|webp)/i.test(u) // .220x220.jpg .310x310.jpg 등
      || /\.search\./i.test(u)
      || /\.summ\./i.test(u)
      || /_\.webp$/i.test(u);
}
function uniq(arr) { return [...new Set(arr)]; }

/* ---- window.context 추출 (괄호 균형 스캔, 문자열 내부 무시) ----------------- */
function extractContext(html) {
  let anchor = html.indexOf('window.contextPath,');
  if (anchor < 0) {
    // 시그니처가 다른 페이지 폴백
    anchor = html.indexOf('window.context');
    if (anchor < 0) throw new Error('window.context 를 HTML 에서 찾지 못함 (빈 페이지? WebFetch 로 받은 것 아닌지 확인)');
  }
  const start = html.indexOf('{', anchor);
  if (start < 0) throw new Error('context 객체 리터럴 시작 { 을 찾지 못함');
  let depth = 0, inStr = false, quote = '', esc = false, end = -1;
  for (let i = start; i < html.length; i++) {
    const c = html[i];
    if (inStr) {
      if (esc) esc = false;
      else if (c === '\\') esc = true;
      else if (c === quote) inStr = false;
      continue;
    }
    if (c === '"' || c === "'") { inStr = true; quote = c; }
    else if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) { end = i; break; } }
  }
  if (end < 0) throw new Error('context 객체 리터럴의 괄호 균형이 맞지 않음');
  const raw = html.slice(start, end + 1);
  // 캡처한 자기 데이터에 대한 eval — 방법론상 JS 객체 리터럴이라 JSON.parse 불가
  // eslint-disable-next-line no-eval
  return eval('(' + raw + ')');
}

/* ---- 상세페이지 JSONP 응답 파싱: var offer_details={"content":"<html>"} ------ */
function parseDetail(js) {
  const s = js.indexOf('{');
  const e = js.lastIndexOf('}');
  if (s < 0 || e < 0) throw new Error('상세페이지 응답에서 객체를 찾지 못함');
  // eslint-disable-next-line no-eval
  return eval('(' + js.slice(s, e + 1) + ')'); // { content: "<html>..." }
}

/* ---- 깊이 우선 첫 매칭 키 값 찾기 (판매자 식별자 등 위치가 유동적인 필드용) ---- */
function deepFind(obj, key, depth = 0) {
  if (!obj || typeof obj !== 'object' || depth > 8) return undefined;
  if (Object.prototype.hasOwnProperty.call(obj, key) && obj[key] != null && typeof obj[key] !== 'object') return obj[key];
  for (const k of Object.keys(obj)) {
    const r = deepFind(obj[k], key, depth + 1);
    if (r !== undefined) return r;
  }
  return undefined;
}

/* ---- 파일명 안전 슬러그 (CJK 유지, 구분자/공백 → _) ------------------------- */
function slugify(title) {
  if (!title) return 'untitled';
  return String(title)
    .replace(/[\/\\:*?"<>|\r\n\t]+/g, '_') // 파일시스템 금지문자
    .replace(/\s+/g, '_')
    .replace(/[_]{2,}/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 60);
}

/* ---- 정규화 요약 빌더 (확인된 필드 경로 기반) ------------------------------ */
function buildSummary(ctx) {
  const D = (ctx.result && ctx.result.data) || {};
  const pt = (D.productTitle && D.productTitle.fields) || {};
  const gf = (D.gallery && D.gallery.fields) || {};
  const mp = (D.mainPrice && D.mainPrice.fields) || {};
  const fp = (mp.finalPriceModel && mp.finalPriceModel.tradeWithoutPromotion) || {};
  const pmModel = mp.priceModel || {};
  const df = (D.description && D.description.fields) || {};
  const sf = (D.shippingServices && D.shippingServices.fields) || {};
  const shop = pt.shopInfo || {};
  const ri = pt.rateInfo || {};
  const cpv = gf.CpvEnhance || {};

  // mainImage 는 콤마로 이어붙인 문자열인 경우가 있어 분리한다.
  const mainImgs = typeof gf.mainImage === 'string' ? gf.mainImage.split(',')
                 : Array.isArray(gf.mainImage) ? gf.mainImage : [];
  const images = uniq([]
    .concat(Array.isArray(gf.offerImgList) ? gf.offerImgList : [])
    .concat(mainImgs)
    .map(u => (u || '').trim())
    .filter(u => /^https?:\/\//.test(u) && !isThumb(u)));

  const attributes = []
    .concat(Array.isArray(cpv.decisionCpv) ? cpv.decisionCpv : [])
    .concat(Array.isArray(cpv.normalCpv) ? cpv.normalCpv : [])
    .map(a => ({ name: a.name, values: a.values || [] }));

  const skus = (Array.isArray(fp.skuMapOriginal) ? fp.skuMapOriginal : []).map(s => ({
    skuId: s.skuId, specId: s.specId, specAttrs: s.specAttrs,
    price: s.price, discountPrice: s.discountPrice, canBookCount: s.canBookCount,
  }));

  const commonTags = Array.isArray(ri.commonTagNodeList) ? ri.commonTagNodeList : [];
  const totalTag = commonTags.find(t => t.name === '全部') || commonTags[0] || {};

  return {
    offerId: gf.offerId || deepFind(D, 'offerId'),
    title: pt.title || gf.subject,
    slug: slugify(pt.title || gf.subject),
    saleNum: pt.saleNum,
    unit: mp.unit || fp.unit || pmModel.unit,
    price: {
      display: fp.offerPriceDisplay,
      min: fp.offerMinPrice, max: fp.offerMaxPrice,
      moq: fp.offerBeginAmount,
      tiers: Array.isArray(pmModel.currentPrices) ? pmModel.currentPrices : [],
    },
    skus,
    attributes,
    images,
    video: gf.video ? {
      videoUrl: gf.video.videoUrl, coverUrl: gf.video.coverUrl,
      videoId: gf.video.videoId, title: gf.video.title,
    } : null,
    detailUrl: df.detailUrl,
    leafCategoryId: df.leafCategoryId,
    shipping: {
      location: sf.location,
      logisticsText: sf.freightInfo && sf.freightInfo.logisticsText,
      unitWeight: sf.unitWeight,
    },
    seller: {
      companyName: shop.companyName || shop.authCompanyName,
      authCompanyName: shop.authCompanyName,
      cardType: shop.cardType,
      byrRepeatRate3m: shop.byrRepeatRate3m,
      sellerMemberId: deepFind(D, 'sellerMemberId'),
      sellerUserId: deepFind(D, 'sellerUserId'),
      shopUrl: deepFind(D, 'sellerWinportUrl') || deepFind(D, 'indexUrl') || deepFind(D, 'defaultUrl'),
      winportUrl: deepFind(D, 'winportUrl'),
    },
    rate: {
      goodRates: ri.goodRates,
      goodsGrade: ri.goodsGrade,
      reviewCount: totalTag.count,
      impressionTags: (Array.isArray(ri.impressionTagNodeList) ? ri.impressionTagNodeList : [])
        .map(t => ({ name: t.name, count: t.count })),
    },
  };
}

/* ---- 입력 파일을 raw context 로 로드 (html/json 자동판별) ------------------- */
function loadContext(file) {
  const txt = fs.readFileSync(file, 'utf8');
  const trimmed = txt.trimStart();
  if (trimmed[0] === '{' || trimmed[0] === '[') {
    const obj = JSON.parse(txt);
    if (obj.result && obj.result.data) return obj;    // 이미 raw context
    if (obj.offerId && obj.skus) return { __summary: obj }; // 이미 summary
    return obj;
  }
  return extractContext(txt); // HTML
}
function loadSummary(file) {
  const c = loadContext(file);
  return c.__summary ? c.__summary : buildSummary(c);
}

/* ---- dotted path 리졸버 (skus[0].price 형태 지원) -------------------------- */
function resolvePath(obj, path) {
  const parts = path.replace(/\[(\d+)\]/g, '.$1').split('.').filter(Boolean);
  let cur = obj;
  for (const p of parts) { if (cur == null) return undefined; cur = cur[p]; }
  return cur;
}

/* ---- CLI ------------------------------------------------------------------ */
function csvEscape(v) {
  const s = v == null ? '' : String(v);
  return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

function main() {
  const [mode, file, arg] = process.argv.slice(2);
  if (!mode || !file) {
    console.error('usage: node parse_context.js <parse|summary|get|images|skucsv|attrs|detail-html|detail-images> <file> [path]');
    process.exit(2);
  }
  switch (mode) {
    case 'parse': {
      const ctx = extractContext(fs.readFileSync(file, 'utf8'));
      process.stdout.write(JSON.stringify(ctx, null, 2));
      break;
    }
    case 'summary': {
      process.stdout.write(JSON.stringify(loadSummary(file), null, 2));
      break;
    }
    case 'get': {
      const obj = JSON.parse(fs.readFileSync(file, 'utf8'));
      const v = resolvePath(obj, arg || '');
      process.stdout.write(v == null ? '' : (typeof v === 'object' ? JSON.stringify(v) : String(v)));
      break;
    }
    case 'images': {
      process.stdout.write(loadSummary(file).images.join('\n')+'\n');
      break;
    }
    case 'skucsv': {
      const s = loadSummary(file);
      const rows = ['skuId,specAttrs,price,discountPrice,canBookCount'];
      for (const k of s.skus) {
        rows.push([k.skuId, csvEscape(k.specAttrs), k.price, k.discountPrice, k.canBookCount].join(','));
      }
      process.stdout.write(rows.join('\n')+'\n');
      break;
    }
    case 'attrs': {
      const s = loadSummary(file);
      process.stdout.write(s.attributes.map(a => `- ${a.name}: ${(a.values || []).join(' / ')}`).join('\n')+'\n');
      break;
    }
    case 'productmd': {
      const s = loadSummary(file);
      const url = `https://detail.1688.com/offer/${s.offerId}.html`;
      const L = [];
      L.push(`# 상품 정보 (원문) — ${s.offerId}`);
      L.push('');
      L.push(`- **상품명(原文)**: ${s.title || ''}`);
      L.push(`- **offerId**: ${s.offerId}`);
      L.push(`- **URL**: ${url}`);
      L.push(`- **가격(价格)**: ${s.price.display || ''}  (最低 ${s.price.min || '?'} ~ 最高 ${s.price.max || '?'})`);
      L.push(`- **판매단위(单位)**: ${s.unit || ''}`);
      L.push(`- **최소주문수량 MOQ(起订量)**: ${s.price.moq != null ? s.price.moq : ''}`);
      L.push(`- **판매량(销量)**: ${s.saleNum || ''}`);
      L.push(`- **발송지(发货地)**: ${s.shipping.location || ''}`);
      L.push(`- **물류(物流)**: ${s.shipping.logisticsText || ''}`);
      L.push(`- **개당 무게(单位重量, kg)**: ${s.shipping.unitWeight != null ? s.shipping.unitWeight : ''}`);
      L.push(`- **카테고리ID(叶子类目)**: ${s.leafCategoryId != null ? s.leafCategoryId : ''}`);
      L.push('');
      L.push('## 판매자/회사 (卖家/公司)');
      L.push('');
      L.push(`- **회사명(公司名)**: ${s.seller.companyName || ''}`);
      L.push(`- **유형(卡片类型)**: ${s.seller.cardType || ''}`);
      L.push(`- **최근3개월 재구매율(复购率)**: ${s.seller.byrRepeatRate3m || ''}`);
      L.push(`- **sellerMemberId**: ${s.seller.sellerMemberId || ''}`);
      L.push(`- **shopUrl**: ${s.seller.shopUrl || ''}`);
      L.push(`- **winportUrl**: ${s.seller.winportUrl || ''}`);
      L.push('');
      L.push('## 평가 집계 (评价)');
      L.push('');
      L.push(`- **별점(评分)**: ${s.rate.goodsGrade != null ? s.rate.goodsGrade : ''} / 5`);
      L.push(`- **긍정률(好评率)**: ${s.rate.goodRates != null ? s.rate.goodRates + '%' : ''}`);
      L.push(`- **리뷰 수(评价数)**: ${s.rate.reviewCount != null ? s.rate.reviewCount : ''}`);
      if (s.rate.impressionTags && s.rate.impressionTags.length) {
        L.push(`- **인상 태그(印象标签)**: ${s.rate.impressionTags.slice(0, 10).map(t => `${t.name}(${t.count})`).join(', ')}`);
      }
      L.push('');
      L.push('## 상품 속성 (属性 / CpvEnhance)');
      L.push('');
      for (const a of s.attributes) L.push(`- **${a.name}**: ${(a.values || []).join(' / ')}`);
      L.push('');
      L.push('## SKU (规格)');
      L.push('');
      L.push('| skuId | 规格(specAttrs) | 价格 | 折后价 | 재고(canBookCount) |');
      L.push('|---|---|---|---|---|');
      for (const k of s.skus) L.push(`| ${k.skuId} | ${(k.specAttrs || '').replace(/\|/g, '\\|')} | ${k.price || ''} | ${k.discountPrice || ''} | ${k.canBookCount != null ? k.canBookCount : ''} |`);
      L.push('');
      if (s.video) {
        L.push('## 동영상 (视频)');
        L.push('');
        L.push(`- videoUrl: ${s.video.videoUrl || ''}`);
        L.push(`- coverUrl: ${s.video.coverUrl || ''}`);
      }
      L.push('');
      process.stdout.write(L.join('\n'));
      break;
    }
    case 'detail-html': {
      const d = parseDetail(fs.readFileSync(file, 'utf8'));
      process.stdout.write(d.content || '');
      break;
    }
    case 'detail-images': {
      const d = parseDetail(fs.readFileSync(file, 'utf8'));
      const html = d.content || '';
      const urls = [];
      const re = /<img[^>]+src=["']([^"']+)["']/gi;
      let m;
      while ((m = re.exec(html))) if (!isThumb(m[1])) urls.push(m[1]);
      process.stdout.write(uniq(urls).join('\n')+'\n');
      break;
    }
    default:
      console.error('알 수 없는 mode: ' + mode);
      process.exit(2);
  }
}

if (require.main === module) main();

module.exports = {
  extractContext, parseDetail, buildSummary, slugify, isThumb, deepFind, loadContext, loadSummary,
};
