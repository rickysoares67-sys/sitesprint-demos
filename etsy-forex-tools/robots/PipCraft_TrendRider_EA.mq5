//+------------------------------------------------------------------+
//|                                     PipCraft_TrendRider_EA.mq5   |
//|  Trend-following robot:                                          |
//|   - Entry: fast MA crosses slow MA, in the direction of a        |
//|     long-term trend filter MA (optional RSI confirmation).       |
//|   - Stop loss / take profit sized by ATR.                        |
//|   - Lot size from risk % of balance.                             |
//|   - ATR trailing stop, break-even, spread & trading-hours        |
//|     filters, max daily loss guard.                               |
//|  Signals are taken on CLOSED bars only.                          |
//+------------------------------------------------------------------+
#property copyright "PipCraft Tools"
#property version   "1.00"
#property description "TrendRider EA - MA crossover + trend filter, ATR stops, risk % sizing."
#property description "Always backtest and demo-test before using on a live account."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

input group "Strategy"
input int                InpFastMA     = 20;          // Fast MA period
input int                InpSlowMA     = 50;          // Slow MA period
input int                InpTrendMA    = 200;         // Trend filter MA (0 = off)
input ENUM_MA_METHOD     InpMAMethod   = MODE_EMA;    // MA method
input bool               InpUseRSI     = true;        // Require RSI confirmation
input int                InpRSIPeriod  = 14;          // RSI period
input double             InpRSIBuyMin  = 50;          // Buy only if RSI above
input double             InpRSISellMax = 50;          // Sell only if RSI below
input bool               InpCloseOnOpposite = true;   // Close trade on opposite signal

input group "Risk"
input double InpRiskPct     = 1.0;  // Risk per trade (% of balance)
input double InpFixedLots   = 0.0;  // Fixed lots (0 = use risk %)
input int    InpATRPeriod   = 14;   // ATR period
input double InpSL_ATR      = 1.5;  // Stop loss (x ATR)
input double InpTP_ATR      = 3.0;  // Take profit (x ATR, 0 = none)
input double InpMaxDailyLossPct = 3.0; // Stop trading today after this % loss (0 = off)

input group "Trade management"
input double InpBE_ATR      = 1.0;  // Move to break-even after (x ATR, 0 = off)
input double InpTrail_ATR   = 2.0;  // Trailing stop distance (x ATR, 0 = off)

input group "Filters"
input int    InpMaxSpreadPts = 30;  // Max spread (points)
input int    InpStartHour    = 7;   // Trade from hour (server time)
input int    InpEndHour      = 20;  // Trade until hour (server time)
input bool   InpNoFriday     = false; // No new trades on Friday

input group "General"
input long   InpMagic   = 260101;          // Magic number
input string InpComment = "TrendRider";    // Order comment

CTrade        trade;
CPositionInfo pos;
int hFast, hSlow, hTrend = INVALID_HANDLE, hRsi = INVALID_HANDLE, hAtr;
datetime lastBar = 0;
double   dayStartBalance = 0;
int      dayOfYear = -1;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpSlowMA <= InpFastMA) { Print("Slow MA must be > Fast MA"); return(INIT_PARAMETERS_INCORRECT); }
   hFast = iMA(_Symbol, _Period, InpFastMA, 0, InpMAMethod, PRICE_CLOSE);
   hSlow = iMA(_Symbol, _Period, InpSlowMA, 0, InpMAMethod, PRICE_CLOSE);
   if(InpTrendMA > 0) hTrend = iMA(_Symbol, _Period, InpTrendMA, 0, InpMAMethod, PRICE_CLOSE);
   if(InpUseRSI)      hRsi   = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   hAtr  = iATR(_Symbol, _Period, InpATRPeriod);
   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hAtr == INVALID_HANDLE ||
      (InpTrendMA > 0 && hTrend == INVALID_HANDLE) || (InpUseRSI && hRsi == INVALID_HANDLE))
      return(INIT_FAILED);
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFillingBySymbol(_Symbol);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(hFast); IndicatorRelease(hSlow); IndicatorRelease(hAtr);
   if(hTrend != INVALID_HANDLE) IndicatorRelease(hTrend);
   if(hRsi   != INVALID_HANDLE) IndicatorRelease(hRsi);
  }

//+------------------------------------------------------------------+
double Buf(int handle, int shift)
  {
   double v[1];
   if(CopyBuffer(handle, 0, shift, 1, v) != 1) return(EMPTY_VALUE);
   return(v[0]);
  }

double NormalizeLots(double lots)
  {
   double vMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / vStep) * vStep;
   if(lots < vMin) return(0);
   return(MathMin(lots, vMax));
  }

double LotsForRisk(double slDistance)
  {
   if(InpFixedLots > 0) return(NormalizeLots(InpFixedLots));
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0) tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(slDistance <= 0 || tickSize <= 0 || tickValue <= 0) return(0);
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
   return(NormalizeLots(risk / (slDistance / tickSize * tickValue)));
  }

bool HasPosition(ENUM_POSITION_TYPE &type)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(pos.SelectByIndex(i) && pos.Symbol() == _Symbol && pos.Magic() == InpMagic)
        { type = pos.PositionType(); return(true); }
   return(false);
  }

