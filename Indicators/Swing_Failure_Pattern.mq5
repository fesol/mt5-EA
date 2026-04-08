//+------------------------------------------------------------------+
//|                                        Swing Failure Pattern.mq5 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 16
#property indicator_plots   6
//--- plot LiquiditySweepHighPriceBuffer
#property indicator_label1  "Liquidity Sweep High Price"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1
//--- plot LiquiditySweepHighBarsBuffer
#property indicator_label2  "Liquidity Sweep High Bars"
#property indicator_type2   DRAW_NONE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1
//--- plot LiquiditySweepLowPriceBuffer
#property indicator_label3  "Liquidity Sweep Low Price"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrGreen
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1
//--- plot LiquiditySweepLowBarsBuffer
#property indicator_label4  "Liquidity Sweep Low Bars"
#property indicator_type4   DRAW_NONE
#property indicator_color4  clrGreen
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1
//--- plot ph
#property indicator_label5  "confirm high"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrRed
#property indicator_style5  STYLE_SOLID
#property indicator_width5  1
//--- plot pl
#property indicator_label6  "confirm low"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrGreen
#property indicator_style6  STYLE_SOLID
#property indicator_width6  1

//--- indicator buffers
double         LiquiditySweepHighPriceBuffer[];
double         LiquiditySweepHighBarsBuffer[];
double         LiquiditySweepLowPriceBuffer[];
double         LiquiditySweepLowBarsBuffer[];
//--- calculation buffers
double         ph[];
double         pl[];
double         sw_ph[];
double         sw_pl[];
double         dn[];
double         up[];
double         ph_n[];
double         pl_n[];
double         opposL[];
double         opposH[];
double         finalDn[];
double         finalUp[];


