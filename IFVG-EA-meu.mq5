//+------------------------------------------------------------------+
//|                         IFVG_EA.mq5                             |
//|          Expert Advisor — Inversion Fair Value Gaps             |
//|                                                                  |
//|  Requires IFVG.mq5 compiled in MQL5/Indicators/                 |
//|                                                                  |
//|  Buffer 0 → Bull signal → FVG box BOTTOM price                   |
//|  Buffer 1 → Bear signal → FVG box TOP    price                   |
//+------------------------------------------------------------------+
#property version   "4.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "═══ IFVG Indicator Settings ═══"
input int    Inp_ShowLast    = 5;        // Show Last N IFVGs
input string Inp_SignalPref  = "Close";  // Signal Preference: "Close" or "Wick"
input double Inp_FVGATRMult  = 0.25;    // IFVG ATR Multiplier (size filter)
input int    Inp_Lookback    = 100;      // FVG Lookback (candles, 0=unlimited)

input group "═══ Stop Loss ═══"
enum SL_MODE { SL_ATR=0, SL_SWING=1, SL_FVG=2 };
input SL_MODE Inp_SLMode        = SL_ATR; // Stop Loss Method: ATR / Swing / FVG edge
input double  Inp_SLATRMult     = 2.0;    // [ATR] Multiplier
input int     Inp_SLATRPeriod   = 14;     // [ATR] Period
input int     Inp_SwingLookback = 30;     // [Swing] Bars to scan for fractal pivot

input group "═══ Take Profit ═══"
input double  Inp_TPMultiplier = 2.0;    // TP = SL distance × multiplier

input group "═══ Risk Management ═══"
input double  Inp_RiskPct  = 1.0;   // Risk per trade (% of balance)
input int     Inp_MaxBuys  = 2;     // Max simultaneous BUY positions
input int     Inp_MaxSells = 2;     // Max simultaneous SELL positions

input group "═══ Time Filter ═══"
input bool    Inp_UseTime   = true; // Enable session filter
input int     Inp_StartHour = 8;    // Session start hour (server time)
input int     Inp_StartMin  = 0;    // Session start minute
input int     Inp_EndHour   = 20;   // Session end hour
input int     Inp_EndMin    = 0;    // Session end minute

input group "═══ KAMA Trend Filter ═══"
input bool            Inp_UseKAMA       = true;       // Enable KAMA slope trend filter
input ENUM_TIMEFRAMES Inp_KAMATf        = PERIOD_H1;  // Timeframe for KAMA calculation
input int             Inp_KAMAEr        = 10;         // Efficiency Ratio period
input int             Inp_KAMAFast      = 2;          // Fast SC period (trending)
input int             Inp_KAMASlow      = 30;         // Slow SC period (ranging)
input int             Inp_KAMASlopeBars = 3;          // Bars back to measure slope (HTF bars)
input double          Inp_KAMAMinSlope  = 0.1;        // Min |slope| as multiple of HTF ATR
// ── How it works ─────────────────────────────────────────────────────────
// KAMA adapts its speed to market efficiency: fast in trends, near-flat in
// chop.  Slope is measured as:
//   slope_raw  = KAMA[1] - KAMA[1 + SlopeBars]   (positive = rising)
//   slope_norm = slope_raw / HTF_ATR[1]           (normalised, symbol-agnostic)
// A trade is allowed only when:
//   direction matches (slope_raw > 0 for BUY, < 0 for SELL)
//   AND  |slope_norm| > KAMAMinSlope              (not flat / choppy)
// ─────────────────────────────────────────────────────────────────────────

input group "═══ Daily Trade Limit ═══"
input bool    Inp_UseMaxDaily    = true;  // Enable max trades per day limit
input int     Inp_MaxTradesDay   = 4;     // Max total trades opened per calendar day

input group "═══ Trade Execution ═══"
input int     Inp_Magic    = 20240101; // Magic number
input string  Inp_Comment  = "IFVG";  // Trade comment
input int     Inp_Slippage = 10;       // Max slippage (points)

