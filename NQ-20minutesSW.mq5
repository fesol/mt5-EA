//+--------------------------------------------------------------------+
//|  EA based on NQ stats hourly reversion theory during the first 20m |
//|  https://nqstats.com/hour_stats.html                               |
//+--------------------------------------------------------------------+
#property version   "1.00"

#include <Trade\Trade.mqh>
CPositionInfo  posinfo;      // position info object
CTrade         trade;        // trading object

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                |
//+------------------------------------------------------------------+
input group "=== Trading Inputs ==="
input double   RiskPercent        = 0;        // Risk as % of Trading Capital
input double   InpFixedLot        = 0.5;      // Fixed lot (used if RiskPercent = 0)
input double   InpTpFactorBuy     = 1.5;      // TP factor for buys
input double   InpTpFactorSell    = 0.5;      // TP factor for sells
input double   InpSlBuffer        = 0;        // SL buffer (points)
input double   SweepBuffer        = 20;       // Min points to confirm sweep
input double   RRfactor           = 0.25;     // Min RR to take trade
input int      CutLossParameter   = 5;        // Multiplier for cut-loss
input double   InpTsltrigger      = 20;       // Trail trigger % of TP
input double   InpTslpoints       = 10;       // Trail SL % of TP
input int      InpMagic           = 77777;    // EA ID
input int      StartHour          = 14;       // Trading window start hour
input int      StopHour           = 20;       // Trading window end hour
input bool     allowSells         = true;     // Allow sell trades

input bool     tradeMonday        = true;
input bool     tradeTuesday       = true;
input bool     tradeWednesday     = true;
input bool     tradeThursday      = true;
input bool     tradeFriday        = true;
input bool     tradeSaturday      = false;
input bool     tradeSunday        = false;

input int      MaxTrades          = 2;        // Max trades per day

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                |
//+------------------------------------------------------------------+
double TslTRPoints, TslPoints;
double RangeHigh, RangeLow, RangeOpen;
bool   tradedToday;
MqlDateTime time;

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!isTradingDay())
      return;

   if(!IsNewBar())
      return;

   TimeToStruct(TimeCurrent(), time);
   int Hournow = time.hour;
   int Minnow  = time.min;

   // Outside trading window -> close all positions
   if(Hournow < StartHour || Hournow > StopHour)
   {
      CloseAllPositions();
      return;
   }

   // At the start of the hour, record previous H1 range
   if(Minnow == 0)
   {
      GetHourlyCandleRange(RangeHigh, RangeLow, RangeOpen);
      ObjectsDeleteAll(0, -1, -1);
   }

   // Sweep detection only during first ~20 minutes
   bool SweepBuy  = false;
   bool SweepSell = false;
   if(Minnow < 21 && Minnow > 1)
   {
      SweepBuy  = CheckSweepBuy();
      SweepSell = CheckSweepSell();
   }

   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double low   = iLow(_Symbol, PERIOD_H1, 0);
   double high  = iHigh(_Symbol, PERIOD_H1, 0);

   // Count current positions
   int BuyTotal = 0, SellTotal = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      posinfo.SelectByIndex(i);
      if(posinfo.Magic() != InpMagic || posinfo.Symbol() != _Symbol)
         continue;
      if(posinfo.PositionType() == POSITION_TYPE_BUY)
         BuyTotal++;
      if(posinfo.PositionType() == POSITION_TYPE_SELL)
         SellTotal++;
   }

   // Cut-loss rule
   if(BuyTotal > 0 && close < (RangeLow - SweepBuffer * _Point * CutLossParameter))
      CloseAllPositions();
   if(SellTotal > 0 && close > (RangeHigh + SweepBuffer * _Point * CutLossParameter))
      CloseAllPositions();

   // BUY ENTRY
   if(BuyTotal <= MaxTrades && SweepBuy && !tradedToday)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double SL  = low - InpSlBuffer * _Point;
      double TP  = iOpen(_Symbol, PERIOD_H1, 0);

      double lots = InpFixedLot;
      if(RiskPercent > 0)
         lots = CalcLots(ask - SL);

      // Minimum RR check
      if((TP - ask) > ((ask - SL) * RRfactor))
      {
         trade.Buy(lots, _Symbol, ask, 0, TP);
         tradedToday = true;

         TslTRPoints = (TP - ask) * InpTsltrigger / 100;
         TslPoints   = (TP - ask) * InpTslpoints / 100;
      }
   }

   // SELL ENTRY
   if(SellTotal <= MaxTrades && SweepSell && !tradedToday && allowSells)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double SL  = high + InpSlBuffer * _Point;
      double TP  = iOpen(_Symbol, PERIOD_H1, 0);

      double lots = InpFixedLot;
      if(RiskPercent > 0)
         lots = CalcLots(SL - bid);

      if((bid - TP) > ((SL - bid) * RRfactor))
      {
         trade.Sell(lots, _Symbol, bid, 0, TP);
         tradedToday = true;

         TslTRPoints = (bid - TP) * InpTsltrigger / 100;
         TslPoints   = (bid - TP) * InpTslpoints / 100;
      }
   }

   // Trailing();
}

