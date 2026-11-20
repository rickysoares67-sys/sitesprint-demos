//+------------------------------------------------------------------+
//|                                    PipCraft_DataExtractor.mq5    |
//|  SCRIPT: exports price history, symbol specs (swaps, costs) and  |
//|  your real commissions to MQL5/Files/PipCraft_Export/ so it can  |
//|  be zipped and uploaded for strategy research.                   |
//|                                                                  |
//|  Install: copy to MQL5/Scripts, compile (F7), then drag it onto  |
//|  any chart. Open the folder with File > Open Data Folder >       |
//|  MQL5 > Files > PipCraft_Export.                                 |
//+------------------------------------------------------------------+
#property copyright "PipCraft Tools"
#property version   "1.00"
#property script_show_inputs

input bool   InpAllMarketWatch = true;   // Export every symbol in Market Watch
input string InpSymbols = "US30,US500,NAS100,GER40,UK100,JPN225,XAUUSD,XAGUSD,USOIL,UKOIL,NGAS,BTCUSD,ETHUSD,EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,USDCHF,NZDUSD"; // Used when the option above is false
input bool   InpD1 = true;               // Export daily bars (all available history)
input bool   InpH1 = true;               // Export 1-hour bars
input int    InpH1Years = 6;             // ...for this many years back
input bool   InpM15 = false;             // Export 15-minute bars (large files)
input int    InpM15Years = 2;            // ...for this many years back
input int    InpDealYears = 3;           // Read this many years of your trade history for real costs

const string DIR = "PipCraft_Export\\";