input group "═══ Debug ═══"
input bool    Inp_Debug = true;  // Print debug info to journal

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade        g_trade;
int           g_ifvg_handle    = INVALID_HANDLE;
int           g_atr_handle     = INVALID_HANDLE;
int           g_kama_handle    = INVALID_HANDLE;  // KAMA on HTF timeframe
int           g_htf_atr_handle = INVALID_HANDLE;  // ATR on HTF (slope normalisation)
datetime      g_last_bar       = 0;
datetime      g_today          = 0;
int           g_trades_today   = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Trade object setup
   g_trade.SetExpertMagicNumber(Inp_Magic);
   g_trade.SetDeviationInPoints(Inp_Slippage);
   g_trade.SetTypeFilling(ORDER_FILLING_RETURN); // most universal, works on all brokers/CFDs
   g_trade.LogLevel(LOG_LEVEL_ALL);              // log everything from CTrade

   //--- IFVG indicator handle
   //    Parameter order matches IFVG.mq5 inputs exactly:
   //    ShowLast, SignalPref, ATRMult, Lookback, BullColor, BearColor, MidColor, Debug
   g_ifvg_handle = iCustom(_Symbol, _Period, "IFVG",
                            Inp_ShowLast,
                            Inp_SignalPref,
                            Inp_FVGATRMult,
                            Inp_Lookback,
                            (color)C'8,153,129',
                            (color)C'242,54,69',
                            clrGray,
                            false);   // indicator debug off by default (set true if needed)
   if(g_ifvg_handle == INVALID_HANDLE)
     {
      PrintFormat("EA ERROR: iCustom(IFVG) failed. Err=%d  "
                  "Make sure IFVG.mq5 is compiled in MQL5/Indicators/",
                  GetLastError());
      return INIT_FAILED;
     }

   //--- ATR handle for SL calculations
   g_atr_handle = iATR(_Symbol, _Period, Inp_SLATRPeriod);
   if(g_atr_handle == INVALID_HANDLE)
     {
      PrintFormat("EA ERROR: iATR handle failed. Err=%d", GetLastError());
      return INIT_FAILED;
     }

   //--- Input validation
   if(Inp_TPMultiplier <= 0)
     { Print("EA ERROR: TPMultiplier must be > 0"); return INIT_FAILED; }
   if(Inp_RiskPct <= 0 || Inp_RiskPct > 100)
     { Print("EA ERROR: RiskPct must be 0-100"); return INIT_FAILED; }

   //--- KAMA handle (Perry Kaufman Adaptive MA — MQL5 built-in iAMA)
   //    iAMA(symbol, tf, er_period, fast_period, slow_period, shift, price)
   if(Inp_UseKAMA)
     {
      if(Inp_KAMASlopeBars < 1)
        { Print("EA ERROR: KAMASlopeBars must be >= 1"); return INIT_FAILED; }
      if(Inp_KAMAMinSlope < 0)
        { Print("EA ERROR: KAMAMinSlope must be >= 0"); return INIT_FAILED; }

      g_kama_handle = iAMA(_Symbol, Inp_KAMATf,
                           Inp_KAMAEr, Inp_KAMAFast, Inp_KAMASlow,
                           0, PRICE_CLOSE);
      if(g_kama_handle == INVALID_HANDLE)
        {
         PrintFormat("EA ERROR: KAMA handle failed. TF=%s ER=%d Fast=%d Slow=%d Err=%d",
                     EnumToString(Inp_KAMATf),
                     Inp_KAMAEr, Inp_KAMAFast, Inp_KAMASlow, GetLastError());
         return INIT_FAILED;
        }

      //--- HTF ATR for slope normalisation (same TF as KAMA)
      g_htf_atr_handle = iATR(_Symbol, Inp_KAMATf, 14);
      if(g_htf_atr_handle == INVALID_HANDLE)
        {
         PrintFormat("EA ERROR: HTF ATR handle failed. TF=%s Err=%d",
                     EnumToString(Inp_KAMATf), GetLastError());
         return INIT_FAILED;
        }
     }

   g_last_bar     = 0;
   g_today        = 0;
   g_trades_today = 0;

   PrintFormat("IFVG_EA v4 ready | %s %s | SL=%s | Risk=%.2f%% | Lookback=%d"
               " | KAMA=%s TF=%s ER=%d F=%d S=%d SlopeBars=%d MinSlope=%.2f"
               " | MaxDay=%d",
               _Symbol, EnumToString(_Period),
               SLModeStr(Inp_SLMode), Inp_RiskPct, Inp_Lookback,
               Inp_UseKAMA ? "ON" : "OFF",
               EnumToString(Inp_KAMATf),
               Inp_KAMAEr, Inp_KAMAFast, Inp_KAMASlow,
               Inp_KAMASlopeBars, Inp_KAMAMinSlope,
               Inp_UseMaxDaily ? Inp_MaxTradesDay : 0);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_ifvg_handle    != INVALID_HANDLE) IndicatorRelease(g_ifvg_handle);
   if(g_atr_handle     != INVALID_HANDLE) IndicatorRelease(g_atr_handle);
   if(g_kama_handle    != INVALID_HANDLE) IndicatorRelease(g_kama_handle);
   if(g_htf_atr_handle != INVALID_HANDLE) IndicatorRelease(g_htf_atr_handle);
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- New-bar detection via CopyTime (reliable in tester + live)
   datetime bar_time[1];
   if(CopyTime(_Symbol, _Period, 0, 1, bar_time) <= 0)
     {
      if(Inp_Debug) Print("EA: CopyTime failed, err=", GetLastError());
      return;
     }
   if(bar_time[0] == g_last_bar) return;  // same bar, nothing to do
   g_last_bar = bar_time[0];

   if(Inp_Debug)
      PrintFormat("EA: new bar %s | time=%s",
                  _Symbol, TimeToString(bar_time[0]));

   //--- Time filter
   if(!IsInTradingHours())
     {
      if(Inp_Debug) Print("EA: outside trading hours, skipping");
      return;
     }

   //--- Reset daily trade counter when the calendar day changes ------
   //    Uses server time date — consistent in both live and tester.
   MqlDateTime dt_now;
   TimeToStruct(TimeCurrent(), dt_now);
   datetime today = (datetime)StringToTime(
                      StringFormat("%04d.%02d.%02d 00:00",
                                   dt_now.year, dt_now.mon, dt_now.day));
   if(today != g_today)
     {
      if(Inp_Debug && g_today != 0)
         PrintFormat("EA: new day %s | trades yesterday=%d | counter reset",
                     TimeToString(today, TIME_DATE), g_trades_today);
      g_today        = today;
      g_trades_today = 0;
     }

   //--- Daily trade limit check -------------------------------------
   if(Inp_UseMaxDaily && g_trades_today >= Inp_MaxTradesDay)
     {
      if(Inp_Debug)
         PrintFormat("EA: daily limit reached (%d/%d), skipping",
                     g_trades_today, Inp_MaxTradesDay);
      return;
     }

   //--- Read IFVG signals from bar[1] (last closed bar, offset=1)
   //    Buffer 0 = Bull signal = FVG box bottom price
   //    Buffer 1 = Bear signal = FVG box top   price
   double bull_buf[1], bear_buf[1];
   int b0 = CopyBuffer(g_ifvg_handle, 0, 1, 1, bull_buf);
   int b1 = CopyBuffer(g_ifvg_handle, 1, 1, 1, bear_buf);

   if(b0 <= 0 || b1 <= 0)
     {
      PrintFormat("EA: CopyBuffer failed | b0=%d b1=%d err=%d — "
                  "indicator may still be warming up",
                  b0, b1, GetLastError());
      return;
     }

   double bull_sig = bull_buf[0];
   double bear_sig = bear_buf[0];

   if(Inp_Debug)
      PrintFormat("EA: bar[1] bull_sig=%s bear_sig=%s",
                  (bull_sig != EMPTY_VALUE) ? DoubleToString(bull_sig,_Digits) : "none",
                  (bear_sig != EMPTY_VALUE) ? DoubleToString(bear_sig,_Digits) : "none");

   //--- Read ATR for SL computation (bar[1])
   double atr_buf[1];
   if(CopyBuffer(g_atr_handle, 0, 1, 1, atr_buf) <= 0)
     {
      PrintFormat("EA: ATR CopyBuffer failed, err=%d", GetLastError());
      return;
     }
   double atr_val = atr_buf[0];
   if(atr_val <= 0)
     {
      if(Inp_Debug) Print("EA: ATR=0, skipping (still in warmup)");
      return;
     }

   //--- BUY signal
   if(bull_sig != EMPTY_VALUE && bull_sig > 0)
     {
      if(!KAMATrendAllow(true))
        {
         if(Inp_Debug) Print("EA: BUY signal blocked by KAMA trend filter");
        }
      else if(Inp_UseMaxDaily && g_trades_today >= Inp_MaxTradesDay)
        {
         if(Inp_Debug) PrintFormat("EA: BUY blocked — daily limit (%d)", Inp_MaxTradesDay);
        }
      else
        {
         int open_buys = CountPositions(POSITION_TYPE_BUY);
         if(open_buys < Inp_MaxBuys)
           {
            if(Inp_Debug)
               PrintFormat("EA: BUY signal at %.5f | open_buys=%d max=%d | trades_today=%d",
                           bull_sig, open_buys, Inp_MaxBuys, g_trades_today);
            if(PlaceOrder(ORDER_TYPE_BUY, bull_sig, atr_val))
               g_trades_today++;
           }
         else
            PrintFormat("EA: BUY skipped — max buys reached (%d/%d)",
                        open_buys, Inp_MaxBuys);
        }
     }

   //--- SELL signal
   if(bear_sig != EMPTY_VALUE && bear_sig > 0)
     {
      if(!KAMATrendAllow(false))
        {
         if(Inp_Debug) Print("EA: SELL signal blocked by KAMA trend filter");
        }
      else if(Inp_UseMaxDaily && g_trades_today >= Inp_MaxTradesDay)
        {
         if(Inp_Debug) PrintFormat("EA: SELL blocked — daily limit (%d)", Inp_MaxTradesDay);
        }
      else
        {
         int open_sells = CountPositions(POSITION_TYPE_SELL);
         if(open_sells < Inp_MaxSells)
           {
            if(Inp_Debug)
               PrintFormat("EA: SELL signal at %.5f | open_sells=%d max=%d | trades_today=%d",
                           bear_sig, open_sells, Inp_MaxSells, g_trades_today);
            if(PlaceOrder(ORDER_TYPE_SELL, bear_sig, atr_val))
               g_trades_today++;
           }
         else
            PrintFormat("EA: SELL skipped — max sells reached (%d/%d)",
                        open_sells, Inp_MaxSells);
        }
     }
  }

