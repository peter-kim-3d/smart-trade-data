#!/usr/bin/env node
/* =============================================================================
 * parse_mobile.js — 1688 모바일(m.1688.com) 상품 페이지의 window.__INIT_DATA 파서
 *
 * 데스크톱(detail.1688.com)은 datacenter IP 를 차단하지만 모바일 엔드포인트는
 * 익명 GET 으로 전체 상품 JSON 을 내려준다:
 *   window.__INIT_DATA = { data:{<moduleId>:{componentType,data}}, globalData:{...}, ... }
 * 순수 JSON 이라 JSON.parse 로 파싱한다 (데스크톱과 달리 eval 불필요).
 *
 * 출력 스키마는 scripts/1688/parse_context.js 의 buildSummary() 와 동일 형태.
 * 모듈 ID 는 페이지마다 다를 수 있어 componentType 으로 모듈을 찾는다.
 *
 * 사용법:
 *   node parse_mobile.js parse   <page.html>                 # __INIT_DATA 를 JSON 으로 출력
 *   node parse_mobile.js summary <page.html|init.json>       # 정규화 요약 JSON (데스크톱 스키마)
 *   node parse_mobile.js get     <*.json> <dotted.path>      # 스칼라 값 하나 출력
 *   node parse_mobile.js images  <page.html|init.json>       # 메인 원본 이미지 URL 줄단위
 *   node parse_mobile.js skucsv  <page.html|init.json>       # SKU 가격표 CSV (동일 컬럼)
 *   node parse_mobile.js attrs   <page.html|init.json>       # 속성 마크다운 줄단위
 *   node parse_mobile.js productmd <page.html|init.json>     # 상품정보 원문 md
 *   node parse_mobile.js detail-html   <detail_response.js>  # 상세 content(HTML) 출력
 *   node parse_mobile.js detail-images <detail_response.js>  # 상세 원본 이미지 URL 줄단위
 * ============================================================================= */
'use strict';
const fs = require('fs');

