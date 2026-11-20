//+------------------------------------------------------------------+
//|                                          PipCraft_Apex_EA.mq5    |
//|  Three uncorrelated daily strategies, one chart, one dashboard.  |
//|                                                                  |
//|  1. REVERSION  - RSI(2) pullbacks in the 200-day trend, exit at  |
//|                  the 10-day mean or after 10 days.               |
//|  2. ROTATION   - every Monday, buy the markets that fell most    |
//|                  over 5/10/20 days and sell those that rose most |
//|                  (volatility-adjusted), hold for the week.       |
//|  3. CALENDAR   - each market's weekday tendencies, re-learned    |
//|                  every year from the previous 3 years, traded    |
//|                  only where they are statistically strong.       |
//|                                                                  |
//|  Walk-forward test 2016-2022, 12 markets, after costs, combined: |
//|  ~3.9%/yr at 4.4% volatility, Sharpe 0.9, worst drop 6.9%.       |
//|  The strategies were chosen after seeing results, so expect      |
//|  less live. Test on a demo account before risking money.         |
//|  REQUIRES a HEDGING account (strategies hold separate positions).|
//+------------------------------------------------------------------+
#property copyright "PipCraft Tools"
#property version   "1.00"
#property description "PipCraft Apex - three uncorrelated daily strategies with a live dashboard."
#property description "Honest walk-forward results: modest, steady returns. Demo-test first."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

enum ENUM_PROFILE { PROFILE_CONSERVATIVE = 0, // Conservative (~4% yearly volatility)
                    PROFILE_STANDARD     = 1, // Standard (~8% yearly volatility)
                    PROFILE_CUSTOM       = 2  // Custom (use the risk inputs below)
                  };

input group "Markets"
input string InpSymbols = "EURUSD,GBPUSD,USDJPY,USDCHF,USDCAD,AUDUSD,EURGBP,EURCHF,EURJPY,GBPJPY,AUDJPY,XAUUSD"; // Symbols (comma separated)
input string InpSuffix  = "";                   // Broker symbol suffix, e.g. ".m"

input group "Risk profile"
input ENUM_PROFILE InpProfile   = PROFILE_STANDARD;
input double InpRevRiskPct      = 0.84;  // Custom: REVERSION risk per trade (% equity)
input double InpRotUnitPct      = 0.15;  // Custom: ROTATION risk per 1-ATR move per full position (% equity)
input double InpCalUnitPct      = 0.23;  // Custom: CALENDAR risk per 1-ATR move (% equity)
input bool   InpUseReversion    = true;  // Run REVERSION
input bool   InpUseRotation     = true;  // Run ROTATION
input bool   InpUseCalendar     = true;  // Run CALENDAR

input group "Safety limits (0 = off)"
input double InpDailyLossPct = 3.0;   // Close all & pause for the day at this % daily loss
input double InpMaxLossPct   = 15.0;  // Close all & stop at this % below the starting balance
input double InpTargetPct    = 0.0;   // Close all & stop at this % profit (prop challenge target)
input double InpStartBalance = 0.0;   // Starting balance for the limits (0 = balance when attached)
input double InpMaxSpreadATR = 0.10;  // Skip an order if spread > this fraction of daily ATR

input group "Display & logging"
input bool   InpDashboard = true;     // Show dashboard on the chart
input bool   InpLogCsv    = true;     // Log every order to MQL5/Files/Apex_log.csv
input long   InpMagicBase = 270100;   // Magic numbers: base+1 reversion, +2 rotation, +3 calendar

//+------------------------------------------------------------------+
CTrade        trade;
CPositionInfo pos;
#define NSLEEVE 3
string SLEEVE[NSLEEVE] = {"REVERSION", "ROTATION", "CALENDAR"};

struct Mkt
  {
   string   sym;
   int      hRsi, hTrend, hExit;
   datetime revBar;
   int      cal[5];          // weekday signal -1/0/+1 (Mon..Fri)
  };
Mkt      M[];
int      NM = 0;
double   revRisk, rotUnit, calUnit;
double   startBal = 0, dayStartEq = 0, peakEq = 0;
int      dayKey = -1, calYear = -1;
bool     haltedToday = false, haltedForGood = false;
datetime lastD1 = 0, lastRotWeek = 0;
string   lastAction[NSLEEVE];

