
#property version   "2.02"
#property indicator_separate_window
#property indicator_minimum 0
#property indicator_buffers 2
#property indicator_plots   2

//--- plot Output (Histogram)
#property indicator_label1  "Average Speed"
#property indicator_type1   DRAW_HISTOGRAM
#property indicator_color1  clrGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
#property indicator_level1  2.0
#property indicator_levelcolor Gray
#property indicator_levelstyle STYLE_DASHDOTDOT

//--- plot StdDev (Line)
#property indicator_label2  "StdDev"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

//--- input parameters
input int n           = 3;   // Period for Average Speed
input int std_period  = 3;   // Period for Standard Deviation
input ENUM_APPLIED_PRICE price = PRICE_CLOSE; // Price type

//--- indicator buffers
double OutputBuffer[];   // Average Speed
double StdDevBuffer[];   // Standard Deviation of Speed

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- indicator buffers mapping
   SetIndexBuffer(0, OutputBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, StdDevBuffer, INDICATOR_DATA);

//--- set plot labels (optional, for DataWindow)
   PlotIndexSetString(0, PLOT_LABEL, "AvgSpeed");
   PlotIndexSetString(1, PLOT_LABEL, "StdDev");

//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
//--- check for minimum bars
   if(rates_total < MathMax(n, std_period)) return(0);

//--- determine start index (need enough bars for both periods)
   int start_limit = MathMax(n, std_period);
   int limit;
   if(prev_calculated == 0)
     {
      limit = start_limit;          // first bars not calculated
     }
   else
     {
      limit = prev_calculated - 1;  // recalculate only the last bar
     }

//--- main loop
   for(int i = limit; i < rates_total; i++)
     {
      int t = GetMinute();          // minutes per bar (constant)

      //--------------------------------------------------------------
      // 1. Average Speed over the last n bars (histogram)
      //--------------------------------------------------------------
      double sumv = 0.0;
      for(int j = i - n + 1; j <= i; j++)
        {
         double d = 0.0;  // distance in points
         switch(price)
           {
            case PRICE_CLOSE:
               d = MathAbs(close[j] - close[j-1]) / _Point;
               break;
            case PRICE_HIGH:
               d = MathAbs(high[j] - high[j-1]) / _Point;
               break;
            case PRICE_LOW:
               d = MathAbs(low[j] - low[j-1]) / _Point;
               break;
            case PRICE_MEDIAN:
               d = MathAbs((high[j] + low[j])/2 - (high[j-1] + low[j-1])/2) / _Point;
               break;
            case PRICE_OPEN:
               d = MathAbs(open[j] - open[j-1]) / _Point;
               break;
            case PRICE_TYPICAL:
               d = MathAbs((high[j] + low[j] + close[j])/3 - (high[j-1] + low[j-1] + close[j-1])/3) / _Point;
               break;
            case PRICE_WEIGHTED:
               d = MathAbs((high[j] + low[j] + close[j] + close[j])/4 - (high[j-1] + low[j-1] + close[j-1] + close[j-1])/4) / _Point;
               break;
           }
         double v = d / t;           // speed in points per minute
         sumv += v;
        }
      OutputBuffer[i] = (n > 0) ? sumv / n : 0.0;

      //--------------------------------------------------------------
      // 2. Standard Deviation over the last std_period bars (line)
      //--------------------------------------------------------------
      if(i >= std_period - 1)
        {
         double sumv_std  = 0.0;
         double sumv2_std = 0.0;
         for(int j = i - std_period + 1; j <= i; j++)
           {
            double d = 0.0;
            switch(price)
              {
               case PRICE_CLOSE:
                  d = MathAbs(close[j] - close[j-1]) / _Point;
                  break;
               case PRICE_HIGH:
                  d = MathAbs(high[j] - high[j-1]) / _Point;
                  break;
               case PRICE_LOW:
                  d = MathAbs(low[j] - low[j-1]) / _Point;
                  break;
               case PRICE_MEDIAN:
                  d = MathAbs((high[j] + low[j])/2 - (high[j-1] + low[j-1])/2) / _Point;
                  break;
               case PRICE_OPEN:
                  d = MathAbs(open[j] - open[j-1]) / _Point;
                  break;
               case PRICE_TYPICAL:
                  d = MathAbs((high[j] + low[j] + close[j])/3 - (high[j-1] + low[j-1] + close[j-1])/3) / _Point;
                  break;
               case PRICE_WEIGHTED:
                  d = MathAbs((high[j] + low[j] + close[j] + close[j])/4 - (high[j-1] + low[j-1] + close[j-1] + close[j-1])/4) / _Point;
                  break;
              }
            double v = d / t;         // speed in points per minute
            sumv_std  += v;
            sumv2_std += v * v;
           }
         double mean_std = sumv_std / std_period;
         double variance = (sumv2_std / std_period) - (mean_std * mean_std);
         if(variance < 0.0) variance = 0.0;   // guard against tiny negatives
         StdDevBuffer[i] = MathSqrt(variance);
        }
      else
        {
         StdDevBuffer[i] = 0.0;       // not enough bars yet
        }
     }

//--- return value of prev_calculated for next call
   return(rates_total);
  }
//+------------------------------------------------------------------+
//| Return the number of minutes in the current chart period        |
//+------------------------------------------------------------------+
int GetMinute()
  {
   switch(Period())
     {
      case PERIOD_M1:  return(1);
      case PERIOD_M2:  return(2);
      case PERIOD_M3:  return(3);
      case PERIOD_M4:  return(4);
      case PERIOD_M5:  return(5);
      case PERIOD_M6:  return(6);
      case PERIOD_M10: return(10);
      case PERIOD_M12: return(12);
      case PERIOD_M15: return(15);
      case PERIOD_M20: return(20);
      case PERIOD_M30: return(30);
      case PERIOD_H1:  return(60);
      case PERIOD_H2:  return(120);
      case PERIOD_H3:  return(180);
      case PERIOD_H4:  return(240);
      case PERIOD_H6:  return(360);
      case PERIOD_H8:  return(480);
      case PERIOD_H12: return(720);
      case PERIOD_D1:  return(1440);
      case PERIOD_W1:  return(10080);
      case PERIOD_MN1: return(43200);
     }
//--- default (should never happen)
   return(1);
  }
//+------------------------------------------------------------------+