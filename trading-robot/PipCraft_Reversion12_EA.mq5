//+------------------------------------------------------------------+
//|                                   PipCraft_Reversion12_EA.mq5    |
//|  Daily mean-reversion robot that trades a basket of markets from |
//|  ONE chart.                                                      |
//|                                                                  |
//|  Rules (the only strategy that held up on unseen 2019-2022 data  |
//|  in a 12-market, 10-year test, after costs):                     |
//|   BUY  when RSI(2) < 5  and close > 200-day SMA (pullback in an  |
//|        uptrend).                                                 |
//|   SELL when RSI(2) > 95 and close < 200-day SMA.                 |
//|   Stop loss 4 x ATR(14). Exit when price closes back across the  |
//|   10-day SMA, or after 10 days.                                  |
//|  Signals use CLOSED daily bars; orders go in at the new day's    |
//|  open.                                                           |
//|                                                                  |
//|  Expect a SMALL edge: about +0.05R per trade, ~75 trades a year  |
//|  across 12 markets. Test it on a demo account before real money. |
//+------------------------------------------------------------------+
#property copyright "PipCraft Tools"
#property version   "1.10"
#property description "Reversion12 - daily RSI(2) mean reversion across a basket of markets."
#property description "Small, tested edge. Backtest and demo-trade before using real money."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

input group "Markets"
input string InpSymbols = "EURUSD,GBPUSD,USDJPY,USDCHF,USDCAD,AUDUSD,EURGBP,EURCHF,EURJPY,GBPJPY,AUDJPY,XAUUSD"; // Symbols (comma separated, exactly as in Market Watch)
input string InpSuffix  = "";      // Broker symbol suffix, e.g. ".m" or "pro"

input group "Strategy"
input int    InpRSIPeriod = 2;     // RSI period
input double InpRSILow    = 5;     // Buy when RSI below
input double InpRSIHigh   = 95;    // Sell when RSI above
input int    InpTrendMA   = 200;   // Trend filter SMA (days)
input int    InpExitMA    = 10;    // Exit SMA (days)
input int    InpATR       = 14;    // ATR period
input double InpStopATR   = 4.0;   // Stop loss (x ATR)
input int    InpMaxDays   = 10;    // Close after this many days

input group "Risk"
input double InpRiskPct      = 0.5;  // Risk per trade (% of balance)
input double InpMaxOpenRisk  = 3.0;  // Max total risk of open trades (% of balance)
input double InpMaxSpreadPct = 15;   // Skip entry if spread > this % of the stop distance
input double InpDDStopPct    = 15;   // Stop opening trades if equity is this % below its peak (0 = off)

input group "Prop-firm limits (0 = off)"
input double InpDailyLossPct = 4.0;  // Close all & pause for the day at this % loss from the day's start
input double InpMaxLossPct   = 8.0;  // Close all & stop for good at this % below the starting balance
input double InpTargetPct    = 0.0;  // Close all & stop when this % profit is reached (challenge target)
input double InpStartBalance = 0.0;  // Starting balance for the limits (0 = balance when attached)

input group "Logging"
input bool   InpLogCsv = true;       // Write every trade to MQL5/Files/Reversion12_log.csv

input group "General"
input long   InpMagic   = 260312;
input string InpComment = "Reversion12";

CTrade        trade;
CPositionInfo pos;

struct Mkt { string sym; int hRsi, hTrend, hExit, hAtr; datetime lastBar; bool ok; };
Mkt   M[];
double peakEquity = 0, startBal = 0, dayStartEq = 0;
int    dayKey = -1;
bool   haltedToday = false, haltedForGood = false;

void LogCsv(const string what, const string sym, double lots, double price, const string note)
  {
   if(!InpLogCsv) return;
   int h = FileOpen("Reversion12_log.csv", FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0) FileWrite(h, "time", "event", "symbol", "lots", "price", "balance", "equity", "note");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), what, sym, DoubleToString(lots, 2), DoubleToString(price, 5),
             DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2), DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), note);
   FileClose(h);
  }

void CloseAllMine(const string why)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(pos.SelectByIndex(i) && pos.Magic() == InpMagic)
        {
         string s = pos.Symbol(); double v = pos.Volume(), px = pos.PriceCurrent();
         if(trade.PositionClose(pos.Ticket())) LogCsv("CLOSE", s, v, px, why);
        }
  }

