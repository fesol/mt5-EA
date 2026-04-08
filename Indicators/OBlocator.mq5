//+------------------------------------------------------------------+
//|                                                    OrderBlock.mq5| 
//+------------------------------------------------------------------+

//--- indicator settings
#property indicator_chart_window
#property indicator_buffers 4
// #property indicator_plots   4
#property indicator_plots   0
//#property indicator_type1   DRAW_ARROW // 
//#property indicator_type2   DRAW_ARROW //
//#property indicator_type3   DRAW_ARROW //  
//#property indicator_type4   DRAW_ARROW // 
//#property indicator_color1  clrOrange
//#property indicator_color2  clrGreenYellow
//#property indicator_color3  clrBlueViolet 
//#property indicator_color4  clrDarkGoldenrod
//#property indicator_label1  "AM Up Fractal"
//#property indicator_label2  "AM Down Fractal"
//#property indicator_label3  "AM Bullish OrderBlock"
//#property indicator_label4  "AM Bearish OrderBlock"

//--- indicator buffers
double AMUpperFractalBuffer[];
double AMLowerFractalBuffer[];
double AMBullishOrderBlockLowBuffer[];
double AMBearishOrderBlockHighBuffer[];

//--- 20 pixels upper from high/low price
int    AMFractalArrowShift=-25;
int    AMOrderBlockArrowShift=10;

//--- enums
enum OB_Object_Drawer
{
   OB_Rectangle = 0, // Rectangle
   OB_TrendLine = 1, // Horizontal Line
};
ENUM_OBJECT OB_OBJECT_TYPE = OBJ_RECTANGLE; // default

enum OB_Termination
{
   OB_FirstTouch = 0, // First Touch
   OB_BreakOut = 1 // Break Out Above/Under
};

enum OB_Algorithm
{
   OB_Simple_Search = 0, // Simple Fractal Search Algorithm
   OB_Naive_Search = 2, // Naive Fractal Movers Algorithm
   OB_Transition_Search = 3, // Candle Transition Algorithm
   OB_Mixed_Search_NT = 4, // Mixed Search (Naive + Transition)
   OB_Mixed_Search_FT = 5 // Mixed Search (Fractal + Transition)
};

//+-----------------------------------+
//|  INDICATOR INPUT PARAMETERS       |
//+-----------------------------------+
input int lookBackLimit = 500; // Look Back Candle Limit (0 for all)
//
input string Notes1  =" == + Order Block Settings + == ";
input bool showBullishOrderBlocks = true; // Show Bullish OrderBlocks
input color orderBlockBullsColor =clrGreen; // Bullish OrderBlock Color
input bool showBearishOrderBlocks = true; // Show Bearish OrderBlocks
input color orderBlockBearsColor = clrDarkMagenta; // Bearish OrderBlock Color
input bool hideMitigatedOB = true; // Hide mitigated Order Blocks
input OB_Algorithm orderBlockAlgo = OB_Simple_Search; // Order Block Locator Algorithm
// 
input OB_Object_Drawer orderBlockObject = OB_Rectangle; // Object to show Order Block 
input OB_Termination orderBlockTermination = OB_FirstTouch; // OrderBlock Termination By 
//
input string Notes2  =" == + If Rectangle and First Touch extras + == ";
input bool showClustredOrderBlocks = true; // If First Touch: Show Clustered OrderBlocks
input int orderBlockFastMoveRange = 7; // If First Touch: Clustered OB Candle Range
input color orderBlockClusterColor = clrBeige; // If First Touch: Clustered Order Block  Color
//
input string Notes3  =" == + Fractal Algorithm Settings + == ";
input int candlesAroundFractal = 10; // Candles Around Fractal (High/Low)
bool showFractals = false; // Show Fractals
color fractalHighColor = clrOrange; // Fractal High Color
color fractalLowColor = clrGreenYellow; // Fractal Low Color
//
input string Notes4  =" == + Candle Transition Settings + == ";
input int candlesAfterTransition = 4; // One Directional Candles after transition
input bool transitionMustEngulf = false; // Transision Candles must be engulfing
//
input string Notes5  =" == + Naive Mover Settings + == ";
input int naiveFractalCandles = 2; // Naive Candles Count(2/3 recommended)
input int naiveCandleFastMoveLimit = 4; // Fast Move Detection Candle Limit
//
string OrderBlockObjStr = "AM_OrderBlock";
int CandleCount; 

