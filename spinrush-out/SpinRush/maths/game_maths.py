"""Maths for the three SpinRush games, all targeted at ~84% RTP.
python3 -I math3.py [neon|classic|gold|all] [spins]"""
import numpy as np, json, sys, itertools
OUT = {}

# ============================================================ NEON SEVENS (25 lines, free spins x3)
def neon(N):
    W, S7, DI, BE, BA, CH, GR, LE, SC = range(9)
    PAY = {W: (50, 250, 2500), S7: (40, 160, 1000), DI: (25, 100, 500), BE: (15, 60, 250),
           BA: (10, 40, 150), CH: (6, 22, 110), GR: (5, 18, 90), LE: (5, 14, 70)}
    SCATPAY = {3: 5, 4: 20, 5: 100}; FS = {3: 10, 4: 15, 5: 25}; FSM = 3
    COUNTS = [[1,2,3,4,5,7,8,9,1],[2,2,3,4,5,7,8,8,1],[2,2,3,4,5,7,8,8,1],[2,2,3,4,5,7,8,8,1],[1,2,3,4,5,7,8,9,1]]
    LINES = [[1,1,1,1,1],[0,0,0,0,0],[2,2,2,2,2],[0,1,2,1,0],[2,1,0,1,2],[0,0,1,0,0],[2,2,1,2,2],[1,2,2,2,1],[1,0,0,0,1],[1,0,1,0,1],
             [1,2,1,2,1],[0,1,0,1,0],[2,1,2,1,2],[1,1,0,1,1],[1,1,2,1,1],[0,1,1,1,0],[2,1,1,1,2],[0,2,0,2,0],[2,0,2,0,2],[0,0,2,0,0],
             [2,2,0,2,2],[0,2,2,2,0],[2,0,0,0,2],[1,0,2,0,1],[1,2,0,2,1]]
    STR = [[6,7,1,4,2,6,4,7,5,6,7,6,2,3,5,5,1,5,7,3,5,7,4,7,7,6,6,3,4,5,6,4,8,5,7,3,0,7,2,6],[6,3,7,7,6,1,7,5,3,8,7,5,4,5,1,5,2,7,0,5,6,6,4,2,4,7,6,5,2,0,7,3,3,6,6,5,4,4,6,7],[6,7,3,6,2,2,7,6,4,1,4,3,6,5,7,3,7,2,0,7,7,6,5,3,5,6,4,7,5,5,7,6,6,1,0,5,8,4,4,5],[7,7,1,3,6,7,6,5,1,7,6,7,6,4,3,6,6,5,5,0,6,4,4,5,3,3,5,0,7,7,2,6,8,4,5,2,2,4,7,5],[4,7,8,5,4,4,7,5,7,4,3,5,6,2,3,6,6,3,4,7,7,5,5,2,6,7,7,6,5,5,7,2,1,6,6,3,1,0,7,6]]
    STR = [np.array(s) for s in STR]; L = [len(s) for s in STR]; NL = 25
    rng = np.random.default_rng(1); B = 500_000; tl = ts = hits = 0; trig = {3: 0, 4: 0, 5: 0}
    for _ in range(N // B):
        g = np.empty((B, 3, 5), np.int8)
        for r in range(5):
            st = rng.integers(0, L[r], B)
            for row in range(3): g[:, row, r] = STR[r][(st + row) % L[r]]
        win = np.zeros(B)
        for ln in LINES:
            seq = g[:, ln, range(5)]
            wl = np.zeros(B, int); al = np.ones(B, bool)
            for k in range(5): al &= seq[:, k] == W; wl += al
            best = np.zeros(B)
            for k in (3, 4, 5): best = np.where(wl == k, np.maximum(best, PAY[W][k-3]), best)
            base = np.full(B, -1)
            for k in range(4, -1, -1): base = np.where(seq[:, k] != W, seq[:, k], base)
            cnt = np.zeros(B, int); al = np.ones(B, bool)
            for k in range(5): al &= (seq[:, k] == W) | (seq[:, k] == base); cnt += al
            for sym, p in PAY.items():
                if sym == W: continue
                for k in (3, 4, 5): best = np.where((base == sym) & (cnt == k), np.maximum(best, p[k-3]), best)
            win += best
        sc = np.minimum((g == SC).sum(axis=(1, 2)), 5)
        scp = np.select([sc == 3, sc == 4, sc == 5], [SCATPAY[3], SCATPAY[4], SCATPAY[5]], 0) * NL
        tl += win.sum(); ts += scp.sum(); hits += ((win + scp) > 0).sum()
        for k in trig: trig[k] += (sc == k).sum()
    base = (tl + ts) / (N * NL); p = {k: trig[k] / N for k in trig}
    r = sum(p[k] * FS[k] for k in p); fs = sum(p[k] * FS[k] / (1 - r) for k in p) * FSM * base
    print(f"NEON  base {base:.4f} + free spins {fs:.4f} = RTP {base+fs:.4f} | hit {hits/N:.3f} | FS 1 in {1/sum(p.values()):.0f}")
    OUT["neon"] = dict(pay={str(k): v for k, v in PAY.items()}, rtp=round(base + fs, 4), hit=round(hits / N, 3), fs=round(1 / sum(p.values())))

# ============================================================ DIAMOND FIRE (classic 3 reel, 1 line, coins 1-3)
BL, CHc, B1, B2, B3, S7c, DW = range(7)
C_WEIGHTS = [  # virtual reel weights per reel: blank, cherry, bar, 2bar, 3bar, seven, diamond(wild)
    [78, 22, 14, 10, 8, 4, 3],
    [82, 10, 14, 10, 8, 4, 2],
    [80, 8, 14, 10, 8, 4, 3]]
def classic_pay(line, coins):
    """returns credits-per-coin * coins (with max-coin bonus on the top award)"""
    w = line.count(DW)
    if w == 3: return {1: 800, 2: 1600, 3: 5000}[coins]
    def match(ok): return all(s in ok or s == DW for s in line)
    m = 2 ** w
    best = 0
    for sym, p in ((S7c, 200), (B3, 100), (B2, 50), (B1, 25)):
        if match((sym,)): best = max(best, p * m)
    if match((B1, B2, B3)): best = max(best, 10 * m)
    ch = 0                            # cherries pay counted from the left reel
    while ch < 3 and line[ch] == CHc: ch += 1
    if ch: best = max(best, {1: 2, 2: 5, 3: 10}[ch])
    return best * coins
def classic():
    tot = {1: 0, 3: 0}; hits = 0; P = 1
    probs = [np.array(w) / sum(w) for w in C_WEIGHTS]
    for a, b, c in itertools.product(range(7), repeat=3):
        pr = probs[0][a] * probs[1][b] * probs[2][c]
        for coins in (1, 3): tot[coins] += pr * classic_pay([a, b, c], coins) / coins
        if classic_pay([a, b, c], 1): hits += pr
    top = np.prod([p[DW] for p in probs])
    print(f"CLASSIC RTP 1 coin {tot[1]:.4f}, 3 coins {tot[3]:.4f} | hit {hits:.3f} | 3 diamonds 1 in {1/top:,.0f}")
    OUT["classic"] = dict(weights=C_WEIGHTS, rtp1=round(tot[1], 4), rtp3=round(tot[3], 4), hit=round(hits, 3), top=round(1 / top))

# ============================================================ GOLD RUSH (243 ways + hold & win coins)
GW, RU, EM, SA, A_, K_, Q_, J_, T_, CO = range(10)
G_PAY = {RU: (30, 80, 250), EM: (25, 60, 200), SA: (20, 50, 150), A_: (10, 25, 60), K_: (10, 25, 60),
         Q_: (7, 16, 40), J_: (7, 16, 40), T_: (7, 15, 30)}   # x bet unit (total bet / 25) for 3/4/5 reels
G_COUNTS = [  # W  Ru Em Sa  A  K  Q  J  T  Coin
    [0, 2, 3, 3, 5, 5, 6, 6, 6, 5],
    [2, 2, 3, 3, 5, 5, 6, 6, 6, 5],
    [2, 2, 3, 3, 5, 5, 6, 6, 6, 5],
    [2, 2, 3, 3, 5, 5, 6, 6, 6, 5],
    [0, 2, 3, 3, 5, 5, 6, 6, 6, 5]]
COIN_V = [1, 2, 3, 5, 10, 20, 50, 200]          # x total bet; 20/50/200 are MINI/MINOR/MAJOR
COIN_W = [380, 250, 150, 100, 60, 35, 20, 5]
RESPIN_P = 0.078                                  # chance each empty cell lands a coin on a respin
GRAND = 1000; TRIGGER = 6
def make_strip(counts, seed, spaced):
    rng = np.random.default_rng(seed)
    for _ in range(50000):
        s = np.repeat(np.arange(len(counts)), counts); rng.shuffle(s); ok = True
        for sym in spaced:
            idx = np.where(s == sym)[0]
            if len(idx) > 1 and np.diff(np.r_[idx, idx[0] + len(s)]).min() < 2: ok = False
        if ok: return s
    raise SystemExit("strip")
def gold(N):
    STR = [make_strip(c, 300 + i, (GW,)) for i, c in enumerate(G_COUNTS)]; L = [len(s) for s in STR]
    rng = np.random.default_rng(5); B = 400_000; ways = 0; hits = 0; trig = 0; hw = 0.0; cw = np.array(COIN_W) / sum(COIN_W)
    for _ in range(N // B):
        g = np.empty((B, 3, 5), np.int8)
        for r in range(5):
            st = rng.integers(0, L[r], B)
            for row in range(3): g[:, row, r] = STR[r][(st + row) % L[r]]
        win = np.zeros(B)
        for sym, p in G_PAY.items():
            mult = np.ones(B); run = np.ones(B, bool); n = np.zeros(B, int)
            for c in range(5):
                k = ((g[:, :, c] == sym) | (g[:, :, c] == GW)).sum(axis=1)
                run &= k > 0; mult = np.where(run, mult * k, mult); n += run
            for k3 in (3, 4, 5):
                win += np.where(n == k3, mult * p[k3 - 3], 0)
        coins = (g == CO).sum(axis=(1, 2))
        ways += win.sum(); hits += ((win > 0) | (coins >= TRIGGER)).sum()
        t = np.where(coins >= TRIGGER)[0]; trig += len(t)
        for i in t:                     # play out each hold & win
            locked = int(coins[i]); total = rng.choice(COIN_V, locked, p=cw).sum(); spins = 3
            while spins and locked < 15:
                new = rng.binomial(15 - locked, RESPIN_P)
                if new: locked += new; total += rng.choice(COIN_V, new, p=cw).sum(); spins = 3
                else: spins -= 1
            if locked >= 15: total += GRAND
            hw += total * 25          # in bet units (total bet = 25 units)
    base = ways / (N * 25); feat = hw / (N * 25)
    print(f"GOLD  ways {base:.4f} + hold&win {feat:.4f} = RTP {base+feat:.4f} | hit {hits/N:.3f} | H&W 1 in {N/max(1,trig):.0f}")
    OUT["gold"] = dict(strips=[s.tolist() for s in STR], rtp=round(base + feat, 4), hit=round(hits / N, 3), hw=round(N / max(1, trig)))

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"; N = int(sys.argv[2]) if len(sys.argv) > 2 else 2_000_000
    if which in ("neon", "all"): neon(N)
    if which in ("classic", "all"): classic()
    if which in ("gold", "all"): gold(N)
    try: old = json.load(open("math3.json"))
    except Exception: old = {}
    old.update(OUT); json.dump(old, open("math3.json", "w"))
