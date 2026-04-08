//+------------------------------------------------------------------+
//|                                               SuperScalperFX.mq5 |
//+------------------------------------------------------------------+

#property version   "1.00"

#include <Trade\Trade.mqh>
   CPositionInfo  posinfo;                   // trade position object
   CTrade         trade;                     // trading object
   COrderInfo     ordinfo;                   // pending orders object
   
#include <Indicators\Trend.mqh>
   CiIchimoku  Ichimoku;
   CiMA        MovAvg;
#include <Indicators\Oscilators.mqh>
   CiRSI    RSI;
   
//enum IchiTypes  {PriceAboveCloud=0,PriceAboveTen=1,PriceAboveKij=2,PriceAboveSenA=3,PriceAboveSenB,TenAboveKij=5,TenAboveKijAboveCloud=6,TenAboveCloud=7,KijAboutCloud=8};
//enum IchiTypes  {TenAboveKij=0,TenAboveKijAboveCloud=1};
//enum StartHour {Inactive=0, _0100=1,_0200=2,_0300=3,_0400=4,_0500=5,_0600=6,_0700=7,_0800=8,_0900=9,_1000=10,_1100=11,_1200=12,_1300=13,_1400=14,_1500=15,_1600=16,_1700=17,_1800=18,_1900=19,_2000=20,_2100=21,_2200=22,_2300=23 };
//enum EndHour {Inactive=0, _0100=1,_0200=2,_0300=3,_0400=4,_0500=5,_0600=6,_0700=7,_0800=8,_0900=9,_1000=10,_1100=11,_1200=12,_1300=13,_1400=14,_1500=15,_1600=16,_1700=17,_1800=18,_1900=19,_2000=20,_2100=21,_2200=22,_2300=23 };

input group "=== Trading Inputs ==="

   input double RiskPercent      = 1; // Risk as % of Trading Capital 
   input double InpFixedLot = 0.01;  // Fixed lot (only if Risk Percent = 0)
   input double InpTpFactorBuy          = 1.5; // TP as factor of SL for buys
   input double InpTpFactorSell          = 0.65; // TP as factor of SL for sells
   input double InpSlBuffer          = 10; // SL buffer: Points for SL buffer above/below the trigger 
   input double SweepBuffer         = 10; // Min Points to close back again inside the range
   input double RRfactor            = 0.5; // RRfactor: Min RR to take a trade
   input int    CutLossParameter    = 10;  
   input double InpTsltrigger       = 16; // Trail Trigger as % of TP
   input double InpTslpoints        = 20; // Trail SL as % of TP
   input bool  SpreadFilterOn       = false;
   input int InpMaxSpread           = 20; //Max spread to allow a trade as % of Trailing Stop
   input ENUM_TIMEFRAMES timeframe  = PERIOD_CURRENT;
   input int InpMagic               = 77777; // EA id number

   input bool HideIndicators = true;
   input int   StartHour = 15;
   input int   StopHour  = 18;
   input bool trade3hours=true;
   input double retracementLevel = 0.5;
   input bool allowSells = false;


input bool     tradeMonday  = true;
input bool     tradeTuesday  = true;
input bool     tradeWednesday  = true;
input bool     tradeThursday  = true;
input bool     tradeFriday  = true;  
input bool     tradeSaturday  = false;  
input bool     tradeSunday = false;  

