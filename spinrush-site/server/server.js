/* SpinRush game server — every outcome is decided here, never in the browser.
   - Spins, features and the gamble use Node's cryptographically secure RNG (crypto.randomInt).
   - Balances live on the server; the browser only animates the result it is sent.
   - Every round and gamble is appended to an audit log (data/rounds.jsonl).
   - Virtual play-money only: there are no deposit, payment or withdrawal endpoints.
   Run: node server.js   (PORT, DATA_DIR and STATIC_DIR can be set in the environment) */
'use strict';
const http = require('http'), fs = require('fs'), path = require('path'), crypto = require('crypto');
const E = require('./engine.js');

const PORT = +process.env.PORT || 8080;
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');
const PUBLIC_DIR = path.join(__dirname, 'public');
const STATIC_DIR = process.env.STATIC_DIR || [path.join(__dirname, 'static'), path.join(__dirname, '..', 'static')].find(d => fs.existsSync(d));
const LINE_BETS = [0.05, 0.10, 0.20, 0.50, 1, 2, 5];
const START_BALANCE = 25000, GAMBLE_MAX = 2500, GAMBLE_ROUNDS = 5, MIN_GAP_MS = 120;

/* ------------------------------------------------------------------ games (server-side copy of the maths) */
const GAME_DATA = JSON.parse(fs.readFileSync(path.join(__dirname, 'games_data.json'), 'utf8'));
const GAMES = new Map();
for (const g of GAME_DATA) { const G = E.makeGame(g); G.k = g.k; GAMES.set(g.id, G); }
const rng = n => crypto.randomInt(0, n);                    // unbiased, cryptographically secure
const cents = v => Math.round(v * 100) / 100;

/* ------------------------------------------------------------------ storage */
fs.mkdirSync(DATA_DIR, { recursive: true });
const SESS_FILE = path.join(DATA_DIR, 'sessions.json'), LOG_FILE = path.join(DATA_DIR, 'rounds.jsonl');
let sessions = {};
try { sessions = JSON.parse(fs.readFileSync(SESS_FILE, 'utf8')); } catch (e) { sessions = {}; }
let dirty = false;
function persist() {
  if (!dirty) return; dirty = false;
  const tmp = SESS_FILE + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(sessions)); fs.renameSync(tmp, SESS_FILE);  // atomic replace
}
setInterval(persist, 2000).unref();
function shutdown() { persist(); auditStream.end(() => process.exit(0)); setTimeout(() => process.exit(0), 3000).unref(); }
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
// One open append stream for the audit log: writes are queued in order, so heavy load can't exhaust file handles.
const auditStream = fs.createWriteStream(LOG_FILE, { flags: 'a' });
auditStream.on('error', e => console.error('audit log error', e));
function audit(rec) { auditStream.write(JSON.stringify(rec) + '\n'); }
const sidHash = sid => crypto.createHash('sha256').update(sid).digest('hex').slice(0, 16);

/* ------------------------------------------------------------------ sessions */
function parseCookies(req) { const o = {}; (req.headers.cookie || '').split(';').forEach(p => { const i = p.indexOf('='); if (i > 0) o[p.slice(0, i).trim()] = decodeURIComponent(p.slice(i + 1).trim()); }); return o; }
function session(req, res) {
  let sid = parseCookies(req).sr_sid;
  if (!sid || !/^[a-f0-9]{64}$/.test(sid) || !sessions[sid]) {
    sid = crypto.randomBytes(32).toString('hex');
    sessions[sid] = { bal: START_BALANCE, pending: 0, gRounds: 0, created: Date.now(), last: 0, rounds: 0 };
    dirty = true;
  }
  const secure = (req.headers['x-forwarded-proto'] || '').includes('https') ? '; Secure' : '';
  res.setHeader('Set-Cookie', 'sr_sid=' + sid + '; Path=/; HttpOnly; SameSite=Lax; Max-Age=31536000' + secure);
  const s = sessions[sid]; s.id = sid; return s;
}
const busy = new Set();

/* ------------------------------------------------------------------ the round, settled in rand */
// The engine returns raw units; the server converts every win to rand (×k, rounded to cents) and the
// balance moves by exactly the sum the player is shown.
function settle(G, L, lb, raw) {
  const TB = L * lb, k = G.k; let total = 0;
  for (const st of raw.steps) {
    if (st.wins) { let s = 0; for (const w of st.wins) { w.amt = cents(w.amt * k); s += w.amt; } st.amt = cents(s); }
    if (st.kind === 'base' || st.kind === 'respin' || st.kind === 'free') total = cents(total + st.amt);
    if (st.kind === 'hold') {
      let s = 0; for (const v of Object.values(st.locked)) s = cents(s + cents(v * TB * k));
      if (st.grand) s = cents(s + cents(st.grand * TB * k));
      st.amt = s; total = cents(total + s);
    }
  }
  let fs = 0; for (const st of raw.steps) { if (st.kind === 'free') fs = cents(fs + st.amt); if (st.kind === 'fsEnd') { st.amt = fs; fs = 0; } }
  return total;
}

/* ------------------------------------------------------------------ API */
function send(res, code, obj) { res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(obj)); }
function body(req) {
  return new Promise((ok, bad) => { let d = ''; req.on('data', c => { d += c; if (d.length > 4096) { bad(new Error('Request too large')); req.destroy(); } });
    req.on('end', () => { try { ok(d ? JSON.parse(d) : {}); } catch (e) { bad(new Error('Bad JSON')); } }); });
}