//+------------------------------------------------------------------+
//| deinitialization function                             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, OrderBlockObjStr, -1, -1); // this must delete everything but its not working
   Comment("");
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+

void OnInit()
  {
   //--- indicator buffers mapping
      SetIndexBuffer(0,AMUpperFractalBuffer,INDICATOR_DATA);
      SetIndexBuffer(1,AMLowerFractalBuffer,INDICATOR_DATA);
      SetIndexBuffer(2,AMBullishOrderBlockLowBuffer,INDICATOR_DATA);
      SetIndexBuffer(3,AMBearishOrderBlockHighBuffer,INDICATOR_DATA);
      IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   //--- sets first bar from what index will be drawn
      //PlotIndexSetInteger(0,PLOT_ARROW, 174);
     // PlotIndexSetInteger(1,PLOT_ARROW, 174);
      //PlotIndexSetInteger(2,PLOT_ARROW, 241);
     // PlotIndexSetInteger(3,PLOT_ARROW, 242);
   //--- arrow colors
     // PlotIndexSetInteger(0,PLOT_LINE_COLOR, fractalHighColor);
      //PlotIndexSetInteger(1,PLOT_LINE_COLOR, fractalLowColor);
      //PlotIndexSetInteger(2,PLOT_LINE_COLOR, orderBlockBullsColor);
      //PlotIndexSetInteger(3,PLOT_LINE_COLOR, orderBlockBearsColor);
   //--- arrow shifts when drawing
      //PlotIndexSetInteger(0,PLOT_ARROW_SHIFT,AMFractalArrowShift);
      //PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,-AMFractalArrowShift);
      //PlotIndexSetInteger(2,PLOT_ARROW_SHIFT,AMOrderBlockArrowShift);
      //PlotIndexSetInteger(3,PLOT_ARROW_SHIFT,-AMOrderBlockArrowShift);
   //--- sets drawing line empty value--
      //PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      //PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      //PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      //PlotIndexSetDouble(3,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   //---
      ArraySetAsSeries(AMUpperFractalBuffer,true);
      ArraySetAsSeries(AMLowerFractalBuffer,true);
      ArraySetAsSeries(AMBullishOrderBlockLowBuffer,true);
      ArraySetAsSeries(AMBearishOrderBlockHighBuffer,true);
   //---
      switch(orderBlockObject) {
         case 0 : OB_OBJECT_TYPE = OBJ_RECTANGLE; break;
         case 1 : OB_OBJECT_TYPE =  OBJ_TREND; break;
      }
   //---
     CandleCount = candlesAroundFractal;
     if(orderBlockAlgo == OB_Naive_Search)
     {
      CandleCount=naiveFractalCandles;
     }
     if(orderBlockAlgo == OB_Transition_Search)
     {
      CandleCount=candlesAfterTransition;
     }
  }
  
//+------------------------------------------------------------------+
//|  Fractals on 5 bars                                              |
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
  ArraySetAsSeries(open,true);
  ArraySetAsSeries(high,true);
  ArraySetAsSeries(low,true);
  ArraySetAsSeries(close,true);
  ArraySetAsSeries(time,true);
  
  int limit;
  if(lookBackLimit > rates_total) 
  {
      limit = rates_total - (CandleCount*2 + 1);
  }else if(lookBackLimit == 0) 
  {
      limit = rates_total - (CandleCount*2 + 1);
  }
  else 
  {
      limit = lookBackLimit;
  }
  
   if(rates_total <  (CandleCount*2 + 1)) {
      return(prev_calculated);
   }

//--- clean up arrays
   int start;
   if(prev_calculated < (CandleCount*2 + 1) + CandleCount)
     {
      start=CandleCount;
      ArrayInitialize(AMUpperFractalBuffer,EMPTY_VALUE);
      ArrayInitialize(AMLowerFractalBuffer,EMPTY_VALUE);
      ArrayInitialize(AMBullishOrderBlockLowBuffer,EMPTY_VALUE);
      ArrayInitialize(AMBearishOrderBlockHighBuffer,EMPTY_VALUE);
     }
   else
      start=limit - (CandleCount*2 + 1);
      