input int     MaxTrades = 2;



   double TP, SL,TslTRPoints,TslPoints, OrderDistPoints, MaxSpread;
   


   int SHChoice, EHChoice;
   
   int handleRSI;

   
   bool TradingEnabled = true;
   string TradingEnabledcomment = "";
   
      double RangeHigh, RangeLow, RangeOpen;
   
   bool tradedToday;
   
      MqlDateTime time;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   return(INIT_SUCCEEDED);
   


  if (HideIndicators == true) TesterHideIndicators(true);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   
   //Trailing();
   //MoveToBreakevenAndClosePartial(0, 10);

    if(!isTradingDay())
         return; 
   
   if (!IsNewBar()) return; 
     

   int BuyTotal=0;
   int SellTotal=0;
   bool SweepBuy=false;
   bool SweepSell=false;
   

   TimeToStruct(TimeCurrent(),time);
   int Hournow = time.hour;
   int Minnow = time.min;
   
     if (Hournow<StartHour || Hournow>StopHour) {CloseAllPositions();return;}
     
     if( Minnow == 0) {GetHourlyCandleRange(RangeHigh,RangeLow,RangeOpen); ObjectsDeleteAll(0,-1,-1);}
     if( Minnow < 21 && Minnow > 01) {SweepBuy=CheckSweepBuy();SweepSell=CheckSweepSell();}

   //if( Hournow == (HInput+1)  && Minnow == 0) GetHourlyCandleRange(RangeHigh,RangeLow,RangeOpen);
   //if( Hournow == (HInput+1)  && Minnow < 21 && Minnow > 01) {SweepBuy=CheckSweepBuy();SweepSell=CheckSweepSell();}

   //if( Hournow == (HInput+2)   && Minnow == 0) GetHourlyCandleRange(RangeHigh,RangeLow,RangeOpen);
   //if( Hournow == (HInput+2)   && Minnow < 21 && Minnow > 01) {SweepBuy=CheckSweepBuy();SweepSell=CheckSweepSell();}
   
   
   /*if (trade3hours){
         if( Hournow == (HInput+3)   && Minnow == 0) GetHourlyCandleRange(RangeHigh,RangeLow,RangeOpen);
         if( Hournow == (HInput+3)   && Minnow < 21 && Minnow > 01) {SweepBuy=CheckSweepBuy();SweepSell=CheckSweepSell();}
   }
  */
  
  
   double close=iClose(_Symbol,PERIOD_CURRENT,1);
   double low=iLow(_Symbol,PERIOD_H1,0);
   double high=iHigh(_Symbol,PERIOD_H1,0);
   
  
   
   for(int i=PositionsTotal()-1; i>=0; i--){
      posinfo.SelectByIndex(i);
      if (posinfo.PositionType()==POSITION_TYPE_BUY && posinfo.Symbol()==_Symbol && posinfo.Magic()==InpMagic) BuyTotal++;
      if (posinfo.PositionType()==POSITION_TYPE_SELL && posinfo.Symbol()==_Symbol && posinfo.Magic()==InpMagic) SellTotal++;
   }
   
   if (BuyTotal > 0 && close < (RangeLow-(SweepBuffer*CutLossParameter))) CloseAllPositions(); // Cut losses if breaks the oposite.
   
   if (SellTotal > 0 && close > (RangeHigh+(SweepBuffer*CutLossParameter))) CloseAllPositions();
   
   //if (Hournow == HClose && Minnow == 0) { CloseAllPositions(); ObjectsDeleteAll(0,-1,-1);}
   

   
   //if (BuyTotal<=MaxTrades && OrdersTotal()==0 && time.hour>HInput && close>RangeHigh && !tradedToday){
    if (BuyTotal<=MaxTrades  && SweepBuy && !tradedToday){
      
           Print("ENTRA AL debug1 buy!!!!!!!!!!!!");
      
      
      double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      //SL=RangeLow-(InpSlBuffer*_Point);
      SL=low-(InpSlBuffer*_Point);
      //TP=ask + (ask-low)*InpTpFactorBuy;
      TP=iOpen(_Symbol,PERIOD_H1,0);
      double lots = InpFixedLot;         
      if (RiskPercent > 0) lots=CalcLots(ask-SL);
      
      //double EnterPrice= RangeHigh - (RangeHigh - RangeLow) * retracementLevel;
      //datetime expTime=TimeCurrent()+(60*60*8);
      if ( (TP-ask)>((ask-SL)*RRfactor) ){
            trade.Buy(lots,_Symbol,ask,0,TP);
            tradedToday = true;
                
                TslTRPoints=(TP-ask)*InpTsltrigger/100;
                TslPoints=(TP-ask)*InpTslpoints/100;
      }
          //trade.Buy(lots,_Symbol,ask,SL,TP,"Sweep Candle Pattern Stocks");
          //SendBuyOrder(TPPoints,SLPoints); 
      }

      //sleep (100);
  
  
   //if (SellTotal<=MaxTrades && OrdersTotal()==0 && time.hour>HInput && close<RangeLow && !tradedToday && allowSells ){
   if (SellTotal<=MaxTrades  && SweepSell && !tradedToday && allowSells){
           
                      Print("ENTRA AL debug1 sell!!!!!!!!!!!!");
   
    
          double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);      
          SL=high+(InpSlBuffer*_Point);
          //TP=bid-(SL-bid)*InpTpFactorSell;
          TP=iOpen(_Symbol,PERIOD_H1,0);
          double lots = InpFixedLot;
          if (RiskPercent > 0) lots=CalcLots(SL-bid);
          
          //double EnterPrice= RangeLow + (RangeHigh - RangeLow) * retracementLevel;
          //datetime expTime=TimeCurrent()+(60*60*8);
          //trade.SellLimit(lots,EnterPrice,_Symbol,SL,TP,ORDER_TIME_SPECIFIED,expTime);
          if ( (bid-TP)> ((SL-bid)*RRfactor) ){
             trade.Sell(lots,_Symbol,bid,0,TP);
             tradedToday = true;
   
             TslTRPoints=(bid-TP)*InpTsltrigger/100;
             TslPoints=(bid-TP)*InpTslpoints/100;
         // trade.Sell(lots,_Symbol,bid,SL,TP,"Sweep Candle Pattern Stocks");
            }
      
      //SendSellOrder(TPPoints,SLPoints);
      //sleep (100);
   }
  
  }
