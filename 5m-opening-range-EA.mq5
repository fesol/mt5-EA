//+------------------------------------------------------------------+
//| Agressive trail Scalper based on the 5m opening range            |
//+------------------------------------------------------------------+
#property link      ""
#property version   "1.00"
#property strict
#property description "EA that trades based on 5m opening range at 16:30 server time. Trailing the position with very tight stop"

#include <Trade\Trade.mqh>

// Trailing modes
enum TrailingMode
{
   None = 0,
   CandleTrail = 1,
   PercentTrail = 2
};

// Inputs
input bool AllowSells  = false; 
input bool UsePercentRisk = true;      // Use percent risk
input double RiskPercent = 1.0;        // Risk percent of account balance
input double FixedLots = 0.1;          // Fixed lot size if not using percent
input double TPMultiplier = 2.0;       // TP as multiplier of SL distance
input TrailingMode Trailing = None;    // Trailing mode: None, CandleTrail, PercentTrail
input double StartTrailPercentTP = 10; // Start trailing after % of TP distance
input double TrailDistPercentTP = 5; // Trailing distance % of TP distance
input int CancelAfterCandles = 5;      // Cancel pending after this many candles if not filled
input int MagicNumber = 12345;         // Magic number for orders
input int Slippage = 3;                // Slippage in points

