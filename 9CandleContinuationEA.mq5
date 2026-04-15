//+------------------------------------------------------------------+
//|         9AM New York First-Hour Continuation Strategy            |
//|                                                                  |
//|  Logic:                                                          |
//|   1. At InpServerEntryHour (default 17:00 server = 10AM NY)     |
//|      read the just-closed H1 candle (= 9AM NY candle).          |
//|   2. Conviction = |Close-Open| / (High-Low)                     |
//|   3. ATR size filter: candle range > InpATRCandleFilter × D1ATR |
//|   4. Green + conviction ≥ threshold → Long                      |
//|      Red  + conviction ≥ threshold → Short                      |
//|   5. During exit window: close on RSI extreme                    |
//|   6. Force-close at end of exit window                          |
//|   7. Close if floating profit ≥ % of account balance             |
//+------------------------------------------------------------------+
#property copyright "9AM NY Conviction EA"
#property version   "1.02"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//====================================================================
//  INPUT PARAMETERS
//====================================================================

input group "══ EA Settings ════════════════════════════"
input long   InpMagicNumber      = 9001;  // EA Magic Number

input group "══ Entry ══════════════════════════════════"
input int    InpServerEntryHour  = 17;    // Server hour when 9AM NY candle closes (10AM NY)
input double InpConviction       = 0.70;  // Minimum conviction  |Close-Open|/(High-Low)
input double InpATRCandleFilter  = 0.25;  // Min candle range as multiplier of Daily ATR
input int    InpATRPeriod        = 14;    // ATR period (Daily timeframe)

input group "══ Direction Filter ═══════════════════════"
input bool   InpAllowLong        = true;  // Allow Long trades
input bool   InpAllowShort       = true;  // Allow Short trades

input group "══ Stop Loss ══════════════════════════════"
enum ENUM_SL_MODE
{
   SL_ATR  = 0,  // ATR Multiplier
   SL_9AM  = 1,  // 9AM High / Low
   SL_NONE = 2   // No stop loss (time/RSI exit only)
};
input ENUM_SL_MODE InpSLMode     = SL_ATR;  // Stop loss type
input double InpSLATRMult        = 1.5;     // ATR multiplier for SL (if SL_ATR)

input group "══ Risk ════════════════════════════════════"
input double InpRiskPct          = 1.0;   // Risk % of account balance per trade

input group "══ Exit Window ═════════════════════════════"
input int    InpExitStartHour    = 21;    // Exit window: start hour   (server time)
input int    InpExitStartMin     = 50;    // Exit window: start minute (server time)
input int    InpExitEndHour      = 22;    // Exit window: end hour     (server time)
input int    InpExitEndMin       = 55;    // Exit window: end minute   (server time)

input group "══ RSI Exit ════════════════════════════════"
input ENUM_TIMEFRAMES InpRSITF   = PERIOD_H1;  // RSI timeframe
input int    InpRSIPeriod        = 14;          // RSI period
input double InpRSILongClose     = 90.0;        // RSI ≥ this → close longs
input double InpRSIShortClose    = 10.0;        // RSI ≤ this → close shorts

input group "══ Profit Target ════════════════════════"
input bool   InpUseProfitTarget   = false;  // Enable profit target exit
input double InpProfitTargetPct   = 1.0;    // Close when profit ≥ this % of account balance

//====================================================================
//  CONSTANTS & GLOBALS
//====================================================================
CTrade        trade;
CPositionInfo posInfo;

int      g_atrHandle    = INVALID_HANDLE;
int      g_rsiHandle    = INVALID_HANDLE;
ulong    g_magic        = 0;        // Stores the user-defined magic number

datetime g_today        = 0;        // Current trading day (midnight)
bool     g_tradedToday  = false;    // One trade per day flag
bool     g_entryChecked = false;    // Entry logic run today flag

double   g_nineAMHigh   = 0.0;
double   g_nineAMLow    = 0.0;

//====================================================================
//  INIT
//====================================================================
int OnInit()
{
   // Store magic number from input
   g_magic = (ulong)InpMagicNumber;
   
   // Daily ATR for size filter and SL
   g_atrHandle = iATR(_Symbol, PERIOD_D1, InpATRPeriod);
   // RSI on user-defined timeframe for exit
   g_rsiHandle = iRSI(_Symbol, InpRSITF, InpRSIPeriod, PRICE_CLOSE);

   if(g_atrHandle == INVALID_HANDLE || g_rsiHandle == INVALID_HANDLE)
   {
      Alert("NineAM EA: Failed to create indicator handles. Aborting.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(g_magic);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   PrintFormat("NineAM Conviction EA initialised | Symbol=%s | Magic=%llu | EntryHour(server)=%d | Conviction=%.2f | SLMode=%d",
               _Symbol, g_magic, InpServerEntryHour, InpConviction, (int)InpSLMode);
   return INIT_SUCCEEDED;
}

//====================================================================
//  DEINIT
//====================================================================
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
}