//--- main cycle of calculations
   for(int i = limit - CandleCount + 1; i > CandleCount && !IsStopped(); i--)
     {
      if(orderBlockAlgo == OB_Transition_Search) 
      {
         if(showBullishOrderBlocks) searchTransitionBullishOrderBlock(open,high,low,close,time,i);
         if(showBearishOrderBlocks) searchTransitionBearishOrderBlock(open,high,low,close,time,i);
      }
      else
      {
         //--- Upper Fractal
         if(isUpperFractal(high, CandleCount, i))
            {
               AMUpperFractalBuffer[i]= showFractals == true ? high[i] : EMPTY_VALUE;
               if(showBearishOrderBlocks) 
               {
                  if(orderBlockAlgo == OB_Simple_Search || orderBlockAlgo == OB_Mixed_Search_FT) searchExtremumBearishOrderBlock(open,high,low,close,time,i);
                  if(orderBlockAlgo == OB_Naive_Search || orderBlockAlgo == OB_Mixed_Search_NT) searchNaiveBearishOrderBlock(open,high,low,close,time,i);
               }
            }
         else
            {
               AMUpperFractalBuffer[i]=EMPTY_VALUE;
               AMBearishOrderBlockHighBuffer[i] = EMPTY_VALUE;
               if(showBearishOrderBlocks) 
               {
                  if(orderBlockAlgo == OB_Mixed_Search_NT || orderBlockAlgo == OB_Mixed_Search_FT)
                  {  
                     searchTransitionBearishOrderBlock(open,high,low,close,time,i);
                  }
               }
            }
   
         //--- Lower Fractal
         if(isLowerFractal(low, CandleCount, i))
         {
            AMLowerFractalBuffer[i]= showFractals == true ? low[i] : EMPTY_VALUE;
            if(showBullishOrderBlocks) 
            {
               if(orderBlockAlgo == OB_Simple_Search || orderBlockAlgo == OB_Mixed_Search_FT) searchExtremumBullishOrderBlock(open,high,low,close,time,i);
               if(orderBlockAlgo == OB_Naive_Search || orderBlockAlgo == OB_Mixed_Search_NT) searchNaiveBullishOrderBlock(open,high,low,close,time,i);
            }       
         }
         else
         {
            AMLowerFractalBuffer[i]=EMPTY_VALUE;
            AMBullishOrderBlockLowBuffer[i] = EMPTY_VALUE;
            if(showBullishOrderBlocks) 
            {
               if(orderBlockAlgo == OB_Mixed_Search_NT || orderBlockAlgo == OB_Mixed_Search_FT)
               {
                  searchTransitionBullishOrderBlock(open,high,low,close,time,i);                  
               }
            }
         }
       }
      
   }
     
//--- OnCalculate done. Return new prev_calculated.
   return(rates_total);
}

//+------------------------------------------------------------------+
//|     Is High fractal detector                                     |
//+------------------------------------------------------------------+
bool isUpperFractal(const double &high[], int n, int i)
{
   bool passed = true;
   for(int k=1; k <= n; k++)
   {
      if(high[i]>high[i+k] && high[i]>=high[i-k])
         continue;
      else
         {
            passed = false;
            break;
         }
   }
   return passed;
}

//+------------------------------------------------------------------+
//|     Is Low fractal detector                                      |
//+------------------------------------------------------------------+
bool isLowerFractal(const double &low[], int n, int i)
{
   bool passed = true;
   for(int k=1; k <= n; k++)
   {
      if(low[i]<low[i+k] && low[i]<=low[i-k])
         continue;
      else
         {
            passed = false;
            break;
         }
   }
   return passed;
}

//+------------------------------------------------------------------+
//|      Is Bullish Candle Detector                                  |
//+------------------------------------------------------------------+
bool IsBullishCandle(double open_price, double close_price)
  {
   if(open_price == close_price) //doji
      return false;
   return close_price > open_price;
  }

//+------------------------------------------------------------------+
//|     Is bearish Candle Detector                                   |
//+------------------------------------------------------------------+
bool IsBearishCandle(double open_price, double close_price)
  {
   if(open_price == close_price) //doji
      return false;
   return close_price < open_price;
  }


//+------------------------------------------------------------------+
//|      Get Object Name                          |
//+------------------------------------------------------------------+
string getObjectName(string theName)
{
   return theName;
}