// returns false when no new trades may be opened
bool RiskGuards()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_year != dayKey) { dayKey = dt.day_of_year; dayStartEq = eq; haltedToday = false; }
   if(haltedForGood) return(false);
   if(InpMaxLossPct > 0 && eq <= startBal * (1 - InpMaxLossPct / 100.0))
     { CloseAllMine("max loss limit"); haltedForGood = true; Print("Reversion12: MAX LOSS limit hit - trading stopped. Remove and re-attach to restart."); return(false); }
   if(InpTargetPct > 0 && eq >= startBal * (1 + InpTargetPct / 100.0))
     { CloseAllMine("profit target"); haltedForGood = true; Print("Reversion12: PROFIT TARGET reached - trading stopped."); return(false); }
   if(InpDailyLossPct > 0 && !haltedToday && eq <= dayStartEq * (1 - InpDailyLossPct / 100.0))
     { CloseAllMine("daily loss limit"); haltedToday = true; Print("Reversion12: DAILY LOSS limit hit - paused until tomorrow."); }
   return(!haltedToday);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   string parts[]; int n = StringSplit(InpSymbols, ',', parts);
   ArrayResize(M, 0);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i]; StringTrimLeft(s); StringTrimRight(s);
      if(s == "") continue;
      s += InpSuffix;
      if(!SymbolSelect(s, true)) { PrintFormat("Reversion12: symbol %s not found at this broker - skipped", s); continue; }
      Mkt m; m.sym = s; m.lastBar = 0;
      m.hRsi   = iRSI(s, PERIOD_D1, InpRSIPeriod, PRICE_CLOSE);
      m.hTrend = iMA(s, PERIOD_D1, InpTrendMA, 0, MODE_SMA, PRICE_CLOSE);
      m.hExit  = iMA(s, PERIOD_D1, InpExitMA, 0, MODE_SMA, PRICE_CLOSE);
      m.hAtr   = iATR(s, PERIOD_D1, InpATR);
      m.ok = m.hRsi != INVALID_HANDLE && m.hTrend != INVALID_HANDLE && m.hExit != INVALID_HANDLE && m.hAtr != INVALID_HANDLE;
      if(!m.ok) { PrintFormat("Reversion12: could not create indicators for %s", s); continue; }
      int k = ArraySize(M); ArrayResize(M, k + 1); M[k] = m;
     }
   if(ArraySize(M) == 0) { Print("Reversion12: no tradable symbols."); return(INIT_FAILED); }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);
   peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   startBal = InpStartBalance > 0 ? InpStartBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   dayStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   EventSetTimer(30);   // check every 30s so all symbols are handled even if this chart is quiet
   PrintFormat("Reversion12 running on %d symbols", ArraySize(M));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < ArraySize(M); i++)
     { IndicatorRelease(M[i].hRsi); IndicatorRelease(M[i].hTrend); IndicatorRelease(M[i].hExit); IndicatorRelease(M[i].hAtr); }
   Comment("");
  }

//+------------------------------------------------------------------+
double Buf(int h, int shift)
  {
   double v[1];
   if(CopyBuffer(h, 0, shift, 1, v) != 1) return(EMPTY_VALUE);
   return(v[0]);
  }

bool FindPos(const string s, ulong &ticket, ENUM_POSITION_TYPE &type, datetime &opened, double &risk)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(pos.SelectByIndex(i) && pos.Symbol() == s && pos.Magic() == InpMagic)
        {
         ticket = pos.Ticket(); type = pos.PositionType(); opened = pos.Time(); risk = 0;
         double sl = pos.StopLoss();
         if(sl > 0)
           {
            double ts = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE), tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE_LOSS);
            if(tv <= 0) tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE);
            if(ts > 0) risk = MathMax(0, (type == POSITION_TYPE_BUY ? pos.PriceOpen() - sl : sl - pos.PriceOpen())) / ts * tv * pos.Volume();
           }
         return(true);
        }
   return(false);
  }

double OpenRiskMoney()
  {
   double r = 0; ulong t; ENUM_POSITION_TYPE ty; datetime o; double rk;
   for(int i = 0; i < ArraySize(M); i++) if(FindPos(M[i].sym, t, ty, o, rk)) r += rk;
   return(r);
  }

double LotsFor(const string s, double stopDist, double riskMoney)
  {
   double ts = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE), tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0) tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE);
   if(stopDist <= 0 || ts <= 0 || tv <= 0) return(0);
   double lots = riskMoney / (stopDist / ts * tv);
   double step = SymbolInfoDouble(s, SYMBOL_VOLUME_STEP), mn = SymbolInfoDouble(s, SYMBOL_VOLUME_MIN), mx = SymbolInfoDouble(s, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;          // round DOWN, never over-risk
   if(lots < mn) return(0);
   return(MathMin(lots, mx));
  }

