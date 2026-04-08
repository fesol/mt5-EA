//+------------------------------------------------------------------+
//|                        HFT_Scalper_EA.mq5                        |
//|                  High Frequency Scalper  v4.1                    |
//|  Fixes: log threshold arg, static array, velocity in debug log   |
//+------------------------------------------------------------------+
#property copyright   "HFT Scalper v4"
#property version     "4.10"
#property description "HFT Scalper – AMA raw slope | velocity | trail | daily P&L"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//|  INPUTS                                                           |
//+------------------------------------------------------------------+
input group "========== ENTRY SETTINGS =========="
input double InpEntryMultiplier   = 3.0;    // Entry distance (x spread)
input int    InpMaxPositions      = 3;      // Max open positions per direction
input double InpStaleRetraceMult  = 8.0;   // Cancel pending if price RETRACES X*spread away
input int    InpOrderCooldownSec  = 2;     // Min seconds between placing new orders

input group "========== STOP LOSS =========="
input double InpSLMultiplier      = 5.0;   // Initial SL distance (x spread)

input group "========== TRAILING STOP =========="
input double InpTrailTrigger      = 2.0;   // Trail activation: profit >= X * spread
input double InpTrailDistance     = 1.0;   // Trail SL distance behind price (x spread)

input group "========== AMA TREND FILTER =========="
input int    InpAmaPeriod         = 8;     // AMA efficiency ratio period
input int    InpAmaFastPeriod     = 3;     // AMA fast EMA period
input int    InpAmaSlowPeriod     = 5;     // AMA slow EMA period
// Raw slope = (AMA[0]-AMA[1])/AMA[1]
// BUY  when slope >  +InpSlopeThreshold
// SELL when slope < -InpSlopeThreshold
// Pending BuyStops  cancelled when slope <= 0
// Pending SellStops cancelled when slope >= 0
input double InpSlopeThreshold    = 0.00015; // Min |slope| to open trades

input group "========== TIME FILTER =========="
input int    InpStartHour         = 8;     // Trading window start hour (server time)
input int    InpStartMinute       = 0;     // Trading window start minute
input int    InpTradeDuration     = 240;   // Trading window duration (minutes)

input group "========== VELOCITY FILTER =========="
input double InpVelocityPoints    = 50.0;  // Min price move required (points)
input int    InpVelocitySeconds   = 1;     // Velocity measurement window (seconds)

input group "========== DAILY P&L FILTER =========="
input double InpDailyProfitPct    = 3.0;   // Stop entries when daily profit >= X% of day-open equity
input double InpDailyLossPct      = 3.0;   // Stop entries when daily loss  >= X% of day-open equity

input group "========== RISK MANAGEMENT =========="
input bool   InpUsePercentRisk    = true;  // true=% balance | false=fixed lots
input double InpRiskPercent       = 0.5;   // Risk % of balance per trade
input double InpFixedLots         = 0.01;  // Fixed lot size (if fixed mode)

input group "========== GENERAL =========="
input int    InpMagic             = 88001;
input int    InpSlippage          = 10;
input bool   InpDebug             = true;

//+------------------------------------------------------------------+
//|  GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade        Trade;
CPositionInfo PosInfo;
COrderInfo    OrdInfo;

int           g_amaHandle   = INVALID_HANDLE;
double        g_amaBuf[];

// Velocity ring buffer – declared DYNAMIC to allow ArrayResize
// Stores both Ask and Bid: Ask used for buy velocity, Bid for sell velocity
struct TickRec { datetime ts; double ask; double bid; };
#define  VBUF_SIZE 2000
TickRec  g_vBuf[];          // dynamic
int      g_vHead  = 0;
int      g_vCount = 0;

// Cooldown per direction
datetime g_lastBuyOrder  = 0;
datetime g_lastSellOrder = 0;

// Session
bool     g_sessionActive = false;

// Daily P&L
double   g_dayOpenEquity  = 0.0;
datetime g_lastDayReset   = 0;
bool     g_dailyProfitHit = false;
bool     g_dailyLossHit   = false;