//+------------------------------------------------------------------+
//| PlaceOrder — returns true if order was accepted by broker        |
//+------------------------------------------------------------------+
bool PlaceOrder(ENUM_ORDER_TYPE type, double fvg_level, double atr_val)
  {
   bool   is_buy = (type == ORDER_TYPE_BUY);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price  = is_buy ? ask : bid;
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   //--- Compute SL
   double sl = ComputeSL(type, price, fvg_level, atr_val);
   if(sl <= 0)
     { Print("PlaceOrder: ComputeSL returned 0, aborting"); return false; }

   //--- Enforce broker minimum stop distance
   long   stops_lvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_dist  = (stops_lvl + 2) * point;  // +2 for safety margin
   if(is_buy  && price - sl < min_dist) sl = price - min_dist;
   if(!is_buy && sl - price < min_dist) sl = price + min_dist;

   double sl_dist = MathAbs(price - sl);
   if(sl_dist <= 0)
     { Print("PlaceOrder: SL distance=0 after clamp, aborting"); return false; }

   //--- TP
   double tp = is_buy ? price + sl_dist * Inp_TPMultiplier
                      : price - sl_dist * Inp_TPMultiplier;

   //--- Lot size
   double lots = ComputeLots(sl_dist);
   if(lots <= 0)
     { Print("PlaceOrder: lot size=0, aborting"); return false; }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   PrintFormat("PlaceOrder: %s | price=%.5f sl=%.5f tp=%.5f dist=%.5f lots=%.2f mode=%s",
               is_buy ? "BUY" : "SELL",
               price, sl, tp, sl_dist, lots, SLModeStr(Inp_SLMode));

   bool ok = is_buy ? g_trade.Buy(lots, _Symbol, price, sl, tp, Inp_Comment)
                    : g_trade.Sell(lots, _Symbol, price, sl, tp, Inp_Comment);

   if(ok)
      PrintFormat("PlaceOrder: order sent OK, ticket=#%I64u retcode=%u",
                  g_trade.ResultOrder(), g_trade.ResultRetcode());
   else
      PrintFormat("PlaceOrder: FAILED retcode=%u err=%d",
                  g_trade.ResultRetcode(), GetLastError());

   return ok;
  }

