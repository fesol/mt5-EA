//+--------------------------------------------------------------------+
//|     US30 vs US500 arbitrage trading system                         |
//|                                                                    |
//|  Strategy:                                                         |
//|  At a configurable open time, SHORT US30 and LONG US500 or oposite |
//|  Exit when combined P&L hits profit target or loss limit.          |
//|                                                                    |
//|  v1.30 additions:                                                  |
//|    1. Trailing profit lock                                         |
//|    2. Time-based hard close                                        |
//|    3. Direction filter (skip/flip if US30 outperforming US500)     |
//|    4. ATR-based dynamic lot sizing                                 |
//+--------------------------------------------------------------------+

#property version   "1.30"
#property strict

#include <Trade\Trade.mqh>

//========================================================================
//  INPUT PARAMETERS
//========================================================================

input group "=== Symbols ==="
input string   Sym_US30             = "US30";    // US30 symbol name
input string   Sym_US500            = "US500";   // US500 symbol name

input group "=== Trade Entry Time ==="
input int      OpenHour             = 16;         // Entry hour   (server time)
input int      OpenMinute           = 30;        // Entry minute (server time)

input group "=== Position Sizing ==="
input bool     UseDynamicLots       = true;      // Use ATR-based dynamic lot sizing
input double   BaseLots_US30        = 1.0;       // Base lots for US30 (anchor leg)
input int      ATR_Period           = 14;        // ATR period for dynamic sizing
input ENUM_TIMEFRAMES ATR_TF        = PERIOD_H1; // ATR timeframe
// If UseDynamicLots=false these fixed lots are used:
input double   FixedLots_US30       = 1.0;       // Fixed lots US30  (SHORT)
input double   FixedLots_US500      = 8.0;       // Fixed lots US500 (LONG)

input group "=== Exit: Fixed Thresholds ==="
input double   ProfitTarget         = 60;     // Hard profit target ($)
input double   LossLimit            = 120;     // Hard loss limit   ($, positive)

input group "=== Exit: Trailing Profit Lock ==="
input bool     UseTrailing          = true;      // Enable trailing profit lock
input double   TrailActivation      = 0;      // Activate trail once P&L >= this ($)
input double   TrailDrawdown        = 0;      // Trail distance in ($)

input group "=== Exit: Time-Based Hard Close ==="
input bool     UseTimeClose         = true;      // Force-close if still open at set time
input int      HardCloseHour        = 22;        // Hard-close hour   (server time)
input int      HardCloseMinute      = 0;         // Hard-close minute (server time)

input group "=== Entry: Direction Filter ==="
input bool     UseDirectionFilter   = true;      // Skip/flip if US30 is leading US500
input int      FilterLookbackBars   = 10;         // Number of H1 bars to measure return over
input double   FilterThresholdPct   = 0.1;      // Min US30 outperformance % to trigger filter
input bool     FlipOnFilter         = true;     // true=flip legs  false=skip trade entirely

input group "=== Risk: Friday Close ==="
input bool     CloseOnFriday        = true;      // Force-close at end of Friday
input int      FridayCloseHour      = 21;        // Friday close hour
input int      FridayCloseMin       = 0;         // Friday close minute

input group "=== Misc ==="
input bool     AllowOneTradePerDay  = false;      // One entry per calendar day
input int      MagicNumber          = 202401;    // EA magic number
input int      Slippage             = 10;        // Max slippage (points)
input bool     EnableAlerts         = true;      // Popup alerts
input bool     EnablePrint          = true;      // Expert log printing

//========================================================================
//  GLOBALS
//========================================================================
CTrade  trade;
int     lastTradeDay   = -1;
bool    positionsOpen  = false;
double  peakPnL        = -DBL_MAX;   // High-water mark for trailing
bool    trailActive    = false;