/* ---- 썸네일 판별 / uniq / slugify — parse_context.js 와 동일 ---------------- */
function isThumb(u) {
  if (!u) return true;
  return /\.\d+x\d+(xz)?\.(jpg|jpeg|png|webp)/i.test(u)
      || /\.search\./i.test(u)
      || /\.summ\./i.test(u)
      || /_\.webp$/i.test(u);
}
function uniq(arr) { return [...new Set(arr)]; }
function slugify(title) {
  if (!title) return 'untitled';
  return String(title)
    .replace(/[\/\\:*?"<>|\r\n\t]+/g, '_')
    .replace(/\s+/g, '_')
    .replace(/[_]{2,}/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 60);
}

/* ---- window.__INIT_DATA 추출 (괄호 균형 스캔 → JSON.parse, eval 금지) ------- */
function extractInitData(html) {
  const anchor = html.indexOf('window.__INIT_DATA');
  if (anchor < 0) throw new Error('window.__INIT_DATA 를 HTML 에서 찾지 못함 (차단/빈 페이지?)');
  const eq = html.indexOf('=', anchor);
  const start = html.indexOf('{', eq);
  if (start < 0) throw new Error('__INIT_DATA 객체 시작 { 을 찾지 못함');
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
  if (end < 0) throw new Error('__INIT_DATA 객체의 괄호 균형이 맞지 않음');
  return JSON.parse(html.slice(start, end + 1)); // 순수 JSON — eval 불필요
}

/* ---- 상세페이지 JSONP 응답 파싱 — parse_context.js parseDetail 와 동일 ------- */
function parseDetail(js) {
  const s = js.indexOf('{');
  const e = js.lastIndexOf('}');
  if (s < 0 || e < 0) throw new Error('상세페이지 응답에서 객체를 찾지 못함');
  const raw = js.slice(s, e + 1);
  try { return JSON.parse(raw); } // 대개 순수 JSON: var offer_details={"content":"..."}
  catch (_) {
    // eslint-disable-next-line no-eval
    return eval('(' + raw + ')'); // JS 리터럴 폴백 (데스크톱 파서와 동일 처리)
  }
}

/* ---- componentType 으로 모듈 data 찾기 (모듈 ID 는 페이지마다 다름) ---------- */
function moduleData(init, typeSuffix) {
  const d = init.data || {};
  for (const k of Object.keys(d)) {
    const m = d[k];
    if (m && typeof m.componentType === 'string' && m.componentType.endsWith(typeSuffix)) {
      return m.data || {};
    }
  }
  return {};
}

/* ---- 정규화 요약 빌더 — 데스크톱 buildSummary 와 동일 스키마 ----------------- */
function buildSummary(init) {
  const G = init.globalData || {};
  const temp = G.tempModel || {};
  const base = G.offerBaseInfo || {};
  const orderParam = (G.orderParamModel && G.orderParamModel.orderParam) || {};
  const skuParam = orderParam.skuParam || {};

  const mainPic  = moduleData(init, 'cmod-od-wap-main-pic');       // 이미지/동영상/sku이미지
  const titleMod = moduleData(init, 'cmod-od-wap-offer-title');    // 제목/판매수
  const priceMod = moduleData(init, 'cmod-od-wap-offer-price');    // 가격/단위
  const attrMod  = moduleData(init, 'cmod-od-wap-offer-attribute');// 속성 propsList
  const logiMod  = moduleData(init, 'cmod-od-wap-offer-logistics');// 발송지/물류/무게
  const descMod  = moduleData(init, 'cmod-odw-basic-description'); // 상세페이지 URL
  const footMod  = moduleData(init, 'cmod-odw-basic-footer');      // 판매자/단위 폴백

  const offerInfo = mainPic.offerInfoModel || {};

  // 가격 계층: skuRangePrices (수량구간 가격사다리, {price,beginAmount} — 데스크톱
  // currentPrices 와 동일 형태). priceModel.currentPrices 는 1구간만 오는 경우가 있어
  // skuRangePrices 를 우선한다.
  const rangePrices = Array.isArray(skuParam.skuRangePrices) ? skuParam.skuRangePrices : [];
  const pmPrices = (priceMod.priceModel && Array.isArray(priceMod.priceModel.currentPrices))
    ? priceMod.priceModel.currentPrices : [];
  const tiers = rangePrices.length >= pmPrices.length ? rangePrices : pmPrices;
  const nums = tiers.map(t => parseFloat(t.price)).filter(n => !isNaN(n));
  const priceMin = nums.length ? Math.min(...nums).toFixed(2) : null;
  const priceMax = nums.length ? Math.max(...nums).toFixed(2) : null;

  // 메인 이미지: offerImgList(주도판) + skuImages(색상별 원본) — 원본만, uniq
  const skuImages = Array.isArray(mainPic.skuImages) ? mainPic.skuImages : [];
  const images = uniq([]
    .concat(Array.isArray(mainPic.offerImgList) ? mainPic.offerImgList : [])
    .concat(skuImages.map(s => s.imgUrl))
    .map(u => (u || '').trim())
    .filter(u => /^https?:\/\//.test(u) && !isThumb(u)));

  // SKU: 모바일 초기 페이로드에는 skuId 별 스펙/개별가/재고 매핑이 없다 (SKU 패널은
  // 로그인/서명 mtop 으로 지연로딩). skuWeight 의 키가 skuId 목록이므로 행은 만들되
  // specAttrs/price/canBookCount 는 null 로 둔다. (skuImages 의 색상명 목록은 있으나
  // skuId ↔ 색상 결합근거가 페이로드에 없어 임의 결합하지 않는다.)
  const skuWeight = logiMod.skuWeight || {};
  const skus = Object.keys(skuWeight).map(id => ({
    skuId: /^\d+$/.test(id) ? Number(id) : id,
    specId: null,
    specAttrs: null,
    price: null,
    discountPrice: null,
    canBookCount: null,
  }));

  // 속성: propsList 는 {name,value(콤마결합 문자열)} — 데스크톱 values 배열로 정규화
  const attributes = (Array.isArray(attrMod.propsList) ? attrMod.propsList : [])
    .map(a => ({ name: a.name, values: a.value == null ? [] : String(a.value).split(',').map(s => s.trim()).filter(Boolean) }));

  const title = titleMod.title || offerInfo.title || footMod.offerTitle || temp.offerTitle;

  return {
    offerId: base.offerId || mainPic.offerId || (temp.offerId ? Number(temp.offerId) : undefined),
    title,
    slug: slugify(title),
    saleNum: titleMod.selledNumber != null ? titleMod.selledNumber : orderParam.saledCount,
    unit: priceMod.unit || footMod.offerUnit || temp.offerUnit,
    price: {
      display: offerInfo.price || null,       // 예: "5.00-4.50"
      min: priceMin, max: priceMax,
      moq: orderParam.beginNum != null ? orderParam.beginNum : null,
      tiers,
    },
    skus,
    attributes,
    images,
    video: mainPic.videoUrl ? {
      videoUrl: mainPic.videoUrl,
      coverUrl: null,                          // 모바일 페이로드에 커버 URL 없음
      videoId: mainPic.videoId != null ? mainPic.videoId : null,
      title: null,                             // 모바일 페이로드에 비디오 제목 없음
    } : null,
    detailUrl: descMod.detailUrl || null,
    leafCategoryId: temp.postCategoryId != null ? Number(temp.postCategoryId) : null,
    shipping: {
      location: logiMod.location || null,
      logisticsText: logiMod.deliveryLimitTxt || logiMod.logistics || null,
      unitWeight: logiMod.unitWeight != null ? logiMod.unitWeight : null,
    },
    seller: {
      companyName: temp.companyName || (G.shareModel && G.shareModel.companyName) || null,
      authCompanyName: null,                   // 모바일 페이로드에 없음
      cardType: null,                          // 모바일 페이로드에 없음
      byrRepeatRate3m: null,                   // 모바일 페이로드에 없음
      sellerMemberId: base.sellerMemberId || temp.sellerMemberId || footMod.sellerMemberId || null,
      sellerUserId: base.sellerUserId != null ? base.sellerUserId
                  : (temp.sellerUserId != null ? Number(temp.sellerUserId) : null),
      shopUrl: temp.winportUrl || footMod.winportUrl || null,
      winportUrl: footMod.winportUrl || temp.winportUrl || null,
    },
    rate: {                                    // 평가 데이터는 모바일 초기 페이로드에 없음(지연로딩)
      goodRates: null,
      goodsGrade: null,
      reviewCount: null,
      impressionTags: [],
    },
  };
}

/* ---- 입력 파일 로드 (html/json 자동판별) ----------------------------------- */
function loadInit(file) {
  const txt = fs.readFileSync(file, 'utf8');
  const trimmed = txt.trimStart();
  if (trimmed[0] === '{' || trimmed[0] === '[') {
    const obj = JSON.parse(txt);
    if (obj.globalData || obj.data) return obj;          // 이미 __INIT_DATA
    if (obj.offerId && obj.skus) return { __summary: obj }; // 이미 summary
    return obj;
  }
  return extractInitData(txt); // HTML
}
function loadSummary(file) {
  const c = loadInit(file);
  return c.__summary ? c.__summary : buildSummary(c);
}

/* ---- dotted path / csv escape — parse_context.js 와 동일 -------------------- */
function resolvePath(obj, path) {
  const parts = path.replace(/\[(\d+)\]/g, '.$1').split('.').filter(Boolean);
  let cur = obj;
  for (const p of parts) { if (cur == null) return undefined; cur = cur[p]; }
  return cur;
}
function csvEscape(v) {
  const s = v == null ? '' : String(v);
  return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

function main() {
  const [mode, file, arg] = process.argv.slice(2);
  if (!mode || !file) {
    console.error('usage: node parse_mobile.js <parse|summary|get|images|skucsv|attrs|productmd|detail-html|detail-images> <file> [path]');
    process.exit(2);
  }
  switch (mode) {
    case 'parse': {
      process.stdout.write(JSON.stringify(extractInitData(fs.readFileSync(file, 'utf8')), null, 2));
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
      process.stdout.write(loadSummary(file).images.join('\n') + '\n');
      break;
    }
    case 'skucsv': {
      const s = loadSummary(file);
      const rows = ['skuId,specAttrs,price,discountPrice,canBookCount'];
      for (const k of s.skus) {
        rows.push([k.skuId, csvEscape(k.specAttrs), k.price, k.discountPrice, k.canBookCount].join(','));
      }
      process.stdout.write(rows.join('\n') + '\n');
      break;
    }
    case 'attrs': {
      const s = loadSummary(file);
      process.stdout.write(s.attributes.map(a => `- ${a.name}: ${(a.values || []).join(' / ')}`).join('\n') + '\n');
      break;
    }
    case 'productmd': {
      const s = loadSummary(file);
      const url = `https://m.1688.com/offer/${s.offerId}.html`;
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
      L.push(`- **sellerMemberId**: ${s.seller.sellerMemberId || ''}`);
      L.push(`- **shopUrl**: ${s.seller.shopUrl || ''}`);
      L.push(`- **winportUrl**: ${s.seller.winportUrl || ''}`);
      L.push('');
      L.push('## 상품 속성 (属性)');
      L.push('');
      for (const a of s.attributes) L.push(`- **${a.name}**: ${(a.values || []).join(' / ')}`);
      L.push('');
      L.push('## SKU (规格)');
      L.push('');
      L.push('※ 모바일 익명 페이로드에는 skuId 별 스펙/개별가/재고가 없다 (지연로딩). 수량구간 가격은 아래 tiers 참조.');
      L.push('');
      L.push('| skuId | 规格(specAttrs) | 价格 | 折后价 | 재고(canBookCount) |');
      L.push('|---|---|---|---|---|');
      for (const k of s.skus) L.push(`| ${k.skuId} | ${(k.specAttrs || '').replace(/\|/g, '\\|')} | ${k.price || ''} | ${k.discountPrice || ''} | ${k.canBookCount != null ? k.canBookCount : ''} |`);
      L.push('');
      L.push('## 수량구간 가격 (阶梯价)');
      L.push('');
      L.push('| 구간시작수량(beginAmount) | 가격(price) |');
      L.push('|---|---|');
      for (const t of s.price.tiers) L.push(`| ${t.beginAmount} | ${t.price} |`);
      L.push('');
      if (s.video) {
        L.push('## 동영상 (视频)');
        L.push('');
        L.push(`- videoUrl: ${s.video.videoUrl || ''}`);
        L.push(`- videoId: ${s.video.videoId || ''}`);
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
      process.stdout.write(uniq(urls).join('\n') + '\n');
      break;
    }
    default:
      console.error('알 수 없는 mode: ' + mode);
      process.exit(2);
  }
}

if (require.main === module) main();

module.exports = {
  extractInitData, parseDetail, buildSummary, slugify, isThumb, loadInit, loadSummary, moduleData,
};