const routes = {
  'GET /api/session': (s) => ({ balance: s.bal, gamble: s.pending, lineBets: LINE_BETS }),

  'POST /api/spin': (s, b) => {
    const G = GAMES.get(b.game);
    if (!G) throw [400, 'Unknown game'];
    const L = b.lines | 0, lb = +b.lineBet;
    if (L < 1 || L > G.maxLines) throw [400, 'Lines must be 1 to ' + G.maxLines];
    if (!LINE_BETS.includes(lb)) throw [400, 'That bet per line is not offered'];
    const bet = cents(L * lb);
    if (s.bal + 1e-9 < bet) throw [402, 'Not enough balance for this bet'];
    if (Date.now() - s.last < MIN_GAP_MS) throw [429, 'Too fast'];
    s.last = Date.now(); s.pending = 0; s.gRounds = 0;
    const before = s.bal;
    s.bal = cents(s.bal - bet);
    const round = E.round(G, L, lb, rng, true);
    const win = settle(G, L, lb, round);
    s.bal = cents(s.bal + win); s.rounds++;
    if (win > 0 && win <= GAMBLE_MAX) s.pending = win;
    dirty = true;
    const id = crypto.randomUUID();
    audit({ t: new Date().toISOString(), type: 'spin', id, player: sidHash(s.id), game: G.id, lines: L, lineBet: lb, bet, win,
            feature: round.feature, stops: round.steps.filter(x => x.stops).map(x => x.stops), before, after: s.bal });
    return { id, balance: s.bal, bet, win, gamble: s.pending, round: { feature: round.feature, steps: round.steps } };
  },

  'POST /api/gamble': (s, b) => {
    if (!(s.pending > 0)) throw [409, 'Nothing to gamble'];
    const pick = b.pick;
    if (pick === 'collect') { const amt = s.pending; s.pending = 0; s.gRounds = 0; dirty = true; audit({ t: new Date().toISOString(), type: 'collect', player: sidHash(s.id), amount: amt, balance: s.bal }); return { done: true, amount: amt, balance: s.bal }; }
    if (pick !== 'red' && pick !== 'black') throw [400, 'Pick red, black or collect'];
    if (s.gRounds >= GAMBLE_ROUNDS) throw [409, 'Gamble limit reached'];
    const stake = s.pending, result = crypto.randomInt(0, 2) ? 'red' : 'black', won = result === pick;
    if (won) { s.bal = cents(s.bal + stake); s.pending = cents(stake * 2); s.gRounds++; }
    else { s.bal = cents(s.bal - stake); s.pending = 0; s.gRounds = 0; }
    const done = !won || s.gRounds >= GAMBLE_ROUNDS;
    if (done && won) { s.pending = 0; s.gRounds = 0; }
    dirty = true;
    audit({ t: new Date().toISOString(), type: 'gamble', player: sidHash(s.id), pick, result, stake, won, balance: s.bal });
    return { result, won, amount: won ? cents(stake * 2) : 0, balance: s.bal, done };
  },

  'POST /api/topup': (s) => {
    if (s.bal >= START_BALANCE) throw [409, 'Top-up is available below R 25 000,00'];
    s.bal = START_BALANCE; s.pending = 0; dirty = true;
    audit({ t: new Date().toISOString(), type: 'topup', player: sidHash(s.id), balance: s.bal });
    return { balance: s.bal };
  }
};

/* ------------------------------------------------------------------ static files */
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.webp': 'image/webp', '.png': 'image/png', '.svg': 'image/svg+xml', '.css': 'text/css' };
function serveFile(res, file) {
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) { res.writeHead(404, { 'Content-Type': 'text/plain' }); return res.end('Not found'); }
    const ext = path.extname(file);
    res.writeHead(200, { 'Content-Type': TYPES[ext] || 'application/octet-stream', 'Cache-Control': ext === '.html' ? 'no-cache' : 'public, max-age=604800' });
    fs.createReadStream(file).pipe(res);
  });
}
function safeJoin(root, rel) { const p = path.normalize(path.join(root, rel)); return p.startsWith(root + path.sep) ? p : null; }

/* ------------------------------------------------------------------ server */
const server = http.createServer(async (req, res) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'same-origin');
  const url = new URL(req.url, 'http://x'), key = req.method + ' ' + url.pathname;
  if (url.pathname.startsWith('/api/')) {
    const fn = routes[key]; if (!fn) return send(res, 404, { error: 'Not found' });
    const s = session(req, res);
    if (req.method === 'POST' && busy.has(s.id)) return send(res, 409, { error: 'A round is already in progress' });
    busy.add(s.id);
    try { const b = req.method === 'POST' ? await body(req) : {}; send(res, 200, fn(s, b)); }
    catch (e) { if (Array.isArray(e)) send(res, e[0], { error: e[1] }); else { console.error(e); send(res, 500, { error: 'Server error' }); } }
    finally { busy.delete(s.id); }
    return;
  }
  if (url.pathname.startsWith('/static/') && STATIC_DIR) { const f = safeJoin(STATIC_DIR, decodeURIComponent(url.pathname.slice('/static/'.length))); return f ? serveFile(res, f) : send(res, 400, { error: 'Bad path' }); }
  if (url.pathname === '/' || url.pathname === '/index.html' || url.pathname === '/vip' || url.pathname === '/vip.html') return serveFile(res, path.join(PUBLIC_DIR, 'index.html'));
  res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('Not found');
});
if (require.main === module) server.listen(PORT, () => console.log('SpinRush server on http://localhost:' + PORT + ' · ' + GAMES.size + ' games · data in ' + DATA_DIR));
module.exports = { server, routes, settle, GAMES };