//====================================================================
//  TICK
//====================================================================
void OnTick()
{
   // --- Performance optimization: run only once per second ---
   static datetime lastTickTime = 0;
   datetime now = TimeCurrent();
   if(now == lastTickTime)
      return;                 // skip repeated ticks within the same second
   lastTickTime = now;

   MqlDateTime dt;
   TimeToStruct(now, dt);
   datetime today = now - dt.hour * 3600 - dt.min * 60 - dt.sec;

   //── Daily reset ─────────────────────────────────────────────────
   if(today != g_today)
   {
      g_today        = today;
      g_tradedToday  = false;
      g_entryChecked = false;
      g_nineAMHigh   = 0.0;
      g_nineAMLow    = 0.0;
   }

   //── Entry: fire once when the H1 bar opens at InpServerEntryHour ─
   if(!g_entryChecked && !g_tradedToday && !HasPosition())
   {
      // Compare the open-time of the current H1 bar
      datetime h1Open = iTime(_Symbol, PERIOD_H1, 0);
      MqlDateTime h1dt;
      TimeToStruct(h1Open, h1dt);

      if(h1dt.hour == InpServerEntryHour)
      {
         g_entryChecked = true;   // mark before any early return
         CheckEntry();
      }
   }

   //── Exit window ──────────────────────────────────────────────────
   if(HasPosition())
   {
      // 1) Profit target exit (if enabled)
      if(InpUseProfitTarget)
         CheckProfitTargetExit();

      int nowMin   = dt.hour * 60 + dt.min;
      int winStart = InpExitStartHour * 60 + InpExitStartMin;
      int winEnd   = InpExitEndHour   * 60 + InpExitEndMin;

      // 2) RSI exit (only during exit window)
      if(nowMin >= winStart && nowMin <= winEnd)
         CheckRSIExit();

      // 3) Force-close after window ends
      if(nowMin > winEnd)
         CloseAll("EOD forced close");
   }
}

//====================================================================
//  CHECK ENTRY
//====================================================================
void CheckEntry()
{
   //── Get just-closed H1 candle (bar index 1 = 9AM NY candle) ─────
   MqlRates h1[];
   ArraySetAsSeries(h1, true);
   if(CopyRates(_Symbol, PERIOD_H1, 1, 1, h1) < 1)
   {
      Print("NineAM EA: CopyRates H1 failed");
      return;
   }

   double o     = h1[0].open;
   double h     = h1[0].high;
   double l     = h1[0].low;
   double c     = h1[0].close;
   double range = h - l;

   if(range < _Point) return;   // degenerate candle

   g_nineAMHigh = h;
   g_nineAMLow  = l;

   //── Conviction ───────────────────────────────────────────────────
   double conviction = MathAbs(c - o) / range;
   if(conviction < InpConviction)
   {
      PrintFormat("NineAM EA: Conviction %.2f < threshold %.2f — no trade", conviction, InpConviction);
      return;
   }

   //── Daily ATR filter ─────────────────────────────────────────────
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) < 1)
   {
      Print("NineAM EA: ATR buffer read failed");
      return;
   }
   double dailyATR = atrBuf[0];

   if(range < InpATRCandleFilter * dailyATR)
   {
      PrintFormat("NineAM EA: Candle range %.5f < %.2f × ATR (%.5f) — no trade",
                  range, InpATRCandleFilter, dailyATR);
      return;
   }

   //── Direction ────────────────────────────────────────────────────
   bool isLong = (c > o);

   // Apply direction filter
   if(isLong && !InpAllowLong)
   {
      Print("NineAM EA: Long signal generated but InpAllowLong = false. Trade skipped.");
      return;
   }
   if(!isLong && !InpAllowShort)
   {
      Print("NineAM EA: Short signal generated but InpAllowShort = false. Trade skipped.");
      return;
   }

   //── Stop loss distance ───────────────────────────────────────────
   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entryPx   = isLong ? ask : bid;
   double slPrice   = 0.0;
   double slDist    = 0.0;

   switch(InpSLMode)
   {
      case SL_ATR:
         slDist  = InpSLATRMult * dailyATR;
         slPrice = isLong ? entryPx - slDist : entryPx + slDist;
         break;

      case SL_9AM:
         slPrice = isLong ? g_nineAMLow : g_nineAMHigh;
         slDist  = MathAbs(entryPx - slPrice);
         break;

      case SL_NONE:
      default:
         // No hard SL; use ATR distance only for position sizing
         slDist  = InpSLATRMult * dailyATR;
         slPrice = 0.0;
         break;
   }

   if(slDist < _Point) slDist = dailyATR;   // safety floor

   //── Lot calculation ──────────────────────────────────────────────
   double lots = CalcLots(slDist);
   if(lots <= 0.0)
   {
      Print("NineAM EA: Lot calculation returned 0 — aborting trade");
      return;
   }

   slPrice = (InpSLMode != SL_NONE) ? NormalizeDouble(slPrice, _Digits) : 0.0;

   PrintFormat("NineAM EA | Dir=%s | O=%.5f H=%.5f L=%.5f C=%.5f | Conv=%.2f | ATR=%.5f | SL=%.5f | Lots=%.2f",
               isLong ? "LONG" : "SHORT", o, h, l, c, conviction, dailyATR, slPrice, lots);

   //── Send order ───────────────────────────────────────────────────
   bool ok = isLong
             ? trade.Buy (lots, _Symbol, 0, slPrice, 0, "9AM Long")
             : trade.Sell(lots, _Symbol, 0, slPrice, 0, "9AM Short");

   if(trade.ResultRetcode() == TRADE_RETCODE_DONE ||
      trade.ResultRetcode() == TRADE_RETCODE_PLACED)
   {
      g_tradedToday = true;
      PrintFormat("NineAM EA: Order executed | Ticket=%llu | Lots=%.2f", trade.ResultOrder(), lots);
   }
   else
   {
      PrintFormat("NineAM EA: Order FAILED | Code=%u | %s", trade.ResultRetcode(), trade.ResultComment());
   }
}