//+------------------------------------------------------------------+
 bool IsNewBar (){
   static datetime previousTime=0;
   datetime CurrentTime = iTime (_Symbol, PERIOD_CURRENT,0);
   if (previousTime!=CurrentTime){
      previousTime=CurrentTime;
      return true;
   }
   return false;
}

/*
bool findPatternLongs(){
   double high2,low1,low2,close1, close2;
   high2=iHigh(_Symbol,PERIOD_CURRENT,2);
   low1=iLow(_Symbol,PERIOD_CURRENT,1);
   low2=iLow(_Symbol,PERIOD_CURRENT,2);
   close1=iClose(_Symbol,PERIOD_CURRENT,1);
   close2=iClose(_Symbol,PERIOD_CURRENT,2);
   // el video diu que l'ultim candle deu tindre un wick high pero aixo es compleix sempre, afegir un threshold per al wick'
   if (close1>high2 && low1<low2 ) return true;
   else return false;
       
}

bool findPatternShorts(){
   double high1,high2,low2,close1, close2;
   high1=iHigh(_Symbol,PERIOD_CURRENT,1);
   high2=iHigh(_Symbol,PERIOD_CURRENT,2);
   low2=iLow(_Symbol,PERIOD_CURRENT,2);
   close1=iClose(_Symbol,PERIOD_CURRENT,1);
   close2=iClose(_Symbol,PERIOD_CURRENT,2);
   //Print("ENTRA AL CONDICIONAL SHORT!!!!!!!!!!!!");
   // el video diu que l'ultim candle deu tindre un wick high pero aixo es compleix sempre, afegir un threshold per al wick'
   if (close1<low2 && high1>high2) {Print("ENTRA AL CONDICIONAL SHORT!!!!!!!!!!!!");return true;}
   else return false;


}

void SendBuyOrder (double tpp, double slp){

   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   double tp = ask + TPPoints*_Point;
   double sl = ask - SLPoints*_Point;
   
   double lots = 0.01;
   if (RiskPercent > 0) lots=CalcLots(ask-sl);
   trade.Buy(lots,_Symbol,ask,sl,tp,"Candle Pattern Stocks");
   
}

void SendSellOrder (double tpp, double slp){

   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   
   double tp = bid - TPPoints*_Point;
   double sl = bid + SLPoints*_Point;
   
   double lots = 0.01;
   if (RiskPercent > 0) lots=CalcLots(sl-bid);
   trade.Sell(lots,_Symbol,bid,sl,tp,"Candle Pattern Stocks");
}
*/
double CalcLots (double slpoints){
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent/100;
   
   double ticksize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickvalue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double lotstep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minvolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxvolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double volumelimit=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT);
   
   double moneyPerLotstep = slpoints / ticksize*tickvalue*lotstep;
   double lots = MathFloor(risk/moneyPerLotstep) * lotstep;
   
   if(volumelimit!=0) lots = MathMin(lots,volumelimit);
   if(maxvolume!=0) lots=MathMin(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
   if(minvolume!=0) lots=MathMax(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN));
   lots = NormalizeDouble(lots,2);
   return lots;
}

