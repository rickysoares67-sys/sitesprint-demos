# PipCraft Tools: forex products to sell on Etsy

Nine ready-to-list digital products for forex traders, with Etsy listing copy written for each.

| # | Product | File | Suggested price |
|---|---------|------|-----------------|
| 1 | Trend Cloud indicator (MT5) | `indicators/PipCraft_TrendCloud.mq5` | $14.99 |
| 2 | Session Boxes indicator (MT5) | `indicators/PipCraft_SessionBoxes.mq5` | $9.99 |
| 3 | Lot Size Calculator (MT5) | `indicators/PipCraft_LotSizeCalculator.mq5` | $9.99 |
| 4 | TrendRider EA (robot) | `robots/PipCraft_TrendRider_EA.mq5` | $39.99 |
| 5 | Asian Breakout EA (robot) | `robots/PipCraft_AsianBreakout_EA.mq5` | $34.99 |
| 6 | Trade Manager EA | `robots/PipCraft_TradeManager_EA.mq5` | $19.99 |
| 7 | Trading Journal spreadsheet | `tools/PipCraft_Forex_Trading_Journal.xlsx` | $7.99 |
| 8 | Cheat sheet (2-page PDF) | `tools/PipCraft_Forex_Cheat_Sheet.pdf` | $4.99 |
| 9 | Bundle of all the above | `dist/PipCraft_Complete_Forex_Toolkit.zip` | $99.99 |

- `dist/` holds the ZIPs to upload to each Etsy listing. Rebuild them with `./build_zips.sh` after any change.
- `listings/ETSY_LISTINGS.md` has the title, 13 tags, description and price for every listing.
- `tools/PipCraft_Install_Guide.pdf` and `LICENSE_BUYER.txt` go inside every ZIP.

## Before you list (important)
1. **Compile each .mq5 in MetaEditor** (MT5 → F4 → open the file → F7). Fix anything it flags.
   These files have not been compiled yet because MetaTrader doesn't run on this server.
2. **Backtest the robots** in the Strategy Tester and run them on a demo account.
   Use the screenshots for your listing photos. Never post profit claims.
3. Optional: sell the compiled `.ex5` instead of `.mq5` if you don't want buyers to see the source code.
   Then add `.ex5` to the ZIPs in `build_zips.sh`.
4. Rename "PipCraft" everywhere if you want a different shop name (`grep -r PipCraft`).