//========================================================================
//  INIT
//========================================================================
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   if(!SymbolSelect(Sym_US30,  true)) { Alert("Symbol not found: ", Sym_US30);  return INIT_FAILED; }
   if(!SymbolSelect(Sym_US500, true)) { Alert("Symbol not found: ", Sym_US500); return INIT_FAILED; }

   if(EnablePrint)
      PrintFormat("EA v1.30 started | %s SHORT / %s LONG | Entry %02d:%02d | "
                  "TP=%.2f SL=%.2f | Trail=%s (act=%.2f draw=%.2f) | "
                  "TimeClose=%s %02d:%02d | DirFilter=%s | DynLots=%s",
                  Sym_US30, Sym_US500, OpenHour, OpenMinute,
                  ProfitTarget, LossLimit,
                  UseTrailing?"ON":"OFF", TrailActivation, TrailDrawdown,
                  UseTimeClose?"ON":"OFF", HardCloseHour, HardCloseMinute,
                  UseDirectionFilter?"ON":"OFF",
                  UseDynamicLots?"ON":"OFF");
   return INIT_SUCCEEDED;
  }

//========================================================================
//  MAIN TICK
//========================================================================
void OnTick()
  {
   datetime    now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   positionsOpen = AreBothLegsOpen();

   //--- Friday forced close -------------------------------------------
   if(CloseOnFriday && dt.day_of_week == 5)
     {
      if(dt.hour > FridayCloseHour ||
        (dt.hour == FridayCloseHour && dt.min >= FridayCloseMin))
        {
         if(positionsOpen) CloseAllLegs("Friday close");
         return;
        }
     }

   //--- Time-based hard close ----------------------------------------
   if(UseTimeClose && positionsOpen)
     {
      if(dt.hour > HardCloseHour ||
        (dt.hour == HardCloseHour && dt.min >= HardCloseMinute))
        {
         CloseAllLegs(StringFormat("Time-based hard close %02d:%02d", HardCloseHour, HardCloseMinute));
         return;
        }
     }

   //--- Monitor open positions ---------------------------------------
   if(positionsOpen)
     {
      double pnl = GetCombinedPnL();

      // Update trailing high-water mark
      if(UseTrailing)
        {
         if(pnl >= TrailActivation)
           {
            trailActive = true;
            if(pnl > peakPnL) peakPnL = pnl;
           }
         if(trailActive && pnl <= peakPnL - TrailDrawdown)
           {
            CloseAllLegs(StringFormat("Trail stop: peak=%.2f current=%.2f", peakPnL, pnl));
            return;
           }
        }

      // Hard profit target
      if(pnl >= ProfitTarget)
        {
         CloseAllLegs(StringFormat("Profit target hit: %.2f", pnl));
         return;
        }

      // Hard loss limit
      if(pnl <= -LossLimit)
        {
         CloseAllLegs(StringFormat("Loss limit hit: %.2f", pnl));
         return;
        }
     }

   //--- Entry --------------------------------------------------------
   if(!positionsOpen)
     {
      bool rightTime    = (dt.hour == OpenHour && dt.min == OpenMinute);
      bool alreadyToday = (AllowOneTradePerDay && dt.day == lastTradeDay);

      if(rightTime && !alreadyToday)
         EvaluateAndOpen();
     }
  }

//========================================================================
//  DIRECTION FILTER
//  Compares N-bar H1 return of US30 vs US500.
//  Returns:  1 = normal direction (US500 leading, trade as normal)
//           -1 = US30 leading (flip or skip depending on input)
//            0 = inconclusive / filter disabled
//========================================================================
int DirectionSignal()
  {
   if(!UseDirectionFilter) return 1;

   // We need FilterLookbackBars+1 bars
   int barsNeeded = FilterLookbackBars + 1;

   double close30[];  ArraySetAsSeries(close30,  true);
   double close500[]; ArraySetAsSeries(close500, true);

   if(CopyClose(Sym_US30,  PERIOD_H1, 0, barsNeeded, close30)  < barsNeeded ||
      CopyClose(Sym_US500, PERIOD_H1, 0, barsNeeded, close500) < barsNeeded)
     {
      if(EnablePrint) Print("Direction filter: not enough bars, skipping filter.");
      return 1; // default: trade normally
     }

   // Return over the lookback period (current close vs N bars ago close)
   double ret30  = (close30[0]  - close30[FilterLookbackBars])  / close30[FilterLookbackBars]  * 100.0;
   double ret500 = (close500[0] - close500[FilterLookbackBars]) / close500[FilterLookbackBars] * 100.0;
   double diff   = ret30 - ret500; // positive = US30 outperforming

   if(EnablePrint)
      PrintFormat("Direction filter | US30 1h ret=%.4f%%  US500 1h ret=%.4f%%  diff=%.4f%%  threshold=%.4f%%",
                  ret30, ret500, diff, FilterThresholdPct);

   if(diff > FilterThresholdPct)
      return -1; // US30 is leading – normal thesis is weaker

   return 1; // US500 leading or neutral – trade as normal
  }

