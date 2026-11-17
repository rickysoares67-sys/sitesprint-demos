# Reversion12: the robot that survived testing

## What was tested
- **Data:** `komo135/forex-historical-data`, the same dataset as your F28 backtest.
  12 markets (EURUSD, GBPUSD, USDJPY, USDCHF, USDCAD, AUDUSD, EURGBP, EURCHF, EURJPY, GBPJPY, AUDJPY, XAUUSD), Nov 2012 to Mar 2022.
- **Costs:** realistic spread plus commission on every trade (1.2–4 pips round trip depending on the market).
- **Method:** settings were chosen on **2012–2018 only**, then judged once on **2019–2022**, which they had never seen.
  EURUSD 2022–2026 (Dukascopy) was an extra hold-out.
- **Search:** 5 strategy families and ~140 settings (`research/research2_results.csv`).

## Results on unseen 2019–2022 data
| Strategy | Unseen avg per trade | Verdict |
|---|---|---|
| Trend MA (H4) | −0.017R | failed (looked best in 2012–18) |
| Donchian breakout (D1, H4) | −0.05 to −0.06R | failed |
| RSI(2) mean reversion (H4) | −0.025R | failed |
| **RSI(2) mean reversion (D1)** | **+0.048R, PF 1.41, 8 of 12 markets positive** | **kept** |

## Reversion12 performance (all 12 markets, after costs)
| Period | Trades | Win rate | Avg R | Profit factor | Yearly return @0.5% risk | Worst drop @0.5% | @1% risk return / drop |
|---|---|---|---|---|---|---|---|
| 2012–18 (picked here) | 352 | 65% | +0.029 | 1.21 | 1.0% | 3.2% | 1.9% / 6.4% |
| 2019–22 (unseen) | 225 | 68% | +0.048 | 1.41 | 1.7% | 2.3% | 3.5% / 4.6% |
| EURUSD 2022–26 (hold-out) | 36 | 67% | +0.038 | 1.24 | small sample | | |

The edge is real but small. Expect low single-digit yearly returns at sensible risk, not fast doubling.
Gold (XAUUSD), GBPJPY and USDCAD lost money in the test. Consider removing them from `InpSymbols`.

## Use
1. Copy `PipCraft_Reversion12_EA.mq5` to MT5 `MQL5/Experts`, compile it in MetaEditor (F7), and fix anything flagged. It has not been compiled here.
2. Attach it to **one** chart; it trades every symbol in `InpSymbols` on daily bars. Set `InpSuffix` if your broker adds one (e.g. `.m`).
3. Backtest it in the Strategy Tester (multi-currency, daily, real ticks), then run it on a **demo account for at least 2–3 months**.
4. Default risk is 0.5% per trade, with a 3% cap on total open risk and new trades paused after a 15% drop from the equity peak.
