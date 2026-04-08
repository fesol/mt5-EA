//+------------------------------------------------------------------+
//|                                           BreakReturn_EA.mq5     |
//|                    Break & Return Strategy  v1.2                  |
//|  + ATR threshold in hourly log                                    |
//|  + Previous candle H/L/Mid horizontal lines on chart             |
//|  + AMA slope trend filter (higher TF, relative %)                |
//|  + Trailing stop based on TP distance (continuous or step)       |
//+------------------------------------------------------------------+
#property copyright "BreakReturn EA"
#property version   "1.20"
#property description "Break & Return Hourly Strategy - Symbol-Agnostic"

#include <Trade\Trade.mqh>

//─────────────────────────────────────────────────────────────────────
//  ENUMS
//─────────────────────────────────────────────────────────────────────
enum ENUM_TRAIL_MODE
{
   TRAIL_CONTINUOUS = 0, // Continuous — SL follows every tick
   TRAIL_STEP       = 1  // Step-based — SL jumps in fixed chunks
};

//─────────────────────────────────────────────────────────────────────
//  INPUT PARAMETERS
//─────────────────────────────────────────────────────────────────────

input group "══════ Setup ══════"
input int     InpWindowMinutes   = 15;      // Breakout window after hour open (minutes)
input double  InpBreakPct        = 0.20;    // Break distance (% of prev range, e.g. 0.20 = 20%)
input double  InpSLBufferPct     = 0.05;    // SL buffer past current candle extreme (% of prev range)
input int     InpTPOption        = 1;       // TP: 1 = Midpoint prev candle | 2 = Opposite side
input bool    AllowSells         = false; 

input group "══════ ATR Range Filter ══════"
input bool    InpUseATRFilter    = true;    // Enable ATR range filter
input int     InpATRPeriod       = 200;     // ATR period (Daily TF)
input double  InpATRMultiplier   = 1.0;     // Prev H1 range must be >= Multiplier x Daily ATR

input group "══════ AMA Trend Filter ══════"
input bool            InpUseAMAFilter  = true;       // Enable AMA slope trend filter
input ENUM_TIMEFRAMES InpAMATF         = PERIOD_D1;  // AMA timeframe (default Daily)
input int             InpAMAPeriod     = 5;           // AMA period
input int             InpAMAFast       = 2;           // AMA fast EMA period
input int             InpAMASlow       = 8;           // AMA slow EMA period
input double          InpAMAThreshold  = 0.02;        // Slope threshold %
// Slope = (AMA[1]-AMA[2]) / AMA[1] * 100  (last two CLOSED bars)
// Above +threshold  -> Buys only
// Below -threshold  -> Sells only
// Between +-threshold -> Flat, no trades
// Recommended for indices (Daily): 0.01 - 0.05

input group "══════ Trailing Stop ══════"
input bool           InpUseTrailing      = true;   // Enable trailing stop
input ENUM_TRAIL_MODE InpTrailMode       = TRAIL_CONTINUOUS; // Trail mode: Continuous or Step
input double         InpTrailActivatePct = 50.0;   // Activate trail when price reaches X% of TP distance
input double         InpTrailDistPct     = 30.0;   // Trail distance as % of TP distance
// Example with TP distance = 100pts:
//   InpTrailActivatePct=50 -> trail activates when profit reaches 50pts
//   InpTrailDistPct=30     -> SL trails 30pts behind current price
// Step mode: SL only moves forward once price advances by another full trail distance chunk

input group "══════ Session Filter ══════"
input bool    InpUseTimeFilter   = true;    // Enable session time filter
input int     InpStartHour       = 8;       // Session start (server time, inclusive)
input int     InpEndHour         = 20;      // Session end   (server time, exclusive)

input group "══════ Risk Management ══════"
input bool    InpUsePercentRisk  = true;    // true = % of balance | false = fixed lot
input double  InpRiskPercent     = 1.0;     // Risk per trade (% of account balance)
input double  InpFixedLot        = 0.10;    // Fixed lot size (used when % risk disabled)

