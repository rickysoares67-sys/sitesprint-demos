"""Steps 1-3: walk-forward, market selection, Monte Carlo for Reversion12.
python3 -I walkforward.py DATA_DIR
Every year from 2015 to 2022, settings (and optionally markets) are chosen using
ONLY the data before that year, then traded on that year. Stitching those years
together gives a track record the bot could really have produced."""
import sys, os, itertools, json, numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from engine import atr, run
import research2 as R2  # reuses loader, costs, rsi (research2 runs nothing when imported with no strategy list)

HERE = os.path.dirname(os.path.abspath(__file__))
GRID = list(itertools.product([5, 10, 15], [3, 4, 5], [5, 10], [5, 10]))   # rsi_low, stop_atr, exit_ma, max_days
YEARS = list(range(2015, 2023))                                             # traded years (2022 = Jan-Mar)

def trades(sym, p, cost_mult=1.0):
    df = R2.load(sym, "d1"); c = df.close; a = atr(df); r = R2.rsi(c, 2)
    tr = c.rolling(200).mean(); m = c.rolling(p[2]).mean()
    t = run(df, (r < p[0]) & (c > tr), (r > 100 - p[0]) & (c < tr), p[1] * a, R2.COST[sym] * R2.PIP(sym) * cost_mult,
            exit_long=c > m, exit_short=c < m, max_bars=p[3])
    t["sym"] = sym; return t

print("building trade lists...", flush=True)
ALL = {(s, p): trades(s, p) for s in R2.SYMS for p in GRID}
ALL2 = {(s, p): trades(s, p, 2.0) for s in R2.SYMS for p in GRID}        # double costs, for stress tests

def wf(select_markets, book=ALL):
    out, log = [], []
    for y in YEARS:
        lo, hi = pd.Timestamp(f"{y}-01-01"), pd.Timestamp(f"{y+1}-01-01")
        best, bestR = None, -9
        for p in GRID:                                   # settings: best average R across markets, pre-year data only
            past = pd.concat([ALL[(s, p)] for s in R2.SYMS]); past = past[past.exit_time < lo]
            if len(past) >= 150 and past.R.mean() > bestR: best, bestR = p, past.R.mean()
        mk = R2.SYMS
        if select_markets:                              # drop markets whose own pre-year record is negative
            mk = [s for s in R2.SYMS if ALL[(s, best)].pipe(lambda t: t[t.exit_time < lo]).R.mean() > 0]
        yr = pd.concat([book[(s, best)] for s in mk]); yr = yr[(yr.entry_time >= lo) & (yr.entry_time < hi)]
        out.append(yr); log.append(dict(year=y, settings=best, markets=len(mk), dropped=[s for s in R2.SYMS if s not in mk],
                                         trades=len(yr), avgR=round(yr.R.mean(), 3) if len(yr) else 0, totR=round(yr.R.sum(), 1)))
    return pd.concat(out).sort_values("exit_time"), log

def summary(t, risk):
    R = t.R.values; eq = np.cumprod(1 + risk * R); pk = np.maximum.accumulate(np.r_[1, eq])[1:]
    yrs = (t.exit_time.iloc[-1] - t.entry_time.iloc[0]).days / 365.25
    gp, gl = R[R > 0].sum(), -R[R < 0].sum()
    return dict(trades=len(R), win=round((R > 0).mean(), 3), avgR=round(R.mean(), 3), pf=round(gp / gl, 2),
                cagr=round(eq[-1] ** (1 / yrs) - 1, 4), maxdd=round(((pk - eq) / pk).max(), 3), tstat=round(R.mean() / R.std() * np.sqrt(len(R)), 2))

res = {}
for name, sel in (("all markets", False), ("market selection", True)):
    t, log = wf(sel); res[name] = (t, log)
    print(f"\n=== Walk-forward: {name} ===")
    print(pd.DataFrame(log).to_string(index=False))
    for risk in (0.005, 0.01): print(f"  risk {risk:.1%}:", summary(t, risk))
    t2, _ = wf(sel, ALL2); print("  DOUBLE costs, 1%:", summary(t2, 0.01))

# ---------------- Monte Carlo on the walk-forward trades (double costs = stress case)
choice = max(res, key=lambda k: summary(res[k][0], 0.01)["avgR"])
t2, _ = wf(choice == "market selection", ALL2); R = t2.R.values
yrs = (t2.exit_time.iloc[-1] - t2.entry_time.iloc[0]).days / 365.25; per_year = len(R) / yrs
rng = np.random.default_rng(42); N = 20000; H = int(per_year * 3)
print(f"\n=== Monte Carlo: {choice}, DOUBLE costs, {N} shuffled 3-year paths ({per_year:.0f} trades/yr) ===")
mc = {}
for risk in (0.0025, 0.005, 0.0075, 0.01, 0.015, 0.02):
    x = rng.choice(R, (N, H)); eq = np.cumprod(1 + risk * x, axis=1); pk = np.maximum.accumulate(np.concatenate([np.ones((N, 1)), eq], 1), 1)[:, 1:]
    dd = ((pk - eq) / pk).max(1); fin = eq[:, -1]
    mc[risk] = dict(median_3y_return=round(np.median(fin) - 1, 3), p5_3y_return=round(np.percentile(fin, 5) - 1, 3),
                    median_maxdd=round(np.median(dd), 3), p95_maxdd=round(np.percentile(dd, 95), 3), p_loss_3y=round((fin < 1).mean(), 3))
    print(f"  risk {risk:.2%}:", mc[risk])
json.dump({"choice": choice, "logs": {k: v[1] for k, v in res.items()},
           "summary": {k: summary(v[0], 0.01) for k, v in res.items()}, "mc": {str(k): v for k, v in mc.items()}},
          open(f"{HERE}/walkforward_results.json", "w"), default=str, indent=1)
pd.concat([res[choice][0].assign(scenario="base")]).to_csv(f"{HERE}/walkforward_trades.csv", index=False)