//+------------------------------------------------------------------+
//|  INIT                                                             |
//+------------------------------------------------------------------+
int OnInit() {
   Trade.SetExpertMagicNumber(InpMagic);
   Trade.SetDeviationInPoints(InpSlippage);
   Trade.SetTypeFilling(ORDER_FILLING_IOC);
   Trade.LogLevel(LOG_LEVEL_ERRORS);

   g_amaHandle = iAMA(_Symbol, PERIOD_CURRENT,
                      InpAmaPeriod, InpAmaFastPeriod, InpAmaSlowPeriod,
                      0, PRICE_CLOSE);
   if(g_amaHandle == INVALID_HANDLE) {
      Alert("HFT EA: Cannot create AMA handle!");
      return INIT_FAILED;
   }
   ArraySetAsSeries(g_amaBuf, true);

   if(!ChartIndicatorAdd(0, 0, g_amaHandle))
      Print("INFO | ChartIndicatorAdd failed (may already be attached)");
   else
      Print("INFO | AMA attached to chart window 0");

   // Dynamic array – no compiler warning
   ArrayResize(g_vBuf, VBUF_SIZE);
   ZeroMemory(g_vBuf);

   g_dayOpenEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_lastDayReset  = TimeCurrent();

   Print("==================================================");
   Print("HFT SCALPER v4.1 | Symbol=", _Symbol, " Magic=", InpMagic);
   Print("Risk=", InpUsePercentRisk
         ? DoubleToString(InpRiskPercent,2)+"% balance"
         : DoubleToString(InpFixedLots,4)+" lots fixed");
   Print("SL=", InpSLMultiplier, "x spread | Trail trig=", InpTrailTrigger,
         "x spread | Trail dist=", InpTrailDistance, "x spread");
   Print("Slope threshold=+-", DoubleToString(InpSlopeThreshold,8),
         " | Velocity=", InpVelocityPoints, "pts in ", InpVelocitySeconds, "s");
   Print("==================================================");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|  DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   if(g_amaHandle != INVALID_HANDLE)
      IndicatorRelease(g_amaHandle);
}