//+------------------------------------------------------------------+
//|      Extrema Bullish Order Block Search                          |
//+------------------------------------------------------------------+
int searchExtremumBullishOrderBlock(
   const double &open[],
   const double &high[], 
   const double &low[],
   const double &close[],  
   const datetime &time[], 
   int i
   ){
   //Bullish OrderBlock Search search range = 4
   double bears_array[4];
   int bears_indexes[4];
   for(int x=0; x<4; x++)
     {
      bears_array[x]=99999999999999.99;
      bears_indexes[x]=0.0;
     }

   int s_arr[1];
   for(int s=i; s<=i+4; s++)
     {
      s_arr[0] = s;
      
      int arrSize2 = ArraySize(open);
      if(s >= arrSize2) return(0);
      if(IsBearishCandle(open[s], close[s]))
        {
         ArrayInsert(bears_indexes, s_arr, 0, 0, 1); // copy/insert the corresponding price index
         ArrayInsert(bears_array, low, 0, s, 1); // copy/insert the price_low
        }
      //
     }
     
   int idx = bears_indexes[ArrayMinimum(bears_array)];
   AMBullishOrderBlockLowBuffer[idx] = low[idx];
   
   string OBRecName = getObjectName(OrderBlockObjStr + (string)idx + "+OB");
   ResetLastError();  
   if(!ObjectCreate(0,OBRecName,OB_OBJECT_TYPE,0,time[idx],high[idx],time[idx],high[idx])) 
   { 
      Print(__FUNCTION__, 
            ": failed to create a rectangle! Error code = ",GetLastError()); 
      return(false); 
   }
   //--- set rectangle color 
   ObjectSetInteger(0,OBRecName,OBJPROP_COLOR,orderBlockBullsColor); 
   ObjectSetInteger(0,OBRecName,OBJPROP_FILL,orderBlockBullsColor);  
   ObjectSetInteger(0,OBRecName,OBJPROP_BACK,1);

   //--- move the anchor point 
   int fastMoveTrack = 0; //
   bool foundSpaceBetween = false;
   for(int d=idx;d>=0;d--)
   {
      ResetLastError(); 
      double orderBlockHigh = high[idx];
      double orderBlockLow = low[idx];
      if(!ObjectMove(0,OBRecName,0,time[d],OB_OBJECT_TYPE == OBJ_RECTANGLE ? low[idx]: high[idx])) 
      { 
         Print(__FUNCTION__, 
               ": failed to move the anchor point! Error code = ",GetLastError()); 
         return(false);
      }
      
      if(orderBlockTermination == OB_FirstTouch)
      {
         // There has to be space before the touch; Space also help determine fast moves away
         // If no space continue; if not space it also means there is no fast move
         if(low[d]>orderBlockHigh && high[d]>orderBlockHigh)
         {
            foundSpaceBetween = true;
         }
         else 
         {
            fastMoveTrack+=1;
         }
         
         if(foundSpaceBetween)
         {
            // If a candle's low has touched the orderblocks's high then stop
            if(low[d]<=orderBlockHigh)
            {
               if(hideMitigatedOB) ObjectDelete(0, OBRecName);
               break;
            }
         }
         else
         {
            // violated Order block: 
            // current close already below ordeblock's close/low
            if(close[d]<orderBlockLow)
            {
               if(hideMitigatedOB) ObjectDelete(0, OBRecName);
               break;
            }
            // If Slow move detected
            if(fastMoveTrack>=orderBlockFastMoveRange)
            {
               if(showClustredOrderBlocks && OB_OBJECT_TYPE == OBJ_RECTANGLE)
               {
                  ObjectSetInteger(0,OBRecName,OBJPROP_COLOR,orderBlockClusterColor); 
                  ObjectSetInteger(0,OBRecName,OBJPROP_FILL,orderBlockClusterColor);
                  break;
               }
               if(!showClustredOrderBlocks)
               {
                  ObjectDelete(0, OBRecName);
                  break;
               }
            }
         }
      }
      
      if(orderBlockTermination == OB_BreakOut)
      {
         if(close[d]<orderBlockLow)
         {
            if(hideMitigatedOB) ObjectDelete(0, OBRecName);
            break;
         }
      }
   }
   return (0);
} 
//--- End of searchExtremumBullishOrderBlock

