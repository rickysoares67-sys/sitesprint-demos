//+------------------------------------------------------------------+
//|                                      PipCraft_SessionBoxes.mq5   |
//|  Draws the Asian, London and New York session ranges as shaded   |
//|  boxes with high/low and range size in pips.                     |
//|  Session hours are entered in YOUR BROKER'S SERVER TIME          |
//|  (the time shown in Market Watch).                               |
//+------------------------------------------------------------------+
#property copyright "PipCraft Tools"
#property version   "1.00"
#property description "Session Boxes: Asia / London / New York ranges."
#property description "Enter session hours in broker server time."
#property indicator_chart_window
#property indicator_plots 0

input int  InpDays = 10; // How many days to draw

input group "Asian session"
input bool  InpAsiaOn    = true;
input int   InpAsiaStart = 0;   // Start hour (server time)
input int   InpAsiaEnd   = 8;   // End hour (server time)
input color InpAsiaColor = C'40,60,110';

input group "London session"
input bool  InpLonOn    = true;
input int   InpLonStart = 9;
input int   InpLonEnd   = 17;
input color InpLonColor = C'35,95,70';

input group "New York session"
input bool  InpNyOn    = true;
input int   InpNyStart = 15;
input int   InpNyEnd   = 23;
input color InpNyColor = C'110,55,40';

input group "Display"
input bool InpShowLabels = true; // Show range size label

const string PFX = "PCSB_";
datetime lastBar = 0;

int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME, "Session Boxes");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
   ChartRedraw();
  }

double PipSize()
  {
   return (_Digits == 3 || _Digits == 5) ? _Point * 10.0 : _Point;
  }

void DrawSession(const string name, const datetime day, int hStart, int hEnd, color clr)
  {
   datetime t1 = day + hStart * 3600;
   datetime t2 = day + hEnd * 3600;
   if(hEnd <= hStart) t2 += 86400;            // session crosses midnight
   datetime now = TimeCurrent();
   if(t1 > now) return;                        // not started yet
   datetime tEnd = (t2 > now) ? now : t2;

   double hi[], lo[];
   int n1 = CopyHigh(_Symbol, _Period, t1, tEnd - 1, hi);
   int n2 = CopyLow(_Symbol, _Period, t1, tEnd - 1, lo);
   if(n1 <= 0 || n2 <= 0) return;
   double top = hi[ArrayMaximum(hi)];
   double bot = lo[ArrayMinimum(lo)];

   string id = PFX + name + "_" + TimeToString(day, TIME_DATE);
   if(ObjectFind(0, id) < 0)
     {
      ObjectCreate(0, id, OBJ_RECTANGLE, 0, t1, top, t2, bot);
      ObjectSetInteger(0, id, OBJPROP_FILL, true);
      ObjectSetInteger(0, id, OBJPROP_BACK, true);
      ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, id, OBJPROP_COLOR, clr);
   ObjectMove(0, id, 0, t1, top);
   ObjectMove(0, id, 1, t2, bot);
   ObjectSetString(0, id, OBJPROP_TOOLTIP,
                   StringFormat("%s  High %s  Low %s", name,
                                DoubleToString(top, _Digits), DoubleToString(bot, _Digits)));

   if(InpShowLabels)
     {
      string lid = id + "_lbl";
      if(ObjectFind(0, lid) < 0)
        {
         ObjectCreate(0, lid, OBJ_TEXT, 0, t1, top);
         ObjectSetInteger(0, lid, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0, lid, OBJPROP_FONTSIZE, 8);
         ObjectSetInteger(0, lid, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, lid, OBJPROP_HIDDEN, true);
        }
      ObjectMove(0, lid, 0, t1, top);
      ObjectSetInteger(0, lid, OBJPROP_COLOR, clrSilver);
      ObjectSetString(0, lid, OBJPROP_TEXT,
                      StringFormat("%s %.1f pips", name, (top - bot) / PipSize()));
     }
  }

void DrawAll()
  {
   if(_Period >= PERIOD_D1) return;            // boxes make no sense on D1+
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today == 0) return;
   for(int d = 0; d < InpDays; d++)
     {
      datetime day = iTime(_Symbol, PERIOD_D1, d);
      if(day == 0) break;
      if(InpAsiaOn) DrawSession("Asia",   day, InpAsiaStart, InpAsiaEnd, InpAsiaColor);
      if(InpLonOn)  DrawSession("London", day, InpLonStart,  InpLonEnd,  InpLonColor);
      if(InpNyOn)   DrawSession("NY",     day, InpNyStart,   InpNyEnd,   InpNyColor);
     }
   ChartRedraw();
  }

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
  {
   // redraw on first run and on each new bar (keeps it light on CPU)
   ArraySetAsSeries(time, true);
   if(prev_calculated == 0 || time[0] != lastBar)
     {
      lastBar = time[0];
      DrawAll();
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