long Magic(int s) { return InpMagicBase + 1 + s; }

//+------------------------------------------------------------------+
//| helpers                                                          |
//+------------------------------------------------------------------+
void LogCsv(const string ev, const string sleeve, const string sym, double lots, double price, const string note)
  {
   if(!InpLogCsv) return;
   int h = FileOpen("Apex_log.csv", FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0) FileWrite(h, "time", "event", "strategy", "symbol", "lots", "price", "balance", "equity", "note");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), ev, sleeve, sym, DoubleToString(lots, 2),
             DoubleToString(price, 5), DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
             DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), note);
   FileClose(h);
  }

// Wilder ATR(20) on closed daily bars, computed directly so it matches the research
double ATR20(const string s)
  {
   MqlRates r[]; ArraySetAsSeries(r, false);
   int n = CopyRates(s, PERIOD_D1, 1, 120, r);
   if(n < 40) return(0);
   double a = r[1].high - r[1].low;
   for(int i = 1; i < n; i++)
     {
      double tr = MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - r[i-1].close), MathAbs(r[i].low - r[i-1].close)));
      a += (tr - a) / 20.0;
     }
   return(a);
  }

double MoneyPerPriceUnit(const string s)   // account money per 1.0 price move per 1 lot
  {
   double ts = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE), tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0) tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE);
   return (ts > 0) ? tv / ts : 0;
  }

double RoundLots(const string s, double lots)
  {
   double st = SymbolInfoDouble(s, SYMBOL_VOLUME_STEP), mn = SymbolInfoDouble(s, SYMBOL_VOLUME_MIN), mx = SymbolInfoDouble(s, SYMBOL_VOLUME_MAX);
   if(st <= 0) return(0);
   lots = MathFloor(MathAbs(lots) / st + 1e-9) * st;
   if(lots < mn) return(0);
   return MathMin(lots, mx);
  }

// lots for a position that loses `riskPct` of equity per 1-ATR move
double LotsPerATR(const string s, double riskPct, double atr)
  {
   double mpu = MoneyPerPriceUnit(s);
   if(atr <= 0 || mpu <= 0) return(0);
   return AccountInfoDouble(ACCOUNT_EQUITY) * riskPct / 100.0 / (atr * mpu);
  }

bool SpreadOK(const string s, double atr)
  {
   double sp = SymbolInfoDouble(s, SYMBOL_ASK) - SymbolInfoDouble(s, SYMBOL_BID);
   return atr > 0 && sp <= atr * InpMaxSpreadATR;
  }

// net signed lots this sleeve holds on a symbol (+ long / - short)
double SleeveLots(int sl, const string s)
  {
   double v = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(pos.SelectByIndex(i) && pos.Magic() == Magic(sl) && pos.Symbol() == s)
         v += (pos.PositionType() == POSITION_TYPE_BUY ? 1 : -1) * pos.Volume();
   return(v);
  }

void CloseSleeveSymbol(int sl, const string s, const string why)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(pos.SelectByIndex(i) && pos.Magic() == Magic(sl) && pos.Symbol() == s)
        {
         double v = pos.Volume(), px = pos.PriceCurrent();
         if(trade.PositionClose(pos.Ticket())) LogCsv("CLOSE", SLEEVE[sl], s, v, px, why);
        }
  }

void CloseAll(const string why)
  {
   for(int sl = 0; sl < NSLEEVE; sl++) for(int i = 0; i < NM; i++) CloseSleeveSymbol(sl, M[i].sym, why);
  }