//+------------------------------------------------------------------+
//|      Extrema Bearish Order Block Search                          |
//+------------------------------------------------------------------+
int searchExtremumBearishOrderBlock(
   const double &open[],
   const double &high[], 
   const double &low[],
   const double &close[],  
   const datetime &time[], 
   int i
   ){
   //OrderBlock Search search range = 4 candles going backwards
   double bulls_array[4];
   int bulls_indexes[4];
   for(int x=0; x<4; x++)
   {
      bulls_array[x]=0.0;
      bulls_indexes[x]=0.0;
   }

   int s_arr[1];
   for(int s=i; s<=i+4; s++)
   {
      s_arr[0] = s;
      // Print("i ",i," s ", s, " time ", time[s]);
      int arrSize = ArraySize(open);
      if(s >= arrSize) return(0);
      if(IsBullishCandle(open[s], close[s]))
      {
         ArrayInsert(bulls_indexes, s_arr, 0, 0, 1); // copy/insert the corresponding price index
         ArrayInsert(bulls_array, high, 0, s, 1); // copy/insert the price_high
      }
    }
   // ArrayPrint(s_arr);
   int idx = bulls_indexes[ArrayMaximum(bulls_array)];
   AMBearishOrderBlockHighBuffer[idx] = high[idx];

   string OBRecName = getObjectName(OrderBlockObjStr + (string)idx + "-OB");
   ResetLastError();  
   if(!ObjectCreate(0,OBRecName,OB_OBJECT_TYPE,0,time[idx],low[idx],time[idx],low[idx])) 
   { 
      Print(__FUNCTION__, 
            ": failed to create a rectangle! Error code = ",GetLastError()); 
      return(false); 
   }
   //--- set rectangle color 
   ObjectSetInteger(0,OBRecName,OBJPROP_COLOR,orderBlockBearsColor); 
   ObjectSetInteger(0,OBRecName,OBJPROP_FILL,orderBlockBearsColor);  
   ObjectSetInteger(0,OBRecName,OBJPROP_BACK,1);

   //--- move the anchor point 
   
   // If price has moved away from order block
   // 
   int fastMoveTrack = 0; //
   bool foundSpaceBetween = false;
   for(int d=idx;d>=0;d--)
   {
      ResetLastError(); 
      double orderBlockLow = low[idx];
      double orderBlockHigh = high[idx];
      if(!ObjectMove(0,OBRecName,0,time[d],OB_OBJECT_TYPE == OBJ_RECTANGLE ? high[idx] : low[idx])) 
      { 
         Print(__FUNCTION__, 
               ": failed to move the anchor point! Error code = ",GetLastError()); 
         return(false);
      }

      if(orderBlockTermination == OB_FirstTouch)
      {
         // There has to be space before the touch; Space also help determine fast moves away
         // If no space continue; if not space it also means there is no fast move
         if(low[d]<orderBlockLow && high[d]<orderBlockLow)
         {
            foundSpaceBetween = true;
         }
         else 
         {
            fastMoveTrack+=1;
         }
         
         if(foundSpaceBetween)
         {
            // If a candle\s high has touched the orderblock's low
            if(high[d]>=orderBlockLow)
            {
               if(hideMitigatedOB) ObjectDelete(0, OBRecName);
               break;
            }
         }
         else 
         {
            // violated Order block: 
            // current close already above ordeblock's high/closing
            if(close[d]>orderBlockHigh)
            {
               if(hideMitigatedOB) ObjectDelete(0, OBRecName);
               break;
            }
            // If Slow move detected
            if(fastMoveTrack>=orderBlockFastMoveRange)
            {
               if(showClustredOrderBlocks && OB_OBJECT_TYPE == OBJ_RECTANGLE)
               {
                  ObjectSetInteger(0,OBRecName,OBJPROP_COLOR,orderBlockClusterColor); 
                  ObjectSetInteger(0,OBRecName,OBJPROP_FILL,orderBlockClusterColor);
                  break;
               }
               if(!showClustredOrderBlocks)
               {
                  ObjectDelete(0, OBRecName);
                  break;
               }
            }
            
         }
      }
      
      if(orderBlockTermination == OB_BreakOut)
      {
         if(close[d]>orderBlockHigh)
         {
            if(hideMitigatedOB) ObjectDelete(0, OBRecName);
            break;
         }
      }
   }

   return(0);
}
// --- End of searchExtremumBearishOrderBlock