//+------------------------------------------------------------------+
//|  ONTICK                                                           |
//+------------------------------------------------------------------+
void OnTick() {

   RecordTick();
   CheckDayReset();
   ManageTrailingStops();   // always runs – even outside session
   UpdateSession();

   if(!g_sessionActive) {
      CancelAllPending();
      return;
   }

   if(!CheckDailyPnlAllowed()) {
      CancelAllPending();
      return;
   }

   //--- Market data
   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   sprPts   = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(sprPts <= 0) return;

   double spreadVal = (double)sprPts * point;
   double entryDist = spreadVal * InpEntryMultiplier;
   double slDist    = spreadVal * InpSLMultiplier;

   //--- AMA slope
   double slope = GetAMASlope();

   //--- Cancel pending orders on slope direction flip
   if(slope <= 0.0 && CountPending(ORDER_TYPE_BUY_STOP) > 0) {
      Print("SLOPE FLIP | slope=", DoubleToString(slope,8),
            " <= 0 → cancelling all pending BuyStops");
      CancelPendingByType(ORDER_TYPE_BUY_STOP);
   }
   if(slope >= 0.0 && CountPending(ORDER_TYPE_SELL_STOP) > 0) {
      Print("SLOPE FLIP | slope=", DoubleToString(slope,8),
            " >= 0 → cancelling all pending SellStops");
      CancelPendingByType(ORDER_TYPE_SELL_STOP);
   }

   //--- Clean stale pending (retrace only)
   CleanStalePending(ask, bid, spreadVal * InpStaleRetraceMult);

   //--- Counts
   int buyPos      = CountPositions(POSITION_TYPE_BUY);
   int sellPos     = CountPositions(POSITION_TYPE_SELL);
   int buyPending  = CountPending(ORDER_TYPE_BUY_STOP);
   int sellPending = CountPending(ORDER_TYPE_SELL_STOP);

   //--- Current velocity (signed points moved in last InpVelocitySeconds)
   double velPts = GetCurrentVelocityPoints();

   // FIX: InpSlopeThreshold is now correctly passed as the 5th argument
   DebugLog(StringFormat(
      "Spr=%d | Slope=%.6f thr=+-%.6f | "
      "Vel=%.1fpts thr=+-%.1fpts(%ds) | B:pos=%d pend=%d | S:pos=%d pend=%d | DayPnL=%.2f%%",
      sprPts,
      slope, InpSlopeThreshold,
      velPts, InpVelocityPoints, InpVelocitySeconds,
      buyPos, buyPending,
      sellPos, sellPending,
      CalcDailyPnlPct()));

   //================================================================
   //  BUY LOGIC
   //================================================================
   if(slope > InpSlopeThreshold) {
      if(buyPos < InpMaxPositions && buyPending == 0 && CooldownOK(true)) {
         if(CheckVelocity(true)) {
            double entryPrice = NormalizeDouble(ask + entryDist, _Digits);
            double highestBuy = GetHighestBuyPrice();
            bool   aboveLast  = (highestBuy == 0.0 || entryPrice > highestBuy + point);

            DebugLog(StringFormat("BUY gate | entry=%.5f highestBuy=%.5f aboveLast=%s",
                     entryPrice, highestBuy, (string)aboveLast));

            if(aboveLast) {
               double sl   = NormalizeDouble(entryPrice - slDist, _Digits);
               double lots = CalculateLots(slDist);
               if(lots > 0) {
                  bool ok = Trade.BuyStop(lots, entryPrice, _Symbol,
                                           sl, 0, ORDER_TIME_GTC, 0, "HFT_BUY");
                  g_lastBuyOrder = TimeCurrent();
                  Print("ORDER | BuyStop ok=", ok,
                        " entry=", DoubleToString(entryPrice, _Digits),
                        " sl=", DoubleToString(sl, _Digits),
                        " slPts=", DoubleToString(slDist/point,1),
                        " lots=", DoubleToString(lots,4),
                        " slope=", DoubleToString(slope,8),
                        " vel=", DoubleToString(velPts,1),
                        " rc=", Trade.ResultRetcode(),
                        " ", Trade.ResultRetcodeDescription());
               } else Print("WARN | BuyStop skipped – lots=0");
            } else {
               DebugLog(StringFormat("BUY skipped – retrace | entry=%.5f <= highestBuy=%.5f",
                        entryPrice, highestBuy));
            }
         } else DebugLog(StringFormat("BUY skipped – velocity | vel=%.1fpts needed=%.1fpts",
                         velPts, InpVelocityPoints));
      }
   }

   //================================================================
   //  SELL LOGIC
   //================================================================
   if(slope < -InpSlopeThreshold) {
      if(sellPos < InpMaxPositions && sellPending == 0 && CooldownOK(false)) {
         if(CheckVelocity(false)) {
            double entryPrice = NormalizeDouble(bid - entryDist, _Digits);
            double lowestSell = GetLowestSellPrice();
            bool   belowLast  = (lowestSell == 0.0 || entryPrice < lowestSell - point);

            DebugLog(StringFormat("SELL gate | entry=%.5f lowestSell=%.5f belowLast=%s",
                     entryPrice, lowestSell, (string)belowLast));

            if(belowLast) {
               double sl   = NormalizeDouble(entryPrice + slDist, _Digits);
               double lots = CalculateLots(slDist);
               if(lots > 0) {
                  bool ok = Trade.SellStop(lots, entryPrice, _Symbol,
                                            sl, 0, ORDER_TIME_GTC, 0, "HFT_SELL");
                  g_lastSellOrder = TimeCurrent();
                  Print("ORDER | SellStop ok=", ok,
                        " entry=", DoubleToString(entryPrice, _Digits),
                        " sl=", DoubleToString(sl, _Digits),
                        " slPts=", DoubleToString(slDist/point,1),
                        " lots=", DoubleToString(lots,4),
                        " slope=", DoubleToString(slope,8),
                        " vel=", DoubleToString(velPts,1),
                        " rc=", Trade.ResultRetcode(),
                        " ", Trade.ResultRetcodeDescription());
               } else Print("WARN | SellStop skipped – lots=0");
            } else {
               DebugLog(StringFormat("SELL skipped – retrace | entry=%.5f >= lowestSell=%.5f",
                        entryPrice, lowestSell));
            }
         } else DebugLog(StringFormat("SELL skipped – velocity | vel=%.1fpts needed=%.1fpts",
                         velPts, -InpVelocityPoints));
      }
   }
}