bool Open(int sl, const string s, int dir, double lots, double slPrice, const string note)
  {
   lots = RoundLots(s, lots);
   if(lots <= 0 || dir == 0) return(false);
   trade.SetExpertMagicNumber(Magic(sl));
   trade.SetTypeFillingBySymbol(s);
   int dg = (int)SymbolInfoInteger(s, SYMBOL_DIGITS);
   bool ok;
   if(dir > 0) { double a = SymbolInfoDouble(s, SYMBOL_ASK); ok = trade.Buy(lots, s, a, slPrice > 0 ? NormalizeDouble(slPrice, dg) : 0, 0, "Apex " + SLEEVE[sl]); if(ok) LogCsv("BUY", SLEEVE[sl], s, lots, a, note); }
   else        { double b = SymbolInfoDouble(s, SYMBOL_BID); ok = trade.Sell(lots, s, b, slPrice > 0 ? NormalizeDouble(slPrice, dg) : 0, 0, "Apex " + SLEEVE[sl]); if(ok) LogCsv("SELL", SLEEVE[sl], s, lots, b, note); }
   return(ok);
  }

double Buf(int h, int shift) { double v[1]; return CopyBuffer(h, 0, shift, 1, v) == 1 ? v[0] : EMPTY_VALUE; }

//+------------------------------------------------------------------+
//| 1. REVERSION                                                     |
//+------------------------------------------------------------------+
void RunReversion(Mkt &m, bool mayOpen)
  {
   datetime bar = iTime(m.sym, PERIOD_D1, 0);
   if(bar == 0 || bar == m.revBar) return;
   double rsi = Buf(m.hRsi, 1), tr = Buf(m.hTrend, 1), ex = Buf(m.hExit, 1), c1 = iClose(m.sym, PERIOD_D1, 1), atr = ATR20(m.sym);
   if(rsi == EMPTY_VALUE || tr == EMPTY_VALUE || ex == EMPTY_VALUE || c1 <= 0 || atr <= 0) return;   // data not ready
   double held = SleeveLots(0, m.sym);
   if(held != 0)
     {
      datetime opened = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) if(pos.SelectByIndex(i) && pos.Magic() == Magic(0) && pos.Symbol() == m.sym) opened = pos.Time();
      int days = iBarShift(m.sym, PERIOD_D1, opened);
      if((held > 0 && c1 > ex) || (held < 0 && c1 < ex) || days >= 10)
        {
         CloseSleeveSymbol(0, m.sym, days >= 10 ? "time limit" : "back to the mean");
         if(SleeveLots(0, m.sym) != 0) return;                       // close failed: retry next timer
         lastAction[0] = m.sym + " closed";
        }
      m.revBar = bar; return;
     }
   if(!mayOpen) return;
   m.revBar = bar;
   int dir = (rsi < 5 && c1 > tr) ? 1 : (rsi > 95 && c1 < tr) ? -1 : 0;
   if(dir == 0 || !SpreadOK(m.sym, atr)) return;
   double stop = 4.0 * atr, mpu = MoneyPerPriceUnit(m.sym);
   if(mpu <= 0) return;
   double lots = AccountInfoDouble(ACCOUNT_EQUITY) * revRisk / 100.0 / (stop * mpu);
   double px = dir > 0 ? SymbolInfoDouble(m.sym, SYMBOL_ASK) : SymbolInfoDouble(m.sym, SYMBOL_BID);
   if(Open(0, m.sym, dir, lots, px - dir * stop, StringFormat("RSI2 %.1f", rsi))) lastAction[0] = (dir > 0 ? "Bought " : "Sold ") + m.sym;
  }