//+------------------------------------------------------------------+
//| ComputeSL                                                        |
//+------------------------------------------------------------------+
double ComputeSL(ENUM_ORDER_TYPE type, double price,
                 double fvg_level, double atr_val)
  {
   bool is_buy = (type == ORDER_TYPE_BUY);
   switch(Inp_SLMode)
     {
      case SL_ATR:
         return is_buy ? price - atr_val * Inp_SLATRMult
                       : price + atr_val * Inp_SLATRMult;

      case SL_SWING:
        {
         double swing = is_buy ? FindFractalLow(Inp_SwingLookback)
                               : FindFractalHigh(Inp_SwingLookback);
         if(swing > 0 && ((is_buy && swing < price) || (!is_buy && swing > price)))
            return swing;
         if(Inp_Debug)
            PrintFormat("ComputeSL SWING: no valid fractal in %d bars, using ATR fallback",
                        Inp_SwingLookback);
         return is_buy ? price - atr_val * Inp_SLATRMult
                       : price + atr_val * Inp_SLATRMult;
        }

      case SL_FVG:
         if(fvg_level > 0) return fvg_level;
         if(Inp_Debug) Print("ComputeSL FVG: fvg_level=0, using ATR fallback");
         return is_buy ? price - atr_val * Inp_SLATRMult
                       : price + atr_val * Inp_SLATRMult;
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| ComputeLots                                                      |
//|  Price-unit based sizing — correct for indices, forex, metals.  |
//+------------------------------------------------------------------+
double ComputeLots(double sl_dist)
  {
   if(sl_dist <= 0) return 0;

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_cash  = balance * Inp_RiskPct / 100.0;
   double tick_val   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tick_val <= 0 || tick_size <= 0)
     { Print("ComputeLots: invalid tick_val or tick_size"); return 0; }

   double val_per_lot = (sl_dist / tick_size) * tick_val;
   if(val_per_lot <= 0) return 0;

   double lots     = risk_cash / val_per_lot;
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / lot_step) * lot_step;
   lots = MathMax(min_lot, MathMin(max_lot, lots));

   if(Inp_Debug)
      PrintFormat("ComputeLots: balance=%.2f risk=%.2f sl_dist=%.5f val/lot=%.4f lots=%.2f",
                  balance, risk_cash, sl_dist, val_per_lot, lots);
   return lots;
  }

