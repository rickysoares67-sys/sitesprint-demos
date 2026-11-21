(function () {
'use strict';
var E = SREngine, D = SITE, WILD = E.WILD, SCAT = E.SCAT, COIN = E.COIN;
var $ = function (id) { return document.getElementById(id); };
var LB = [0.05, 0.10, 0.20, 0.50, 1, 2, 5];
var BASE = window.SPINRUSH_ASSET_BASE || '';   // '' on Claude (files beside the page); '/' on the ChatGPT site (/static/assets)
function A(p) { return BASE + String(p).replace(/^\//, ''); }
var COMMON = A('static/assets/art52/common.webp'), PIR = A('static/assets/art49/pirate-symbols50.png');
var S = { bal: 25000, lbIdx: 1, lines: {}, turbo: false, auto: 0, sound: true, busy: false, gambleAmt: 0, age: false, stopReq: false };
try { var sv = JSON.parse(localStorage.getItem('spinrush-site-v2') || 'null');
  if (sv) { if (isFinite(sv.bal)) S.bal = Math.max(0, +sv.bal); S.lbIdx = Math.min(LB.length - 1, Math.max(0, sv.lbIdx | 0)); S.lines = sv.lines || {}; S.turbo = !!sv.turbo; S.sound = sv.sound !== false; S.age = !!sv.age; } } catch (e) {}
function save() { try { localStorage.setItem('spinrush-site-v2', JSON.stringify({ bal: S.bal, lbIdx: S.lbIdx, lines: S.lines, turbo: S.turbo, sound: S.sound, age: S.age })); } catch (e) {} }
function r2(v) { return Math.round(v * 100) / 100; }
function money(v) { var neg = v < 0; v = Math.round(Math.abs(v) * 100); var c = v % 100, w = String(Math.floor(v / 100)).replace(/\B(?=(\d{3})+(?!\d))/g, ' '); return (neg ? '−' : '') + 'R ' + w + ',' + (c < 10 ? '0' : '') + c; }
function short(v) { return v >= 1000 ? 'R' + (v / 1000).toFixed(v >= 10000 ? 0 : 1) + 'k' : v >= 100 ? 'R' + Math.round(v) : 'R' + (Math.round(v * 100) / 100).toString().replace('.', ','); }
function rng(n) { var a = new Uint32Array(1), lim = Math.floor(4294967296 / n) * n; do { crypto.getRandomValues(a); } while (a[0] >= lim); return a[0] % n; }
var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
/* Server mode: the game server decides every outcome and holds the balance; this page only animates. */
var SERVER = !!window.SPINRUSH_SERVER;
function api(path, body) {
  return fetch(path, { method: body === undefined ? 'GET' : 'POST', headers: { 'Content-Type': 'application/json' }, credentials: 'same-origin', body: body === undefined ? undefined : JSON.stringify(body) })
    .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { if (!r.ok || j.error) throw new Error(j.error || ('HTTP ' + r.status)); return j; }); });
}
var RM = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
var GAMES = D.games, byId = {}; GAMES.forEach(function (g) { byId[g.id] = g; });
var LABEL = function (f) { return E.FAMILY[f].label; };

/* ================================================================ sound (synthesised) */
var AC = null, master = null;
function audio() { if (!S.sound) return null; if (!AC) { try { AC = new (window.AudioContext || window.webkitAudioContext)(); master = AC.createGain(); master.gain.value = .5; master.connect(AC.destination); } catch (e) { return null; } } if (AC.state === 'suspended') AC.resume(); return AC; }
function tone(f, t, d, type, vol, slide) { var a = audio(); if (!a) return; var o = a.createOscillator(), g = a.createGain(), s = a.currentTime + (t || 0); o.type = type || 'sine'; o.frequency.setValueAtTime(f, s); if (slide) o.frequency.exponentialRampToValueAtTime(slide, s + d); g.gain.setValueAtTime(.0001, s); g.gain.exponentialRampToValueAtTime(vol || .2, s + .01); g.gain.exponentialRampToValueAtTime(.0001, s + d); o.connect(g); g.connect(master); o.start(s); o.stop(s + d + .02); }
function noise(t, d, vol, hp) { var a = audio(); if (!a) return; var n = a.sampleRate * d | 0, b = a.createBuffer(1, n, a.sampleRate), ch = b.getChannelData(0); for (var i = 0; i < n; i++) ch[i] = (Math.random() * 2 - 1) * (1 - i / n); var s = a.createBufferSource(), f = a.createBiquadFilter(), g = a.createGain(); s.buffer = b; f.type = 'highpass'; f.frequency.value = hp || 2000; g.gain.value = vol || .12; s.connect(f); f.connect(g); g.connect(master); s.start(a.currentTime + (t || 0)); }
var SND = {
  click: function () { tone(1400, 0, .04, 'square', .04); },
  coin: function () { tone(1900, 0, .06, 'square', .045); tone(2600, .05, .1, 'square', .035); },
  tick: function () { noise(0, .022, .04, 3200); },
  stop: function (c) { tone(140 - c * 7, 0, .15, 'sine', .45, 48); noise(0, .05, .1, 1400); },
  scat: function (n) { tone(880 * Math.pow(1.26, n), 0, .32, 'triangle', .22); tone(1760 * Math.pow(1.26, n), .05, .38, 'sine', .1); },
  tease: function () { tone(180, 0, 1.1, 'sawtooth', .05, 720); },
  small: function () { [784, 988, 1175].forEach(function (f, i) { tone(f, i * .07, .22, 'triangle', .16); }); },
  win: function () { [523, 659, 784, 1047, 1319].forEach(function (f, i) { tone(f, i * .08, .3, 'triangle', .18); }); },
  roll: function () { tone(2000 + Math.random() * 300, 0, .03, 'square', .025); },
  big: function () { [[523, 659, 784], [587, 740, 880], [659, 831, 988], [784, 988, 1175, 1568]].forEach(function (ch, i) { ch.forEach(function (f) { tone(f, i * .22, .5, 'sawtooth', .06); tone(f * 2, i * .22, .5, 'triangle', .045); }); }); },
  fs: function () { for (var i = 0; i < 10; i++) tone(400 * Math.pow(1.122, i), i * .07, .25, 'triangle', .14); },
  lock: function () { tone(660, 0, .12, 'square', .07); tone(990, .06, .25, 'triangle', .16); },
  heart: function () { tone(70, 0, .15, 'sine', .35, 50); }
};

/* ================================================================ art */
var IMG = {};
function img(src) { if (!IMG[src]) { var im = new Image(); im.decoding = 'async'; im.src = src; IMG[src] = im; } return IMG[src]; }
function loaded(srcs) { return Promise.all(srcs.map(function (s) { var im = img(s); return im.complete && im.naturalWidth ? 1 : new Promise(function (r) { im.onload = im.onerror = r; }); })); }
function tile(x, im, idx, dx, dy, dw, dh) { if (!im.naturalWidth) return; var sw = im.naturalWidth / 4, sh = im.naturalHeight / 4; x.drawImage(im, (idx % 4) * sw, Math.floor(idx / 4) * sh, sw, sh, dx, dy, dw, dh); }
function worldSvg(id, dim) { var a = D.A51[id]; if (!a) return ''; return '<svg viewBox="' + a.view + '" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><image href="' + A(a.src) + '" width="' + a.w + '" height="' + a.h + '"/></svg>'; }
function sheetFor(id) { var a = D.A52[id]; return a ? A(a.src) : PIR; }
function rr(x, X, Y, w, h, r) { x.beginPath(); x.moveTo(X + r, Y); x.arcTo(X + w, Y, X + w, Y + h, r); x.arcTo(X + w, Y + h, X, Y + h, r); x.arcTo(X, Y + h, X, Y, r); x.arcTo(X, Y, X + w, Y, r); x.closePath(); }

function drawSymbol(x, code, px, gid, family) {
  var a = D.A52[gid], pir = !a, sheet = img(sheetFor(gid)), common = img(COMMON), z = px * .94, o = (px - z) / 2;
  if (code <= 7) tile(x, sheet, pir ? D.map49['s0' + code] : a.offset + code, o, o, z, z);
  else if (code <= 10) tile(x, pir ? sheet : common, pir ? D.map49['s' + (code < 10 ? '0' : '') + code] : [3, 4, 5][code - 8], o, o, z, z);
  else if (code === WILD) {
    if (pir) { tile(x, sheet, D.map49.s18, o, o, z, z); return; }
    var w = D.A51[gid], wim = w && img(A(w.src)), p = px * .06;
    x.save(); rr(x, p, p, px - 2 * p, px - 2 * p, px * .08); x.clip();
    var bg = x.createLinearGradient(0, 0, px, px); bg.addColorStop(0, byId[gid].accent || '#8b40c0'); bg.addColorStop(1, '#180c29'); x.fillStyle = bg; x.fillRect(0, 0, px, px);
    if (wim && wim.naturalWidth) { var v = w.view.split(' ').map(Number), crop = Math.min(v[2], v[3]); x.drawImage(wim, v[0] + (v[2] - crop) / 2, v[1], crop, v[3], p, p, px - 2 * p, px - 2 * p); }
    x.fillStyle = 'rgba(33,11,42,.86)'; x.fillRect(p, px * .7, px - 2 * p, px * .3 - p); x.restore();
    tile(x, common, 12, 0, 0, px, px);
    x.font = '900 ' + Math.round(px * .2) + 'px Georgia, serif'; x.textAlign = 'center'; x.textBaseline = 'middle'; x.lineWidth = Math.max(2, px * .025); x.strokeStyle = '#4e140d'; x.fillStyle = '#ffdc78';
    x.strokeText('WILD', px / 2, px * .83); x.fillText('WILD', px / 2, px * .83);
  } else if (code === SCAT) {
    if (pir) tile(x, sheet, D.map49.s19, o, o, z, z); else tile(x, common, family === 'book' ? 6 : 7, o, o, z, z);
    var book = family === 'book', lab = book ? 'WILD / SCATTER' : 'SCATTER';
    x.fillStyle = 'rgba(33,13,36,.9)'; x.fillRect(px * .04, px * .74, px * .92, px * .18);
    x.font = '900 ' + Math.round(px * (book ? .09 : .12)) + 'px Georgia, serif'; x.textAlign = 'center'; x.textBaseline = 'middle'; x.fillStyle = '#ffe29a'; x.fillText(lab, px / 2, px * .835, px * .9);
  } else if (code === COIN) tile(x, common, 8, o, o, z, z);
}

/* ================================================================ lobby */
var FEAT = ['pirate_dominion', 'temple', 'g31'], feat = 0, filter = 'all';
var ORDER = ['respin', 'book', 'pearl', 'fruit', 'classic', 'lock', 'sticky'];
function heroShow(i) {
  feat = i; var g = byId[FEAT[i]];
  $('heroArt').innerHTML = worldSvg(g.id);
  $('heroTitle').textContent = g.name; $('heroText').textContent = E.FAMILY[g.family].blurb; $('heroPlay').textContent = 'PLAY ' + g.name.toUpperCase() + ' ↗';
  $('heroPills').innerHTML = FEAT.map(function (id, j) { return '<button class="pill' + (j === i ? ' on' : '') + '" data-i="' + j + '">' + byId[id].name + '</button>'; }).join('');
}
function renderLobby() {
  var counts = {}; GAMES.forEach(function (g) { counts[g.family] = (counts[g.family] || 0) + 1; });
  $('chips').innerHTML = '<button class="chip' + (filter === 'all' ? ' on' : '') + '" data-f="all">All slots<b>' + GAMES.length + '</b></button>' +
    ORDER.map(function (f) { return '<button class="chip' + (filter === f ? ' on' : '') + '" data-f="' + f + '">' + LABEL(f) + '<b>' + counts[f] + '</b></button>'; }).join('');
  var q = $('q').value.trim().toLowerCase();
  var list = GAMES.filter(function (g) { return (filter === 'all' || g.family === filter) && (!q || g.name.toLowerCase().indexOf(q) >= 0); });
  $('grid').innerHTML = list.map(function (g) {
    return '<button class="card" data-id="' + g.id + '">' + (/^g[0-9]+$/.test(g.id) ? '<img loading="lazy" decoding="async" src="' + A(g.cover) + '" alt="">' : '<span class="original-cover">' + worldSvg(g.id) + '</span>') + '<span class="rt">' + (g.rtp * 100).toFixed(1) + '%</span><span class="meta"><span class="nm">' + g.name + '</span><span class="fm">' + LABEL(g.family) + ' · ' + g.maxLines + ' lines</span></span></button>';
  }).join('');
  $('empty').hidden = list.length > 0;
  $('collSub').textContent = GAMES.length + ' games · find your next world.';
  $('lobBal').textContent = money(S.bal);
}
$('chips').addEventListener('click', function (e) { var b = e.target.closest('.chip'); if (!b) return; filter = b.dataset.f; renderLobby(); });
$('grid').addEventListener('click', function (e) { var b = e.target.closest('.card'); if (b) go(b.dataset.id); });
$('q').addEventListener('input', renderLobby);
$('heroPills').addEventListener('click', function (e) { var b = e.target.closest('.pill'); if (b) heroShow(+b.dataset.i); });
$('heroPlay').addEventListener('click', function () { go(FEAT[feat]); });

/* routing: #play-<id> */
function hashFor(id) { return '#play-' + id.replace(/_/g, '-'); }
function idFromHash() { var m = location.hash.match(/^#play-([a-z0-9-]+)$/); if (!m) return null; var id = m[1].replace(/-/g, '_'); return byId[id] ? id : null; }
function go(id) { if (S.busy) return; location.hash = hashFor(id); }
function route() {
  var id = idFromHash();
  if (id && (!G || G.id !== id || $('gameView').hidden)) { if (!S.busy) openGame(id); }
  else if (!id) { if (S.busy) { location.hash = hashFor(G.id); return; } $('gameView').hidden = true; $('lobby').hidden = false; S.auto = 0; renderLobby(); window.scrollTo(0, 0); }
}
window.addEventListener('hashchange', route);

/* ================================================================ game */
var G = null, entry = null, cv = $('reels'), cx = cv.getContext('2d'), fx = $('fx'), fxx = fx.getContext('2d');
var DPR = 1, CW = 0, CH = 0, cw = 0, ch = 0, SPR = {}, SPRB = {}, PX = 0, reels = [], raf = null, lastTick = 0;
var scene = { held: null, sticky: null, expand: null, coins: null, winCells: null, item: null, tease: -1, hw: null, dimAll: false };
function lines() { return Math.min(G.maxLines, Math.max(1, S.lines[G.id] || G.maxLines)); }
function lineBet() { return LB[S.lbIdx]; }
function totalBet() { return r2(lines() * lineBet()); }

function openGame(id) {
  entry = byId[id]; G = E.makeGame({ id: id, family: entry.family, volatility: entry.volatility, name: entry.name }); G.k = entry.k;
  $('lobby').hidden = true; $('gameView').hidden = false; window.scrollTo(0, 0);
  $('gName').textContent = entry.name; $('gFam').textContent = LABEL(entry.family) + ' · ' + G.maxLines + ' lines';
  $('world').innerHTML = worldSvg(id);
  $('gameView').dataset.world = id;
  $('marqueeArt').innerHTML = worldSvg(id);
  $('rtpFoot').textContent = 'Payout rate ' + (entry.rtp * 100).toFixed(1) + '% at ' + G.maxLines + ' lines, checked over 3 million spins.';
  scene = { held: null, sticky: null, expand: null, coins: null, winCells: null, item: null, tease: -1, hw: null, dimAll: false };
  S.gambleAmt = 0; $('winM').querySelector('b').textContent = money(0);
  msg(E.FAMILY[entry.family].blurb);
  reels = G.strips.map(function (s) { return { pos: rng(s.length), phase: 'idle', v: 0 }; });
  PX = 0; SPR = {}; SPRB = {};
  var srcs = [sheetFor(id), COMMON]; if (D.A51[id]) srcs.push(A(D.A51[id].src));
  loaded(srcs).then(function () { PX = 0; resize(); });
  resize(); paint();
}
function buildSprites(px) {
  SPR = {}; SPRB = {};
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, WILD, SCAT, COIN].forEach(function (code) {
    var c = document.createElement('canvas'); c.width = c.height = px; drawSymbol(c.getContext('2d'), code, px, G.id, G.family); SPR[code] = c;
    var b = document.createElement('canvas'); b.width = b.height = px; var bx = b.getContext('2d'); for (var i = -3; i <= 3; i++) { bx.globalAlpha = .2; bx.drawImage(c, 0, i * px * .07); } SPRB[code] = b;
  });
}
function resize() {
  if (!G || $('gameView').hidden) return;
  var r = $('win').getBoundingClientRect(); if (!r.width) return;
  DPR = Math.min(2.5, window.devicePixelRatio || 1); CW = r.width; CH = r.height;
  cv.width = fx.width = Math.round(CW * DPR); cv.height = fx.height = Math.round(CH * DPR); cw = CW / 5; ch = CH / 3;
  var px = Math.round(Math.min(cw, ch) * DPR); if (px !== PX) { PX = px; buildSprites(px); } draw();
}
new ResizeObserver(function () { resize(); }).observe($('win'));

function draw() {
  var x = cx; x.setTransform(DPR, 0, 0, DPR, 0, 0); x.clearRect(0, 0, CW, CH);
  if (!G || !PX) return;
  if (scene.hw) { drawHold(x); return; }
  for (var c = 0; c < 5; c++) {
    var R = reels[c], s = G.strips[c], L = s.length, x0 = c * cw;
    var bg = x.createLinearGradient(0, 0, 0, CH); bg.addColorStop(0, 'rgba(10,6,24,.82)'); bg.addColorStop(.5, 'rgba(26,14,48,.62)'); bg.addColorStop(1, 'rgba(10,6,24,.82)');
    x.fillStyle = bg; x.fillRect(x0 + 1, 0, cw - 2, CH);
    if (scene.tease === c) { x.fillStyle = 'rgba(190,110,255,' + (.18 + .12 * Math.sin(performance.now() / 80)) + ')'; x.fillRect(x0 + 1, 0, cw - 2, CH); }
    var p = R.pos, base = Math.floor(p), off = p - base, fast = R.v > 9, sz = Math.min(cw, ch) * .96;
    x.save(); x.beginPath(); x.rect(x0, 0, cw, CH); x.clip();
    for (var k = -1; k <= 3; k++) {
      var sym = s[((base + k) % L + L) % L], y = (k - off) * ch, dx = x0 + (cw - sz) / 2, dy = y + (ch - sz) / 2;
      var cell = k >= 0 && k < 3 && off === 0 ? k * 5 + c : -1;
      if (cell >= 0 && scene.held && scene.held[c]) continue;
      if (cell >= 0 && scene.sticky && scene.sticky.indexOf(cell) >= 0) continue;
      var lit = cell >= 0 && scene.winCells && scene.winCells[cell];
      if (lit) { var sc = 1 + .07 * Math.sin(performance.now() / 95); x.save(); x.translate(x0 + cw / 2, y + ch / 2); x.scale(sc, sc); x.translate(-(x0 + cw / 2), -(y + ch / 2)); x.shadowColor = '#ffd76e'; x.shadowBlur = 22; x.drawImage(SPR[sym], dx, dy, sz, sz); x.restore(); }
      else { if (cell >= 0 && (scene.winCells || scene.dimAll)) x.globalAlpha = .38; x.drawImage((fast ? SPRB : SPR)[sym] || SPR[0], dx, dy, sz, sz); x.globalAlpha = 1; }
      if (cell >= 0 && sym === COIN && scene.coins && scene.coins[cell] !== undefined) coinText(x, scene.coins[cell], x0 + cw / 2, y + ch / 2, sz);
    }
    x.restore();
    if (c > 0) { x.fillStyle = 'rgba(237,204,137,.28)'; x.fillRect(x0 - .5, 0, 1, CH); }
  }
  // held (expanded) wild reels
  if (scene.held) for (var hc = 0; hc < 5; hc++) if (scene.held[hc]) {
    var hx = hc * cw; x.save(); x.shadowColor = '#ffcf5a'; x.shadowBlur = 18; x.fillStyle = 'rgba(40,16,60,.85)'; x.fillRect(hx + 2, 2, cw - 4, CH - 4); x.restore();
    for (var hr = 0; hr < 3; hr++) { var hs = Math.min(cw, ch) * .96; x.drawImage(SPR[WILD], hx + (cw - hs) / 2, hr * ch + (ch - hs) / 2, hs, hs); }
    x.save(); x.strokeStyle = '#ffd76e'; x.lineWidth = 3; x.shadowColor = '#ffd76e'; x.shadowBlur = 14; rr(x, hx + 3, 3, cw - 6, CH - 6, 10); x.stroke(); x.restore();
  }
  if (scene.sticky) scene.sticky.forEach(function (cell) {
    var sc2 = cell % 5, sr = Math.floor(cell / 5), ss = Math.min(cw, ch) * .96, sx = sc2 * cw + (cw - ss) / 2, sy = sr * ch + (ch - ss) / 2;
    x.save(); x.shadowColor = '#ffcf5a'; x.shadowBlur = 16; x.drawImage(SPR[WILD], sx, sy, ss, ss); x.restore();
    x.fillStyle = 'rgba(20,8,30,.85)'; x.fillRect(sx + ss * .2, sy + ss * .02, ss * .6, ss * .14); x.fillStyle = '#ffe9a8'; x.font = '800 ' + Math.max(8, ss * .1) + 'px Inter, sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle'; x.fillText('LOCKED', sx + ss / 2, sy + ss * .09);
  });
  if (scene.expand) {
    var e = scene.expand; e.reels.forEach(function (ec) {
      var ex = ec * cw; x.save(); x.fillStyle = 'rgba(30,10,50,.75)'; x.fillRect(ex + 2, 2, cw - 4, CH - 4);
      x.shadowColor = '#c78bff'; x.shadowBlur = 20; var es = Math.min(cw, ch) * .96; for (var er = 0; er < 3; er++) x.drawImage(SPR[e.sym], ex + (cw - es) / 2, er * ch + (ch - es) / 2, es, es); x.restore();
      x.save(); x.strokeStyle = '#d7a6ff'; x.lineWidth = 3; rr(x, ex + 3, 3, cw - 6, CH - 6, 10); x.stroke(); x.restore();
    });
  }
  if (scene.item) {
    var it = scene.item; x.save(); x.strokeStyle = it.color; x.shadowColor = it.color; x.shadowBlur = 14; x.lineJoin = 'round'; x.lineCap = 'round';
    if (it.path) { x.lineWidth = 4; x.beginPath(); for (var lc = 0; lc < 5; lc++) { var lx = lc * cw + cw / 2, ly = it.path[lc] * ch + ch / 2; if (!lc) x.moveTo(4, ly); x.lineTo(lx, ly); } x.lineTo(CW - 4, it.path[4] * ch + ch / 2); x.stroke(); }
    x.shadowBlur = 8; x.lineWidth = 2.5; (it.cells || []).forEach(function (q) { rr(x, q[1] * cw + 4, q[0] * ch + 4, cw - 8, ch - 8, 10); x.stroke(); }); x.restore();
  }
}
function coinText(x, v, X, Y, sz) {
  var lab = v === 200 ? 'MAJOR' : v === 50 ? 'MINOR' : v === 20 ? 'MINI' : null, amt = v * totalBet() * G.k;
  x.save(); x.textAlign = 'center'; x.textBaseline = 'middle';
  var t = lab || short(amt); x.font = '900 ' + Math.round(sz * (t.length > 5 ? .15 : .19)) + 'px Inter, sans-serif';
  x.lineWidth = sz * .05; x.strokeStyle = lab ? '#3a0016' : '#fff7d6'; x.fillStyle = lab ? '#fff' : '#5a2a00'; x.strokeText(t, X, Y + sz * .02); x.fillText(t, X, Y + sz * .02); x.restore();
}
function drawHold(x) {
  var H = scene.hw;
  for (var r = 0; r < 3; r++) for (var c = 0; c < 5; c++) {
    var x0 = c * cw, y0 = r * ch, cell = r * 5 + c, v = H.locked[cell], sz = Math.min(cw, ch) * .9;
    x.fillStyle = (r + c) % 2 ? 'rgba(40,22,6,.86)' : 'rgba(30,16,4,.86)'; x.fillRect(x0 + 1, y0 + 1, cw - 2, ch - 2);
    x.strokeStyle = 'rgba(255,200,80,.35)'; x.lineWidth = 1; x.strokeRect(x0 + 1.5, y0 + 1.5, cw - 3, ch - 3);
    if (v !== undefined) {
      var pop = H.pop[cell] ? 1 + .25 * Math.max(0, 1 - (performance.now() - H.pop[cell]) / 350) : 1;
      x.save(); x.translate(x0 + cw / 2, y0 + ch / 2); x.scale(pop, pop); if (H.hot === cell) { x.shadowColor = '#fff'; x.shadowBlur = 28; } x.drawImage(SPR[COIN], -sz / 2, -sz / 2, sz, sz); x.restore();
      if (H.paid[cell]) { x.globalAlpha = .6; x.fillStyle = '#fff'; x.font = '800 ' + Math.round(sz * .16) + 'px Inter'; x.textAlign = 'center'; x.fillText('PAID', x0 + cw / 2, y0 + ch / 2 + 4); x.globalAlpha = 1; }
      else coinText(x, v, x0 + cw / 2, y0 + ch / 2, sz);
    } else if (H.spinning) {
      x.save(); x.beginPath(); x.rect(x0 + 2, y0 + 2, cw - 4, ch - 4); x.clip(); var t = performance.now() / 45 + c * 7 + r * 3;
      for (var k = -1; k < 2; k++) { var yy = y0 + ((t % 1) + k) * ch; x.globalAlpha = .45; x.drawImage(SPRB[(Math.floor(t) + k + c + r) % 3 === 0 ? COIN : (5 + ((Math.floor(t) + k) & 3))], x0 + (cw - sz) / 2, yy + (ch - sz) / 2, sz, sz); }
      x.restore(); x.globalAlpha = 1;
    }
  }
}

/* ---- motion ---- */
function T() { var t = S.turbo; return { acc: t ? 80 : 200, min: t ? 200 : 600, stag: t ? 70 : 200, dec: t ? 220 : 480, vmax: t ? 56 : 38, tease: t ? 600 : 1400 }; }
function loop(now) {
  var act = false;
  for (var c = 0; c < 5; c++) {
    var R = reels[c], Ln = G.strips[c].length;
    if (R.phase === 'acc') { act = true; var p = Math.min(1, Math.max(0, (now - R.t0) / T().acc)); R.v = T().vmax * p * p; R.pos -= R.v * .016; if (p >= 1) R.phase = 'full'; }
    else if (R.phase === 'full') { act = true; R.v = T().vmax; R.pos -= R.v * .016; }
    else if (R.phase === 'dec') { act = true; var q = Math.min(1, (now - R.t0) / R.dur), e = 1 - Math.pow(1 - q, 3), ov = Math.sin(q * Math.PI) * .16 * (1 - q), prev = R.pos;
      R.pos = R.from - R.dist * e - ov; R.v = Math.abs(R.pos - prev) / .016; if (q >= 1) { R.pos = R.target; R.v = 0; R.phase = 'idle'; SND.stop(c); var cb = R.done; R.done = null; cb && cb(); } }
    if (R.phase === 'acc' || R.phase === 'full') R.pos = ((R.pos % Ln) + Ln) % Ln;
  }
  if (act && now - lastTick > 70) { SND.tick(); lastTick = now; }
  draw();
  if (act || scene.winCells || scene.tease >= 0 || scene.hw || scene.sticky || scene.held || scene.expand) raf = requestAnimationFrame(loop); else raf = null;
}
function kick() { if (!raf) raf = requestAnimationFrame(loop); }
function stopReel(c, stop) { return new Promise(function (res) { var R = reels[c], L = G.strips[c].length, extra = S.turbo ? 4 : 8, d = ((R.pos - stop) % L + L) % L; while (d < extra) d += L; R.from = R.pos; R.dist = d; R.target = stop; R.t0 = performance.now(); R.dur = T().dec; R.phase = 'dec'; R.done = res; }); }
async function spinTo(grid, stops, held) {
  var t = performance.now(); for (var c = 0; c < 5; c++) if (!held || !held[c]) { reels[c].phase = 'acc'; reels[c].t0 = t + c * 25; }
  kick(); await sleep(T().min);
  var pend = [], landed = 0, coinsSeen = 0;
  for (var c2 = 0; c2 < 5; c2++) {
    if (held && held[c2]) continue;
    var before = 0, cb = 0; for (var cc = 0; cc < c2; cc++) for (var r = 0; r < 3; r++) { if (grid[r][cc] === SCAT) before++; if (grid[r][cc] === COIN) cb++; }
    var tease = (G.fam.scat && c2 >= 2 && before >= 2) || (G.fam.coins && c2 >= 3 && cb >= 4);
    if (tease && !S.stopReq) { await Promise.all(pend); scene.tease = c2; kick(); SND.tease(); await sleep(T().tease); }
    (function (col) { var n = 0; for (var r2 = 0; r2 < 3; r2++) if (grid[r2][col] === SCAT) n++;
      pend.push(stopReel(col, stops[col]).then(function () { if (scene.tease === col) scene.tease = -1; if (n) { landed += n; SND.scat(landed); } })); })(c2);
    if (c2 < 4 && !S.stopReq) await sleep(T().stag);
  }
  await Promise.all(pend); scene.tease = -1;
}

/* ---- presentation ---- */
function msg(t) { $('msg').textContent = t; }
var LINECOL = ['#ff5c8a', '#4fd8ff', '#ffd34d', '#7dff9d', '#c88bff', '#ff9a4d', '#3de0ff', '#ff6ab8', '#c4ff4d', '#ffb3f0', '#7df9ff', '#ffe066', '#ff6b6b', '#8affc1', '#a98bff', '#ffa94d', '#4dd2ff', '#ff4fd8', '#d4ff5c', '#ffd6a5', '#6bffea', '#ff9de2', '#ffcf5c', '#9cff7d', '#ff7a7a'];
function nameOf(code) { var n = entry.names || {}; var key = code === WILD ? 's18' : code === SCAT ? 's19' : 's' + (code < 10 ? '0' : '') + code; return code === COIN ? 'Coin' : (n[key] || ['J', '10', '9'][code - 8] || 'Symbol'); }
function rollup(els, froms, tos, ms) { return new Promise(function (res) { var t0 = performance.now(), last = 0; (function f(now) { var p = Math.min(1, (now - t0) / ms), e = 1 - Math.pow(1 - p, 2); els.forEach(function (el, i) { el.textContent = money(froms[i] + (tos[i] - froms[i]) * e); }); if (now - last > 60 && p < 1) { SND.roll(); last = now; } if (p < 1) requestAnimationFrame(f); else res(); })(t0); }); }
function overlay(html, ms, btn) { var o = $('ov'); o.innerHTML = html + (btn ? '<button class="go" id="ovGo">' + btn + '</button>' : ''); o.hidden = false;
  return new Promise(function (res) { var done = function () { o.hidden = true; o.innerHTML = ''; res(); }; if (btn) { $('ovGo').onclick = function () { SND.click(); done(); }; $('ovGo').focus(); } if (ms) setTimeout(function () { if (!o.hidden) done(); }, ms); }); }
function band(t, cls) { var b = $('band'); if (!t) { b.hidden = true; return; } b.hidden = false; b.className = 'band' + (cls ? ' ' + cls : ''); b.textContent = t; }

var cycling = 0;
async function showWins(wins, mult, credit) {
  var k = SERVER ? 1 : G.k, items = [], amt = 0;
  (wins || []).forEach(function (w) {
    var a = r2(w.amt * k); amt += a;
    var text = w.scatter ? w.n + ' × ' + nameOf(SCAT) : w.expand ? 'Expanding ' + nameOf(w.sym) + ' on ' + w.n + ' reels' : 'Line ' + (w.line + 1) + ': ' + w.n + ' × ' + nameOf(w.sym) + (w.wild && G.fam.wildDouble ? ' (wild ×2)' : '');
    items.push({ cells: w.cells, path: w.path || null, color: w.scatter ? '#ff5cb0' : w.expand ? '#d7a6ff' : LINECOL[(w.line || 0) % 25], amt: a, text: text + ' pays ' + money(a) + (mult > 1 ? ' (×' + mult + ')' : '') });
  });
  amt = r2(amt);
  if (!items.length) return 0;
  var wc = {}; items.forEach(function (it) { (it.cells || []).forEach(function (q) { wc[q[0] * 5 + q[1]] = 1; }); }); scene.winCells = wc; kick();
  var my = ++cycling; (async function () { var i = 0; while (cycling === my) { scene.item = items[i % items.length]; if (S.busy) msg(scene.item.text); kick(); await sleep(S.turbo ? 450 : 900); i++; } })();
  var x = amt / totalBet(), wm = $('winM').querySelector('b'), cur = parseMoney(wm.textContent);
  if (credit) {
    (x >= 3 ? SND.win : SND.small)(); if (x >= 5) burst(24, .8);
    await rollup([wm, $('balM'), $('gBal')], [cur, S.bal, S.bal], [r2(cur + amt), r2(S.bal + amt), r2(S.bal + amt)], RM ? 150 : Math.min(1600, 300 + x * 110));
    S.bal = r2(S.bal + amt);
  }
  return amt;
}
function parseMoney(t) { return +(t.replace(/[^0-9,−-]/g, '').replace(',', '.').replace('−', '-')) || 0; }
function stopCycle() { cycling++; scene.item = null; scene.winCells = null; }

async function bigBanner(amount) {
  var x = amount / totalBet(); if (x < 15) return;
  var lbl = x >= 100 ? 'EPIC WIN' : x >= 40 ? 'MEGA WIN' : 'BIG WIN', cls = x >= 100 ? 'epic' : x >= 40 ? 'mega' : '';
  SND.big(); burst(x >= 40 ? 110 : 70, 1.15); var iv = setInterval(function () { burst(12, 1); }, 360);
  var o = $('ov'); o.innerHTML = '<h2 class="' + cls + '">' + lbl + '</h2><div class="amt num" id="ovAmt">' + money(0) + '</div>'; o.hidden = false;
  await rollup([$('ovAmt')], [0], [amount], RM ? 500 : Math.min(5000, 1500 + x * 22)); clearInterval(iv); await sleep(1200); o.hidden = true; o.innerHTML = '';
}

/* ---- particles ---- */
var parts = [], fxOn = false;
function burst(n, power) { for (var i = 0; i < n; i++) parts.push({ x: CW * (.1 + .8 * Math.random()), y: CH + 10, vx: (Math.random() - .5) * 6, vy: -(6 + Math.random() * 9) * (power || 1), r: 4 + Math.random() * 6, a: Math.random() * 6, va: (Math.random() - .5) * .4 }); if (!fxOn) { fxOn = true; requestAnimationFrame(fxLoop); } }
function fxLoop() { var x = fxx; x.setTransform(DPR, 0, 0, DPR, 0, 0); x.clearRect(0, 0, CW, CH);
  for (var i = parts.length - 1; i >= 0; i--) { var p = parts[i]; p.vy += .32; p.x += p.vx; p.y += p.vy; p.a += p.va; if (p.y > CH + 30 && p.vy > 0) { parts.splice(i, 1); continue; }
    var w = Math.abs(Math.cos(p.a)) * p.r, g = x.createLinearGradient(p.x - w, 0, p.x + w, 0); g.addColorStop(0, '#a86a00'); g.addColorStop(.5, '#fff2a8'); g.addColorStop(1, '#c98a12'); x.fillStyle = g; x.beginPath(); x.ellipse(p.x, p.y, Math.max(1, w), p.r, 0, 0, 7); x.fill(); }
  if (parts.length) requestAnimationFrame(fxLoop); else { fxOn = false; x.clearRect(0, 0, CW, CH); } }

/* ---- hold & spin playback ---- */
async function playHold(step) {
  var TB = totalBet(), k = G.k;
  SND.fs(); burst(40, .9);
  await overlay('<h2>HOLD &amp; SPIN</h2><div class="amt">' + step.start.length + ' COINS</div><p>Coins lock in place. Every new coin resets the 3 respins. Fill all 15 spots for the GRAND.</p>', S.auto ? 2400 : 0, 'START');
  var H = { locked: {}, pop: {}, paid: {}, spinning: false, hot: -1 };
  step.start.forEach(function (p) { H.locked[p[0] * 5 + p[1]] = p[2]; H.pop[p[0] * 5 + p[1]] = performance.now(); });
  stopCycle(); scene.hw = H; kick(); var count = step.start.length;
  band('HOLD & SPIN · RESPINS ●●● · ' + count + ' / 15 COINS', 'hold'); await sleep(700);
  for (var i = 0; i < step.respins.length; i++) {
    var rs = step.respins[i]; H.spinning = true; kick(); await sleep(S.turbo ? 320 : 680); H.spinning = false;
    rs.landed.forEach(function (l) { H.locked[l[0]] = l[1]; H.pop[l[0]] = performance.now(); SND.lock(); if (l[1] >= 20) burst(18, .8); });
    if (!rs.landed.length) SND.heart();
    count = rs.count; band('HOLD & SPIN · RESPINS ' + '●'.repeat(rs.left) + '○'.repeat(3 - rs.left) + ' · ' + count + ' / 15 COINS', 'hold'); kick(); await sleep(S.turbo ? 220 : 480);
  }
  msg('Collecting coins…');
  var wm = $('winM').querySelector('b'), total = 0, cur = parseMoney(wm.textContent);
  for (var cell = 0; cell < 15; cell++) { var v = H.locked[cell]; if (v === undefined) continue;
    H.hot = cell; kick(); var amt = r2(v * TB * k);
    if (v >= 20) { var jp = $('jp' + (v === 200 ? 1 : v === 50 ? 2 : 3)); jp && jp.classList.add('hit'); SND.big(); burst(30, 1); } else SND.win();
    await rollup([wm, $('balM'), $('gBal')], [cur + total, S.bal + total, S.bal + total], [cur + total + amt, S.bal + total + amt, S.bal + total + amt], v >= 20 ? 1400 : (S.turbo ? 160 : 360));
    total = r2(total + amt); H.paid[cell] = 1; H.hot = -1; kick(); }
  if (step.grand) { var gA = r2(step.grand * TB * k); $('jp0') && $('jp0').classList.add('hit'); await bigBannerExact('GRAND JACKPOT', gA); total = r2(total + gA); $('winM').querySelector('b').textContent = money(cur + total); }
  S.bal = r2(S.bal + total); paint();
  await overlay('<h2>HOLD &amp; SPIN</h2><div class="amt num">' + money(total) + '</div><p>' + step.count + ' coins collected.</p>', S.auto ? 2600 : 0, 'COLLECT');
  scene.hw = null; band(''); kick(); return total;
}
async function bigBannerExact(label, amount) { SND.big(); burst(140, 1.15); var o = $('ov'); o.innerHTML = '<h2 class="epic">' + label + '</h2><div class="amt num" id="ovAmt">' + money(0) + '</div>'; o.hidden = false; await rollup([$('ovAmt')], [0], [amount], RM ? 500 : 3500); await sleep(1200); o.hidden = true; o.innerHTML = ''; }

/* ---- a full round ---- */
async function play() {
  if (S.busy || !PX) return;
  var L = lines(), lb = lineBet(), TB = totalBet();
  if (S.bal + 1e-9 < TB) { msg('Not enough balance for this bet. Lower the bet or press TOP UP.'); S.auto = 0; paint(); return; }
  S.busy = true; S.stopReq = false; S.gambleAmt = 0; audio(); SND.coin(); stopCycle();
  scene.held = null; scene.sticky = null; scene.expand = null; scene.coins = null; scene.dimAll = false; band('');
  S.bal = r2(S.bal - TB); $('winM').querySelector('b').textContent = money(0); paint(); save();
  var R, srvBal = null, srvGamble = 0;
  if (SERVER) {
    try { var sr = await api('/api/spin', { game: G.id, lines: L, lineBet: lb }); R = sr.round; srvBal = sr.balance; srvGamble = sr.gamble; }
    catch (err) { try { S.bal = (await api('/api/session')).balance; } catch (e2) {} S.busy = false; S.auto = 0; msg('The spin could not be completed: ' + err.message + '. Your balance is shown as the server holds it.'); paint(); return; }
  } else R = E.round(G, L, lb, rng, true);
  var total = 0, fsMult = 1, fsTotal = 0, fsPlayed = 0, special = -1, k = SERVER ? 1 : G.k;
  msg('Good luck!');
  for (var i = 0; i < R.steps.length; i++) {
    var st = R.steps[i];
    if (st.kind === 'base' || st.kind === 'respin') {
      var held = st.held || null, prevHeld = scene.held;
      await spinTo(st.raw || st.grid, st.stops, prevHeld);
      if (st.coins) { scene.coins = {}; st.coins.forEach(function (p) { scene.coins[p[0] * 5 + p[1]] = p[2]; }); kick(); }
      if (held && held.some(Boolean)) {
        var newly = held.filter(function (h, c) { return h && !(prevHeld && prevHeld[c]); }).length;
        if (newly) { SND.fs(); burst(20, .7); scene.held = held.slice(); kick(); band('EXPANDING WILD · RESPIN ' + (st.kind === 'respin' ? '' : '') + '· ' + held.filter(Boolean).length + ' WILD REEL' + (held.filter(Boolean).length > 1 ? 'S' : ''), ''); await sleep(S.turbo ? 300 : 650); }
      }
      stopCycle();
      var w = await showWins(st.wins, 1, true); total = r2(total + w);
      if (!w && st.kind === 'base' && !R.feature) msg('No win. Spin again!');
      if (st.kind === 'respin' || (held && held.some(Boolean) && i < R.steps.length - 1)) await sleep(S.turbo ? 300 : 700);
    } else if (st.kind === 'hold') {
      await sleep(400); var hwAmt = await playHold(st); total = r2(total + hwAmt);
    } else if (st.kind === 'fsIntro') {
      fsMult = st.mult; special = st.special; fsTotal = st.spins; await sleep(500); stopCycle(); SND.fs(); burst(40, .9);
      var extra = special >= 0 ? '<p>Special expanding symbol:</p><canvas id="spCv" width="140" height="140" style="width:84px;height:84px;margin-top:6px"></canvas>' : '';
      var ttl = G.family === 'fruit' ? 'WIN-TO-SPIN' : 'FREE SPINS';
      var p1 = overlay('<h2>' + ttl + '</h2><div class="amt">' + st.spins + ' SPINS</div>' + (fsMult > 1 ? '<p>Every win pays ×' + fsMult + '.</p>' : '') + (G.fam.stickyFs ? '<p>Every wild that lands stays locked.</p>' : '') + extra, S.auto ? 2600 : 0, 'START');
      if (special >= 0) { var spc = $('spCv'); if (spc) drawSymbol(spc.getContext('2d'), special, 140, G.id, G.family); }
      await p1; fsPlayed = 0;
    } else if (st.kind === 'free') {
      fsPlayed = st.played; fsTotal = st.played + st.left;
      band((G.family === 'fruit' ? 'WIN-TO-SPIN ' : 'FREE SPINS ') + fsPlayed + ' / ' + fsTotal + (fsMult > 1 ? ' · ×' + fsMult : '') + ' · ' + money(total));
      scene.expand = null; await spinTo(st.grid, st.stops, null);
      if (st.sticky && st.sticky.length) { var prevN = scene.sticky ? scene.sticky.length : 0; scene.sticky = st.sticky.slice(); if (st.sticky.length > prevN) { SND.lock(); } kick(); }
      if (st.expand) { scene.expand = { sym: special, reels: st.expand.reels }; SND.fs(); kick(); await sleep(S.turbo ? 250 : 600); }
      stopCycle();
      var fw = await showWins(st.wins, fsMult, true); total = r2(total + fw);
      band((G.family === 'fruit' ? 'WIN-TO-SPIN ' : 'FREE SPINS ') + fsPlayed + ' / ' + fsTotal + (fsMult > 1 ? ' · ×' + fsMult : '') + ' · ' + money(total));
      if (st.add) { SND.fs(); msg('+' + st.add + ' free spin' + (st.add > 1 ? 's' : '') + '!'); }
      await sleep(S.turbo ? 260 : 640);
    } else if (st.kind === 'fsEnd') {
      stopCycle(); scene.sticky = null; scene.expand = null; kick();
      var fsWin = r2(st.amt * k); if (fsWin > 0) { SND.big(); burst(70, 1.05); }
      await overlay('<h2>BONUS TOTAL</h2><div class="amt num">' + money(fsWin) + '</div><p>' + st.played + ' free spins played.</p>', S.auto ? 2600 : 0, 'COLLECT');
      band('');
    }
  }
  band('');
  await bigBanner(total);
  if (total > 0) msg('You won ' + money(total) + (S.auto === 0 && total <= 2500 ? '. Press GAMBLE to risk it, or SPIN to keep it.' : '.'));
  if (SERVER) S.bal = srvBal;                       // the server's balance is the only true one
  if (S.auto === 0 && (SERVER ? srvGamble > 0 : (total > 0 && total <= 2500))) S.gambleAmt = SERVER ? srvGamble : total;
  S.busy = false; paint(); save();
  if (S.auto !== 0) { if (S.auto > 0) S.auto--; paint(); if (S.auto !== 0) { await sleep(S.turbo ? 250 : 600); if (S.auto !== 0 && !$('gameView').hidden) return play(); } }
}

/* ---- gamble ---- */
async function gamble() {
  if (S.gambleAmt <= 0 || S.busy) return;
  S.busy = true; var amt = S.gambleAmt; S.gambleAmt = 0; paint(); stopCycle(); var o = $('ov');
  for (var round = 0; round < 5 && amt > 0; round++) {
    var pick = await new Promise(function (res) {
      o.innerHTML = '<h2>GAMBLE</h2><div class="amt num" id="gAmt">' + money(amt) + '</div><p>Pick a colour to double it, or collect.</p><div class="card2" id="gCard">?</div>' +
        '<div class="row"><button class="go red" id="gR">RED</button><button class="go black" id="gB">BLACK</button></div><button class="go" id="gC">COLLECT ' + money(amt) + '</button>';
      o.hidden = false; $('gC').focus(); $('gR').onclick = function () { res('r'); }; $('gB').onclick = function () { res('b'); }; $('gC').onclick = function () { res('c'); };
    });
    if (pick === 'c') { if (SERVER) { try { S.bal = (await api('/api/gamble', { pick: 'collect' })).balance; } catch (e) {} } break; }
    ['gR', 'gB', 'gC'].forEach(function (id) { $(id).disabled = true; });
    var res, srv = null;
    if (SERVER) { try { srv = await api('/api/gamble', { pick: pick === 'r' ? 'red' : 'black' }); res = srv.result === 'red' ? 'r' : 'b'; } catch (e) { msg('Gamble failed: ' + e.message); amt = 0; break; } }
    else res = rng(2) ? 'r' : 'b';
    var card = $('gCard'); card.textContent = res === 'r' ? '♦' : '♣'; card.className = 'card2 ' + res; SND.roll(); await sleep(RM ? 300 : 750);
    if (pick === res) { S.bal = srv ? srv.balance : r2(S.bal + amt); amt = r2(amt * 2); $('gAmt').textContent = money(amt); SND.win(); burst(20, .9); paint(); await sleep(RM ? 250 : 650); }
    else { S.bal = srv ? srv.balance : r2(S.bal - amt); amt = 0; SND.heart(); paint(); o.innerHTML = '<h2>GAMBLE LOST</h2><p>That win is gone. Spin again!</p><button class="go" id="gOk">OK</button>'; await new Promise(function (r) { $('gOk').onclick = r; $('gOk').focus(); setTimeout(r, 1600); }); }
    save();
  }
  o.hidden = true; o.innerHTML = ''; if (amt > 0) msg('Collected ' + money(amt) + '.');
  S.busy = false; paint(); save();
}

/* ---- controls & paint ---- */
function paint() {
  if (!G) return;
  var L = lines(); $('linV').textContent = L + ' / ' + G.maxLines; $('lbV').textContent = money(lineBet()); $('betM').textContent = money(totalBet());
  $('balM').textContent = money(S.bal); $('gBal').textContent = money(S.bal); $('lobBal').textContent = money(S.bal);
  $('betline').innerHTML = 'Playing <b>' + L + '</b> of ' + G.maxLines + ' lines × <b>' + money(lineBet()) + '</b> per line = total bet <b>' + money(totalBet()) + '</b>';
  var lock = S.busy || S.auto !== 0;
  ['linDn', 'linUp', 'lbDn', 'lbUp', 'maxBtn', 'back'].forEach(function (id) { $(id).disabled = lock; });
  $('spinBtn').textContent = S.busy || S.auto ? 'STOP' : 'SPIN'; $('spinBtn').classList.toggle('stop', S.busy || S.auto !== 0);
  $('autoBtn').textContent = S.auto === 0 ? 'AUTO' : S.auto < 0 ? 'AUTO ∞' : 'AUTO ' + S.auto; $('autoBtn').classList.toggle('on', S.auto !== 0);
  $('turboBtn').classList.toggle('on', S.turbo); $('sndBtn').textContent = S.sound ? 'SOUND ON' : 'SOUND OFF';
  var gb = $('gambleBtn'); gb.disabled = !(S.gambleAmt > 0) || S.busy; gb.classList.toggle('green', S.gambleAmt > 0 && !S.busy);
  var jps = $('jps'); jps.hidden = !G.fam.coins;
  if (G.fam.coins) { var TB = totalBet(), k = G.k; jps.innerHTML = [['GRAND', G.fam.grand], ['MAJOR', 200], ['MINOR', 50], ['MINI', 20]].map(function (j, i) { return '<div class="jp" id="jp' + i + '"><small>' + j[0] + '</small><b class="num">' + money(j[1] * TB * k) + '</b></div>'; }).join(''); }
}
$('spinBtn').onclick = function () { SND.click(); if (S.auto !== 0) { S.auto = 0; paint(); return; } if (S.busy) { S.stopReq = true; return; } if (S.gambleAmt > 0) { S.gambleAmt = 0; } play(); };
$('linUp').onclick = function () { SND.click(); S.lines[G.id] = Math.min(G.maxLines, lines() + 1); paint(); save(); };
$('linDn').onclick = function () { SND.click(); S.lines[G.id] = Math.max(1, lines() - 1); paint(); save(); };
$('lbUp').onclick = function () { SND.click(); S.lbIdx = Math.min(LB.length - 1, S.lbIdx + 1); paint(); save(); };
$('lbDn').onclick = function () { SND.click(); S.lbIdx = Math.max(0, S.lbIdx - 1); paint(); save(); };
$('maxBtn').onclick = function () { SND.click(); S.lines[G.id] = G.maxLines; var i = LB.length - 1; while (i > 0 && LB[i] * G.maxLines > S.bal) i--; S.lbIdx = i; paint(); save(); play(); };
var AUTOS = [10, 25, 50, 100, -1];
$('autoBtn').onclick = function () { SND.click(); var i = AUTOS.indexOf(S.auto); S.auto = S.auto === 0 ? 10 : (i < AUTOS.length - 1 ? AUTOS[i + 1] : 0); S.gambleAmt = 0; paint(); if (S.auto !== 0 && !S.busy) play(); };
$('turboBtn').onclick = function () { SND.click(); S.turbo = !S.turbo; paint(); save(); };
$('sndBtn').onclick = function () { S.sound = !S.sound; if (S.sound) SND.click(); paint(); save(); };
$('gambleBtn').onclick = function () { SND.click(); gamble(); };
$('topBtn').onclick = function () { SND.click(); if (S.busy) return;
  if (SERVER) { api('/api/topup', {}).then(function (j) { S.bal = j.balance; paint(); msg('Balance topped up to ' + money(j.balance) + '.'); }).catch(function (e) { msg(e.message + '.'); }); return; }
  if (S.bal >= 25000) { msg('Top-up is available when your balance is below R 25 000,00.'); return; } S.bal = 25000; paint(); save(); msg('Balance topped up to ' + money(25000) + '.'); };
$('back').onclick = function () { SND.click(); if (S.busy) return; S.auto = 0; location.hash = ''; };
document.addEventListener('keydown', function (e) { if (e.code === 'Space' && !$('gameView').hidden && $('rules').hidden && $('ov').hidden && $('gate').hidden && document.activeElement.tagName !== 'INPUT') { e.preventDefault(); $('spinBtn').click(); } });

/* ---- rules sheet ---- */
$('rulesBtn').onclick = function () {
  SND.click(); var lb = lineBet(), L = lines(), TB = totalBet(), k = G.k, f = G.fam;
  $('rTitle').textContent = entry.name + ' · Rules & pays';
  var codes = f.nsym === 8 ? [0, 1, 2, 3, 4, 5, 6, 7] : [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  var h = '<p><b>' + LABEL(G.family) + '.</b> ' + f.blurb + '</p><p>Choose 1 to ' + G.maxLines + ' lines and a bet per line. Total bet = lines × bet per line. Wins pay left to right on played lines; only the highest win per line pays. ' +
    (f.wildReels.length ? 'WILD appears on reels 2, 3 and 4 and replaces every paying symbol.' + (f.wildDouble ? ' A win with a wild in it pays double.' : '') : f.bookWild ? 'The book replaces every paying symbol.' : 'There are no wilds.') + '</p>';
  h += '<h4>Pays at ' + money(lb) + ' per line</h4><div class="pays">';
  codes.forEach(function (c) { var p = G.pays[c], parts = []; for (var n = 5; n >= 2; n--) if (p[n - 2]) parts.push(n + ' = ' + money(p[n - 2] * lb * k)); h += '<div class="pay"><canvas data-s="' + c + '" width="120" height="120"></canvas><div><b>' + nameOf(c) + '</b>' + parts.join('<br>') + '</div></div>'; });
  if (f.scat) h += '<div class="pay"><canvas data-s="' + SCAT + '" width="120" height="120"></canvas><div><b>' + (G.family === 'book' ? 'Book' : 'Scatter') + '</b>' + [5, 4, 3].map(function (n) { return n + ' anywhere = ' + money(f.scatPay[n] * TB * k); }).join('<br>') + '</div></div>';
  if (f.wildReels.length) h += '<div class="pay"><canvas data-s="' + WILD + '" width="120" height="120"></canvas><div><b>Wild</b>Reels 2, 3, 4<br>Replaces paying symbols</div></div>';
  if (f.coins) h += '<div class="pay"><canvas data-s="' + COIN + '" width="120" height="120"></canvas><div><b>Coin</b>6+ start Hold &amp; Spin<br>Values ' + money(k * TB) + ' to ' + money(200 * k * TB) + '</div></div>';
  h += '</div>';
  if (f.fs || f.chainCap || f.coins || f.expandRespin) h += '<h4>Feature</h4><p>' + f.blurb + (f.fs ? ' Free spins use the bet that triggered them and cost nothing.' + (f.retrig ? ' 3 or more ' + (G.family === 'book' ? 'books' : 'scatters') + ' during free spins add ' + f.retrig + ' more.' : '') : '') + (f.coins ? ' Coin values: MINI ' + money(20 * k * TB) + ', MINOR ' + money(50 * k * TB) + ', MAJOR ' + money(200 * k * TB) + ', GRAND ' + money(f.grand * k * TB) + ' at this bet.' : '') + '</p>';
  h += '<p>Gamble: after a win you can press GAMBLE and pick red or black to double it (up to 5 times), or collect. The draw is a fair 50/50, so it does not change the payout rate.</p>';
  h += '<h4>The ' + G.maxLines + ' lines</h4><div class="lines" id="linesG"></div>';
  $('rBody').innerHTML = h;
  $('rBody').querySelectorAll('canvas[data-s]').forEach(function (c) { drawSymbol(c.getContext('2d'), +c.dataset.s, 120, G.id, G.family); });
  var lg = $('linesG'); lg.innerHTML = E.LINES.slice(0, G.maxLines).map(function (l, i) { return '<canvas width="100" height="66" data-l="' + i + '"></canvas>'; }).join('');
  lg.querySelectorAll('canvas').forEach(function (c) { var x = c.getContext('2d'), li = +c.dataset.l, ln = E.LINES[li]; x.fillStyle = '#140e2c'; x.fillRect(0, 0, 100, 66); x.fillStyle = 'rgba(255,255,255,.12)';
    for (var cc = 0; cc < 5; cc++) for (var r = 0; r < 3; r++) x.fillRect(4 + cc * 19, 4 + r * 20, 16, 17); x.strokeStyle = li < L ? LINECOL[li] : 'rgba(255,255,255,.25)'; x.lineWidth = 3; x.beginPath();
    for (var q = 0; q < 5; q++) { var px = 12 + q * 19, py = 12 + ln[q] * 20; q ? x.lineTo(px, py) : x.moveTo(px, py); } x.stroke(); x.fillStyle = '#fff'; x.font = '700 12px Inter, sans-serif'; x.fillText(li + 1, 84, 62); });
  var st = entry;
  $('rStats').innerHTML = [['Payout rate at ' + G.maxLines + ' lines', (st.rtp * 100).toFixed(1) + '%'], ['Payout rate at 1 line', (st.rtp1 * 100).toFixed(1) + '%'], ['Spins that pay something', Math.round(st.hit * 100) + '%'],
    [G.fam.expandRespin ? 'Wild respins' : G.fam.coins ? 'Hold & Spin' : 'Free spins', st.feat ? 'about 1 in ' + Math.round(1 / st.feat) + ' spins' : '—'], ['Wins of 20× bet or more', st.big ? 'about 1 in ' + Math.round(1 / st.big) : '—'], ['Volatility', entry.volatility]]
    .map(function (r) { return '<tr><td>' + r[0] + '</td><td>' + r[1] + '</td></tr>'; }).join('');
  $('simOut').textContent = ''; $('rules').hidden = false; $('rClose').focus();
};
$('rClose').onclick = function () { SND.click(); $('rules').hidden = true; };
$('simBtn').onclick = function () {
  var btn = this, N = 100000, done = 0, bet = 0, ret = 0, hits = 0, feat = 0, L = G.maxLines, r = E.mulberry((Date.now() ^ (Math.random() * 1e9)) >>> 0), q = function (n) { return Math.floor(r() * n); };
  btn.disabled = true;
  (function chunk() { var end = Math.min(N, done + 5000); for (; done < end; done++) { var o = E.round(G, L, 1, q, false); bet += L; ret += o.units * G.k; if (o.units > 0) hits++; if (o.feature) feat++; }
    $('simOut').textContent = 'Spun ' + done.toLocaleString('en-ZA') + ' times · paid back ' + (ret / bet * 100).toFixed(1) + '%';
    if (done < N) setTimeout(chunk, 0); else { $('simOut').textContent = '100,000 spins at ' + L + ' lines: paid back ' + (ret / bet * 100).toFixed(1) + '% · ' + Math.round(hits / N * 100) + '% of spins paid · feature ' + feat + ' times. Short runs swing around the long-run rate.'; btn.disabled = false; } })();
};

/* ---- age gate & boot ---- */
$('gateYes').onclick = function () { S.age = true; save(); $('gate').hidden = true; };
$('gateNo').onclick = function () { $('gateMsg').textContent = 'SpinRush is for adults only. Please come back when you are 18.'; };
$('brandImg').src = A('static/assets/art49/brand.svg');
document.querySelectorAll('img.cabinet-brand').forEach(function (im) { im.src = A('static/assets/art49/brand.svg'); });
heroShow(0); renderLobby();
if (SERVER) api('/api/session').then(function (j) { S.bal = j.balance; renderLobby(); paint(); }).catch(function () { msg('Could not reach the game server.'); });
if (!S.age) $('gate').hidden = false;
route();
if (location.hash === '#selftest') window.__sr = { S: S, open: openGame, play: play, gamble: gamble, G: function () { return G; } };
})();
