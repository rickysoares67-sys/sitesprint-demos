"""New-bot research: portfolio strategies across 12 markets on daily bars, all judged walk-forward.
python3 -I research3.py
Positions are sized in volatility units: 1 unit moves 1 x ATR(20) per ATR move, so every market counts the same.
Costs are charged on every change of position (half the round-trip cost per side)."""
import sys, os, itertools, json, numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import research2 as R2

S = R2.SYMS
def panel():
    C, H, L = {}, {}, {}
    for s in S:
        d = R2.load(s, "d1"); d = d[d.index.dayofweek < 5]
        C[s], H[s], L[s] = d.close, d.high, d.low
    C, H, L = pd.DataFrame(C), pd.DataFrame(H), pd.DataFrame(L)
    C = C[C.index >= "2013-01-01"].ffill(limit=3); H = H.reindex(C.index).ffill(limit=3); L = L.reindex(C.index).ffill(limit=3)
    tr = pd.concat({s: pd.concat([H[s] - L[s], (H[s] - C[s].shift()).abs(), (L[s] - C[s].shift()).abs()], axis=1).max(axis=1) for s in S}, axis=1)
    atr = tr.ewm(alpha=1/20, adjust=False).mean()
    return C, atr
C, ATR = panel()
RET = C.diff() / ATR.shift()                            # next-day move in ATR units
COSTU = pd.DataFrame({s: (R2.COST[s] * R2.PIP(s) / 2) / ATR[s] for s in S})   # one-side cost in ATR units
FRI = C.index.dayofweek == 4

def backtest(W):
    """W: target positions (vol units) decided at each close. Returns daily PnL in vol units."""
    W = W.reindex(C.index).fillna(0)
    pnl = (W.shift() * RET).sum(axis=1) - (W.diff().abs() * COSTU).sum(axis=1)
    return pnl.fillna(0)

def weekly(fn):
    """Recompute target only on Fridays, hold through the week."""
    W = pd.DataFrame(np.nan, index=C.index, columns=S)
    for d in C.index[FRI]: W.loc[d] = fn(d)
    return W.ffill().fillna(0)

# ---------------------------------------------------------------- strategy families
def xs_rank(score, k):
    def f(d):
        sc = score.loc[d].dropna()
        w = pd.Series(0.0, index=S)
        if len(sc) >= 2 * k:
            o = sc.sort_values(); w[o.index[:k]] = -1; w[o.index[-k:]] = 1
        return w
    return f
FAM = {}
FAM["Weekly reversal"] = {(L, k): weekly(xs_rank(-(C - C.shift(L)) / ATR, k)) for L in (5, 10, 20) for k in (2, 3, 4)}
FAM["Cross-market momentum"] = {(L, k): weekly(xs_rank((C - C.shift(L)) / (ATR * np.sqrt(L)), k)) for L in (20, 60, 120, 250) for k in (2, 3, 4)}
FAM["Trend (vol-sized)"] = {(L,): weekly(lambda d, L=L: np.sign((C - C.shift(L)).loc[d]).fillna(0)) for L in (20, 60, 120, 250)}
FAM["Trend (vol-sized)"][("blend",)] = sum(FAM["Trend (vol-sized)"][(L,)] for L in (20, 60, 120, 250)) / 4
# day-of-week: trailing 3-year weekday mean per market; trade only |t|>2 combos, one day long/short
def dow_weights(min_t):
    W = pd.DataFrame(0.0, index=C.index, columns=S); dow = C.index.dayofweek
    for y in range(2016, 2023):
        lo, hi = pd.Timestamp(f"{y-3}-01-01"), pd.Timestamp(f"{y}-01-01")
        past = RET[(RET.index >= lo) & (RET.index < hi)]
        rows = (C.index >= hi) & (C.index < pd.Timestamp(f"{y+1}-01-01"))
        for wd in range(5):
            x = past[past.index.dayofweek == wd]; t = x.mean() / x.std() * np.sqrt(x.count())
            sig = np.sign(t).where(t.abs() > min_t, 0)
            # position for weekday wd is held over the day wd: decided at the previous close
            prev = rows & (dow == (wd - 1) % 5)
            W.loc[prev] = sig.values
    return W
FAM["Day of week"] = {(t,): dow_weights(t) for t in (1.5, 2.0, 2.5)}

def sharpe(p):
    return p.mean() / p.std() * np.sqrt(252) if p.std() > 0 else 0

YEARS = range(2016, 2023)
def walkforward(fam):
    pn = {k: backtest(W) for k, W in fam.items()}
    out, picks = [], []
    for y in YEARS:
        lo, hi = pd.Timestamp(f"{y}-01-01"), pd.Timestamp(f"{y+1}-01-01")
        best = max(pn, key=lambda k: sharpe(pn[k][pn[k].index < lo]))
        picks.append((y, best)); out.append(pn[best][(pn[best].index >= lo) & (pn[best].index < hi)])
    wf = pd.concat(out)
    blend = sum(pn.values()) / len(pn); blend = blend[blend.index >= "2016-01-01"]   # no selection at all
    return wf, blend, picks, pn

def report(name, p):
    yrs = p.groupby(p.index.year).sum()
    t = p.mean() / p.std() * np.sqrt(len(p))
    return dict(strategy=name, sharpe=round(sharpe(p), 2), t=round(t, 2), pos_years=f"{(yrs > 0).sum()}/{len(yrs)}",
                by_year=" ".join(f"{v:+.0f}" for v in yrs.values))

rows, BOOK = [], {}
for name, fam in FAM.items():
    wf, blend, picks, pn = walkforward(fam)
    BOOK[name] = (wf, blend)
    rows.append(report(name + " | walk-forward", wf)); rows.append(report(name + " | all settings blended", blend))
    print(name, "picks:", picks, flush=True)
pd.set_option("display.width", 250); pd.set_option("display.max_colwidth", 80)
print("\n=== 2016-2022, after costs (yearly P&L in vol units; Sharpe is scale-free) ===")
print(pd.DataFrame(rows).to_string(index=False))
pd.to_pickle(BOOK, os.path.join(os.path.dirname(os.path.abspath(__file__)), "research3_book.pkl"))