//+------------------------------------------------------------------+
//|  TRAILING STOP – tick by tick                                     |
//+------------------------------------------------------------------+
void ManageTrailingStops() {
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spreadVal = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * point;
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double trigDist  = spreadVal * InpTrailTrigger;
   double trailDist = spreadVal * InpTrailDistance;

   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol)  continue;
      if(PosInfo.Magic()  != InpMagic) continue;

      ulong  ticket = PosInfo.Ticket();
      double openPx = PosInfo.PriceOpen();
      double curSL  = PosInfo.StopLoss();

      if(PosInfo.PositionType() == POSITION_TYPE_BUY) {
         double profit = bid - openPx;
         if(profit >= trigDist) {
            double newSL = NormalizeDouble(bid - trailDist, _Digits);
            if(newSL > curSL + point) {
               bool res = Trade.PositionModify(ticket, newSL, PosInfo.TakeProfit());
               DebugLog(StringFormat("TRAIL BUY  #%I64u profit=%.5f trig=%.5f SL %.5f->%.5f ok=%s",
                        ticket, profit, trigDist, curSL, newSL, (string)res));
            }
         }
      }
      else if(PosInfo.PositionType() == POSITION_TYPE_SELL) {
         double profit = openPx - ask;
         if(profit >= trigDist) {
            double newSL = NormalizeDouble(ask + trailDist, _Digits);
            if(curSL == 0.0 || newSL < curSL - point) {
               bool res = Trade.PositionModify(ticket, newSL, PosInfo.TakeProfit());
               DebugLog(StringFormat("TRAIL SELL #%I64u profit=%.5f trig=%.5f SL %.5f->%.5f ok=%s",
                        ticket, profit, trigDist, curSL, newSL, (string)res));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//|  AMA SLOPE (price-normalised: (AMA[0]-AMA[1])/AMA[1])            |
//+------------------------------------------------------------------+
double GetAMASlope() {
   if(CopyBuffer(g_amaHandle, 0, 0, 3, g_amaBuf) < 3) {
      Print("WARN | AMA CopyBuffer < 3 values");
      return 0.0;
   }
   if(g_amaBuf[1] == 0.0) return 0.0;
   return (g_amaBuf[0] - g_amaBuf[1]) / g_amaBuf[1];
}

//+------------------------------------------------------------------+
//|  VELOCITY                                                         |
//+------------------------------------------------------------------+
void RecordTick() {
   g_vBuf[g_vHead].ts  = TimeCurrent();
   g_vBuf[g_vHead].ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   g_vBuf[g_vHead].bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_vHead = (g_vHead + 1) % VBUF_SIZE;
   if(g_vCount < VBUF_SIZE) g_vCount++;
}

// Returns true if price moved >= InpVelocityPoints in the required direction.
// BUY  velocity measured on Ask  (you need Ask to rise to get filled on a BuyStop)
// SELL velocity measured on Bid  (you need Bid to fall to get filled on a SellStop)
bool CheckVelocity(bool isBuy) {
   if(g_vCount < 2) return false;
   double curPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   datetime now   = TimeCurrent();
   double   point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = 1; i < g_vCount; i++) {
      int idx = (g_vHead - i + VBUF_SIZE) % VBUF_SIZE;
      if((now - g_vBuf[idx].ts) > InpVelocitySeconds) break;
      double pastPrice = isBuy ? g_vBuf[idx].ask : g_vBuf[idx].bid;
      double movePts   = (curPrice - pastPrice) / point;
      if(isBuy  && movePts >= InpVelocityPoints)  return true;
      if(!isBuy && movePts <= -InpVelocityPoints) return true;
   }
   return false;
}

// Returns the dominant velocity in the window (signed points).
// Up moves measured on Ask, down moves on Bid – mirrors CheckVelocity logic.
double GetCurrentVelocityPoints() {
   if(g_vCount < 2) return 0.0;
   double curAsk  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double curBid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   datetime now   = TimeCurrent();
   double   point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double maxUp   = 0.0;
   double maxDown = 0.0;

   for(int i = 1; i < g_vCount; i++) {
      int idx = (g_vHead - i + VBUF_SIZE) % VBUF_SIZE;
      if((now - g_vBuf[idx].ts) > InpVelocitySeconds) break;
      double upMove   = (curAsk - g_vBuf[idx].ask) / point;
      double downMove = (curBid - g_vBuf[idx].bid) / point;
      if(upMove   > maxUp)   maxUp   = upMove;
      if(downMove < maxDown) maxDown = downMove;
   }

   return (MathAbs(maxUp) >= MathAbs(maxDown)) ? maxUp : maxDown;
}

//+------------------------------------------------------------------+
//|  SESSION WINDOW                                                   |
//+------------------------------------------------------------------+
void UpdateSession() {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int nowMins   = dt.hour * 60 + dt.min;
   int startMins = InpStartHour  * 60 + InpStartMinute;
   int endMins   = startMins + InpTradeDuration;
   bool was      = g_sessionActive;
   g_sessionActive = (nowMins >= startMins && nowMins < endMins);
   if(was != g_sessionActive)
      Print("SESSION | ", g_sessionActive ? "OPENED" : "CLOSED",
            " | ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
}

//+------------------------------------------------------------------+
//|  DAILY P&L                                                        |
//+------------------------------------------------------------------+
void CheckDayReset() {
   MqlDateTime now, last;
   TimeToStruct(TimeCurrent(),  now);
   TimeToStruct(g_lastDayReset, last);
   if(now.day != last.day || now.mon != last.mon || now.year != last.year) {
      g_dayOpenEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
      g_lastDayReset   = TimeCurrent();
      g_dailyProfitHit = false;
      g_dailyLossHit   = false;
      Print("DAY RESET | DayOpenEquity=", DoubleToString(g_dayOpenEquity,2),
            " | ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
   }
}

double CalcDailyPnlPct() {
   if(g_dayOpenEquity <= 0) return 0.0;
   return ((AccountInfoDouble(ACCOUNT_EQUITY) - g_dayOpenEquity) / g_dayOpenEquity) * 100.0;
}

bool CheckDailyPnlAllowed() {
   if(g_dayOpenEquity <= 0) return true;
   double pnl = CalcDailyPnlPct();

   if(pnl >= InpDailyProfitPct) {
      if(!g_dailyProfitHit) {
         g_dailyProfitHit = true;
         Print("DAILY FILTER | Profit cap hit | PnL=", DoubleToString(pnl,2),
               "% >= +", InpDailyProfitPct, "% | No new entries today");
      }
      return false;
   }
   if(pnl <= -InpDailyLossPct) {
      if(!g_dailyLossHit) {
         g_dailyLossHit = true;
         Print("DAILY FILTER | Loss limit hit | PnL=", DoubleToString(pnl,2),
               "% <= -", InpDailyLossPct, "% | No new entries today");
      }
      return false;
   }
   g_dailyProfitHit = false;
   g_dailyLossHit   = false;
   return true;
}

//+------------------------------------------------------------------+
//|  ORDER UTILITIES                                                  |
//+------------------------------------------------------------------+
void CancelAllPending() {
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(!OrdInfo.SelectByIndex(i)) continue;
      if(OrdInfo.Symbol() != _Symbol)  continue;
      if(OrdInfo.Magic()  != InpMagic) continue;
      Trade.OrderDelete(OrdInfo.Ticket());
   }
}

void CancelPendingByType(ENUM_ORDER_TYPE type) {
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(!OrdInfo.SelectByIndex(i)) continue;
      if(OrdInfo.Symbol()    != _Symbol)  continue;
      if(OrdInfo.Magic()     != InpMagic) continue;
      if(OrdInfo.OrderType() != type)     continue;
      bool res = Trade.OrderDelete(OrdInfo.Ticket());
      Print("CANCEL | #", OrdInfo.Ticket(), " type=", EnumToString(type),
            " px=", DoubleToString(OrdInfo.PriceOpen(),_Digits), " ok=", (string)res);
   }
}

void CleanStalePending(double ask, double bid, double maxRetraceDist) {
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(!OrdInfo.SelectByIndex(i)) continue;
      if(OrdInfo.Symbol() != _Symbol)  continue;
      if(OrdInfo.Magic()  != InpMagic) continue;

      double px = OrdInfo.PriceOpen();
      ENUM_ORDER_TYPE ot = OrdInfo.OrderType();
      bool stale = false;

      if(ot == ORDER_TYPE_BUY_STOP) {
         // Cancel only if price has FALLEN far below the order (retrace away from it)
         if(px > ask && (px - ask) > maxRetraceDist) stale = true;
      }
      else if(ot == ORDER_TYPE_SELL_STOP) {
         // Cancel only if price has RISEN far above the order
         if(px < bid && (bid - px) > maxRetraceDist) stale = true;
      }

      if(stale) {
         bool res = Trade.OrderDelete(OrdInfo.Ticket());
         Print("STALE | Cancelled #", OrdInfo.Ticket(),
               " type=", EnumToString(ot),
               " orderPx=", DoubleToString(px,_Digits),
               " ask=", DoubleToString(ask,_Digits),
               " bid=", DoubleToString(bid,_Digits),
               " retraceDist=", DoubleToString(
                  ot==ORDER_TYPE_BUY_STOP ? px-ask : bid-px, _Digits),
               " ok=", (string)res);
      }
   }
}

int CountPositions(ENUM_POSITION_TYPE type) {
   int n = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol)  continue;
      if(PosInfo.Magic()  != InpMagic) continue;
      if(PosInfo.PositionType() == type) n++;
   }
   return n;
}