//+------------------------------------------------------------------+
//|      Naive Bearish Order Block Search                            |
//+------------------------------------------------------------------+
int searchNaiveBearishOrderBlock(
   const double &open[],
   const double &high[], 
   const double &low[],
   const double &close[],  
   const datetime &time[], 
   int i
   ){
   // Find the first OrderBlock in Search going back 4 steps
   // order block must be near the high as much as possible thus 4
   int idx = i;
   for(int s=i; s<=i+4; s++)
   {
      if(s >= ArraySize(open)) return(0);
      if(IsBullishCandle(open[s], close[s]))
      {
         idx = s;
         break;
      };
   }
   
   double orderBlockLow = low[idx];
   double orderBlockHigh = high[idx];
   
   // Find Order Block Fast Move Search range  check
   // Must pass the test for fast move within search range
   bool orderBlockPassed = false;
   int qualifierIdx = i;
   for(int s=idx; s>=idx-naiveCandleFastMoveLimit; s--)
   {
      if(s >= ArraySize(open)) return(0);
      if(IsBearishCandle(open[s], close[s]))
      {
         if(orderBlockLow>close[s] && orderBlockLow<open[s])
         {
            orderBlockPassed = true;
            qualifierIdx = s;
            break;
         }
      }
    }
    
    if(orderBlockPassed)
    {
       AMBearishOrderBlockHighBuffer[idx] = high[idx];
      string OBRecName = getObjectName(OrderBlockObjStr + (string)idx + "-OB");
      ResetLastError();  
      if(!ObjectCreate(0,OBRecName,OB_OBJECT_TYPE,0,time[idx],low[idx],time[idx],low[idx])) 
      { 
         Print(__FUNCTION__, 
               ": failed to create a rectangle! Error code = ",GetLastError()); 
         return(false); 
      }
      //--- set rectangle color 
      ObjectSetInteger(0,OBRecName,OBJPROP_COLOR,orderBlockBearsColor); 
      ObjectSetInteger(0,OBRecName,OBJPROP_FILL,orderBlockBearsColor);  
      ObjectSetInteger(0,OBRecName,OBJPROP_BACK,1);
      
      bool foundSpaceBetween = false;
      for(int d=idx;d>=0;d--)
      {
         ResetLastError(); 
         if(!ObjectMove(0,OBRecName,0,time[d],OB_OBJECT_TYPE == OBJ_RECTANGLE ? high[idx] : low[idx])) 
         { 
            Print(__FUNCTION__, 
                  ": failed to move the anchor point! Error code = ",GetLastError()); 
            return(false);
         }
         
         if(low[d]<orderBlockLow && high[d]<orderBlockLow && d<qualifierIdx)
         {
            foundSpaceBetween = true;
         }
         
         // violated Order block: current close already above ordeblock's closing/high
         if(!foundSpaceBetween && close[d]>orderBlockHigh)
         {
            if(hideMitigatedOB) ObjectDelete(0, OBRecName);
            break;
         }
            
         if(orderBlockTermination == OB_FirstTouch && foundSpaceBetween)
         {
            // If a candle\s high has touched the orderblock's low
            if(high[d]>=orderBlockLow)
            {
               if(hideMitigatedOB) ObjectDelete(0, OBRecName);
               break;
            }
         }
         
         if(orderBlockTermination == OB_BreakOut)
         {
            if(close[d]>orderBlockHigh)
            {
               if(hideMitigatedOB) ObjectDelete(0, OBRecName);
               break;
            }
         }

      }
   }
   
   return(0);
}
//---  End of searchNaiveBearishOrderBlock