input group "══════ Chart Lines ══════"
input bool             InpDrawLines  = true;          // Draw prev candle H/L/Mid lines on chart
input color            InpColorHigh  = clrRed;        // Line color: Prev High
input color            InpColorLow   = clrDodgerBlue; // Line color: Prev Low
input color            InpColorMid   = clrGold;       // Line color: Prev Midpoint
input ENUM_LINE_STYLE  InpLineStyle  = STYLE_DASH;    // Line style

input group "══════ EA Settings ══════"
input long    InpMagic           = 202401;  // Magic number
input bool    InpPrintLogs       = true;    // Print signals to Experts log

//─────────────────────────────────────────────────────────────────────
//  LINE NAME CONSTANTS
//─────────────────────────────────────────────────────────────────────
#define LINE_HIGH  "BRE_PrevHigh"
#define LINE_LOW   "BRE_PrevLow"
#define LINE_MID   "BRE_PrevMid"

//─────────────────────────────────────────────────────────────────────
//  GLOBAL STATE
//─────────────────────────────────────────────────────────────────────
CTrade   trade;
int      g_atrHandle    = INVALID_HANDLE;
int      g_amaHandle    = INVALID_HANDLE;

datetime g_lastHourTime = 0;
bool     g_hourTraded   = false;
bool     g_breakedBelow = false;
bool     g_breakedAbove = false;

double   g_prevHigh     = 0;
double   g_prevLow      = 0;
double   g_prevMid      = 0;
double   g_prevRange    = 0;
double   g_buyTrigger   = 0;
double   g_sellTrigger  = 0;
datetime g_windowEnd    = 0;

//─────────────────────────────────────────────────────────────────────
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   if(InpUseATRFilter)
   {
      g_atrHandle = iATR(_Symbol, PERIOD_D1, InpATRPeriod);
      if(g_atrHandle == INVALID_HANDLE)
      {
         Alert("BreakReturn EA: Failed to create Daily ATR handle.");
         return INIT_FAILED;
      }
   }

   if(InpUseAMAFilter)
   {
      g_amaHandle = iAMA(_Symbol, InpAMATF, InpAMAPeriod, InpAMAFast, InpAMASlow, 0, PRICE_CLOSE);
      if(g_amaHandle == INVALID_HANDLE)
      {
         Alert("BreakReturn EA: Failed to create AMA handle.");
         return INIT_FAILED;
      }
   }

   if(InpTPOption != 1 && InpTPOption != 2)
   {
      Alert("BreakReturn EA: InpTPOption must be 1 or 2.");
      return INIT_FAILED;
   }

   if(InpUseTrailing)
   {
      if(InpTrailActivatePct <= 0 || InpTrailActivatePct >= 100)
      {
         Alert("BreakReturn EA: InpTrailActivatePct must be between 0 and 100.");
         return INIT_FAILED;
      }
      if(InpTrailDistPct <= 0 || InpTrailDistPct >= 100)
      {
         Alert("BreakReturn EA: InpTrailDistPct must be between 0 and 100.");
         return INIT_FAILED;
      }
   }

   Print("BreakReturn EA v1.2 initialised on ", _Symbol,
         " | Window=", InpWindowMinutes, "min",
         " | BreakPct=", DoubleToString(InpBreakPct*100,1), "%",
         " | TP=", (InpTPOption==1 ? "Midpoint" : "Opposite side"),
         " | AMA filter=", (InpUseAMAFilter ? "ON" : "OFF"),
         " | ATR filter=", (InpUseATRFilter ? "ON" : "OFF"),
         " | Trailing=", (InpUseTrailing ? (InpTrailMode==TRAIL_CONTINUOUS ? "Continuous" : "Step") : "OFF"));

   return INIT_SUCCEEDED;
}

//─────────────────────────────────────────────────────────────────────
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_amaHandle != INVALID_HANDLE) IndicatorRelease(g_amaHandle);
   DeleteLevelLines();
}