int alreadyCalculated = 0;
//+------------------------------------------------------------------+
//|INPUTS                                                            |
//+------------------------------------------------------------------+
input int             len           = 5;              //Swings

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit() {
//--- indicator buffers mapping
  SetIndexBuffer(0,LiquiditySweepHighPriceBuffer,INDICATOR_DATA);
  SetIndexBuffer(1,LiquiditySweepHighBarsBuffer,INDICATOR_DATA);
  SetIndexBuffer(2,LiquiditySweepLowPriceBuffer,INDICATOR_DATA);
  SetIndexBuffer(3,LiquiditySweepLowBarsBuffer,INDICATOR_DATA);
  SetIndexBuffer(4,finalDn,INDICATOR_DATA);
  SetIndexBuffer(5,finalUp,INDICATOR_DATA);
  SetIndexBuffer(6,ph,INDICATOR_CALCULATIONS);
  SetIndexBuffer(7,pl,INDICATOR_CALCULATIONS);
  SetIndexBuffer(8,sw_ph,INDICATOR_CALCULATIONS);
  SetIndexBuffer(9,sw_pl,INDICATOR_CALCULATIONS);
  SetIndexBuffer(10,dn,INDICATOR_CALCULATIONS);
  SetIndexBuffer(11,up,INDICATOR_CALCULATIONS);
  SetIndexBuffer(12,ph_n,INDICATOR_CALCULATIONS);
  SetIndexBuffer(13,pl_n,INDICATOR_CALCULATIONS);
  SetIndexBuffer(14,opposL,INDICATOR_CALCULATIONS);
  SetIndexBuffer(15,opposH,INDICATOR_CALCULATIONS);
  

//--- setting a code from the Wingdings charset as the property of PLOT_ARROW
  PlotIndexSetInteger(0,PLOT_ARROW,218);
  PlotIndexSetInteger(1,PLOT_ARROW,159);
  PlotIndexSetInteger(2,PLOT_ARROW,217);
  PlotIndexSetInteger(3,PLOT_ARROW,159);

  //PlotIndexSetInteger(8,PLOT_ARROW,217);
  //PlotIndexSetInteger(9,PLOT_ARROW,218);
  
  PlotIndexSetInteger(4,PLOT_ARROW,218);
  PlotIndexSetInteger(5,PLOT_ARROW,217);
  
  //ArrayFill(LiquiditySweepHighBarsBuffer,0,)
//---
  return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {

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
                const int &spread[]) {
//---
  int start = prev_calculated - 2;
  if(start < 0)start = 0;
  if(start <= alreadyCalculated)start = alreadyCalculated + 1;

  for(int n = start; n < rates_total; n++) {
    LiquiditySweepHighBarsBuffer[n] = EMPTY_VALUE;
    LiquiditySweepHighPriceBuffer[n] = EMPTY_VALUE;
    LiquiditySweepLowBarsBuffer[n] = EMPTY_VALUE;
    LiquiditySweepLowPriceBuffer[n] = EMPTY_VALUE;


    ph[n] = PivotHigh(high,n);
    if(ph[n] == 0)ph[n] = EMPTY_VALUE;
    pl[n] = PivotLow(low,n);
    if(pl[n] == 0)pl[n] = EMPTY_VALUE;
    
    //get the sw and start from the current candle
    if(ph[n] != EMPTY_VALUE){
      sw_ph[n] = ph[n];
      ph_n[n] = n;
    }else{
      if(n == 0){
        sw_ph[n] = EMPTY_VALUE;
        ph_n[n] = 0;
      }else{
        sw_ph[n] = sw_ph[n-1];
        ph_n[n] = ph_n[n-1];
      }
    }
    
    if(pl[n] != EMPTY_VALUE){
      sw_pl[n] = pl[n];
      pl_n[n] = n;
    }else{
      if(n == 0){
        sw_pl[n] = EMPTY_VALUE;
        pl_n[n] = 0;
      }else{
        sw_pl[n] = sw_pl[n-1];
        pl_n[n] = pl_n[n-1];
      }
    }
    
    //bear
    if(high[n] > sw_ph[n] && open[n] < sw_ph[n] && close[n] < sw_ph[n]){
      //check backwards to make sure this is the first cross/touch
      bool isFirst = true;
      for(int j=(int)ph_n[n] ; j<n ; j++){
        if(dn[j] != 0 && dn[j] != EMPTY_VALUE)isFirst = false;
      }
      if(isFirst){
        dn[n] = sw_ph[n];
        //get the opposL
        opposL[n] = sw_ph[n];
        for(int i=n-1;i>=ph_n[n];i--){
          opposL[n] = MathMin(opposL[n],low[i]);
        }
      }
    }
    
    //bull
    if(low[n] < sw_pl[n] && open[n] > sw_pl[n] && close[n] > sw_pl[n]){
      //check backwards to make sure this is the first cross/touch
      bool isFirst = true;
      for(int j=(int)pl_n[n] ; j<n ; j++){
        if(up[j] != 0 && up[j] != EMPTY_VALUE)isFirst = false;
      }
      if(isFirst){
        up[n] = sw_pl[n];
        //get the opposH
        opposH[n] = sw_pl[n];
        for(int i=n-1;i>=pl_n[n];i--){
          opposH[n] = MathMax(opposH[n],high[i]);
        }
      }
    }
    
    //check to confirm
    //first find the most recent opposL
    double opposLToUse = 0;
    double highestClose = 0;
    double sw_phToUse = 0;
    int startIndexOfPh = 0;
    for(int z=n;z>=0;z--){
      if(finalDn[z] != 0 && finalDn[z] != EMPTY_VALUE){
        break;
      }
      
      if(opposL[z] != 0 && opposL[z] != EMPTY_VALUE){
        opposLToUse = opposL[z];
        sw_phToUse = sw_ph[z];
        startIndexOfPh = (int)ph_n[z];
        break;
      }
      
      highestClose = MathMax(highestClose,close[z]);
    }
    if(startIndexOfPh > 0 && opposLToUse != 0 && close[n] < opposLToUse && (highestClose==0 || highestClose < sw_phToUse)){
      if(time[n] != iTime(_Symbol,PERIOD_CURRENT,0)){
        finalDn[n] = sw_phToUse;
        for(int b=startIndexOfPh-1;b<n;b++){
          LiquiditySweepHighPriceBuffer[b] = sw_phToUse;
          LiquiditySweepHighBarsBuffer[b] = b - (startIndexOfPh-1);
        }
        LiquiditySweepHighBarsBuffer[n] = n - (startIndexOfPh-1);
        alreadyCalculated = n;
      }
    }else{
      finalDn[n] = EMPTY_VALUE;
    }
    
    //...
    //check to confirm
    //first find the most recent opposH
    double opposHToUse = 0;
    double lowestClose = 0;
    double sw_plToUse = 0;
    int startIndexOfPl = 0;
    for(int z=n;z>=0;z--){
      if(finalUp[z] != 0 && finalUp[z] != EMPTY_VALUE){
        break;
      }
      if(opposH[z] != 0 && opposH[z] != EMPTY_VALUE){
        opposHToUse = opposH[z];
        sw_plToUse = sw_pl[z];
        startIndexOfPl = (int)pl_n[z];
        break;
      }
      if(lowestClose == 0)lowestClose = low[z];
      lowestClose = MathMin(lowestClose,low[z]);
    }
    if(startIndexOfPl > 0 && opposHToUse != 0 && close[n] > opposHToUse && (lowestClose==0 || lowestClose > sw_plToUse)){
      if(time[n] != iTime(_Symbol,PERIOD_CURRENT,0)){
        finalUp[n] = sw_plToUse;
        for(int a=startIndexOfPl-1;a<n;a++){
          LiquiditySweepLowPriceBuffer[a] = sw_plToUse;
          LiquiditySweepLowBarsBuffer[a] = a - (startIndexOfPl-1);
        }
        LiquiditySweepLowBarsBuffer[n] = n - (startIndexOfPl-1);
        alreadyCalculated = n;
      }
    }else{
      finalUp[n] = EMPTY_VALUE;
    }
    
  }

//--- return value of prev_calculated for next call
  return(rates_total);
}
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double PivotHigh(const double &high[], int index) {
  if(index < len + 2)return 0;
  if(high[index - 1] > high[index]) {
    double highToCheck = high[index - 1];
    int startFromIndex = index - 2;
    int upTo = startFromIndex - len;
    for(int i=startFromIndex;i>upTo;i--) {
      if(high[i] > highToCheck) {
        return 0;
      }
    }
    return highToCheck;
  }
  return 0;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double PivotLow(const double &low[], int index) {
  if(index < len + 2)return 0;
  if(low[index - 1] < low[index]) {
    double lowToCheck = low[index - 1];
    int startFromIndex = index - 2;
    int upTo = startFromIndex - len;
    for(int i=startFromIndex;i>upTo;i--) {
      if(low[i] < lowToCheck) {
        return 0;
      }
    }
    return lowToCheck;
  }
  return 0;
}
//+------------------------------------------------------------------+