//+------------------------------------------------------------------+
//|      Naive Bullish Order Block Search                            |
//+------------------------------------------------------------------+
int searchNaiveBullishOrderBlock(
   const double &open[],
   const double &high[], 
   const double &low[],
   const double &close[],  
   const datetime &time[], 
   int i
   ){
   // Find the first OrderBlock in Search going back 4 steps
   // order block must be near the high as much as possible thus 4
   int idx = i;
   for(int s=i; s<=i+4; s++)
   {
      if(s >= ArraySize(open)) return(0);
      if(IsBearishCandle(open[s], close[s]))
      {
         idx = s;
         break;
      };
   }
   
   double orderBlockLow = low[idx];
   double orderBlockHigh = high[idx];
   
   // Find Order Block Fast Move Search range  check
   // Must pass the test for fast move within search range
   bool orderBlockPassed = false;
   int qualifierIdx = i;
   for(int s=idx; s>=idx-naiveCandleFastMoveLimit; s--)
   {
      if(s >= ArraySize(open)) return(0);
      if(IsBullishCandle(open[s], close[s]))
      {
         if(orderBlockHigh<close[s] && orderBlockHigh>open[s])
         {
            orderBlockPassed = true;
            qualifierIdx = s;
            break;
         }
      }
    }
    
    if(orderBlockPassed)
    {
      AMBullishOrderBlockLowBuffer[idx] = low[idx];
      string OBRecName = getObjectName(OrderBlockObjStr + (string)idx + "+OB");
      ResetLastError();  
      if(!ObjectCreate(0,OBRecName,OB_OBJECT_TYPE,0,time[idx],high[idx],time[idx],high[idx])) 
      { 
         Print(__FUNCTION__, 
               ": failed to create a rectangle! Error code = ",GetLastError()); 
         return(false); 
      }
      //--- set rectangle color 
      ObjectSetInteger(0,OBRecName,OBJPROP_COLOR,orderBlockBullsColor); 
      ObjectSetInteger(0,OBRecName,OBJPROP_FILL,orderBlockBullsColor);  
      ObjectSetInteger(0,OBRecName,OBJPROP_BACK,1);
      
      bool foundSpaceBetween = false;
      for(int d=idx;d>=0;d--)
      {
         ResetLastError(); 
         if(!ObjectMove(0,OBRecName,0,time[d],OB_OBJECT_TYPE == OBJ_RECTANGLE ? low[idx] : high[idx])) 
         { 
            Print(__FUNCTION__, 
                  ": failed to move the anchor point! Error code = ",GetLastError()); 
            return(false);
         }
         
         if(high[d]>orderBlockHigh && low[d]>orderBlockHigh && d<qualifierIdx)
         {
            foundSpaceBetween = true;
         }
         
         // violated Order block: current close already below ordeblock's closing
         if(!foundSpaceBetween && close[d]<close[idx])  // close[d]<orderBlocLow
         {
            if(hideMitigatedOB) ObjectDelete(0, OBRecName);
            break;
         }
            
         if(orderBlockTermination == OB_FirstTouch && foundSpaceBetween)
         {
            // If a candle\s high has touched the orderblock's low
            if(low[d]<=orderBlockHigh)
            {
               if(hideMitigatedOB) ObjectDelete(0, OBRecName);
               break;
            }
         }
         
         if(orderBlockTermination == OB_BreakOut)
         {
            if(close[d]<close[idx]) // close[d]<orderBlocLow
            {
               if(hideMitigatedOB) ObjectDelete(0, OBRecName);
               break;
            }
         }

      }
   }
   
   return(0);
}
//--- End of searchNaiveBullishOrderBlock



//+------------------------------------------------------------------+
//|      Transision Bearish Order Block Search                            |
//+------------------------------------------------------------------+
int searchTransitionBearishOrderBlock(
   const double &open[],
   const double &high[], 
   const double &low[],
   const double &close[],  
   const datetime &time[], 
   int i
   ){
   // Find the first OrderBlock in Search going back 4 steps
   // order block must be near the high as much as possible thus 4
   int idx = i;
   int lastTransisionIndx = i;
   
   bool possileOBIdentfied = false;
   if(IsBullishCandle(open[i], close[i]))
   {  
      possileOBIdentfied = true;
      for(int s=idx-1; s>=idx-candlesAfterTransition; s--)
      {
         lastTransisionIndx = s;
         if(s >= ArraySize(open)) return(0);
         if(IsBullishCandle(open[s], close[s]))
         {
            possileOBIdentfied = false;
            break;
         };
      }
   }
   
   if(!possileOBIdentfied) return (0);
   if(close[lastTransisionIndx]>low[idx]) return (0);
   
   if(transitionMustEngulf)
   {
      if(low[idx-1]>low[idx]) return (0); // low engulfer: use close for body engulfer
   }
   
   double orderBlockLow = low[idx];
   double orderBlockHigh = high[idx];

   AMBearishOrderBlockHighBuffer[idx] = high[idx];
   string OBRecName = getObjectName(OrderBlockObjStr + (string)idx + "-OB");
   ResetLastError();  
   if(!ObjectCreate(0,OBRecName,OB_OBJECT_TYPE,0,time[idx],low[idx],time[idx],low[idx])) 
   { 
      Print(__FUNCTION__, 
            ": failed to create a rectangle! Error code = ",GetLastError()); 
      return(false); 
   }
   //--- set rectangle color 
   ObjectSetInteger(0,OBRecName,OBJPROP_COLOR,orderBlockBearsColor); 
   ObjectSetInteger(0,OBRecName,OBJPROP_FILL,orderBlockBearsColor);  
   ObjectSetInteger(0,OBRecName,OBJPROP_BACK,1);
   
   bool foundSpaceBetween = false;
   for(int d=idx;d>=0;d--)
   {
      ResetLastError(); 
      if(!ObjectMove(0,OBRecName,0,time[d],OB_OBJECT_TYPE == OBJ_RECTANGLE ? high[idx] : low[idx])) 
      { 
         Print(__FUNCTION__, 
               ": failed to move the anchor point! Error code = ",GetLastError()); 
         return(false);
      }
      
      if(low[d]<orderBlockLow && high[d]<orderBlockLow)
      {
         foundSpaceBetween = true;
      }
      
      // violated Order block: current close already above ordeblock's closing/high
      if(!foundSpaceBetween && close[d]>orderBlockHigh)
      {
         if(hideMitigatedOB) ObjectDelete(0, OBRecName);
         break;
      }
         
      if(orderBlockTermination == OB_FirstTouch && foundSpaceBetween)
      {
         // If a candle\s high has touched the orderblock's low
         if(high[d]>=orderBlockLow)
         {
            if(hideMitigatedOB) ObjectDelete(0, OBRecName);
            break;
         }
      }
      
      if(orderBlockTermination == OB_BreakOut)
      {
         if(close[d]>orderBlockHigh)
         {
            if(hideMitigatedOB) ObjectDelete(0, OBRecName);
            break;
         }
      }

   }

   
   return(0);
}
//---  End of searchTransitionBearishOrderBlock