//+------------------------------------------------------------------+
//| 2. ROTATION (weekly cross-market reversal, blend of 9 settings)  |
//+------------------------------------------------------------------+
void RunRotation(bool mayOpen)
  {
   datetime mon = iTime(_Symbol, PERIOD_W1, 0);
   if(mon == 0 || mon == lastRotWeek || !mayOpen) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return;
   double w[]; ArrayResize(w, NM); ArrayInitialize(w, 0);
   double atr[]; ArrayResize(atr, NM);
   int Ls[3] = {5, 10, 20}, Ks[3] = {2, 3, 4};
   double sc[]; int idx[]; ArrayResize(sc, NM); ArrayResize(idx, NM);
   for(int i = 0; i < NM; i++) { atr[i] = ATR20(M[i].sym); if(atr[i] <= 0) return; }
   for(int a = 0; a < 3; a++)
     {
      int ok = 0;
      for(int i = 0; i < NM; i++)
        {
         double c1 = iClose(M[i].sym, PERIOD_D1, 1), cL = iClose(M[i].sym, PERIOD_D1, 1 + Ls[a]);
         if(c1 <= 0 || cL <= 0) return;
         sc[i] = -(c1 - cL) / atr[i]; idx[i] = i; ok++;
        }
      for(int i = 0; i < NM - 1; i++) for(int j = i + 1; j < NM; j++) if(sc[idx[j]] < sc[idx[i]]) { int t = idx[i]; idx[i] = idx[j]; idx[j] = t; }
      for(int b = 0; b < 3; b++)
        {
         if(NM < 2 * Ks[b]) continue;
         for(int r = 0; r < Ks[b]; r++) { w[idx[r]] -= 1.0 / 9.0; w[idx[NM - 1 - r]] += 1.0 / 9.0; }
        }
     }
   lastRotWeek = mon;
   int changes = 0;
   for(int i = 0; i < NM; i++)
     {
      string s = M[i].sym;
      double target = RoundLots(s, LotsPerATR(s, rotUnit, atr[i]) * MathAbs(w[i])) * (w[i] > 0 ? 1 : -1);
      if(MathAbs(w[i]) < 1e-9) target = 0;
      double held = SleeveLots(1, s);
      bool sameSide = (target > 0 && held > 0) || (target < 0 && held < 0);
      if(sameSide && MathAbs(target - held) <= 0.25 * MathAbs(held)) continue;     // close enough: save costs
      if(held != 0) CloseSleeveSymbol(1, s, "weekly rebalance");
      if(target != 0 && SpreadOK(s, atr[i])) Open(1, s, target > 0 ? 1 : -1, MathAbs(target), 0, StringFormat("weight %.2f", w[i]));
      changes++;
     }
   lastAction[1] = StringFormat("Rebalanced %s (%d changes)", TimeToString(TimeCurrent(), TIME_DATE), changes);
  }

//+------------------------------------------------------------------+
//| 3. CALENDAR (weekday tendencies, re-learned every year)          |
//+------------------------------------------------------------------+
void LearnCalendar()
  {
   MqlDateTime now; TimeToStruct(TimeCurrent(), now);
   datetime to = StringToTime(StringFormat("%d.01.01", now.year)), from = StringToTime(StringFormat("%d.01.01", now.year - 3));
   int strong = 0;
   for(int i = 0; i < NM; i++)
     {
      ArrayInitialize(M[i].cal, 0);
      MqlRates r[]; ArraySetAsSeries(r, false);
      int n = CopyRates(M[i].sym, PERIOD_D1, from - 40 * 86400, to - 1, r);
      if(n < 300) { PrintFormat("Apex CALENDAR: not enough history for %s (%d bars) - skipped", M[i].sym, n); continue; }
      double sum[5] = {0,0,0,0,0}, sq[5] = {0,0,0,0,0}; int cnt[5] = {0,0,0,0,0};
      double a = r[1].high - r[1].low;
      for(int k = 1; k < n; k++)
        {
         double prevAtr = a;
         double tr = MathMax(r[k].high - r[k].low, MathMax(MathAbs(r[k].high - r[k-1].close), MathAbs(r[k].low - r[k-1].close)));
         a += (tr - a) / 20.0;
         if(r[k].time < from || prevAtr <= 0) continue;
         MqlDateTime d; TimeToStruct(r[k].time, d);
         if(d.day_of_week < 1 || d.day_of_week > 5) continue;
         double x = (r[k].close - r[k-1].close) / prevAtr; int wd = d.day_of_week - 1;
         sum[wd] += x; sq[wd] += x * x; cnt[wd]++;
        }
      for(int wd = 0; wd < 5; wd++)
        {
         if(cnt[wd] < 60) continue;
         double mean = sum[wd] / cnt[wd], sd = MathSqrt(MathMax(1e-12, sq[wd] / cnt[wd] - mean * mean)), t = mean / sd * MathSqrt(cnt[wd]);
         if(MathAbs(t) > 2.0) { M[i].cal[wd] = t > 0 ? 1 : -1; strong++; }
        }
     }
   calYear = now.year;
   lastAction[2] = StringFormat("Learned %d weekday patterns for %d", strong, now.year);
   Print("Apex CALENDAR: ", lastAction[2]);
  }

