"""12-market strategy research. Select on 2012-2018 (IS), judge on 2019-2022 (OOS).
python3 -I research2.py DATA_DIR"""
import sys, os, itertools, numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from engine import atr, run, stats

D = sys.argv[1] if len(sys.argv) > 1 else "/home/user/komo135/forex-historical-data"
SYMS = ["EURUSD", "GBPUSD", "USDJPY", "USDCHF", "USDCAD", "AUDUSD", "EURGBP", "EURCHF", "EURJPY", "GBPJPY", "AUDJPY", "XAUUSD"]
SCALE = lambda s: 100 if s == "XAUUSD" else (1000 if "JPY" in s else 1e5)
PIP = lambda s: 0.1 if s == "XAUUSD" else (0.01 if "JPY" in s else 1e-4)
COST = {"EURUSD": 1.2, "GBPUSD": 1.6, "USDJPY": 1.4, "USDCHF": 1.8, "USDCAD": 1.8, "AUDUSD": 1.5, "EURGBP": 1.8,
        "EURCHF": 2.2, "EURJPY": 2.0, "GBPJPY": 3.0, "AUDJPY": 2.4, "XAUUSD": 4.0}   # round trip, pips
IS_END, OOS_END = pd.Timestamp("2019-01-01"), pd.Timestamp("2022-03-05")
TF = {"h1": "h1", "h4": "h4", "d1": "d1"}
CACHE = {}
def load(s, tf):
    if (s, tf) in CACHE: return CACHE[(s, tf)]
    df = pd.read_csv(f"{D}/{s}/{s}{tf}.csv", parse_dates=["Date"], index_col="Date")
    df = df.rename(columns={"tick_volume": "volume"})
    for c in ("open", "high", "low", "close"): df[c] = df[c] / SCALE(s)
    df = df[~df.index.duplicated()].sort_index()
    CACHE[(s, tf)] = df; return df
def rsi(c, n):
    d = c.diff(); up = d.clip(lower=0).ewm(alpha=1/n, adjust=False).mean(); dn = (-d.clip(upper=0)).ewm(alpha=1/n, adjust=False).mean()
    return 100 - 100 / (1 + up / dn)

# ------------------------------------------------------------------ strategies
def trend_ma(df, cost, fast, slow, sl, trail):
    c = df.close; a = atr(df); f, s_, t = c.ewm(span=fast).mean(), c.ewm(span=slow).mean(), c.ewm(span=200).mean()
    up = (f > s_) & (f.shift() <= s_.shift()); dn = (f < s_) & (f.shift() >= s_.shift())
    return run(df, up & (c > t), dn & (c < t), sl * a, cost, trail_atr=None if not trail else trail * a)
def donchian(df, cost, n, m, sl):
    c = df.close; a = atr(df, 20)
    hh = df.high.rolling(n).max().shift(); ll = df.low.rolling(n).min().shift()
    xh = df.high.rolling(m).max().shift(); xl = df.low.rolling(m).min().shift()
    return run(df, c > hh, c < ll, sl * a, cost, exit_long=c < xl, exit_short=c > xh)
def meanrev(df, cost, lo, sl, ma, maxb):
    c = df.close; a = atr(df); r = rsi(c, 2); trend = c.rolling(200).mean(); m = c.rolling(ma).mean()
    return run(df, (r < lo) & (c > trend), (r > 100 - lo) & (c < trend), sl * a, cost,
               exit_long=c > m, exit_short=c < m, max_bars=maxb)
def bollrev(df, cost, n, k, sl, maxb):
    c = df.close; a = atr(df); m = c.rolling(n).mean(); sd = c.rolling(n).std(); trend = c.rolling(200).mean()
    return run(df, (c < m - k * sd) & (c > trend), (c > m + k * sd) & (c < trend), sl * a, cost,
               exit_long=c > m, exit_short=c < m, max_bars=maxb)

STRATS = {
 "Trend MA H4":    ("h4", trend_ma, list(itertools.product([10, 20, 50], [30, 50, 100], [1.5, 2.5, 3.5], [0, 3]))),
 "Donchian D1":    ("d1", donchian, [(n, m, sl) for n in (20, 55, 100) for m in (10, 20, 50) for sl in (2, 3) if m < n]),
 "Donchian H4":    ("h4", donchian, [(n, m, sl) for n in (55, 100, 200) for m in (20, 50, 100) for sl in (2, 3) if m < n]),
 "MeanRev RSI2 H4":("h4", meanrev, list(itertools.product([5, 10, 15], [2, 3, 4], [5, 10], [6, 12]))),
 "MeanRev RSI2 D1":("d1", meanrev, list(itertools.product([5, 10, 15], [2, 3, 4], [5, 10], [5, 10]))),
 "Bollinger H1":   ("h1", bollrev, list(itertools.product([20, 50], [2.0, 2.5], [2, 3], [12, 24]))),
}
STRATS = {k: v for k, v in STRATS.items() if len(sys.argv) < 3 or k in sys.argv[2].split(",")}
if __name__ == "__main__":
    rows = []; TRADES = {}
    for name, (tf, fn, grid) in STRATS.items():
        for p in grid:
            if fn is trend_ma and p[0] >= p[1]: continue
            per = {}
            for s in SYMS:
                df = load(s, tf); t = fn(df, COST[s] * PIP(s), *p); t["sym"] = s; per[s] = t
            T = pd.concat(per.values()).sort_values("entry_time")
            ins, oos = T[T.entry_time < IS_END], T[(T.entry_time >= IS_END) & (T.entry_time < OOS_END)]
            si, so = stats(ins, 0.005), stats(oos, 0.005)
            mis = sum(stats(v[v.entry_time < IS_END])["avgR"] > 0 for v in per.values())
            moos = sum(stats(v[(v.entry_time >= IS_END) & (v.entry_time < OOS_END)])["avgR"] > 0 for v in per.values())
            rows.append(dict(strat=name, p=str(p), is_n=si["trades"], is_R=si["avgR"], is_pf=si["pf"], is_mk=mis,
                             oos_n=so["trades"], oos_R=so["avgR"], oos_pf=so["pf"], oos_mk=moos, oos_cagr=so["cagr"], oos_dd=so["maxdd"]))
            TRADES[(name, str(p))] = T
        print("done", name, flush=True)
    R = pd.DataFrame(rows); R.to_csv(f"{os.path.dirname(os.path.abspath(__file__))}/research2_results.csv", index=False)
    pd.set_option("display.width", 250); pd.set_option("display.max_columns", 30)
    print("\n=== Settings chosen on 2012-2018 only (most robust: positive in most markets, then best avg R) ===")
    best = R[R.is_n >= 300].sort_values(["is_mk", "is_R"], ascending=False).groupby("strat").head(1)
    print(best.to_string(index=False))
    print("\n=== Every setting, judged on unseen 2019-2022 ===")
    print(R.groupby("strat").agg(n=("oos_R", "size"), share_pos_oos=("oos_R", lambda x: round((x > 0).mean(), 2)),
          med_oos_R=("oos_R", "median"), med_is_R=("is_R", "median"), best_oos_R=("oos_R", "max")).to_string())
    import pickle; pickle.dump({k: v for k, v in TRADES.items() if (k[0], k[1]) in set(zip(best.strat, best.p))},
                               open(f"{os.path.dirname(os.path.abspath(__file__))}/best_trades.pkl", "wb"))