int CountPending(ENUM_ORDER_TYPE type) {
   int n = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(!OrdInfo.SelectByIndex(i)) continue;
      if(OrdInfo.Symbol() != _Symbol)  continue;
      if(OrdInfo.Magic()  != InpMagic) continue;
      if(OrdInfo.OrderType() == type) n++;
   }
   return n;
}

bool CooldownOK(bool isBuy) {
   datetime last = isBuy ? g_lastBuyOrder : g_lastSellOrder;
   return (TimeCurrent() - last) >= (datetime)InpOrderCooldownSec;
}

//+------------------------------------------------------------------+
//|  DIRECTIONAL PRICE GUARDS                                        |
//+------------------------------------------------------------------+
double GetHighestBuyPrice() {
   double highest = 0.0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol)  continue;
      if(PosInfo.Magic()  != InpMagic) continue;
      if(PosInfo.PositionType() != POSITION_TYPE_BUY) continue;
      if(PosInfo.PriceOpen() > highest) highest = PosInfo.PriceOpen();
   }
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(!OrdInfo.SelectByIndex(i)) continue;
      if(OrdInfo.Symbol() != _Symbol)  continue;
      if(OrdInfo.Magic()  != InpMagic) continue;
      if(OrdInfo.OrderType() != ORDER_TYPE_BUY_STOP) continue;
      if(OrdInfo.PriceOpen() > highest) highest = OrdInfo.PriceOpen();
   }
   return highest;
}

