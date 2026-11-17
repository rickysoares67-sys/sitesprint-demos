//+------------------------------------------------------------------+
//|                                 PipCraft_AsianBreakout_EA.mq5    |
//|  Session breakout robot:                                         |
//|   1. Measures the high/low of the Asian range (server time).     |
//|   2. When the range closes, places a Buy Stop above the high     |
//|      and a Sell Stop below the low (plus a buffer).              |
//|   3. When one side triggers, the other is cancelled (OCO).       |
//|   4. Unfilled orders are deleted at the cut-off hour and open    |
//|      trades are closed at the end-of-day hour.                   |
//|  Range size filters skip days that are too quiet or too wild.    |
//+------------------------------------------------------------------+
#property copyright "PipCraft Tools"
#property version   "1.00"
#property description "Asian Range Breakout EA - one OCO breakout setup per day."
#property description "Always backtest and demo-test before using on a live account."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

input group "Range (server time)"
input int    InpRangeStart = 0;    // Range start hour
input int    InpRangeEnd   = 7;    // Range end hour (orders placed then)
input int    InpOrderExpire= 12;   // Delete unfilled orders at hour
input int    InpCloseHour  = 21;   // Close open trades at hour (-1 = never)

input group "Entry"
input double InpBufferPips  = 2.0;   // Buffer beyond range (pips)
input double InpMinRangePips= 15.0;  // Skip day if range smaller (pips)
input double InpMaxRangePips= 60.0;  // Skip day if range larger (pips)

input group "Exits"
enum ENUM_SL_MODE { SL_OPPOSITE = 0, // Opposite side of range
                    SL_MIDDLE   = 1, // Middle of range
                    SL_PIPS     = 2  // Fixed pips
                  };
input ENUM_SL_MODE InpSLMode = SL_MIDDLE; // Stop loss placement
input double InpSLPips   = 20.0;  // Fixed SL (pips, if SL mode = Fixed)
input double InpRR       = 2.0;   // Take profit (x risk)
input double InpBE_R     = 1.0;   // Move SL to break-even at (x risk, 0 = off)

input group "Risk"
input double InpRiskPct   = 1.0;  // Risk per trade (% of balance)
input double InpFixedLots = 0.0;  // Fixed lots (0 = use risk %)

input group "Days"
input bool InpMon = true; input bool InpTue = true; input bool InpWed = true;
input bool InpThu = true; input bool InpFri = false;

input group "General"
input long   InpMagic   = 260202;
input string InpComment = "AsianBreakout";

CTrade        trade;
CPositionInfo pos;
COrderInfo    ord;
datetime      setupDay = 0;   // day we already placed orders for

double Pip() { return (_Digits == 3 || _Digits == 5) ? _Point * 10.0 : _Point; }

int OnInit()
  {
   if(InpRangeStart == InpRangeEnd) return(INIT_PARAMETERS_INCORRECT);
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) { ObjectsDeleteAll(0, "PCAB_"); }

//+------------------------------------------------------------------+
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

bool DayAllowed(int dow)
  {
   switch(dow)
     {
      case 1: return InpMon; case 2: return InpTue; case 3: return InpWed;
      case 4: return InpThu; case 5: return InpFri;
     }
   return(false);
  }

int CountMine(bool positions)
  {
   int n = 0;
   if(positions)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
         if(pos.SelectByIndex(i) && pos.Symbol() == _Symbol && pos.Magic() == InpMagic) n++;
     }
   else
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
         if(ord.SelectByIndex(i) && ord.Symbol() == _Symbol && ord.Magic() == InpMagic) n++;
     }
   return(n);
  }

void DeletePending()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(ord.SelectByIndex(i) && ord.Symbol() == _Symbol && ord.Magic() == InpMagic)
         trade.OrderDelete(ord.Ticket());
  }

void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(pos.SelectByIndex(i) && pos.Symbol() == _Symbol && pos.Magic() == InpMagic)
         trade.PositionClose(pos.Ticket());
  }