//─────────────────────────────────────────────────────────────────────
void OnTick()
{
   // ── Always manage open positions first ──
   if(InpUseTrailing) ManageTrailing();

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   //────────────────────────────────────────
   // 1. DETECT NEW HOUR
   //────────────────────────────────────────
   MqlDateTime hDt = dt;
   hDt.min = 0;
   hDt.sec = 0;
   datetime thisHour = StructToTime(hDt);

   if(thisHour != g_lastHourTime)
   {
      g_lastHourTime = thisHour;
      g_hourTraded   = false;
      g_breakedBelow = false;
      g_breakedAbove = false;

      double pH = iHigh(_Symbol, PERIOD_H1, 1);
      double pL = iLow (_Symbol, PERIOD_H1, 1);

      if(pH <= 0 || pL <= 0 || pH <= pL)
      {
         g_prevRange = 0;
         return;
      }

      g_prevHigh    = pH;
      g_prevLow     = pL;
      g_prevMid     = (pH + pL) / 2.0;
      g_prevRange   = pH - pL;
      g_buyTrigger  = pL - InpBreakPct * g_prevRange;
      g_sellTrigger = pH + InpBreakPct * g_prevRange;
      g_windowEnd   = thisHour + (datetime)(InpWindowMinutes * 60);

      // ── ATR info for log ──
      string atrLog = "ATR filter=OFF";
      if(InpUseATRFilter && g_atrHandle != INVALID_HANDLE)
      {
         double atrBuf[1];
         ArraySetAsSeries(atrBuf, true);
         if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) > 0 && atrBuf[0] > 0)
         {
            double minRequired = InpATRMultiplier * atrBuf[0];
            bool   passes      = g_prevRange >= minRequired;
            atrLog = StringFormat("ATRx%.1f=%.5f (need>=%.5f) [%s]",
                                  InpATRMultiplier,
                                  atrBuf[0],
                                  minRequired,
                                  passes ? "PASS" : "FAIL");
         }
      }

      if(InpPrintLogs)
         PrintFormat("[%s] New hour | PrevH=%.5f PrevL=%.5f Range=%.5f | "
                     "BuyTrig=%.5f SellTrig=%.5f | Window until %s | %s",
                     _Symbol,
                     g_prevHigh, g_prevLow, g_prevRange,
                     g_buyTrigger, g_sellTrigger,
                     TimeToString(g_windowEnd, TIME_MINUTES),
                     atrLog);

      if(InpDrawLines) DrawLevelLines();
   }

   //────────────────────────────────────────
   // 2. EARLY EXIT
   //────────────────────────────────────────
   if(g_hourTraded)      return;
   if(g_prevRange <= 0)  return;
   if(now > g_windowEnd) return;

   //────────────────────────────────────────
   // 3. SESSION FILTER
   //────────────────────────────────────────
   if(InpUseTimeFilter)
      if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return;

   //────────────────────────────────────────
   // 4. ATR RANGE FILTER
   //────────────────────────────────────────
   if(InpUseATRFilter && g_atrHandle != INVALID_HANDLE)
   {
      double atrBuf[1];
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) <= 0) return;
      if(atrBuf[0] <= 0 || g_prevRange < InpATRMultiplier * atrBuf[0]) return;
   }

   //────────────────────────────────────────
   // 5. AMA TREND FILTER
   //────────────────────────────────────────
   bool allowBuy  = true;
   bool allowSell = true;

   if(InpUseAMAFilter && g_amaHandle != INVALID_HANDLE)
   {
      double amaBuf[3];
      ArraySetAsSeries(amaBuf, true);
      if(CopyBuffer(g_amaHandle, 0, 1, 3, amaBuf) < 3) return;

      double ama1  = amaBuf[0];
      double ama2  = amaBuf[1];
      if(ama1 <= 0 || ama2 <= 0) return;

      double slope = (ama1 - ama2) / ama1 * 100.0;

      if(slope > InpAMAThreshold)        { allowBuy = true;  allowSell = false; }
      else if(slope < -InpAMAThreshold)  { allowBuy = false; allowSell = true;  }
      else                               { allowBuy = false; allowSell = false; }

      if(InpPrintLogs && (g_breakedBelow || g_breakedAbove))
         PrintFormat("AMA slope=%.5f%% (threshold=+-%.4f%%) | AllowBuy=%s AllowSell=%s",
                     slope, InpAMAThreshold,
                     allowBuy  ? "YES" : "NO",
                     allowSell ? "YES" : "NO");
   }

   //────────────────────────────────────────
   // 6. TRACK BREAKOUTS
   //────────────────────────────────────────
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(bid < g_buyTrigger)  g_breakedBelow = true;
   if(ask > g_sellTrigger) g_breakedAbove = true;

   //────────────────────────────────────────
   // 7. BUY SETUP
   //────────────────────────────────────────
   if(g_breakedBelow && ask >= g_prevLow && allowBuy)
   {
      double curLow = iLow(_Symbol, PERIOD_H1, 0);
      double buffer = InpSLBufferPct * g_prevRange;
      double sl     = curLow - buffer;
      double tp     = (InpTPOption == 1) ? g_prevMid : g_prevHigh;

      if(tp <= ask)
      {
         if(InpPrintLogs) PrintFormat("BUY skipped: TP(%.5f) <= Ask(%.5f)", tp, ask);
         return;
      }

      double lots = CalculateLots(ask, sl);
      if(lots <= 0) return;

      if(InpPrintLogs)
         PrintFormat(">>> BUY signal | Ask=%.5f SL=%.5f TP=%.5f Lots=%.2f", ask, sl, tp, lots);

      if(trade.Buy(lots, _Symbol, ask, sl, tp, "HourlyFakeout_Buy"))
      {
         g_hourTraded = true;
         Print("BUY executed: ticket=", trade.ResultOrder());
      }
      else
         Print("BUY failed: ", trade.ResultRetcodeDescription());

      return;
   }

   //────────────────────────────────────────
   // 8. SELL SETUP
   //────────────────────────────────────────
   if(g_breakedAbove && bid <= g_prevHigh && allowSell && AllowSells)
   {
      double curHigh = iHigh(_Symbol, PERIOD_H1, 0);
      double buffer  = InpSLBufferPct * g_prevRange;
      double sl      = curHigh + buffer;
      double tp      = (InpTPOption == 1) ? g_prevMid : g_prevLow;

      if(tp >= bid)
      {
         if(InpPrintLogs) PrintFormat("SELL skipped: TP(%.5f) >= Bid(%.5f)", tp, bid);
         return;
      }

      double lots = CalculateLots(bid, sl);
      if(lots <= 0) return;

      if(InpPrintLogs)
         PrintFormat(">>> SELL signal | Bid=%.5f SL=%.5f TP=%.5f Lots=%.2f", bid, sl, tp, lots);

      if(trade.Sell(lots, _Symbol, bid, sl, tp, "HourlyFakout_Sell"))
      {
         g_hourTraded = true;
         Print("SELL executed: ticket=", trade.ResultOrder());
      }
      else
         Print("SELL failed: ", trade.ResultRetcodeDescription());
   }
}

