"""Combine the three weakly positive sleeves at equal risk and report honest walk-forward stats.
python3 -I combine.py  -> combined_daily.csv, combined_stats.json"""
import json, numpy as np, pandas as pd
book = pd.read_pickle("research3_book.pkl")
wr = book["Weekly reversal"][1]            # all-settings blend (no selection)
dw = book["Day of week"][0]                # walk-forward
t = pd.read_csv("walkforward_trades.csv", parse_dates=["entry_time", "exit_time"])
rv = t.groupby(t.exit_time.dt.normalize()).R.sum()
idx = wr.index[(wr.index >= "2016-01-01") & (wr.index < "2022-03-05")]
sl = pd.DataFrame({"Reversion12": rv.reindex(idx).fillna(0), "Weekly reversal": wr.reindex(idx).fillna(0),
                   "Day of week": dw.reindex(idx).fillna(0)})
TARGET = 0.10 / np.sqrt(252)                 # each sleeve scaled to 10% yearly volatility, then averaged
# scale with TRAILING volatility only (expanding window, min 120 days) so no future info leaks in
scaled = sl.apply(lambda s: s * (TARGET / s.expanding(120).std().shift()).clip(upper=50)).fillna(0)
port = scaled.mean(axis=1)
def st(p):
    eq = (1 + p).cumprod(); yrs = len(p) / 252; dd = (1 - eq / eq.cummax()).max()
    return dict(cagr=round(eq.iloc[-1] ** (1 / yrs) - 1, 4), vol=round(p.std() * np.sqrt(252), 4),
                sharpe=round(p.mean() / p.std() * np.sqrt(252), 2), maxdd=round(dd, 3),
                t=round(p.mean() / p.std() * np.sqrt(len(p)), 2), pos_years=int((p.groupby(p.index.year).sum() > 0).sum()),
                years=int(p.index.year.nunique()))
out = {k: st(scaled[k]) for k in scaled} | {"Combined": st(port)}
print(pd.DataFrame(out).T.to_string())
print("\nsleeve correlations:\n", scaled.corr().round(2).to_string())
print("\nCombined by year:", (port.groupby(port.index.year).sum() * 100).round(1).to_dict())
eq = (1 + port).cumprod(); pd.DataFrame({"equity": eq, **{k: (1 + scaled[k]).cumprod() for k in scaled}}).to_csv("combined_daily.csv")
json.dump({"stats": out, "years": (port.groupby(port.index.year).sum()).round(4).to_dict()}, open("combined_stats.json", "w"), indent=1, default=str)