//+------------------------------------------------------------------+
//| New bar detection                                               |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime previousTime = 0;
   datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(previousTime != currentTime)
   {
      previousTime = currentTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get previous H1 candle range                                    |
//+------------------------------------------------------------------+
void GetHourlyCandleRange(double &CandleHigh, double &CandleLow, double &CandleOpen)
{
   CandleHigh = iHigh(_Symbol, PERIOD_H1, 1);
   CandleLow  = iLow(_Symbol, PERIOD_H1, 1);
   CandleOpen = iOpen(_Symbol, PERIOD_H1, 1);
   tradedToday = false;

   ObjectCreate(0, "candle High", OBJ_HLINE, 0, 0, CandleHigh);
   ObjectCreate(0, "candle Low",  OBJ_HLINE, 0, 0, CandleLow);
}

//+------------------------------------------------------------------+
//| Sweep detection for Buy                                         |
//+------------------------------------------------------------------+
bool CheckSweepBuy()
{
   double open = iOpen(_Symbol, PERIOD_H1, 0);
   if(open > RangeHigh || open < RangeLow)
      return false;

   double low   = iLow(_Symbol, PERIOD_H1, 0);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);

   return (low < RangeLow && close > (RangeLow + SweepBuffer * _Point));
}

//+------------------------------------------------------------------+
//| Sweep detection for Sell                                        |
//+------------------------------------------------------------------+
bool CheckSweepSell()
{
   double open = iOpen(_Symbol, PERIOD_H1, 0);
   if(open > RangeHigh || open < RangeLow)
      return false;

   double high  = iHigh(_Symbol, PERIOD_H1, 0);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);

   return (high > RangeHigh && close < (RangeHigh - SweepBuffer * _Point));
}

//+------------------------------------------------------------------+
//| Lot size calculation based on % risk                            |
//+------------------------------------------------------------------+
double CalcLots(double slPoints)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minVol    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volLimit  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);

   double moneyPerLotStep = slPoints / tickSize * tickValue * lotStep;
   double lots = MathFloor(risk / moneyPerLotStep) * lotStep;

   if(volLimit != 0) lots = MathMin(lots, volLimit);
   if(maxVol   != 0) lots = MathMin(lots, maxVol);
   if(minVol   != 0) lots = MathMax(lots, minVol);

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Close all positions for this symbol/magic                       |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posinfo.SelectByIndex(i) && posinfo.Magic() == InpMagic)
      {
         trade.PositionClose(posinfo.Ticket());
         Sleep(100);
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing stop                                                    |
//+------------------------------------------------------------------+
void Trailing()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posinfo.SelectByIndex(i))
         continue;
      if(posinfo.Magic() != InpMagic || posinfo.Symbol() != _Symbol)
         continue;

      ulong ticket = posinfo.Ticket();
      double tp = posinfo.TakeProfit();

      if(posinfo.PositionType() == POSITION_TYPE_BUY)
      {
         if(bid - posinfo.PriceOpen() > TslTRPoints)
         {
            double sl = bid - TslPoints;
            if(sl > posinfo.StopLoss() && sl != 0)
               trade.PositionModify(ticket, sl, tp);
         }
      }
      else if(posinfo.PositionType() == POSITION_TYPE_SELL)
      {
         if(posinfo.PriceOpen() - ask > TslTRPoints)
         {
            double sl = ask + TslPoints;
            if(sl < posinfo.StopLoss() && sl != 0)
               trade.PositionModify(ticket, sl, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Day-of-week filter                                              |
//+------------------------------------------------------------------+
bool isTradingDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   switch(dt.day_of_week)
   {
      case 1: return tradeMonday;
      case 2: return tradeTuesday;
      case 3: return tradeWednesday;
      case 4: return tradeThursday;
      case 5: return tradeFriday;
      case 6: return tradeSaturday;
      case 0: return tradeSunday;
   }
   return false;
}
//+------------------------------------------------------------------+