void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(pos.SelectByIndex(i) && pos.Symbol() == _Symbol && pos.Magic() == InpMagic)
         trade.PositionClose(pos.Ticket());
  }

bool DailyLossHit()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_year != dayOfYear)
     { dayOfYear = dt.day_of_year; dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE); }
   if(InpMaxDailyLossPct <= 0 || dayStartBalance <= 0) return(false);
   double lossPct = (dayStartBalance - AccountInfoDouble(ACCOUNT_EQUITY)) / dayStartBalance * 100.0;
   return(lossPct >= InpMaxDailyLossPct);
  }

bool FiltersOK()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(InpNoFriday && dt.day_of_week == 5) return(false);
   bool inHours = (InpStartHour <= InpEndHour)
                  ? (dt.hour >= InpStartHour && dt.hour < InpEndHour)
                  : (dt.hour >= InpStartHour || dt.hour < InpEndHour);
   if(!inHours) return(false);
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts) return(false);
   return(true);
  }

//+------------------------------------------------------------------+
void ManagePositions()
  {
   double atr = Buf(hAtr, 1);
   if(atr == EMPTY_VALUE || atr <= 0) return;
   double stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!pos.SelectByIndex(i) || pos.Symbol() != _Symbol || pos.Magic() != InpMagic) continue;
      double open = pos.PriceOpen(), sl = pos.StopLoss(), tp = pos.TakeProfit();
      double newSl = sl;

      if(pos.PositionType() == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(InpBE_ATR > 0 && bid - open >= InpBE_ATR * atr && (sl < open || sl == 0))
            newSl = open + 2 * _Point;
         if(InpTrail_ATR > 0)
           {
            double t = bid - InpTrail_ATR * atr;
            if(t > open && t > newSl) newSl = t;
           }
         newSl = NormalizeDouble(newSl, _Digits);
         if(newSl > sl + _Point && bid - newSl > stopsLvl)
            trade.PositionModify(pos.Ticket(), newSl, tp);
        }
      else
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(InpBE_ATR > 0 && open - ask >= InpBE_ATR * atr && (sl > open || sl == 0))
            newSl = open - 2 * _Point;
         if(InpTrail_ATR > 0)
           {
            double t = ask + InpTrail_ATR * atr;
            if(t < open && (t < newSl || newSl == 0)) newSl = t;
           }
         newSl = NormalizeDouble(newSl, _Digits);
         if((sl == 0 || newSl < sl - _Point) && newSl > 0 && newSl - ask > stopsLvl)
            trade.PositionModify(pos.Ticket(), newSl, tp);
        }
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   ManagePositions();

   datetime bar = iTime(_Symbol, _Period, 0);
   if(bar == lastBar) return;      // act once per new bar
   lastBar = bar;

   double f1 = Buf(hFast, 1), f2 = Buf(hFast, 2);
   double s1 = Buf(hSlow, 1), s2 = Buf(hSlow, 2);
   double atr = Buf(hAtr, 1);
   if(f1 == EMPTY_VALUE || f2 == EMPTY_VALUE || s1 == EMPTY_VALUE || s2 == EMPTY_VALUE ||
      atr == EMPTY_VALUE || atr <= 0)
      return;

   bool crossUp   = f2 <= s2 && f1 > s1;
   bool crossDown = f2 >= s2 && f1 < s1;
   double close1  = iClose(_Symbol, _Period, 1);

   if(InpTrendMA > 0)
     {
      double tr = Buf(hTrend, 1);
      if(tr == EMPTY_VALUE) return;
      if(close1 < tr) crossUp   = false;
      if(close1 > tr) crossDown = false;
     }
   if(InpUseRSI)
     {
      double rsi = Buf(hRsi, 1);
      if(rsi == EMPTY_VALUE) return;
      if(rsi < InpRSIBuyMin)  crossUp   = false;
      if(rsi > InpRSISellMax) crossDown = false;
     }

   ENUM_POSITION_TYPE type = POSITION_TYPE_BUY;
   bool has = HasPosition(type);
   if(has && InpCloseOnOpposite &&
      ((type == POSITION_TYPE_BUY && crossDown) || (type == POSITION_TYPE_SELL && crossUp)))
     { CloseAll(); has = false; }
   if(has) return;
   if(!crossUp && !crossDown) return;
   if(!FiltersOK() || DailyLossHit()) return;

   double slDist = InpSL_ATR * atr;
   double lots = LotsForRisk(slDist);
   if(lots <= 0) { Print("TrendRider: lot size below broker minimum for this risk - skipped."); return; }

   if(crossUp)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - slDist, _Digits);
      double tp  = InpTP_ATR > 0 ? NormalizeDouble(ask + InpTP_ATR * atr, _Digits) : 0;
      trade.Buy(lots, _Symbol, ask, sl, tp, InpComment);
     }
   else
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + slDist, _Digits);
      double tp  = InpTP_ATR > 0 ? NormalizeDouble(bid - InpTP_ATR * atr, _Digits) : 0;
      trade.Sell(lots, _Symbol, bid, sl, tp, InpComment);
     }
  }
//+------------------------------------------------------------------+
