/* API tests for the SpinRush server. Run: node test_api.js
   Starts the server on a temporary data folder, then checks validation, money movement, gamble,
   concurrency, the audit log, and the payout rate of server-settled spins. */
'use strict';
const os = require('os'), fs = require('fs'), path = require('path'), http = require('http');
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'srtest-'));
const { server, routes, GAMES } = require('./server.js');
let pass = 0, fail = 0;
const ok = (cond, name) => { if (cond) pass++; else { fail++; console.log('FAIL', name); } };
const cents = v => Math.round(v * 100) / 100;

function call(port, method, p, body, cookie) {
  return new Promise((res, rej) => {
    const data = body === undefined ? null : JSON.stringify(body);
    const req = http.request({ port, method, path: p, headers: Object.assign({ 'Content-Type': 'application/json' }, cookie ? { Cookie: cookie } : {}) }, r => {
      let d = ''; r.on('data', c => d += c); r.on('end', () => { let j = {}; try { j = JSON.parse(d); } catch (e) {} res({ status: r.statusCode, body: j, cookie: (r.headers['set-cookie'] || [''])[0].split(';')[0] }); });
    });
    req.on('error', rej); if (data) req.write(data); req.end();
  });
}
const wait = ms => new Promise(r => setTimeout(r, ms));

server.listen(0, async () => {
  const port = server.address().port;
  // ---- session
  let r = await call(port, 'GET', '/api/session'); const ck = r.cookie;
  ok(r.status === 200 && r.body.balance === 25000, 'new session starts at R25 000');
  ok(/^sr_sid=[a-f0-9]{64}$/.test(ck), 'secure random session id');
  // ---- validation (cheating attempts)
  r = await call(port, 'POST', '/api/spin', { game: 'nope', lines: 10, lineBet: 0.1 }, ck); ok(r.status === 400, 'unknown game rejected');
  r = await call(port, 'POST', '/api/spin', { game: 'temple', lines: 99, lineBet: 0.1 }, ck); ok(r.status === 400, 'too many lines rejected');
  r = await call(port, 'POST', '/api/spin', { game: 'temple', lines: 0, lineBet: 0.1 }, ck); ok(r.status === 400, 'zero lines rejected');
  r = await call(port, 'POST', '/api/spin', { game: 'temple', lines: 10, lineBet: 0.0001 }, ck); ok(r.status === 400, 'odd bet rejected');
  r = await call(port, 'POST', '/api/spin', { game: 'temple', lines: 10, lineBet: 5, win: 999999 }, ck); ok(r.status === 200 && r.body.win !== 999999, 'client cannot set its own win');
  r = await call(port, 'POST', '/api/gamble', { pick: 'red' }, 'sr_sid=' + 'f'.repeat(64)); ok(r.status === 409, 'forged session gets a fresh account, nothing to gamble');
  // ---- money movement on real spins
  let bal = (await call(port, 'GET', '/api/session', undefined, ck)).body.balance, consistent = true, stepsMatch = true;
  for (let i = 0; i < 60; i++) {
    await wait(130);
    const g = ['temple', 'diamond', 'moonlit_magic', 'g31', 'fruit', 'bass', 'neon_empire'][i % 7];
    const G = GAMES.get(g), L = G.maxLines;
    r = await call(port, 'POST', '/api/spin', { game: g, lines: L, lineBet: 0.1 }, ck);
    if (r.status !== 200) { consistent = false; console.log('spin status', r.status, r.body); break; }
    const b = r.body; if (Math.abs(b.balance - cents(bal - b.bet + b.win)) > 0.001) consistent = false;
    let credited = 0; for (const st of b.round.steps) if (['base', 'respin', 'free', 'hold'].includes(st.kind)) credited = cents(credited + st.amt);
    if (Math.abs(credited - b.win) > 0.001) stepsMatch = false;
    bal = b.balance;
  }
  ok(consistent, 'balance always moves by exactly win − bet');
  ok(stepsMatch, 'amounts shown per step add up to the win');
  // ---- too fast
  await call(port, 'POST', '/api/spin', { game: 'temple', lines: 10, lineBet: 0.1 }, ck);
  r = await call(port, 'POST', '/api/spin', { game: 'temple', lines: 10, lineBet: 0.1 }, ck); ok(r.status === 429, 'spam spins rejected');
  // ---- gamble via the route layer with a known pending win
  const s = { id: 'x'.repeat(64), bal: 1000, pending: 100, gRounds: 0, last: 0 };
  const g1 = routes['POST /api/gamble'](s, { pick: 'red' });
  ok(g1.won ? (s.bal === 1100 && s.pending === 200) : (s.bal === 900 && s.pending === 0), 'gamble moves the balance by exactly the stake');
  const s2 = { id: 'y'.repeat(64), bal: 1000, pending: 50, gRounds: 0, last: 0 }; const c = routes['POST /api/gamble'](s2, { pick: 'collect' });
  ok(c.done && s2.pending === 0 && s2.bal === 1000, 'collect keeps the win, ends the gamble');
  let gw = 0, gn = 20000; for (let i = 0; i < gn; i++) { const t = { id: 'z', bal: 0, pending: 10, gRounds: 0 }; if (routes['POST /api/gamble'](t, { pick: 'black' }).won) gw++; }
  ok(Math.abs(gw / gn - 0.5) < 0.015, 'gamble is a fair 50/50 (' + (gw / gn * 100).toFixed(1) + '% wins)');
  // ---- insufficient balance
  const poor = { id: 'p'.repeat(64), bal: 0.5, pending: 0, gRounds: 0, last: 0 };
  let threw = null; try { routes['POST /api/spin'](poor, { game: 'temple', lines: 10, lineBet: 0.1 }); } catch (e) { threw = e; }
  ok(threw && threw[0] === 402 && poor.bal === 0.5, 'cannot bet more than the balance');
  // ---- audit log
  await wait(300);
  const log = fs.readFileSync(path.join(process.env.DATA_DIR, 'rounds.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
  ok(log.filter(x => x.type === 'spin').length >= 60, 'every spin is in the audit log');
  ok(log.every(x => x.t && x.type) && log.filter(x => x.type === 'spin').every(x => Array.isArray(x.stops) && 'before' in x && 'after' in x), 'log records stops and balances');
  ok(!JSON.stringify(log).includes(ck.split('=')[1]), 'log never stores the raw session id');
  // ---- payout rate of server-settled spins (route layer, no rate limit)
  const sum = {};
  for (const id of ['temple', 'bass', 'neon_empire', 'moonlit_magic', 'g31', 'fruit']) {
    const G = GAMES.get(id), L = G.maxLines, N = 200000; let bet = 0, win = 0;
    const p = { id: 'r'.repeat(64), bal: 1e12, pending: 0, gRounds: 0, last: 0 };
    for (let i = 0; i < N; i++) { p.last = 0; const o = routes['POST /api/spin'](p, { game: id, lines: L, lineBet: 1 }); bet += o.bet; win += o.win; }
    sum[id] = (win / bet * 100).toFixed(1) + '%';
  }
  console.log('server-settled payout over 200,000 spins each:', JSON.stringify(sum));
  console.log(pass + ' passed, ' + fail + ' failed');
  server.close(); process.exit(fail ? 1 : 0);
});