//─────────────────────────────────────────────────────────────────────
//  TRAILING STOP MANAGER
//
//  Called on every tick. Loops through all open positions on this
//  symbol that belong to this EA (magic number match).
//
//  For each position:
//    tpDist       = |TP - entry|                    (full TP distance)
//    activateDist = tpDist * InpTrailActivatePct/100
//    trailDist    = tpDist * InpTrailDistPct/100
//
//  CONTINUOUS mode:
//    Once price moves activateDist in our favour, SL is moved to
//    (currentPrice - trailDist) for buys / (currentPrice + trailDist)
//    for sells, every tick — always the tightest valid level.
//
//  STEP mode:
//    SL only advances in discrete jumps of trailDist. A new step is
//    triggered when price beats the last activation price by another
//    full trailDist chunk.
//─────────────────────────────────────────────────────────────────────
void ManageTrailing()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))             continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;

      ENUM_POSITION_TYPE posType  = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             entry    = PositionGetDouble(POSITION_PRICE_OPEN);
      double             curSL    = PositionGetDouble(POSITION_SL);
      double             curTP    = PositionGetDouble(POSITION_TP);

      if(curTP <= 0) continue; // no TP set — can't compute distance

      double tpDist       = MathAbs(curTP - entry);
      if(tpDist <= 0)     continue;

      double activateDist = tpDist * InpTrailActivatePct / 100.0;
      double trailDist    = tpDist * InpTrailDistPct    / 100.0;

      // Minimum legal distance from price to SL (stops level)
      double stopsLevel   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)
                            * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      double newSL = curSL;

      if(posType == POSITION_TYPE_BUY)
      {
         double profit = bid - entry;
         if(profit < activateDist) continue; // not activated yet

         if(InpTrailMode == TRAIL_CONTINUOUS)
         {
            // SL = bid - trailDist, but never lower than current SL
            double candidate = bid - trailDist;
            candidate = NormalizeDouble(candidate, _Digits);
            if(candidate > curSL && bid - candidate >= stopsLevel)
               newSL = candidate;
         }
         else // TRAIL_STEP
         {
            // How many full trailDist steps has price advanced beyond activateDist?
            // SL sits at entry + activateDist + (steps-1)*trailDist - trailDist
            // = entry + activateDist + (steps)*trailDist - trailDist
            // Simplified: SL = price_at_last_step - trailDist
            double stepsCompleted = MathFloor((profit - activateDist) / trailDist);
            double stepSL = NormalizeDouble(
                              entry + activateDist + stepsCompleted * trailDist - trailDist,
                              _Digits);
            // First step: SL moves to entry + activateDist - trailDist (may be BE or small profit)
            if(stepSL > curSL && bid - stepSL >= stopsLevel)
               newSL = stepSL;
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double profit = entry - ask;
         if(profit < activateDist) continue;

         if(InpTrailMode == TRAIL_CONTINUOUS)
         {
            double candidate = ask + trailDist;
            candidate = NormalizeDouble(candidate, _Digits);
            if(candidate < curSL && candidate - ask >= stopsLevel)
               newSL = candidate;
         }
         else // TRAIL_STEP
         {
            double stepsCompleted = MathFloor((profit - activateDist) / trailDist);
            double stepSL = NormalizeDouble(
                              entry - activateDist - stepsCompleted * trailDist + trailDist,
                              _Digits);
            if(stepSL < curSL && stepSL - ask >= stopsLevel)
               newSL = stepSL;
         }
      }

      // Only modify if SL actually changed
      if(newSL != curSL)
      {
         if(trade.PositionModify(ticket, newSL, curTP))
         {
            if(InpPrintLogs)
               PrintFormat("TRAIL [%s] #%I64u | NewSL=%.5f (was %.5f)",
                           (posType==POSITION_TYPE_BUY ? "BUY" : "SELL"),
                           ticket, newSL, curSL);
         }
      }
   }
}