// Global variables
CTrade trade;
static datetime lastOpenTime = 0;
static datetime placementTime = 0;
static int candlesSincePlacement = 0;
ulong pendingTicket = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up if needed
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Detect new bar
      // Trailing SL if enabled and position open
   if (Trailing != None && HasOpenPosition())
   {
      TrailStopLoss();
   }
   
   datetime currentOpenTime = iTime(_Symbol, PERIOD_M5, 0);
   bool isNewBar = (currentOpenTime != lastOpenTime);
   if (isNewBar)
   {
      lastOpenTime = currentOpenTime;
      
      // Check if this is the 16:35 candle
      MqlDateTime dt;
      TimeToStruct(currentOpenTime, dt);
      if (dt.hour == 16 && dt.min == 35)
      {
         // No existing position or pending
         if (!HasOpenPosition() && !HasPendingOrder())
         {
            // Get opening range from previous candle (16:30-16:35)
            double highRange = iHigh(_Symbol, PERIOD_M5, 1);
            double lowRange = iLow(_Symbol, PERIOD_M5, 1);
            double midRange = (highRange + lowRange) / 2.0;
            double currentOpen = iOpen(_Symbol, PERIOD_M5, 0);
            
            // Calculate SL distance
            double slDist = highRange - midRange; // Symmetric
            
            // Calculate lot size
            double lotSize = CalculateLotSize(slDist);
            
            if (lotSize > 0.0)
            {
               // Long condition: open between mid and high (mid < open <= high)
               if (currentOpen > midRange && currentOpen <= highRange)
               {
                  double entry = highRange;
                  double sl = midRange;
                  double tp = entry + TPMultiplier * (entry - sl);
                  
                  // Place buy stop
                  ulong ticket = trade.OrderOpen(_Symbol, ORDER_TYPE_BUY_STOP, lotSize, 0, entry, sl, tp, 0, 0, "5m Opening Scalper BUY");
                  if (ticket > 0)
                  {
                     pendingTicket = ticket;
                     placementTime = currentOpenTime;
                     candlesSincePlacement = 0;
                     Print("Placed BUY_STOP at ", entry, " SL:", sl, " TP:", tp);
                  }
               }
               // Short condition: open between low and mid (low <= open < mid)
               else if (AllowSells && currentOpen >= lowRange && currentOpen < midRange)
               {
                  double entry = lowRange;
                  double sl = midRange;
                  double tp = entry - TPMultiplier * (sl - entry);
                  
                  // Place sell stop
                  ulong ticket = trade.OrderOpen(_Symbol, ORDER_TYPE_SELL_STOP, lotSize, 0, entry, sl, tp, 0, 0, "5m Opening Scalper SELL");
                  if (ticket > 0)
                  {
                     pendingTicket = ticket;
                     placementTime = currentOpenTime;
                     candlesSincePlacement = 0;
                     Print("Placed SELL_STOP at ", entry, " SL:", sl, " TP:", tp);
                  }
               }
            }
         }
      }
      
      // Increment candle count for pending order cancellation
      if (HasPendingOrder())
      {
         candlesSincePlacement++;
         if (candlesSincePlacement >= CancelAfterCandles)
         {
            CancelPendingOrder();
         }
      }
   }
   

}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDist)
{
   if (slDist <= 0.0) return 0.0;
   
   double lotSize = FixedLots;
   if (UsePercentRisk)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount = balance * RiskPercent / 100.0;
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double slPoints = slDist / tickSize;
      
      if (tickValue > 0.0 && slPoints > 0.0)
      {
         lotSize = riskAmount / (slPoints * tickValue);
      }
      else
      {
         Print("Error calculating lot size: invalid tick value or SL points");
         return 0.0;
      }
      
      // Normalize lot size
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      lotSize = NormalizeDouble(MathRound(lotSize / lotStep) * lotStep, 2);
      
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      if (lotSize < minLot) lotSize = minLot;
      if (lotSize > maxLot) lotSize = maxLot;
   }
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Check if there is an open position                               |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (PositionGetTicket(i) > 0)
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if there is a pending order                                |
//+------------------------------------------------------------------+
bool HasPendingOrder()
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderGetTicket(i) > 0)
      {
         if (OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Cancel pending order                                             |
//+------------------------------------------------------------------+
void CancelPendingOrder()
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if (ticket > 0)
      {
         if (OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         {
            trade.OrderDelete(ticket);
            Print("Canceled pending order: ", ticket);
            pendingTicket = 0;
            candlesSincePlacement = 0;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trail stop loss                                                  |
//+------------------------------------------------------------------+
void TrailStopLoss()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket > 0)
      {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            double currentSL = PositionGetDouble(POSITION_SL);
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double tp = PositionGetDouble(POSITION_TP);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            double tpDist = (posType == POSITION_TYPE_BUY) ? (tp - entry) : (entry - tp);
            
            if (Trailing == CandleTrail)
            {
               if (posType == POSITION_TYPE_BUY)
               {
                  double newSL = iLow(_Symbol, PERIOD_M5, 1);
                  if (newSL > currentSL)
                  {
                     trade.PositionModify(ticket, newSL, tp);
                     Print("Trailed SL for long position to ", newSL);
                  }
               }
               else if (posType == POSITION_TYPE_SELL)
               {
                  double newSL = iHigh(_Symbol, PERIOD_M5, 1);
                  if (newSL < currentSL)
                  {
                     trade.PositionModify(ticket, newSL, tp);
                     Print("Trailed SL for short position to ", newSL);
                  }
               }
            }
            else if (Trailing == PercentTrail)
            {
               double startLevel = (StartTrailPercentTP / 100.0) * tpDist;
               double trailDist = (TrailDistPercentTP / 100.0) * tpDist;
               
               if (posType == POSITION_TYPE_BUY)
               {
                  double currentProfit = bid - entry;
                  if (currentProfit >= startLevel)
                  {
                     double newSL = bid - trailDist;
                     if (newSL > currentSL)
                     {
                        trade.PositionModify(ticket, newSL, tp);
                        Print("Trailed SL for long position to ", newSL);
                     }
                  }
               }
               else if (posType == POSITION_TYPE_SELL)
               {
                  double currentProfit = entry - ask;
                  if (currentProfit >= startLevel)
                  {
                     double newSL = ask + trailDist;
                     if (newSL < currentSL)
                     {
                        trade.PositionModify(ticket, newSL, tp);
                        Print("Trailed SL for short position to ", newSL);
                     }
                  }
               }
            }
         }
      }
   }
}
