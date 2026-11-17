//+------------------------------------------------------------------+
//|                                  PipCraft_LotSizeCalculator.mq5  |
//|  Drag the red "Stop Loss" line on the chart and this panel shows |
//|  the exact lot size for your chosen risk %, the money at risk    |
//|  and take-profit levels for 1R, 2R and 3R.                       |
//|  Works on forex, gold, indices and crypto (uses tick value).     |
//+------------------------------------------------------------------+
#property copyright "PipCraft Tools"
#property version   "1.00"
#property description "Lot Size Calculator: drag the SL line, get the lot size."
#property indicator_chart_window
#property indicator_plots 0

enum ENUM_RISK_BASE { RISK_BALANCE = 0, // Balance
                      RISK_EQUITY  = 1, // Equity
                      RISK_FIXED   = 2  // Fixed amount
                    };

input ENUM_RISK_BASE InpBase       = RISK_BALANCE; // Risk based on
input double         InpRiskPct    = 1.0;          // Risk % (Balance/Equity)
input double         InpFixedMoney = 100.0;        // Fixed risk amount (account currency)
input double         InpStartPips  = 20.0;         // Initial SL distance (pips)
input color          InpLineColor  = clrRed;       // SL line colour
input int            InpCorner     = CORNER_LEFT_UPPER; // Panel corner (0-3)

const string PFX     = "PCLS_";
const string SL_LINE = "PCLS_SL";

double PipSize()
  {
   return (_Digits == 3 || _Digits == 5) ? _Point * 10.0 : _Point;
  }

int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME, "Lot Size Calculator");
   if(ObjectFind(0, SL_LINE) < 0)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      ObjectCreate(0, SL_LINE, OBJ_HLINE, 0, 0, bid - InpStartPips * PipSize());
     }
   ObjectSetInteger(0, SL_LINE, OBJPROP_COLOR, InpLineColor);
   ObjectSetInteger(0, SL_LINE, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, SL_LINE, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, SL_LINE, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, SL_LINE, OBJPROP_SELECTED, true);
   ObjectSetString(0, SL_LINE, OBJPROP_TEXT, "Stop Loss (drag me)");
   Update();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   // keep the SL line where the user left it when only the timeframe changes
   if(reason == REASON_CHARTCHANGE || reason == REASON_PARAMETERS || reason == REASON_RECOMPILE)
     {
      double keep = ObjectGetDouble(0, SL_LINE, OBJPROP_PRICE);
      ObjectsDeleteAll(0, PFX);
      ObjectCreate(0, SL_LINE, OBJ_HLINE, 0, 0, keep);
     }
   else
      ObjectsDeleteAll(0, PFX);   // removed from chart: clean everything
   ChartRedraw();
  }

void Label(const string id, const int row, const string text, const color clr = clrWhite)
  {
   string n = PFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, InpCorner);
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   bool bottom = (InpCorner == CORNER_LEFT_LOWER || InpCorner == CORNER_RIGHT_LOWER);
   bool right  = (InpCorner == CORNER_RIGHT_UPPER || InpCorner == CORNER_RIGHT_LOWER);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,
                    bottom ? (right ? ANCHOR_RIGHT_LOWER : ANCHOR_LEFT_LOWER)
                           : (right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER));
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, 12);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, 20 + row * 18);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetString(0, n, OBJPROP_TEXT, text);
  }

void TPLine(const string id, const double price, const string text)
  {
   string n = PFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clrMediumSeaGreen);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   ObjectSetDouble(0, n, OBJPROP_PRICE, price);
   ObjectSetString(0, n, OBJPROP_TEXT, text);
  }

void Update()
  {
   if(ObjectFind(0, SL_LINE) < 0) return;
   double sl  = ObjectGetDouble(0, SL_LINE, OBJPROP_PRICE);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool   isBuy = sl < bid;
   double entry = isBuy ? ask : bid;
   double dist  = MathAbs(entry - sl);

   string ccy = AccountInfoString(ACCOUNT_CURRENCY);
   double riskMoney;
   if(InpBase == RISK_FIXED)       riskMoney = InpFixedMoney;
   else if(InpBase == RISK_EQUITY) riskMoney = AccountInfoDouble(ACCOUNT_EQUITY)  * InpRiskPct / 100.0;
   else                            riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0) tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double vMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double lots = 0, lossPerLot = 0;
   if(dist > 0 && tickSize > 0 && tickValue > 0)
     {
      lossPerLot = dist / tickSize * tickValue;
      lots = riskMoney / lossPerLot;
      lots = MathFloor(lots / vStep) * vStep;     // round DOWN – never over-risk
      lots = MathMin(lots, vMax);
     }
   bool tooSmall = lots < vMin;
   int  volDigits = (int)MathMax(0, MathCeil(-MathLog10(vStep)));
   double realRisk = lots * lossPerLot;
   double pips = dist / PipSize();

   Label("t",  0, "== LOT SIZE CALCULATOR ==", clrGold);
   Label("d",  1, StringFormat("Direction : %s", isBuy ? "BUY" : "SELL"),
         isBuy ? clrLimeGreen : clrTomato);
   Label("e",  2, StringFormat("Entry     : %s", DoubleToString(entry, _Digits)));
   Label("s",  3, StringFormat("Stop loss : %s  (%.1f pips)", DoubleToString(sl, _Digits), pips));
   Label("r",  4, StringFormat("Risk      : %.2f %s", riskMoney, ccy));
   Label("l",  5, tooSmall ? StringFormat("LOT SIZE  : below min %.2f - widen risk", vMin)
                           : StringFormat("LOT SIZE  : %s", DoubleToString(lots, volDigits)),
         tooSmall ? clrTomato : clrAqua);
   Label("a",  6, StringFormat("Real risk : %.2f %s", tooSmall ? 0.0 : realRisk, ccy));

   for(int r = 1; r <= 3; r++)
     {
      double tp = isBuy ? entry + dist * r : entry - dist * r;
      Label("tp" + IntegerToString(r), 6 + r,
            StringFormat("TP %dR     : %s  (+%.2f %s)", r, DoubleToString(tp, _Digits),
                         tooSmall ? 0.0 : realRisk * r, ccy), clrMediumSeaGreen);
      TPLine("tpl" + IntegerToString(r), tp, StringFormat("TP %dR", r));
     }
   ChartRedraw();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if((id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_CHANGE) && sparam == SL_LINE)
      Update();
  }

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
  {
   Update();   // keep entry price live
   return(rates_total);
  }
//+------------------------------------------------------------------+