//─────────────────────────────────────────────────────────────────────
//  CHART LINES
//─────────────────────────────────────────────────────────────────────
void DrawLevelLines()
{
   DeleteLevelLines();
   DrawHLine(LINE_HIGH, g_prevHigh, InpColorHigh, "Prev H: "   + DoubleToString(g_prevHigh, _Digits));
   DrawHLine(LINE_LOW,  g_prevLow,  InpColorLow,  "Prev L: "   + DoubleToString(g_prevLow,  _Digits));
   DrawHLine(LINE_MID,  g_prevMid,  InpColorMid,  "Prev Mid: " + DoubleToString(g_prevMid,  _Digits));
   ChartRedraw(0);
}

void DrawHLine(string name, double price, color clr, string tooltip)
{
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      InpLineStyle);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString (0, name, OBJPROP_TOOLTIP,    tooltip);
}

void DeleteLevelLines()
{
   ObjectDelete(0, LINE_HIGH);
   ObjectDelete(0, LINE_LOW);
   ObjectDelete(0, LINE_MID);
}

//─────────────────────────────────────────────────────────────────────
//  LOT SIZE CALCULATION
//─────────────────────────────────────────────────────────────────────
double CalculateLots(double entryPrice, double slPrice)
{
   double lots;

   if(!InpUsePercentRisk)
   {
      lots = InpFixedLot;
   }
   else
   {
      double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney = balance * InpRiskPercent / 100.0;
      double slDist    = MathAbs(entryPrice - slPrice);

      if(slDist <= 0) { Print("CalculateLots: SL distance zero."); return 0; }

      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

      if(tickSize <= 0 || tickValue <= 0)
      {
         Print("CalculateLots: Invalid tick data for ", _Symbol);
         return 0;
      }

      double riskPerLot = (slDist / tickSize) * tickValue;
      if(riskPerLot <= 0) return 0;

      lots = riskMoney / riskPerLot;
   }

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return NormalizeDouble(lots, 2);
}
//+------------------------------------------------------------------+