//+------------------------------------------------------------------+
void Process(Mkt &m, bool mayOpen)
  {
   datetime bar = iTime(m.sym, PERIOD_D1, 0);
   if(bar == 0 || bar == m.lastBar) return;      // once per new daily bar
   if(Bars(m.sym, PERIOD_D1) < InpTrendMA + 5) return;
   double rsi = Buf(m.hRsi, 1), tr = Buf(m.hTrend, 1), ex = Buf(m.hExit, 1), at = Buf(m.hAtr, 1);
   double c1 = iClose(m.sym, PERIOD_D1, 1);
   if(rsi == EMPTY_VALUE || tr == EMPTY_VALUE || ex == EMPTY_VALUE || at == EMPTY_VALUE || at <= 0 || c1 <= 0) return;  // data not ready: retry next timer
   ulong ticket; ENUM_POSITION_TYPE type; datetime opened; double rk;
   if(FindPos(m.sym, ticket, type, opened, rk))
     {
      // ---- exits: back across the exit SMA, or too old
      int daysOpen = iBarShift(m.sym, PERIOD_D1, opened);
      bool exitNow = (type == POSITION_TYPE_BUY && c1 > ex) || (type == POSITION_TYPE_SELL && c1 < ex) || daysOpen >= InpMaxDays;
      if(exitNow)
        {
         double v = pos.Volume(), px = pos.PriceCurrent();
         if(!trade.PositionClose(ticket)) return;          // market closed / requote: retry on the next timer
         string why = daysOpen >= InpMaxDays ? "time limit" : "back to the mean";
         PrintFormat("Reversion12 %s: closed (%s)", m.sym, why); LogCsv("CLOSE", m.sym, v, px, why);
        }
      m.lastBar = bar;
      return;   // never re-enter on the same bar we exit
     }
   if(!mayOpen) return;                                   // keep checking until the guards allow trading today
   m.lastBar = bar;

   // ---- entries
   bool buy = rsi < InpRSILow && c1 > tr, sell = rsi > InpRSIHigh && c1 < tr;
   if(!buy && !sell) return;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY), bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(InpDDStopPct > 0 && peakEquity > 0 && (peakEquity - eq) / peakEquity * 100.0 >= InpDDStopPct)
     { PrintFormat("Reversion12: equity %.1f%% below peak - no new trades", (peakEquity - eq) / peakEquity * 100.0); return; }

   double stop = InpStopATR * at, riskMoney = bal * InpRiskPct / 100.0;
   if(OpenRiskMoney() + riskMoney > bal * InpMaxOpenRisk / 100.0) { PrintFormat("Reversion12 %s: open-risk cap reached - skipped", m.sym); return; }
   double spread = SymbolInfoDouble(m.sym, SYMBOL_ASK) - SymbolInfoDouble(m.sym, SYMBOL_BID);
   if(spread > stop * InpMaxSpreadPct / 100.0) { PrintFormat("Reversion12 %s: spread too wide - skipped", m.sym); return; }

   double lots = LotsFor(m.sym, stop, riskMoney);
   if(lots <= 0) { PrintFormat("Reversion12 %s: lot size below broker minimum for this risk - skipped", m.sym); return; }
   int dg = (int)SymbolInfoInteger(m.sym, SYMBOL_DIGITS);
   trade.SetTypeFillingBySymbol(m.sym);
   if(buy)
     {
      double ask = SymbolInfoDouble(m.sym, SYMBOL_ASK);
      if(trade.Buy(lots, m.sym, ask, NormalizeDouble(ask - stop, dg), 0, InpComment)) LogCsv("BUY", m.sym, lots, ask, StringFormat("RSI %.1f", rsi));
     }
   else
     {
      double bid = SymbolInfoDouble(m.sym, SYMBOL_BID);
      if(trade.Sell(lots, m.sym, bid, NormalizeDouble(bid + stop, dg), 0, InpComment)) LogCsv("SELL", m.sym, lots, bid, StringFormat("RSI %.1f", rsi));
     }
  }

void RunAll()
  {
   peakEquity = MathMax(peakEquity, AccountInfoDouble(ACCOUNT_EQUITY));
   bool mayOpen = RiskGuards();
   for(int i = 0; i < ArraySize(M); i++) Process(M[i], mayOpen);
   Comment(StringFormat("Reversion12 · %d markets · %s · open risk %.2f%% · peak-equity drop %.1f%%",
           ArraySize(M), haltedForGood ? "STOPPED" : haltedToday ? "PAUSED TODAY" : "trading", OpenRiskMoney() / MathMax(1, AccountInfoDouble(ACCOUNT_BALANCE)) * 100,
           peakEquity > 0 ? (peakEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / peakEquity * 100 : 0));
  }

void OnTick()  { RunAll(); }
void OnTimer() { RunAll(); }
//+------------------------------------------------------------------+