void RunCalendar(bool mayOpen)
  {
   MqlDateTime now; TimeToStruct(TimeCurrent(), now);
   if(now.year != calYear) LearnCalendar();
   datetime d1 = iTime(_Symbol, PERIOD_D1, 0);
   if(d1 == 0 || d1 == lastD1) return;
   // new trading day: close yesterday's calendar positions
   for(int i = 0; i < NM; i++) if(SleeveLots(2, M[i].sym) != 0) CloseSleeveSymbol(2, M[i].sym, "end of day");
   for(int i = 0; i < NM; i++) if(SleeveLots(2, M[i].sym) != 0) return;   // a close failed: retry next timer
   lastD1 = d1;
   if(!mayOpen || now.day_of_week < 1 || now.day_of_week > 5) return;
   int wd = now.day_of_week - 1, opened = 0;
   for(int i = 0; i < NM; i++)
     {
      int dir = M[i].cal[wd]; if(dir == 0) continue;
      double atr = ATR20(M[i].sym);
      if(!SpreadOK(M[i].sym, atr)) continue;
      if(Open(2, M[i].sym, dir, LotsPerATR(M[i].sym, calUnit, atr), 0, "weekday pattern")) opened++;
     }
   lastAction[2] = StringFormat("%s: %d positions for today", TimeToString(TimeCurrent(), TIME_DATE), opened);
  }

//+------------------------------------------------------------------+
//| safety + dashboard                                               |
//+------------------------------------------------------------------+
bool Guards()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY); MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   peakEq = MathMax(peakEq, eq);
   if(dt.day_of_year != dayKey) { dayKey = dt.day_of_year; dayStartEq = eq; haltedToday = false; }
   if(haltedForGood) return(false);
   if(InpMaxLossPct > 0 && eq <= startBal * (1 - InpMaxLossPct / 100)) { CloseAll("max loss limit"); haltedForGood = true; Print("Apex: MAX LOSS reached - stopped."); return(false); }
   if(InpTargetPct > 0 && eq >= startBal * (1 + InpTargetPct / 100)) { CloseAll("profit target"); haltedForGood = true; Print("Apex: TARGET reached - stopped."); return(false); }
   if(InpDailyLossPct > 0 && !haltedToday && eq <= dayStartEq * (1 - InpDailyLossPct / 100)) { CloseAll("daily loss limit"); haltedToday = true; Print("Apex: daily loss limit - paused until tomorrow."); }
   return(!haltedToday);
  }

void Lbl(const string id, int x, int y, const string t, color c, int size = 9, const string font = "Consolas")
  {
   string n = "APEX_" + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER); ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true); ObjectSetInteger(0, n, OBJPROP_ZORDER, 10);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n, OBJPROP_FONT, font); ObjectSetInteger(0, n, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c); ObjectSetString(0, n, OBJPROP_TEXT, t);
  }

