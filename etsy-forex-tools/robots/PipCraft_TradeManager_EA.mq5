//+------------------------------------------------------------------+
//|                                   PipCraft_TradeManager_EA.mq5   |
//|  Hands-free management for trades you open MANUALLY (or from     |
//|  any other EA). It never opens trades itself.                    |
//|   - Auto stop loss / take profit if you forget to set them       |
//|   - Break-even (+ lock-in pips) after X pips profit              |
//|   - Partial close at a target                                    |
//|   - Trailing stop                                                |
//|   - Close everything at a set equity profit / loss               |
//|  Attach it to ONE chart; it manages the symbols you choose.      |
//+------------------------------------------------------------------+
#property copyright "PipCraft Tools"
#property version   "1.00"
#property description "Trade Manager - break-even, partial close, trailing stop, equity guard."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

input group "Which trades"
input bool InpAllSymbols = false; // Manage ALL symbols (false = this chart only)
input long InpMagicFilter = -1;   // Only this magic (-1 = all, 0 = manual trades)

input group "Auto SL / TP (pips, 0 = off)"
input double InpAutoSL = 25;  // Add SL if missing
input double InpAutoTP = 50;  // Add TP if missing

input group "Break-even"
input double InpBEStart = 15; // Move SL to break-even at +pips (0 = off)
input double InpBELock  = 2;  // ...and lock in pips

input group "Partial close"
input double InpPartialAt  = 20; // Close part at +pips (0 = off)
input double InpPartialPct = 50; // Percent of volume to close

input group "Trailing stop"
input double InpTrailStart = 25; // Start trailing at +pips (0 = off)
input double InpTrailDist  = 15; // Trail distance (pips)
input double InpTrailStep  = 1;  // Minimum step (pips)

input group "Equity guard (account currency, 0 = off)"
input double InpCloseAllProfit = 0; // Close all when floating profit >=
input double InpCloseAllLoss   = 0; // Close all when floating loss >=

CTrade        trade;
CPositionInfo pos;
ulong partialDone[];   // tickets already partially closed

int OnInit()
  {
   trade.SetDeviationInPoints(20);
   EventSetTimer(1);   // also manage when the chart symbol is quiet
   Comment("PipCraft Trade Manager running");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) { EventKillTimer(); Comment(""); }

double PipOf(const string sym)
  {
   int d = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   return (d == 3 || d == 5) ? pt * 10.0 : pt;
  }

bool Mine()
  {
   if(!InpAllSymbols && pos.Symbol() != _Symbol) return(false);
   if(InpMagicFilter >= 0 && pos.Magic() != InpMagicFilter) return(false);
   return(true);
  }

bool WasPartial(ulong t)
  {
   for(int i = 0; i < ArraySize(partialDone); i++) if(partialDone[i] == t) return(true);
   return(false);
  }

void MarkPartial(ulong t)
  {
   int n = ArraySize(partialDone);
   ArrayResize(partialDone, n + 1);
   partialDone[n] = t;
  }

void Manage()
  {
   // ---- equity guard
   if(InpCloseAllProfit > 0 || InpCloseAllLoss > 0)
     {
      double fl = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
         if(pos.SelectByIndex(i) && Mine()) fl += pos.Profit() + pos.Swap();
      if((InpCloseAllProfit > 0 && fl >= InpCloseAllProfit) ||
         (InpCloseAllLoss   > 0 && fl <= -InpCloseAllLoss))
        {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
            if(pos.SelectByIndex(i) && Mine()) trade.PositionClose(pos.Ticket());
         PrintFormat("Trade Manager: equity guard closed all (floating %.2f)", fl);
         return;
        }
     }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!pos.SelectByIndex(i) || !Mine()) continue;
      string sym  = pos.Symbol();
      int    dig  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double pip  = PipOf(sym);
      double stopsLvl = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(sym, SYMBOL_POINT);
      bool   buy  = pos.PositionType() == POSITION_TYPE_BUY;
      double open = pos.PriceOpen(), sl = pos.StopLoss(), tp = pos.TakeProfit();
      double px   = buy ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      double profitPips = (buy ? px - open : open - px) / pip;
      ulong  ticket = pos.Ticket();
      double newSl = sl, newTp = tp;

      // ---- auto SL / TP
      if(sl == 0 && InpAutoSL > 0) newSl = buy ? open - InpAutoSL * pip : open + InpAutoSL * pip;
      if(tp == 0 && InpAutoTP > 0) newTp = buy ? open + InpAutoTP * pip : open - InpAutoTP * pip;

      // ---- partial close
      if(InpPartialAt > 0 && profitPips >= InpPartialAt && !WasPartial(ticket))
        {
         double vStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
         double vMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
         double part  = MathFloor(pos.Volume() * InpPartialPct / 100.0 / vStep) * vStep;
         if(part >= vMin && pos.Volume() - part >= vMin)
            trade.PositionClosePartial(ticket, part);
         MarkPartial(ticket);   // only try once per ticket
         if(!pos.SelectByTicket(ticket)) continue;
        }

      // ---- break-even
      if(InpBEStart > 0 && profitPips >= InpBEStart)
        {
         double be = buy ? open + InpBELock * pip : open - InpBELock * pip;
         if(buy  && (newSl < be || newSl == 0)) newSl = be;
         if(!buy && (newSl > be || newSl == 0)) newSl = be;
        }

      // ---- trailing
      if(InpTrailStart > 0 && profitPips >= InpTrailStart)
        {
         double t = buy ? px - InpTrailDist * pip : px + InpTrailDist * pip;
         if(buy  && t > newSl + InpTrailStep * pip) newSl = t;
         if(!buy && (newSl == 0 || t < newSl - InpTrailStep * pip)) newSl = t;
        }

      newSl = NormalizeDouble(newSl, dig);
      newTp = NormalizeDouble(newTp, dig);
      bool slChanged = MathAbs(newSl - sl) > SymbolInfoDouble(sym, SYMBOL_POINT) / 2;
      bool tpChanged = MathAbs(newTp - tp) > SymbolInfoDouble(sym, SYMBOL_POINT) / 2;
      if(!slChanged && !tpChanged) continue;
      // never move the SL backwards & respect broker stop level
      if(slChanged && sl != 0 && ((buy && newSl < sl) || (!buy && newSl > sl))) newSl = sl;
      if(newSl != 0 && MathAbs(px - newSl) <= stopsLvl) newSl = sl;
      if(newSl != sl || tpChanged)
         trade.PositionModify(ticket, newSl, newTp);
     }
  }

void OnTick()  { Manage(); }
void OnTimer() { Manage(); }
//+------------------------------------------------------------------+