void CloseAllPositions(){


   //Print("Closing all positions !!!");
   for(int i = PositionsTotal() - 1; i >= 0; i--) // loop all Orders
      if(posinfo.SelectByIndex(i) && posinfo.Magic()==InpMagic)  // select an order
        {
         trade.PositionClose(posinfo.Ticket()); // then delete it --period
         Print("Closing all Positions !!!");
         Sleep(100); // Relax for 100 ms
        }

}

void Trailing(){

   double sl = 0;
   double tp = 0;
   
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   for(int i=PositionsTotal()-1; i>=0; i--){
      if(posinfo.SelectByIndex(i)){
         ulong ticket = posinfo.Ticket();
            if (posinfo.Magic()==InpMagic && posinfo.Symbol()==_Symbol){
               if(posinfo.PositionType()==POSITION_TYPE_BUY){
                  if(bid-posinfo.PriceOpen()>TslTRPoints){
                        tp = posinfo.TakeProfit();
                        sl = bid - TslPoints;
                        if(sl>posinfo.StopLoss() && sl!=0) trade.PositionModify(ticket,sl,tp);
                  }
               }
               else if (posinfo.PositionType()==POSITION_TYPE_SELL){
                  if(ask+(TslTRPoints)<posinfo.PriceOpen()){
                        tp = posinfo.TakeProfit();
                        sl = ask + TslPoints;
                        if(sl<posinfo.StopLoss() && sl!=0) trade.PositionModify(ticket,sl,tp);
                  }
               }
            }
      }      
   }
}


bool isTradingDay()
  {
   datetime currentTime = TimeCurrent();
   MqlDateTime mqlDateTime;
   TimeToStruct(currentTime, mqlDateTime);
   ENUM_DAY_OF_WEEK currentDayOfWeek = (ENUM_DAY_OF_WEEK)mqlDateTime.day_of_week;

   switch(currentDayOfWeek)
     {
      case MONDAY:
         return tradeMonday;
      case TUESDAY:
         return tradeTuesday;
      case WEDNESDAY:
         return tradeWednesday;
      case THURSDAY:
         return tradeThursday;
      case FRIDAY:
         return tradeFriday;
      case SATURDAY:
         return tradeSaturday;
      case SUNDAY:
         return tradeSunday;
      default:
         return false;
     }
  }
  
//+------------------------------------------------------------------+
//| Function: GetHourlyCandleRange                                   |
//| Purpose : Detect the range (high and low) of the candle at a given |
//|           hour. The input hour is an integer (0-23).             |
//| Returns : true if a candle is found, false otherwise.            |
//+------------------------------------------------------------------+
bool GetHourlyCandleRange(double &CandleHigh, double &CandleLow, double &CandleOpen)
{

         CandleHigh = iHigh(_Symbol,PERIOD_H1,1);
         CandleLow  = iLow(_Symbol,PERIOD_H1,1);
         Print("Candle Range", 
               " - High: ", CandleHigh, ", Low: ", CandleLow);
         tradedToday = false;
         ObjectCreate(0,"candle High",OBJ_HLINE,0,0,CandleHigh);
         ObjectCreate(0,"candle Low",OBJ_HLINE,0,0,CandleLow);
         return true;
    
 }
   

