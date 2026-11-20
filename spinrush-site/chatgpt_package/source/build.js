/* Tune every game to the target payout rate and verify it with an independent run.
   node build.js CATALOGUE.json [spins] [target]  ->  games.json */
'use strict';
const fs = require('fs');
const E = require('./engine.js');
const [, , catPath, nArg, tArg] = process.argv;
const N = +nArg || 1000000, TARGET = +tArg || 0.84;
const cat = JSON.parse(fs.readFileSync(catPath, 'utf8'));
const rngFrom = seed => { const r = E.mulberry(seed); return n => Math.floor(r() * n); };

const out = [];
const t0 = Date.now();
for (const g of cat) {
  const entry = { id: g.id, family: g.family, volatility: g.volatility, name: g.name };
  const G = E.makeGame(entry);
  const n = g.family === 'lock' ? N * 7 : N;                                  // jackpot games need far more spins
  const raw = E.simulate(G, n, rngFrom(E.seedOf(g.id + '|tune')));         // run 1: measure
  const k = TARGET / raw.rtpRaw;
  G.k = k;
  const check = E.simulate(G, n, rngFrom(E.seedOf(g.id + '|verify')));     // run 2: independent check
  const low = E.simulate(G, Math.round(N / 4), rngFrom(E.seedOf(g.id + '|1line')), 1); // 1 line
  out.push({ id: g.id, k: +k.toFixed(6), rtp: +check.rtp.toFixed(4), rtp1: +low.rtp.toFixed(4), hit: +check.hit.toFixed(4),
             feat: +check.feat.toFixed(5), big: +check.big.toFixed(5), maxLines: G.maxLines });
  console.log(g.id.padEnd(18), g.family.padEnd(8), g.volatility.padEnd(7), 'k', k.toFixed(3),
    '| verify', (check.rtp * 100).toFixed(2) + '%', '| 1 line', (low.rtp * 100).toFixed(1) + '%',
    '| hit', (check.hit * 100).toFixed(0) + '%', '| feature 1 in', check.feat ? Math.round(1 / check.feat) : '-');
}
fs.writeFileSync('games.json', JSON.stringify(out));
console.log('done in', ((Date.now() - t0) / 1000).toFixed(0) + 's');
