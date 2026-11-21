/* SpinRush engine v2 — original game maths for 7 families.
   One file shared by the page and the Node simulator, so the tested maths is the played maths.
   Symbols: 0..7 game symbols (s00..s07), 8..10 common royals (J,10,9), 18 WILD, 19 SCATTER/BOOK, 20 COIN. */
(function (root) {
  'use strict';
  var WILD = 18, SCAT = 19, COIN = 20;
  var LINES = [[1,1,1,1,1],[0,0,0,0,0],[2,2,2,2,2],[0,1,2,1,0],[2,1,0,1,2],[0,0,1,0,0],[2,2,1,2,2],[1,2,2,2,1],[1,0,0,0,1],[1,0,1,0,1],
    [1,2,1,2,1],[0,1,0,1,0],[2,1,2,1,2],[1,1,0,1,1],[1,1,2,1,1],[0,1,1,1,0],[2,1,1,1,2],[0,2,0,2,0],[2,0,2,0,2],[0,0,2,0,0],
    [2,2,0,2,2],[0,2,2,2,0],[2,0,0,0,2],[1,0,2,0,1],[1,2,0,2,1]];

  /* ------------------------------------------------------------ family templates (original designs) */
  // pays: [x2, x3, x4, x5] per symbol, in line-bet units, before the game's tuning factor k.
  var PAY11 = {
    medium: [[5,40,200,1000],[2,30,120,500],[0,20,80,300],[0,20,80,300],[0,15,50,150],[0,10,30,100],[0,8,25,90],[0,6,20,80],[0,5,15,60],[0,5,12,50],[0,4,10,40]],
    high:   [[10,80,400,2500],[5,50,250,1000],[0,30,120,500],[0,25,100,400],[0,15,60,200],[0,8,25,90],[0,6,20,75],[0,5,15,60],[0,4,10,40],[0,3,8,30],[0,3,6,25]],
    low:    [[2,25,100,400],[0,20,70,250],[0,15,50,180],[0,15,45,160],[0,12,35,110],[0,10,28,90],[0,8,24,80],[0,7,20,70],[0,6,16,60],[0,6,14,50],[0,5,12,45]]
  };
  var CNT11 = {  // symbol counts per reel (s00..s10), before per-game jitter
    medium: [2,3,3,4,5,6,7,7,8,8,9], high: [1,2,3,3,4,6,7,8,9,9,10], low: [3,3,4,4,5,6,6,7,7,8,8]
  };
  var PAY8 = {   // classic: s00..s07, [x2,x3,x4,x5]
    medium: [[0,50,200,1000],[0,20,80,400],[0,15,50,200],[0,10,40,150],[0,8,25,100],[0,5,15,60],[0,5,15,60],[1,4,10,40]],
    high:   [[0,100,500,3000],[0,40,150,600],[0,20,80,300],[0,12,50,180],[0,8,30,100],[0,5,15,50],[0,4,12,45],[1,4,10,35]],
    low:    [[0,30,120,500],[0,20,60,250],[0,15,45,160],[0,12,35,120],[0,10,25,90],[0,8,20,70],[0,7,18,60],[1,6,15,50]]
  };
  var CNT8 = { medium: [2,3,4,5,6,7,8,8], high: [1,2,4,5,6,8,9,9], low: [3,4,4,5,6,7,7,8] };

  var FAMILY = {
    classic: { label: 'Classic 5 Lines', maxLines: 5, nsym: 8, wildReels: [], scat: 2, scatPay: { 3: 2, 4: 10, 5: 50 },
      blurb: 'Five fixed-style lines, no wilds, pure symbol pays. Stars pay anywhere.' },
    book:    { label: 'Book Expansion', maxLines: 10, nsym: 11, wildReels: [], scat: 2, scatPay: { 3: 2, 4: 20, 5: 200 }, bookWild: true, fs: 10, retrig: 10,
      blurb: 'The book is wild and scatter. 3 books give 10 free spins with a special symbol that expands to fill its reels and pays on every line.' },
    pearl:   { label: 'Triple Free Spins', maxLines: 20, nsym: 11, wildReels: [1,2,3], wildN: 2, scat: 2, scatPay: { 3: 2, 4: 10, 5: 50 }, wildDouble: true, fs: 15, fsMult: 3, retrig: 15,
      blurb: 'Wilds on reels 2 to 4 double any win they complete. 3 scatters give 15 free spins where every win pays triple.' },
    fruit:   { label: 'Win-to-Spin', maxLines: 15, nsym: 11, wildReels: [1,2,3], wildN: 2, scat: 0, fsMult: 2, chainCap: 50,
      blurb: 'Line wins with the top four symbols award free spins: 3 in a row = 1, 4 = 3, 5 = 6. Free-spin wins pay double and can win more spins.' },
    lock:    { label: 'Hold & Spin', maxLines: 20, nsym: 11, wildReels: [1,2,3], wildN: 2, scat: 0, coins: 8, trigger: 6, respins: 3,
      coinV: [1,2,3,5,10,20,50,200], coinW: [380,250,150,100,60,35,20,5], grand: 1000, respinP: 0.075,
      blurb: '6 or more coins start Hold & Spin. Coins lock, every new coin resets 3 respins, and filling all 15 spots adds the GRAND.' },
    sticky:  { label: 'Sticky Wild Free Spins', maxLines: 20, nsym: 11, wildReels: [1,2,3], wildN: 2, scat: 2, scatPay: { 3: 2, 4: 10, 5: 50 }, fs: 10, retrig: 5, stickyFs: true,
      blurb: '3 scatters give 10 free spins. Every wild that lands in the free spins stays locked in place until the bonus ends.' },
    respin:  { label: 'Expanding Wild Respins', maxLines: 10, nsym: 11, wildReels: [1,2,3], wildN: 1, scat: 0, expandRespin: true,
      blurb: 'A wild on reels 2 to 4 expands to fill the reel, locks, and gives a free respin. Every new wild gives another respin.' }
  };

  /* ------------------------------------------------------------ deterministic helpers for building games */
  function seedOf(str) { var h = 2166136261; for (var i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }
  function mulberry(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; var t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }

  function buildStrip(counts, extra, r, clumps) {
    // counts: per paying symbol; extra: [[code, n], ...] spaced apart (wild/scatter); clumps: shuffled in freely (coins can stack)
    var s = [], i, j;
    for (i = 0; i < counts.length; i++) for (j = 0; j < counts[i]; j++) s.push(i);
    (clumps || []).forEach(function (e) { for (var q = 0; q < e[1]; q++) s.push(e[0]); });
    for (i = s.length - 1; i > 0; i--) { j = Math.floor(r() * (i + 1)); var t = s[i]; s[i] = s[j]; s[j] = t; }
    // insert specials at evenly spread positions with a little jitter so two never sit within 2 stops
    var total = s.length + extra.reduce(function (a, e) { return a + e[1]; }, 0), specials = [];
    extra.forEach(function (e) { for (var k = 0; k < e[1]; k++) specials.push(e[0]); });
    for (i = specials.length - 1; i > 0; i--) { j = Math.floor(r() * (i + 1)); var u = specials[i]; specials[i] = specials[j]; specials[j] = u; }
    var out = [], gap = total / Math.max(1, specials.length), next = Math.floor(r() * gap), si = 0, pi = 0;
    for (var pos = 0; pos < total; pos++) {
      if (si < specials.length && pos >= next) { out.push(specials[si++]); next = Math.floor((si + 0.15 + r() * 0.7) * gap); }
      else out.push(s[pi++]);
    }
    return out;
  }

  /* Build a playable game from a catalogue entry (art and identity stay the user's). */
  function makeGame(entry) {
    var fam = FAMILY[entry.family], vol = entry.volatility in PAY11 ? entry.volatility : 'medium';
    var r = mulberry(seedOf(entry.id + '|v2'));
    var base = fam.nsym === 8 ? CNT8[vol] : CNT11[vol];
    var pays = (fam.nsym === 8 ? PAY8[vol] : PAY11[vol]).map(function (p) { return p.slice(); });
    // per-game variety: nudge counts and pays so no two games in a family are identical
    var strips = [];
    for (var c = 0; c < 5; c++) {
      var counts = base.map(function (n, i) { var d = Math.floor(r() * 3) - 1; return Math.max(i < 2 ? 1 : 2, n + d); });
      var extra = [];
      if (fam.wildReels.indexOf(c) >= 0) extra.push([WILD, fam.wildN + (r() < 0.3 ? 1 : 0)]);
      if (fam.scat) extra.push([SCAT, fam.scat]);
      var clumps = fam.coins ? [[COIN, fam.coins + (c === 2 ? 1 : 0)]] : [];
      strips.push(buildStrip(counts, extra, r, clumps));
    }
    pays = pays.map(function (p) { var f = 0.9 + r() * 0.2; return p.map(function (v) { return Math.round(v * f); }); });
    return {
      id: entry.id, name: entry.name, family: entry.family, vol: vol, fam: fam,
      maxLines: fam.maxLines, strips: strips, pays: pays, k: entry.k || 1,
      specialW: [1, 1, 2, 2, 3, 3, 3, 4, 4, 4, 4]
    };
  }

  /* ------------------------------------------------------------ spin primitives */
  function drawGrid(G, rng) {
    var g = [[], [], []], stops = [];
    for (var c = 0; c < 5; c++) { var s = G.strips[c], st = rng(s.length); stops.push(st); for (var r = 0; r < 3; r++) g[r][c] = s[(st + r) % s.length]; }
    return { grid: g, stops: stops };
  }
  function isWild(G, v) { return v === WILD || (G.fam.bookWild && v === SCAT); }

  function lineWins(G, grid, L, lb, cells, out) {
    var tot = 0;
    for (var li = 0; li < L; li++) {
      var ln = LINES[li], s0 = -1, k;
      for (k = 0; k < 5; k++) { var v = grid[ln[k]][k]; if (!isWild(G, v)) { s0 = v; break; } }
      if (s0 < 0 || s0 > 10) continue;
      var n = 0, wild = false;
      for (k = 0; k < 5; k++) { var x = grid[ln[k]][k]; if (x === s0) n++; else if (isWild(G, x)) { n++; wild = true; } else break; }
      if (n < 2) continue;
      var p = G.pays[s0][n - 2]; if (!p) continue;
      var amt = p * lb * (G.fam.wildDouble && wild ? 2 : 1);
      tot += amt;
      if (out) out.push({ line: li, sym: s0, n: n, amt: amt, path: ln, wild: wild,
        cells: cells ? ln.slice(0, n).map(function (row, cc) { return [row, cc]; }) : null });
    }
    return tot;
  }
  function countSym(grid, code, cells) { var n = 0; for (var r = 0; r < 3; r++) for (var c = 0; c < 5; c++) if (grid[r][c] === code) { n++; if (cells) cells.push([r, c]); } return n; }

  /* One evaluated spin: line wins + scatter pays. mult applies to everything. */
  function evalSpin(G, grid, L, lb, mult, ui) {
    var wins = ui ? [] : null, tot = lineWins(G, grid, L, lb, ui, wins), TB = L * lb;
    var sc = 0, scCells = ui ? [] : null;
    if (G.fam.scat) {
      sc = countSym(grid, SCAT, scCells);
      var sp = G.fam.scatPay[Math.min(5, sc)] || 0;
      if (sp) { tot += sp * TB; if (ui) wins.push({ scatter: true, n: sc, amt: sp * TB, cells: scCells }); }
    }
    if (ui && mult !== 1) wins.forEach(function (w) { w.amt *= mult; });
    return { amt: tot * mult, wins: wins, sc: sc };
  }

  /* ------------------------------------------------------------ a full round (base spin + any feature) */
  // Returns raw units (before k); the caller multiplies by G.k. ui=true also returns presentation steps.
  function round(G, L, lb, rng, ui) {
    var f = G.fam, TB = L * lb, steps = ui ? [] : null, total = 0;
    var d = drawGrid(G, rng), grid = d.grid;

    if (f.expandRespin) {               // ---------- RESPIN: expanding, locking wilds
      var held = [false, false, false, false, false], spinN = 0, cur = grid, curStops = d.stops;
      while (true) {
        var newWild = false;
        for (var c = 1; c <= 3; c++) if (!held[c]) { for (var r = 0; r < 3; r++) if (cur[r][c] === WILD) { held[c] = true; newWild = true; break; } }
        var shown = cur.map(function (row) { return row.slice(); });
        for (var c2 = 0; c2 < 5; c2++) if (held[c2]) for (var r2 = 0; r2 < 3; r2++) shown[r2][c2] = WILD;
        var ev = evalSpin(G, shown, L, lb, 1, ui);
        total += ev.amt;
        if (ui) steps.push({ kind: spinN ? 'respin' : 'base', grid: shown, raw: cur, stops: curStops, wins: ev.wins, amt: ev.amt, held: held.slice() });
        if (!newWild || spinN >= 3) break;
        spinN++;
        var nd = drawGrid(G, rng); cur = nd.grid; curStops = nd.stops;
        for (var c3 = 0; c3 < 5; c3++) if (held[c3]) for (var r3 = 0; r3 < 3; r3++) cur[r3][c3] = WILD;
      }
      return { units: total, steps: steps, feature: spinN ? 'respin' : null, spins: spinN };
    }

    var ev0 = evalSpin(G, grid, L, lb, 1, ui);
    total += ev0.amt;
    var coinVals = null;
    if (f.coins) {                       // coins carry values (x total bet) from the moment they land
      coinVals = [];
      for (var rr = 0; rr < 3; rr++) for (var cc = 0; cc < 5; cc++) if (grid[rr][cc] === COIN) coinVals.push([rr, cc, pickW(f.coinV, f.coinW, rng)]);
    }
    if (ui) steps.push({ kind: 'base', grid: grid, stops: d.stops, wins: ev0.wins, amt: ev0.amt, coins: coinVals });

    // ---------- HOLD & SPIN
    if (f.coins && coinVals.length >= f.trigger) {
      var locked = {}, count = 0, sum = 0;
      coinVals.forEach(function (p) { locked[p[0] * 5 + p[1]] = p[2]; count++; sum += p[2]; });
      var left = f.respins, hsteps = ui ? [] : null;
      while (left > 0 && count < 15) {
        var landed = [];
        for (var cell = 0; cell < 15; cell++) if (locked[cell] === undefined && rng(1000000) < f.respinP * 1000000) {
          var v = pickW(f.coinV, f.coinW, rng); locked[cell] = v; count++; sum += v; landed.push([cell, v]);
        }
        if (landed.length) left = f.respins; else left--;
        if (ui) hsteps.push({ landed: landed, left: left, count: count });
      }
      var grand = count >= 15 ? f.grand : 0, hw = (sum + grand) * TB;
      total += hw;
      if (ui) steps.push({ kind: 'hold', start: coinVals, respins: hsteps, locked: locked, grand: grand, amt: hw, count: count });
      return { units: total, steps: steps, feature: 'hold', coins: count };
    }

    // ---------- FREE SPINS families
    var fs = 0, mult = 1;
    if (f.fs && ev0.sc >= 3) { fs = f.fs; mult = f.fsMult || 1; }
    if (f.chainCap) {                    // fruit: premium line wins award spins
      fs = fruitAward(ev0.wins, G, grid, L);
      mult = f.fsMult;
    }
    if (!fs) return { units: total, steps: steps, feature: null };

    var special = -1, sticky = {}, played = 0, featureWin = 0, maxSpins = f.chainCap || 200;
    if (f.bookWild) special = pickW([0,1,2,3,4,5,6,7,8,9,10], G.specialW, rng);
    if (ui) steps.push({ kind: 'fsIntro', spins: fs, special: special, mult: mult });
    while (fs > 0 && played < maxSpins) {
      fs--; played++;
      var dd = drawGrid(G, rng), g2 = dd.grid;
      if (f.stickyFs) {
        for (var c4 = 1; c4 <= 3; c4++) for (var r4 = 0; r4 < 3; r4++) if (g2[r4][c4] === WILD) sticky[r4 * 5 + c4] = 1;
        for (var key in sticky) { var kk = +key; g2[Math.floor(kk / 5)][kk % 5] = WILD; }
      }
      var e2 = evalSpin(G, g2, L, lb, mult, ui), stepAmt = e2.amt, exp = null;
      if (special >= 0) {                // book: special symbol expands over whole reels and pays every line
        var reels = [];
        for (var c5 = 0; c5 < 5; c5++) for (var r5 = 0; r5 < 3; r5++) if (g2[r5][c5] === special) { reels.push(c5); break; }
        var need = special <= 1 ? 2 : 3;
        if (reels.length >= need) {
          var p = G.pays[special][reels.length - 2] || 0, ex = p * lb * L * mult;
          if (ex) { stepAmt += ex; exp = { reels: reels, amt: ex }; if (ui) e2.wins.push({ expand: true, sym: special, n: reels.length, amt: ex, cells: reels.reduce(function (a, cc) { return a.concat([[0, cc], [1, cc], [2, cc]]); }, []) }); }
        }
      }
      featureWin += stepAmt;
      var add = 0;
      if (f.fs && e2.sc >= 3) add = f.retrig;
      if (f.chainCap) add = fruitAward(e2.wins, G, g2, L);
      if (add && played + fs < maxSpins) fs += add;
      if (ui) steps.push({ kind: 'free', grid: g2, stops: dd.stops, wins: e2.wins, amt: stepAmt, left: fs, played: played, add: add, sticky: f.stickyFs ? Object.keys(sticky).map(Number) : null, expand: exp, mult: mult });
    }
    total += featureWin;
    if (ui) steps.push({ kind: 'fsEnd', amt: featureWin, played: played });
    return { units: total, steps: steps, feature: 'free', spins: played };
  }
  function fruitAward(wins, G, grid, L) {
    // needs line results; in sim mode wins is null, so recompute the best premium run per line cheaply
    var best = 0;
    for (var li = 0; li < L; li++) {
      var ln = LINES[li], s0 = -1, k;
      for (k = 0; k < 5; k++) { var v = grid[ln[k]][k]; if (v !== WILD) { s0 = v; break; } }
      if (s0 < 0 || s0 > 3) continue;
      var n = 0; for (k = 0; k < 5; k++) { var x = grid[ln[k]][k]; if (x === s0 || x === WILD) n++; else break; }
      if (n >= 3 && G.pays[s0][n - 2]) best += n === 3 ? 1 : n === 4 ? 3 : 6;
    }
    return best;
  }
  function pickW(vals, ws, rng) { var t = 0, i; for (i = 0; i < ws.length; i++) t += ws[i]; var x = rng(t); for (i = 0; i < ws.length; i++) { if (x < ws[i]) return vals[i]; x -= ws[i]; } return vals[0]; }

  /* ------------------------------------------------------------ simulator (Node or browser) */
  function simulate(G, n, rng, L) {
    L = L || G.maxLines;
    var bet = 0, ret = 0, hits = 0, feats = 0, big = 0;
    for (var i = 0; i < n; i++) {
      var o = round(G, L, 1, rng, false), w = o.units;
      bet += L; ret += w; if (w > 0) hits++; if (o.feature) feats++; if (w >= 20 * L) big++;
    }
    return { rtpRaw: ret / bet, rtp: ret / bet * G.k, hit: hits / n, feat: feats / n, big: big / n };
  }

  var API = { WILD: WILD, SCAT: SCAT, COIN: COIN, LINES: LINES, FAMILY: FAMILY, makeGame: makeGame, round: round,
    simulate: simulate, drawGrid: drawGrid, pickW: pickW, mulberry: mulberry, seedOf: seedOf };
  if (typeof module !== 'undefined' && module.exports) module.exports = API; else root.SREngine = API;
})(this);