bool CheckSweepBuy()
{


    if ( (iOpen(Symbol(), PERIOD_H1, 0) > RangeHigh) || (iOpen(Symbol(), PERIOD_H1, 0) < RangeLow) ){
        Print ("Price it's outside of 9 candle Range");
        Print ("RangeHigh  ", RangeHigh);
        Print ("RangeLow", RangeLow);
        return false;
    }
    
    double Low = iLow(Symbol(), PERIOD_H1, 0);
    double Close = iClose(Symbol(), PERIOD_CURRENT, 1);


    if (Low < RangeLow && Close > (RangeLow+SweepBuffer))
        return true;

    return false;
}

bool CheckSweepSell()
{

    // Get candle data
    if ( (iOpen(Symbol(), PERIOD_H1, 0) > RangeHigh) || (iOpen(Symbol(), PERIOD_H1, 0) < RangeLow) ){
        Print ("Price it's outside of 9 candle Range");
        Print ("RangeHigh  ", RangeHigh);
        Print ("RangeLow", RangeLow);
        return false;
    }
    
    double High = iHigh(Symbol(), PERIOD_H1, 0);
    double Close = iClose(Symbol(), PERIOD_CURRENT, 1);


    if (High > RangeHigh && Close < (RangeHigh-SweepBuffer))
        return true;

    return false;
}

void MoveToBreakevenAndClosePartial(double breakevenTriggerPercent, double closePercentage)
{
    //CTrade trade;
    CPositionInfo positionInfo;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0 || !positionInfo.SelectByTicket(ticket)) continue;
        
        if(positionInfo.Magic() != InpMagic) continue;

        string symbol = positionInfo.Symbol();
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        ENUM_POSITION_TYPE posType = positionInfo.PositionType();
        double entryPrice = positionInfo.PriceOpen();
        double currentSL = positionInfo.StopLoss();
        double takeProfitPrice = positionInfo.TakeProfit();
        double volume = positionInfo.Volume();
        
        // Get current price based on position type
        MqlTick lastTick;
        SymbolInfoTick(symbol, lastTick);
        double currentPrice = (posType == POSITION_TYPE_BUY) ? lastTick.bid : lastTick.ask;
        
        // Skip if already at breakeven (considering 1 point tolerance)
        if(MathAbs(currentSL - entryPrice) <= point) continue;

        // Calculate price movement percentage
        double priceMovementPercent = 0;
        if(posType == POSITION_TYPE_BUY) {
            priceMovementPercent = ((currentPrice - entryPrice) / entryPrice) * 100;
        } else {
            priceMovementPercent = ((entryPrice - currentPrice) / entryPrice) * 100;
        }

        // Check trigger conditions
        bool trigger = false;
        if(takeProfitPrice > 0) {
            if((posType == POSITION_TYPE_BUY && currentPrice >= takeProfitPrice) ||
               (posType == POSITION_TYPE_SELL && currentPrice <= takeProfitPrice)) {
                trigger = true;
            }
        }
        if(priceMovementPercent >= breakevenTriggerPercent) {
            trigger = true;
        }

        if(!trigger) continue;

        // Calculate volume to close
        double volumeToClose = NormalizeDouble(volume * closePercentage / 100.0, 2);
        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        
        // Adjust volume to valid steps
        volumeToClose = MathFloor(volumeToClose / lotStep) * lotStep;
        volumeToClose = MathMax(volumeToClose, minLot);
        volumeToClose = MathMin(volumeToClose, volume - minLot);

        if(volumeToClose <= 0) continue;

        // Close partial position
        if(!trade.PositionClosePartial(ticket, volumeToClose))
        {
            Print("Close partial failed. Error: ", GetLastError());
            continue;
        }

        // Modify stop loss to breakeven
        if(!trade.PositionModify(ticket, entryPrice, takeProfitPrice))
        {
            Print("Modify SL failed. Error: ", GetLastError());
        }
    }
}
   
 
 
 
 

