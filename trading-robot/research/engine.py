"""Small, honest bar-by-bar backtester.
- One position at a time per market.
- Signals are computed on a CLOSED bar and filled at the NEXT bar's open.
- Stops/targets are checked intrabar with high/low; if both are hit in the
  same bar we assume the STOP was hit first (pessimistic).
- Gaps through a stop fill at the open (worse price).
- Round-trip cost (spread + commission + slippage) is charged on every trade.
Results are in R (multiples of the initial risk) so markets are comparable;
equity is simulated with fixed-fractional risk per trade.
"""
import numpy as np, pandas as pd

PIP = {"EURUSD": 1e-4, "GBPUSD": 1e-4, "USDJPY": 1e-2, "XAUUSD": 0.1}
# realistic round-trip cost in pips: raw spread + $7/lot commission + slippage
COST_PIPS = {"EURUSD": 1.2, "GBPUSD": 1.6, "USDJPY": 1.4, "XAUUSD": 4.0}


def load(path, tf="1h"):
    df = pd.read_csv(path, parse_dates=["time"], index_col="time")
    if tf != "1h":
        df = df.resample(tf).agg({"open": "first", "high": "max", "low": "min",
                                  "close": "last", "volume": "sum"}).dropna()
    return df


def atr(df, n=14):
    h, l, c = df.high, df.low, df.close
    tr = pd.concat([h - l, (h - c.shift()).abs(), (l - c.shift()).abs()], axis=1).max(axis=1)
    return tr.ewm(alpha=1 / n, adjust=False).mean()


def run(df, long_sig, short_sig, stop_dist, cost, tp_r=0.0, trail_atr=None,
        exit_long=None, exit_short=None, max_bars=0):
    """long_sig/short_sig/exit_*: bool arrays evaluated at bar close.
    stop_dist: price distance of the initial stop (array).
    tp_r: take profit in R (0 = none). trail_atr: array of trailing distances or None."""
    o, h, l, c = (df[k].values for k in ("open", "high", "low", "close"))
    n = len(c)
    ls = np.asarray(long_sig, bool); ss = np.asarray(short_sig, bool)
    sd = np.asarray(stop_dist, float)
    el = np.zeros(n, bool) if exit_long is None else np.asarray(exit_long, bool)
    es = np.zeros(n, bool) if exit_short is None else np.asarray(exit_short, bool)
    tr = None if trail_atr is None else np.asarray(trail_atr, float)
    trades = []  # (entry_time, exit_time, dir, R)
    pos = 0; entry = stop = tp = risk = 0.0; ei = 0
    pending = 0; pend_sd = 0.0; pend_exit = False
    for i in range(1, n):
        # ---- fills at this bar's open
        if pos != 0 and pend_exit:
            px = o[i]
            trades.append((ei, i, pos, (pos * (px - entry) - cost) / risk)); pos = 0
        pend_exit = False
        if pos == 0 and pending != 0 and pend_sd > 0:
            pos = pending; entry = o[i]; risk = pend_sd; ei = i
            stop = entry - pos * risk
            tp = entry + pos * risk * tp_r if tp_r > 0 else 0.0
        pending = 0
        # ---- intrabar stop / target
        if pos != 0:
            if pos == 1:
                hit_s = l[i] <= stop; hit_t = tp > 0 and h[i] >= tp
                if hit_s:
                    px = min(stop, o[i]) if o[i] < stop else stop
                    trades.append((ei, i, 1, (px - entry - cost) / risk)); pos = 0
                elif hit_t:
                    px = max(tp, o[i]) if i > ei and o[i] > tp else tp
                    trades.append((ei, i, 1, (px - entry - cost) / risk)); pos = 0
            else:
                hit_s = h[i] >= stop; hit_t = tp > 0 and l[i] <= tp
                if hit_s:
                    px = max(stop, o[i]) if o[i] > stop else stop
                    trades.append((ei, i, -1, (entry - px - cost) / risk)); pos = 0
                elif hit_t:
                    px = min(tp, o[i]) if i > ei and o[i] < tp else tp
                    trades.append((ei, i, -1, (entry - px - cost) / risk)); pos = 0
        # ---- end-of-bar management
        if pos != 0:
            if tr is not None and tr[i] > 0:
                if pos == 1: stop = max(stop, c[i] - tr[i])
                else:        stop = min(stop, c[i] + tr[i])
            if (pos == 1 and el[i]) or (pos == -1 and es[i]) or \
               (max_bars and i - ei >= max_bars):
                pend_exit = True
            if (pos == 1 and ss[i]) or (pos == -1 and ls[i]):
                pend_exit = True  # reverse handled next bar after exit
        if pos == 0 or pend_exit:
            if ls[i] and not ss[i]: pending, pend_sd = 1, sd[i]
            elif ss[i] and not ls[i]: pending, pend_sd = -1, sd[i]
    if pos != 0:
        trades.append((ei, n - 1, pos, (pos * (c[-1] - entry) - cost) / risk))
    t = pd.DataFrame(trades, columns=["ei", "xi", "dir", "R"])
    if len(t):
        t["entry_time"] = df.index[t.ei]; t["exit_time"] = df.index[t.xi]
    return t


def stats(t, risk=0.01, years=None):
    if len(t) == 0:
        return dict(trades=0, win=0, avgR=0, pf=0, totR=0, maxddR=0, cagr=0, maxdd=0)
    R = t.R.values
    eqR = np.cumsum(R); ddR = (np.maximum.accumulate(np.r_[0, eqR])[1:] - eqR).max()
    eq = np.cumprod(1 + risk * R); peak = np.maximum.accumulate(np.r_[1, eq])[1:]
    dd = ((peak - eq) / peak).max()
    gp, gl = R[R > 0].sum(), -R[R < 0].sum()
    if years is None:
        years = max((t.exit_time.iloc[-1] - t.entry_time.iloc[0]).days / 365.25, 0.1)
    return dict(trades=len(R), win=round((R > 0).mean(), 3), avgR=round(R.mean(), 3),
                pf=round(gp / gl, 2) if gl > 0 else 99, totR=round(R.sum(), 1),
                maxddR=round(ddR, 1), cagr=round(eq[-1] ** (1 / years) - 1, 4),
                maxdd=round(dd, 3))