int ExportBars(const string s, ENUM_TIMEFRAMES tf, const string tfName, datetime from)
  {
   // ask the terminal to download history, then copy it
   MqlRates r[]; ArraySetAsSeries(r, false);
   int n = -1;
   for(int attempt = 0; attempt < 10 && n <= 0; attempt++)
     {
      n = CopyRates(s, tf, from, TimeCurrent(), r);
      if(n <= 0) Sleep(500);
     }
   if(n <= 0) { PrintFormat("  %s %s: no data (%d)", s, tfName, GetLastError()); return(0); }
   int h = FileOpen(DIR + s + "_" + tfName + ".csv", FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(h == INVALID_HANDLE) { PrintFormat("  cannot write %s %s", s, tfName); return(0); }
   FileWrite(h, "time", "open", "high", "low", "close", "tick_volume", "spread_points");
   int dg = (int)SymbolInfoInteger(s, SYMBOL_DIGITS);
   for(int i = 0; i < n; i++)
      FileWrite(h, TimeToString(r[i].time, TIME_DATE|TIME_MINUTES), DoubleToString(r[i].open, dg), DoubleToString(r[i].high, dg),
                DoubleToString(r[i].low, dg), DoubleToString(r[i].close, dg), (string)r[i].tick_volume, (string)r[i].spread);
   FileClose(h);
   return(n);
  }

void OnStart()
  {
   string list[];
   if(InpAllMarketWatch)
     {
      int t = SymbolsTotal(true); ArrayResize(list, t);
      for(int i = 0; i < t; i++) list[i] = SymbolName(i, true);
     }
   else
     {
      string p[]; int n = StringSplit(InpSymbols, ',', p); ArrayResize(list, 0);
      for(int i = 0; i < n; i++)
        {
         string s = p[i]; StringTrimLeft(s); StringTrimRight(s);
         if(s != "" && SymbolSelect(s, true)) { int k = ArraySize(list); ArrayResize(list, k + 1); list[k] = s; }
         else if(s != "") PrintFormat("Not at this broker: %s (check the exact name in Market Watch)", s);
        }
     }
   int total = ArraySize(list);
   if(total == 0) { Alert("No symbols to export."); return; }

   // ---------- symbol specifications: costs, swaps, sizes, trading hours
   int hs = FileOpen(DIR + "symbols_spec.csv", FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   FileWrite(hs, "symbol", "description", "path", "currency_profit", "digits", "point", "tick_size", "tick_value", "contract_size",
             "volume_min", "volume_step", "spread_now_points", "spread_float", "stops_level", "swap_mode", "swap_long", "swap_short",
             "swap_3day", "margin_initial", "trade_mode", "calc_mode");
   datetime now = TimeCurrent();
   for(int i = 0; i < total; i++)
     {
      string s = list[i]; SymbolSelect(s, true);
      FileWrite(hs, s, SymbolInfoString(s, SYMBOL_DESCRIPTION), SymbolInfoString(s, SYMBOL_PATH), SymbolInfoString(s, SYMBOL_CURRENCY_PROFIT),
                (string)SymbolInfoInteger(s, SYMBOL_DIGITS), DoubleToString(SymbolInfoDouble(s, SYMBOL_POINT), 10),
                DoubleToString(SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE), 10), DoubleToString(SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE), 6),
                DoubleToString(SymbolInfoDouble(s, SYMBOL_TRADE_CONTRACT_SIZE), 2), DoubleToString(SymbolInfoDouble(s, SYMBOL_VOLUME_MIN), 4),
                DoubleToString(SymbolInfoDouble(s, SYMBOL_VOLUME_STEP), 4), (string)SymbolInfoInteger(s, SYMBOL_SPREAD),
                (string)SymbolInfoInteger(s, SYMBOL_SPREAD_FLOAT), (string)SymbolInfoInteger(s, SYMBOL_TRADE_STOPS_LEVEL),
                EnumToString((ENUM_SYMBOL_SWAP_MODE)SymbolInfoInteger(s, SYMBOL_SWAP_MODE)), DoubleToString(SymbolInfoDouble(s, SYMBOL_SWAP_LONG), 4),
                DoubleToString(SymbolInfoDouble(s, SYMBOL_SWAP_SHORT), 4), EnumToString((ENUM_DAY_OF_WEEK)SymbolInfoInteger(s, SYMBOL_SWAP_ROLLOVER3DAYS)),
                DoubleToString(SymbolInfoDouble(s, SYMBOL_MARGIN_INITIAL), 2), EnumToString((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(s, SYMBOL_TRADE_MODE)),
                EnumToString((ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(s, SYMBOL_TRADE_CALC_MODE)));
     }
   FileClose(hs);

   // ---------- your real costs: commission & swap per deal (no personal account details are written)
   if(InpDealYears > 0 && HistorySelect(now - InpDealYears * 365 * 86400, now))
     {
      int hd = FileOpen(DIR + "my_deal_costs.csv", FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
      FileWrite(hd, "time", "symbol", "type", "entry", "volume", "price", "commission", "swap", "fee", "profit");
      int nd = HistoryDealsTotal();
      for(int i = 0; i < nd; i++)
        {
         ulong t = HistoryDealGetTicket(i); if(t == 0) continue;
         long type = HistoryDealGetInteger(t, DEAL_TYPE); if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;
         FileWrite(hd, TimeToString((datetime)HistoryDealGetInteger(t, DEAL_TIME), TIME_DATE|TIME_SECONDS), HistoryDealGetString(t, DEAL_SYMBOL),
                   type == DEAL_TYPE_BUY ? "buy" : "sell", EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY)),
                   DoubleToString(HistoryDealGetDouble(t, DEAL_VOLUME), 2), DoubleToString(HistoryDealGetDouble(t, DEAL_PRICE), 6),
                   DoubleToString(HistoryDealGetDouble(t, DEAL_COMMISSION), 2), DoubleToString(HistoryDealGetDouble(t, DEAL_SWAP), 2),
                   DoubleToString(HistoryDealGetDouble(t, DEAL_FEE), 2), DoubleToString(HistoryDealGetDouble(t, DEAL_PROFIT), 2));
        }
      FileClose(hd);
      PrintFormat("Trade history: %d deals checked for costs", nd);
     }

   // ---------- price history
   int files = 0;
   for(int i = 0; i < total; i++)
     {
      string s = list[i];
      Comment(StringFormat("PipCraft extractor: %d / %d  %s", i + 1, total, s));
      if(InpD1  && ExportBars(s, PERIOD_D1,  "D1",  D'1990.01.01') > 0) files++;
      if(InpH1  && ExportBars(s, PERIOD_H1,  "H1",  now - InpH1Years * 365 * 86400) > 0) files++;
      if(InpM15 && ExportBars(s, PERIOD_M15, "M15", now - InpM15Years * 365 * 86400) > 0) files++;
      if(IsStopped()) break;
     }
   Comment("");
   string msg = StringFormat("PipCraft extractor done: %d symbols, %d price files.\nFolder: %s\\MQL5\\Files\\PipCraft_Export\n"
                             "Zip that folder and upload it. If the zip is over ~15 MB, split it into several zips.",
                             total, files, TerminalInfoString(TERMINAL_DATA_PATH));
   Print(msg); Alert(msg);
  }
//+------------------------------------------------------------------+
