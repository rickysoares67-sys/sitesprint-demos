"""Step 4: odds of passing an FTMO-style challenge (+10% target, -5% daily, -10% overall, 12-month cap)
by resampling the walk-forward trades day by day. python3 -I propsim.py"""
import numpy as np, pandas as pd
t = pd.read_csv("walkforward_trades.csv", parse_dates=["entry_time", "exit_time"])
t["day"] = t.exit_time.dt.normalize()
days = pd.date_range(t.day.min(), t.day.max(), freq="B")
daily = [t[t.day == d].R.values for d in days]          # trades closing each business day (most days: none)
rng = np.random.default_rng(7)
for risk in (0.005, 0.01, 0.015, 0.02):
    res = {"pass": 0, "fail": 0, "timeout": 0}; tdays = []
    for _ in range(20000):
        bal = 1.0
        for k in range(252):
            day_r = daily[rng.integers(len(daily))]
            start = bal; bal *= np.prod(1 + risk * day_r) if len(day_r) else 1
            if bal <= 0.90 or bal <= start * 0.95: res["fail"] += 1; break
            if bal >= 1.10: res["pass"] += 1; tdays.append(k + 1); break
        else: res["timeout"] += 1
    n = sum(res.values())
    print(f"risk {risk:.1%}: pass {res['pass']/n:.1%}  fail {res['fail']/n:.1%}  not done in 12 months {res['timeout']/n:.1%}"
          + (f"  median days to pass {int(np.median(tdays))}" if tdays else ""))