//+------------------------------------------------------------------+
//| CountPositions                                                   |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE dir)
  {
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)                    != _Symbol)   continue;
      if((long)PositionGetInteger(POSITION_MAGIC)              != Inp_Magic) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != dir)       continue;
      count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| IsInTradingHours                                                 |
//+------------------------------------------------------------------+
bool IsInTradingHours()
  {
   if(!Inp_UseTime) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int now   = dt.hour * 60 + dt.min;
   int start = Inp_StartHour * 60 + Inp_StartMin;
   int stop  = Inp_EndHour   * 60 + Inp_EndMin;
   if(start <= stop)
      return (now >= start && now < stop);
   else
      return (now >= start || now < stop);
  }

//+------------------------------------------------------------------+
//| FindFractalLow — most recent 3-bar pivot low                    |
//+------------------------------------------------------------------+
double FindFractalLow(int lookback)
  {
   double lo[];
   int n = CopyLow(_Symbol, _Period, 1, lookback+2, lo);
   if(n < 3) return 0;
   for(int i = 1; i < n-1; i++)
      if(lo[i] < lo[i-1] && lo[i] < lo[i+1]) return lo[i];
   return 0;
  }

//+------------------------------------------------------------------+
//| FindFractalHigh — most recent 3-bar pivot high                  |
//+------------------------------------------------------------------+
double FindFractalHigh(int lookback)
  {
   double hi[];
   int n = CopyHigh(_Symbol, _Period, 1, lookback+2, hi);
   if(n < 3) return 0;
   for(int i = 1; i < n-1; i++)
      if(hi[i] > hi[i-1] && hi[i] > hi[i+1]) return hi[i];
   return 0;
  }