double GetLowestSellPrice() {
   double lowest = 0.0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol)  continue;
      if(PosInfo.Magic()  != InpMagic) continue;
      if(PosInfo.PositionType() != POSITION_TYPE_SELL) continue;
      if(lowest == 0.0 || PosInfo.PriceOpen() < lowest) lowest = PosInfo.PriceOpen();
   }
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(!OrdInfo.SelectByIndex(i)) continue;
      if(OrdInfo.Symbol() != _Symbol)  continue;
      if(OrdInfo.Magic()  != InpMagic) continue;
      if(OrdInfo.OrderType() != ORDER_TYPE_SELL_STOP) continue;
      if(lowest == 0.0 || OrdInfo.PriceOpen() < lowest) lowest = OrdInfo.PriceOpen();
   }
   return lowest;
}

//+------------------------------------------------------------------+
//|  LOT CALCULATION                                                  |
//+------------------------------------------------------------------+
double CalculateLots(double slDist) {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0) lotStep = minLot;

   if(!InpUsePercentRisk) {
      double lots = NormalizeLots(InpFixedLots, minLot, maxLot, lotStep);
      DebugLog("LOT | Fixed=" + DoubleToString(lots,4));
      return lots;
   }

   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt  = balance * InpRiskPercent / 100.0;
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickVal <= 0 || tickSize <= 0 || point <= 0 || slDist <= 0) {
      Print("WARN | LOT fallback minLot – invalid inputs tkVal=", tickVal,
            " tkSz=", tickSize, " pt=", point, " slDist=", slDist);
      return minLot;
   }

   double pointValue    = tickVal * (point / tickSize);
   double slPoints      = slDist / point;
   double slMoneyPerLot = slPoints * pointValue;

   double lots = riskAmt / slMoneyPerLot;
   double norm = NormalizeLots(lots, minLot, maxLot, lotStep);

   Print("LOT | Bal=", DoubleToString(balance,2),
         " Risk$=", DoubleToString(riskAmt,2),
         " slDist=", DoubleToString(slDist,_Digits),
         " slPts=", DoubleToString(slPoints,1),
         " ptVal=", DoubleToString(pointValue,6),
         " slMoney/lot=", DoubleToString(slMoneyPerLot,4),
         " raw=", DoubleToString(lots,4),
         " final=", DoubleToString(norm,4));

   return norm;
}

double NormalizeLots(double lots, double minLot, double maxLot, double lotStep) {
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(lots, 4);
}

//+------------------------------------------------------------------+
//|  DEBUG LOG                                                        |
//+------------------------------------------------------------------+
void DebugLog(string msg) {
   if(InpDebug) Print("DEBUG | ", msg);
}

//+------------------------------------------------------------------+
//| END OF EA                                                         |
//+------------------------------------------------------------------+