void DrawRange(datetime t1, datetime t2, double hi, double lo)
  {
   string n = "PCAB_" + TimeToString(t1, TIME_DATE);
   ObjectDelete(0, n);
   ObjectCreate(0, n, OBJ_RECTANGLE, 0, t1, hi, t2, lo);
   ObjectSetInteger(0, n, OBJPROP_COLOR, C'40,60,110');
   ObjectSetInteger(0, n, OBJPROP_FILL, true);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
void PlaceSetup(datetime today)
  {
   datetime t1 = today + InpRangeStart * 3600;
   datetime t2 = today + InpRangeEnd * 3600;
   if(InpRangeEnd < InpRangeStart) t1 -= 86400;     // range started yesterday evening

   double hi[], lo[];
   if(CopyHigh(_Symbol, PERIOD_M5, t1, t2 - 1, hi) <= 0 ||
      CopyLow (_Symbol, PERIOD_M5, t1, t2 - 1, lo) <= 0)
     { Print("AsianBreakout: no M5 data for range yet."); return; }

   double top = hi[ArrayMaximum(hi)];
   double bot = lo[ArrayMinimum(lo)];
   double rangePips = (top - bot) / Pip();
   setupDay = today;                                // one attempt per day
   DrawRange(t1, t2, top, bot);

   if(rangePips < InpMinRangePips || rangePips > InpMaxRangePips)
     {
      PrintFormat("AsianBreakout: range %.1f pips outside filter - no trade today.", rangePips);
      return;
     }

   double buf   = InpBufferPips * Pip();
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double mid   = (top + bot) / 2.0;
   datetime exp = today + InpOrderExpire * 3600;

   double buyPx  = NormalizeDouble(top + buf, _Digits);
   double sellPx = NormalizeDouble(bot - buf, _Digits);

   double buySL  = InpSLMode == SL_OPPOSITE ? sellPx : InpSLMode == SL_MIDDLE ? mid : buyPx - InpSLPips * Pip();
   double sellSL = InpSLMode == SL_OPPOSITE ? buyPx  : InpSLMode == SL_MIDDLE ? mid : sellPx + InpSLPips * Pip();
   buySL = NormalizeDouble(buySL, _Digits); sellSL = NormalizeDouble(sellSL, _Digits);

   double buyRisk  = buyPx - buySL, sellRisk = sellSL - sellPx;
   double buyTP  = NormalizeDouble(buyPx  + buyRisk  * InpRR, _Digits);
   double sellTP = NormalizeDouble(sellPx - sellRisk * InpRR, _Digits);

   double lotsB = LotsForRisk(buyRisk), lotsS = LotsForRisk(sellRisk);
   if(lotsB <= 0 || lotsS <= 0) { Print("AsianBreakout: lot size below minimum - skipped."); return; }

   // only place a stop order if price has not already broken out
   // use broker-side expiry if allowed, otherwise GTC (the EA deletes them itself)
   long expModes = SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE);
   ENUM_ORDER_TYPE_TIME tt = ((expModes & SYMBOL_EXPIRATION_SPECIFIED) != 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
   datetime ex = (tt == ORDER_TIME_SPECIFIED) ? exp : 0;
   if(buyPx - ask > stops)
      trade.BuyStop(lotsB, buyPx, _Symbol, buySL, buyTP, tt, ex, InpComment);
   if(bid - sellPx > stops)
      trade.SellStop(lotsS, sellPx, _Symbol, sellSL, sellTP, tt, ex, InpComment);
  }

void BreakEven()
  {
   if(InpBE_R <= 0) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!pos.SelectByIndex(i) || pos.Symbol() != _Symbol || pos.Magic() != InpMagic) continue;
      double open = pos.PriceOpen(), sl = pos.StopLoss(), tp = pos.TakeProfit();
      if(sl == 0) continue;
      double risk = MathAbs(open - sl);
      if(pos.PositionType() == POSITION_TYPE_BUY && sl < open &&
         SymbolInfoDouble(_Symbol, SYMBOL_BID) - open >= risk * InpBE_R)
         trade.PositionModify(pos.Ticket(), NormalizeDouble(open + _Point, _Digits), tp);
      if(pos.PositionType() == POSITION_TYPE_SELL && sl > open &&
         open - SymbolInfoDouble(_Symbol, SYMBOL_ASK) >= risk * InpBE_R)
         trade.PositionModify(pos.Ticket(), NormalizeDouble(open - _Point, _Digits), tp);
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime now = TimeCurrent();
   MqlDateTime dt; TimeToStruct(now, dt);
   datetime today = now - (now % 86400);

   // OCO: once a position exists, cancel the remaining pending order
   if(CountMine(true) > 0 && CountMine(false) > 0) DeletePending();

   if(dt.hour >= InpOrderExpire) DeletePending();
   if(InpCloseHour >= 0 && dt.hour >= InpCloseHour) CloseAll();

   BreakEven();

   if(setupDay != today && DayAllowed(dt.day_of_week) &&
      dt.hour >= InpRangeEnd && dt.hour < InpOrderExpire &&
      CountMine(true) == 0 && CountMine(false) == 0)
      PlaceSetup(today);
  }
//+------------------------------------------------------------------+