//+------------------------------------------------------------------+
//| KAMATrendAllow                                                   |
//|                                                                  |
//|  Returns true if KAMA slope direction and magnitude allow the    |
//|  requested trade direction.  Always true when filter disabled.   |
//|                                                                  |
//|  Algorithm:                                                      |
//|   1. Read KAMA[1] and KAMA[1 + SlopeBars] — both fully closed   |
//|      HTF bars, so values are stable and non-repainting.          |
//|   2. slope_raw  = KAMA[1] - KAMA[1+SlopeBars]                   |
//|      Positive → KAMA is rising (adaptive uptrend)               |
//|      Negative → KAMA is falling (adaptive downtrend)            |
//|      Near-zero → KAMA is flat = chop, no trade                  |
//|   3. slope_norm = slope_raw / HTF_ATR[1]                        |
//|      Dividing by ATR makes the threshold symbol-agnostic —      |
//|      same MinSlope value works on USTEC, Gold, EURUSD, etc.     |
//|   4. Gate: direction must match AND |slope_norm| > MinSlope.    |
//|      The MinSlope gate is the key improvement over "price > EMA": |
//|      during sideways markets KAMA moves but its slope is tiny,  |
//|      so flat/choppy conditions are explicitly rejected.          |
//+------------------------------------------------------------------+
bool KAMATrendAllow(bool is_buy)
  {
   if(!Inp_UseKAMA) return true;

   //--- Need SlopeBars+2 values: [1] and [1+SlopeBars], both closed bars
   int    n_needed = Inp_KAMASlopeBars + 2;
   double kama_buf[];

   // CopyBuffer offset 1 = skip the forming bar, start from bar[1]
   if(CopyBuffer(g_kama_handle, 0, 1, n_needed, kama_buf) < n_needed)
     {
      if(Inp_Debug)
         PrintFormat("KAMATrendAllow: CopyBuffer failed (need %d) err=%d — allowing trade",
                     n_needed, GetLastError());
      return true;   // fail-open during warm-up
     }

   //--- kama_buf[0] = KAMA at bar[1]  (newest requested)
   //    kama_buf[SlopeBars] = KAMA at bar[1+SlopeBars]  (SlopeBars ago)
   double kama_now  = kama_buf[0];
   double kama_past = kama_buf[Inp_KAMASlopeBars];
   double slope_raw = kama_now - kama_past;

   //--- HTF ATR for normalisation
   double atr_buf[1];
   double htf_atr = 0;
   if(CopyBuffer(g_htf_atr_handle, 0, 1, 1, atr_buf) > 0)
      htf_atr = atr_buf[0];

   //--- Normalised slope — fall back to raw if ATR unavailable
   double slope_norm = (htf_atr > 0) ? slope_raw / htf_atr : slope_raw;

   bool dir_ok  = is_buy ? (slope_raw > 0) : (slope_raw < 0);
   bool mag_ok  = (MathAbs(slope_norm) >= Inp_KAMAMinSlope);
   bool allowed = dir_ok && mag_ok;

   if(Inp_Debug)
      PrintFormat("KAMATrendAllow: TF=%s KAMA[1]=%.5f KAMA[%d]=%.5f"
                  " | slope_raw=%.5f slope_norm=%.4f HTF_ATR=%.5f"
                  " | MinSlope=%.2f | dir=%s mag=%s | %s=%s",
                  EnumToString(Inp_KAMATf),
                  kama_now, 1+Inp_KAMASlopeBars, kama_past,
                  slope_raw, slope_norm, htf_atr,
                  Inp_KAMAMinSlope,
                  dir_ok ? "OK" : "FAIL",
                  mag_ok ? "OK" : "FAIL (flat)",
                  is_buy ? "BUY" : "SELL",
                  allowed ? "ALLOWED" : "BLOCKED");

   return allowed;
  }

//+------------------------------------------------------------------+
//| SLModeStr                                                        |
//+------------------------------------------------------------------+
string SLModeStr(SL_MODE m)
  {
   switch(m)
     {
      case SL_ATR:   return "ATR";
      case SL_SWING: return "Swing";
      case SL_FVG:   return "FVG";
     }
   return "?";
  }
//+------------------------------------------------------------------+