void Panel()
  {
   if(!InpDashboard) return;
   string bg = "APEX_bg";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, 8); ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, 20);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE, 380); ObjectSetInteger(0, bg, OBJPROP_YSIZE, 250);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'14,18,28'); ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, C'245,165,36'); ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
     }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY), bal = AccountInfoDouble(ACCOUNT_BALANCE);
   string st = haltedForGood ? "STOPPED" : haltedToday ? "PAUSED TODAY" : "TRADING";
   color stc = haltedForGood ? clrTomato : haltedToday ? clrOrange : clrLimeGreen;
   Lbl("t", 20, 28, "PIPCRAFT APEX", C'245,165,36', 13, "Arial Black");
   Lbl("s", 250, 32, "● " + st, stc, 10, "Arial");
   Lbl("p", 20, 54, StringFormat("Profile %s  ·  %d markets", InpProfile == PROFILE_CONSERVATIVE ? "Conservative" : InpProfile == PROFILE_STANDARD ? "Standard" : "Custom", NM), clrSilver);
   Lbl("e", 20, 76, StringFormat("Equity  %s  (balance %s)", DoubleToString(eq, 2), DoubleToString(bal, 2)), clrWhite);
   Lbl("d", 20, 94, StringFormat("Today   %+.2f%%   From peak  -%.2f%%   Since start %+.2f%%",
       dayStartEq > 0 ? (eq / dayStartEq - 1) * 100 : 0, peakEq > 0 ? (1 - eq / peakEq) * 100 : 0, startBal > 0 ? (eq / startBal - 1) * 100 : 0), clrWhite);
   bool on[NSLEEVE] = {InpUseReversion, InpUseRotation, InpUseCalendar};
   for(int sl = 0; sl < NSLEEVE; sl++)
     {
      int n = 0; double fl = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) if(pos.SelectByIndex(i) && pos.Magic() == Magic(sl)) { n++; fl += pos.Profit() + pos.Swap(); }
      int y = 122 + sl * 38;
      Lbl("n" + (string)sl, 20, y, StringFormat("%-10s %s  %2d open  %+10.2f", SLEEVE[sl], on[sl] ? "ON " : "OFF", n, fl), on[sl] ? (fl >= 0 ? clrMediumSeaGreen : clrTomato) : clrGray);
      Lbl("a" + (string)sl, 34, y + 16, lastAction[sl] == "" ? "waiting for the next daily bar" : lastAction[sl], clrDarkGray, 8, "Arial");
     }
   Lbl("f", 20, 240, StringFormat("Limits: day -%.1f%%  total -%.1f%%  target %s", InpDailyLossPct, InpMaxLossPct, InpTargetPct > 0 ? DoubleToString(InpTargetPct, 1) + "%" : "off"), clrGray, 8, "Arial");
   ChartRedraw();
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     { Alert("PipCraft Apex needs a HEDGING account: its three strategies hold separate positions on the same market."); return(INIT_FAILED); }
   double k = InpProfile == PROFILE_CONSERVATIVE ? 0.5 : 1.0;
   revRisk = InpProfile == PROFILE_CUSTOM ? InpRevRiskPct : 0.84 * k;
   rotUnit = InpProfile == PROFILE_CUSTOM ? InpRotUnitPct : 0.15 * k;
   calUnit = InpProfile == PROFILE_CUSTOM ? InpCalUnitPct : 0.23 * k;
   string parts[]; int n = StringSplit(InpSymbols, ',', parts); ArrayResize(M, 0); NM = 0;
   for(int i = 0; i < n; i++)
     {
      string s = parts[i]; StringTrimLeft(s); StringTrimRight(s); if(s == "") continue; s += InpSuffix;
      if(!SymbolSelect(s, true)) { PrintFormat("Apex: %s not available - skipped", s); continue; }
      Mkt m; m.sym = s; m.revBar = 0; ArrayInitialize(m.cal, 0);
      m.hRsi = iRSI(s, PERIOD_D1, 2, PRICE_CLOSE); m.hTrend = iMA(s, PERIOD_D1, 200, 0, MODE_SMA, PRICE_CLOSE); m.hExit = iMA(s, PERIOD_D1, 10, 0, MODE_SMA, PRICE_CLOSE);
      if(m.hRsi == INVALID_HANDLE || m.hTrend == INVALID_HANDLE || m.hExit == INVALID_HANDLE) continue;
      ArrayResize(M, NM + 1); M[NM++] = m;
     }
   if(NM < 4) { Alert("Apex needs at least 4 tradable markets."); return(INIT_FAILED); }
   startBal = InpStartBalance > 0 ? InpStartBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   peakEq = dayStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   trade.SetDeviationInPoints(30);
   for(int s2 = 0; s2 < NSLEEVE; s2++) lastAction[s2] = "";
   EventSetTimer(20);
   Panel();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < NM; i++) { IndicatorRelease(M[i].hRsi); IndicatorRelease(M[i].hTrend); IndicatorRelease(M[i].hExit); }
   ObjectsDeleteAll(0, "APEX_");
  }

void Run()
  {
   bool may = Guards();
   if(!haltedForGood)
     {
      if(InpUseReversion) for(int i = 0; i < NM; i++) RunReversion(M[i], may);
      if(InpUseRotation)  RunRotation(may);
      if(InpUseCalendar)  RunCalendar(may);
     }
   Panel();
  }
void OnTick()  { Run(); }
void OnTimer() { Run(); }
//+------------------------------------------------------------------+