//====================================================================
//  RSI EXIT CHECK  (called within exit window)
//====================================================================
void CheckRSIExit()
{
   double rsiBuf[];
   ArraySetAsSeries(rsiBuf, true);
   if(CopyBuffer(g_rsiHandle, 0, 0, 1, rsiBuf) < 1) return;
   double rsi = rsiBuf[0];

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))           continue;
      if(posInfo.Symbol() != _Symbol)         continue;
      if(posInfo.Magic()  != g_magic)         continue;

      bool closeLong  = (posInfo.PositionType() == POSITION_TYPE_BUY  && rsi >= InpRSILongClose);
      bool closeShort = (posInfo.PositionType() == POSITION_TYPE_SELL && rsi <= InpRSIShortClose);

      if(closeLong || closeShort)
      {
         PrintFormat("NineAM EA: RSI exit triggered | RSI=%.1f | %s",
                     rsi, closeLong ? "Long closed" : "Short closed");
         trade.PositionClose(posInfo.Ticket(), 20);
      }
   }
}

//====================================================================
//  PROFIT TARGET EXIT CHECK
//====================================================================
void CheckProfitTargetExit()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double targetProfit = balance * InpProfitTargetPct / 100.0;

   double totalProfit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))   continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic()  != g_magic) continue;

      totalProfit += posInfo.Profit();
   }

   if(totalProfit >= targetProfit - _Point)   // small tolerance
   {
      PrintFormat("NineAM EA: Profit target reached | Profit=%.2f (%.2f%% of balance) | Closing all positions",
                  totalProfit, totalProfit / balance * 100.0);
      CloseAll("Profit target hit");
   }
}

//====================================================================
//  CLOSE ALL POSITIONS (by magic + symbol)
//====================================================================
void CloseAll(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))   continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic()  != g_magic) continue;

      trade.PositionClose(posInfo.Ticket(), 20);
      PrintFormat("NineAM EA: %s | Ticket=%llu", reason, posInfo.Ticket());
   }
}

//====================================================================
//  HAS OPEN POSITION (by magic + symbol)
//====================================================================
bool HasPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!posInfo.SelectByIndex(i))   continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic()  == g_magic) return true;
   }
   return false;
}

//====================================================================
//  LOT SIZE  (risk % of balance ÷ SL distance)
//====================================================================
double CalcLots(double slDist)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt  = balance * InpRiskPct / 100.0;

   double tickSz   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickSz <= 0 || tickVal <= 0) return minLot;

   // Value of SL distance per 1 lot
   double slValuePerLot = (slDist / tickSz) * tickVal;
   if(slValuePerLot <= 0) return minLot;

   double lots = riskAmt / slValuePerLot;
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return NormalizeDouble(lots, 2);
}
