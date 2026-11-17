//+------------------------------------------------------------------+
//|                                        PipCraft_TrendCloud.mq5   |
//|  Coloured trend cloud between two moving averages, with buy/sell |
//|  arrows on crossovers and popup / sound / push / email alerts.   |
//+------------------------------------------------------------------+
#property copyright "PipCraft Tools"
#property version   "1.00"
#property description "Trend Cloud: green cloud = uptrend, red cloud = downtrend."
#property description "Arrows mark crossovers. Alerts fire once per closed bar."
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   3

#property indicator_label1  "Fast MA;Slow MA"
#property indicator_type1   DRAW_FILLING
#property indicator_color1  clrSeaGreen,clrIndianRed

#property indicator_label2  "Buy signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  2

#property indicator_label3  "Sell signal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_width3  2

input group "Moving averages"
input int                InpFastPeriod = 21;          // Fast MA period
input int                InpSlowPeriod = 50;          // Slow MA period
input ENUM_MA_METHOD     InpMethod     = MODE_EMA;    // MA method
input ENUM_APPLIED_PRICE InpPrice      = PRICE_CLOSE; // Applied price

input group "Signals"
input bool   InpShowArrows  = true;  // Show crossover arrows
input double InpArrowOffset = 0.5;   // Arrow distance from candle (x ATR)

input group "Alerts"
input bool InpAlertPopup = true;  // Popup alert
input bool InpAlertSound = false; // Sound alert
input bool InpAlertPush  = false; // Push notification (phone)
input bool InpAlertEmail = false; // Email alert

double FastBuf[], SlowBuf[], BuyBuf[], SellBuf[], AtrBuf[];
int    hFast = INVALID_HANDLE, hSlow = INVALID_HANDLE, hAtr = INVALID_HANDLE;
datetime lastAlertBar = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpFastPeriod < 1 || InpSlowPeriod <= InpFastPeriod)
     {
      Print("Trend Cloud: Slow period must be greater than Fast period.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   SetIndexBuffer(0, FastBuf, INDICATOR_DATA);
   SetIndexBuffer(1, SlowBuf, INDICATOR_DATA);
   SetIndexBuffer(2, BuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(3, SellBuf, INDICATOR_DATA);
   SetIndexBuffer(4, AtrBuf,  INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(1, PLOT_ARROW, 233);
   PlotIndexSetInteger(2, PLOT_ARROW, 234);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   for(int p = 0; p < 3; p++)
      PlotIndexSetInteger(p, PLOT_DRAW_BEGIN, InpSlowPeriod);
   if(!InpShowArrows)
     {
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE);
     }

   hFast = iMA(_Symbol, _Period, InpFastPeriod, 0, InpMethod, InpPrice);
   hSlow = iMA(_Symbol, _Period, InpSlowPeriod, 0, InpMethod, InpPrice);
   hAtr  = iATR(_Symbol, _Period, 14);
   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hAtr == INVALID_HANDLE)
      return(INIT_FAILED);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("Trend Cloud (%d,%d)", InpFastPeriod, InpSlowPeriod));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(hFast);
   IndicatorRelease(hSlow);
   IndicatorRelease(hAtr);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
  {
   if(rates_total < InpSlowPeriod + 2)
      return(0);
   if(BarsCalculated(hFast) < rates_total || BarsCalculated(hSlow) < rates_total ||
      BarsCalculated(hAtr) < rates_total)
      return(0);

   int toCopy = (prev_calculated <= 0 || prev_calculated > rates_total)
                ? rates_total : rates_total - prev_calculated + 1;
   if(CopyBuffer(hFast, 0, 0, toCopy, FastBuf) <= 0) return(0);
   if(CopyBuffer(hSlow, 0, 0, toCopy, SlowBuf) <= 0) return(0);
   if(CopyBuffer(hAtr,  0, 0, toCopy, AtrBuf)  <= 0) return(0);

   int start;
   if(prev_calculated <= 0)
     {
      for(int k = 0; k < rates_total; k++)
        { BuyBuf[k] = EMPTY_VALUE; SellBuf[k] = EMPTY_VALUE; }
      start = InpSlowPeriod + 1;
     }
   else
      start = prev_calculated - 1;

   for(int i = start; i < rates_total; i++)
     {
      BuyBuf[i]  = EMPTY_VALUE;
      SellBuf[i] = EMPTY_VALUE;
      bool upNow  = FastBuf[i]   > SlowBuf[i];
      bool upPrev = FastBuf[i-1] > SlowBuf[i-1];
      double off  = AtrBuf[i] * InpArrowOffset;

      if(upNow && !upPrev)  BuyBuf[i]  = low[i]  - off;
      if(!upNow && upPrev)  SellBuf[i] = high[i] + off;
     }

   // Alerts on the last CLOSED bar only (no repainting)
   int c = rates_total - 2;
   if(time[rates_total-1] != lastAlertBar && prev_calculated > 0)
     {
      lastAlertBar = time[rates_total-1];
      if(BuyBuf[c]  != EMPTY_VALUE) SendAlert("BUY",  close[c]);
      if(SellBuf[c] != EMPTY_VALUE) SendAlert("SELL", close[c]);
     }
   else if(prev_calculated <= 0)
      lastAlertBar = time[rates_total-1];

   return(rates_total);
  }

//+------------------------------------------------------------------+
void SendAlert(const string side, const double price)
  {
   string msg = StringFormat("Trend Cloud %s signal on %s %s at %s",
                             side, _Symbol, EnumToString(_Period),
                             DoubleToString(price, _Digits));
   if(InpAlertPopup) Alert(msg);
   if(InpAlertSound) PlaySound("alert.wav");
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertEmail) SendMail("Trend Cloud signal", msg);
  }
//+------------------------------------------------------------------+