//========================================================================
//  ATR-BASED DYNAMIC LOT SIZING
//  Sizes US500 lots so that 1 ATR move costs the same dollar amount
//  as 1 ATR move on the US30 anchor leg.
//  
//  Dollar volatility per lot = ATR * (TickValue / TickSize)
//  Lots_US500 = (ATR_30 * PointVal_30 * BaseLots_US30)
//               / (ATR_500 * PointVal_500)
//========================================================================
bool CalcDynamicLots(double &lotsUS30, double &lotsUS500)
  {
   lotsUS30  = BaseLots_US30;
   lotsUS500 = FixedLots_US500; // fallback

   if(!UseDynamicLots)
     {
      lotsUS30  = FixedLots_US30;
      lotsUS500 = FixedLots_US500;
      return true;
     }

   // ATR handles
   int atr30  = iATR(Sym_US30,  ATR_TF, ATR_Period);
   int atr500 = iATR(Sym_US500, ATR_TF, ATR_Period);
   if(atr30 == INVALID_HANDLE || atr500 == INVALID_HANDLE)
     {
      if(EnablePrint) Print("ATR handles invalid – using fixed lots.");
      lotsUS30  = FixedLots_US30;
      lotsUS500 = FixedLots_US500;
      return true;
     }

   double atrVal30[1], atrVal500[1];
   if(CopyBuffer(atr30,  0, 0, 1, atrVal30)  < 1 ||
      CopyBuffer(atr500, 0, 0, 1, atrVal500) < 1)
     {
      if(EnablePrint) Print("ATR buffer copy failed – using fixed lots.");
      lotsUS30  = FixedLots_US30;
      lotsUS500 = FixedLots_US500;
      IndicatorRelease(atr30); IndicatorRelease(atr500);
      return true;
     }

   IndicatorRelease(atr30);
   IndicatorRelease(atr500);

   // $ per point per 1 lot
   double pv30  = SymbolInfoDouble(Sym_US30,  SYMBOL_TRADE_TICK_VALUE)
                / SymbolInfoDouble(Sym_US30,  SYMBOL_TRADE_TICK_SIZE);
   double pv500 = SymbolInfoDouble(Sym_US500, SYMBOL_TRADE_TICK_VALUE)
                / SymbolInfoDouble(Sym_US500, SYMBOL_TRADE_TICK_SIZE);

   if(pv500 <= 0 || atrVal500[0] <= 0)
     {
      if(EnablePrint) Print("Invalid point value or ATR – using fixed lots.");
      lotsUS30  = FixedLots_US30;
      lotsUS500 = FixedLots_US500;
      return true;
     }

   // Equalize dollar volatility
   double rawLots500 = (atrVal30[0] * pv30 * BaseLots_US30) / (atrVal500[0] * pv500);

   // Round to broker's lot step
   double lotStep = SymbolInfoDouble(Sym_US500, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(Sym_US500, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(Sym_US500, SYMBOL_VOLUME_MAX);
   rawLots500 = MathRound(rawLots500 / lotStep) * lotStep;
   rawLots500 = MathMax(lotMin, MathMin(lotMax, rawLots500));

   lotsUS30  = BaseLots_US30;
   lotsUS500 = rawLots500;

   if(EnablePrint)
      PrintFormat("Dynamic lots | ATR30=%.2f ATR500=%.2f PV30=%.4f PV500=%.4f "
                  "-> US30 lots=%.2f  US500 lots=%.2f",
                  atrVal30[0], atrVal500[0], pv30, pv500, lotsUS30, lotsUS500);
   return true;
  }

//========================================================================
//  EVALUATE DIRECTION FILTER THEN OPEN LEGS
//========================================================================
void EvaluateAndOpen()
  {
   int signal = DirectionSignal();

   bool shortUS30  = true;  // default direction
   bool longUS500  = true;

   if(signal == -1) // US30 is outperforming
     {
      if(FlipOnFilter)
        {
         // Flip: Long US30, Short US500
         shortUS30 = false;
         longUS500 = false;
         if(EnablePrint) Print("Direction filter: US30 leading – FLIPPING legs.");
        }
      else
        {
         if(EnablePrint) Print("Direction filter: US30 leading – SKIPPING trade today.");
         MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
         lastTradeDay = dt.day; // mark day as used so we don't re-check every minute
         return;
        }
     }

   double lotsUS30, lotsUS500;
   CalcDynamicLots(lotsUS30, lotsUS500);

   OpenLegs(lotsUS30, lotsUS500, shortUS30, longUS500);
  }

//========================================================================
//  OPEN LEGS
//========================================================================
void OpenLegs(double lotsUS30, double lotsUS500, bool sellUS30, bool buyUS500)
  {
   // Reset trailing state
   peakPnL     = -DBL_MAX;
   trailActive = false;

   double bid30  = SymbolInfoDouble(Sym_US30,  SYMBOL_BID);
   double ask30  = SymbolInfoDouble(Sym_US30,  SYMBOL_ASK);
   double bid500 = SymbolInfoDouble(Sym_US500, SYMBOL_BID);
   double ask500 = SymbolInfoDouble(Sym_US500, SYMBOL_ASK);

   bool leg1 = sellUS30
               ? trade.Sell(lotsUS30, Sym_US30,  bid30,  0, 0, "US30 SHORT")
               : trade.Buy (lotsUS30, Sym_US30,  ask30,  0, 0, "US30 LONG");

   bool leg2 = buyUS500
               ? trade.Buy (lotsUS500, Sym_US500, ask500, 0, 0, "US500 LONG")
               : trade.Sell(lotsUS500, Sym_US500, bid500, 0, 0, "US500 SHORT");

   if(leg1 && leg2)
     {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      lastTradeDay  = dt.day;
      positionsOpen = true;
      string msg = StringFormat("OPENED | %s %.2f %s @ %.2f | %s %.2f %s @ %.2f",
                                sellUS30?"SELL":"BUY",  lotsUS30,  Sym_US30,  sellUS30?bid30:ask30,
                                buyUS500?"BUY":"SELL",  lotsUS500, Sym_US500, buyUS500?ask500:bid500);
      if(EnablePrint)  Print(msg);
      if(EnableAlerts) Alert(msg);
     }
   else
     {
      if(EnablePrint)
         PrintFormat("Partial fill: leg1=%s leg2=%s – cleaning up.", leg1?"OK":"FAIL", leg2?"OK":"FAIL");
      CloseAllLegs("Partial fill cleanup");
     }
  }

//========================================================================
//  CLOSE ALL EA LEGS  (always via PositionClose(ticket))
//========================================================================
void CloseAllLegs(string reason)
  {
   int closed = 0;

   for(int attempt = 0; attempt < 10; attempt++)
     {
      bool foundAny = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
         foundAny = true;
         if(trade.PositionClose(ticket, Slippage))
            closed++;
         else if(EnablePrint)
            PrintFormat("PositionClose failed: #%I64u retcode=%d %s",
                        ticket, trade.ResultRetcode(), trade.ResultComment());
        }
      if(!foundAny) break;
     }

   positionsOpen = false;
   peakPnL       = -DBL_MAX;
   trailActive   = false;

   string msg = StringFormat("CLOSED %d leg(s) | Reason: %s", closed, reason);
   if(EnablePrint)  Print(msg);
   if(EnableAlerts) Alert(msg);
  }

//========================================================================
//  COMBINED FLOATING P&L  (profit + swap)
//========================================================================
double GetCombinedPnL()
  {
   double total = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return total;
  }

//========================================================================
//  BOTH LEGS OPEN CHECK
//========================================================================
bool AreBothLegsOpen()
  {
   bool hasUS30 = false, hasUS500 = false;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      if(sym == Sym_US30)  hasUS30  = true;
      if(sym == Sym_US500) hasUS500 = true;
     }
   return (hasUS30 && hasUS500);
  }

//========================================================================
void OnDeinit(const int reason)
  {
   if(EnablePrint) PrintFormat("EA removed (reason %d).", reason);
  }
//========================================================================