//+------------------------------------------------------------------+
//|      Transition Bullish Order Block Search                            |
//+------------------------------------------------------------------+
int searchTransitionBullishOrderBlock(
   const double &open[],
   const double &high[], 
   const double &low[],
   const double &close[],  
   const datetime &time[], 
   int i
   ){
   // Find the first OrderBlock in Search going back 4 steps
   // Order Block must be near the high as much as possible thus 4
   int idx = i;
   int lastTransisionIndx = i;
   
   bool possileOBIdentfied = false;
   if(IsBearishCandle(open[i], close[i]))
   {  
      possileOBIdentfied = true;
      for(int s=idx-1; s>=idx-candlesAfterTransition; s--)
      {
         lastTransisionIndx = s;
         if(s >= ArraySize(open)) return(0);
         if(IsBearishCandle(open[s], close[s]))
         {
            possileOBIdentfied = false;
            break;
         };
      }
   }
   
   if(!possileOBIdentfied) return (0);
   if(close[lastTransisionIndx]<high[idx]) return (0);
   
   if(transitionMustEngulf)
   {
      if(high[idx-1]>high[idx]) return (0); // low engulfer: use close for body engulfer
   }
   
   double orderBlockLow = low[idx];
   double orderBlockHigh = high[idx];

   AMBullishOrderBlockLowBuffer[idx] = low[idx];
   string OBRecName = getObjectName(OrderBlockObjStr + (string)idx + "+OB");
   ResetLastError();  
   if(!ObjectCreate(0,OBRecName,OB_OBJECT_TYPE,0,time[idx],high[idx],time[idx],high[idx])) 
   { 
      Print(__FUNCTION__, 
            ": failed to create a rectangle! Error code = ",GetLastError()); 
      return(false); 
   }
   //--- set rectangle color 
   ObjectSetInteger(0,OBRecName,OBJPROP_COLOR,orderBlockBullsColor); 
   ObjectSetInteger(0,OBRecName,OBJPROP_FILL,orderBlockBullsColor);  
   ObjectSetInteger(0,OBRecName,OBJPROP_BACK,1);
   
   bool foundSpaceBetween = false;
   for(int d=idx;d>=0;d--)
   {
      ResetLastError(); 
      if(!ObjectMove(0,OBRecName,0,time[d],OB_OBJECT_TYPE == OBJ_RECTANGLE ? low[idx] : high[idx])) 
      { 
         Print(__FUNCTION__, 
               ": failed to move the anchor point! Error code = ",GetLastError()); 
         return(false);
      }
      
      if(high[d]>orderBlockHigh && low[d]>orderBlockHigh)
      {
         foundSpaceBetween = true;
      }
      
      // violated Order block: current close already below ordeblock's closing
      if(!foundSpaceBetween && close[d]<close[idx])  // close[d]<orderBlocLow
      {
         if(hideMitigatedOB) ObjectDelete(0, OBRecName);
         break;
      }
         
      if(orderBlockTermination == OB_FirstTouch && foundSpaceBetween)
      {
         // If a candle\s high has touched the orderblock's low
         if(low[d]<=orderBlockHigh)
         {
            if(hideMitigatedOB) ObjectDelete(0, OBRecName);
            break;
         }
      }
      
      if(orderBlockTermination == OB_BreakOut)
      {
         if(close[d]<close[idx]) // close[d]<orderBlocLow
         {
            if(hideMitigatedOB) ObjectDelete(0, OBRecName);
            break;
         }
      }

   }

   
   return(0);
}
//--- End of searchTransitionBullishOrderBlock
